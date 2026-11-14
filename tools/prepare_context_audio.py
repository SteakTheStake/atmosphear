"""Correct contextual mismatches using only the user's local recordings.

Requires FFmpeg, NumPy and SciPy. Four canopy loops are separate passages of ONE
actual tree-wind take (the other explicit foliage take includes traffic). Pipe
rings likewise use excerpts of one actual vibrating-pipe take, not independent
thermal ticks. Source labels and signal metrics are evidence, not an audition.
Run after base/detail/landmark/menu preparation; completed menu patch is merged.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import numpy as np
from scipy.signal import butter, sosfilt

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/library'
SR = 44100
FILES = {p.name: p for p in (ROOT/'audio').rglob('*.wav')}
HASHES = {}

LOOPS = [
    *[(f'canopy{i}.ogg','Ambience Wind Blowing Through Trees 01.wav',start,20,
       'Actual wind through trees: non-overlapping passage of one take; not shaken-tree, sticks or footsteps.')
      for i,start in enumerate([0,22,44,66])],
    ('water_flow0.ogg','Liquid Water Flowing Through Pipe 04.wav',25,19,
     'Continuous recorded pipe-water flow, suitable for an outlet/channel. Not a bucket pour or a claimed fountain field recording.'),
    ('water_flow1.ogg','Liquid Water Flowing Through Pipe 04.wav',2,20,
     'A separate non-overlapping passage of continuous real pipe-water flow; plumbing/outlet context, not small metal-bowl bubbling.'),
    *[(f'wind_shaft{i}.ogg','WINDInt_ChimneyWind05_InMotionAudio_ChimneyWind.wav',start,22,
       'Actual interior chimney wind passage; an airshaft analogue, not blizzard or hurricane weather.')
      for i,start in enumerate([18,62])],
    *[(f'wind_open{i}.ogg','Ambience Nature Field Windy 02.wav',start,22,
       'Outdoor windy-field ambience; general open-air wind rather than extreme hurricane weather.')
      for i,start in enumerate([16,54])],
]

ONES = [
    ('wood_creak0.wav','Foley Wood Creak 03.wav',0,3,'Recorded wooden creak; timber structure/floor context.'),
    ('wood_creak1.wav','Foley Wood Creak Floor 06.wav',0,3,'Recorded creaking wooden floor; boardwalk/floor context.'),
    ('wood_creak2.wav','Foley Wood Squeak Low 01.wav',0,3,'Recorded low wooden friction; timber structure context, not leaf motion.'),
    ('wood_creak3.wav','Foley Wood Squeak 01.wav',0,3,'Recorded wooden squeak; timber structure context, not leaf motion.'),
    ('metal_creak0.wav','Foley Metal Creak 01.wav',0,4,'Recorded metal creak; stressed metal structure.'),
    ('metal_creak1.wav','Foley Metal Creak Long 01.wav',0,4,'A different long recorded metal creak; stressed metal structure.'),
    ('metal_creak2.wav','Foley Metal Squeak Stress Hand 01.wav',0,4,'Actual metal stressed by hand; structural flex/friction analogue.'),
    ('metal_creak3.wav','Foley Metal Squeak 01.wav',0,4,'Recorded metal friction, not a synthetic or creature effect.'),
    ('bird5.wav','Animal Bird Brown Headed Cowbird Chirp 02.wav',0,4,'Second cowbird call; pair with existing bird4.'),
    ('bird6.wav','Animal Bird American Goldfinch Chirp 02.wav',0,4,'Second goldfinch call; pair with existing bird3.'),
    ('bird7.wav','Animal Bird Black Necked Stilt Chirp 01.wav',0,4,'Recorded shorebird call; wetland/waterside only, not generic canopy fauna.'),
    ('bird8.wav','Animal Bird Black Necked Stilt Chirp 02.wav',0,4,'Second shorebird call; wetland/waterside use.'),
    *[(f'pipe_ring{i}.wav','Industry Aluminum Pipe Vibrating 04.wav',start,1.25,
       'Distinct excerpt of one actual vibrating aluminum-pipe take. Pipe resonance, not hammer/nail impact or a claimed thermal tick.')
      for i,start in enumerate([.08,1.55,3.0,4.25])],
]
DRIPS = [
    ('drip3.wav','Liquid Water Water Dripping 01.wav'),
    ('drip4.wav','Liquid Water Water Dripping 05 .wav'),
    ('drip5.wav','Liquid Water Water Dripping 08 .wav'),
    ('drip6.wav','Liquid Water Water Drips 02.wav'),
]
ALIASES = {
    'tree_rustle.ogg':'canopy0.ogg','pipe_tick.wav':'pipe_ring0.wav',
    'landmark_fountain.ogg':'water_flow0.ogg','landmark_water_resonance.ogg':'water_flow1.ogg',
    'cistern_air.ogg':'wind_shaft0.ogg','courtyard_wind.ogg':'wind_open0.ogg',
}

def decode(path,start=0,duration=180):
    data=subprocess.check_output(['ffmpeg','-v','error','-ss',str(start),'-i',str(path),'-t',str(duration),'-ac','1','-ar',str(SR),'-f','f32le','-'])
    return np.frombuffer(data,dtype='<f4').copy()

def trim(samples,start):
    active=np.flatnonzero(np.abs(samples)>max(float(np.max(np.abs(samples)))*.004,.00001))
    if not len(active): raise ValueError('Empty recording')
    begin=max(0,int(active[0])-int(.012*SR));end=min(len(samples),int(active[-1])+int(.04*SR))
    return samples[begin:end],start+begin/SR

def write(name,samples,path,start,loop,context):
    if not len(samples) or not np.isfinite(samples).all(): raise ValueError(name)
    samples-=float(np.mean(samples))
    highpass=name.startswith(('canopy','wind_'))
    if highpass: samples=sosfilt(butter(2,65,'highpass',fs=SR,output='sos'),samples)
    fade=min(.75,len(samples)/SR*.1) if loop else (.035 if name.startswith('pipe_ring') else .005)
    n=min(int(fade*SR),len(samples)//4)
    if loop:
        angle=np.linspace(0,np.pi/2,n)
        samples=np.concatenate([samples[n:-n],samples[-n:]*np.cos(angle)+samples[:n]*np.sin(angle)])
    else:
        samples[:n]*=np.linspace(0,1,n);samples[-n:]*=np.linspace(1,0,n)
    peak=float(np.max(np.abs(samples)));rms=float(np.sqrt(np.mean(samples*samples)))
    target=.055 if name.startswith(('canopy','wind_')) else .07
    gain=min(10**(18/20),.7/peak,target/rms) if loop else min(10**(12/20),.30/peak)
    if name.startswith('pipe_ring'): gain=min(gain,.03/rms)
    pcm=np.asarray(samples*gain,dtype='<f4');dest=OUT/name
    codec=['-c:a','libvorbis','-q:a','4'] if loop else ['-c:a','pcm_s16le']
    subprocess.run(['ffmpeg','-v','error','-y','-f','f32le','-ar',str(SR),'-ac','1','-i','-',*codec,str(dest)],input=pcm.tobytes(),check=True)
    decoded=decode(dest);pk=float(np.max(np.abs(decoded)));r=float(np.sqrt(np.mean(decoded*decoded)))
    assert pk<.99 and r>.00001 and np.isfinite(decoded).all(),name
    blocks=np.array([np.sqrt(np.mean(decoded[i:i+2205]**2)) for i in range(0,len(decoded),2205)])
    env_db=20*np.log10(np.maximum(blocks,1e-8))
    if path not in HASHES: HASHES[path]=hashlib.sha256(path.read_bytes()).hexdigest()
    entry={
        'file':dest.relative_to(ROOT).as_posix(),'sources':[{'path':path.relative_to(ROOT).as_posix(),'sha256':HASHES[path]}],
        'source_start_seconds':round(start,5),'duration_seconds':round(len(pcm)/SR,5),
        'sample_rate':SR,'channels':1,'loop':loop,'gain_db':round(float(20*np.log10(gain)),3),
        'peak_dbfs':round(float(20*np.log10(pk)),3),'rms_dbfs':round(float(20*np.log10(r)),3),
        'crest_db':round(float(20*np.log10(pk/r)),3),
        'envelope_p95_p05_db':round(float(np.percentile(env_db,95)-np.percentile(env_db,5)),3),
        'processing':f"Mono44.1k; DC removal; {'65Hz highpass; ' if highpass else ''}{round(fade*1000)}ms {'equal-power wrap crossfade' if loop else 'edge fades'}; bounded level; {'Vorbis q4' if loop else 'PCM16'}; no synthesized replacement, pitch/time copies or baked reverb.",
        'application':context,'selection':'Source labels/provenance and waveform/loudness inspection only. No listening audition claimed; contextual use and ambiguity described explicitly.'}
    print(name,entry['duration_seconds'],'s',entry['rms_dbfs'],'RMS dBFS',flush=True)
    return entry

def main():
    entries=[]
    for name,source,start,length,context in LOOPS:
        path=FILES[source];entries.append(write(name,decode(path,start,length),path,start,True,context))
    for name,source,start,length,context in ONES:
        path=FILES[source];samples,actual_start=trim(decode(path,start,length),start)
        entries.append(write(name,samples,path,actual_start,False,context))
    for name,source in DRIPS:
        path=FILES[source];samples=decode(path);hop=220
        energy=np.array([np.mean(samples[i:i+hop]**2) for i in range(0,len(samples),hop)])
        center=int(np.argmax(energy))*hop;begin=max(0,center-int(.055*SR));end=min(len(samples),center+int(.65*SR))
        selected,start=trim(samples[begin:end],begin/SR)
        entries.append(write(name,selected,path,start,False,'Real water-drip event from a separate dripping-water recording; no generic impact Foley.'))
    by_name={Path(e['file']).name:e for e in entries}
    for alias,primary in ALIASES.items():
        (OUT/alias).write_bytes((OUT/primary).read_bytes())
        entry=json.loads(json.dumps(by_name[primary]));entry['file']=(OUT/alias).relative_to(ROOT).as_posix();entry['alias_of']=primary
        entry['application']+=' Compatibility filename; this alias is not an additional variant.'
        entries.append(entry)
    manifest_path=OUT/'manifest.json';manifest=json.loads(manifest_path.read_text(encoding='utf8'))
    menu_patch=OUT/'menu_manifest_patch.json'
    if menu_patch.exists():
        patch=json.loads(menu_patch.read_text(encoding='utf8'));entries.extend(patch['assets']);manifest['menu_notes']=patch['menu_notes']
    replaced={e['file'] for e in entries}
    manifest['assets']=[e for e in manifest['assets'] if e['file'] not in replaced]+entries
    manifest['context_notes']='Shaken-tree Foley replaced with real tree-wind passages; hammer/nail pipe ticks with actual pipe resonance; bucket/bowl landmarks with real pipe flow; blizzard/hurricane aliases with chimney/open-field wind. Added real creak/drip/bird recordings. Canopy and pipe families each use separate excerpts of one take, not separate field recordings; aliases are not extra variants. Evidence is labels and signal metrics, not listening audition.'
    manifest['regeneration_order']=['prepare_library.py','prepare_detail_audio.py','prepare_landmark_audio.py','prepare_menu_audio.py','prepare_context_audio.py']
    manifest_path.write_text(json.dumps(manifest,indent=2),encoding='utf8')
    size=sum(p.stat().st_size for p in OUT.iterdir() if p.suffix in ('.ogg','.wav'))
    print(f"{len(manifest['assets'])} assets; {size/1e6:.3f}MB")

if __name__=='__main__': main()
