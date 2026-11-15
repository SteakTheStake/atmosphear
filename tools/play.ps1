param([switch]$Web, [string]$Godot = '', [int]$AudioLatency = 30)
$ErrorActionPreference = 'Stop'
if (-not $Web) {
    & (Join-Path $PSScriptRoot 'play_desktop.ps1') -Godot $Godot -AudioLatency $AudioLatency
    return
}
$projectPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $projectPath
try {
    New-Item -ItemType Directory -Force -Path build/web | Out-Null
    New-Item -ItemType File -Force -Path build/.gdignore | Out-Null
    $webArgs = @('tools/build_pages.py', '--output', 'build/web')
    if ($Godot) { $webArgs += @('--godot', $Godot) }
    & python @webArgs
    if ($LASTEXITCODE -ne 0) { throw 'Verified Godot web build failed. See the output above.' }
    Write-Host 'Open http://127.0.0.1:8060 in your browser. Press Ctrl+C here to stop.'
    & python tools/serve.py
} finally {
    Pop-Location
}
