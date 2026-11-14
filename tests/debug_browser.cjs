/* Regression test of live acoustic debugging in the actual Godot Web export. */
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {execFileSync}=require('node:child_process');

(async()=>{
  const browser=await chromium.launch({headless:true});
  const page=await browser.newPage({viewport:{width:1280,height:900}});
  const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  page.on('console',m=>{if(m.type()==='error'&&!m.text().includes('Blocking on the main thread'))errors.push(m.text());});
  await page.addInitScript(()=>{
    window.audioMeters=[];
    const original=AudioNode.prototype.connect;
    AudioNode.prototype.connect=function(destination,...args){
      if(destination instanceof AudioDestinationNode&&!this.__metered){
        this.__metered=true;
        const meter=this.context.createAnalyser();meter.fftSize=2048;
        original.call(this,meter);
        window.audioMeters.push(meter);
      }
      return original.call(this,destination,...args);
    };
    window.readAudio=()=>window.audioMeters.reduce((sum,meter)=>{
      const a=new Float32Array(meter.fftSize);meter.getFloatTimeDomainData(a);
      return sum+Math.sqrt(a.reduce((s,v)=>s+v*v,0)/a.length);
    },0);
    const pads=[];
    Object.defineProperty(navigator,'getGamepads',{value:()=>pads});
    window.padConnect=()=>{
      const pad={id:'Acoustic debug test standard gamepad',index:0,connected:true,mapping:'standard',timestamp:performance.now(),axes:[0,0,0,0],buttons:Array.from({length:17},()=>({pressed:false,touched:false,value:0}))};
      pads[0]=pad;
      const event=new Event('gamepadconnected');Object.defineProperty(event,'gamepad',{value:pad});window.dispatchEvent(event);
    };
    window.padButton=(index,pressed)=>{pads[0].buttons[index]={pressed,touched:pressed,value:pressed?1:0};pads[0].timestamp=performance.now();};
  });
  fs.mkdirSync('test-results',{recursive:true});fs.writeFileSync('test-results/.gdignore','');
  const state=()=>page.evaluate(()=>window.atmoDebug);
  const until=predicate=>page.waitForFunction(predicate,null,{timeout:20000});
  const screenshot=async(name)=>{
    const file='test-results/'+name+'.png';
    await page.screenshot({path:file});
    const stats=JSON.parse(execFileSync('python',['-c',
      'from PIL import Image; import json,sys; im=Image.open(sys.argv[1]).convert("RGB"); raw=iter(im.tobytes()); print(json.dumps({"nonblack":sum(max(v)>3 for v in zip(raw,raw,raw)),"pixels":im.width*im.height,"extrema":im.getextrema()}))',file],{encoding:'utf8'}));
    return stats;
  };
  const press=async(key)=>page.keyboard.press(key,{delay:80});
  const padPress=async(index)=>{
    await page.evaluate(i=>window.padButton(i,true),index);await page.waitForTimeout(100);
    await page.evaluate(i=>window.padButton(i,false),index);await page.waitForTimeout(250);
  };
  const audio=async()=>{
    let total=0;for(let i=0;i<8;i++){total+=await page.evaluate(()=>window.readAudio());await page.waitForTimeout(100);}
    return total/8;
  };
  const continuity=(before,after)=>{
    assert.deepEqual(after.position,before.position,'Toggling must preserve listener position');
    assert.equal(after.steps,before.steps,'Toggling must not reset footsteps');
    assert.equal(after.generation,before.generation,'Toggling must not reload the level');
    assert.equal(after.diagnostics.bus_count,before.diagnostics.bus_count,'Debugging must not allocate audio buses');
    if(Number.isFinite(before.elapsed)&&Number.isFinite(after.elapsed))assert(after.elapsed>=before.elapsed,'Toggling must not reset the simulation clock');
  };
  const result={levels:{}};
  const command=async(value)=>page.evaluate(v=>window.Atmo.command(v),value);
  try{
    await page.goto('http://127.0.0.1:8060/?debug=1');
    await until(()=>window.atmoDebug?.ready&&window.atmoDebug.ui_screen==='main');
    await page.locator('#start').click();
    await command('play:cistern');
    await until(()=>window.atmoDebug.started&&!window.atmoDebug.paused&&window.atmoDebug.level==='cistern');
    await page.waitForTimeout(900);
    assert.equal((await state()).debug_enabled,false);
    assert.equal((await state()).map_visible,true);
    result.initialPlan=await screenshot('native-debug-plan-before');
    assert(result.initialPlan.nonblack>5000,'Native plan should be visible by default');
    const before=await state();result.audioBefore=await audio();
    await press('F3');
    await until(()=>window.atmoDebug.debug_enabled&&window.atmoDebug.debug_visuals.source_count>=3&&window.atmoDebug.debug_visuals.segment_count>=3);
    const enabled=await state();continuity(before,enabled);
    assert.equal(enabled.map_visible,true,'Debug must preserve plan preference');
    assert(enabled.debug_visuals.reflection_count>0,'Cistern should render valid reflected paths');
    result.enabled=enabled;
    result.visibleGeometry=await screenshot('native-debug-cistern-initial');
    assert(result.visibleGeometry.nonblack>5000,'Debug geometry must render');
    assert(!fs.readFileSync('test-results/native-debug-plan-before.png').equals(fs.readFileSync('test-results/native-debug-cistern-initial.png')),'Debug should replace the static plan with geometry');
    result.audioAfter=await audio();assert(result.audioBefore>.00001&&result.audioAfter>.00001,'Audio must continue through debug toggles');
    await press('F3');await until(()=>!window.atmoDebug.debug_enabled);continuity(before,await state());
    result.restoredPlan=await screenshot('native-debug-plan-restored');
    assert(fs.readFileSync('test-results/native-debug-plan-before.png').equals(fs.readFileSync('test-results/native-debug-plan-restored.png')),'Debug exit must restore the same static plan');
    await press('m');await until(()=>!window.atmoDebug.map_visible);
    result.hiddenPlan=await screenshot('native-debug-plan-hidden');assert.equal(result.hiddenPlan.nonblack,0,'Hiding the plan should restore black gameplay');
    await page.evaluate(()=>window.padConnect());await until(()=>window.atmoDebug.controllers===1);
    await padPress(11);await until(()=>window.atmoDebug.debug_enabled);
    await padPress(11);await until(()=>!window.atmoDebug.debug_enabled);
    assert.equal((await state()).map_visible,false);
    assert.equal((await screenshot('native-debug-hidden-preference')).nonblack,0,'R3 must restore hidden-plan preference');
    await command('debug:on');await until(()=>window.atmoDebug.debug_enabled);
    await press('Escape');await until(()=>window.atmoDebug.paused&&window.atmoDebug.ui_screen==='pause');
    await screenshot('native-debug-paused-on');
    await command('debug:off');await until(()=>!window.atmoDebug.debug_enabled);
    await screenshot('native-debug-paused-off');
    assert(fs.readFileSync('test-results/native-debug-paused-on.png').equals(fs.readFileSync('test-results/native-debug-paused-off.png')),'Paused UI must hide debug geometry and paths');
    await command('debug:on');
    let maximumReflections=0;
    for(const id of ['forest','cistern','freighter','courtyard']){
      await command('play:'+id);
      await page.waitForFunction(id=>window.atmoDebug.level===id&&window.atmoDebug.started&&!window.atmoDebug.paused&&window.atmoDebug.debug_visuals.source_count>=3,id,{timeout:20000});
      await page.waitForTimeout(850);
      if(id==='cistern'){
        // The expanded arrival chamber has a two-path budget. Walk through its
        // aligned north doors to the large reservoir with a three-path landmark.
        await page.keyboard.down('Shift');await page.keyboard.down('w');
        await page.waitForTimeout(16200);
        await page.keyboard.up('w');await page.keyboard.up('Shift');await page.waitForTimeout(850);
      }
      const current=await state();
      assert(current.debug_enabled,'Debug should remain enabled across environment changes');
      maximumReflections=Math.max(maximumReflections,...current.diagnostics.sources.map(source=>source.acoustics.reflections||0));
      const image=await screenshot('native-debug-'+id);
      assert(image.nonblack>5000,id+' must render geometry');
      result.levels[id]={state:current,image};
      const beforeToggle=await state();
      await command('debug:off');await until(()=>!window.atmoDebug.debug_enabled);
      continuity(beforeToggle,await state());
      await command('debug:on');await until(()=>window.atmoDebug.debug_enabled);
      continuity(beforeToggle,await state());
      assert.deepEqual((await state()).diagnostics.sources.map(s=>s.clip),beforeToggle.diagnostics.sources.map(s=>s.clip),'Toggling must retain acoustic sources');
    }
    assert(maximumReflections>2,'At least one source should expose more than two valid reflections when geometry permits');
    result.maximumReflections=maximumReflections;
    assert.deepEqual(errors,[]);
    result.result='PASS: native static-plan restoration, F3 and R3, real geometry and live paths in four environments, more than two reflections, preserved level/audio buses/sources, continuing sound, pause hides debug, hidden-plan preference preserved';
    fs.writeFileSync('test-results/debug-browser.json',JSON.stringify(result,null,2));
    console.log(result.result);
    console.log(JSON.stringify({levels:Object.keys(result.levels),maximumReflections,audioBefore:result.audioBefore,audioAfter:result.audioAfter,visuals:result.enabled.debug_visuals},null,2));
  }catch(error){
    const current=await state();fs.writeFileSync('test-results/debug-browser-failed.json',JSON.stringify({result,state:current,errors},null,2));
    console.error('STATE',JSON.stringify(current,null,2));console.error('ERRORS',errors);throw error;
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
