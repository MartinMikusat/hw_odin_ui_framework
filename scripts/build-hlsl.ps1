param([string]$Output = 'build/shaders')
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Push-Location $Root
try {
    New-Item -ItemType Directory -Force $Output | Out-Null
    New-Item -ItemType Directory -Force build/tools | Out-Null
    hw-odin run tools/compile_hlsl -out:build/tools/compile-hlsl.exe -thread-count:1 -warnings-as-errors -vet -strict-style -args $Output
    if ($LASTEXITCODE -ne 0) { throw "HLSL compilation failed ($LASTEXITCODE)." }
} finally {
    Pop-Location
}
