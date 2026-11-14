"""Stage only referenced recordings and the shared-clock browser renderer."""
import json,shutil,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
out=Path(sys.argv[1]).resolve()
inventory=json.loads((root/'assets/library/used_audio.json').read_text())
sound=out/'sound'
sound.mkdir(exist_ok=True)
expected={Path(a['file']).name for a in inventory['files']}
for old in sound.iterdir():
    if old.is_file() and old.name not in expected: old.unlink()
for asset in inventory['files']:
    shutil.copyfile(root/asset['file'],sound/Path(asset['file']).name)
html=out/'index.html'
s=html.read_text(encoding='utf8')
assert '/* ATMO_ACOUSTICS */' in s
s=s.replace('/* ATMO_ACOUSTICS */',(root/'web/acoustics.js').read_text(encoding='utf8'))
html.write_text(s,encoding='utf8')
print('Staged browser renderer and',len(expected),'used audio files')
