
function Show-Menu {
    Clear-Host
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host "          MOJNTOOLS v1.0" -ForegroundColor Cyan
    Write-Host "   Windows Administration & Support" -ForegroundColor Gray
    Write-Host "====================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[1] Netvaerksvaerktoejer" -ForegroundColor Green
    Write-Host "[2] Windows reparation" -ForegroundColor Green
    Write-Host "[3] Printervaerktoejer" -ForegroundColor Green
    Write-Host "[4] Systeminformation" -ForegroundColor Green
    Write-Host "[5] Brugeradministration" -ForegroundColor Green
    Write-Host "[6] Windows opdateringer" -ForegroundColor Green
    Write-Host "[7] Oprydning" -ForegroundColor Green
    Write-Host "[8] Avancerede vaerktoejer" -ForegroundColor Green
    Write-Host ""
    Write-Host "[0] Afslut" -ForegroundColor Red
    Write-Host ""
}

function Pause-Menu {
    Read-Host "Tryk ENTER for at fortsaette"
}

function Show-NetworkMenu {
    do {
        Clear-Host
        Write-Host "=== NETVAERK ===" -ForegroundColor Cyan
        Write-Host "[1] IP-konfiguration"
        Write-Host "[2] Ping Google DNS"
        Write-Host "[3] DNS-opslag"
        Write-Host "[4] Test internetforbindelse"
        Write-Host "[0] Tilbage"

        $choice = Read-Host "Vaelg"

        switch ($choice) {
            "1" { ipconfig /all; Pause-Menu }
            "2" { ping 8.8.8.8; Pause-Menu }
            "3" {
                $domain = Read-Host "Indtast domaene"
                if ($domain) { nslookup $domain }
                Pause-Menu
            }
            "4" {
                Test-NetConnection 1.1.1.1 -Port 443
                Pause-Menu
            }
        }
    } until ($choice -eq "0")
}

do {
    Show-Menu
    $choice = Read-Host "Vaelg en funktion"

    switch ($choice) {
        "1" { Show-NetworkMenu }
        "2" {
            sfc /scannow
            Pause-Menu
        }
        "3" {
            Start-Process "control.exe" -ArgumentList "printers"
        }
        "4" {
            Get-ComputerInfo |
                Select-Object CsName, WindowsProductName, OsVersion
            Pause-Menu
        }
        "5" {
            Start-Process "lusrmgr.msc"
        }
        "6" {
            Start-Process "ms-settings:windowsupdate"
        }
        "7" {
            Start-Process "cleanmgr.exe"
        }
        "8" {
            Start-Process "eventvwr.msc"
        }
        "0" {
            Write-Host "Mojn og tak for denne gang!" -ForegroundColor Cyan
        }
        default {
            Write-Host "Ugyldigt valg!" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} until ($choice -eq "0")
