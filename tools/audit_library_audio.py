"""Read-only signal/provenance audit. This is not a perceptual listening test."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse
import hashlib
import json
import subprocess
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
MANIFEST=ROOT/'assets/library/manifest.json'
DEST=ROOT/'test-results/library-signal-audit.json'

def measure(entry):
    path=ROOT/entry['file']
    probe=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','stream=sample_rate,channels,codec_name','-of','json',str(path)]))['streams'][0]
    data=subprocess.check_output(['ffmpeg','-v','error','-i',str(path),'-ac','1','-ar','44100','-f','f32le','-'])
    x=np.frombuffer(data,dtype='<f4')
    peak=float(np.max(np.abs(x)));rms=float(np.sqrt(np.mean(x*x)))
    diff=np.abs(np.diff(x));p99=float(np.percentile(diff,99))
    envelope=np.array([np.sqrt(np.mean(x[i:i+2205]**2)) for i in range(0,len(x),2205)])
    env_db=20*np.log10(np.maximum(envelope,1e-10))
    row={
        'file':entry['file'],'bytes':path.stat().st_size,'duration_seconds':round(len(x)/44100,6),
        'sample_rate':int(probe['sample_rate']),'channels':int(probe['channels']),'codec':probe['codec_name'],
        'finite':bool(np.isfinite(x).all()),'peak_dbfs':round(float(20*np.log10(max(peak,1e-10))),3),
        'rms_dbfs':round(float(20*np.log10(max(rms,1e-10))),3),
        'crest_db':round(float(20*np.log10(max(peak,1e-10)/max(rms,1e-10))),3),
        'clipped_sample_count':int(np.count_nonzero(np.abs(x)>=.999)),
        'envelope_p95_p05_db':round(float(np.percentile(env_db,95)-np.percentile(env_db,5)),3),
        'loop':entry['loop'],'output_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
        'sources':entry['sources'],'source_start_seconds':entry.get('source_start_seconds'),
        'application':entry.get('application',''),'alias_of':entry.get('alias_of'),
    }
    if entry['loop']:
        jump=float(abs(x[-1]-x[0]))
        row['seam_jump_dbfs']=round(float(20*np.log10(max(jump,1e-10))),3)
        row['seam_jump_relative_to_p99_sample_difference']=round(jump/max(p99,1e-10),4)
        edge=min(len(x)//4,2205)
        front=float(np.sqrt(np.mean(x[:edge]**2)));tail=float(np.sqrt(np.mean(x[-edge:]**2)))
        row['seam_edge_rms_delta_db']=round(float(abs(20*np.log10(max(front,1e-10)/max(tail,1e-10)))),3)
    return row

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-sources',action='store_true',help='Fail if raw source recordings are unavailable locally.')
    parser.add_argument('--all-local',action='store_true',help='Audit the ignored full local catalog, including unused derivatives.')
    args=parser.parse_args()
    manifest_path=ROOT/'assets/library/manifest.local.json' if args.all_local else MANIFEST
    manifest=json.loads(manifest_path.read_text(encoding='utf8'))
    entries=manifest['assets'];filenames=[e['file'] for e in entries]
    assert len(filenames)==len(set(filenames)),'Duplicate manifest filename'
    with ThreadPoolExecutor(max_workers=4) as pool: rows=list(pool.map(measure,entries))
    originals={s['path']:s['sha256'] for e in entries for s in e['sources']}
    source_checks=[]
    for path,expected in originals.items():
        file=ROOT/path
        actual=hashlib.sha256(file.read_bytes()).hexdigest() if file.is_file() else None
        source_checks.append({'path':path,'exists':file.is_file(),'sha256_matches':actual==expected})
    failures=[r['file'] for r in rows if not r['finite'] or r['clipped_sample_count'] or r['sample_rate']!=44100 or r['channels']!=1]
    failures.extend(s['path'] for s in source_checks if (s['exists'] and not s['sha256_matches']) or (args.require_sources and not s['exists']))
    loops=[r for r in rows if r['loop']]
    new_loops=[r for r in loops if Path(r['file']).name.startswith(('canopy','wind_shaft','wind_open','water_flow'))]
    report={
        'method':'FFmpeg decoded PCM measurements, source SHA-256 verification, manifest provenance. No listening audition or semantic audio-content verification claimed.',
        'summary':{'asset_count':len(rows),'total_bytes':sum(r['bytes'] for r in rows),'loop_count':len(loops),
                   'source_recording_count':len(originals),'all_sources_sha256_match':all(s['sha256_matches'] for s in source_checks),
                   'missing_local_source_count':sum(not s['exists'] for s in source_checks),
                   'maximum_peak_dbfs':max(r['peak_dbfs'] for r in rows),'clipped_samples':sum(r['clipped_sample_count'] for r in rows),
                   'new_loop_worst_seam_jump_to_p99_ratio':max(r['seam_jump_relative_to_p99_sample_difference'] for r in new_loops),'failures':failures},
        'new_loop_details':new_loops,'assets':rows,'source_checks':source_checks,
        'interpretation_limits':['Four canopy loops are separate passages of one explicitly tree-wind take, not four independent recordings.',
            'Four pipe rings are separate time excerpts of one actual pipe-vibration take, not four independent thermal ticks.',
            'Compatibility aliases duplicate their named primary; they must not be counted as extra variants.',
            'Seam discontinuity is compared to the recording\'s own99th-percentile sample derivative; this numerical test does not prove perceptual seamlessness.',
            'Active scene/palette assignments and rejected-context checks are validated separately by tests/context_audio.gd.']}
    DEST.parent.mkdir(exist_ok=True)
    DEST.write_text(json.dumps(report,indent=2),encoding='utf8')
    print(json.dumps(report['summary'],indent=2))
    print(DEST)
    if failures: raise SystemExit(1)

if __name__=='__main__':main()
