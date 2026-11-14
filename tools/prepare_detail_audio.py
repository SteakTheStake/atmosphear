"""Add detailed library-only environmental, movement, and menu recordings.

Requires FFmpeg, NumPy and SciPy. Footstep variants are DIFFERENT recorded steps,
not pitch-shifted copies. Existing same-named footfalls are replaced to keep each
material's footwear consistent. Original user-library files remain untouched.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import numpy as np
from scipy.signal import find_peaks

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/library'
OUT.mkdir(parents=True,exist_ok=True)
SR=44100
FILES={p.name:p for p in (ROOT/'audio').rglob('*.wav')}
ENTRIES=[]
HASHES={}

def decode(name,start=0,duration=45):
    path=FILES[name]
    data=subprocess.check_output(['ffmpeg','-v','error','-ss',str(start),'-i',str(path),'-t',str(duration),'-ac','1','-ar',str(SR),'-f','f32le','-'])
    return np.frombuffer(data,dtype='<f4').copy(),path

def edges(x,seconds=.005):
    n=min(int(SR*seconds),len(x)//4)
    x[:n]*=np.linspace(0,1,n);x[-n:]*=np.linspace(1,0,n)
    return x

def trim(x,max_seconds=6):
    block=220
    envelope=np.array([np.mean(x[i:i+block]**2) for i in range(0,len(x),block)])
    active=np.flatnonzero(envelope>max(float(max(envelope))*.001,.00000001))
    if not len(active):raise ValueError('Empty source')
    begin=max(0,int(active[0]*block)-int(.012*SR))
    end=min(len(x),int((active[-1]+1)*block)+int(.05*SR),begin+int(max_seconds*SR))
    return edges(x[begin:end]),begin/SR

def write(name,x,path,start,processing,loop=False,gain=None):
    peak=float(np.max(np.abs(x)));rms=float(np.sqrt(np.mean(x*x)))
    assert np.isfinite(x).all() and peak>.0001 and rms>.00001,name
    if gain is None:gain=min(10**(8/20),(.07/max(rms,1e-6) if loop else .4/peak),.7/peak)
    x=np.asarray(x*gain,dtype='<f4')
    assert np.max(np.abs(x))<.95,name
    ext='.ogg' if loop else '.wav'
    output=OUT/(name+ext)
    codec=['-c:a','libvorbis','-q:a','4'] if loop else ['-c:a','pcm_s16le']
    subprocess.run(['ffmpeg','-v','error','-y','-f','f32le','-ar',str(SR),'-ac','1','-i','-',*codec,str(output)],input=x.tobytes(),check=True)
    if path not in HASHES:HASHES[path]=hashlib.sha256(path.read_bytes()).hexdigest()
    ENTRIES.append({'file':output.relative_to(ROOT).as_posix(),'sources':[{'path':path.relative_to(ROOT).as_posix(),'sha256':HASHES[path]}],
        'source_start_seconds':round(start,5),'duration_seconds':round(len(x)/SR,5),'sample_rate':SR,'channels':1,'loop':loop,
        'gain_db':round(float(20*np.log10(gain)),3),'peak_dbfs':round(float(20*np.log10(np.max(np.abs(x)))),3),
        'processing':processing,'selection':'Nonvocal recording labels; no synthesized tones or speech. Source originals unchanged.'})
    print(output.name,round(len(x)/SR,2),'s',flush=True)

WALKS={
 'stone':'Foley Footstep Work Boots Concrete Walking 01.wav',
 'wood':'Foley Footstep Cowboy Boots Walking On Solid Wood Platform 01.wav',
 'gravel':'Foley Footstep Work Boots Dirt Debris Walking 01.wav',
 'metal':'Foley Footstep Work Boots Metal Walking 01.wav',
}
for material,name in WALKS.items():
    x,path=decode(name)
    hop=220
    envelope=np.array([np.sqrt(np.mean(x[i:i+hop]**2)) for i in range(0,len(x),hop)])
    minimum=.5 if material=='gravel' else .6
    peaks,_=find_peaks(envelope,height=float(max(envelope))*.1,distance=int(minimum*SR/hop),prominence=float(max(envelope))*.06)
    peaks=[int(p*hop) for p in peaks if .25<p*hop/SR<len(x)/SR-.3]
    if len(peaks)<12:raise ValueError(f'Only {len(peaks)} discrete {material} steps found')
    clips=[]
    for p in peaks[:12]:
        begin=max(0,p-int(.12*SR));end=min(len(x),p+int((.6 if material=='metal' else .4)*SR))
        clip,offset=trim(x[begin:end],.75)
        clips.append((clip,begin/SR+offset))
    gain=min(10**(8/20),.38/max(float(np.max(np.abs(c))) for c,_ in clips))
    for index,(clip,start) in enumerate(clips):
        write(material+str(index),clip,path,start,'Distinct footfall extracted from continuous walking recording; shared gain preserves differences in force; no pitch/time changes; 5 ms fades; mono PCM16',gain=gain)

for output,name,start,length in [
 ('tree_rustle','Foley Tree Shaking 01.wav',0,18),
 ('insects','Animal Ambience Crickets Near A Stream 01.wav',8,22),
 ('water_lap','Liquid Water Ambience Lake Shore 01.wav',12,24),
]:
    x,path=decode(name,start,length)
    n=min(int(.5*SR),len(x)//5);phase=np.linspace(0,np.pi/2,n)
    x=np.concatenate([x[n:-n],x[-n:]*np.cos(phase)+x[:n]*np.sin(phase)])
    write(output,x,path,start,'Mono 44.1 kHz; 500 ms equal-power wrap crossfade; bounded gain; Vorbis q4',True)

ONES=[
 ('tree_creak','Foley Wood Creak 03.wav',3.5),
 ('bird0','Animal Bird Western Wood Pewee Chirp 01.wav',3),
 ('bird1','Animal Bird Western Tanager Chirp Single 01.wav',3),
 ('bird2','Animal Bird Solitary Vireo Chirp Single 01.wav',3),
 ('bird3','Animal Bird American Goldfinch Chirp 01.wav',3),
 ('bird4','Animal Bird Brown Headed Cowbird Chirp 01.wav',3),
 ('metal_creak','Foley Metal Creak 01.wav',4),
 ('pipe_tick','Industry Tool Hammer Small Metal Hammer Tapping Nail 01.wav',.6),
 ('distant_bell','Foley Bell Brass Handbell Ring 01.wav',6),
 ('drip0','Liquid Water Dripping Single 01.wav',1),
 ('drip1','Liquid Water Dripping In Water 02.wav',1),
 ('drip2','Liquid Water Dripping In Water 05.wav',1),
 ('punch_swing','Foley Cloth Flap Jacket 03.wav',.5),
 ('punch_stone','Industry Tool Hammer Strike Cement Single 01.wav',.7),
 ('punch_wood','Industry Tool Hammer Hitting Nail Into Wood 02.wav',.65),
 ('punch_metal','Foley Metal Sheet Metal Tap 01.wav',1),
 ('jump_takeoff','Foley Cloth Hit And Short Rustle Cloth 05.wav',.55),
 ('ui_move','Science Fiction Sci-Fi Electronic Computer Terminal Button 01.wav',.25),
 ('ui_accept','Science Fiction Sci-Fi Electronic Computer Terminal Button 02.wav',.4),
 ('ui_back','Science Fiction Sci-Fi Electronic Computer Terminal Button 03.wav',.3),
]
for output,name,length in ONES:
    x,path=decode(name,0,max(length+1,6))
    x,offset=trim(x,length)
    write(output,x,path,offset,'Recorded nonvocal effect; silence trim and 5 ms edge fades; mono PCM16. Material impact/cloth recording used as action Foley stand-in.')

manifest_path=OUT/'manifest.json'
manifest=json.loads(manifest_path.read_text(encoding='utf8'))
new_files={e['file'] for e in ENTRIES}
manifest['assets']=[e for e in manifest['assets'] if e['file'] not in new_files]+ENTRIES
manifest['detail_notes']='Each material now uses 12 different recorded footfalls from one boot walking session. Nonvocal tree, bird, lake, insect, mechanical, movement, impact and UI recordings added. No pitch-shift duplicates used for footstep variation.'
manifest_path.write_text(json.dumps(manifest,indent=2),encoding='utf8')
print('Total library assets:',sum(p.stat().st_size for p in OUT.iterdir() if p.suffix in ['.wav','.ogg'])/1e6,'MB')
