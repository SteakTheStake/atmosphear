"""Prepare bounded, traceable game assets from the user's local SFX library.

Requires ffmpeg and NumPy. Never changes the library originals. All audible
content comes from the named source recordings; no speech or synthesized cues.
"""
from pathlib import Path
import hashlib
import json
import subprocess
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/library'
OUT.mkdir(parents=True, exist_ok=True)
SR = 44100
FILES = {p.name: p for p in (ROOT / 'audio').rglob('*.wav')}
MANIFEST = []

def decode(name, start=0, duration=22):
    source = FILES[name]
    command = ['ffmpeg', '-v', 'error', '-ss', str(start), '-i', str(source), '-t', str(duration),
               '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-']
    raw = subprocess.check_output(command)
    samples = np.frombuffer(raw, dtype='<f4').copy()
    if len(samples) < 50:
        raise ValueError(f'Incomplete or empty source: {source}')
    return samples, source

def write(name, samples, sources, start, processing, loop, target_rms=-23):
    # Bounded gain preserves source dynamics and avoids lifting quiet noise floors excessively.
    peak = max(float(np.max(np.abs(samples))), .000001)
    rms = max(float(np.sqrt(np.mean(samples*samples))), .000001)
    if loop:
        gain = min(10**(6/20), 10**(target_rms/20)/rms, .7/peak)
    else:
        gain = min(10**(8/20), .45/peak)
    samples = np.asarray(samples*gain, dtype='<f4')
    ext = '.ogg' if loop else '.wav'
    destination = OUT/(name+ext)
    codec = ['-c:a', 'libvorbis', '-q:a', '4'] if loop else ['-c:a', 'pcm_s16le']
    subprocess.run(['ffmpeg','-v','error','-y','-f','f32le','-ar',str(SR),'-ac','1','-i','-',
                    *codec,str(destination)],input=samples.tobytes(),check=True)
    MANIFEST.append({
        'file':destination.relative_to(ROOT).as_posix(),
        'sources':[{'path':p.relative_to(ROOT).as_posix(), 'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sources],
        'source_start_seconds':start,'duration_seconds':round(len(samples)/SR,4),
        'sample_rate':SR,'channels':1,'loop':loop,'gain_db':round(20*np.log10(gain),3),
        'processing':processing, 'peak_dbfs':round(float(20*np.log10(max(np.max(np.abs(samples)),1e-9))),2),
        'selection':'Nonvocal source filenames; no narration, dialogue, crowds, or human voice assets selected.'
    })
    print(destination.name, round(len(samples)/SR,2), 'seconds',flush=True)

LOOPS = [
 ('forest_wind','Ambience Wind Blowing Through Trees 01.wav',12,24),
 ('forest_stream','Ambience Stream 01.wav',18,24),
 ('cistern_drips','Liquid Water Drips Ambience 01.wav',10,24),
 ('cistern_water','Liquid Water Flowing Through Pipe 04.wav',8,24),
 ('cistern_air','Weather Ambience Wind Blizzard Snow Whistle Gust 01.wav',14,24),
 ('freighter_engine','Ambience Boiler Room 01.wav',18,24),
 ('freighter_vent','Ambience Factory Fan 01.wav',10,24),
 ('courtyard_rain','Weather Ambience Heavy Rain Downpour Splatty 01.wav',15,24),
 ('courtyard_drain','Ambience Sewer Drain 01.wav',10,24),
 ('courtyard_wind','Weather Ambience Hurricane Storm Wind Strong Gusts 01.wav',24,24),
]
for name, source, start, duration in LOOPS:
    samples, path = decode(source,start,duration)
    n = int(.65*SR)
    phase = np.linspace(0,np.pi/2,n)
    seam = samples[-n:]*np.cos(phase)+samples[:n]*np.sin(phase)
    samples = np.concatenate([samples[n:-n],seam])
    write(name,samples,[path],start,'Mono downmix, 44.1 kHz, 650 ms equal-power wrap crossfade, bounded level adjustment, Vorbis q4',True)

# Sparse bird calls use source recordings and silence, never generated tones.
birds = np.zeros(18*SR,dtype=np.float32)
bird_paths=[]
for source, at in [('Animal Bird Western Wood Pewee Chirp 01.wav',1.3),
                   ('Animal Bird American Goldfinch Chirp 01.wav',7.2),
                   ('Animal Bird Western Wood Pewee Chirp 01.wav',13.5)]:
    clip,path=decode(source,0,3)
    n=min(int(.01*SR),len(clip)//4)
    clip[:n]*=np.linspace(0,1,n);clip[-n:]*=np.linspace(1,0,n)
    offset=int(at*SR);birds[offset:offset+len(clip)]+=clip
    if path not in bird_paths:bird_paths.append(path)
write('forest_birds',birds,bird_paths,0,'Three sparse recorded bird calls with silence between; 10 ms edge fades; Vorbis q4',True,target_rms=-28)

samples,path=decode('Science Fiction Sci-Fi Electronic Computer Processing 01.wav',0,4)
n=int(.03*SR);samples[:n]*=np.linspace(0,1,n);samples[-n:]*=np.linspace(1,0,n)
samples=np.concatenate([samples,np.zeros(int(1.5*SR))])
write('freighter_electronics',samples,[path],0,'Original electronic processing effect followed by 1.5 s silence; 30 ms edge fades; Vorbis q4',True,target_rms=-27)

STEPS = {
 'stone': ['Foley Footstep Work Boots Patio Stone Single Step 01.wav',
           'Foley Footstep Work Boots Concrete Single Step 01.wav',
           'Foley Footstep Soft Sole Work Boots Single Step On Cement 02.wav',
           'Foley Footstep Hard Sole Dress Shoe Single Step On Cement 02.wav'],
 'wood': ['Foley Footstep Cowboy Boots Single Step On Wood Board Walk 01.wav',
          'Foley Footstep Cowboy Boots Single Step On Solid Wood Platform 01.wav',
          'Foley Footstep Cowboy Boots Single Step On Solid Wood Platform 02.wav',
          'Foley Footstep Cowboy Boots Single Step On Wood Surface 01.wav'],
 'gravel': ['Foley Footstep Work Boots Dirt Debris Single Step 01.wav',
            'Foley Footstep Work Boots Leaves And Twigs Debris Single Step 01.wav',
            'Foley Footstep Baseball Cleat Dirt Debris Single Step 01.wav',
            'Foley Footstep Golf Cleats Dirt Debris Single Step 02.wav'],
 'metal': ['Foley Footstep Work Boots Metal Single Step 01.wav',
           'Foley Footstep Work Boots Metal Single Step 02.wav',
           'Foley Footstep Cowboy Boots Single Step On Metal Platform 01.wav',
           'Foley Footstep Cowboy Boots Single Step On Metal Platform 02.wav'],
}
for surface,names in STEPS.items():
    for i,name in enumerate(names):
        samples,path=decode(name,0,5)
        energy=np.convolve(samples*samples,np.ones(220)/220,'same')
        active=np.flatnonzero(energy>max(energy)*.003)
        begin=max(0,int(active[0]) - int(.012*SR))
        end=min(len(samples),int(active[-1])+int(.05*SR),begin+int(1.2*SR))
        samples=samples[begin:end]
        n=min(220,len(samples)//4)
        samples[:n]*=np.linspace(0,1,n);samples[-n:]*=np.linspace(1,0,n)
        write(surface+str(i),samples,[path],round(begin/SR,4),'Single footfall; energy-based silence trim; 5 ms edge fades; mono 44.1 kHz PCM16',False)

(OUT/'manifest.json').write_text(json.dumps({'assets':MANIFEST,'note':'Original files remain untouched in audio/. These derived clips are the only playable audio assets for the exploration prototype.'},indent=2),encoding='utf8')
print('Total derived assets:',sum(p.stat().st_size for p in OUT.iterdir() if p.suffix in ['.wav','.ogg'])/1_000_000,'MB')
