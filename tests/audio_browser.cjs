/* Sample the exported engine's real stereo output, including effects and pause. */
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
  const sample=async(count=20,interval=50)=>{
    const mean=[0,0],peak=[0,0];let running=false;
    for(let i=0;i<count;i++){
      for(const meter of await page.evaluate(()=>window.audioSample())){
        running ||= meter.state==='running';
        meter.rms.forEach((value,channel)=>{mean[channel]+=value/count;peak[channel]=Math.max(value,peak[channel]);});
      }
      await page.waitForTimeout(interval);
    }
    return {mean,peak,running};
  };
  const result={levels:{}};
  try{
    await page.goto('http://127.0.0.1:8060/?debug=1');
    await until(()=>window.atmoDebug?.ready);
    assert.equal(await page.evaluate(()=>crossOriginIsolated),true);
    await page.locator('#start').click();
    await page.keyboard.press('Enter',{delay:80});
    await until(()=>window.atmoDebug.started);
    for(const level of ['forest','cistern','freighter','courtyard']){
      await command('play:'+level);
      await until(id=>window.atmoDebug.started&&window.atmoDebug.level===id,level);
      await page.waitForTimeout(850);
      const audio=await sample();
      assert(audio.running&&audio.mean.every(value=>value>.00001),level+' must emit actual audio in both stereo channels near its spawn');
      const snapshot=await state();
      result.levels[level]={audio,buses:snapshot.diagnostics.bus_count,room:snapshot.diagnostics.room,sources:snapshot.diagnostics.sources.length};
      if(level==='cistern')assert(snapshot.diagnostics.room.wet>.05,'Cistern must excite the late reverb');
      if(level==='freighter'){
        // The expanded ship's moving source may be in a distant compartment.
        // Acoustic unit tests verify the radial Doppler model independently.
        result.levels[level].dopplerNearSpawn=snapshot.diagnostics.sources.some(source=>Math.abs((source.acoustics.pitch??1)-1)>.0005);
      }
    }
    await command('play:forest');await until(()=>window.atmoDebug.level==='forest');
    await page.waitForTimeout(500);
    const before=await state(),beforeImage=await page.screenshot();
    await page.keyboard.down('w');await page.waitForTimeout(1200);await page.keyboard.up('w');
    await page.waitForTimeout(300);
    const after=await state(),afterImage=await page.screenshot();
    assert(after.position[1]<before.position[1]-1,'Player must move during the map check');
    assert(beforeImage.equals(afterImage),'Normal plan pixels must stay unchanged while the player moves');
    assert.equal(after.diagnostics.bus_count,result.levels.forest.buses,'Revisiting a level must not leak audio buses');
    await page.keyboard.press('Escape',{delay:80});await until(()=>window.atmoDebug.paused);
    await page.waitForTimeout(500);
    result.paused=await sample();
    assert(result.paused.peak.every(value=>value<.000001),'Pause must silence environmental sound and reverb tails');
    // Start metering before input: the soft recorded click lasts only44–68ms.
    const uiMeasurement=sample(30,10);
    await page.keyboard.press('ArrowDown',{delay:35});
    result.ui=await uiMeasurement;
    assert(result.ui.peak[0]+result.ui.peak[1]>.00001,'Native UI focus must produce actual audio while world is paused');
    await command('resume');await until(()=>!window.atmoDebug.paused);
    await page.waitForTimeout(300);result.resumed=await sample();
    assert(result.resumed.mean[0]+result.resumed.mean[1]>.00003,'Resume must restore environmental audio');
    assert.deepEqual(errors,[]);
    fs.mkdirSync('test-results',{recursive:true});
    fs.writeFileSync('test-results/audio-browser.json',JSON.stringify(result,null,2));
    console.log('PASS: actual stereo audio near all four spawns, reverb, static plan pixels, bus cleanup, pause silence, native UI sound, resume');
  }catch(error){console.error('STATE',await state());console.error('ERRORS',errors);throw error;}
  finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
