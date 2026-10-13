# MojnTools v1.5 - Windows PowerShell 5.1+
# Read-only password expiry checks for the current Windows user.

function Pause-Menu {
    Write-Host ''
    [void](Read-Host 'Tryk ENTER for at fortsaette')
}

function Show-Menu {
    Clear-Host
    Write-Host '====================================' -ForegroundColor Cyan
    Write-Host '          MOJNTOOLS v1.5' -ForegroundColor Cyan
    Write-Host '   Windows Administration & Support' -ForegroundColor Gray
    Write-Host '====================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '[1] Netvaerksvaerktoejer' -ForegroundColor Green
    Write-Host '[2] Windows reparation' -ForegroundColor Green
    Write-Host '[3] Printervaerktoejer' -ForegroundColor Green
    Write-Host '[4] Systeminformation' -ForegroundColor Green
    Write-Host '[5] Brugeradministration' -ForegroundColor Green
    Write-Host '[6] Windows opdateringer' -ForegroundColor Green
    Write-Host '[7] Oprydning' -ForegroundColor Green
    Write-Host '[8] Avancerede vaerktoejer' -ForegroundColor Green
    Write-Host '[9] Passwordstatus - aktuel bruger' -ForegroundColor Yellow
    Write-Host '[10] Windows Performance Score (WinSAT)' -ForegroundColor Yellow
    Write-Host '[11] PC Oppetid og genstartsstatus' -ForegroundColor Yellow
    Write-Host '[12] Fjern eller rediger et program' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '[0] Afslut' -ForegroundColor Red
    Write-Host ''
}

function Show-NetworkMenu {
    do {
        Clear-Host
        Write-Host '=== NETVAERK ===' -ForegroundColor Cyan
        Write-Host '[1] IP-konfiguration'
        Write-Host '[2] Ping Google DNS'
        Write-Host '[3] DNS-opslag'
        Write-Host '[4] Test internetforbindelse'
        Write-Host '[0] Tilbage'
        $choice = Read-Host 'Vaelg'
        switch ($choice) {
            '1' { ipconfig /all; Pause-Menu }
            '2' { ping 8.8.8.8; Pause-Menu }
            '3' {
                $domain = Read-Host 'Indtast domaene'
                if (-not [string]::IsNullOrWhiteSpace($domain)) { nslookup $domain }
                Pause-Menu
            }
            '4' { Test-NetConnection 1.1.1.1 -Port 443; Pause-Menu }
        }
    } until ($choice -eq '0')
}

