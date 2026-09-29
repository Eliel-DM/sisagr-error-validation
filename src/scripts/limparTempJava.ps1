<#
.SYNOPSIS
    Encerra processos Java, limpa temp/cache, reabre os Java que estavam rodando
    e informa a versão do Java instalado.
.DESCRIPTION
    Etapas:
      1. Detecta a(s) versão(ões) de Java instalada(s).
      2. Descobre o usuário LOGADO no computador (não o que executa o script).
      3. Registra os processos Java em execução (nome, argumentos, PID).
      4. Finaliza processos Java (java.exe, javaw.exe, javaws.exe, javac.exe,
         jp2launcher.exe) e processos que carregaram a JVM (jvm.dll).
      5. Limpa temp + cache do Java (Web Start / Deployment / aplicativos em cache).
      6. Reabre os processos Java que estavam rodando, com os mesmos argumentos.
    Não interrompe o script caso algo falhe — apenas registra.
.NOTES
    Execute como Administrador (o main.ps1 já eleva automaticamente).
#>

# ============================================================
# Descobre o usuário LOGADO no computador (não o que executa)
# ============================================================
function Get-PerfilUsuarioLogado {
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs.UserName) {
            $nomeUsuario = $cs.UserName.Split('\')[-1]
            $perfil = Join-Path "C:\Users" $nomeUsuario
            if (Test-Path $perfil) { return $perfil }
        }
    } catch { }

    try {
        $explorer = Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
                    Select-Object -First 1
        if ($explorer) {
            $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner
            if ($owner.User) {
                $perfil = Join-Path "C:\Users" $owner.User
                if (Test-Path $perfil) { return $perfil }
            }
        }
    } catch { }

    return $env:USERPROFILE
}

# ============================================================
# Detecta a versão do Java instalado
# ============================================================
function Get-VersaoJava {
    $versoes = @()

    # ---------- 1. Registro: JavaSoft (JRE e JDK) ----------
    $chaves = @(
        "HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment",
        "HKLM:\SOFTWARE\JavaSoft\Java Development Kit",
        "HKLM:\SOFTWARE\JavaSoft\JRE",
        "HKLM:\SOFTWARE\JavaSoft\JDK",
        "HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Runtime Environment",
        "HKLM:\SOFTWARE\WOW6432Node\JavaSoft\Java Development Kit",
        "HKLM:\SOFTWARE\WOW6432Node\JavaSoft\JRE",
        "HKLM:\SOFTWARE\WOW6432Node\JavaSoft\JDK"
    )

    foreach ($chave in $chaves) {
        if (-not (Test-Path $chave)) { continue }

        # Subchaves (cada versão instalada)
        Get-ChildItem -Path $chave -ErrorAction SilentlyContinue | ForEach-Object {
            $sub = $_.PSChildName
            try {
                $props = Get-ItemProperty -Path $_.PSPath -ErrorAction Stop
                $versoes += [PSCustomObject]@{
                    Fonte      = "Registro"
                    Tipo       = Split-Path $chave -Leaf
                    Versao     = $sub
                    Caminho    = $props.JavaHome
                    Arquitetura = if ($chave -match "WOW6432Node") { "32-bit" } else { "64-bit" }
                }
            } catch { }
        }
    }

    # ---------- 2. Pastas de instalação padrão ----------
    $pastasJava = @(
        "C:\Program Files\Java",
        "C:\Program Files (x86)\Java",
        "C:\Program Files\Eclipse Adoptium",
        "C:\Program Files\Microsoft\jdk*",
        "C:\Program Files\Amazon Corretto",
        "C:\Program Files\Zulu",
        "C:\Program Files\BellSoft"
    )

    foreach ($base in $pastasJava) {
        if (-not (Test-Path $base)) { continue }
        Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $exe = Join-Path $_.FullName "bin\java.exe"
            if (Test-Path $exe) {
                # Evita duplicar entradas já capturadas via registro
                $jaExiste = $versoes | Where-Object { $_.Caminho -ieq $_.FullName }
                if (-not $jaExiste) {
                    $versoes += [PSCustomObject]@{
                        Fonte       = "Pasta"
                        Tipo        = "JRE/JDK"
                        Versao      = $_.Name
                        Caminho     = $_.FullName
                        Arquitetura = if ($base -match "x86") { "32-bit" } else { "64-bit" }
                    }
                }
            }
        }
    }

    # ---------- 3. java.exe no PATH ----------
    $javaNoPath = Get-Command "java.exe" -ErrorAction SilentlyContinue
    if ($javaNoPath) {
        try {
            $saida = & $javaNoPath.Source -version 2>&1 | Out-String
            $match = [regex]::Match($saida, 'version\s+"([^"]+)"')
            if ($match.Success) {
                $versoes += [PSCustomObject]@{
                    Fonte       = "PATH"
                    Tipo        = "Java ativo"
                    Versao      = $match.Groups[1].Value
                    Caminho     = $javaNoPath.Source
                    Arquitetura = if ($saida -match "64-Bit") { "64-bit" } else { "32-bit" }
                }
            }
        } catch { }
    }

    # Remove duplicatas exatas
    $versoes = $versoes | Sort-Object Caminho -Unique

    return $versoes
}

