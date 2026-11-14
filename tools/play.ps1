$ErrorActionPreference = 'Stop'
$projectPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $projectPath
try {
    New-Item -ItemType Directory -Force -Path build/web | Out-Null
    New-Item -ItemType File -Force -Path build/.gdignore | Out-Null
    & python tools/build_pages.py --output build/web
    if ($LASTEXITCODE -ne 0) { throw 'Verified Godot web build failed. See the output above.' }
    Write-Host 'Open http://127.0.0.1:8060 in your browser. Press Ctrl+C here to stop.'
    & python tools/serve.py
} finally {
    Pop-Location
}
