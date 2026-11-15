#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <phonon.h>
#include <array>
#include <atomic>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>
#include <xmmintrin.h>

// Scene geometry stays in Godot. This component owns the audio sample clock.
// All decoding, allocation and HRTF-effect creation happen on the control thread.
// The mixer only tries the control mutex; a late update retains the last state.
namespace atmo {
using namespace godot;
struct DenormalGuard {
 unsigned previous=_mm_getcsr();
 DenormalGuard(){_mm_setcsr(previous|0x8040);}
 ~DenormalGuard(){_mm_setcsr(previous);}
};
constexpr int BLOCK=256, EMITTERS=128, INPUT_PATHS=18, PATHS=36, ROOMS=32, RING=65536;
constexpr float PI=3.14159265358979323846f;
static float bound(float x,float a,float b){return std::max(a,std::min(b,x));}
static float gain(float db){return std::pow(10.0f,db*.05f);}
struct V3 {
 float x=0,y=0,z=-1;
 V3 operator-(V3 b)const{return{x-b.x,y-b.y,z-b.z};}
 V3 operator+(V3 b)const{return{x+b.x,y+b.y,z+b.z};}
 V3 operator*(float s)const{return{x*s,y*s,z*s};}
 float dot(V3 b)const{return x*b.x+y*b.y+z*b.z;}
 V3 normalized()const{float n=std::sqrt(dot(*this));return n>.0001f?(*this)*(1/n):V3{0,0,-1};}
};
static V3 vector(const Variant &v){
 if(v.get_type()==Variant::VECTOR3){Vector3 p=v;return{p.x,p.y,p.z};}
 Array a=v;return a.size()>=3?V3{float(double(a[0])),float(double(a[1])),float(double(a[2]))}:V3{};
}
static float number(const Dictionary &d,const char *key,float fallback){return float(double(d.get(key,fallback)));}
static uint64_t identity(const String &s){uint64_t h=1469598103934665603ULL;auto bytes=s.utf8();for(int i=0;i<bytes.length();i++){h^=uint8_t(bytes[i]);h*=1099511628211ULL;}return std::max(uint64_t(2),h);}
struct Coeff {float b0=1,b1=0,b2=0,a1=0,a2=0;};
struct Biquad {
 float z1=0,z2=0;
 float run(float x,const Coeff &c){float y=c.b0*x+z1;z1=c.b1*x-c.a1*y+z2;z2=c.b2*x-c.a2*y;return y;}
};
static Coeff lowpass(float hz,float rate){
 float w=2*PI*bound(hz,40,rate*.45f)/rate,c=std::cos(w),s=std::sin(w),a=s; // Q=.5
 float d=1/(1+a);return{(1-c)*.5f*d,(1-c)*d,(1-c)*.5f*d,-2*c*d,(1-a)*d};
}
static Coeff peak(float hz,float db,float rate){
 float w=2*PI*hz/rate,c=std::cos(w),a=std::sin(w)/(2*.6f),A=std::pow(10.0f,db/40),d=1/(1+a/A);
 return{(1+a*A)*d,-2*c*d,(1-a*A)*d,-2*c*d,(1-a/A)*d};
}
static float air_loss(float f){
 float h=.5f*std::pow(10.0f,-6.8346f*std::pow(273.16f/293.15f,1.261f)+4.6151f);
 float o=24+40400*h*(.02f+h)/(.391f+h),n=9+280*h;
 return 8.686f*f*f*(1.84e-11f+.01275f*std::exp(-2239.1f/293.15f)/(o+f*f/o)+.1068f*std::exp(-3352.0f/293.15f)/(n+f*f/n));
}
// Four-point interpolation is used both for source variation and propagation.
static float cubic(float a,float b,float c,float d,float t){return b+.5f*t*(c-a+t*(2*a-5*b+4*c-d+t*(3*(b-c)+d-a)));}
struct PCM {std::vector<float> data;};
struct PathTarget {uint64_t id=0;V3 position;float distance=0,cutoff=20000,volume=0;};
struct Control {
 std::shared_ptr<PCM> pcm;
 std::array<PathTarget,INPUT_PATHS> paths{};
 int count=0,field=0;float pitch=1,send=0,offset=0;bool loop=false,playing=false,silent=false,disposed=false,foot=false,doppler=true;uint64_t serial=0;
};
struct Scene {V3 position{0,0,0},forward{0,0,-1};float ambience=.8f,footsteps=.75f;bool paused=true,headphones=true;};
struct Path {
 IPLBinauralEffect hrtf=nullptr;
 uint64_t id=0;float level=0,delay=0,delay_step=0;int delay_left=0;V3 direction{0,0,-1};
 float distance=0,cutoff=20000;std::array<Biquad,4> filters{};
 std::array<float,BLOCK> mono{},left{},right{};
 ~Path(){if(hrtf)iplBinauralEffectRelease(&hrtf);}
};
struct Emitter {
 Control control,render;
 std::array<Path,PATHS> paths;
 std::vector<float> history=std::vector<float>(RING,0);
 std::array<float,BLOCK> signal{};
 uint64_t serial=0;int write=0,quiet=0;double position=0,old_position=0;float pitch=1,envelope=0,old_envelope=0;
 std::shared_ptr<PCM> pcm,old_pcm;bool playing=false;int old_left=0;
 std::atomic<bool> finished{false};
};
struct FieldControl {float local=0,remote=0,wet=0;V3 at,decay{.2f,.2f,.2f};};
struct Portal {int room=0;String id;V3 at;float width=1,open=1;};
struct Field {
 String id;float x=0,z=0,w=0,h=0;bool region=false;
 std::array<std::vector<float>,16> lines;
 std::array<int,16> indices{};
 std::array<float,16> lo{},hi{},v{},feedback{};
 std::array<std::array<float,3>,16> decay{},target_decay{};
 std::array<float,BLOCK> input{},left{},right{},mono{},remote_l{},remote_r{};
 float wet=0,target_wet=0,local=0,remote=0;FieldControl control,render;
 IPLBinauralEffect hrtf=nullptr;Biquad remote_filter;
 ~Field(){if(hrtf)iplBinauralEffectRelease(&hrtf);}
 void set_decay(V3 rt,float rate){
  for(int i=0;i<16;i++)for(int k=0;k<3;k++){float t=k==0?rt.x:(k==1?rt.y:rt.z);target_decay[i][k]=std::pow(10.0f,-3*float(lines[i].size())/rate/bound(t,.08f,8));}
 }
 void process(float rate){
  float a=1-std::exp(-2*PI*400/rate),b=1-std::exp(-2*PI*3500/rate);
  for(int s=0;s<BLOCK;s++){
   for(int i=0;i<16;i++){
    float x=lines[i][indices[i]];lo[i]+=a*(x-lo[i]);hi[i]+=b*(x-hi[i]);
    for(int k=0;k<3;k++)decay[i][k]+=.0002f*(target_decay[i][k]-decay[i][k]);
    v[i]=lo[i]*decay[i][0]+(hi[i]-lo[i])*decay[i][1]+(x-hi[i])*decay[i][2];feedback[i]=v[i];
   }
   for(int step=1;step<16;step*=2)for(int i=0;i<16;i+=step*2)for(int j=0;j<step;j++){float x=feedback[i+j],y=feedback[i+j+step];feedback[i+j]=x+y;feedback[i+j+step]=x-y;}
   for(int i=0;i<16;i++){lines[i][indices[i]]=input[s]*(i%2?-.25f:.25f)+feedback[i]*.25f;indices[i]=(indices[i]+1)%int(lines[i].size());}
   wet+=.0005f*(target_wet-wet);float l=0,r=0;
   for(int i=0;i<8;i++){l+=v[i*2]*(i%3==0?-1.0f:1.0f);r+=v[i*2+1]*(i%3==1?-1.0f:1.0f);}
   left[s]=l*.35355339f*wet;right[s]=r*.35355339f*wet;
  }
 }
};
struct Bank {std::array<std::shared_ptr<Field>,ROOMS> fields{};std::vector<Portal> portals;int count=0;};

class Core {
public:
 float rate=48000;IPLContext context=nullptr;IPLHRTF hrtf=nullptr;bool ready=false;
 std::string error;
 std::mutex mutex;
 std::array<std::shared_ptr<Emitter>,EMITTERS> emitters{},audio_emitters{};
 std::vector<std::shared_ptr<Emitter>> retired;
 std::unordered_map<std::string,int> ids;
 std::unordered_map<std::string,std::shared_ptr<PCM>> clips;
 std::shared_ptr<Bank> bank,audio_bank;std::vector<std::shared_ptr<Bank>> retired_banks;
 Scene scene,audio_scene;
 std::array<AudioFrame,BLOCK> output{};int output_at=BLOCK;
 std::array<float,BLOCK> blend{};
 float output_gate=0,headphone_blend=1;std::atomic<uint64_t> frames{0};std::atomic<int> playbacks{0};
 std::atomic<uint64_t> blocks{0},deadline_misses{0},max_us{0},total_us{0},path_overflows{0};
 std::atomic<int> active_paths{0};
 ~Core(){audio_emitters={};emitters={};retired.clear();audio_bank.reset();bank.reset();retired_banks.clear();if(hrtf)iplHRTFRelease(&hrtf);if(context)iplContextRelease(&context);}
 bool initialize(float hz){
  if(ready)return true;rate=hz;
  IPLContextSettings c{};c.version=STEAMAUDIO_VERSION;
  if(iplContextCreate(&c,&context)!=IPL_STATUS_SUCCESS){error="Steam Audio context creation failed";return false;}
  IPLAudioSettings a{};a.samplingRate=int(rate);a.frameSize=BLOCK;
  IPLHRTFSettings h{};h.type=IPL_HRTFTYPE_DEFAULT;h.volume=1;
  if(iplHRTFCreate(context,&a,&h,&hrtf)!=IPL_STATUS_SUCCESS){error="Steam Audio HRTF creation failed";return false;}
  ready=true;return true;
 }
 bool effect(IPLBinauralEffect &out){
  IPLAudioSettings a{int(rate),BLOCK};IPLBinauralEffectSettings s{};s.hrtf=hrtf;
  if(iplBinauralEffectCreate(context,&a,&s,&out)!=IPL_STATUS_SUCCESS){error="Steam Audio binaural effect creation failed";return false;}return true;
 }
 void collect(){
  for(int i=0;i<EMITTERS;i++)if(emitters[i]&&emitters[i]->control.disposed&&emitters[i]->finished.load()){
   retired.push_back(std::move(emitters[i]));
  }
  retired.erase(std::remove_if(retired.begin(),retired.end(),[](auto &p){return p.use_count()==1;}),retired.end());
  retired_banks.erase(std::remove_if(retired_banks.begin(),retired_banks.end(),[](auto &p){return p.use_count()==1;}),retired_banks.end());
 }
 std::shared_ptr<Field> field(){
  auto f=std::make_shared<Field>();constexpr int lengths[16]={1493,1601,1747,1867,1999,2137,2281,2411,2557,2687,2801,2953,3163,3319,3469,3623};
  for(int i=0;i<16;i++)f->lines[i].resize(std::max(1,int(std::round(lengths[i]*rate/48000))),0);
  effect(f->hrtf);return f;
 }
 int region(V3 p)const{
  if(bank)for(int i=1;i<bank->count;i++){const auto &f=*bank->fields[i];if(p.x>=f.x&&p.x<=f.x+f.w&&p.z>=f.z&&p.z<=f.z+f.h)return i;}return 0;
 }
 V3 relative(V3 at)const{
  V3 d=(at-audio_scene.position).normalized(),f=audio_scene.forward.normalized(),r{-f.z,0,f.x};
  return V3{d.dot(r),d.y,-d.dot(f)}.normalized();
 }
 void spatialize(IPLBinauralEffect effect_,float *input,float *l,float *r,V3 direction){
  float *in[1]={input},*out[2]={l,r};IPLAudioBuffer ib{1,BLOCK,in},ob{2,BLOCK,out};
  IPLBinauralEffectParams p{};p.direction={direction.x,direction.y,direction.z};p.interpolation=IPL_HRTFINTERPOLATION_BILINEAR;p.spatialBlend=1;p.hrtf=hrtf;
  iplBinauralEffectApply(effect_,&p,&ib,&ob);
 }
 static float read_pcm(const PCM &pcm,double pos,bool loop){
  int n=int(pcm.data.size());if(n<4)return 0;
  if(!loop&&(pos<0||pos>=n))return 0;
  int i=int(std::floor(pos));float f=float(pos-i);
  auto read=[&](int x){if(loop){x%=n;if(x<0)x+=n;return pcm.data[x];}return x>=0&&x<n?pcm.data[x]:0.0f;};
  return cubic(read(i-1),read(i),read(i+1),read(i+2),f);
 }
 void block(){
  auto began=std::chrono::steady_clock::now();
  if(mutex.try_lock()){
   audio_scene=scene;audio_bank=bank;
   for(int i=0;i<EMITTERS;i++){audio_emitters[i]=emitters[i];if(audio_emitters[i])audio_emitters[i]->render=audio_emitters[i]->control;}
   if(audio_bank)for(int i=0;i<audio_bank->count;i++){auto &f=*audio_bank->fields[i];f.render=f.control;if(i==0){f.set_decay(f.render.decay,rate);f.target_wet=f.render.wet;}}
   mutex.unlock();
  }
  for(auto &s:output)s={0,0};
  for(int n=0;n<BLOCK;n++){headphone_blend+=bound((audio_scene.headphones?1.0f:0.0f)-headphone_blend,-1/(rate*.04f),1/(rate*.04f));blend[n]=headphone_blend;}
  if(audio_bank)for(int i=0;i<audio_bank->count;i++)audio_bank->fields[i]->input.fill(0);
  int active=0;
  for(auto &owner:audio_emitters){
   if(!owner)continue;auto &e=*owner;auto &c=e.render;
   if(c.serial!=e.serial){
    if(e.playing&&e.pcm&&e.envelope>.00001f){e.old_pcm=e.pcm;e.old_position=e.position;e.old_envelope=e.envelope;e.old_left=int(rate*.008f);}
    e.serial=c.serial;e.pcm=c.pcm;e.position=c.offset*rate;e.envelope=0;e.playing=c.playing;e.pitch=c.pitch;
   }
   if(!c.playing)e.playing=false;
   float category=c.foot?audio_scene.footsteps:audio_scene.ambience;
   float envelope_target=e.playing&&!c.silent&&!c.disposed?1.0f:0.0f;
   float env_step=1/(rate*.008f);
   for(int n=0;n<BLOCK;n++){
    e.envelope+=bound(envelope_target-e.envelope,-env_step,env_step);
    float x=0;
    if(e.pcm&&(e.playing||e.envelope>0)){
     e.pitch+=.002f*(c.pitch-e.pitch);x=read_pcm(*e.pcm,e.position,c.loop)*e.envelope;
     if(e.envelope>0||!c.silent)e.position+=e.pitch;
     if(c.loop&&!e.pcm->data.empty()&&e.position>=e.pcm->data.size())e.position=std::fmod(e.position,double(e.pcm->data.size()));
     if(!c.loop&&e.position>=e.pcm->data.size()){e.playing=false;envelope_target=0;}
    }
    if(e.old_left>0&&e.old_pcm){x+=read_pcm(*e.old_pcm,e.old_position,c.loop)*e.old_envelope*float(e.old_left)/std::max(1,int(rate*.008f));e.old_position+=e.pitch;e.old_left--;}
    e.quiet=std::abs(x)<1e-8f?std::min(RING*2,e.quiet+1):0;
    e.signal[n]=x;int at=(e.write+n)&(RING-1);e.history[at]=x;
    if(audio_bank&&c.field<audio_bank->count)audio_bank->fields[std::max(0,c.field)]->input[n]+=x*c.send*category;
   }
   if(e.quiet>int(rate*.85f)&&e.envelope<.000001f){e.write=(e.write+BLOCK)&(RING-1);e.finished.store(c.disposed);continue;}
   std::array<int,PATHS> target_index{};target_index.fill(-1);
   if(!c.disposed)for(int t=0;t<c.count;t++){
    int found=-1;for(int p=0;p<PATHS;p++)if(e.paths[p].id==c.paths[t].id){found=p;break;}
    if(found<0)for(int p=0;p<PATHS;p++)if(e.paths[p].level<.000001f&&target_index[p]<0){found=p;auto &s=e.paths[p];s.id=c.paths[t].id;s.delay=bound((c.doppler?c.paths[t].distance:(t==0?0:std::max(0.0f,c.paths[t].distance-c.paths[0].distance)))/343*rate,0,rate*.8f);s.delay_left=0;s.direction=relative(c.paths[t].position);s.filters={};iplBinauralEffectReset(s.hrtf);break;}
    if(found>=0)target_index[found]=t;else path_overflows.fetch_add(1);
   }
   bool finished=c.disposed&&e.envelope<.000001f;
   for(int p=0;p<PATHS;p++){
    auto &s=e.paths[p];int t=target_index[p];float target_level=0;
    if(t>=0){
     const auto &dest=c.paths[t];target_level=dest.volume*category;
     float delay=bound(dest.distance/343*rate,0,rate*.8f);
     // New geometry updates create a continuous linear delay ramp. Its slope
     // supplies Doppler, so source playback receives take variation only.
     float remaining=s.delay+s.delay_step*s.delay_left;
     if(c.doppler&&std::abs(delay-remaining)>.005f){s.delay_left=std::max(1,int(rate*(s.id==1?1.0f/60:.08f)));s.delay_step=(delay-s.delay)/s.delay_left;}
     if(!c.doppler)s.delay_left=0; // Stable ambient taps; spatial gain/filter/direction still update.
     s.direction=(s.direction*.8f+relative(dest.position)*.2f).normalized();s.distance+=.2f*(dest.distance-s.distance);s.cutoff+=.2f*(dest.cutoff-s.cutoff);
    }
    if(s.level<.000001f&&target_level<.000001f)continue;
    finished=false;active++;
    float level_step=(target_level-s.level)/std::max(1.0f,rate*.04f);
    std::array<Coeff,4> coeffs={peak(500,-air_loss(500)*s.distance,rate),peak(2000,-air_loss(2000)*s.distance,rate),peak(8000,-air_loss(8000)*s.distance,rate),lowpass(s.cutoff,rate)};
    for(int n=0;n<BLOCK;n++){
     if(s.delay_left>0){s.delay+=s.delay_step;s.delay_left--;}
     float read=float(e.write+n)-s.delay;int i=int(std::floor(read));float f=read-i;
     float x=cubic(e.history[(i-1)&(RING-1)],e.history[i&(RING-1)],e.history[(i+1)&(RING-1)],e.history[(i+2)&(RING-1)],f);
     for(int k=0;k<4;k++)x=s.filters[k].run(x,coeffs[k]);
     s.level+=level_step;if((level_step>0&&s.level>target_level)||(level_step<0&&s.level<target_level))s.level=target_level;
     s.mono[n]=x*s.level;
    }
    spatialize(s.hrtf,s.mono.data(),s.left.data(),s.right.data(),s.direction);
    float pan=bound(s.direction.x,-1,1),l=std::sqrt((1-pan)*.5f),r=std::sqrt((1+pan)*.5f);
    for(int n=0;n<BLOCK;n++){output[n].left+=s.left[n]*blend[n]+s.mono[n]*l*(1-blend[n]);output[n].right+=s.right[n]*blend[n]+s.mono[n]*r*(1-blend[n]);}
   }
   e.write=(e.write+BLOCK)&(RING-1);e.finished.store(finished);
  }
  if(audio_bank)for(int i=0;i<audio_bank->count;i++){
   auto &f=*audio_bank->fields[i];f.process(rate);
   auto direction=relative(f.render.at);Coeff lp=lowpass(3500,rate);
   for(int n=0;n<BLOCK;n++)f.mono[n]=f.remote_filter.run((f.left[n]+f.right[n])*.5f,lp);
   spatialize(f.hrtf,f.mono.data(),f.remote_l.data(),f.remote_r.data(),direction);
   float pan=bound(direction.x,-1,1),l=std::sqrt((1-pan)*.5f),r=std::sqrt((1+pan)*.5f);
   float dl=(f.render.local-f.local)/std::max(1.0f,rate*.12f),dr=(f.render.remote-f.remote)/std::max(1.0f,rate*.12f);
   for(int n=0;n<BLOCK;n++){f.local+=dl;f.remote+=dr;output[n].left+=f.left[n]*f.local+f.remote*(f.remote_l[n]*blend[n]+f.mono[n]*l*(1-blend[n]));output[n].right+=f.right[n]*f.local+f.remote*(f.remote_r[n]*blend[n]+f.mono[n]*r*(1-blend[n]));}
  }
  float desired=audio_scene.paused?0.0f:1.0f;
  for(int n=0;n<BLOCK;n++){output_gate+=bound(desired-output_gate,-1/(rate*.02f),1/(rate*.02f));output[n].left*=output_gate;output[n].right*=output_gate;}
  active_paths.store(active);frames+=BLOCK;blocks.fetch_add(1);
  uint64_t micros=uint64_t(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-began).count());
  total_us.fetch_add(micros);uint64_t old=max_us.load();while(old<micros&&!max_us.compare_exchange_weak(old,micros)){}
  if(micros>uint64_t(BLOCK*1000000/rate))deadline_misses.fetch_add(1);
 }
 void mix(AudioFrame *dst,int count){
  DenormalGuard denormals;
  if(!ready){for(int i=0;i<count;i++)dst[i]={0,0};return;}
  for(int n=0;n<count;){if(output_at==BLOCK){block();output_at=0;}int size=std::min(count-n,BLOCK-output_at);std::copy_n(output.data()+output_at,size,dst+n);output_at+=size;n+=size;}
 }
};