# ============================================================
# Exibe a versão do Java de forma amigável
# ============================================================
function Show-VersaoJava {
    param([array]$Versoes)

    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host " Java instalado no sistema" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    if (-not $Versoes -or $Versoes.Count -eq 0) {
        Write-Host " Nenhuma instalacao de Java encontrada." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    $i = 1
    foreach ($v in $Versoes) {
        $corVersao = switch -Wildcard ($v.Versao) {
            "1.8*"  { "Yellow" }
            "11*"   { "Green"  }
            "17*"   { "Cyan"   }
            "21*"   { "Magenta"}
            default { "White"  }
        }

        Write-Host " [$i] $($v.Tipo) - versao $($v.Versao) [$($v.Arquitetura)]" -ForegroundColor $corVersao
        Write-Host "     Fonte:   $($v.Fonte)" -ForegroundColor DarkGray
        Write-Host "     Caminho: $($v.Caminho)" -ForegroundColor DarkGray
        Write-Host ""
        $i++
    }

    Write-Host " Total de instalacoes detectadas: $($Versoes.Count)" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================
# Verifica se um processo carregou a JVM (jvm.dll)
# ============================================================
function Test-ProcessoUsaJVM {
    param([System.Diagnostics.Process]$Processo)

    if ($Processo.ProcessName -match "powershell|pwsh|WindowsTerminal|conhost") {
        return $false
    }

    try {
        $modulos = $Processo.Modules
    } catch {
        return $false
    }

    foreach ($m in $modulos) {
        if ($m.ModuleName -ieq "jvm.dll") { return $true }
    }
    return $false
}

# ============================================================
# Captura info dos processos Java ANTES de matar
# ============================================================
function Get-InfoProcessosJava {
    $nomesJava = @(
        "java", "javaw", "javaws", "javac", "jp2launcher",
        "java-rmi", "jqs", "jucheck", "jusched"
    )

    $lista = @()

    foreach ($proc in Get-CimInstance Win32_Process -ErrorAction SilentlyContinue) {
        $nomeProc = $proc.Name -replace "\.exe$", ""

        $ehJava = $false
        foreach ($n in $nomesJava) {
            if ($nomeProc -ieq $n) { $ehJava = $true; break }
        }
        if (-not $ehJava) { continue }

        $lista += [PSCustomObject]@{
            Nome           = $nomeProc
            ExecutablePath = $proc.ExecutablePath
            CommandLine    = $proc.CommandLine
            ProcessId      = $proc.ProcessId
        }
    }

    return $lista
}

# ============================================================
# Finaliza processos Java (pelos nomes + por jvm.dll)
# ============================================================
function Stop-ProcessosJava {
    $nomesJava = @(
        "java", "javaw", "javaws", "javac", "jp2launcher",
        "java-rmi", "jqs", "jucheck", "jusched"
    )

    Write-Host "--> Encerrando processos Java em execucao..." -ForegroundColor Yellow

    $mortos = 0
    $falhas = 0

    foreach ($nome in $nomesJava) {
        $procs = Get-Process -Name $nome -ErrorAction SilentlyContinue
        if (-not $procs) { continue }

        foreach ($p in $procs) {
            try {
                Write-Host "   [KILL] $($p.ProcessName) (PID $($p.Id))" -ForegroundColor DarkYellow
                $p.CloseMainWindow() | Out-Null
                Start-Sleep -Milliseconds 200
                if (-not $p.HasExited) {
                    Stop-Process -Id $p.Id -Force -ErrorAction Stop
                }
                $mortos++
            } catch {
                Write-Host "   [ERRO] PID $($p.Id): $($_.Exception.Message)" -ForegroundColor DarkRed
                $falhas++
            }
        }
    }

    $todos = Get-Process -ErrorAction SilentlyContinue
    foreach ($p in $todos) {
        $jaTratado = $false
        foreach ($nome in $nomesJava) {
            if ($p.ProcessName -ieq $nome) { $jaTratado = $true; break }
        }
        if ($jaTratado) { continue }

        if (-not (Test-ProcessoUsaJVM -Processo $p)) { continue }

        try {
            Write-Host "   [KILL] $($p.ProcessName) (PID $($p.Id)) - usa JVM" -ForegroundColor DarkYellow
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            $mortos++
        } catch {
            Write-Host "   [ERRO] PID $($p.Id): $($_.Exception.Message)" -ForegroundColor DarkRed
            $falhas++
        }
    }

    Write-Host "   Processos encerrados: $mortos | Falhas: $falhas" -ForegroundColor Gray
    Write-Host ""

    return @{ Mortos = $mortos; Falhas = $falhas }
}

# ============================================================
# Reabre os processos Java que estavam em execução
# ============================================================
function Start-ProcessosJava {
    param([array]$ListaOriginal)

    if (-not $ListaOriginal -or $ListaOriginal.Count -eq 0) {
        Write-Host "--> Nenhum processo Java estava em execucao. Nada a reabrir." -ForegroundColor DarkGray
        Write-Host ""
        return @{ Iniciados = 0; Falhas = 0 }
    }

    Write-Host "--> Reabrindo $($ListaOriginal.Count) processo(s) Java..." -ForegroundColor Cyan

    $iniciados = 0
    $falhas    = 0

    foreach ($info in $ListaOriginal) {
        $exe = $info.ExecutablePath
        if ([string]::IsNullOrWhiteSpace($exe)) {
            $exe = (Get-Command "$($info.Nome).exe" -ErrorAction SilentlyContinue).Source
        }

        if ([string]::IsNullOrWhiteSpace($exe) -or -not (Test-Path $exe)) {
            Write-Host "   [SKIP] Executavel nao encontrado: $($info.Nome)" -ForegroundColor DarkYellow
            $falhas++
            continue
        }

        $argumentos = ""
        if ($info.CommandLine) {
            $argumentos = $info.CommandLine -replace '^"[^"]+"\s*', '' -replace '^\S+\s*', ''
        }

        try {
            Write-Host "   [START] $exe $argumentos" -ForegroundColor Green

            if ([string]::IsNullOrWhiteSpace($argumentos)) {
                Start-Process -FilePath $exe -ErrorAction Stop | Out-Null
            } else {
                Start-Process -FilePath $exe -ArgumentList $argumentos -ErrorAction Stop | Out-Null
            }
            $iniciados++
            Start-Sleep -Milliseconds 300
        } catch {
            Write-Host "   [ERRO] Falha ao reabrir $($info.Nome): $($_.Exception.Message)" -ForegroundColor DarkRed
            $falhas++
        }
    }

    Write-Host "   Reabertos: $iniciados | Falhas: $falhas" -ForegroundColor Gray
    Write-Host ""

    return @{ Iniciados = $iniciados; Falhas = $falhas }
}

# ============================================================
# Limpeza de uma pasta
# ============================================================
function Clear-Pasta {
    param([string]$Pasta)

    if (-not (Test-Path -Path $Pasta)) {
        Write-Host "[SKIP] Pasta nao existe: $Pasta" -ForegroundColor DarkGray
        return @{ Removidos = 0; Erros = 0 }
    }

    Write-Host "--> Limpando: $Pasta" -ForegroundColor Yellow

    $removidos = 0
    $erros     = 0

    Get-ChildItem -Path $Pasta -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
            $removidos++
        } catch {
            Write-Host "   [ERRO] $($_.Name): $($_.Exception.Message)" -ForegroundColor DarkRed
            $erros++
        }
    }

    Write-Host "   Removidos: $removidos | Falhas: $erros" -ForegroundColor Gray
    Write-Host ""

    return @{ Removidos = $removidos; Erros = $erros }
}

