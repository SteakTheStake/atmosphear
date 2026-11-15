/* Single-clock browser propagation. Godot supplies geometry, not duplicated audio.
 * Web Audio HRTF uses the browser's bundled data; no external dataset/download.
 */
(()=>{
'use strict';
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v));
const db=v=>Math.pow(10,v/20);
const ramp=(p,v,t,d=.04)=>{p.cancelScheduledValues(t);p.setValueAtTime(p.value,t);p.linearRampToValueAtTime(v,t+d);};
// ISO 9613-1 coefficients at 20 C, 50% RH, 101.325 kPa; broad-band EQ fit.
function airLoss(f){const T=293.15,h=.5*Math.pow(10,-6.8346*Math.pow(273.16/T,1.261)+4.6151);
 const o=24+40400*h*(.02+h)/(.391+h),n=9+280*h;
 return 8.686*f*f*(1.84e-11+.01275*Math.exp(-2239.1/T)/(o+f*f/o)+.1068*Math.exp(-3352/T)/(n+f*f/n));}
function airFilters(c){return [500,2000,8000].map(f=>{const eq=c.createBiquadFilter();eq.type='peaking';eq.frequency.value=f;eq.Q.value=.6;return eq;});}
function airUpdate(eq,d,t){eq.forEach((filter,i)=>ramp(filter.gain,-airLoss([500,2000,8000][i])*d,t));}
const worklet=`
class Room extends AudioWorkletProcessor {
 constructor(){super();this.n=0;this.wet=0;this.targetWet=0;this.rt=[.3,.25,.2];
 this.lengths=[1493,1601,1747,1867,1999,2137,2281,2411].map(n=>Math.round(n*sampleRate/48000));
 this.buffers=this.lengths.map(n=>new Float32Array(n));this.at=new Int32Array(8);this.lo=new Float64Array(8);this.hi=new Float64Array(8);
 this.g=this.lengths.map(()=>[0,0,0]);this.targetG=this.lengths.map(()=>[0,0,0]);this.energy=0;
 this.port.onmessage=e=>{const d=e.data;if(d.dispose)this.dead=true;if(d.clear){for(const b of this.buffers)b.fill(0);this.lo.fill(0);this.hi.fill(0);}
 if(d.rt){this.rt=d.rt.map(v=>Math.max(.08,Math.min(8,v)));for(let i=0;i<8;i++)this.targetG[i]=this.rt.map(rt=>Math.pow(10,-3*this.lengths[i]/sampleRate/rt));}
 if(d.wet!==undefined)this.targetWet=d.wet;};
 this.a=1-Math.exp(-2*Math.PI*400/sampleRate);this.b=1-Math.exp(-2*Math.PI*3500/sampleRate);this.v=new Float64Array(8);this.h=new Float64Array(8);
 }
 process(inputs,outputs){if(this.dead)return false;const out=outputs[0],input=inputs[0];if(!out?.length)return true;
 for(let n=0;n<out[0].length;n++){
 let energy=0;for(let i=0;i<8;i++){const x=this.buffers[i][this.at[i]];this.lo[i]+=this.a*(x-this.lo[i]);this.hi[i]+=this.b*(x-this.hi[i]);
 for(let k=0;k<3;k++)this.g[i][k]+=.0002*(this.targetG[i][k]-this.g[i][k]);
 this.v[i]=this.lo[i]*this.g[i][0]+(this.hi[i]-this.lo[i])*this.g[i][1]+(x-this.hi[i])*this.g[i][2];this.h[i]=this.v[i];energy+=x*x;}
 // Orthogonal normalized Hadamard feedback, fixed delays (no chorus modulation).
 for(let step=1;step<8;step*=2)for(let i=0;i<8;i+=step*2)for(let j=0;j<step;j++){let a=this.h[i+j],b=this.h[i+j+step];this.h[i+j]=a+b;this.h[i+j+step]=a-b;}
 const x=((input[0]?.[n]||0)+(input[1]?.[n]||0))*.5;
 for(let i=0;i<8;i++){this.buffers[i][this.at[i]]=x*(i%2?-.353553:.353553)+this.h[i]*.353553390593;this.at[i]=(this.at[i]+1)%this.lengths[i];}
 this.wet+=.0005*(this.targetWet-this.wet);
 out[0][n]=(this.v[0]+this.v[2]-this.v[4]+this.v[6])*.5*this.wet;
 if(out[1])out[1][n]=(this.v[1]-this.v[3]+this.v[5]+this.v[7])*.5*this.wet;
 this.energy=energy;
 }
 return true;
 }
}registerProcessor('atmo-room',Room);`;
const renderer={version:2,context:null,emitters:new Map(),cache:new Map(),errors:[],mode:'headphones',audit:{starts:0,pathReplacements:0,decodes:0},isolation:'all',room:null};
window.AtmoAcoustics=renderer;
renderer.init=async function(context){
 if(this.context)return;this.context=context;
 this.output=context.createGain();this.output.connect(context.destination);
 this.roomInput=context.createGain();this.roomGate=context.createGain();this.roomGate.connect(this.output);
 const blob=URL.createObjectURL(new Blob([worklet],{type:'text/javascript'}));
 try{await context.audioWorklet.addModule(blob);this.room=new AudioWorkletNode(context,'atmo-room',{numberOfInputs:1,numberOfOutputs:1,outputChannelCount:[2]});this.room.onprocessorerror=()=>this.errors.push('Passage reverb processor failed');this.roomInput.connect(this.room);this.room.connect(this.roomGate);}
 finally{URL.revokeObjectURL(blob);}
 this.ready=true;
};
renderer.load=function(path){
 if(!this.cache.has(path))this.cache.set(path,fetch(new URL('sound/'+path.split('/').pop(),document.baseURI)).then(r=>{if(!r.ok)throw Error('Audio '+r.status+': '+path);return r.arrayBuffer();}).then(b=>this.context.decodeAudioData(b)).then(b=>{this.audit.decodes++;return b;}).catch(e=>{this.errors.push(String(e));throw e;}));
 return this.cache.get(path);
};
function panner(c){const p=c.createPanner();p.panningModel=renderer.mode==='headphones'?'HRTF':'equalpower';p.distanceModel='inverse';p.rolloffFactor=0;return p;}
function position(p,v,t){ramp(p.positionX,v[0],t);ramp(p.positionY,v[1],t);ramp(p.positionZ,v[2],t);}
function filter(c){const f=c.createBiquadFilter();f.type='lowpass';f.frequency.value=20000;f.Q.value=.5;return f;}
renderer.configure=function(id,path,loop,category){
 if(!this.context)return;let e=this.emitters.get(id);
 if(!e){const c=this.context;e={id,category,loop,path,serial:0,offset:0,source:null,paths:new Map(),playing:false,silent:false};
 e.input=c.createGain();e.delay=c.createDelay(1);e.filter=filter(c);e.gain=c.createGain();e.gain.gain.value=0;e.pan=panner(c);
 e.air=airFilters(c);e.input.connect(e.delay);e.delay.connect(e.air[0]);e.air[0].connect(e.air[1]);e.air[1].connect(e.air[2]);e.air[2].connect(e.filter);e.filter.connect(e.gain);e.gain.connect(e.pan);e.pan.connect(this.output);
 e.send=c.createGain();e.send.gain.value=0;e.input.connect(e.send);e.send.connect(this.roomInput);this.emitters.set(id,e);}
 if(e.path!==path){this.stop(id);e.path=path;}e.loop=loop;e.category=category;this.load(path).catch(()=>{});
};
renderer.play=function(id,offset=0){const e=this.emitters.get(id);if(!e)return;this.stop(id);e.playing=true;e.offset=offset;e.request=this.context.currentTime;this.start(e);};
renderer.start=async function(e){const token=++e.serial;
 try{const buffer=await this.load(e.path);if(!e.playing||e.silent||e.serial!==token||!this.emitters.has(e.id))return;
 const c=this.context,s=c.createBufferSource();s.buffer=buffer;s.loop=e.loop;s.playbackRate.value=e.pitch||1;
 let offset=e.offset+(e.silent?0:(c.currentTime-e.request)*(e.pitch||1));if(e.loop)offset%=buffer.duration;else if(offset>=buffer.duration){e.playing=false;return;}
 // Each playback owns its envelope so a pooled restart can overlap the old
 // voice's release without cutting a nonzero sample or fading the new voice.
 const envelope=c.createGain();envelope.gain.setValueAtTime(0,c.currentTime);envelope.gain.linearRampToValueAtTime(1,c.currentTime+.008);
 e.source=s;e.envelope=envelope;e.startOffset=offset;e.startTime=c.currentTime;e.lastRate=e.pitch||1;s.connect(envelope);envelope.connect(e.input);s.start(0,offset);this.audit.starts++;
 s.onended=()=>{s.disconnect();envelope.disconnect();if(e.source===s){e.source=null;e.envelope=null;if(!e.silent)e.playing=false;}};
 }catch(err){this.errors.push(String(err));}
};
function release(e){if(!e.source)return;const s=e.source,envelope=e.envelope,t=renderer.context.currentTime;
 e.source=null;e.envelope=null;
 // Keep the signal connected until the audio clock has rendered the release.
 s.onended=()=>{s.disconnect();envelope.disconnect();};ramp(envelope.gain,0,t,.008);s.stop(t+.010);
}
renderer.stop=function(id){const e=this.emitters.get(id);if(!e)return;e.serial++;e.playing=false;release(e);};
renderer.suspend=function(id,silent){const e=this.emitters.get(id);if(!e||e.silent===silent)return;
 if(silent){e.serial++;if(e.source){e.offset=e.startOffset+(this.context.currentTime-e.startTime)*(e.lastRate||1);release(e);}}
 e.silent=silent;if(!silent&&e.playing){e.request=this.context.currentTime;this.start(e);}
 ramp(e.input.gain,silent?0:1,this.context.currentTime,.015);
};
renderer.dispose=function(id){const e=this.emitters.get(id);if(!e)return;this.stop(id);const t=this.context.currentTime;
 ramp(e.gain.gain,0,t,.015);ramp(e.send.gain,0,t,.015);for(const p of e.paths.values())retire(e,p);
 setTimeout(()=>{for(const node of [e.input,e.delay,e.filter,e.gain,e.pan,e.send,...e.air])node.disconnect();},100);this.emitters.delete(id);};
