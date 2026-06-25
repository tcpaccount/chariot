<#
.SYNOPSIS
    Collects baseline information from a Windows endpoint for DFIR asset enumeration.
    Designed for hosts where Velociraptor agents could not be deployed.
.DESCRIPTION
    Collects: installed software, running services, scheduled tasks, local accounts,
    network connections, autoruns. Outputs results to a structured text report and CSV files.
.PARAMETER OutputDir
    Directory to save output files. Defaults to C:\Windows\Temp\baseline-<hostname>.
.EXAMPLE
    .\baseline-endpoints.ps1
.EXAMPLE
    .\baseline-endpoints.ps1 -OutputDir "D:\IR\baseline"
#>

param(
    [string]$OutputDir
)

$Hostname = $env:COMPUTERNAME
if (-not $OutputDir) {
    $OutputDir = "C:\Windows\Temp\baseline-$Hostname"
}

New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null

Write-Host "========================================="
Write-Host " Endpoint Baseline Collection"
Write-Host " Host: $Hostname"
Write-Host " Output: $OutputDir"
Write-Host "========================================="

# System info
Write-Host "[1/7] Collecting system information..."
$SysInfo = [PSCustomObject]@{
    Hostname = $Hostname
    IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" }).IPAddress -join ", "
    MAC = (Get-NetAdapter | Where-Object { $_.Status -eq "Up" }).MacAddress -join ", "
    OS = (Get-CimInstance Win32_OperatingSystem).Caption
    OSVersion = (Get-CimInstance Win32_OperatingSystem).Version
    Domain = (Get-CimInstance Win32_ComputerSystem).Domain
    DomainJoined = (Get-CimInstance Win32_ComputerSystem).PartOfDomain
    LastBoot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    CollectionTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
}
$SysInfo | ConvertTo-Json | Out-File "$OutputDir\01-system-info.json"
Write-Host "[+] System info saved"

# Installed software
Write-Host "[2/7] Collecting installed software..."
$Software = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
                              "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, InstallLocation
$Software | Export-Csv "$OutputDir\02-installed-software.csv" -NoTypeInformation
Write-Host "[+] Found $($Software.Count) installed programs"

# Running services
Write-Host "[3/7] Collecting services..."
$Services = Get-CimInstance Win32_Service |
    Select-Object Name, DisplayName, State, StartMode, PathName, StartName, Description
$Services | Export-Csv "$OutputDir\03-services.csv" -NoTypeInformation
Write-Host "[+] Found $($Services.Count) services"

# Scheduled tasks
Write-Host "[4/7] Collecting scheduled tasks..."
$Tasks = Get-ScheduledTask | Where-Object { $_.State -ne "Disabled" } |
    Select-Object TaskName, TaskPath, State,
        @{N="Actions";E={($_.Actions | ForEach-Object { $_.Execute + " " + $_.Arguments }) -join "; "}},
        @{N="RunAs";E={$_.Principal.UserId}},
        @{N="Triggers";E={($_.Triggers | ForEach-Object { $_.CimClass.CimClassName }) -join "; "}}
$Tasks | Export-Csv "$OutputDir\04-scheduled-tasks.csv" -NoTypeInformation
Write-Host "[+] Found $($Tasks.Count) active scheduled tasks"

# Local user accounts
Write-Host "[5/7] Collecting local accounts..."
$Users = Get-LocalUser |
    Select-Object Name, Enabled, LastLogon, PasswordLastSet, Description,
        @{N="Groups";E={
            $u = $_.Name
            (Get-LocalGroup | Where-Object {
                (Get-LocalGroupMember $_.Name -ErrorAction SilentlyContinue).Name -match "\\$u$"
            }).Name -join ", "
        }}
$Users | Export-Csv "$OutputDir\05-local-users.csv" -NoTypeInformation
Write-Host "[+] Found $($Users.Count) local accounts"

# Network connections
Write-Host "[6/7] Collecting network connections..."
$Connections = Get-NetTCPConnection |
    Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State,
        @{N="Process";E={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}},
        OwningProcess
$Connections | Export-Csv "$OutputDir\06-network-connections.csv" -NoTypeInformation
Write-Host "[+] Found $($Connections.Count) TCP connections"

# Autoruns / persistence
Write-Host "[7/7] Collecting autorun entries..."
$Autoruns = @()

# Run keys
$RunKeys = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
)
foreach ($Key in $RunKeys) {
    if (Test-Path $Key) {
        $Props = Get-ItemProperty $Key -ErrorAction SilentlyContinue
        $Props.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
            $Autoruns += [PSCustomObject]@{
                Location = $Key
                Name = $_.Name
                Value = $_.Value
                Type = "Registry Run Key"
            }
        }
    }
}

# Startup folder
$StartupPaths = @(
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp",
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
)
foreach ($Path in $StartupPaths) {
    if (Test-Path $Path) {
        Get-ChildItem $Path -ErrorAction SilentlyContinue | ForEach-Object {
            $Autoruns += [PSCustomObject]@{
                Location = $Path
                Name = $_.Name
                Value = $_.FullName
                Type = "Startup Folder"
            }
        }
    }
}

$Autoruns | Export-Csv "$OutputDir\07-autoruns.csv" -NoTypeInformation
Write-Host "[+] Found $($Autoruns.Count) autorun entries"

# Generate summary report
Write-Host ""
Write-Host "[*] Generating summary report..."
$Report = @"
ENDPOINT BASELINE REPORT
========================
Hostname:       $Hostname
IP Address:     $($SysInfo.IP)
MAC Address:    $($SysInfo.MAC)
OS:             $($SysInfo.OS) ($($SysInfo.OSVersion))
Domain:         $($SysInfo.Domain) (Joined: $($SysInfo.DomainJoined))
Last Boot:      $($SysInfo.LastBoot)
Collected:      $($SysInfo.CollectionTime)

SUMMARY
-------
Installed Software:     $($Software.Count)
Services:               $($Services.Count) (Running: $(($Services | Where-Object {$_.State -eq 'Running'}).Count))
Active Scheduled Tasks: $($Tasks.Count)
Local Accounts:         $($Users.Count) (Enabled: $(($Users | Where-Object {$_.Enabled}).Count))
TCP Connections:        $($Connections.Count) (Established: $(($Connections | Where-Object {$_.State -eq 'Established'}).Count))
Autorun Entries:        $($Autoruns.Count)

FILES GENERATED
---------------
01-system-info.json         System information
02-installed-software.csv   Installed programs
03-services.csv             Windows services
04-scheduled-tasks.csv      Active scheduled tasks
05-local-users.csv          Local user accounts
06-network-connections.csv  TCP connections
07-autoruns.csv             Autorun/persistence entries
"@

$Report | Out-File "$OutputDir\00-SUMMARY.txt"
Write-Host $Report
Write-Host ""
Write-Host "[+] Baseline collection complete. Files saved to: $OutputDir"
Write-Host "[*] Copy $OutputDir to the DFIR server for analysis."