# ============================================================
# ============ EXECUCAO PRINCIPAL ============================
# ============================================================

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " Limpeza de Temp e Cache Java" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# ---- ETAPA 0: Detectar versões de Java instaladas --------------------------
$versoesJava = Get-VersaoJava
Show-VersaoJava -Versoes $versoesJava

# ---- ETAPA 1: Perfil do usuário logado ------------------------------------
$perfilUsuario = Get-PerfilUsuarioLogado
Write-Host "Usuario logado detectado: $perfilUsuario" -ForegroundColor Magenta
Write-Host ""

# ---- ETAPA 2: Registrar processos Java em execucao -------------------------
Write-Host "--> Registrando processos Java em execucao..." -ForegroundColor Cyan
$processosOriginais = Get-InfoProcessosJava

if ($processosOriginais.Count -gt 0) {
    foreach ($p in $processosOriginais) {
        Write-Host "   [REG] $($p.Nome) (PID $($p.ProcessId))" -ForegroundColor DarkGray
        if ($p.CommandLine) {
            Write-Host "         $($p.CommandLine)" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "   Nenhum processo Java em execucao." -ForegroundColor DarkGray
}
Write-Host ""

# ---- ETAPA 3: Encerrar Java -----------------------------------------------
$resKill = Stop-ProcessosJava
Start-Sleep -Seconds 2

# ---- ETAPA 4: Pastas a limpar ---------------------------------------------
$pastas = @(
    $env:TEMP,
    (Join-Path $perfilUsuario "AppData\Local\Temp"),

    # Cache Java Web Start / Deployment
    (Join-Path $perfilUsuario "AppData\LocalLow\Sun\Java\Deployment\cache"),
    (Join-Path $perfilUsuario "AppData\Local\Sun\Java\Deployment\cache"),
    (Join-Path $perfilUsuario "AppData\Local\Oracle\Java\Deployment\cache"),

    # Cache de aplicativos baixados
    (Join-Path $perfilUsuario "AppData\LocalLow\Sun\Java\Deployment"),
    (Join-Path $perfilUsuario "AppData\Local\Sun\Java\Deployment"),
    (Join-Path $perfilUsuario "AppData\Local\Oracle\Java\Deployment"),

    # Cache generico
    (Join-Path $perfilUsuario ".java\deployment\cache"),
    (Join-Path $perfilUsuario ".oracle_jre_usage")
) | Select-Object -Unique

# ---- ETAPA 5: Limpar -------------------------------------------------------
$totalRemovidos = 0
$totalErros     = 0

foreach ($pasta in $pastas) {
    $res = Clear-Pasta -Pasta $pasta
    $totalRemovidos += $res.Removidos
    $totalErros     += $res.Erros
}

# ---- ETAPA 6: Reabrir os Java que estavam rodando --------------------------
$resStart = Start-ProcessosJava -ListaOriginal $processosOriginais

# ---- ETAPA 7: Resumo -------------------------------------------------------
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " Resumo final" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

# Versões de Java
if ($versoesJava.Count -gt 0) {
    Write-Host " Java instalado:" -ForegroundColor Magenta
    foreach ($v in $versoesJava) {
        Write-Host "   - $($v.Versao) [$($v.Arquitetura)] ($($v.Tipo))" -ForegroundColor Gray
    }
} else {
    Write-Host " Java instalado: nenhuma instalacao detectada" -ForegroundColor Yellow
}
Write-Host ""

Write-Host " Java detectados no inicio:   $($processosOriginais.Count)" -ForegroundColor Gray
Write-Host " Processos Java encerrados:   $($resKill.Mortos)" -ForegroundColor Green
Write-Host " Processos Java reabertos:    $($resStart.Iniciados)" -ForegroundColor Green
Write-Host " Itens removidos:             $totalRemovidos" -ForegroundColor Green
Write-Host " Falhas de limpeza:           $totalErros" -ForegroundColor $(if ($totalErros -gt 0) { "Red" } else { "Green" })
Write-Host " Falhas de kill:              $($resKill.Falhas)" -ForegroundColor $(if ($resKill.Falhas -gt 0) { "Red" } else { "Green" })
Write-Host " Falhas de reabertura:        $($resStart.Falhas)" -ForegroundColor $(if ($resStart.Falhas -gt 0) { "Red" } else { "Green" })
Write-Host "=====================================" -ForegroundColor Cyan