function Get-CurrentPasswordInfo {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $account = $identity.Name
    $parts = $account -split '\\', 2
    $username = if ($parts.Count -eq 2) { $parts[1] } else { $env:USERNAME }
    $authority = if ($parts.Count -eq 2) { $parts[0] } else { $env:COMPUTERNAME }

    $result = [ordered]@{
        Account = $account
        Source = 'Ikke fundet'
        LastSet = $null
        Expires = $null
        Status = 'Udlobsdato kunne ikke bestemmes'
    }

    # Local SAM accounts: use built-in local account cmdlet when available.
    if ($authority -ieq $env:COMPUTERNAME) {
        try {
            $local = Get-LocalUser -Name $username -ErrorAction Stop
            $result.Source = 'Lokal Windows-konto'
            $result.LastSet = $local.PasswordLastSet
            $result.Expires = $local.PasswordExpires
            if ($local.PasswordRequired -eq $false) {
                $result.Status = 'Kontoen kraever ikke adgangskode'
            } elseif ($local.PasswordExpires -eq $null) {
                $result.Status = 'Ingen udlobsdato registreret (muligvis udlober aldrig)'
            } else {
                $result.Status = 'OK'
            }
        } catch {
            $result.Status = 'Lokale kontooplysninger er ikke tilgaengelige'
        }
        return [pscustomobject]$result
    }

    # Domain accounts: computed expiry accounts for domain password policy and FGPP.
    # Prefer the current user's SID over a username lookup to avoid name collisions.
    try {
        $sid = $identity.User.Value
        $searcher = New-Object System.DirectoryServices.DirectorySearcher
        $searcher.Filter = "(&(objectCategory=person)(objectClass=user)(objectSid=$sid))"
        [void]$searcher.PropertiesToLoad.Add('msDS-UserPasswordExpiryTimeComputed')
        [void]$searcher.PropertiesToLoad.Add('pwdLastSet')
        [void]$searcher.PropertiesToLoad.Add('userAccountControl')
        $entry = $searcher.FindOne()
        if ($null -eq $entry) { throw 'Brugeren blev ikke fundet i Active Directory.' }

        $result.Source = 'Active Directory (beregnet udloeb)'
        $p = $entry.Properties
        if ($p.Contains('pwdlastset') -and $p['pwdlastset'].Count -gt 0) {
            $rawLast = [long]$p['pwdlastset'][0]
            if ($rawLast -gt 0) { $result.LastSet = [datetime]::FromFileTime($rawLast) }
        }
        if ($p.Contains('useraccountcontrol') -and (([int]$p['useraccountcontrol'][0] -band 0x10000) -ne 0)) {
            $result.Status = 'Adgangskoden er sat til aldrig at udloebe'
            return [pscustomobject]$result
        }
        if ($p.Contains('msds-userpasswordexpirytimecomputed') -and $p['msds-userpasswordexpirytimecomputed'].Count -gt 0) {
            $rawExpiry = [long]$p['msds-userpasswordexpirytimecomputed'][0]
            if ($rawExpiry -eq [long]::MaxValue) {
                $result.Status = 'Adgangskoden udloeber ikke ifolge AD'
            } elseif ($rawExpiry -gt 0) {
                $result.Expires = [datetime]::FromFileTime($rawExpiry)
                $result.Status = 'OK'
            } else {
                $result.Status = 'AD returnerede ingen gyldig udlobsdato'
            }
        } else {
            $result.Status = 'AD returnerede ingen beregnet udlobsdato'
        }
    } catch {
        $result.Source = 'Active Directory ikke tilgaengeligt'
        $result.Status = 'Kunne ikke hente udloeb fra AD. Tjek VPN/domaeneforbindelse og AD-rettigheder.'
    }
    return [pscustomobject]$result
}

