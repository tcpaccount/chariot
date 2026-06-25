<#
.SYNOPSIS
    Deploys Velociraptor agent to endpoints via PsExec (no Active Directory required).
.PARAMETER ServerIP
    The pfSense WAN IP that endpoints will connect to.
.PARAMETER MSIPath
    Path to the repacked Velociraptor client MSI.
.PARAMETER TargetList
    Path to a text file with one target IP per line.
.PARAMETER PsExecPath
    Path to PsExec.exe. Defaults to .\PsExec.exe in the current directory.
.EXAMPLE
    .\deploy-velo-local.ps1 -ServerIP "10.0.1.50" -MSIPath ".\velociraptor-client.msi" -TargetList ".\targets.txt"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerIP,

    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [string]$MSIPath,

    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [string]$TargetList,

    [string]$PsExecPath = ".\PsExec.exe"
)

$ErrorActionPreference = "Continue"

if (-not (Test-Path $PsExecPath)) {
    Write-Host "[!] PsExec not found at $PsExecPath"
    Write-Host "[!] Download from: https://docs.microsoft.com/en-us/sysinternals/downloads/psexec"
    exit 1
}

$Targets = Get-Content $TargetList | Where-Object { $_ -match '\S' }
$Credential = Get-Credential -Message "Enter local admin credentials for target machines"
$Username = $Credential.UserName
$Password = $Credential.GetNetworkCredential().Password

Write-Host "========================================="
Write-Host " Velociraptor Local/PsExec Deployment"
Write-Host "========================================="
Write-Host "[*] Server IP: $ServerIP"
Write-Host "[*] MSI Path: $MSIPath"
Write-Host "[*] Targets: $($Targets.Count) hosts"
Write-Host ""

$Results = @()

foreach ($Target in $Targets) {
    $Result = [PSCustomObject]@{
        Target = $Target
        CopyStatus = "Pending"
        InstallStatus = "Pending"
        ServiceStatus = "Pending"
    }

    Write-Host "[*] ---- Deploying to $Target ----"

    # Step 1: Test connectivity
    if (-not (Test-Connection -ComputerName $Target -Count 1 -Quiet)) {
        Write-Host "[-] $Target is unreachable, skipping"
        $Result.CopyStatus = "Unreachable"
        $Result.InstallStatus = "Skipped"
        $Result.ServiceStatus = "Skipped"
        $Results += $Result
        continue
    }

    # Step 2: Copy MSI to target
    try {
        $RemotePath = "\\$Target\C`$\Windows\Temp\velociraptor-client.msi"
        Copy-Item $MSIPath -Destination $RemotePath -Force -ErrorAction Stop
        $Result.CopyStatus = "OK"
        Write-Host "[+] MSI copied to $Target"
    } catch {
        Write-Host "[-] Failed to copy MSI to ${Target}: $($_.Exception.Message)"
        $Result.CopyStatus = "Failed"
        $Result.InstallStatus = "Skipped"
        $Result.ServiceStatus = "Skipped"
        $Results += $Result
        continue
    }

    # Step 3: Install via PsExec
    try {
        $InstallArgs = "\\$Target -accepteula -u $Username -p $Password msiexec /i `"C:\Windows\Temp\velociraptor-client.msi`" /qn /norestart"
        $Process = Start-Process -FilePath $PsExecPath -ArgumentList $InstallArgs -Wait -PassThru -NoNewWindow
        if ($Process.ExitCode -eq 0) {
            $Result.InstallStatus = "OK"
            Write-Host "[+] Agent installed on $Target"
        } else {
            $Result.InstallStatus = "Exit code: $($Process.ExitCode)"
            Write-Host "[-] Install returned exit code $($Process.ExitCode) on $Target"
        }
    } catch {
        Write-Host "[-] Failed to install on ${Target}: $($_.Exception.Message)"
        $Result.InstallStatus = "Failed"
        $Result.ServiceStatus = "Skipped"
        $Results += $Result
        continue
    }

    # Step 4: Verify service is running
    Start-Sleep -Seconds 5
    try {
        $SvcCheck = & $PsExecPath "\\$Target" -accepteula -u $Username -p $Password sc query Velociraptor 2>&1
        if ($SvcCheck -match "RUNNING") {
            $Result.ServiceStatus = "Running"
            Write-Host "[+] Velociraptor service is running on $Target"
        } else {
            $Result.ServiceStatus = "Not Running"
            Write-Host "[!] Velociraptor service is NOT running on $Target"
        }
    } catch {
        $Result.ServiceStatus = "Check Failed"
        Write-Host "[-] Could not verify service status on $Target"
    }

    $Results += $Result
}

# Summary
Write-Host ""
Write-Host "========================================="
Write-Host " Deployment Summary"
Write-Host "========================================="
Write-Host ""
$Results | Format-Table -AutoSize
Write-Host ""
Write-Host "[*] Monitor agent check-in from Velociraptor frontend:"
Write-Host "    https://${ServerIP}:8000"
Write-Host ""
Write-Host "[*] VQL to verify check-in:"
Write-Host '    SELECT client_id, os_info.hostname, last_seen_at FROM clients() WHERE last_seen_at > now() - 600'

# Export results to CSV
$ResultsFile = "deploy-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$Results | Export-Csv -Path $ResultsFile -NoTypeInformation
Write-Host "[*] Results exported to $ResultsFile"