function retire(e,p){const t=renderer.context.currentTime;ramp(p.gain.gain,0,t,.06);setTimeout(()=>{try{e.input.disconnect(p.delay);}catch{}for(const n of [p.delay,p.filter,p.gain,p.pan])n.disconnect();},100);}
renderer.update=function(id,d){const e=this.emitters.get(id);if(!e||!this.ready)return;const c=this.context,t=c.currentTime;
 const region=this.region(d.position);if(e.field!==region){e.send.disconnect();e.send.connect(this.fields?.get(region)?.input||this.roomInput);e.field=region;}
 e.pitch=d.pitch; // source variation only; propagation delay supplies physical Doppler.
 if(e.source){ramp(e.source.playbackRate,d.pitch,t);e.lastRate=d.pitch;}
 const category=e.category==='Footsteps'?this.settings?.footsteps:this.settings?.ambience;
 airUpdate(e.air,d.distance,t);
 const gain=(category??.8)*db(d.db);ramp(e.gain.gain,this.isolation==='early'||this.isolation==='late'?0:gain,t);
 ramp(e.delay.delayTime,clamp(d.distance/343,0,.8),t,1/30);ramp(e.filter.frequency,d.cutoff,t);position(e.pan,d.position,t);
 const seen=new Set();for(const path of d.paths){seen.add(path.id);let p=e.paths.get(path.id);
 if(!p){p={delay:c.createDelay(1),filter:filter(c),gain:c.createGain(),pan:panner(c)};p.gain.gain.value=0;p.delay.delayTime.value=clamp(path.length/343,0,.8);e.input.connect(p.delay);p.delay.connect(p.filter);p.filter.connect(p.gain);p.gain.connect(p.pan);p.pan.connect(this.output);e.paths.set(path.id,p);this.audit.pathReplacements++;}
 ramp(p.delay.delayTime,clamp(path.length/343,0,.8),t,.16);ramp(p.filter.frequency,path.cutoff,t);position(p.pan,path.position,t);
 ramp(p.gain.gain,this.isolation==='direct'||this.isolation==='late'?0:(category??.8)*db(path.db),t,.06);}
 for(const [key,p] of e.paths)if(!seen.has(key)){retire(e,p);e.paths.delete(key);}
 ramp(e.send.gain,this.isolation==='direct'||this.isolation==='early'?0:(category??.8)*db(d.send_db)*(region?1:(d.transmission??1)),t);
};
// Each authored region owns a late field. Door lintels define openings into the
// connecting passage field; this is a one-hop portal approximation.
renderer.layout=function(layout){
 for(const f of this.fields?.values()||[]){f.node.port.postMessage({dispose:true});f.node.port.close();f.input.disconnect();f.node.disconnect();f.local.disconnect();f.gain.disconnect();f.filter.disconnect();f.pan.disconnect();}
 this.fields=new Map();this.geometry=layout;
 const c=this.context;
 for(const room of layout.rooms){const input=c.createGain(),node=new AudioWorkletNode(c,'atmo-room',{numberOfInputs:1,numberOfOutputs:1,outputChannelCount:[2]}),gain=c.createGain(),local=c.createGain(),pan=panner(c),spectral=filter(c);
 node.onprocessorerror=()=>this.errors.push('Room reverb processor failed: '+room.id);gain.gain.value=0;local.gain.value=0;input.connect(node);node.connect(local);local.connect(this.output);node.connect(gain);gain.connect(spectral);spectral.connect(pan);pan.connect(this.output);node.port.postMessage({rt:room.rt,wet:room.wet});
 this.fields.set(room.id,{...room,input,node,gain,local,pan,filter:spectral});}
 for(const e of this.emitters.values())e.field=null;
};
renderer.region=function(p){return this.geometry?.rooms.find(r=>p[0]>=r.rect[0]&&p[0]<=r.rect[0]+r.rect[2]&&p[2]>=r.rect[1]&&p[2]<=r.rect[1]+r.rect[3])?.id||'';};
renderer.scene=function(d){if(!this.ready)return;const t=this.context.currentTime;this.settings=d.settings;
 const mode=d.settings.binaural>.5?"headphones":"speakers";if(mode!==this.mode)this.setMode(mode);
 ramp(this.output.gain,d.settings.master,t);ramp(this.roomGate.gain,d.paused?0:1,t,.02);
 if(this.fields){const here=this.region(d.position);
 for(const f of this.fields.values()){
 let gain=0,at=d.position;
 if(f.id===here){gain=1;at=[d.position[0],d.position[1],d.position[2]-1];}
 else{let best=0;for(const portal of this.geometry.portals.filter(p=>p.room===f.id)){
 const distance=Math.hypot(...portal.position.map((x,i)=>x-d.position[i]));
 const strength=portal.open*portal.width/(portal.width+distance)*.35*(d.portal_visibility?.[portal.id]===false?.025:1);
 if(strength>best){best=strength;at=portal.position;}}
 gain=best;}
 ramp(f.local.gain,!d.paused&&f.id===here?1:0,t,.12);ramp(f.gain.gain,d.paused||f.id===here?0:gain,t,.12);ramp(f.filter.frequency,f.id===here?20000:3500,t);position(f.pan,at,t);
 }
 }
 const l=this.context.listener;for(const [a,v] of [['positionX',d.position[0]],['positionY',d.position[1]],['positionZ',d.position[2]],['forwardX',d.forward[0]],['forwardY',d.forward[1]],['forwardZ',d.forward[2]],['upX',0],['upY',1],['upZ',0]])if(l[a])ramp(l[a],v,t);
 this.room.port.postMessage({rt:d.decay,wet:d.wet});
 if(this.level!==d.level){this.level=d.level;this.room.port.postMessage({clear:true});}
};
renderer.setMode=function(mode){this.mode=mode==='speakers'?'speakers':'headphones';for(const e of this.emitters.values()){e.pan.panningModel=this.mode==='headphones'?'HRTF':'equalpower';for(const p of e.paths.values())p.pan.panningModel=e.pan.panningModel;}};
renderer.snapshot=function(){return {version:2,ready:!!this.ready,emitters:this.emitters.size,active:[...this.emitters.values()].filter(e=>e.source).length,paths:[...this.emitters.values()].reduce((n,e)=>n+e.paths.size,0),errors:this.errors.slice(),audit:{...this.audit},mode:this.mode,clock:'one AudioBufferSource per emitter',late:'8-line frequency-dependent orthogonal FDN',room_fields:this.fields?.size||0,portals:this.geometry?.portals.length||0};};
})();
