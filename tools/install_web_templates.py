"""Fetch Web or Windows templates from the official release using HTTP ranges."""
import argparse
import io
import os
from pathlib import Path
import urllib.request
import zipfile

URL = 'https://github.com/godotengine/godot-builds/releases/download/4.6.2-stable/Godot_v4.6.2-stable_export_templates.tpz'

class RemoteZip(io.RawIOBase):
    def __init__(self):
        response = urllib.request.urlopen(urllib.request.Request(URL, method='HEAD'))
        self.url = response.url
        self.size = int(response.headers['Content-Length'])
        self.pos = 0

    def seekable(self):
        return True

    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else (self.pos if whence == 1 else self.size) + offset
        return self.pos

    def tell(self):
        return self.pos

    def read(self, size=-1):
        end = self.size - 1 if size < 0 else min(self.size - 1, self.pos + size - 1)
        if end < self.pos:
            return b''
        req = urllib.request.Request(self.url, headers={'Range': f'bytes={self.pos}-{end}'})
        with urllib.request.urlopen(req, timeout=120) as response:
            if response.status != 206:
                raise RuntimeError('Server did not honor byte range; refusing full download')
            data = response.read()
        self.pos += len(data)
        return data

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--windows', action='store_true', help='Install Windows x64 templates instead of Web')
    args = parser.parse_args()
    target = Path(os.environ['APPDATA']) / 'Godot/export_templates/4.6.2.stable'
    names = {'windows_release_x86_64.exe', 'windows_debug_x86_64.exe', 'version.txt'} if args.windows else {'web_release.zip', 'web_debug.zip', 'version.txt'}
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(RemoteZip()) as archive:
        for info in archive.infolist():
            if Path(info.filename).name in names:
                print('Installing', info.filename, flush=True)
                # ZipFile.read validates the member CRC before writing it.
                (target / Path(info.filename).name).write_bytes(archive.read(info))
    missing = [name for name in names if not (target / name).is_file()]
    if missing:
        raise RuntimeError('Release archive lacks required templates: ' + ', '.join(missing))
    print('Windows templates ready:' if args.windows else 'Web templates ready:', target, flush=True)


if __name__ == '__main__':
    main()
