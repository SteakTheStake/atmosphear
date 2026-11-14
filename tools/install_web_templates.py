"""Fetch only the web templates from the official release archive using HTTP ranges."""
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

target = Path(os.environ['APPDATA']) / 'Godot/export_templates/4.6.2.stable'
target.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(RemoteZip()) as archive:
    for info in archive.infolist():
        if Path(info.filename).name in ('web_release.zip', 'web_debug.zip', 'version.txt'):
            print('Installing', info.filename, flush=True)
            (target / Path(info.filename).name).write_bytes(archive.read(info))
print('Web templates ready:', target, flush=True)