function Show-PasswordStatus {
    Clear-Host
    Write-Host '====================================' -ForegroundColor Cyan
    Write-Host '        PASSWORDSTATUS' -ForegroundColor Cyan
    Write-Host '====================================' -ForegroundColor Cyan
    Write-Host 'Henter oplysninger...' -ForegroundColor Gray

    $info = Get-CurrentPasswordInfo
    Write-Host ''
    Write-Host ('Computer:        {0}' -f $env:COMPUTERNAME)
    Write-Host ('Windows-bruger:  {0}' -f $info.Account)
    Write-Host ('Datakilde:       {0}' -f $info.Source)
    if ($null -ne $info.LastSet) {
        Write-Host ('Sidst aendret:   {0:dd-MM-yyyy HH:mm}' -f $info.LastSet)
    } else {
        Write-Host 'Sidst aendret:   Ukendt' -ForegroundColor Yellow
    }

    if ($null -ne $info.Expires) {
        Write-Host ('Udlober:         {0:dd-MM-yyyy HH:mm}' -f $info.Expires)
        $remaining = $info.Expires - (Get-Date)
        if ($remaining.TotalSeconds -le 0) {
            Write-Host 'STATUS: ADGANGSKODEN ER UDLOEBET!' -ForegroundColor Red
        } elseif ($remaining.TotalDays -lt 1) {
            Write-Host ('STATUS: Udlober om {0} timer!' -f [math]::Ceiling($remaining.TotalHours)) -ForegroundColor Red
        } else {
            $days = [math]::Floor($remaining.TotalDays)
            $color = if ($days -le 7) { 'Red' } elseif ($days -le 14) { 'Yellow' } else { 'Green' }
            Write-Host ('Dage tilbage:   {0} hele dage' -f $days) -ForegroundColor $color
        }
    } else {
        Write-Host ('Status:          {0}' -f $info.Status) -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host 'Bemaerk: Entra ID/cloud-only-konti kan ikke altid aflases via lokal AD.' -ForegroundColor Gray
    Pause-Menu
}

function Show-WinSATScore {
    Clear-Host
    Write-Host '====================================' -ForegroundColor Cyan
    Write-Host '     WINDOWS PERFORMANCE SCORE' -ForegroundColor Cyan
    Write-Host '====================================' -ForegroundColor Cyan
    Write-Host 'Henter senest registrerede WinSAT-resultat...' -ForegroundColor Gray
    Write-Host ''
    try {
        $score = Get-CimInstance -ClassName Win32_WinSAT -ErrorAction Stop
        if ($null -eq $score -or $score.WinSATAssessmentState -ne 1) {
            Write-Host 'Ingen gyldig, gennemfoert WinSAT-vurdering blev fundet.' -ForegroundColor Yellow
            Write-Host 'En ny vurdering kan koeres med winsat formal fra en administratorterminal.' -ForegroundColor Gray
            return
        }
        $items = @(
            @{ Label = 'Processor (CPU)'; Value = $score.CPUScore },
            @{ Label = 'Hukommelse (RAM)'; Value = $score.MemoryScore },
            @{ Label = 'Grafik'; Value = $score.GraphicsScore },
            @{ Label = 'Gaming-grafik'; Value = $score.D3DScore },
            @{ Label = 'Disk (SSD/HDD)'; Value = $score.DiskScore }
        )
        foreach ($item in $items) {
            $value = [double]$item.Value
            $color = if ($value -ge 8) { 'Green' } elseif ($value -ge 6) { 'Yellow' } else { 'Red' }
            Write-Host ('{0,-20}: ' -f $item.Label) -NoNewline
            Write-Host ('{0:N1} / 9,9' -f $value) -ForegroundColor $color
        }
        Write-Host '------------------------------------' -ForegroundColor DarkGray
        $base = [double]$score.WinSPRLevel
        $baseColor = if ($base -ge 8) { 'Green' } elseif ($base -ge 6) { 'Yellow' } else { 'Red' }
        Write-Host 'Samlet Windows-score: ' -NoNewline
        Write-Host ('{0:N1} / 9,9' -f $base) -ForegroundColor $baseColor
        Write-Host ''
        Write-Host 'Samlet score er normalt den laveste delscore, ikke et gennemsnit.' -ForegroundColor Gray
        Write-Host 'WinSAT er en tidligere maaling, ikke live overvagning af hardware.' -ForegroundColor Gray
    } catch {
        Write-Host ('Kunne ikke hente WinSAT-data: {0}' -f $_.Exception.Message) -ForegroundColor Red
    } finally {
        Pause-Menu
    }
}

function Show-UptimeStatus {
    Clear-Host
    Write-Host '=== MOJNTOOLS - PC OPPETID ===' -ForegroundColor Cyan
    Write-Host ''
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $boot = $os.LastBootUpTime
        if ($boot -is [string]) {
            $boot = [System.Management.ManagementDateTimeConverter]::ToDateTime($boot)
        }
        if (-not $boot) { throw 'Windows returnerede ingen opstartstid.' }
        $now = Get-Date
        $uptime = $now - $boot
        if ($uptime.TotalSeconds -lt 0) { throw 'Opstartstiden ligger i fremtiden. Kontroller systemuret.' }
        $hours = [math]::Floor($uptime.TotalHours)

        if ($hours -ge 2000) {
            $status = 'EKSTREM OPPETID'; $score = 0; $color = 'Red'
            $advice = 'Genstart snarest, naar arbejdet er gemt.'
        } elseif ($hours -ge 1500) {
            $status = 'ALT FOR MEGET'; $score = 10; $color = 'Red'
            $advice = 'Genstart snarest, naar arbejdet er gemt.'
        } elseif ($hours -ge 1000) {
            $status = 'KRITISK'; $score = 25; $color = 'Red'
            $advice = 'Genstart snarest, naar arbejdet er gemt.'
        } elseif ($hours -ge 500) {
            $status = 'PAA TIDE AT GENSTARTE'; $score = 50; $color = 'Yellow'
            $advice = 'Planlaeg en genstart.'
        } elseif ($hours -ge 200) {
            $status = 'GENSTART ANBEFALES'; $score = 75; $color = 'Yellow'
            $advice = 'Overvej en genstart ved lejlighed.'
        } else {
            $status = 'OK'; $score = 100; $color = 'Green'
            $advice = 'Ingen genstart anbefalet ud fra oppetid alene.'
        }

        Write-Host ('Computer:       {0}' -f $env:COMPUTERNAME)
        Write-Host ('Sidste opstart: {0}' -f $boot.ToString('dd-MM-yyyy HH:mm:ss'))
        Write-Host ('Oppetid:        {0} dage, {1} timer, {2} minutter' -f [math]::Floor($uptime.TotalDays), $uptime.Hours, $uptime.Minutes)
        Write-Host ('Samlet:         {0} hele timer' -f $hours)
        Write-Host ''
        Write-Host ('STATUS: {0}' -f $status) -ForegroundColor $color
        Write-Host ('Genstartsscore: {0}/100' -f $score) -ForegroundColor $color
        Write-Host ('Anbefaling: {0}' -f $advice) -ForegroundColor $color
        Write-Host ''
        Write-Host 'Skala: <200=100, 200-499=75, 500-999=50, 1000-1499=25, 1500-1999=10, 2000+=0' -ForegroundColor Gray
        Write-Host 'Scoren er en brugerdefineret genstartsindikator, ikke en Windows-sundhedsmaaling.' -ForegroundColor Gray
        Write-Host 'Windows Hurtig start kan paavirke opstartstiden efter Luk computeren.' -ForegroundColor Gray
        Write-Host 'En almindelig Genstart nulstiller normalt oppetiden.' -ForegroundColor Gray
    } catch {
        Write-Host ('Kunne ikke hente oppetid: {0}' -f $_.Exception.Message) -ForegroundColor Red
    } finally {
        Pause-Menu
    }
}

