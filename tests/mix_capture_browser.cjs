/* Capture the real exported engine mix. No asset-only or subjective listening claims. */
const {chromium}=require('playwright');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {spawnSync}=require('node:child_process');
const assert=require('node:assert/strict');

const phase=process.env.ATMO_MIX_PHASE||'before';
const seconds=Number(process.env.ATMO_CAPTURE_SECONDS||15);
const regionMatch=process.env.ATMO_REGION_MATCH?new RegExp(process.env.ATMO_REGION_MATCH,'i'):null;
const base=process.env.ATMO_BASE_URL||'http://127.0.0.1:8060/';
const out=path.resolve('test-results','mix-captures-'+phase);
fs.mkdirSync(out,{recursive:true});
const report={phase,method:{source:'Live Godot browser output tapped immediately before WebAudio destination; the same mixed samples feed preview capture.',analysis:'Sample peak, RMS and time windows from live PCM, saved as PCM16 stereo WAV with optional Ogg preview. No auditory perception or listening claimed.',area_seconds:seconds,region_filter:process.env.ATMO_REGION_MATCH||null,settings:{master:.75,ambience:.8,footsteps:.75,ui:.35,quality:1,speed:1}},areas:[],walks:[],longs:[],errors:[]};
const pack=path.resolve('build/web/index.pck');
if(fs.existsSync(pack))report.export_sha256=crypto.createHash('sha256').update(fs.readFileSync(pack)).digest('hex');
const slug=text=>text.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'');
const save=()=>fs.writeFileSync(path.resolve('test-results','mix-audit-'+phase+'.json'),JSON.stringify(report,null,2));

