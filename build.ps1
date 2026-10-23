<#
.SYNOPSIS
    Gera o ColetorBiometrico.msi a partir dos scripts em src\.

.DESCRIPTION
    Usa o WiX Toolset v3 (candle.exe + light.exe) para empacotar os scripts
    .ps1 em um instalador MSI per-machine. O payload nao contem nenhum binario
    compilado, apenas os scripts e um atalho que invoca powershell.exe.

.PARAMETER Version
    Versao do produto. Padrao: 1.0.0

.PARAMETER WixBin
    Caminho da pasta bin do WiX Toolset v3. Se omitido, procura em
    <repo>\tools\wix e depois em C:\Program Files (x86)\WiX Toolset v3*.

.EXAMPLE
    .\build.ps1
    .\build.ps1 -Version 1.1.0
    .\build.ps1 -WixBin "$env:LOCALAPPDATA\wix\extracted"

.NOTES
    Pre-requisito: choco install wixtoolset -y
#>

[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = "1.0.0",

    [string]$WixBin
)

$ErrorActionPreference = "Stop"

$projectRoot   = $PSScriptRoot
$installerDir = Join-Path $projectRoot "installer"
$wxs          = Join-Path $installerDir "Product.wxs"
$objDir       = Join-Path $projectRoot "build\obj"
$msiOutput    = Join-Path $projectRoot "ColetorBiometrico.msi"

# ── Valida entradas ───────────────────────────────────────────────────────
$inputs = @(
    (Join-Path $projectRoot "src\main.ps1")
    (Join-Path $projectRoot "src\scripts\leitor-biometrico.ps1")
    (Join-Path $projectRoot "src\scripts\limparTempJava.ps1")
)

foreach ($file in @($wxs) + $inputs) {
    if (-not (Test-Path $file)) {
        Write-Host "ERRO: arquivo nao encontrado: $file" -ForegroundColor Red
        exit 1
    }
}

# ── Localiza o WiX ────────────────────────────────────────────────────────
# Ordem de busca:
#   1. -WixBin explícito
#   2. <repo>\tools\wix (portátil, sem necessidade de instalar)
#   3. instalação em C:\Program Files (x86)\WiX Toolset v3*
# Ordena por nome decrescente para pegar a maior versao (v3.14 > v3.11).
$wixCandidates = @(
    $WixBin
    (Join-Path $projectRoot "tools\wix")
    (Get-ChildItem "C:\Program Files (x86)\WiX Toolset v3*" -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "bin" })
) | Where-Object { $_ -and (Test-Path (Join-Path $_ "candle.exe")) }

$wixBin = $wixCandidates | Select-Object -First 1

if (-not $wixBin) {
    Write-Host "ERRO: WiX Toolset v3 nao encontrado." -ForegroundColor Red
    Write-Host "  Instale com:  choco install wixtoolset -y" -ForegroundColor Yellow
    Write-Host "  Ou extraia o portatil em: $projectRoot\tools\wix" -ForegroundColor Yellow
    exit 1
}

$candle = Join-Path $wixBin "candle.exe"
$light  = Join-Path $wixBin "light.exe"

Write-Host "WiX: $wixBin" -ForegroundColor DarkGray

# ── Aplica a versao no .wxs ───────────────────────────────────────────────
# Substitui apenas o atributo Version do elemento Product, sem tocar no
# ProductVersion do schema nem em outros atributos.
$wxsContent = Get-Content $wxs -Raw -Encoding UTF8
$wxsContent = $wxsContent -replace '(?s)(<Product\b.*?Version=")[^"]*(")', "`${1}$Version`${2}"
Set-Content -Path $wxs -Value $wxsContent -Encoding UTF8 -NoNewline

# ── Build ─────────────────────────────────────────────────────────────────
if (Test-Path $objDir) {
    Remove-Item $objDir -Recurse -Force
}
New-Item -Path $objDir -ItemType Directory -Force | Out-Null

$wixobj = Join-Path $objDir "Product.wixobj"

Push-Location $installerDir
try {
    Write-Host "[1/2] candle.exe - compilando o .wxs..." -ForegroundColor Cyan
    # -fips e exigido em maquinas com FIPS habilitado (padrao em ambiente
    # corporativo); sem ele o candle aborta com CNDL0308.
    # Os GUIDs estaveis vem de Guid="*" nos <Component> do .wxs.
    & $candle -nologo -arch x64 -ext WixUIExtension -fips -out $wixobj $wxs
    if ($LASTEXITCODE -ne 0) {
        throw "candle.exe falhou com codigo $LASTEXITCODE"
    }

    Write-Host "[2/2] light.exe - linkando o MSI (validacao ICE)..." -ForegroundColor Cyan
    # -sice: o atalho vive em ProgramMenuFolder (per-user por natureza) mas o
    # pacote e per-machine com keypath em HKLM. E o padrao recomendado pela
    # Microsoft para Start Menu shortcuts em pacotes admin, e dispara ICE38 /
    # ICE43 / ICE57 por analise estatica de diretorio. Ver comentario no .wxs.
    & $light -nologo -ext WixUIExtension -cultures:pt-BR `
        -sice:ICE38 -sice:ICE43 -sice:ICE57 `
        -out $msiOutput $wixobj
    if ($LASTEXITCODE -ne 0) {
        throw "light.exe falhou com codigo $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

if (-not (Test-Path $msiOutput)) {
    Write-Host "ERRO: o MSI nao foi gerado." -ForegroundColor Red
    exit 1
}

$kb = [math]::Round((Get-Item $msiOutput).Length / 1KB, 1)

Write-Host ""
Write-Host "SUCESSO: $msiOutput ($kb KB) - versao $Version" -ForegroundColor Green
Write-Host ""
Write-Host "Instalar:     msiexec /i `"$msiOutput`"" -ForegroundColor Gray
Write-Host "Desinstalar:  msiexec /x `"$msiOutput`"" -ForegroundColor Gray