class AtmoSpatialPlayback:public AudioStreamPlayback {
 GDCLASS(AtmoSpatialPlayback,AudioStreamPlayback)
protected:static void _bind_methods(){}
public:
 std::shared_ptr<Core> core;std::atomic<bool> active{false};
 void _start(double)override{if(!active.exchange(true)&&core)core->playbacks.fetch_add(1);}
 void _stop()override{if(active.exchange(false)&&core)core->playbacks.fetch_sub(1);}
 bool _is_playing()const override{return active.load();}
 double _get_playback_position()const override{return core?double(core->frames.load())/core->rate:0;}
 int32_t _mix(AudioFrame *buffer,float,int32_t count)override{if(core&&active.load())core->mix(buffer,count);else for(int i=0;i<count;i++)buffer[i]={0,0};return count;}
};
class AtmoSpatialStream:public AudioStream {
 GDCLASS(AtmoSpatialStream,AudioStream)
 std::shared_ptr<Core> core=std::make_shared<Core>();
 static std::string key(const String &s){return std::string(s.utf8().get_data());}
 Emitter *lookup(const String &id){auto it=core->ids.find(key(id));return it!=core->ids.end()&&core->emitters[it->second]?core->emitters[it->second].get():nullptr;}
protected:
 static void _bind_methods(){
  ClassDB::bind_method(D_METHOD("initialize","sample_rate"),&AtmoSpatialStream::initialize);
  ClassDB::bind_method(D_METHOD("configure","id","stream","loop","category"),&AtmoSpatialStream::configure);
  ClassDB::bind_method(D_METHOD("configure_pcm","id","samples","loop","category"),&AtmoSpatialStream::configure_pcm);
  ClassDB::bind_method(D_METHOD("play","id","offset"),&AtmoSpatialStream::play);
  ClassDB::bind_method(D_METHOD("stop","id"),&AtmoSpatialStream::stop);
  ClassDB::bind_method(D_METHOD("suspend","id","silent"),&AtmoSpatialStream::suspend);
  ClassDB::bind_method(D_METHOD("dispose","id"),&AtmoSpatialStream::dispose);
  ClassDB::bind_method(D_METHOD("update","id","data"),&AtmoSpatialStream::update);
  ClassDB::bind_method(D_METHOD("scene","data"),&AtmoSpatialStream::scene);
  ClassDB::bind_method(D_METHOD("layout","data"),&AtmoSpatialStream::layout);
  ClassDB::bind_method(D_METHOD("clear"),&AtmoSpatialStream::clear);
  ClassDB::bind_method(D_METHOD("snapshot"),&AtmoSpatialStream::snapshot);
  ClassDB::bind_method(D_METHOD("render_frames","frames"),&AtmoSpatialStream::render_frames);
 }
public:
 Ref<AudioStreamPlayback> _instantiate_playback()const override{Ref<AtmoSpatialPlayback> p;p.instantiate();p->core=core;return p;}
 String _get_stream_name()const override{return "Atmosphear native HRTF";}
 double _get_length()const override{return 0;}
 bool _is_monophonic()const override{return false;}
 bool initialize(int hz){return core->initialize(float(hz));}
 void install(const String &id,std::shared_ptr<PCM> pcm,bool loop,const String &category){
  if(!core->ready&&!initialize(int(AudioServer::get_singleton()->get_mix_rate())))return;
  std::shared_ptr<Emitter> created;
  {std::lock_guard<std::mutex> guard(core->mutex);core->collect();if(!lookup(id))created=std::make_shared<Emitter>();}
  if(created)for(auto &p:created->paths)if(!core->effect(p.hrtf))return;
  std::lock_guard<std::mutex> guard(core->mutex);auto *e=lookup(id);
  if(!e){int slot=-1;for(int i=0;i<EMITTERS;i++)if(!core->emitters[i]){slot=i;break;}if(slot<0){core->error="Native emitter capacity exceeded";return;}core->emitters[slot]=created;core->ids[key(id)]=slot;e=created.get();}
  e->control.pcm=pcm;e->control.loop=loop;e->control.foot=category=="Footsteps";e->control.disposed=false;
 }
 void configure(const String &id,const Ref<AudioStream> &stream,bool loop,const String &category){
  if(stream.is_null())return;if(!core->ready&&!initialize(int(AudioServer::get_singleton()->get_mix_rate())))return;
  std::string name=key(stream->get_path());if(name.empty())name="instance:"+std::to_string(uint64_t(stream->get_instance_id()));
  auto it=core->clips.find(name);std::shared_ptr<PCM> pcm;
  if(it!=core->clips.end())pcm=it->second;
  else{
   pcm=std::make_shared<PCM>();int wanted=int(std::ceil(stream->get_length()*core->rate));
   if(wanted<=0||wanted>int(core->rate*600)){core->error="Invalid native recording length";return;}
   pcm->data.reserve(wanted);auto playback=stream->instantiate_playback();playback->start(0);
   while(int(pcm->data.size())<wanted){auto chunk=playback->mix_audio(1.0f,std::min(8192,wanted-int(pcm->data.size())));if(chunk.is_empty())break;for(int i=0;i<chunk.size();i++)pcm->data.push_back((chunk[i].x+chunk[i].y)*.5f);}
   playback->stop();core->clips[name]=pcm;
  }
  install(id,pcm,loop,category);
 }
 void configure_pcm(const String &id,const PackedFloat32Array &samples,bool loop,const String &category){auto pcm=std::make_shared<PCM>();pcm->data.assign(samples.ptr(),samples.ptr()+samples.size());core->clips[key(id)]=pcm;install(id,pcm,loop,category);}
 void play(const String &id,double offset){std::lock_guard<std::mutex> g(core->mutex);if(auto *e=lookup(id)){e->control.serial++;e->control.offset=float(offset);e->control.playing=true;}}
 void stop(const String &id){std::lock_guard<std::mutex> g(core->mutex);if(auto *e=lookup(id))e->control.playing=false;}
 void suspend(const String &id,bool silent){std::lock_guard<std::mutex> g(core->mutex);if(auto *e=lookup(id))e->control.silent=silent;}
 void dispose(const String &id){std::lock_guard<std::mutex> g(core->mutex);if(auto *e=lookup(id)){e->control.disposed=true;e->control.playing=false;core->ids.erase(key(id));}}
 void clear(){std::lock_guard<std::mutex> g(core->mutex);for(auto &e:core->emitters)if(e){e->control.disposed=true;e->control.playing=false;}core->ids.clear();core->scene.paused=true;}
 void update(const String &id,const Dictionary &d){
  std::lock_guard<std::mutex> g(core->mutex);core->collect();auto *e=lookup(id);if(!e)return;auto &c=e->control;
  c.doppler=bool(d.get("doppler",true));c.pitch=number(d,"pitch",1);c.send=gain(number(d,"send_db",-100));c.field=core->region(vector(d["position"]));if(c.field==0)c.send*=number(d,"transmission",1);
  c.count=1;c.paths[0]={1,vector(d["position"]),number(d,"distance",0),number(d,"cutoff",20000),gain(number(d,"db",-100))};
  Array paths=d.get("paths",Array());for(int i=0;i<paths.size()&&c.count<INPUT_PATHS;i++){Dictionary p=paths[i];c.paths[c.count++]={identity(p["id"]),vector(p["position"]),number(p,"length",0),number(p,"cutoff",20000),gain(number(p,"db",-100))};}
 }
 void layout(const Dictionary &data){
  if(!core->ready)return;auto b=std::make_shared<Bank>();b->fields[0]=core->field();b->fields[0]->id="passage";b->fields[0]->set_decay({.2f,.2f,.2f},core->rate);b->count=1;
  Array rooms=data.get("rooms",Array());for(int i=0;i<rooms.size()&&b->count<ROOMS;i++){
   Dictionary r=rooms[i];auto f=core->field();f->id=r["id"];f->region=true;Array rect=r["rect"];f->x=rect[0];f->z=rect[1];f->w=rect[2];f->h=rect[3];f->target_wet=number(r,"wet",0);f->set_decay(vector(r["rt"]),core->rate);b->fields[b->count++]=f;
  }
  Array portals=data.get("portals",Array());for(int i=0;i<portals.size();i++){Dictionary p=portals[i];Portal portal;portal.id=p["id"];portal.at=vector(p["position"]);portal.width=number(p,"width",1);portal.open=number(p,"open",1);String room=p["room"];for(int j=1;j<b->count;j++)if(b->fields[j]->id==room)portal.room=j;b->portals.push_back(portal);}
  std::lock_guard<std::mutex> g(core->mutex);if(core->bank)core->retired_banks.push_back(core->bank);core->bank=b;
 }
 void scene(const Dictionary &data){
  std::lock_guard<std::mutex> g(core->mutex);Dictionary settings=data.get("settings",Dictionary());
  core->scene.position=vector(data["position"]);core->scene.forward=vector(data["forward"]);core->scene.paused=bool(data.get("paused",false));core->scene.ambience=number(settings,"ambience",.8f);core->scene.footsteps=number(settings,"footsteps",.75f);core->scene.headphones=number(settings,"binaural",1)>.5f;
  if(!core->bank)return;auto &bank=*core->bank;int here=core->region(core->scene.position);Dictionary visible=data.get("portal_visibility",Dictionary());
  bank.fields[0]->control.decay=vector(data.get("decay",Array::make(.2,.2,.2)));bank.fields[0]->control.wet=number(data,"wet",0);
  for(int i=0;i<bank.count;i++){
   auto &f=*bank.fields[i];f.control.local=(i==0||i==here)?1.0f:0.0f;f.control.remote=0;f.control.at=core->scene.position+core->scene.forward;
   if(i==0||i==here)continue;
   for(const auto &p:bank.portals)if(p.room==i){V3 d=p.at-core->scene.position;float distance=std::sqrt(d.dot(d));float strength=p.open*p.width/(p.width+distance)*.35f*(bool(visible.get(p.id,true))?1:.025f);if(strength>f.control.remote){f.control.remote=strength;f.control.at=p.at;}}
  }
 }
 Dictionary snapshot(){
  std::lock_guard<std::mutex> g(core->mutex);Dictionary d;d["ready"]=core->ready;d["backend"]="C++ / Steam Audio 4.8.1";d["hrtf"]="bilinear measured HRTF convolution";d["sample_rate"]=core->rate;d["block_frames"]=BLOCK;d["emitters"]=int(core->ids.size());d["decoded_clips"]=int(core->clips.size());d["active_paths"]=core->active_paths.load();d["room_fields"]=core->bank?core->bank->count-1:0;d["fdn_lines"]=16;d["blocks"]=int64_t(core->blocks.load());d["max_block_ms"]=double(core->max_us.load())/1000;d["mean_block_ms"]=double(core->total_us.load())/std::max(uint64_t(1),core->blocks.load())/1000;d["over_budget_blocks"]=int64_t(core->deadline_misses.load());d["path_overflows"]=int64_t(core->path_overflows.load());d["error"]=String(core->error.c_str());return d;
 }
 PackedVector2Array render_frames(int count){
  PackedVector2Array result;if(count<1||count>int(core->rate*30)||core->playbacks.load()>0)return result;result.resize(count);
  static_assert(sizeof(Vector2)==sizeof(AudioFrame));core->mix(reinterpret_cast<AudioFrame *>(result.ptrw()),count);return result;
 }
};
static void initialize_module(ModuleInitializationLevel level){if(level==MODULE_INITIALIZATION_LEVEL_SCENE){ClassDB::register_class<AtmoSpatialPlayback>();ClassDB::register_class<AtmoSpatialStream>();}}
static void uninitialize_module(ModuleInitializationLevel){}
}
extern "C" {
GDExtensionBool GDE_EXPORT atmo_audio_init(GDExtensionInterfaceGetProcAddress get_proc_address,const GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization){
 godot::GDExtensionBinding::InitObject init(get_proc_address,library,initialization);init.register_initializer(atmo::initialize_module);init.register_terminator(atmo::uninitialize_module);init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);return init.init();
}
}
