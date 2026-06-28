<#
.SYNOPSIS
    Deploys Velociraptor agent to endpoints via WinRM/Invoke-Command (no GPO, no PsExec).
.DESCRIPTION
    Uses PowerShell Remoting (WinRM) to copy the repacked Velociraptor MSI to each target
    and install it silently. Requires WinRM enabled on targets and admin credentials.
.PARAMETER ServerIP
    The pfSense WAN IP that endpoints will connect to.
.PARAMETER MSIPath
    Path to the repacked Velociraptor client MSI.
.PARAMETER TargetList
    Path to a text file with one target IP/hostname per line.
.PARAMETER ThrottleLimit
    Maximum number of concurrent deployments. Defaults to 10.
.EXAMPLE
    .\deploy-velo-winrm.ps1 -ServerIP "10.0.1.50" -MSIPath ".\velociraptor-client.msi" -TargetList ".\targets.txt"
.EXAMPLE
    .\deploy-velo-winrm.ps1 -ServerIP "10.0.1.50" -MSIPath ".\velociraptor-client.msi" -TargetList ".\targets.txt" -ThrottleLimit 20
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

    [int]$ThrottleLimit = 10
)

$ErrorActionPreference = "Continue"

$Targets = Get-Content $TargetList | Where-Object { $_ -match '\S' }
$Credential = Get-Credential -Message "Enter admin credentials for target machines"

Write-Host "========================================="
Write-Host " Velociraptor WinRM Deployment"
Write-Host "========================================="
Write-Host "[*] Server IP: $ServerIP"
Write-Host "[*] MSI Path: $MSIPath"
Write-Host "[*] Targets: $($Targets.Count) hosts"
Write-Host "[*] Throttle: $ThrottleLimit concurrent"
Write-Host ""

$MSIBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $MSIPath))
$Results = @()

foreach ($Target in $Targets) {
    $Result = [PSCustomObject]@{
        Target        = $Target
        WinRM         = "Pending"
        CopyStatus    = "Pending"
        InstallStatus = "Pending"
        ServiceStatus = "Pending"
    }

    Write-Host "[*] ---- Deploying to $Target ----"

    # Step 1: Test connectivity
    if (-not (Test-Connection -ComputerName $Target -Count 1 -Quiet)) {
        Write-Host "[-] $Target is unreachable, skipping"
        $Result.WinRM = "Unreachable"
        $Result.CopyStatus = "Skipped"
        $Result.InstallStatus = "Skipped"
        $Result.ServiceStatus = "Skipped"
        $Results += $Result
        continue
    }

    # Step 2: Establish PS session
    $Session = $null
    try {
        $Session = New-PSSession -ComputerName $Target -Credential $Credential -ErrorAction Stop
        $Result.WinRM = "OK"
        Write-Host "[+] WinRM session established to $Target"
    } catch {
        Write-Host "[-] WinRM failed on ${Target}: $($_.Exception.Message)"
        $Result.WinRM = "Failed"
        $Result.CopyStatus = "Skipped"
        $Result.InstallStatus = "Skipped"
        $Result.ServiceStatus = "Skipped"
        $Results += $Result
        continue
    }

    # Step 3: Copy MSI to target via session
    try {
        Invoke-Command -Session $Session -ScriptBlock {
            param($Bytes)
            [System.IO.File]::WriteAllBytes("C:\Windows\Temp\velociraptor-client.msi", $Bytes)
        } -ArgumentList (,$MSIBytes) -ErrorAction Stop
        $Result.CopyStatus = "OK"
        Write-Host "[+] MSI copied to $Target"
    } catch {
        Write-Host "[-] Failed to copy MSI to ${Target}: $($_.Exception.Message)"
        $Result.CopyStatus = "Failed"
        $Result.InstallStatus = "Skipped"
        $Result.ServiceStatus = "Skipped"
        Remove-PSSession $Session
        $Results += $Result
        continue
    }

    # Step 4: Install MSI silently
    try {
        $ExitCode = Invoke-Command -Session $Session -ScriptBlock {
            $proc = Start-Process -FilePath "msiexec.exe" `
                -ArgumentList '/i "C:\Windows\Temp\velociraptor-client.msi" /qn /norestart' `
                -Wait -PassThru -NoNewWindow
            return $proc.ExitCode
        } -ErrorAction Stop

        if ($ExitCode -eq 0) {
            $Result.InstallStatus = "OK"
            Write-Host "[+] Agent installed on $Target"
        } else {
            $Result.InstallStatus = "Exit code: $ExitCode"
            Write-Host "[-] Install returned exit code $ExitCode on $Target"
        }
    } catch {
        Write-Host "[-] Failed to install on ${Target}: $($_.Exception.Message)"
        $Result.InstallStatus = "Failed"
        $Result.ServiceStatus = "Skipped"
        Remove-PSSession $Session
        $Results += $Result
        continue
    }

    # Step 5: Verify service is running
    Start-Sleep -Seconds 5
    try {
        $SvcStatus = Invoke-Command -Session $Session -ScriptBlock {
            $svc = Get-Service -Name "Velociraptor" -ErrorAction SilentlyContinue
            if ($svc) { return $svc.Status.ToString() }
            return "NotFound"
        } -ErrorAction Stop

        if ($SvcStatus -eq "Running") {
            $Result.ServiceStatus = "Running"
            Write-Host "[+] Velociraptor service is running on $Target"
        } else {
            $Result.ServiceStatus = $SvcStatus
            Write-Host "[!] Velociraptor service status on ${Target}: $SvcStatus"
        }
    } catch {
        $Result.ServiceStatus = "Check Failed"
        Write-Host "[-] Could not verify service status on $Target"
    }

    Remove-PSSession $Session
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
$ResultsFile = "deploy-results-winrm-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$Results | Export-Csv -Path $ResultsFile -NoTypeInformation
Write-Host "[*] Results exported to $ResultsFile"
