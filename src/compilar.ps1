$ErrorActionPreference = "Stop"

$srcDir   = "C:\projetos\sisagr-error-validation\src"
$input    = Join-Path $srcDir "combined.ps1"
$finalExe = "C:\projetos\sisagr-error-validation\ColetorBiometrico.exe"

Import-Module ps2exe -Force

Write-Host "Compilando $input -> $finalExe ..." -ForegroundColor Cyan

Invoke-PS2EXE -InputFile $input `
              -OutputFile $finalExe `
              -Title "Coletor Biometrico" `
              -Description "Instalador de drivers e limpeza de cache Java" `
              -Company "SISAGR" `
              -Product "Coletor Biometrico" `
              -Version "1.0.0" `
              -RequireAdmin

if (Test-Path $finalExe) {
    $kb = [math]::Round((Get-Item $finalExe).Length / 1KB, 1)
    Write-Host "SUCESSO! ColetorBiometrico.exe gerado ($kb KB)" -ForegroundColor Green
} else {
    Write-Host "FALHA ao gerar o EXE." -ForegroundColor Red
    exit 1
}