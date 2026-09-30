$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force build/test | Out-Null
    & ./scripts/build-hlsl.ps1 -Output build/test/shaders
    hw-odin run tests/directwrite_layout "-collection:ui_framework=$PSScriptRoot" -out:build/test/directwrite-layout.exe -thread-count:1 -warnings-as-errors -vet -strict-style
    if ($LASTEXITCODE -ne 0) { throw "DirectWrite checks failed ($LASTEXITCODE)." }
} finally {
    Pop-Location
}
