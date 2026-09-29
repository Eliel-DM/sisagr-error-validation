<#
.SYNOPSIS
    Copia todas as DLLs da versão mais recente do Coletor Biométrico
    para System32 e SysWOW64, sobrescrevendo as existentes.
.DESCRIPTION
    - Descobre dinamicamente o usuário LOGADO no computador (não o que executa o script).
    - Busca a pasta mais recente dentro de ColetorBiometrico\PROD.
    - Localiza a subpasta "Drivers".
    - Copia todas as DLLs (recursivamente) para System32 e SysWOW64.
    - Faz backup das DLLs existentes antes de sobrescrever.
    - Exibe resumo final de sucessos/falhas.
.NOTES
    Execute como Administrador (o main.ps1 já eleva automaticamente).
#>

# ============================================================
# Descobre o usuário LOGADO no computador (não o que executa)
# ============================================================
function Get-PerfilUsuarioLogado {
    # Tentativa 1: WMI — usuário interativo logado
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs.UserName) {
            $nomeUsuario = $cs.UserName.Split('\')[-1]
            $perfil = Join-Path "C:\Users" $nomeUsuario
            if (Test-Path $perfil) {
                return $perfil
            }
        }
    } catch { }

    # Tentativa 2: dono do explorer.exe
    try {
        $explorer = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
                    Select-Object -First 1
        if ($explorer) {
            $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner
            if ($owner.User) {
                $perfil = Join-Path "C:\Users" $owner.User
                if (Test-Path $perfil) {
                    return $perfil
                }
            }
        }
    } catch { }

    # Fallback
    return $env:USERPROFILE
}

# ---- Caminhos -------------------------------------------------------------
$perfilUsuario   = Get-PerfilUsuarioLogado
$caminhoBaseProd = Join-Path -Path $perfilUsuario -ChildPath "ColetorBiometrico\PROD"

$destinos = @(
    "C:\Windows\System32",
    "C:\Windows\SysWOW64"
)

# ---- Backup ---------------------------------------------------------------
$pastaBackup = Join-Path -Path $perfilUsuario -ChildPath ("Backup_DLLs_" + (Get-Date -Format "yyyyMMdd_HHmmss"))

# ---- Contadores -----------------------------------------------------------
$totalOk   = 0
$totalErro = 0

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " Instalação de Drivers Biométricos" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Usuário logado detectado: $perfilUsuario" -ForegroundColor Magenta
Write-Host ""

# ---- 1. Valida pasta base -------------------------------------------------
if (-not (Test-Path -Path $caminhoBaseProd)) {
    Write-Host "O diretório base do coletor não existe para o usuário logado:" -ForegroundColor Red
    Write-Host " -> $caminhoBaseProd" -ForegroundColor Gray
    return
}

# ---- 2. Busca a pasta de versão mais recente ------------------------------
$pastaVersao = Get-ChildItem -Path $caminhoBaseProd -Directory |
               Sort-Object LastWriteTime -Descending |
               Select-Object -First 1

if (-not $pastaVersao) {
    Write-Host "Nenhuma pasta de versão foi encontrada em: $caminhoBaseProd" -ForegroundColor Yellow
    return
}

Write-Host "Versão detectada: $($pastaVersao.Name)" -ForegroundColor Cyan

# ---- 3. Localiza a subpasta Drivers ---------------------------------------
$caminhoOrigem = Join-Path -Path $pastaVersao.FullName -ChildPath "Drivers"

if (-not (Test-Path -Path $caminhoOrigem)) {
    Write-Host "A pasta 'Drivers' não foi encontrada na versão $($pastaVersao.Name)." -ForegroundColor Red
    return
}

Write-Host "Origem dos drivers: $caminhoOrigem" -ForegroundColor Gray
Write-Host ""

# ---- 4. Lista todas as DLLs (recursivo) -----------------------------------
$dlls = Get-ChildItem -Path $caminhoOrigem -Filter "*.dll" -Recurse

if ($dlls.Count -eq 0) {
    Write-Host "Nenhum arquivo .dll foi encontrado na pasta Drivers." -ForegroundColor Yellow
    return
}

Write-Host "Localizadas $($dlls.Count) DLL(s). Iniciando cópia..." -ForegroundColor Cyan
Write-Host ""

# ---- 5. Cria pasta de backup ---------------------------------------------
New-Item -ItemType Directory -Path $pastaBackup -Force | Out-Null
Write-Host "Backup das DLLs existentes será salvo em:" -ForegroundColor DarkGray
Write-Host " -> $pastaBackup" -ForegroundColor DarkGray
Write-Host ""

# ---- 6. Copia para cada destino -------------------------------------------
foreach ($destino in $destinos) {
    Write-Host "--> Destino: $destino" -ForegroundColor Yellow
    Write-Host ""

    foreach ($dll in $dlls) {
        $arquivoDestino = Join-Path $destino $dll.Name

        # Backup se já existir
        if (Test-Path -Path $arquivoDestino) {
            try {
                Copy-Item -Path $arquivoDestino -Destination $pastaBackup -Force -ErrorAction Stop
            } catch { }
        }

        try {
            Copy-Item -Path $dll.FullName -Destination $arquivoDestino -Force -ErrorAction Stop
            Write-Host " [OK] Copiado/Substituido: $($dll.Name)" -ForegroundColor Green
            $totalOk++
        } catch {
            Write-Host " [ERRO] Falha ao copiar $($dll.Name): $_" -ForegroundColor Red
            $totalErro++
        }
    }

    Write-Host ""
}

# ---- 7. Resumo ------------------------------------------------------------
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " Resumo final" -ForegroundColor Cyan
Write-Host "  Sucessos: $totalOk" -ForegroundColor Green
Write-Host "  Falhas:   $totalErro" -ForegroundColor $(if ($totalErro -gt 0) { "Red" } else { "Green" })
Write-Host "  Backup:   $pastaBackup" -ForegroundColor DarkGray
Write-Host "=====================================" -ForegroundColor Cyan