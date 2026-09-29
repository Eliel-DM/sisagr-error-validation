<#
.SYNOPSIS
    Menu principal que chama scripts de ação.
.DESCRIPTION
    Exibe um menu numerado e invoca scripts .ps1 localizados na pasta "scripts".
    Solicita elevação (UAC) automaticamente quando necessário.
.NOTES
    Salve este arquivo como "main.ps1".
    Estrutura esperada:
        src\
        ├── main.ps1
        └── scripts\
            ├── leitor-biometrico.ps1
            └── limparTempJava.ps1
#>

# ============================================================
# AUTO-ELEVAÇÃO (reabre como Administrador se necessário)
# ============================================================
$usuarioAtual = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
$ehAdmin = $usuarioAtual.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $ehAdmin) {
    Write-Host "Solicitando privilégios de Administrador..." -ForegroundColor Yellow

    $caminhoScript = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($caminhoScript)) {
        $caminhoScript = $MyInvocation.MyCommand.Path
    }
    if ([string]::IsNullOrWhiteSpace($caminhoScript)) {
        Write-Host "ERRO: não foi possível determinar o caminho do main.ps1." -ForegroundColor Red
        Read-Host "Pressione Enter"
        exit 1
    }

    $pastaScript  = Split-Path -Path $caminhoScript -Parent
    $launcherPath = Join-Path $env:TEMP "launch_main.ps1"

    $conteudoLauncher = @"
Set-Location -Path '$pastaScript'
& '$caminhoScript'
"@
    $conteudoLauncher | Out-File -FilePath $launcherPath -Encoding UTF8 -Force

    try {
        Start-Process -FilePath "powershell.exe" `
            -ArgumentList @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-NoExit",
                "-File", "`"$launcherPath`""
            ) `
            -Verb RunAs
    } catch {
        Write-Host "Não foi possível elevar: $_" -ForegroundColor Red
        Read-Host "Pressione Enter"
    }
    exit
}
# ============================================================
# A partir daqui, o script roda como Administrador
# ============================================================


function Executar-Script {
    param(
        [string]$CaminhoScript,
        [string]$Titulo
    )

    Clear-Host
    Write-Host "=== $Titulo ===" -ForegroundColor Yellow
    Write-Host ""

    if (Test-Path -Path $CaminhoScript) {
        & $CaminhoScript
    } else {
        Write-Host "Erro: O script não foi encontrado no caminho:" -ForegroundColor Red
        Write-Host " -> $CaminhoScript" -ForegroundColor Gray
    }

    Write-Host ""
    Read-Host "Pressione Enter para voltar ao menu..." | Out-Null
}


function Main {
    # Resolve a pasta "scripts" a partir da pasta onde o main.ps1 está salvo
    $pastaScripts = Join-Path -Path $PSScriptRoot -ChildPath "scripts"

    do {
        Clear-Host
        Write-Host "========== MENU PRINCIPAL ==========" -ForegroundColor Cyan
        Write-Host " 1 - Drivers Coletor Biométrico"
        Write-Host " 2 - Limpar arquivos temporários e cache Java"
        Write-Host " 0 - Sair"
        Write-Host "====================================" -ForegroundColor Cyan

        $opcao = Read-Host "Digite o número da opção desejada"

        switch ($opcao) {
            '1' {
                Executar-Script -CaminhoScript (Join-Path $pastaScripts "leitor-biometrico.ps1") `
                                -Titulo "Instalação de Drivers"
            }
            '2' {
                Executar-Script -CaminhoScript (Join-Path $pastaScripts "limparTempJava.ps1") `
                                -Titulo "Limpeza de Temp e Cache Java"
            }
            '0' {
                Write-Host "Saindo do programa..." -ForegroundColor Green
            }
            default {
                Write-Host "Opção inválida! Tente novamente." -ForegroundColor Red
                Pause
            }
        }
    } while ($opcao -ne '0')
}

Main