do {
    Show-Menu
    $choice = Read-Host 'Vaelg en funktion'
    switch ($choice) {
        '1' { Show-NetworkMenu }
        '2' { sfc /scannow; Pause-Menu }
        '3' {
            $wizard = Join-Path $env:WINDIR 'System32\DevicePairingWizard.exe'
            if (Test-Path $wizard) {
                Start-Process -FilePath $wizard
            } else {
                Write-Host 'Enhedsguiden blev ikke fundet paa denne Windows-version.' -ForegroundColor Yellow
                Pause-Menu
            }
        }
        '4' { Get-ComputerInfo | Select-Object CsName, WindowsProductName, OsVersion; Pause-Menu }
        '5' { Start-Process 'lusrmgr.msc' }
        '6' { Start-Process 'ms-settings:windowsupdate' }
        '7' { Start-Process 'cleanmgr.exe' }
        '8' { Start-Process 'eventvwr.msc' }
        '9' { Show-PasswordStatus }
        '10' { Show-WinSATScore }
        '11' { Show-UptimeStatus }
        '12' {
            try {
                Start-Process -FilePath 'control.exe' -ArgumentList 'appwiz.cpl' -ErrorAction Stop
            } catch {
                Write-Host ('Kunne ikke aabne Programmer og funktioner: {0}' -f $_.Exception.Message) -ForegroundColor Red
                Pause-Menu
            }
        }
        '0' { Write-Host 'Mojn og tak for denne gang!' -ForegroundColor Cyan }
        default { Write-Host 'Ugyldigt valg!' -ForegroundColor Red; Start-Sleep -Seconds 1 }
    }
} until ($choice -eq '0')
