/*
 * Cold-start autoplay regression, deliberately WITHOUT trusted controller input.
 * Fake getGamepads verifies our blocked/fallback flow, not physical-device unlock.
 * Chromium grants real gamepad button activation inside native getGamepads():
 * https://raw.githubusercontent.com/chromium/chromium/main/third_party/blink/renderer/modules/gamepad/navigator_gamepad.cc
 * Playwright page.evaluate sends userGesture:true and would invalidate this test:
 * https://raw.githubusercontent.com/microsoft/playwright/main/packages/playwright-core/src/server/chromium/crExecutionContext.ts
 * Every page expression therefore uses CDP Runtime.evaluate/userGesture:false.
 * Only the explicitly labelled fallback sends a trusted browser keyboard event.
 */
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const base=process.env.ATMO_BASE_URL||'http://127.0.0.1:8060/';
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));

async function runCase(name,args){
  const browser=await chromium.launch({headless:true,args});
  const context=await browser.newContext();
  const page=await context.newPage();
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  await page.addInitScript(()=>{
    window.policyProbe={contexts:[],resumeCalls:[],trustedKeys:[],meters:[],pads:[]};
    for(const name of ['AudioContext','webkitAudioContext']){
      const Native=window[name];
      if(Native)window[name]=new Proxy(Native,{construct(Target,args,newTarget){
        const audio=Reflect.construct(Target,args,newTarget);
        policyProbe.contexts.push(audio);
        const original=audio.resume;
        audio.resume=function(...values){
          policyProbe.resumeCalls.push({t:performance.now(),state:this.state,active:navigator.userActivation.isActive,ever:navigator.userActivation.hasBeenActive});
          return original.apply(this,values);
        };
        return audio;
      }});
    }
    const connect=AudioNode.prototype.connect;
    AudioNode.prototype.connect=function(destination,...args){
      if(destination instanceof AudioDestinationNode&&!this.__policyMeter){
        this.__policyMeter=true;
        const meter=this.context.createAnalyser();meter.fftSize=2048;
        connect.call(this,meter);policyProbe.meters.push(meter);
      }
      return connect.call(this,destination,...args);
    };
    Object.defineProperty(navigator,'getGamepads',{value:()=>policyProbe.pads});
    window.policyPadConnect=()=>{
      const pad={id:'Synthetic policy regression pad',index:0,connected:true,mapping:'standard',timestamp:performance.now(),axes:[0,0,0,0],buttons:Array.from({length:17},()=>({pressed:false,touched:false,value:0}))};
      policyProbe.pads[0]=pad;
      const event=new Event('gamepadconnected');Object.defineProperty(event,'gamepad',{value:pad});window.dispatchEvent(event);
    };
    window.policyPadButton=(index,pressed)=>{
      policyProbe.pads[0].buttons[index]={pressed,touched:pressed,value:pressed?1:0};
      policyProbe.pads[0].timestamp=performance.now();
    };
    document.addEventListener('keydown',event=>policyProbe.trustedKeys.push({key:event.key,trusted:event.isTrusted}),true);
    window.policySnapshot=()=>({
      boot:window.atmoBoot||null,
      state:window.atmoDebug?{ready:atmoDebug.ready,started:atmoDebug.started,paused:atmoDebug.paused,ui_screen:atmoDebug.ui_screen,controllers:atmoDebug.controllers}:null,
      activation:{active:navigator.userActivation.isActive,ever:navigator.userActivation.hasBeenActive},
      contexts:policyProbe.contexts.map(audio=>audio.state),
      resume_calls:policyProbe.resumeCalls,
      trusted_keys:policyProbe.trustedKeys,
      launch_visible:!!document.getElementById('launch')&&!document.getElementById('launch').hidden,
      focused:document.hasFocus(),
      audio_peak_rms:Math.max(0,...policyProbe.meters.map(meter=>{
        const samples=new Float32Array(meter.fftSize);meter.getFloatTimeDomainData(samples);
        return Math.sqrt(samples.reduce((sum,value)=>sum+value*value,0)/samples.length);
      }))
    });
  });
  const cdp=await context.newCDPSession(page);
  const evaluate=async expression=>{
    const response=await cdp.send('Runtime.evaluate',{expression,userGesture:false,returnByValue:true});
    if(response.exceptionDetails)throw new Error(response.exceptionDetails.text+': '+response.exceptionDetails.exception?.description);
    return response.result.value;
  };
  const snapshot=()=>evaluate('window.policySnapshot ? policySnapshot() : null');
  const until=async(predicate,label,timeout=20000)=>{
    const deadline=Date.now()+timeout;let last;
    while(Date.now()<deadline){
      try{last=await snapshot();if(last&&predicate(last))return last;}
      catch(error){if(!/context.*destroyed|Cannot find context/i.test(String(error)))throw error;}
      await delay(60);
    }
    throw new Error(label+' timed out. Last state: '+JSON.stringify(last));
  };
  const result={name,browser:browser.version(),autoplay_flags:args};
  try{
    const url=new URL(base);url.searchParams.set('debug','1');
    await page.goto(url.href,{waitUntil:'domcontentloaded',timeout:90000});
    await cdp.send('Page.bringToFront');
    result.initial=await until(s=>s.state?.ready&&s.boot?.phase==='ready','engine ready',120000);
    assert.equal(result.initial.activation.ever,false,'Cold start must not be contaminated by automation activation');
    assert.equal(result.initial.state.started,false,'World must not start behind the launcher');
    assert(result.initial.launch_visible,'Launcher must be visible');
    assert(result.initial.contexts.includes('suspended'),'Fresh audio must actually be policy-blocked');
    assert(result.initial.focused,'Page must have focus for controller polling');

    await evaluate('policyPadConnect(); policyPadButton(0,true); null');
    result.attempt=await until(s=>s.boot?.phase==='enabling-audio','held A begins resume attempt',4000);
    assert.equal(result.attempt.activation.ever,false,'Synthetic gamepad must not create native user activation');
    assert(result.attempt.resume_calls.length>result.initial.resume_calls.length,'Launcher must request audio resume');
    result.blocked=await until(s=>s.boot?.phase==='audio-blocked','autoplay blocked status',5000);
    assert.equal(result.blocked.boot.activated,false);
    assert.equal(result.blocked.boot.controller_input_ready,false);
    assert.equal(result.blocked.state.started,false,'Blocked game must not silently enter a world');
    assert(result.blocked.launch_visible,'Blocked audio must retain the launcher');
    assert(result.blocked.contexts.includes('suspended'));
    assert.equal(result.blocked.activation.ever,false);
    const attempts=result.blocked.resume_calls.length;
    await delay(600);
    result.held=await snapshot();
    assert.equal(result.held.resume_calls.length,attempts,'Holding A must not flood repeated resume attempts');
    assert.equal(result.held.state.started,false);

    // Deliberate real browser keyboard fallback. Nothing before this point may
    // call page.evaluate, page.keyboard, locator.click, or CDP userGesture:true.
    await cdp.send('Input.dispatchKeyEvent',{type:'keyDown',key:'Enter',code:'Enter',windowsVirtualKeyCode:13,nativeVirtualKeyCode:13});
    await delay(90);
    await cdp.send('Input.dispatchKeyEvent',{type:'keyUp',key:'Enter',code:'Enter',windowsVirtualKeyCode:13,nativeVirtualKeyCode:13});
    result.unlocked_while_held=await until(s=>s.boot?.phase==='active'&&s.boot?.audio_state==='running','trusted fallback enables audio');
    assert(result.unlocked_while_held.activation.ever,'Explicit keyboard fallback must create activation');
    assert(result.unlocked_while_held.trusted_keys.some(event=>event.key==='Enter'&&event.trusted));
    assert(result.unlocked_while_held.contexts.filter(value=>value!=='closed').every(value=>value==='running'));
    assert.equal(result.unlocked_while_held.launch_visible,false);
    assert.equal(result.unlocked_while_held.boot.controller_input_ready,false,'Held launcher A must not reach the native menu');
    assert.equal(result.unlocked_while_held.state.started,false,'Fallback Enter must not also select the first world');

    await evaluate('policyPadButton(0,false); null');
    result.neutral=await until(s=>s.boot?.controller_input_ready===true,'neutral releases native controller gate');
    assert.equal(result.neutral.state.started,false);
    await delay(200);
    await evaluate('policyPadButton(0,true); null');
    await delay(110);
    await evaluate('policyPadButton(0,false); null');
    result.playing=await until(s=>s.state?.started&&!s.state.paused&&s.audio_peak_rms>0.000001,'fresh controller press selects a world with real audio');
    assert.deepEqual(errors,[]);
    result.result='PASS: untrusted controller stays audio-blocked; explicit keyboard unlocks; held A is consumed; fresh A enters audible gameplay';
    return result;
  }catch(error){
    result.failure=String(error.stack||error);result.last=await snapshot().catch(()=>null);result.errors=errors;
    throw Object.assign(error,{policyResult:result});
  }finally{await browser.close();}
}

(async()=>{
  const report={scope:'Synthetic-pad policy/fallback regression only. Physical controller activation requires a native hardware or browser-internal gamepad test.',cases:[]};
  fs.mkdirSync('test-results',{recursive:true});
  try{
    for(const [name,args] of [['strict-document-activation',['--autoplay-policy=document-user-activation-required']],['default-policy',[]]]){
      report.cases.push(await runCase(name,args));
      console.log(name+': '+report.cases.at(-1).result);
    }
  }catch(error){report.cases.push(error.policyResult||{failure:String(error)});throw error;}
  finally{fs.writeFileSync('test-results/controller-audio-policy.json',JSON.stringify(report,null,2));}
})().catch(error=>{console.error(error);process.exit(1);});
