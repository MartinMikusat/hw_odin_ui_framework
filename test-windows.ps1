$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    New-Item -ItemType Directory -Force build/test | Out-Null
    & ./scripts/build-hlsl.ps1 -Output build/test/shaders
    hw-odin check d3d11 -no-entry-point "-collection:ui_framework=$PSScriptRoot" -thread-count:1 -warnings-as-errors -vet -strict-style
    if ($LASTEXITCODE -ne 0) { throw "Direct3D 11 checks failed ($LASTEXITCODE)." }
    hw-odin run tests/d3d11_resources "-collection:ui_framework=$PSScriptRoot" -out:build/test/d3d11-resources.exe -thread-count:1 -warnings-as-errors -vet -strict-style -define:UI_FRAMEWORK_TEST_MODE=true
    if ($LASTEXITCODE -ne 0) { throw "Direct3D 11 resource checks failed ($LASTEXITCODE)." }
    hw-odin run tests/directwrite_layout "-collection:ui_framework=$PSScriptRoot" -out:build/test/directwrite-layout.exe -thread-count:1 -warnings-as-errors -vet -strict-style
    if ($LASTEXITCODE -ne 0) { throw "DirectWrite checks failed ($LASTEXITCODE)." }
} finally {
    Pop-Location
}
