#region Configuration
$script:CacheFilePath = "$env:LOCALAPPDATA\PlatformProcess\Cache\data_1"
$script:UrlChars = '[A-Za-z0-9._~\-/?&=%+]'
$script:UrlRegexPattern = "https://[A-Za-z0-9.\-]+\.gryphline\.com/$script:UrlChars*?token=$script:UrlChars*?server=$script:UrlChars+"
#endregion

#region Functions
function Copy-CacheToTemp {
    <#
        .SYNOPSIS
        Copies the locked cache file to a temp location so it can be read.
    #>
    if (-not (Test-Path $script:CacheFilePath)) {
        Write-Error "Khong tim thay file cache: $script:CacheFilePath"
        return $null
    }

    $tempFile = Join-Path $env:TEMP "tracker_cache_$([Guid]::NewGuid().ToString('N')).tmp"

    try {
        $sourceStream = [System.IO.File]::Open($script:CacheFilePath, 'Open', 'Read', 'ReadWrite,Delete')
        $destStream = [System.IO.File]::Create($tempFile)
        $sourceStream.CopyTo($destStream)
        $sourceStream.Close()
        $destStream.Close()
        return $tempFile
    }
    catch [System.IO.IOException] {
        # Sharing violation: 0x80070020 (-2147024864). Game thuong giu lock doc quyen → copy fail.
        # User co the Ctrl+C/V trong Explorer (dung Volume Shadow Copy) ma code lai khong → bao
        # user tat game thay vi cai dat shadow-copy library.
        $hresult = $_.Exception.HResult
        if ($hresult -eq -2147024864) {
            Write-Host ""
            Write-Host "LOI: File cache dang bi game khoa." -ForegroundColor Red
            Write-Host "Vui long TAT GAME hoan toan, sau do chay lai script." -ForegroundColor Yellow
            Write-Host "(Chi tiet: $($_.Exception.Message))" -ForegroundColor DarkGray
        }
        else {
            Write-Error "Khong the copy file cache: $_"
        }
        return $null
    }
    catch {
        Write-Error "Khong the copy file cache: $_"
        return $null
    }
}

function Find-UrlInCacheFile {
    <#
        .SYNOPSIS
        Extracts the last matching URL from the cache file.

        .PARAMETER FilePath
        The path to the (temp) cache file.
    #>
    param(
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        return $null
    }

    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    # Latin1 giu nguyen byte 1:1 (binary byte >= 128 thanh ky tu ngoai ASCII, khong bi thay bang '?')
    $content = [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetString($bytes)

    $urlMatches = [regex]::Matches($content, $script:UrlRegexPattern)

    if ($urlMatches.Count -eq 0) {
        return $null
    }

    return $urlMatches[$urlMatches.Count - 1].Value
}

function Remove-TempFile {
    param([string]$Path)

    if ($Path -and (Test-Path $Path)) {
        Remove-Item $Path -Force -ErrorAction SilentlyContinue
    }
}

function Write-SuccessMessage {
    <#
        .SYNOPSIS
        Displays success message with the URL.

        .PARAMETER Url
        The URL to display.
    #>
    param(
        [string]$Url
    )

    Write-Host "Thanh cong! URL da duoc sao chep vao clipboard:" -ForegroundColor Green
    Write-Host $Url
}

function Wait-ForUserExit {
    # Khi user chay bang double-click .ps1, exit ngay se dong cua so → khong kip doc message.
    # Dung Read-Host de cho Enter, va guard try/catch cho moi truong khong co host (vd. piped exec).
    try {
        Read-Host "`nNhan Enter de thoat" | Out-Null
    }
    catch {
        # Non-interactive host (vd. iwr | iex tu remote) → bo qua.
    }
}
#endregion

#region Main Execution
function Main {
    Write-Host "Dang doc file cache..." -ForegroundColor Yellow

    $tempFile = $null
    try {
        $tempFile = Copy-CacheToTemp
        if (-not $tempFile) {
            return
        }

        $foundUrl = Find-UrlInCacheFile -FilePath $tempFile

        if (-not $foundUrl) {
            Write-Host "" -NoNewline
            Write-Host "Khong tim thay URL phu hop trong file cache." -ForegroundColor Red
            Write-Host "Vui long dam bao ban da mo game va truy cap trang Ho So Chieu Mo." -ForegroundColor Yellow
            return
        }

        Set-Clipboard -Value $foundUrl
        Write-SuccessMessage -Url $foundUrl
    }
    finally {
        Remove-TempFile -Path $tempFile
    }
}

# Bao Main trong try/catch ngoai cung — bat ki loi nao khong duoc handle ben trong cung khong dong PS host.
try {
    Main
}
catch {
    Write-Host ""
    Write-Host "Loi khong xac dinh:" -ForegroundColor Red
    Write-Host $_ -ForegroundColor DarkGray
}
finally {
    Wait-ForUserExit
}
#endregion
