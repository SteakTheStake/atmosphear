"""Maintain the runtime-only audio publication set without deleting local files.

Run after Godot import: python tools/package_used_audio.py --write
CI/preflight: python tools/package_used_audio.py --check
The full local provenance catalog is preserved in ignored manifest.local.json.
This tool never stages, commits, removes, or pushes files.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
LIBRARY=ROOT/'assets/library'
BEGIN='# BEGIN GENERATED USED AUDIO ALLOWLIST'
END='# END GENERATED USED AUDIO ALLOWLIST'
SUFFIXES={'.wav','.ogg','.mp3','.flac','.aif','.aiff'}

def encoded(value):
    return json.dumps(value,indent=2,ensure_ascii=False)+'\n'

def refresh_web_selection(scan):
    """Refresh only Web export_files; retain filters and every unrelated option."""
    selected=set(scan['export_roots']) | set(scan['used_audio'])
    selected.update('res://'+path.relative_to(ROOT).as_posix() for path in (ROOT/'assets/acoustics').glob('*.tres'))
    line='export_files=PackedStringArray('+', '.join(json.dumps(path) for path in sorted(selected))+')'
    path=ROOT/'export_presets.cfg'
    original=path.read_text(encoding='utf8')
    count=0
    def replace_section(match):
        nonlocal count
        header,body=match.groups()
        if not re.search(r'^platform="Web"$',body,re.M): return match.group(0)
        body,replaced=re.subn(r'^export_files=.*$',lambda _:line,body,count=1,flags=re.M)
        if not replaced: body=body.rstrip()+'\n'+line+'\n\n'
        count+=1
        return header+body
    updated=re.sub(r'(^\[preset\.\d+\]\n)(.*?)(?=^\[|\Z)',replace_section,original,flags=re.M|re.S)
    if count!=len(scan['web_presets']):
        raise SystemExit('Could not refresh every Web export preset safely.')
    if updated!=original: path.write_text(updated,encoding='utf8',newline='\n')
    return updated!=original

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group()
    mode.add_argument('--write',action='store_true')
    mode.add_argument('--check',action='store_true')
    parser.add_argument('--godot',default=os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot') or 'godot')
    args=parser.parse_args()
    result=ROOT/'test-results/used-audio-scan.json'
    result.parent.mkdir(exist_ok=True)
    subprocess.run([args.godot,'--headless','--path',str(ROOT),'--script','tools/list_used_audio.gd','--',str(result)],check=True)
    scan=json.loads(result.read_text(encoding='utf8'))
    used=sorted(p.removeprefix('res://') for p in scan['used_audio'])
    dependencies=sorted(p.removeprefix('res://') for p in scan['dependency_audio'])
    if used!=dependencies:
        raise SystemExit('Export dependency graph differs from live audio properties. Unused declarations: '+str(sorted(set(dependencies)-set(used)))+'; untracked dependencies: '+str(sorted(set(used)-set(dependencies))))
    if not scan['web_presets']: raise SystemExit('No Web export preset found.')
    for preset in scan['web_presets']:
        if preset['filter']!='resources':
            raise SystemExit('Web export must use selected-resource mode: '+preset['name'])
    if args.write and refresh_web_selection(scan):
        # Additions/removals change the explicit selection before its dependency
        # validation; --check intentionally never repairs stale publication data.
        subprocess.run([args.godot,'--headless','--path',str(ROOT),'--script','tools/list_used_audio.gd','--',str(result)],check=True)
        scan=json.loads(result.read_text(encoding='utf8'))
    for preset in scan['web_presets']:
        if preset['filter']!='resources' or not set(scan['export_roots']).issubset(preset['files']) or sorted(p.removeprefix('res://') for p in preset['audio_dependencies'])!=used:
            raise SystemExit('Web preset must select the runtime roots and only their used-audio dependencies: '+preset['name'])
    published_path=LIBRARY/'manifest.json'
    local_path=LIBRARY/'manifest.local.json'
    current=json.loads(published_path.read_text(encoding='utf8'))
    catalog=json.loads(local_path.read_text(encoding='utf8')) if local_path.exists() else current.copy()
    by_file={entry['file']:entry for entry in catalog['assets']}
    by_file.update({entry['file']:entry for entry in current['assets']})
    missing=[path for path in used if path not in by_file or not (ROOT/path).is_file()]
    if missing: raise SystemExit('Used audio needs an existing file and provenance entry: '+str(missing))
    assets=[]
    details=[]
    allow=[]
    for path in used:
        item=dict(by_file[path])
        item['asset_sha256']=hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
        assets.append(item)
        details.append({'file':path,'bytes':(ROOT/path).stat().st_size,'sha256':item['asset_sha256'],
                        'references':sorted(scan['references']['res://'+path])})
        # Explicit parent exceptions also support future subfolders under library/.
        for parent in reversed(Path(path).parents):
            if parent.as_posix() not in ('.','assets','assets/library'):
                allow.append('!/'+parent.as_posix()+'/')
        allow.append('!/'+path)
        if (ROOT/(path+'.import')).is_file(): allow.append('!/'+path+'.import')
    published={
        'schema_version':2,
        'scope':'Only AudioStream files referenced by playable scenes and their shared sound palette. Raw recordings and unused derivatives remain local.',
        'audio_rights_notice':'../../THIRD_PARTY_AUDIO.md',
        'provenance_note':'Source paths and SHA-256 values identify local source recordings; those originals are not redistributed. Compatibility alias names describe local preparation, not extra playback dependencies.',
        'assets':assets,
    }
    inventory={'schema_version':1,'export_roots':scan['export_roots'],'asset_count':len(used),
               'total_bytes':sum(entry['bytes'] for entry in details),'files':details}
    existing=(ROOT/'.gitignore').read_text(encoding='utf8')
    if BEGIN in existing:
        before,tail=existing.split(BEGIN,1)
        _,after=tail.split(END,1)
        existing=before.rstrip()+after
    block=[BEGIN,
           '# Preserve the raw library and unused derivatives locally; publish only live references.',
           '/audio/*','!/audio/.gdignore','/assets/audio/','/build/','/test-results/',
           '# New recordings anywhere in the project require an explicit used-audio entry.',
           '*.wav','*.ogg','*.mp3','*.flac','*.aif','*.aiff',
           '*.wav.import','*.ogg.import','*.mp3.import','*.flac.import','*.aif.import','*.aiff.import',
           '/assets/library/*','!/assets/library/manifest.json','!/assets/library/used_audio.json',
           *dict.fromkeys(allow),END]
    ignore=existing.rstrip()+'\n\n'+'\n'.join(block)+'\n'
    outputs={published_path:encoded(published),LIBRARY/'used_audio.json':encoded(inventory),ROOT/'.gitignore':ignore}
    drift=[str(path.relative_to(ROOT)) for path,value in outputs.items() if not path.exists() or path.read_text(encoding='utf8')!=value]
    if args.write:
        catalog['assets']=[by_file[key] for key in sorted(by_file)]
        local_path.write_text(encoded(catalog),encoding='utf8')
        for path,value in outputs.items(): path.write_text(value,encoding='utf8')
    elif drift:
        raise SystemExit('Audio packaging is stale; run --write. Changed files: '+', '.join(drift))
    # Read-only index safety: .gitignore cannot remove already tracked files.
    tracked=subprocess.run(['git','ls-files','-z'],cwd=ROOT,capture_output=True,check=False).stdout.decode('utf8').split('\0')
    bad=[path for path in tracked if path and ((path.startswith('audio/') and path!='audio/.gdignore') or (Path(path).suffix.lower() in SUFFIXES and path not in used))]
    if bad: raise SystemExit('Index already contains raw/unused audio; untrack without deleting local originals: '+str(bad))
    local_audio={p.relative_to(ROOT).as_posix() for p in LIBRARY.rglob('*') if p.suffix.lower() in SUFFIXES}
    print(json.dumps({'used_audio_files':len(used),'used_audio_bytes':inventory['total_bytes'],
                      'unused_library_files_preserved':len(local_audio-set(used)),
                      'local_catalog_entries':len(by_file),'dependency_graph_matches':True,
                      'tracked_raw_or_unused_audio':bad,'mode':'write' if args.write else 'check'},indent=2))

if __name__=='__main__': main()
