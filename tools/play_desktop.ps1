param([string]$Godot = '', [int]$AudioLatency = 30)
$ErrorActionPreference = 'Stop'
$projectPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $projectPath
try {
    $buildArgs = @('tools/build_desktop.py')
    if ($Godot) { $buildArgs += @('--godot', $Godot) }
    & python @buildArgs
    if ($LASTEXITCODE -ne 0) { throw 'Native Godot build failed. See the output above.' }
    & (Join-Path $projectPath 'build/windows/Atmosphear.exe') --audio-output-latency $AudioLatency
} finally {
    Pop-Location
}
