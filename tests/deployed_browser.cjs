/* Smoke-check a deployed HTTPS build, including actual output and native input. */
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');

(async()=>{
  const url=new URL(process.argv[2]||'https://steakthestake.github.io/atmosphear/');
  url.searchParams.set('debug','1');
  const browser=await chromium.launch({headless:true});
  const page=await browser.newPage({viewport:{width:1152,height:720}});
  const errors=[];
  page.on('pageerror',error=>errors.push(error.message));
  page.on('console',message=>{if(message.type()==='error'&&!message.text().includes('Blocking on the main thread'))errors.push(message.text());});
  await page.addInitScript(()=>{
    const connect=AudioNode.prototype.connect;
    window.liveMeters=[];
    AudioNode.prototype.connect=function(destination,...args){
      if(destination instanceof AudioDestinationNode&&!this.__liveMetered){
        this.__liveMetered=true;
        const split=this.context.createChannelSplitter(2);connect.call(this,split);
        window.liveMeters.push([0,1].map(channel=>{
          const meter=this.context.createAnalyser();meter.fftSize=2048;
          connect.call(split,meter,channel);return meter;
        }));
      }
      return connect.call(this,destination,...args);
    };
  });
  try{
    await page.goto(url.href,{waitUntil:'domcontentloaded',timeout:90000});
    await page.waitForFunction(()=>window.atmoDebug?.ready,null,{timeout:120000});
    assert.equal(await page.evaluate(()=>crossOriginIsolated),true);
    assert(await page.evaluate(()=>!!navigator.serviceWorker.controller));
    await page.locator('#start').click();
    await page.keyboard.press('Enter',{delay:100});
    await page.waitForFunction(()=>window.atmoDebug?.started&&!window.atmoDebug.paused,null,{timeout:30000});
    await page.waitForTimeout(800);
    const peak=[0,0];
    for(let i=0;i<12;i++){
      const values=await page.evaluate(()=>window.liveMeters.map(meters=>meters.map(meter=>{
        const values=new Float32Array(meter.fftSize);meter.getFloatTimeDomainData(values);
        return Math.sqrt(values.reduce((sum,value)=>sum+value*value,0)/values.length);
      })));
      for(const pair of values)pair.forEach((value,index)=>peak[index]=Math.max(peak[index],value));
      await page.waitForTimeout(50);
    }
    assert(peak.every(value=>value>1e-6),'Published game must produce real stereo audio');
    const before=await page.evaluate(()=>window.atmoDebug.position);
    await page.keyboard.down('w');await page.waitForTimeout(1000);await page.keyboard.up('w');
    await page.waitForTimeout(250);
    const after=await page.evaluate(()=>window.atmoDebug.position);
    assert(after[1]<before[1]-.5,'Published game must respond to native movement input');
    await page.keyboard.press('Escape',{delay:80});
    await page.waitForFunction(()=>window.atmoDebug.paused);
    assert.deepEqual(errors,[]);
    fs.mkdirSync('test-results',{recursive:true});
    await page.screenshot({path:'test-results/deployed-pages.png'});
    const result={url:url.origin+url.pathname,stereo_peak_rms:peak,movement_before:before,movement_after:after,errors,result:'PASS: live HTTPS Pages startup, worker isolation, actual stereo sound, movement and pause'};
    fs.writeFileSync('test-results/deployed-pages.json',JSON.stringify(result,null,2));
    console.log(JSON.stringify(result,null,2));
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