(async()=>{
  const browser=await chromium.launch({headless:true,args:['--autoplay-policy=no-user-gesture-required']});
  const page=await browser.newPage({viewport:{width:1152,height:720}});
  page.on('pageerror',error=>report.errors.push(error.message));
  page.on('console',message=>{if(message.type()==='error'&&!message.text().includes('Blocking on the main thread'))report.errors.push(message.text());});
  await page.addInitScript(()=>{
    const nativeConnect=AudioNode.prototype.connect;
    window.mixTaps=[];
    window.activeMixCapture=null;
    AudioNode.prototype.connect=function(destination,...args){
      if(destination instanceof AudioDestinationNode&&!this.__mixTap){
        this.__mixTap=true;
        const context=this.context;
        const analyser=context.createAnalyser();analyser.fftSize=2048;
        nativeConnect.call(this,analyser);
        const processor=context.createScriptProcessor(2048,2,2);
        nativeConnect.call(this,processor);
        nativeConnect.call(processor,destination);
        processor.onaudioprocess=event=>{
          const capture=window.activeMixCapture;
          if(!capture||capture.processor!==processor)return;
          const left=event.inputBuffer.getChannelData(0),right=event.inputBuffer.getChannelData(1);
          let l2=0,r2=0,peak=0,clipped=0;
          const pcm=new Int16Array(left.length*2);
          for(let i=0;i<left.length;i++){
            l2+=left[i]*left[i];r2+=right[i]*right[i];
            peak=Math.max(peak,Math.abs(left[i]),Math.abs(right[i]));
            if(Math.abs(left[i])>=.999)clipped++;
            if(Math.abs(right[i])>=.999)clipped++;
            pcm[i*2]=Math.round(Math.max(-1,Math.min(1,left[i]))*32767);
            pcm[i*2+1]=Math.round(Math.max(-1,Math.min(1,right[i]))*32767);
          }
          capture.chunks.push(new Uint8Array(pcm.buffer));
          capture.frames+=left.length;capture.l2+=l2;capture.r2+=r2;
          capture.peak=Math.max(capture.peak,peak);capture.clipped+=clipped;
          capture.windows.push({t:context.currentTime-capture.audioStart,seconds:left.length/context.sampleRate,rms:Math.sqrt((l2+r2)/(2*left.length)),peak,left_rms:Math.sqrt(l2/left.length),right_rms:Math.sqrt(r2/left.length)});
        };
        window.mixTaps.push({context,processor,analyser,nodeType:this.constructor.name});
      }
      return nativeConnect.call(this,destination,...args);
    };
    window.beginMixCapture=()=>{
      const candidates=window.mixTaps.filter(t=>t.context.state==='running').map(t=>{const data=new Float32Array(t.analyser.fftSize);t.analyser.getFloatTimeDomainData(data);return{tap:t,rms:Math.sqrt(data.reduce((s,v)=>s+v*v,0)/data.length)};}).sort((a,b)=>b.rms-a.rms);
      const tap=candidates[0]?.tap;
      if(!tap)throw new Error('No running engine output tap');
      const capture={frames:0,l2:0,r2:0,peak:0,clipped:0,windows:[],chunks:[],processor:tap.processor,sampleRate:tap.context.sampleRate,audioStart:tap.context.currentTime,wallStart:performance.now(),tap_candidates:candidates.map(c=>({node:c.tap.nodeType,rms:c.rms}))};
      window.activeMixCapture=capture;
      return capture.tap_candidates;
    };
    window.finishMixCapture=async()=>{
      const capture=window.activeMixCapture;window.activeMixCapture=null;
      const bytes=new Uint8Array(44+capture.frames*4),view=new DataView(bytes.buffer);
      const text=(offset,value)=>{for(let i=0;i<value.length;i++)bytes[offset+i]=value.charCodeAt(i);};
      text(0,'RIFF');view.setUint32(4,bytes.length-8,true);text(8,'WAVE');text(12,'fmt ');view.setUint32(16,16,true);view.setUint16(20,1,true);view.setUint16(22,2,true);view.setUint32(24,capture.sampleRate,true);view.setUint32(28,capture.sampleRate*4,true);view.setUint16(32,4,true);view.setUint16(34,16,true);text(36,'data');view.setUint32(40,capture.frames*4,true);
      let writeOffset=44;for(const chunk of capture.chunks){bytes.set(chunk,writeOffset);writeOffset+=chunk.length;}
      let binary='';for(let i=0;i<bytes.length;i+=8192)binary+=String.fromCharCode(...bytes.subarray(i,i+8192));
      const db=value=>20*Math.log10(Math.max(value,1e-9));
      const rms=Math.sqrt((capture.l2+capture.r2)/(2*Math.max(capture.frames,1)));
      const envelope=capture.windows.map(w=>w.rms).sort((a,b)=>a-b);
      const percentile=p=>envelope[Math.floor((envelope.length-1)*p)]||0;
      return {audio_base64:btoa(binary),tap_candidates:capture.tap_candidates,sample_rate:capture.sampleRate,audio_seconds:capture.frames/capture.sampleRate,wall_seconds:(performance.now()-capture.wallStart)/1000,rms_dbfs:db(rms),peak_dbfs:db(capture.peak),crest_db:db(capture.peak)-db(rms),clipped_samples:capture.clipped,stereo_rms_dbfs:[db(Math.sqrt(capture.l2/Math.max(capture.frames,1))),db(Math.sqrt(capture.r2/Math.max(capture.frames,1)))],quiet_window_fraction:capture.windows.filter(w=>db(w.rms)<-60).length/Math.max(capture.windows.length,1),envelope_p95_p05_db:db(percentile(.95))-db(percentile(.05)),windows:capture.windows.map(w=>({t:+w.t.toFixed(4),rms_dbfs:+db(w.rms).toFixed(3),peak_dbfs:+db(w.peak).toFixed(3)}))};
    };
  });
  const state=()=>page.evaluate(()=>window.atmoDebug);
  const command=cmd=>page.evaluate(value=>window.Atmo.command(value),cmd);
  const until=(fn,arg)=>page.waitForFunction(fn,arg,{timeout:30000});
  const capture=async(filename,duration,move=false)=>{
    const before=await state(),states=[];
    const wallStart=Date.now();
    const taps=await page.evaluate(()=>window.beginMixCapture());
    console.log('CAPTURE_TAPS '+JSON.stringify(taps));
    if(move)await page.keyboard.down('w');
    for(let i=0;i<duration*4;i++){
      if(move&&i===Math.floor(duration*2)){
        await page.keyboard.up('w');
        await page.keyboard.down('ArrowRight');
      }
      await page.waitForTimeout(250);
      const snapshot=await state();snapshot.capture_t=(Date.now()-wallStart)/1000;states.push(snapshot);
    }
    if(move){await page.keyboard.up('w');await page.keyboard.up('ArrowRight');}
    const result=await page.evaluate(()=>window.finishMixCapture());
    const bytes=Buffer.from(result.audio_base64,'base64');delete result.audio_base64;
    const wav=path.join(out,filename+'.wav');fs.writeFileSync(wav,bytes);
    const preview=path.join(out,filename+'.ogg');
    assert(result.audio_seconds>duration*.85,'Capture must contain continuous real-time output: '+JSON.stringify({audio_seconds:result.audio_seconds,peak:result.peak_dbfs}));
    assert(result.peak_dbfs>-120,'Capture must contain nonzero engine output');
    const converted=spawnSync('ffmpeg',['-v','error','-y','-i',wav,'-c:a','libvorbis','-q:a','5',preview],{encoding:'utf8'});
    if(converted.status!==0)throw new Error('Preview conversion failed: '+converted.stderr);
    const countMap=snapshot=>Object.fromEntries(snapshot.diagnostics.sources.map(s=>[s.anchor,s.event_count??null]));
    const countsBefore=countMap(before),countsAfter=countMap(states.at(-1));
    const events=Object.entries(countsAfter).map(([anchor,count])=>{
      let prior=countsBefore[anchor];const timeline=[];
      for(const snapshot of states){const current=snapshot.diagnostics.sources.find(x=>x.anchor===anchor);if(current&&current.event_count!==prior){timeline.push({t:snapshot.capture_t,clip:current.active_clip,count:current.event_count-prior});prior=current.event_count;}}
      return {anchor,events:count===null||countsBefore[anchor]===null?null:count-countsBefore[anchor],timeline,active_clips:[...new Set(states.map(s=>s.diagnostics.sources.find(x=>x.anchor===anchor)?.active_clip).filter(Boolean))]};
    }).filter(e=>e.events>0||e.active_clips.length>1);
    const snapshot=states.at(-1);
    const active=snapshot.diagnostics.sources.filter(s=>!s.virtualized);
    result.preview=path.relative(process.cwd(),preview).replaceAll('\\','/');
    result.raw_capture=path.relative(process.cwd(),wav).replaceAll('\\','/');
    result.position=before.position;result.end_position=snapshot.position;
    result.active_sources=active.map(s=>({anchor:s.anchor,clip:s.clip,landmark:s.landmark,...s.acoustics}));
    result.events=events;result.room=snapshot.diagnostics.room;
    result.pause_samples=states.filter(s=>s.paused).length;
    assert.equal(result.pause_samples,0,'Captures must remain unpaused');
    assert(result.audio_seconds>duration*.85,'Capture must contain continuous real-time output');
    return result;
  };
  try{
    await page.goto(base+'?debug=1&qa=1');await until(()=>window.atmoDebug?.ready);
    await page.locator('#start').click();
    await page.keyboard.press('Enter',{delay:80});
    await until(()=>window.atmoDebug.started);
    for(const [name,value]of Object.entries(report.method.settings))await command('setting:'+name+':'+value);
    const levels=(process.env.ATMO_LEVELS||'forest,cistern,freighter,courtyard').split(',');
    for(const level of levels){
      await command('play:'+level);await until(id=>window.atmoDebug.started&&window.atmoDebug.level===id,level);
      await page.waitForTimeout(300);
      const regions=(await state()).qa_regions;
      assert(Array.isArray(regions)&&regions.length>=6,'Opt-in local QA must expose six region fixtures');
      for(let index=0;index<regions.length;index++){
        const label=regions[index].label||regions[index].name||String(index);
        if(regionMatch&&!regionMatch.test(label))continue;
        await command('qa:region:'+index);
        await until(i=>window.atmoDebug.qa_region===i,index);
        await page.waitForTimeout(1800);
        const measurement=await capture(level+'-'+String(index).padStart(2,'0')+'-'+slug(label),seconds);
        report.areas.push({level,index,label,...measurement});save();
        console.log(JSON.stringify({level,area:label,rms_dbfs:+measurement.rms_dbfs.toFixed(2),peak_dbfs:+measurement.peak_dbfs.toFixed(2),events:measurement.events.map(e=>[e.anchor,e.events])}));
      }
      if(process.env.ATMO_LONG_LOOPS==='1'){
        const requested={forest:/bird grove/i,cistern:/bell vault/i,freighter:/servo/i,courtyard:/bell gate/i}[level];
        const index=regions.findIndex(r=>requested.test(r.label||r.name||''));
        assert(index>=0,'Representative long-capture region must exist for '+level);
        await command('qa:region:'+index);await until(i=>window.atmoDebug.qa_region===i,index);await page.waitForTimeout(1800);
        const label=regions[index].label||regions[index].name;
        report.longs.push({level,index,label,...await capture(level+'-long-'+slug(label),60)});save();
        console.log('LONG CAPTURE COMPLETE '+level+' '+label);
      }else if(process.env.ATMO_SKIP_WALKS!=='1'){
        await command('play:'+level);await until(id=>window.atmoDebug.level===id,level);await page.waitForTimeout(1800);
        report.walks.push({level,...await capture(level+'-walk-and-turn',12,true)});save();
      }
    }
    assert.deepEqual(report.errors,[]);
    console.log('CAPTURE COMPLETE '+report.areas.length+' areas '+report.walks.length+' walking/turning samples '+report.longs.length+' long samples');
  }finally{save();await browser.close();}
})().catch(error=>{report.failure=String(error.stack||error);save();console.error(error);process.exit(1);});
