<#
.SYNOPSIS
    Combina os scripts do projeto em um único .ps1 e opcionalmente compila para .exe.
.DESCRIPTION
    Lê os scripts auxiliares, embrulha cada um em uma função, e gera um
    combined.ps1 com o menu principal adaptado.

    Uso:
        .\build.ps1                   # só gera o combined.ps1
        .\build.ps1 -Compile          # gera + compila com console
        .\build.ps1 -Compile -NoConsole  # gera + compila sem console
.PARAMETER Compile
    Compila o combined.ps1 em ColetorBiometrico.exe via PS2EXE.
.PARAMETER NoConsole
    Gera EXE sem janela de console (modo GUI).
#>

param(
    [switch]$Compile,
    [switch]$NoConsole
)

$ErrorActionPreference = "Stop"

# ── Caminhos ──────────────────────────────────────────────────────────────
$projectRoot  = $PSScriptRoot
$srcDir       = Join-Path $projectRoot "src"
$scriptsDir   = Join-Path $srcDir "scripts"
$outputFile   = Join-Path $srcDir "combined.ps1"
$exeOutput    = Join-Path $projectRoot "ColetorBiometrico.exe"
$iconFile     = Join-Path $projectRoot "icone.ico"

# ── Arquivos de entrada ──────────────────────────────────────────────────
$leitorScript = Join-Path $scriptsDir "leitor-biometrico.ps1"
$limparScript = Join-Path $scriptsDir "limparTempJava.ps1"
$mainScript   = Join-Path $srcDir "main.ps1"

