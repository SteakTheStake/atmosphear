/* Focused real-output checks for quiet menu feedback and silent play controls. */
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');

(async()=>{
  const browser=await chromium.launch({headless:true});
  const page=await browser.newPage({viewport:{width:1280,height:900}});
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  page.on('console',message=>{if(message.type()==='error'&&!message.text().includes('Blocking on the main thread'))errors.push(message.text());});
  await page.addInitScript(()=>{
    const recorders=[],ready=[];
    const workletCode=`class MenuOutputMeter extends AudioWorkletProcessor {
      constructor(){super();this.recording=false;this.elapsed=0;this.port.onmessage=event=>{
        if(event.data==='start'){this.recording=true;this.elapsed=0;this.port.postMessage({armed:true});}
        if(event.data==='stop'){this.recording=false;this.port.postMessage({done:true});}
      };}
      process(inputs,outputs){
        const input=inputs[0]||[],length=(input[0]||outputs[0][0]).length;
        if(this.recording){
          const rms=[0,1].map(channel=>{
            const values=input[channel]||input[0];if(!values)return 0;
            let power=0;for(let i=0;i<values.length;i++)power+=values[i]*values[i];
            return Math.sqrt(power/values.length);
          });
          this.port.postMessage({elapsed_ms:this.elapsed/sampleRate*1000,block_ms:length/sampleRate*1000,rms,running:true});
          this.elapsed+=length;
        }
        for(const channel of outputs[0])channel.fill(0);
        return true;
      }
    };registerProcessor('menu-output-meter',MenuOutputMeter);`;
    const connect=AudioNode.prototype.connect;
    AudioNode.prototype.connect=function(destination,...args){
      if(destination instanceof AudioDestinationNode&&!this.__menuMetered){
        this.__menuMetered=true;
        const source=this,context=this.context;
        ready.push((async()=>{
          const url=URL.createObjectURL(new Blob([workletCode],{type:'application/javascript'}));
          await context.audioWorklet.addModule(url);URL.revokeObjectURL(url);
          const node=new AudioWorkletNode(context,'menu-output-meter',{numberOfInputs:1,numberOfOutputs:1,outputChannelCount:[2]});
          const recorder={node,samples:[],armed:null,done:null};
          node.port.onmessage=event=>{
            if(event.data.armed){recorder.armed?.();return;}
            if(event.data.done){recorder.done?.();return;}
            recorder.samples.push(event.data);
          };
          // A silent connected branch keeps the processor scheduled; original
          // output continues unchanged. Original connect avoids recursive taps.
          connect.call(source,node);connect.call(node,context.destination);
          recorders.push(recorder);
        })());
      }
      return connect.call(this,destination,...args);
    };
    window.beginMenuCapture=async()=>{
      await Promise.all(ready);
      if(!recorders.length)throw new Error('No actual output node connected to the destination');
      await Promise.all(recorders.map(recorder=>new Promise(resolve=>{
        recorder.samples=[];recorder.armed=resolve;recorder.node.port.postMessage('start');
      })));
    };
    window.endMenuCapture=async()=>{
      await Promise.all(recorders.map(recorder=>new Promise(resolve=>{
        recorder.done=resolve;recorder.node.port.postMessage('stop');
      })));
      return recorders.flatMap(recorder=>recorder.samples);
    };
  });
  const state=()=>page.evaluate(()=>window.atmoDebug);
  const until=(fn,arg)=>page.waitForFunction(fn,arg,{timeout:20000});
  const command=value=>page.evaluate(value=>window.Atmo.command(value),value);
  const key=async value=>{await page.keyboard.press(value,{delay:40});await page.waitForTimeout(110);};
  const capture=async action=>{
    // Arm before input: a44ms click can finish before keyboard.press resolves.
    await page.evaluate(()=>window.beginMenuCapture());
    if(action)await action();
    await page.waitForTimeout(360);
    const samples=await page.evaluate(()=>window.endMenuCapture());
    const peak=Math.max(...samples.flatMap(sample=>sample.rms));
    const active=samples.filter(sample=>Math.max(...sample.rms)>peak*.12&&peak>0);
    const active_ms=active.length?active.at(-1).elapsed_ms-active[0].elapsed_ms+active.at(-1).block_ms:0;
    return {peak,active_ms,samples};
  };
  fs.mkdirSync('test-results',{recursive:true});
  const result={};
  try{
    await page.goto('http://127.0.0.1:8060/?debug=1');
    await until(()=>window.atmoDebug?.ready);
    await page.locator('#start').click();
    await until(()=>window.atmoDebug.ui_screen==='main');
    assert.equal((await state()).settings.ui,.35,'A new player starts with very soft menu feedback');
    await page.waitForTimeout(250);
    result.focus=await capture(()=>page.keyboard.press('ArrowDown',{delay:35}));
    assert(result.focus.peak>0&&result.focus.samples.some(sample=>sample.running),'Menu focus must still produce an actual click');
    assert(result.focus.peak<.008,'Default feedback stays below0.8% full-scale measured output RMS');
    assert(result.focus.active_ms>0&&result.focus.active_ms<100,'Audio-thread measurements must show a brief click rather than a sustained tone');

    // Actual native navigation: cistern selection -> Settings -> fourth slider.
    for(let i=0;i<3;i++)await key('ArrowDown');
    await key('Enter');await until(()=>window.atmoDebug.ui_screen==='settings');
    for(let i=0;i<3;i++)await key('ArrowDown');
    for(let i=0;i<7;i++)await key('ArrowLeft');
    await until(()=>window.atmoDebug.settings.ui===0);
    await page.waitForTimeout(150);
    await page.screenshot({path:'test-results/menu-feedback-settings.png'});
    result.muted=await capture(()=>page.keyboard.press('ArrowDown',{delay:35}));
    assert(result.muted.peak<=result.focus.peak*.01,'Menu feedback slider at zero must suppress clicks by at least40dB');
    await key('ArrowUp');
    for(let i=0;i<7;i++)await key('ArrowRight');
    await until(()=>window.atmoDebug.settings.ui===.35);
    await key('Escape');await until(()=>window.atmoDebug.ui_screen==='main');
    await key('Enter');await until(()=>window.atmoDebug.started&&window.atmoDebug.level==='forest');
    for(const setting of ['setting:ambience:0','setting:footsteps:0'])await command(setting);
    await until(()=>window.atmoDebug.settings.ambience===0&&window.atmoDebug.settings.footsteps===0);
    await page.waitForTimeout(1500);
    const before=await state();
    result.playing_baseline=await capture();
    result.map_toggle=await capture(()=>page.keyboard.press('m',{delay:35}));
    const after=await state();
    assert.notEqual(after.map_visible,before.map_visible,'The map control must still work');
    assert.equal(after.steps,before.steps);assert.deepEqual(after.position,before.position);
    assert.equal(after.settings.ui,.35,'Map silence must not be implemented by changing the user menu-volume setting');
    assert(result.map_toggle.peak<=Math.max(result.playing_baseline.peak*2,result.focus.peak*.01),'A gameplay map toggle must add no menu click above the measured quiet baseline');
    await key('Escape');await until(()=>window.atmoDebug.paused&&window.atmoDebug.ui_screen==='pause');
    result.paused_focus=await capture(()=>page.keyboard.press('ArrowDown',{delay:35}));
    assert(result.paused_focus.peak>result.focus.peak*.05,'Feedback returns for actual pause-menu navigation');
    await key('Escape');await until(()=>!window.atmoDebug.paused&&window.atmoDebug.ui_screen==='playing');
    assert.equal((await state()).map_visible,after.map_visible,'Pause/resume preserves the chosen map visibility');
    assert.deepEqual(errors,[]);
    result.result='PASS: soft brief recorded menu clicks, real native menu-volume slider mute/restore, silent gameplay map toggle, and pause-menu/resume behavior';
    fs.writeFileSync('test-results/context-audio-browser.json',JSON.stringify(result,null,2));
    console.log('MEASURED',JSON.stringify(Object.fromEntries(Object.entries(result).filter(([,value])=>value&&typeof value==='object').map(([name,value])=>[name,{peak:value.peak,active_ms:value.active_ms}]))));
    console.log(result.result);
  }catch(error){
    result.failure={message:error.message,state:await state(),errors};
    fs.writeFileSync('test-results/context-audio-browser.json',JSON.stringify(result,null,2));
    await page.screenshot({path:'test-results/context-audio-failure.png'});
    console.error('FAIL',error.message,'ERRORS',errors);throw error;
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
