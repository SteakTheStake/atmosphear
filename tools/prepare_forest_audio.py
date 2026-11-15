"""Prepare only used forest recordings; preserve raw library and source provenance."""
from pathlib import Path
import hashlib,json,subprocess
import numpy as np

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'assets/library';SR=44100
def decode(p,seconds=40):
    return np.frombuffer(subprocess.check_output(['ffmpeg','-v','error','-i',str(p),'-t',str(seconds),'-ar',str(SR),'-ac','1','-f','f32le','-']),dtype='<f4').copy()
def locate(name):
    matches=list((ROOT/'audio').rglob(name));assert len(matches)==1,(name,len(matches));return matches[0]
entries=[]
def save(name,x,sources,loop=False,note=''):
    x=x.astype('<f4');x-=x.mean()
    if loop:
        n=min(int(.65*SR),len(x)//5);t=np.linspace(0,np.pi/2,n)
        x=np.concatenate([x[n:-n],x[-n:]*np.cos(t)+x[:n]*np.sin(t)])
    else:
        n=min(int(.008*SR),len(x)//5);x[:n]*=np.linspace(0,1,n);x[-n:]*=np.linspace(1,0,n)
    target=.085 if loop else .14
    gain=min(target/max(np.sqrt(np.mean(x*x)),1e-7),(.65 if not loop else .58)/max(abs(x).max(),1e-7),12)
    x=np.asarray(x*gain,dtype='<f4');path=OUT/name
    codec=['-c:a','libvorbis','-q:a','5'] if loop else ['-c:a','pcm_s16le']
    subprocess.run(['ffmpeg','-v','error','-y','-f','f32le','-ar',str(SR),'-ac','1','-i','-',*codec,str(path)],input=x.tobytes(),check=True)
    check=decode(path);assert np.isfinite(check).all() and abs(check).max()<.92
    entries.append({'file':path.relative_to(ROOT).as_posix(),'sources':[{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in sources],
      'sample_rate':SR,'channels':1,'loop':loop,'duration_seconds':round(len(x)/SR,5),'gain_db':round(float(20*np.log10(gain)),3),
      'peak_dbfs':round(float(20*np.log10(abs(check).max())),3),'rms_dbfs':round(float(20*np.log10(np.sqrt(np.mean(check*check)))),3),'processing':note+'; DC removed, natural attack preserved, short edge fades; no chorus, pitch modulation or baked reverb.'})
def steps(paths,count=8):
    clips=[]
    for path in paths:
        x=decode(path);hop=441;frames=len(x)//hop
        rms=np.sqrt(np.mean(x[:frames*hop].reshape(-1,hop)**2,axis=1));strength=np.maximum(0,rms-np.roll(rms,3))
        selected=[]
        for k in np.argsort(strength)[::-1]:
            t=k*hop
            if strength[k]<max(strength.max()*.12,.001):break
            if t<int(.025*SR) or t>len(x)-int(.15*SR) or any(abs(t-s)<.38*SR for s in selected):continue
            selected.append(t)
        for t in sorted(selected):
            clips.append(x[max(0,t-int(.03*SR)):min(len(x),t+int(.32*SR))])
    assert len(clips)>=2,[str(p) for p in paths]
    return [clips[i%len(clips)].copy() for i in range(count)]
def main():
    raw={
      'grass':[locate('Foley Footstep Human Walking Through Tall Grass 01.wav'),locate('Foley Footstep Human Walking Through Tall Grass 02.wav')],
      'dirt':[locate('Foley Footstep Work Boots Dirt Debris Walking 01.wav'),locate('Foley Footstep Work Boots Dirt Debris Walking 02.wav')],
      'forest_litter':[locate('Foley Footstep Boots Walking On Leaves 01.wav'),locate('Foley Footstep Work Boots Leaves And Twigs Debris Slow Walking 01.wav')],
      'water':[locate('Liquid Water Water Footsteps Walking In Water 03.wav'),locate('Liquid Water Water Footsteps Walking In Water 04.wav')],
      'sand':[ROOT/'assets/library'/f'gravel{i}.wav' for i in range(8)]}
    # The library has no dedicated sand steps. Filtered real granular footfalls
    # provide a documented approximation, rather than inventing a sand recording.
    pools={key:steps(paths) for key,paths in raw.items() if key!='sand'}
    pools['sand']=[decode(p,1.5) for p in raw['sand']]
    for kind in ['grass','dirt','forest_litter','sand','water','wet_dirt','wet_sand','marsh']:
        for i in range(8):
            base='dirt' if kind in ['wet_dirt','marsh'] else ('sand' if kind=='wet_sand' else kind)
            x=pools[base][i].copy();sources=list(raw[base])
            if base=='sand':
                # A broad spectral reduction of gravel crunch, no time smearing.
                n=len(x);freq=np.fft.rfftfreq(n,1/SR);x=np.fft.irfft(np.fft.rfft(x)/(1+(freq/1700)**2),n)
            if kind in ['wet_dirt','wet_sand','marsh']:
                w=pools['water'][i];n=max(len(x),len(w));a=np.zeros(n);b=np.zeros(n);a[:len(x)]=x;b[:len(w)]=w
                a/=max(abs(a).max(),1e-5);b/=max(abs(b).max(),1e-5)
                x=a*.72+b*({'wet_dirt':.22,'wet_sand':.13,'marsh':.46}[kind]);sources+=raw['water']
            save(f'forest_step_{kind}_{i}.wav',x,sources,note='One isolated footfall; '+('granular-footstep sand approximation' if base=='sand' else 'recorded '+kind.replace('_',' ')))
    for name,source in [('forest_river_flow.ogg','Liquid Water River Flowing Water 02.wav'),('forest_stream_detail.ogg','Ambience Stream 01.wav'),('forest_ocean_surf.ogg','Ambience Ocean Shore 01.wav')]:
        p=locate(source);x=decode(p,32)
        # Remove infrasonic rumble without dulling bird/leaf detail elsewhere.
        n=len(x);freq=np.fft.rfftfreq(n,1/SR);x=np.fft.irfft(np.fft.rfft(x)*(freq/np.maximum(freq,75))**2,n)
        save(name,x,[p],True,'Mono point-source ambience; 75Hz rumble reduction; 650ms loop wrap')
    path=OUT/'manifest.local.json';catalog=json.loads(path.read_text(encoding='utf8'))
    owned={e['file'] for e in entries};catalog['assets']=[e for e in catalog['assets'] if e['file'] not in owned]+entries
    path.write_text(json.dumps(catalog,indent=2)+'\n',encoding='utf8')
    (ROOT/'test-results/forest_audio_preparation.json').write_text(json.dumps(entries,indent=2),encoding='utf8')
    print('Prepared',len(entries),'used forest audio assets, with provenance.')
if __name__=='__main__':main()