# ── Validação dos arquivos de entrada ────────────────────────────────────
foreach ($path in @($leitorScript, $limparScript, $mainScript)) {
    if (-not (Test-Path $path)) {
        Write-Host "ERRO: Arquivo nao encontrado: $path" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Lendo scripts..." -ForegroundColor Cyan

# ── Lê os scripts auxiliares e embrulha em funções ──────────────────────
$leitorConteudo = Get-Content -Raw $leitorScript -Encoding UTF8
$limparConteudo = Get-Content -Raw $limparScript -Encoding UTF8

$leitorWrapper = @"
# ============================================================
# Script embrulhado: leitor-biometrico.ps1
# ============================================================
function Invoke-InstalarDrivers {
$leitorConteudo
}
"@

$limparWrapper = @"
# ============================================================
# Script embrulhado: limparTempJava.ps1
# ============================================================
function Invoke-LimparTempJava {
$limparConteudo
}
"@

# ── Lê e adapta o main.ps1 ──────────────────────────────────────────────
$linhas = Get-Content $mainScript -Encoding UTF8
$novasLinhas = @()
$dentroExecutarScript = 0
$dentroSwitchCase1 = $false
$dentroSwitchCase2 = $false

# Função Executar-Script modificada (aceita scriptblock)
$novoExecutarScript = @"
function Executar-Script {
    param(
        [scriptblock]`$Bloco,
        [string]`$Titulo
    )

    Clear-Host
    Write-Host "=== `$Titulo ===" -ForegroundColor Yellow
    Write-Host ""

    if (`$null -ne `$Bloco) {
        & `$Bloco
    } else {
        Write-Host "Erro: Bloco de script nulo." -ForegroundColor Red
    }

    Write-Host ""
    Read-Host "Pressione Enter para voltar ao menu..." | Out-Null
}
"@

foreach ($linha in $linhas) {
    # Pula a definição antiga da função Executar-Script (usando brace depth)
    if ($linha -match '^function Executar-Script\b') {
        $dentroExecutarScript = 1  # já conta a { da linha de definição
        continue
    }
    if ($dentroExecutarScript -gt 0) {
        # Conta { e } para saber quando a função realmente termina
        foreach ($c in $linha.ToCharArray()) {
            if ($c -eq '{') { $dentroExecutarScript++ }
            if ($c -eq '}') { $dentroExecutarScript-- }
        }
        if ($dentroExecutarScript -eq 0) {
            $novasLinhas += $novoExecutarScript
        }
        continue
    }

    # Detecta início dos cases '1' e '2' no switch
    if ($linha -match "'1'\s*\{") {
        $novasLinhas += $linha
        $dentroSwitchCase1 = $true
        continue
    }
    if ($linha -match "'2'\s*\{") {
        $novasLinhas += $linha
        $dentroSwitchCase2 = $true
        continue
    }

    # Substitui linha do Executar-Script dentro do case '1' /
    if ($dentroSwitchCase1 -and $linha -match 'Executar-Script') {
        $novasLinhas += "                Executar-Script -Bloco `${function:Invoke-InstalarDrivers} -Titulo `"Instalação/Atualização de Drivers`""
        continue
    }
    # Substitui linha do Executar-Script dentro do case '2'
    if ($dentroSwitchCase2 -and $linha -match 'Executar-Script') {
        $novasLinhas += "                Executar-Script -Bloco `${function:Invoke-LimparTempJava} -Titulo `"Limpeza de Temp e Cache Java`""
        continue
    }

    # Fim dos cases: linha com '}'
    if ($dentroSwitchCase1 -and $linha.Trim() -eq '}') {
        $novasLinhas += $linha
        $dentroSwitchCase1 = $false
        continue
    }
    if ($dentroSwitchCase2 -and $linha.Trim() -eq '}') {
        $novasLinhas += $linha
        $dentroSwitchCase2 = $false
        continue
    }

    # Pula linha -Titulo dentro dos cases
    if ($dentroSwitchCase1 -or $dentroSwitchCase2) {
        continue
    }

    $novasLinhas += $linha
}

$mainModificado = $novasLinhas -join "`r`n"

# ── Monta o combined.ps1 ──────────────────────────────────────────────────
$cabecalho = @"
<#
.SYNOPSIS
    Script combinado - Coletor Biometrico + Limpeza Java.
.DESCRIPTION
    Gerado automaticamente pelo build.ps1 em $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss').
    Compila todos os modulos em um unico arquivo para distribuicao via PS2EXE.
.NOTES
    Nao edite este arquivo manualmente - ele e gerado pelo build.ps1.
#>

#Requires -RunAsAdministrator

"@

$combined = $cabecalho + "`r`n" + $leitorWrapper + "`r`n`r`n" + $limparWrapper + "`r`n`r`n" + $mainModificado

# ── Salva ──────────────────────────────────────────────────────────────────
$combined | Out-File -FilePath $outputFile -Encoding UTF8 -Force
Write-Host "combined.ps1 gerado em: $outputFile" -ForegroundColor Green

# ── Compilação opcional ────────────────────────────────────────────────────
if ($Compile) {
    if (-not (Get-Module -ListAvailable -Name ps2exe)) {
        Write-Host "ERRO: Modulo ps2exe nao encontrado. Instale com:" -ForegroundColor Red
        Write-Host "  Install-Module -Name ps2exe -Scope CurrentUser -Force" -ForegroundColor Yellow
        exit 1
    }

    Import-Module ps2exe -Force -ErrorAction Stop

    $parametros = @{
        InputFile    = $outputFile
        OutputFile   = $exeOutput
        Title        = "Coletor Biometrico"
        Description  = "Instalador de drivers e limpeza de cache Java"
        Company      = "SISAGR"
        Product      = "Coletor Biometrico"
        Version      = "1.0.0"
        RequireAdmin = $true
    }

    if ($NoConsole) {
        $parametros.NoConsole = $true
    }

    if (Test-Path $iconFile) {
        $parametros.IconFile = $iconFile
    }

    Write-Host "Compilando EXE..." -ForegroundColor Cyan
    Invoke-PS2EXE @parametros

    if (Test-Path $exeOutput) {
        Write-Host "OK EXE gerado em: $exeOutput" -ForegroundColor Green
    } else {
        Write-Host "ERRO: Falha ao gerar o EXE." -ForegroundColor Red
        exit 1
    }
}

Write-Host "Concluido." -ForegroundColor Green