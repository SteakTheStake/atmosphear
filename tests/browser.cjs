/* Compatibility entry point: the native UI, audio, and debug checks are split by concern. */
const {spawnSync}=require('node:child_process');
const path=require('node:path');
for(const name of ['experience_browser.cjs','audio_browser.cjs','debug_browser.cjs']){
  const result=spawnSync(process.execPath,[path.join(__dirname,name)],{stdio:'inherit'});
  if(result.error)throw result.error;
  if(result.status!==0)process.exit(result.status||1);
}
