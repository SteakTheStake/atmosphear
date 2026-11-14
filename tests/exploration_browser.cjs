/* Real keyboard routes with a black playfield; no teleport or location UI. */
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
      if(destination instanceof AudioDestinationNode&&!this.__metered){
        this.__metered=true;
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
    window.audioSample=()=>window.audioMeters.map(({context,meters})=>({
      state:context.state,
      rms:meters.map(meter=>{
        const values=new Float32Array(meter.fftSize);meter.getFloatTimeDomainData(values);
        return Math.sqrt(values.reduce((sum,value)=>sum+value*value,0)/values.length);
      })
    }));
  });
  const state=()=>page.evaluate(()=>window.atmoDebug);
  const until=(fn,arg)=>page.waitForFunction(fn,arg,{timeout:20000});
  const command=value=>page.evaluate(value=>window.Atmo.command(value),value);
  const byAnchor=s=>new Map(s.diagnostics.sources.map(source=>[source.anchor,source]));
  const active=s=>s.diagnostics.sources.filter(source=>!source.virtualized).map(source=>source.anchor);
  const summary=s=>({position:s.position,steps:s.steps,surface:s.surface,last_step_clip:s.last_step_clip,
    map_visible:s.map_visible,debug_enabled:s.debug_enabled,generation:s.generation,
    room:s.diagnostics.room,buses:s.diagnostics.bus_count,active:active(s),
    landmarks:s.diagnostics.sources.filter(source=>source.landmark)});
  const sample=async(count=8,interval=50)=>{
    const mean=[0,0],peak=[0,0];let running=false;
    for(let i=0;i<count;i++){
      for(const meter of await page.evaluate(()=>window.audioSample())){
        running ||= meter.state==='running';
        meter.rms.forEach((value,channel)=>{mean[channel]+=value/count;peak[channel]=Math.max(peak[channel],value);});
      }
      await page.waitForTimeout(interval);
    }
    return {mean,peak,running};
  };
  const assertAudio=(audio,label)=>assert(audio.running&&audio.mean.every(value=>value>.00001),label+' emits actual audio in both stereo channels');
  const hidePlan=async()=>{
    if((await state()).map_visible)await page.keyboard.press('m',{delay:75});
    await until(()=>!window.atmoDebug.map_visible&&!window.atmoDebug.debug_enabled);
  };
  const walk=async(key,milliseconds)=>{
    const samples=[];
    await page.keyboard.down('Shift');await page.keyboard.down(key);
    const started=Date.now();
    try{
      while(Date.now()-started<milliseconds){
        const snapshot=await state();
        assert.equal(snapshot.map_visible,false,'The whole route must keep the navigation plan hidden');
        assert.equal(snapshot.debug_enabled,false,'The whole route must keep developer geometry hidden');
        samples.push({elapsed_ms:Date.now()-started,position:snapshot.position,steps:snapshot.steps,
          surface:snapshot.surface,active:active(snapshot),room:snapshot.diagnostics.room,
          audio:await page.evaluate(()=>window.audioSample())});
        await page.waitForTimeout(240);
      }
    }finally{
      await page.keyboard.up(key);await page.keyboard.up('Shift');
    }
    await page.waitForTimeout(400);
    assert(samples.length>20,'The route must sample sustained real movement');
    const audible=samples.filter(sample=>sample.audio.some(meter=>meter.state==='running'&&meter.rms.every(value=>value>.000001)));
    assert(audible.length>=samples.length*.9,'Both stereo channels must remain audible throughout at least90% of the route samples');
    return {duration_ms:Date.now()-started,samples,after:await state(),audio:await sample()};
  };
  fs.mkdirSync('test-results',{recursive:true});
  const result={scope:'Real held-key traversal, floor changes, active source transitions, and output audio. This does not measure human wayfinding success.'};
  try{
    await page.goto('http://127.0.0.1:8060/?debug=1');
    await until(()=>window.atmoDebug?.ready);
    await page.locator('#start').click();
    await page.keyboard.press('ArrowDown');await page.keyboard.press('Enter',{delay:80});await until(()=>window.atmoDebug.ui_screen==='legacy');await page.keyboard.press('Enter',{delay:80});
    await until(()=>window.atmoDebug.started&&window.atmoDebug.level==='forest');
    await hidePlan();await page.waitForTimeout(500);
    const entry=await state();
    assert.equal(entry.surface,'gravel');
    const blackFrame=await page.screenshot({path:'test-results/exploration-black-start.png'});
    const entryAudio=await sample();assertAudio(entryAudio,'Forest clearing');
    const outward=await walk('w',10000);
    assert(outward.after.position[1]>=-6&&outward.after.position[1]<=12,'Ten seconds running must reach the boardwalk interior');
    assert(Math.abs(outward.after.position[0]-entry.position[0])<.5,'The central route must stay unobstructed');
    assert.equal(outward.after.surface,'wood');
    assert.match(outward.after.last_step_clip,/wood/);
    assert(outward.after.steps>entry.steps+20,'Sustained movement must produce repeated footsteps');
    assertAudio(outward.audio,'Forest boardwalk');
    const entrySources=byAnchor(entry),boardwalkSources=byAnchor(outward.after);
    const woke=outward.after.diagnostics.sources.filter(source=>!source.virtualized&&entrySources.get(source.anchor)?.virtualized).map(source=>source.anchor);
    const slept=entry.diagnostics.sources.filter(source=>!source.virtualized&&boardwalkSources.get(source.anchor)?.virtualized).map(source=>source.anchor);
    assert(woke.length>=3&&slept.length>=3,'Approaching the boardwalk must wake new details and suspend distant entry details');
    assert(woke.some(anchor=>boardwalkSources.get(anchor).landmark),'A previously distant landmark must wake during the route');
    assert(blackFrame.equals(await page.screenshot()),'Gameplay pixels must remain black despite movement and source activation');
    const homeward=await walk('s',10000);
    assert(Math.abs(homeward.after.position[1]-entry.position[1])<2,'Returning along the same route must reach the clearing');
    assert.equal(homeward.after.surface,'gravel');
    assert.match(homeward.after.last_step_clip,/gravel/);
    assertAudio(homeward.audio,'Returned forest clearing');
    const returnSources=byAnchor(homeward.after);
    assert(slept.every(anchor=>!returnSources.get(anchor).virtualized),'All entry details suspended during travel must wake again on return');
    assert(woke.some(anchor=>boardwalkSources.get(anchor).landmark&&returnSources.get(anchor).virtualized),'A distant landmark must suspend again after returning out of range');
    const entryBeacon=entrySources.get('ClearingWindBeacon'),returnBeacon=returnSources.get('ClearingWindBeacon');
    assert(!returnBeacon.virtualized&&Math.abs(returnBeacon.acoustics.distance-entryBeacon.acoustics.distance)<2,'The original fixed clearing landmark must remain active at its original relative distance on return');
    assert.equal(homeward.after.diagnostics.bus_count,entry.diagnostics.bus_count,'Travel and source activation must not allocate more buses');
    assert.equal(homeward.after.generation,entry.generation,'Traversal must not reload the world');
    result.forest={entry:summary(entry),entry_audio:entryAudio,outward:{...outward,after:summary(outward.after)},homeward:{...homeward,after:summary(homeward.after)},woke,slept};
    await page.screenshot({path:'test-results/exploration-black-return.png'});

    await command('play:freighter');await until(()=>window.atmoDebug.level==='freighter'&&window.atmoDebug.started);
    await hidePlan();await page.waitForTimeout(500);
    const airlock=await state();assert.equal(airlock.surface,'stone');
    const workshop=await walk('w',8000);
    assert(workshop.after.position[1]>=-6&&workshop.after.position[1]<=8,'The connected doors must allow an uninterrupted airlock-to-workshop route');
    assert(Math.abs(workshop.after.position[0]-airlock.position[0])<.5);
    assert.equal(workshop.after.surface,'metal');assert.match(workshop.after.last_step_clip,/metal/);
    assert(workshop.after.steps>airlock.steps+18);
    assertAudio(workshop.audio,'Freighter workshop');
    const airlockSources=byAnchor(airlock),workshopSources=byAnchor(workshop.after);
    const shipWoke=workshop.after.diagnostics.sources.filter(source=>!source.virtualized&&airlockSources.get(source.anchor)?.virtualized).map(source=>source.anchor);
    assert(shipWoke.some(anchor=>anchor.startsWith('Servo')),'Approaching the workshop must activate its local details');
    assert(workshopSources.get('Servo workshop').acoustics.distance<airlockSources.get('Servo workshop').acoustics.distance-20,'The fixed workshop landmark must become physically closer');
    assert(workshopSources.get('Servo workshop').acoustics.cutoff>airlockSources.get('Servo workshop').acoustics.cutoff+1000,'The workshop landmark must become spectrally clearer along the real doorway route');
    assert(Math.abs(workshop.after.diagnostics.room.wet-airlock.diagnostics.room.wet)>.02,'The different connected rooms must change the receiving reverb');
    assert.equal(workshop.after.diagnostics.bus_count,airlock.diagnostics.bus_count);
    assert.equal(workshop.after.generation,airlock.generation);
    assert(blackFrame.equals(await page.screenshot({path:'test-results/exploration-black-workshop.png'})),'Interior exploration must also keep a black playfield');
    result.freighter={entry:summary(airlock),outward:{...workshop,after:summary(workshop.after)},woke:shipWoke};
    assert.deepEqual(errors,[]);
    result.result='PASS: hidden-plan forest round trip and connected freighter route, surface footsteps, real stereo audio, source wake/sleep/return, room changes, and stable source/bus allocation';
    fs.writeFileSync('test-results/exploration-browser.json',JSON.stringify(result,null,2));
    console.log(result.result);
  }catch(error){
    result.failure={message:error.message,state:await state(),errors};
    fs.writeFileSync('test-results/exploration-browser.json',JSON.stringify(result,null,2));
    await page.screenshot({path:'test-results/exploration-failure.png'});
    console.error('FAIL',error.message,'STATE',JSON.stringify(summary(await state())),'ERRORS',errors);throw error;
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
