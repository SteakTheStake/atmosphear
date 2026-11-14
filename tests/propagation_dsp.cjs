/* Measured DSP behavior, independent of game telemetry. */
const fs=require('fs'),vm=require('vm'),assert=require('node:assert/strict');
const {chromium}=require('playwright');
const source=fs.readFileSync('web/acoustics.js','utf8');
const code=source.match(/const worklet=`([\s\S]*?)`;/)[1];
let Room;vm.runInNewContext(code,{sampleRate:48000,Float32Array,Float64Array,Int32Array,Math,AudioWorkletProcessor:class{constructor(){this.port={};}},registerProcessor:(name,type)=>Room=type});
function impulse(rt){const r=new Room();r.port.onmessage({data:{rt:[rt,rt,rt],wet:1}});r.wet=1;r.g=r.targetG.map(a=>a.slice());
const y=new Float32Array(48000*4);let peak=0;
for(let i=0;i<y.length;i+=128){const x=new Float32Array(128),l=new Float32Array(128),h=new Float32Array(128);if(!i)x[0]=1;r.process([[x,x]],[[l,h]]);for(let j=0;j<128&&i+j<y.length;j++){assert(Number.isFinite(l[j]));y[i+j]=(l[j]+h[j])*.5;peak=Math.max(peak,Math.abs(l[j]),Math.abs(h[j]));}}
let total=0;const edc=new Float64Array(y.length);for(let i=y.length-1;i>=0;i--){total+=y[i]*y[i];edc[i]=total;}
let a=-1,b=-1;for(let i=0;i<edc.length;i++){const db=10*Math.log10(edc[i]/total);if(a<0&&db<=-5)a=i;if(b<0&&db<=-35){b=i;break;}}
const measured=(b-a)/48000*2;assert(Math.abs(measured-rt)<rt*.15,`FDN T30 RT60 ${measured} must track ${rt}`);assert(peak<2);return{target_rt60:rt,measured_rt60:measured,peak};}
const retired=new Room();retired.port.onmessage({data:{dispose:true}});assert.equal(retired.process([],[]),false,'Disposed field must stop processing');
(async()=>{const report={decay:[.3,1,2].map(impulse)};const browser=await chromium.launch({headless:true});try{
const page=await browser.newPage();await page.goto('about:blank');await page.addScriptTag({content:source});
report.propagation=await page.evaluate(async()=>{
 const results=[];
 for(const isolation of ['direct','all','early']){
 const c=new OfflineAudioContext(2,48000*.3,48000),r=window.AtmoAcoustics;r.context=c;r.output=c.createGain();r.output.connect(c.destination);r.roomInput=c.createGain();r.ready=true;r.mode='speakers';r.isolation=isolation;r.settings={ambience:1};r.emitters.clear();r.cache.clear();
 const b=c.createBuffer(1,48000*.2,48000);b.getChannelData(0)[3840]=1;r.cache.set('probe',Promise.resolve(b));r.configure('probe','probe',false,'Environment');
 r.update('probe',{distance:3.43,position:[0,0,-3.43],cutoff:20000,db:0,pitch:1,send_db:-120,paths:[{id:'wall',position:[0,0,-6.86],length:6.86,cutoff:20000,db:-6}]});r.play('probe');await Promise.resolve();await Promise.resolve();
 const out=await c.startRendering(),y=out.getChannelData(0);const regions=[];
 for(let start=0;start<y.length;start+=48){let energy=0;for(let j=start;j<start+48&&j<y.length;j++)energy+=y[j]*y[j];if(energy>1e-5)regions.push({ms:start/48,energy});}
 results.push({isolation,regions,starts:r.audit.starts});
 }
 return results;
});
for(const item of report.propagation){const times=item.regions.map(r=>r.ms);if(item.isolation!=='early')assert(times.some(t=>Math.abs(t-90)<=1),'Direct arrival must be distance/c');if(item.isolation!=='direct')assert(times.some(t=>Math.abs(t-100)<=1),'Reflection must be total length/c');assert(times.every(t=>Math.abs(t-90)<=1||Math.abs(t-100)<=1),'No arbitrary 3/11/19 ms copies');}
console.log(JSON.stringify(report,null,2));fs.mkdirSync('test-results',{recursive:true});fs.writeFileSync('test-results/propagation-dsp.json',JSON.stringify(report,null,2));
}finally{await browser.close();}})().catch(e=>{console.error(e);process.exit(1);});
