/* Measure the actual exported stereo tail after a real, isolated air-punch. */
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');

(async()=>{
  const browser=await chromium.launch({headless:true});
  const page=await browser.newPage({viewport:{width:1280,height:900}});
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  page.on('console',message=>{
    if(message.type()==='error'&&!message.text().includes('Blocking on the main thread'))errors.push(message.text());
  });
  await page.addInitScript(()=>{
    window.audioMeters=[];
    const connect=AudioNode.prototype.connect;
    AudioNode.prototype.connect=function(destination,...args){
      if(destination instanceof AudioDestinationNode&&!this.__tailMetered){
        this.__tailMetered=true;
        const split=this.context.createChannelSplitter(2);
        connect.call(this,split);
        const meters=[0,1].map(channel=>{
          const meter=this.context.createAnalyser();meter.fftSize=2048;
          connect.call(split,meter,channel);return meter;
        });
        window.audioMeters.push({context:this.context,meters});
      }
      return connect.call(this,destination,...args);
    };
    window.audioSample=()=>{
      const rms=[0,0];let running=false;
      for(const {context,meters} of window.audioMeters){
        running ||= context.state==='running';
        meters.forEach((meter,channel)=>{
          const values=new Float32Array(meter.fftSize);meter.getFloatTimeDomainData(values);
          rms[channel]+=Math.sqrt(values.reduce((sum,value)=>sum+value*value,0)/values.length);
        });
      }
      return {rms,running};
    };
    window.armTailCapture=()=>{
      window.tailCapture={start:null,samples:[]};
      window.tailCaptureTimer=setInterval(()=>{
        const sample=window.audioSample();
        window.tailCapture.samples.push({time:performance.now(),...sample});
      },15);
    };
    window.addEventListener('keydown',event=>{
      if(event.key.toLowerCase()==='e'&&!event.repeat&&window.tailCapture&&window.tailCapture.start===null)window.tailCapture.start=performance.now();
    },true);
    window.finishTailCapture=()=>{
      clearInterval(window.tailCaptureTimer);
      const capture=window.tailCapture;
      return {start: capture.start,samples:capture.samples.filter(sample=>sample.time>=capture.start).map(sample=>({elapsed_ms:sample.time-capture.start,rms:sample.rms,running:sample.running}))};
    };
  });
  const state=()=>page.evaluate(()=>window.atmoDebug);
  const until=(fn,arg)=>page.waitForFunction(fn,arg,{timeout:20000});
  const command=value=>page.evaluate(value=>window.Atmo.command(value),value);
  const measure=samples=>{
    assert(samples.length>3,'Each measurement window must contain multiple actual output samples');
    const power=[0,0],peak=[0,0];
    for(const sample of samples)sample.rms.forEach((value,channel)=>{power[channel]+=value*value/samples.length;peak[channel]=Math.max(peak[channel],value);});
    return {samples:samples.length,rms:power.map(Math.sqrt),combined_rms:Math.sqrt((power[0]+power[1])/2),peak:Math.max(...peak),running:samples.some(sample=>sample.running)};
  };
  const baseline=async()=>{
    const samples=[];
    for(let i=0;i<20;i++){samples.push(await page.evaluate(()=>window.audioSample()));await page.waitForTimeout(20);}
    return measure(samples);
  };
  const median=values=>[...values].sort((a,b)=>a-b)[Math.floor(values.length/2)];
  const result={method:{clip_seconds:.5,maximum_early_delay_seconds:.5,diffusion_delay_seconds:.019,initial_window_ms:[0,350],late_window_ms:[1200,2400],settings:{master:1,ambience:0,footsteps:.75},note:'Output is measured after source playback and maximum early delays; estimated RT60 values are not measured decay calibration.'},levels:{}};
  fs.mkdirSync('test-results',{recursive:true});
  try{
    await page.goto('http://127.0.0.1:8060/?debug=1');
    await until(()=>window.atmoDebug?.ready);
    await page.locator('#start').click();
    for(const setting of ['setting:master:1','setting:ambience:0','setting:footsteps:0.75','setting:quality:1'])await command(setting);
    await until(()=>window.atmoDebug.settings.master===1&&window.atmoDebug.settings.ambience===0&&window.atmoDebug.settings.footsteps===.75);
    for(const level of ['cistern','forest']){
      const trials=[];
      for(let trial=0;trial<3;trial++){
        const generation=(await state()).generation;
        await command('play:'+level);
        await until(previous=>window.atmoDebug.started&&!window.atmoDebug.paused&&window.atmoDebug.generation>previous,generation);
        if((await state()).map_visible)await page.keyboard.press('m',{delay:60});
        await page.waitForTimeout(2400);
        const before=await state();
        assert.equal(before.level,level);assert.equal(before.debug_enabled,false);
        assert.equal(before.map_visible,false);
        assert(Array.isArray(before.diagnostics.room.decay_bands)&&before.diagnostics.room.decay_bands.length===3,'The current export must expose the new three-band model');
        const noise=await baseline();
        await page.evaluate(()=>window.armTailCapture());
        await page.keyboard.press('e',{delay:70});
        await page.waitForTimeout(2500);
        const capture=await page.evaluate(()=>window.finishTailCapture());
        assert(capture.start!==null,'Measurement timing must begin at the actual physical key event');
        const initial=measure(capture.samples.filter(sample=>sample.elapsed_ms<=350));
        const late=measure(capture.samples.filter(sample=>sample.elapsed_ms>=1200&&sample.elapsed_ms<=2400));
        const after=await state();
        assert.equal(after.punches,before.punches+1);assert.equal(after.event,'punch_air');
        assert.equal(after.steps,before.steps,'No footfall may contaminate the stationary pulse measurement');
        assert.deepEqual(after.position,before.position,'The test must not move or teleport the listener');
        assert(initial.running&&initial.rms.every((value,index)=>value>noise.rms[index]*10),'The real punch must clearly exceed the measured idle baseline in both stereo channels');
        const tailAboveNoise=Math.sqrt(Math.max(0,late.combined_rms**2-noise.combined_rms**2));
        trials.push({trial,room:before.diagnostics.room,baseline:noise,initial,late,normalized_tail:tailAboveNoise/initial.peak,
          tail_to_baseline_db:late.combined_rms>0&&noise.combined_rms>0?20*Math.log10(late.combined_rms/noise.combined_rms):null,
          late_digital_silence:late.combined_rms===0,capture:capture.samples});
      }
      result.levels[level]={trials,normalized_tail:median(trials.map(trial=>trial.normalized_tail)),late_rms:median(trials.map(trial=>trial.late.combined_rms)),baseline_rms:median(trials.map(trial=>trial.baseline.combined_rms)),room:trials[0].room};
    }
    const inside=result.levels.cistern,outside=result.levels.forest;
    result.normalized_indoor_outdoor_ratio=outside.normalized_tail>0?inside.normalized_tail/outside.normalized_tail:null;
    result.outdoor_late_digital_silence=outside.late_rms===0;
    fs.writeFileSync('test-results/reverb-browser.json',JSON.stringify(result,null,2));
    console.log('MEASURED',JSON.stringify({cistern:{tail:inside.late_rms,baseline:inside.baseline_rms,normalized:inside.normalized_tail,decays:inside.room.decay_bands},forest:{tail:outside.late_rms,baseline:outside.baseline_rms,normalized:outside.normalized_tail,decays:outside.room.decay_bands},normalized_ratio:result.normalized_indoor_outdoor_ratio}));
    assert(inside.late_rms>inside.baseline_rms*3,'The isolated indoor late tail must measurably exceed its real idle baseline');
    assert(inside.normalized_tail>outside.normalized_tail*2,'Indoor normalized late output must exceed the open forest by more than6dB, or exceed its measured digital silence');
    assert(inside.room.decay_bands.every((value,index)=>value>outside.room.decay_bands[index]),'Indoor geometry must yield longer estimates in all three bands');
    assert(new Set(inside.room.decay_bands).size===3,'Indoor diagnostics must expose three distinct frequency decay estimates');
    assert.notDeepEqual(inside.room.absorption,outside.room.absorption,'Different material distributions must affect the measured geometry model');
    assert.deepEqual(errors,[]);
    result.result='PASS: actual isolated stereo late tail survives after clip/early echoes, exceeds baseline, and is stronger indoors than outdoors; three-band material diagnostics differ';
    fs.writeFileSync('test-results/reverb-browser.json',JSON.stringify(result,null,2));
    console.log(result.result);
  }catch(error){
    result.failure={message:error.message,state:await state(),errors};
    fs.writeFileSync('test-results/reverb-browser.json',JSON.stringify(result,null,2));
    console.error('FAIL',error.message,'ERRORS',errors);throw error;
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
