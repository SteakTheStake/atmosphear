/* Real Godot PWA startup at a project subpath on a server with NO COOP/COEP. */
const browsers=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const http=require('node:http');

(async()=>{
  const directory=path.resolve(process.argv[2]||'build/pages');
  const prefix='/atmosphear-pages-check/';
  const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.json':'application/json','.wasm':'application/wasm','.pck':'application/octet-stream','.png':'image/png','.svg':'image/svg+xml'};
  const server=http.createServer((request,response)=>{
    const pathname=new URL(request.url,'http://localhost').pathname;
    if(pathname==='/favicon.ico'){response.writeHead(204);response.end();return;}
    if(pathname===prefix+'empty-response'){response.writeHead(204);response.end();return;}
    if(!pathname.startsWith(prefix)){response.writeHead(404);response.end();return;}
    const relative=decodeURIComponent(pathname.slice(prefix.length))||'index.html';
    const filename=path.resolve(directory,relative);
    if(!filename.startsWith(directory+path.sep)||!fs.existsSync(filename)||!fs.statSync(filename).isFile()){
      response.writeHead(404);response.end();return;
    }
    response.writeHead(200,{'Content-Type':mime[path.extname(filename)]||'application/octet-stream','Cache-Control':'no-cache','Content-Length':fs.statSync(filename).size});
    if(request.method==='HEAD')response.end();else fs.createReadStream(filename).pipe(response);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}${prefix}`;
  const browserName=process.env.PAGES_BROWSER||'chromium';
  const reportPath=browserName==='chromium'?'test-results/pages-browser.json':`test-results/pages-browser-${browserName}.json`;
  const browser=await browsers[browserName].launch({headless:true});
  const result={base,browser:browserName,preset:'threaded Stream DSP with Godot-generated isolation worker'};
  let activePage;
  fs.mkdirSync('test-results',{recursive:true});
  try{
    const plain=await fetch(base);
    assert.equal(plain.headers.get('cross-origin-opener-policy'),null);
    assert.equal(plain.headers.get('cross-origin-embedder-policy'),null);
    const context=await browser.newContext();
    const page=await context.newPage();
    activePage=page;
    const errors=[],navigations=[],requests=[];
    result.browser_errors=errors;
    page.on('pageerror',error=>errors.push(error.message));
    page.on('console',message=>{if((message.type()==='error'||/SCRIPT ERROR|Parse Error|Failed to load/.test(message.text()))&&!message.text().includes('Blocking on the main thread'))errors.push(message.text());});
    page.on('request',request=>requests.push(request.url()));
    page.on('response',response=>{
      if(response.request().isNavigationRequest())navigations.push({url:response.url(),worker:response.fromServiceWorker()});
    });
    await page.addInitScript(()=>{
      window.pageAudioMeters=[];
      if(typeof AudioNode==='undefined'||typeof AudioDestinationNode==='undefined')return;
      const connect=AudioNode.prototype.connect;
      AudioNode.prototype.connect=function(destination,...args){
        if(destination instanceof AudioDestinationNode&&!this.__pagesMetered){
          this.__pagesMetered=true;
          const splitter=this.context.createChannelSplitter(2);connect.call(this,splitter);
          const meters=[0,1].map(channel=>{
            const analyser=this.context.createAnalyser();analyser.fftSize=2048;
            connect.call(splitter,analyser,channel);return analyser;
          });
          window.pageAudioMeters.push({context:this.context,meters});
        }
        return connect.call(this,destination,...args);
      };
      window.pagesRms=()=>window.pageAudioMeters.map(({context,meters})=>({running:context.state==='running',rms:meters.map(meter=>{
        const values=new Float32Array(meter.fftSize);meter.getFloatTimeDomainData(values);
        return Math.sqrt(values.reduce((sum,value)=>sum+value*value,0)/values.length);
      })}));
    });
    await page.goto(base+'?debug=1');
    await page.waitForFunction(()=>window.atmoDebug?.ready||window.atmoBoot?.phase==='failed',null,{timeout:90000});
    if(process.env.PAGES_EXPECT_UNSUPPORTED==='1'){
      assert.equal(await page.evaluate(()=>window.atmoBoot.phase),'failed');
      assert.equal(await page.evaluate(()=>Engine.isAudioWorkletAvailable()),false,'This mode only accepts an actually missing audio capability');
      assert.equal(await page.locator('#start').isEnabled(),true);
      result.unsupported_audio={message:await page.locator('#status').innerText(),playback_tested:false};
      assert.match(result.unsupported_audio.message,/browser|audio engine/i);
      await page.waitForTimeout(700);assert.equal(navigations.length,1);
      assert.deepEqual(errors,[]);
      result.result='PASS: this browser runtime lacks AudioWorklet and displays a clear, bounded compatibility fallback; playback was not tested';
      fs.writeFileSync(reportPath,JSON.stringify(result,null,2));
      await page.screenshot({path:'test-results/pages-unsupported-audio.png'});
      console.log(result.result);return;
    }
    assert.equal(await page.evaluate(()=>window.atmoBoot.phase),'ready',await page.locator('#status').innerText());
    assert.equal(await page.evaluate(()=>crossOriginIsolated),true);
    assert.equal(await page.evaluate(()=>typeof SharedArrayBuffer),'function');
    assert.equal(await page.evaluate(async()=>{const response=await fetch(new URL('empty-response',location.href));return response.status;}),204,'Isolation header wrapper must preserve null-body responses in every browser');
    const worker=await page.evaluate(()=>navigator.serviceWorker.controller?.scriptURL);
    assert(worker.startsWith(base)&&worker.endsWith('.service.worker.js'));
    assert(navigations.length>=2&&navigations.length<=3,'First visit must complete one bounded isolation reload');
    assert.equal(navigations[0].worker,false);assert.equal(navigations.at(-1).worker,true);
    assert(!page.url().includes('_atmo_boot'),'Bootstrap marker must disappear after successful initialization');
    await page.locator('#start').click();await page.keyboard.press('Enter',{delay:70});
    await page.waitForFunction(()=>window.atmoDebug.started);
    await page.waitForTimeout(700);
    const initial=await page.evaluate(()=>window.atmoDebug);
    await page.keyboard.down('w');await page.waitForTimeout(950);await page.keyboard.up('w');
    await page.waitForTimeout(300);
    const moved=await page.evaluate(()=>window.atmoDebug);
    assert(moved.position[1]<initial.position[1]-.7&&moved.steps>initial.steps,'Actual controller-compatible game movement must run under worker-provided headers');
    assert.equal(moved.diagnostics.room.decay_bands.length,3,'Complex room DSP must remain enabled');
    const audio=[0,0];let running=false;
    for(let i=0;i<20;i++){
      for(const meter of await page.evaluate(()=>window.pagesRms())){
        running ||= meter.running;meter.rms.forEach((value,channel)=>audio[channel]=Math.max(audio[channel],value));
      }
      await page.waitForTimeout(30);
    }
    assert(running&&audio.every(value=>value>0),'The real exported stereo audio must play on the headerless static host');
    const gameRequests=requests.filter(url=>/\.(js|wasm|pck|json)(\?|$)/.test(url));
    assert(gameRequests.every(url=>url.startsWith(base)),'All game resources must stay relative to the project subpath');
    result.first_visit={navigations:[...navigations],worker,stereo_peak_rms:audio,room:moved.diagnostics.room};
    await page.screenshot({path:'test-results/pages-running.png'});
    await context.setOffline(true);
    await page.reload();
    await page.waitForFunction(()=>window.atmoDebug?.ready,null,{timeout:30000});
    assert.equal(await page.evaluate(()=>crossOriginIsolated),true);
    result.cached_offline_reload=true;
    assert.deepEqual(errors,[]);
    await context.close();

    // Private/storage policy denial must produce a useful retry screen, never
    // start a broken threaded runtime or endlessly reload the document.
    const blocked=await browser.newContext();
    await blocked.addInitScript(()=>{
      Object.defineProperty(navigator.serviceWorker,'register',{value:()=>Promise.reject(new DOMException('Site storage denied','SecurityError'))});
    });
    const blockedPage=await blocked.newPage();let blockedNavigations=0;
    blockedPage.on('response',response=>{if(response.request().isNavigationRequest())blockedNavigations++;});
    await blockedPage.goto(base);
    await blockedPage.waitForFunction(()=>window.atmoBoot?.phase==='failed',null,{timeout:20000});
    const failure=await blockedPage.locator('#status').innerText();
    assert.match(failure,/storage|browser/i);
    assert.equal(await blockedPage.locator('#start').isEnabled(),true);
    await blockedPage.waitForTimeout(700);assert.equal(blockedNavigations,1);
    result.blocked_worker={message:failure,navigations:blockedNavigations};
    await blockedPage.screenshot({path:'test-results/pages-blocked-worker.png'});
    await blocked.close();

    // Simulate an engine/browser that still cannot isolate after activation.
    const incompatible=await browser.newContext();
    await incompatible.addInitScript(()=>Object.defineProperty(window,'crossOriginIsolated',{value:false}));
    const incompatiblePage=await incompatible.newPage();let incompatibleNavigations=0;
    incompatiblePage.on('response',response=>{if(response.request().isNavigationRequest())incompatibleNavigations++;});
    await incompatiblePage.goto(base);
    await incompatiblePage.waitForFunction(()=>window.atmoBoot?.phase==='failed',null,{timeout:30000});
    await incompatiblePage.waitForTimeout(700);
    assert.equal(incompatibleNavigations,2,'Unsupported isolation may reload once, then must stop clearly');
    result.unsupported_isolation={navigations:incompatibleNavigations,message:await incompatiblePage.locator('#status').innerText()};
    await incompatible.close();
    result.result='PASS: project-subpath static hosting without COOP/COEP, one-time worker activation, threaded game/audio, offline cache, and bounded failure screens';
    fs.writeFileSync(reportPath,JSON.stringify(result,null,2));
    console.log(result.result);
  }catch(error){
    result.failure=error.message;
    if(activePage&&!activePage.isClosed()){
      result.failure_state=await activePage.evaluate(()=>({url:location.href,isolated:crossOriginIsolated,boot:window.atmoBoot,status:document.getElementById('status')?.textContent,worker:navigator.serviceWorker.controller?.scriptURL})).catch(()=>null);
      await activePage.screenshot({path:'test-results/pages-failure.png'}).catch(()=>{});
    }
    fs.writeFileSync(reportPath,JSON.stringify(result,null,2));
    console.error(JSON.stringify(result,null,2));
    throw error;
  }finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exit(1);});
