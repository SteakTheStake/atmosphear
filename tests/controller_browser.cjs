/* Controller routing through the real exported Godot game.
 * Synthetic pads do not grant native browser activation. This test explicitly
 * permits autoplay, and all CDP evaluation uses userGesture:false. The separate
 * default-policy launch test checks that blocked audio cannot start silently.
 * Usage: node tests/controller_browser.cjs [build/pages | https://host/game/]
 */
const {chromium,devices}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const http=require('node:http');

const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));

async function serve(target){
  if(/^https?:\/\//.test(target))return {base:target,close:async()=>{}};
  const directory=path.resolve(target),prefix='/atmosphear-controller-check/';
  const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript','.json':'application/json','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.svg':'image/svg+xml'};
  const server=http.createServer((request,response)=>{
    const pathname=new URL(request.url,'http://localhost').pathname;
    if(pathname==='/favicon.ico'){response.writeHead(204);response.end();return;}
    if(!pathname.startsWith(prefix)){response.writeHead(404);response.end();return;}
    let relative=decodeURIComponent(pathname.slice(prefix.length));if(!relative||relative.endsWith('/'))relative+='index.html';
    const filename=path.resolve(directory,relative);
    if(!filename.startsWith(directory+path.sep)||!fs.existsSync(filename)||!fs.statSync(filename).isFile()){
      response.writeHead(404);response.end();return;
    }
    response.writeHead(200,{'Content-Type':mime[path.extname(filename)]||'application/octet-stream','Cache-Control':'no-cache','Content-Length':fs.statSync(filename).size});
    if(request.method==='HEAD')response.end();else fs.createReadStream(filename).pipe(response);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  return {base:`http://127.0.0.1:${server.address().port}${prefix}`,close:()=>new Promise(resolve=>server.close(resolve))};
}

(async()=>{
  const host=await serve(process.argv[2]||process.env.CONTROLLER_URL||'build/pages');
  const browser=await chromium.launch({headless:true,args:['--autoplay-policy=no-user-gesture-required']});
  const mobile=process.env.ATMO_DEVICE;
  const context=await browser.newContext(mobile?{...devices[mobile]}:{viewport:{width:1280,height:900}});
  const page=await context.newPage();
  const cdp=await context.newCDPSession(page);
  const errors=[],checks=[];
  const report={url:host.base,mobile_emulation:mobile||null,browser_engine:'Chromium (device emulation does not test Android/iOS hardware or Safari)',controller:'simulated standard Gamepad API',audio_policy:'Chromium autoplay override for input routing only',real_browser_user_activation_tested:false,evaluation_user_gesture:false,checks,levels:{}};
  fs.mkdirSync('test-results',{recursive:true});
  page.on('pageerror',error=>errors.push(error.message));
  page.on('console',message=>{
    if((message.type()==='error'||/SCRIPT ERROR|Parse Error|Failed to load/.test(message.text()))&&!message.text().includes('Blocking on the main thread'))errors.push(message.text());
  });
  await page.addInitScript(()=>{
    const pads=[];
    let active=0;
    const inputs={keyboard:0,mouse:0,touch:0};
    for(const type of ['keydown','keyup'])addEventListener(type,()=>inputs.keyboard++,true);
    for(const type of ['mousedown','mouseup','click'])addEventListener(type,()=>inputs.mouse++,true);
    addEventListener('touchstart',()=>inputs.touch++,true);
    Object.defineProperty(navigator,'getGamepads',{value:()=>pads});
    const test=window.__controllerTest={inputs,meters:[],connect(index=0){
      active=index;
      const pad={id:'Atmosphear simulated standard controller',index,connected:true,mapping:'standard',timestamp:performance.now(),axes:[0,0,0,0],buttons:Array.from({length:17},()=>({pressed:false,touched:false,value:0}))};
      pads[index]=pad;
      const event=new Event('gamepadconnected');Object.defineProperty(event,'gamepad',{value:pad});dispatchEvent(event);
    },disconnect(){
      const pad=pads[active];if(!pad)return;
      pad.connected=false;pads[active]=null;
      const event=new Event('gamepaddisconnected');Object.defineProperty(event,'gamepad',{value:pad});dispatchEvent(event);
    },button(index,pressed){
      const pad=pads[active];pad.buttons[index]={pressed,touched:pressed,value:pressed?1:0};pad.timestamp=performance.now();
    },axis(index,value){pads[active].axes[index]=value;pads[active].timestamp=performance.now();}};
    const connect=AudioNode.prototype.connect;
    AudioNode.prototype.connect=function(destination,...args){
      if(destination instanceof AudioDestinationNode&&!this.__controllerMetered){
        this.__controllerMetered=true;
        const splitter=this.context.createChannelSplitter(2);connect.call(this,splitter);
        const channels=[0,1].map(channel=>{
          const meter=this.context.createAnalyser();meter.fftSize=2048;connect.call(splitter,meter,channel);return meter;
        });
        test.meters.push({context:this.context,channels});
      }
      return connect.call(this,destination,...args);
    };
    test.audio=()=>test.meters.map(({context,channels})=>({state:context.state,rms:channels.map(meter=>{
      const values=new Float32Array(meter.fftSize);meter.getFloatTimeDomainData(values);
      return Math.sqrt(values.reduce((sum,value)=>sum+value*value,0)/values.length);
    })}));
  });

  // Playwright's normal evaluate/waitForFunction can request a browser user
  // gesture. Use CDP explicitly for every read, poll, and injected pad change.
  const evaluate=async(fn,arg)=>{
    const response=await cdp.send('Runtime.evaluate',{expression:`(${fn.toString()})(${JSON.stringify(arg)??'undefined'})`,returnByValue:true,awaitPromise:true,userGesture:false});
    if(response.exceptionDetails)throw new Error(response.exceptionDetails.exception?.description||response.exceptionDetails.text);
    return response.result.value;
  };
  const snapshot=()=>evaluate(()=>{
    const source=window.atmoDebug;
    const game=source?{...source,diagnostics:{bus_count:source.diagnostics?.bus_count,source_count:source.diagnostics?.sources?.length}}:null;
    return {game,boot:window.atmoBoot,launch_hidden:document.getElementById('launch')?.hidden,status:document.getElementById('status')?.textContent,activation:navigator.userActivation?.hasBeenActive,inputs:window.__controllerTest?.inputs};
  });
  const screenshot=async(filename)=>{
    // Playwright's screenshot preparation also evaluates page code. Capture the
    // compositor directly so screenshots cannot introduce implicit activation.
    const result=await cdp.send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
    fs.writeFileSync(filename,Buffer.from(result.data,'base64'));
  };
  const state=async()=>((await snapshot()).game);
  const until=async(fn,arg,label='condition',timeout=15000)=>{
    const start=Date.now();
    while(Date.now()-start<timeout){
      try{if(await evaluate(fn,arg))return;}catch(error){if(!/context|navigat/i.test(error.message))throw error;}
      await sleep(60);
    }
    throw new Error(`Timed out: ${label}\n${JSON.stringify(await snapshot())}`);
  };
  const screen=expected=>until(value=>window.atmoDebug?.ui_screen===value&&(value==='playing'||window.atmoDebug.ui_focus_index>=0),expected,`screen ${expected}`);
  const button=(index,pressed)=>evaluate(({index,pressed})=>window.__controllerTest.button(index,pressed),{index,pressed});
  const axis=(index,value)=>evaluate(({index,value})=>window.__controllerTest.axis(index,value),{index,value});
  const tap=async(index,hold=90)=>{await button(index,true);await sleep(hold);await button(index,false);await sleep(280);};
  const stick=async(index,value,duration=110)=>{await axis(index,value);await sleep(duration);await axis(index,0);await sleep(280);};
  const check=label=>{checks.push(label);console.log('PASS',label);};
  const focus=async(index)=>{
    for(let attempt=0;attempt<12;attempt++){
      const current=await state();
      if(current.ui_focus_index===index)return;
      assert(current.ui_control_count>index,'Requested native control must exist');
      await tap(13);
    }
    assert.equal((await state()).ui_focus_index,index,'Controller must reach native focus target');
  };
  const noOtherInput=async()=>{
    const current=await snapshot();
    assert.equal(current.activation,false,'CDP/synthetic pads must never grant browser user activation');
    assert.deepEqual(current.inputs,{keyboard:0,mouse:0,touch:0},'No keyboard, pointer, or touch events may drive this test');
  };
  const launch=async(index)=>{
    await until(()=>window.atmoDebug?.ready&&window.atmoBoot?.phase!=='loading',null,'engine ready',90000);
    assert.equal((await snapshot()).launch_hidden,false,'Launcher must initially cover native menus');
    await evaluate(()=>window.__controllerTest.connect());
    await button(index,true);
    await until(()=>window.atmoBoot?.activated===true,null,'controller launches overlay');
    await sleep(850);
    let current=await snapshot();
    assert.equal(current.boot.audio_state,'running','Overlay may dismiss only with a running audio context');
    assert.equal(current.launch_hidden,true);
    assert.equal(current.game.started,false,'Held launch button must not select an environment');
    assert.equal(current.game.ui_screen,'main');
    assert.equal(current.game.host_input_ready,false,'Held launch input remains gated');
    await button(index,false);
    await until(()=>window.atmoBoot?.controller_input_ready&&window.atmoDebug?.host_input_ready&&window.atmoDebug.ui_focus_index===0,null,'release arms controller and native focus');
    if(mobile){assert((await evaluate(()=>location.pathname)).includes('/mobile/'),'Phone must select the mobile build');assert.equal(await evaluate(()=>crossOriginIsolated),false,'Mobile export must work without cross-origin isolation');}
    await noOtherInput();
  };
  const play=async(index,id)=>{
    await screen(id==='template'?'main':'legacy');await focus(index);
    const generation=(await state()).generation;
    await button(0,true);
    await until(value=>window.atmoDebug?.level===value&&window.atmoDebug?.ui_screen==='playing',id,`enter ${id}`);
    await sleep(850);
    const current=await state();
    assert.equal(current.generation,generation+1,'Held confirm loads an environment exactly once');
    assert.equal(current.jumps,0,'Held environment confirmation must not also jump');
    assert(id==='template'?current.scene_source===current.main_level_scene:current.scene_source.endsWith(`/legacy/${id}.tscn`));
    await button(0,false);await sleep(350);
    const mean=[0,0];let running=false;
    for(let i=0;i<12;i++){
      for(const meter of await evaluate(()=>window.__controllerTest.audio())){
        running ||= meter.state==='running';meter.rms.forEach((value,channel)=>mean[channel]+=value/12);
      }
      await sleep(50);
    }
    assert(running,'Audio context must run');if(id!=='template')assert(mean.every(value=>value>1e-6),`${id} must produce actual stereo audio`);
    const renderer=await evaluate(()=>window.AtmoAcoustics.snapshot());assert.equal(renderer.version,2);if(id!=='template')assert(renderer.active>0);assert.deepEqual(renderer.errors,[]);assert.equal(renderer.room_fields,current.region_count);
    report.levels[id]={renderer,generation:current.generation,scene:current.scene_source,stereo_rms:mean};
    check(`Controller enters ${id}; held confirm causes no jump; stereo output runs`);
  };
  const pause=async()=>{await tap(9);await screen('pause');};
  const chooser=async()=>{await pause();await focus(2);await tap(0);await screen('main');await focus(1);await tap(0);await screen('legacy');};

  try{
    const url=new URL(host.base);url.searchParams.set('debug','1');
    await page.goto(url.href,{waitUntil:'domcontentloaded'});
    await launch(0);
    check('A launches from the overlay without native activation, and release gates menu input');
    assert.equal((await state()).ui_focus_index,0);
    await tap(12);assert.equal((await state()).ui_focus_index,2,'D-pad up wraps to Settings');
    await tap(13);assert.equal((await state()).ui_focus_index,0,'D-pad down wraps to Forest');
    await stick(1,.2,300);assert.equal((await state()).ui_focus_index,0,'Stick drift below dead zone does not navigate');
    await stick(1,.8);assert.equal((await state()).ui_focus_index,1,'One stick edge moves exactly one item');
    await stick(1,-.8);assert.equal((await state()).ui_focus_index,0);
    await stick(1,.8,590);const repeated=(await state()).ui_focus_index;
    assert(repeated>=0&&repeated<3&&repeated!==1,'Held stick repeats after the navigation delay');
    await sleep(350);assert.equal((await state()).ui_focus_index,repeated,'Neutral stick stops navigation repeat');
    check('D-pad wrap, stick dead zone, single edges, delayed repeat, and neutral release');
    await screenshot('test-results/controller-main.png');await noOtherInput();

    await focus(2);await tap(0);await screen('settings');
    const settings=[['master',1,.05],['ambience',1,.05],['footsteps',1,.05],['ui',1,.05],['sensitivity',2,.1],['speed',1.5,.1]];
    for(let i=0;i<settings.length;i++){
      const [key,max,step]=settings[i];await focus(i);
      const before=(await state()).settings[key],direction=before>=max-.001?-1:1;
      if(i%2===0)await tap(direction<0?14:15);else await stick(0,direction*.8);
      const value=(await state()).settings[key];
      assert(Math.abs(value-(before+step*direction))<.001,`${key} changes exactly once by its authored step`);
    }
    await focus(6);const quality=(await state()).settings.quality;await tap(0);
    assert.notEqual((await state()).settings.quality,quality,'A toggles full acoustic detail');
    await tap(0);assert.equal((await state()).settings.quality,quality);
    await focus(7);const debug=(await state()).debug_enabled;await tap(0);
    assert.equal((await state()).debug_enabled,!debug,'A toggles developer visualization');
    await tap(0);assert.equal((await state()).debug_enabled,debug);
    await screenshot('test-results/controller-settings.png');await noOtherInput();
    report.saved_settings={...(await state()).settings};
    await focus(8);const binaural=(await state()).settings.binaural;await tap(0);assert.notEqual((await state()).settings.binaural,binaural);await until(()=>window.AtmoAcoustics.mode===(window.atmoDebug.settings.binaural>.5?"headphones":"speakers"),null,"renderer switches output mode");await tap(0);
    report.saved_settings={...(await state()).settings};await focus(9);await tap(0);await screen('main');
    check('All six settings sliders, quality/debug toggles, and Done work using controller focus');

    await play(0,'template');check('Default main choice loads the editable template');
    await chooser();await play(0,'forest');
    const beforeWalk=await state();await stick(1,-.85,1000);const walked=await state();
    assert(walked.position[1]<beforeWalk.position[1]-.5&&walked.steps>beforeWalk.steps,'Left stick walks with footsteps');
    const yaw=walked.yaw;await stick(2,.8,400);assert(Math.abs((await state()).yaw-yaw)>.1,'Right stick turns');
    await button(4,true);await axis(1,-.8);await until(()=>window.atmoDebug.locomotion==='run',null,'LB runs');
    await axis(1,0);await button(4,false);await sleep(350);
    await tap(10);await axis(1,-.8);await until(()=>window.atmoDebug.locomotion==='run',null,'L3 toggles run');
    await tap(10);await until(()=>window.atmoDebug.locomotion==='walk',null,'L3 toggles walking back');await axis(1,0);await sleep(350);
    const jumps=(await state()).jumps;await button(0,true);
    await until(value=>window.atmoDebug.jumps===value+1,jumps,'A jumps');await sleep(1400);await button(0,false);
    assert.equal((await state()).jumps,jumps+1,'Held A must not chain jumps');
    const punches=(await state()).punches;await tap(2);await until(value=>window.atmoDebug.punches===value+1,punches,'X punches');
    await sleep(300);await tap(7);await until(value=>window.atmoDebug.punches===value+2,punches,'RT punches');
    const map=(await state()).map_visible;await tap(3);assert.equal((await state()).map_visible,!map);await tap(3);assert.equal((await state()).map_visible,map);
    await tap(11);assert.equal((await state()).debug_enabled,true);await tap(11);assert.equal((await state()).debug_enabled,false);
    check('Controller walk, turn, LB/L3 run, edge-triggered jump, X/RT punch, plan, and R3 debug');
    await tap(1);await screen('pause');await tap(1);await screen('playing');
    check('Right face button pauses and resumes without an OS-reserved Menu button');
    if(mobile){
      await page.setViewportSize({width:844,height:390});await sleep(450);
      await tap(1);await focus(1);await tap(0);await screen('settings');await focus(9);
      await screenshot('test-results/mobile-landscape-settings.png');await noOtherInput();
      await tap(1);await screen('pause');await tap(1);await screen('playing');
      await page.setViewportSize({width:393,height:851});await sleep(450);
      await evaluate(()=>window.__controllerTest.meters[0].context.suspend());
      await until(()=>window.atmoBoot.phase==='audio-blocked'&&window.atmoDebug.paused&&!window.atmoDebug.host_input_ready,null,'audio interruption safely gates input');
      await tap(0);await until(()=>window.atmoBoot.activated&&window.atmoDebug.host_input_ready,null,'controller restores interrupted audio');
      await screen('pause');await tap(1);await screen('playing');
      check('Phone rotation, scrolled settings, audio interruption and controller-only recovery');
    }


    await button(9,true);await screen('pause');await sleep(850);assert.equal((await state()).paused,true,'Held Start must pause only once');
    await button(9,false);await sleep(300);await tap(9);await screen('playing');
    await pause();const resumeJumps=(await state()).jumps;await button(0,true);await screen('playing');await sleep(850);
    assert.equal((await state()).jumps,resumeJumps,'Held Resume confirmation must not also jump');await button(0,false);await sleep(350);
    await pause();await focus(1);await tap(0);await screen('settings');await tap(1);await screen('pause');
    await focus(1);await tap(0);await screen('settings');await tap(9);await screen('playing');
    await chooser();await tap(1);await screen('main');await tap(1);await screen('pause');await tap(1);await screen('playing');
    await chooser();await focus(5);await tap(0);await screen('playing');
    check('Start pause/resume, held transitions, B back through both submenus, and Back to this walk');

    const beforeDisconnect=await state();await axis(1,-.8);await sleep(500);
    await evaluate(()=>window.__controllerTest.disconnect());await until(()=>window.atmoDebug.controllers===0,null,'disconnect detected');
    await screen('pause');
    await sleep(400);const stopped=await state();await sleep(550);const stillStopped=await state();
    assert(Math.hypot(stillStopped.position[0]-stopped.position[0],stillStopped.position[1]-stopped.position[1])<.1,'Disconnect clears held movement');
    await evaluate(()=>window.__controllerTest.connect(1));await until(()=>window.atmoDebug.controllers===1,null,'new-index reconnect detected');
    assert.equal((await state()).paused,true,'Reconnecting must preserve the safety pause');
    await tap(9);await screen('playing');
    await stick(1,.8,500);assert((await state()).steps>beforeDisconnect.steps,'Reconnected controller moves and produces footsteps');
    await pause();await evaluate(()=>window.__controllerTest.disconnect());await until(()=>window.atmoDebug.controllers===0,null,'menu disconnect');
    await evaluate(()=>window.__controllerTest.connect(0));await until(()=>window.atmoDebug.controllers===1,null,'menu reconnect');
    await tap(13);assert.equal((await state()).ui_focus_index,1,'Reconnected controller navigates retained native menu');
    await tap(1);await screen('playing');
    check('Disconnect clears held movement and pauses; reconnect resumes explicitly and restores native menus');

    for(const [index,id] of [[1,'cistern'],[2,'freighter'],[3,'courtyard']]){await chooser();await play(index,id);}
    await pause();await focus(3);const generation=(await state()).generation;await tap(0);await screen('playing');
    assert.equal((await state()).generation,generation+1,'Restart loads one fresh walk');
    assert.equal((await state()).level,'courtyard');
    await pause();await focus(4);await tap(0);await screen('main');assert.equal((await state()).started,false,'Main menu unloads the active walk');
    check('All four environments, Restart, and Main menu are reachable without another input device');
    await noOtherInput();report.before_reload={activation:(await snapshot()).activation,inputs:(await snapshot()).inputs};
    await sleep(1200);await page.reload({waitUntil:'domcontentloaded'});await launch(9);
    assert.deepEqual((await state()).settings,report.saved_settings,'Every edited setting persists across a browser reload');
    await focus(2);await tap(0);await screen('settings');await tap(1);await screen('main');
    await noOtherInput();
    check('Start also launches safely after reload; settings persist; B returns from initial Settings');
    assert.deepEqual(errors,[],'No browser or Godot errors');
    report.after_reload={activation:(await snapshot()).activation,inputs:(await snapshot()).inputs};
    report.result='PASS: controller-only synthetic routing, all menus/settings/actions, four environments, reconnects, transition holds, and persistence';
    fs.writeFileSync('test-results/controller-browser.json',JSON.stringify(report,null,2));
    console.log(report.result);
  }catch(error){
    report.result='FAIL';report.error=error.stack;report.browser_errors=errors;
    try{report.last_state=await snapshot();await screenshot('test-results/controller-failure.png');}catch{}
    fs.writeFileSync('test-results/controller-browser.json',JSON.stringify(report,null,2));
    throw error;
  }finally{await browser.close();await host.close();}
})().catch(error=>{console.error(error);process.exit(1);});
