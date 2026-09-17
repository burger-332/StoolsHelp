```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Windows PowerShell 5.1 peut utiliser TLS 1.0 par défaut, ce que le CDN refuse
# (connexion interrompue pendant l'envoi). Force TLS moderne afin que
# HttpWebRequest puisse négocier correctement avec le serveur.
try {
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol `
        -bor [System.Net.SecurityProtocolType]::Tls12 `
        -bor [System.Net.SecurityProtocolType]::Tls13
} catch {
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol `
        -bor [System.Net.SecurityProtocolType]::Tls12
}

function Show-SpinnerAndResult {
    param (
        [string]$SpinnerText,
        [ScriptBlock]$Action,
        [string]$ExtraInfo = $null,
        [string]$Tip = $null
    )
    $spinnerPos = [Console]::CursorTop
    $spinner = @('|', '/', '-', '\')
    Write-Host $spinner[0] -NoNewline -ForegroundColor White
    Write-Host " $SpinnerText" -ForegroundColor White
    if ($Tip) {
        $tipPos = [Console]::CursorTop
        Write-Host "  $([char]0x2514)$([char]0x2500) $Tip" -ForegroundColor Yellow
    }
    $done = $false
    $i = 0
    $result = $null
    $job = Start-Job -ScriptBlock $Action

    while (-not $done) {
        Start-Sleep -Milliseconds 100
        $char = $spinner[$i % $spinner.Count]
        [Console]::SetCursorPosition(0, $spinnerPos)
        Write-Host $char -NoNewline -ForegroundColor White
        Write-Host " $SpinnerText" -NoNewline -ForegroundColor White
        $i++
        if ($job.State -eq 'Completed' -or $job.State -eq 'Failed' -or $job.State -eq 'Stopped') {
            $done = $true
        }
    }
    $result = Receive-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job | Out-Null

    [Console]::SetCursorPosition(0, $spinnerPos)
    [Console]::Write((' ' * ([Console]::WindowWidth-1)))
    if ($Tip) {
        [Console]::SetCursorPosition(0, $tipPos)
        [Console]::Write((' ' * ([Console]::WindowWidth-1)))
    }
    [Console]::SetCursorPosition(0, $spinnerPos)
    if ($result -and $result.Success) {
        Write-Host ([char]0x2713) -NoNewline -ForegroundColor Green
        Write-Host " $SpinnerText" -NoNewline -ForegroundColor Green
        [Console]::WriteLine('')
        if ($ExtraInfo) {
            Write-Host "Emplacement : $($result.Path)" -ForegroundColor White
        }
    } else {
        Write-Host 'X' -NoNewline -ForegroundColor Red
        Write-Host " $SpinnerText" -NoNewline -ForegroundColor Red
        [Console]::WriteLine('')
        if ($result -and $result.Extra) {
            Write-Host "$($result.Extra)" -ForegroundColor Red
        }
        Write-Host ''
        Write-Host 'Appuyez sur une touche pour quitter...' -ForegroundColor White
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        exit
    }
    return $result.Path
}

Clear-Host
Write-Host ''
Write-Host 'Ce script a été refait par https://stools-help.vercel.app/?v=999' -BackgroundColor Magenta
Write-Host ''

# Étape 0 : Rechercher l'installation de Steam
$steamPath = Show-SpinnerAndResult `
    -SpinnerText 'Recherche de linstallation de Steam' `
    -Action {
        $registryPaths = @(
            'HKCU:\Software\Valve\Steam',
            'HKLM:\Software\Valve\Steam',
            'HKLM:\Software\WOW6432Node\Valve\Steam'
        )

        foreach ($regPath in $registryPaths) {
            if (Test-Path $regPath) {
                $installPath = (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue).InstallPath
                if ($installPath -and (Test-Path $installPath)) {
                    return @{ Success = $true; Path = $installPath }
                }
            }
        }

        return @{ Success = $false; Extra = 'Installation de Steam introuvable. Essayez de réinstaller Steam.' }
    }

# Étape 1 : Fermer les processus Steam
$null = Show-SpinnerAndResult `
    -SpinnerText 'Fermeture de tous les processus Steam' `
    -Action {
        $steamProcesses = Get-Process | Where-Object { $_.Name -match 'steam' }

        if ($steamProcesses) {
            try {
                $steamProcesses | Stop-Process -Force -ErrorAction Stop
                Start-Sleep -Seconds 2
                return @{ Success = $true; Path = '' }
            } catch {
                return @{ Success = $false; Extra = "Impossible de fermer les processus Steam. Lancez PowerShell en tant qu'administrateur et réessayez." }
            }
        } else {
            return @{ Success = $true; Path = '' }
        }
    }

# Étape 2 : Supprimer xinput1_4.dll et dwmapi.dll existants
$null = Show-SpinnerAndResult `
    -SpinnerText 'Suppression des anciens fichiers' `
    -Action {
        $dll1 = Join-Path $using:steamPath 'xinput1_4.dll'
        $dll2 = Join-Path $using:steamPath 'dwmapi.dll'

        try {
            if (Test-Path $dll1) { Remove-Item $dll1 -Force -ErrorAction Stop }
            if (Test-Path $dll2) { Remove-Item $dll2 -Force -ErrorAction Stop }
            return @{ Success = $true; Path = '' }
        } catch {
            return @{ Success = $false; Extra = "Impossible de supprimer les fichiers : $($_.Exception.Message)" }
        }
    }

# Étape 3 : Supprimer le correctif de manifeste SteamProof
$null = Show-SpinnerAndResult `
    -SpinnerText 'Suppression de lancien correctif SteamProof' `
    -Action {
        $sp = $using:steamPath
        $targets = @(
            (Join-Path $sp 'wtsapi32.dll'),
            (Join-Path $sp 'version.dll'),
            (Join-Path $sp 'config\manifests.dll'),
            (Join-Path $sp 'config\.mfx_init'),
            (Join-Path $sp 'config\.stfix_init')
        )

        try {
            $removed = 0
            foreach ($t in $targets) {
                if (Test-Path $t) {
                    Remove-Item $t -Force -ErrorAction Stop
                    $removed++
                }
            }
            return @{ Success = $true; Path = "$removed fichier(s) supprimé(s)" }
        } catch {
            return @{ Success = $false; Extra = "Impossible de supprimer le correctif de manifeste SteamProof : $($_.Exception.Message)" }
        }
    }

function Update-DownloadDisplay {
    param($Display)

    $elapsed = $Display.Clock.ElapsedMilliseconds
    if (($elapsed - $Display.LastFrameMs) -lt 100) { return }
    $Display.LastFrameMs = $elapsed
    $Display.Frame++

    $char = $Display.Spinner[$Display.Frame % $Display.Spinner.Count]
    [Console]::SetCursorPosition(0, $Display.TitlePos)
    [Console]::Write("$char Téléchargement des fichiers mis à jour")

    if ($Display.TotalReady -and $Display.TotalBytes -gt 0) {
        $progress = [math]::Min(1.0, ($Display.DownloadedBytes / $Display.TotalBytes))
        $pct = [math]::Floor($progress * 100)
        $filled = [math]::Floor($progress * $Display.BarLength)
        $empty = $Display.BarLength - $filled
        $bar = "$([char]0x2588)" * $filled + "$([char]0x2591)" * $empty
        $sizeMB = '{0:N1}' -f ($Display.DownloadedBytes / 1MB)
        $totalMB = '{0:N1}' -f ($Display.TotalBytes / 1MB)
        $barText = "  $bar $pct% ($sizeMB / $totalMB Mo)  "
        [Console]::SetCursorPosition(0, $Display.BarPos)
        [Console]::Write($barText)
    }

    [Console]::SetCursorPosition(0, $Display.TitlePos)
}

function Wait-DownloadOperation {
    param(
        [IAsyncResult]$Operation,
        $Display,
        [System.Net.HttpWebRequest]$Request,
        [int]$TimeoutMs
    )

    $wait = [Diagnostics.Stopwatch]::StartNew()
    while (-not $Operation.AsyncWaitHandle.WaitOne(100)) {
        Update-DownloadDisplay $Display
        if ($wait.ElapsedMilliseconds -ge $TimeoutMs) {
            $Request.Abort()
            throw 'La requête de téléchargement a dépassé le délai imparti.'
        }
    }
    Update-DownloadDisplay $Display
}

# Étape 4 : Télécharger les fichiers mis à jour
$dllDownloadSuccess = $false
$dllSpinner = @('|', '/', '-', '\')
$dllNames = @(
    'dwmapi.dll',
    'dwmapi.exp',
    'dwmapi.lib',
    'lua_static.lib',
    'OpenSteamTool.dll',
    'xinput1_4.dll',
    'xinput1_4.exp',
    'xinput1_4.lib'
)
$dllFiles = $dllNames | ForEach-Object { @{ Name = $_; Url = "https://cdn.openlua.cloud/ost/$_" } }
$dllTitlePos = [Console]::CursorTop
Write-Host "$($dllSpinner[0]) Téléchargement des fichiers mis à jour" -ForegroundColor White
$dllBarPos = [Console]::CursorTop
Write-Host ''
$dllDisplay = @{
    TitlePos = $dllTitlePos
    BarPos = $dllBarPos
    BarLength = 30
    Spinner = $dllSpinner
    Frame = 0
    LastFrameMs = -100
    DownloadedBytes = 0L
    TotalBytes = 0L
    TotalReady = $false
    Clock = [Diagnostics.Stopwatch]::StartNew()
}

try {
    foreach ($dll in $dllFiles) {
        $req = [System.Net.HttpWebRequest]::Create($dll.Url)
        $req.Method = 'HEAD'
        $headResult = $req.BeginGetResponse($null, $null)
        Wait-DownloadOperation $headResult $dllDisplay $req $req.Timeout
        $resp = $req.EndGetResponse($headResult)
        if ($resp.ContentLength -gt 0) {
            $dllDisplay.TotalBytes += $resp.ContentLength
        }
        $resp.Close()
        $resp = $null
    }
    $dllDisplay.TotalReady = $true

    foreach ($dll in $dllFiles) {
        $outPath = Join-Path $steamPath $dll.Name
        $req = [System.Net.HttpWebRequest]::Create($dll.Url)
        $responseResult = $req.BeginGetResponse($null, $null)
        Wait-DownloadOperation $responseResult $dllDisplay $req $req.Timeout
        $response = $req.EndGetResponse($responseResult)
        $stream = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($outPath)
        $buffer = New-Object byte[] 8192

        while ($true) {
            $readResult = $stream.BeginRead($buffer, 0, $buffer.Length, $null, $null)
            Wait-DownloadOperation $readResult $dllDisplay $req $req.ReadWriteTimeout
            $bytesRead = $stream.EndRead($readResult)
            if ($bytesRead -eq 0) { break }

            $fileStream.Write($buffer, 0, $bytesRead)
            $dllDisplay.DownloadedBytes += $bytesRead
            Update-DownloadDisplay $dllDisplay
        }

        $fileStream.Close()
        $fileStream = $null
        $stream.Close()
        $stream = $null
        $response.Close()
        $response = $null
    }
    $dllDownloadSuccess = $true
} catch {
    $dllError = $_
    $failedFile = if ($dll) { $dll.Name } else { 'inconnu' }
    if ($resp) { $resp.Close() }
    if ($fileStream) { $fileStream.Close() }
    if ($stream) { $stream.Close() }
    if ($response) { $response.Close() }
}

[Console]::SetCursorPosition(0, $dllTitlePos)
[Console]::Write((' ' * ([Console]::WindowWidth - 1)))
[Console]::SetCursorPosition(0, $dllBarPos)
[Console]::Write((' ' * ([Console]::WindowWidth - 1)))
[Console]::SetCursorPosition(0, $dllTitlePos)
if ($dllDownloadSuccess) {
    Write-Host ([char]0x2713) -NoNewline -ForegroundColor Green
    Write-Host ' Téléchargement des fichiers mis à jour' -ForegroundColor Green
} else {
    Write-Host 'X' -NoNewline -ForegroundColor Red
    Write-Host ' Téléchargement des fichiers mis à jour' -ForegroundColor Red
    $errMsg = "Échec du téléchargement de $failedFile"
    if ($dllError.Exception -is [System.Net.WebException] -and $dllError.Exception.Response) {
        $statusCode = [int]$dllError.Exception.Response.StatusCode
        $statusDesc = $dllError.Exception.Response.StatusDescription
        $errMsg += " (HTTP $statusCode $statusDesc)"
    } elseif ($dllError.Exception) {
        $errMsg += " : $($dllError.Exception.Message)"
    }
    Write-Host $errMsg -ForegroundColor Red
    Write-Host ''
    Write-Host 'Appuyez sur une touche pour quitter...' -ForegroundColor White
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit
}

# Étape 5 : Configurer la source GMRC
$null = Show-SpinnerAndResult `
    -SpinnerText 'Configuration de la source GMRC' `
    -Action {
        $configPath = Join-Path $using:steamPath 'opensteamtool.toml'

        try {
            $source = 'steamrun'
            if (Test-Path -LiteralPath $configPath) {
                $inManifest = $false
                foreach ($line in [System.IO.File]::ReadAllLines($configPath)) {
                    if ($line -match '^\s*\[([^\]]+)\]\s*(?:#.*)?$') {
                        $inManifest = $Matches[1] -eq 'manifest'
                        continue
                    }
                    if ($inManifest -and $line -match '^\s*url\s*=\s*"(steamrun|wudrm)"\s*(?:#.*)?$') {
                        if ($Matches[1] -eq 'steamrun') { $source = 'wudrm' }
                        break
                    }
                }
            }

            [System.IO.File]::WriteAllText(
                $configPath,
                "[manifest]`r`nurl = `"$source`"`r`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            return @{ Success = $true; Path = $configPath }
        } catch {
            return @{ Success = $false; Extra = "Impossible de configurer la source GMRC : $($_.Exception.Message)" }
        }
    }

# Étape 6 : Déplacer les fichiers Lua vers config\lua
$null = Show-SpinnerAndResult `
    -SpinnerText 'Déplacement des fichiers Lua' `
    -Action {
        $sp = $using:steamPath
        $srcDir = Join-Path $sp "config\stplug-in"
        $dstDir = Join-Path $sp "config\lua"

        try {
            if (-not (Test-Path $dstDir)) { $null = New-Item -Path $dstDir -ItemType Directory -Force -ErrorAction Stop }
            if (-not (Test-Path $srcDir)) { return @{ Success = $true; Path = '0 fichier(s) déplacé(s)' } }

            $luaFiles = Get-ChildItem -Path $srcDir -Filter "*.lua" -ErrorAction SilentlyContinue
            $moved = 0
            foreach ($f in $luaFiles) {
                Move-Item -Path $f.FullName -Destination (Join-Path $dstDir $f.Name) -Force -ErrorAction Stop
                $moved++
            }
            return @{ Success = $true; Path = "$moved fichier(s) déplacé(s)" }
        } catch {
            return @{ Success = $false; Extra = "Impossible de déplacer les fichiers Lua : $($_.Exception.Message)" }
        }
    }

# Étape 7 : Supprimer les anciennes lignes SteamProof des fichiers Lua
$null = Show-SpinnerAndResult `
    -SpinnerText 'Nettoyage des fichiers Lua' `
    -Action {
        $sp = $using:steamPath
        $pDir = Join-Path $sp "config\lua"
        if (-not (Test-Path $pDir)) { return @{ Success = $true; Path = '' } }

        $luaFiles = Get-ChildItem -Path $pDir -Filter "*.lua" -ErrorAction SilentlyContinue
        $cleaned = 0

        foreach ($f in $luaFiles) {
            $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match "SteamProof") {
                $lines = Get-Content $f.FullName
                $filtered = $lines | Where-Object { $_ -notmatch "^-- SteamProof" -and $_ -notmatch "^setManifestid" }
                while ($filtered.Count -gt 0 -and $filtered[-1].Trim() -eq "") {
                    $filtered = $filtered[0..($filtered.Count - 2)]
                }
                $filtered | Set-Content $f.FullName -Encoding UTF8
                $cleaned++
            }
        }

        return @{ Success = $true; Path = "$cleaned fichier(s) nettoyé(s)" }
    }

# Étape 8 : Supprimer le BOM UTF-8 des fichiers Lua
$null = Show-SpinnerAndResult `
    -SpinnerText 'Correction des fichiers Lua' `
    -Action {
        $sp = $using:steamPath
        $pDir = Join-Path $sp "config\lua"
        if (-not (Test-Path $pDir)) { return @{ Success = $true; Path = '' } }
        $luaFiles = Get-ChildItem -Path $pDir -Filter "*.lua" -EA SilentlyContinue
        $fixed = 0
        $bom = [byte[]]@(0xEF, 0xBB, 0xBF)
        foreach ($f in $luaFiles) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            if ($bytes.Length -ge 3 -and $bytes[0] -eq $bom[0] -and $bytes[1] -eq $bom[1] -and $bytes[2] -eq $bom[2]) {
                [System.IO.File]::WriteAllBytes($f.FullName, $bytes[3..($bytes.Length - 1)])
                $fixed++
            }
        }
        return @{ Success = $true; Path = "$fixed fichier(s) corrigé(s)" }
    }

Write-Host ''
Write-Host ([char]0x2713) 'Processus terminé' -BackgroundColor Green -ForegroundColor Black
Write-Host ''
Write-Host 'Pour ajouter des jeux ou des applications :' -ForegroundColor Yellow
Write-Host 'Déplacez chaque fichier .lua téléchargé dans ce dossier :' -ForegroundColor White
Write-Host "  $(Join-Path $steamPath 'config\lua')" -ForegroundColor White
Write-Host 'Le glisser-déposer sur licône Steam flottante ne fonctionne plus.' -ForegroundColor White
Write-Host 'Steam détecte immédiatement les fichiers présents dans ce dossier. Aucun redémarrage nest nécessaire.' -ForegroundColor White
Write-Host ''
Write-Host 'Ouvrez Steam normalement et réessayez le téléchargement ou la mise à jour.' -ForegroundColor Yellow
Write-Host 'Si Steam affiche « PAS DE CONNEXION INTERNET » ou « ERREUR INCONNUE » :' -ForegroundColor Yellow
Write-Host '  1. Faites un clic droit sur licône Steam dans la barre système et choisissez « Quitter Steam ».' -ForegroundColor White
Write-Host '     Ouvrez ensuite Steam normalement et réessayez.' -ForegroundColor White
Write-Host '  2. Si cela ne fonctionne toujours pas, relancez ce script.' -ForegroundColor White
Write-Host '     Ouvrez ensuite Steam normalement et réessayez.' -ForegroundColor White
Write-Host '  3. Si cela ne fonctionne toujours pas, quittez Steam depuis la barre système et ouvrez-le normalement.' -ForegroundColor White
Write-Host '     Réessayez le téléchargement ou la mise à jour.' -ForegroundColor White
Write-Host ''
Write-Host 'Appuyez sur une touche pour quitter...' -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
exit
```
