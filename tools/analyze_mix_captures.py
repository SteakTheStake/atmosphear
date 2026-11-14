"""Measure captured GAME OUTPUT, not source assets. No subjective listening claims."""
import argparse, concurrent.futures, json, math, re, subprocess
from pathlib import Path
import numpy as np
from scipy.signal import welch

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--phase',default='before')
args=parser.parse_args()
audit=json.loads((ROOT/f'test-results/mix-audit-{args.phase}.json').read_text())

def analyze(item):
    file=ROOT/item['raw_capture']
    process=subprocess.run(['ffmpeg','-hide_banner','-nostats','-i',str(file),'-af','ebur128=peak=true','-f','null','-'],capture_output=True,text=True,check=True)
    summary=process.stderr.split('Summary:')[-1]
    def metric(pattern):
        match=re.search(pattern,summary)
        return float(match[1]) if match else None
    raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(file),'-ac','1','-ar','22050','-f','f32le','-'])
    signal=np.frombuffer(raw,dtype='<f4')
    frequencies,power=welch(signal,22050,nperseg=4096)
    total=max(float(power.sum()),1e-15)
    env=np.sqrt(np.mean(signal[:len(signal)//441*441].reshape(-1,441)**2,axis=1))
    repeat=None
    if len(env)>2200:
        centered=env-env.mean();best=(-1,0)
        for lag in range(4*50,min(35*50,len(env)//2)):
            a,b=centered[:-lag],centered[lag:]
            corr=float(np.dot(a,b)/max(np.linalg.norm(a)*np.linalg.norm(b),1e-15))
            if corr>best[0]:best=(corr,lag/50)
        repeat={'envelope_correlation':round(best[0],4),'lag_seconds':best[1],'interpretation':'Strong positive correlation can expose repeated timing/envelopes; it is not itself a perceptual defect.'}
    seconds=item['audio_seconds']
    events=[{**e,'events_per_minute':round(60*e['events']/seconds,2)} for e in item.get('events',[]) if e['events'] is not None]
    return {'level':item['level'],'label':item.get('label','Walk and turn'),'capture':item['raw_capture'],'preview':item['preview'],
        'duration_seconds':round(seconds,2),'integrated_lufs':metric(r'I:\s+(-?[\d.]+) LUFS'),'loudness_range_lu':metric(r'LRA:\s+(-?[\d.]+) LU'),
        'true_peak_dbfs':metric(r'Peak:\s+(-?[\d.]+) dBFS'),'sample_peak_dbfs':round(item['peak_dbfs'],2),'rms_dbfs':round(item['rms_dbfs'],2),
        'crest_db':round(item['crest_db'],2),'low_frequency_energy_below_120hz':round(float(power[frequencies<120].sum())/total,4),
        'high_frequency_energy_above_4khz':round(float(power[frequencies>4000].sum())/total,4),
        'quiet_windows_below_minus60dbfs_fraction':round(item['quiet_window_fraction'],4),'envelope_p95_p05_db':round(item['envelope_p95_p05_db'],2),
        'clipped_samples':item['clipped_samples'],'event_counts':events,'long_capture_repeat_metric':repeat}

items=audit.get('areas',[])+audit.get('walks',[])+audit.get('longs',[])
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: results=list(pool.map(analyze,items))
areas=results[:len(audit.get('areas',[]))]
summary={'areas':len(areas),'walking_captures':len(audit.get('walks',[])),'long_captures':len(audit.get('longs',[])),
    'rms_range_dbfs':[min((x['rms_dbfs'] for x in areas),default=None),max((x['rms_dbfs'] for x in areas),default=None)],
    'highest_true_peak_dbfs':max((x['true_peak_dbfs'] for x in results if x['true_peak_dbfs'] is not None),default=None),'clipped_samples':sum(x['clipped_samples'] for x in results)}
out={'phase':args.phase,'method':'Actual browser-mix PCM captures: FFmpeg EBU R128 integrated loudness/true peak, Welch spectral energy, live sample peaks and scheduler event counters.',
    'limits':['Short-capture LUFS and loudness range depend on which intermittent events occurred.','No headphone sound pressure calibration: dBFS/LUFS are digital levels, not perceived absolute loudness.','Measurements do not replace the separate audio-input model review.','Event sampling has approximately250ms timing granularity; event_count retains short events between snapshots.'],
    'summary':summary,'captures':results}
(ROOT/f'test-results/mix-measurements-{args.phase}.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(summary))
for x in sorted(areas,key=lambda x:x['rms_dbfs'],reverse=True): print(f"{x['level']}/{x['label']}: RMS{x['rms_dbfs']:.1f}dBFS peak{x['sample_peak_dbfs']:.1f}dBFS I{x['integrated_lufs']}LUFS")
