<#
.SYNOPSIS
    Deploys Velociraptor agent to domain-joined endpoints via Active Directory GPO.
.PARAMETER ServerIP
    The pfSense WAN IP that endpoints will connect to.
.PARAMETER MSIPath
    Path to the repacked Velociraptor client MSI.
.PARAMETER TargetOU
    Distinguished Name of the OU to target. Defaults to domain root.
.PARAMETER GPOName
    Name for the GPO. Defaults to "Deploy Velociraptor Agent".
.PARAMETER SharePath
    Network share path to host the MSI. Defaults to NETLOGON\Velociraptor.
.EXAMPLE
    .\deploy-velo-ad.ps1 -ServerIP "10.0.1.50" -MSIPath ".\velociraptor-client.msi"
.EXAMPLE
    .\deploy-velo-ad.ps1 -ServerIP "10.0.1.50" -MSIPath ".\velociraptor-client.msi" -TargetOU "OU=Workstations,DC=contoso,DC=com"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerIP,

    [Parameter(Mandatory=$true)]
    [ValidateScript({Test-Path $_})]
    [string]$MSIPath,

    [string]$TargetOU,

    [string]$GPOName = "Deploy Velociraptor Agent",

    [string]$SharePath
)

$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory -ErrorAction Stop
Import-Module GroupPolicy -ErrorAction Stop

$Domain = Get-ADDomain
if (-not $TargetOU) {
    $TargetOU = $Domain.DistinguishedName
    Write-Host "[*] No TargetOU specified, using domain root: $TargetOU"
}

if (-not $SharePath) {
    $SharePath = "\\$($Domain.PDCEmulator)\NETLOGON\Velociraptor"
}

Write-Host "========================================="
Write-Host " Velociraptor AD/GPO Deployment"
Write-Host "========================================="
Write-Host "[*] Server IP: $ServerIP"
Write-Host "[*] MSI Path: $MSIPath"
Write-Host "[*] Target OU: $TargetOU"
Write-Host "[*] GPO Name: $GPOName"
Write-Host "[*] Share Path: $SharePath"
Write-Host ""

# Step 1: Create share directory and copy MSI
Write-Host "[1/5] Copying MSI to network share..."
if (-not (Test-Path $SharePath)) {
    New-Item -Path $SharePath -ItemType Directory -Force | Out-Null
}
Copy-Item $MSIPath -Destination "$SharePath\velociraptor-client.msi" -Force
Write-Host "[+] MSI copied to $SharePath\velociraptor-client.msi"

# Step 2: Create GPO
Write-Host "[2/5] Creating GPO..."
$ExistingGPO = Get-GPO -Name $GPOName -ErrorAction SilentlyContinue
if ($ExistingGPO) {
    Write-Host "[!] GPO '$GPOName' already exists. Remove it first or use a different name."
    Write-Host "    To remove: Remove-GPO -Name '$GPOName'"
    exit 1
}
$GPO = New-GPO -Name $GPOName -Comment "DFIR - Velociraptor agent deployment for IR engagement"
Write-Host "[+] GPO created: $($GPO.DisplayName) (ID: $($GPO.Id))"

# Step 3: Link GPO to target OU
Write-Host "[3/5] Linking GPO to target OU..."
$GPO | New-GPLink -Target $TargetOU -LinkEnabled Yes | Out-Null
Write-Host "[+] GPO linked to $TargetOU"

# Step 4: Remind to assign MSI package via GPMC
Write-Host "[4/5] MANUAL STEP REQUIRED:"
Write-Host ""
Write-Host "    The MSI package must be assigned via Group Policy Management Console (gpmc.msc):"
Write-Host "    1. Open gpmc.msc"
Write-Host "    2. Navigate to: $GPOName"
Write-Host "    3. Edit -> Computer Configuration -> Policies -> Software Settings -> Software Installation"
Write-Host "    4. Right-click -> New -> Package"
Write-Host "    5. Browse to: $SharePath\velociraptor-client.msi"
Write-Host "    6. Select 'Assigned' deployment method"
Write-Host "    7. Click OK"
Write-Host ""
Read-Host "Press Enter after completing the manual step"

# Step 5: Force GP update
Write-Host "[5/5] Forcing group policy update on domain computers..."
$Computers = Get-ADComputer -Filter * -SearchBase $TargetOU
$Total = $Computers.Count
$Success = 0
$Failed = 0

foreach ($Computer in $Computers) {
    try {
        Invoke-GPUpdate -Computer $Computer.Name -Force -RandomDelayInMinutes 0 -ErrorAction Stop
        $Success++
        Write-Host "[+] GP update sent to $($Computer.Name)"
    } catch {
        $Failed++
        Write-Host "[-] Failed to update $($Computer.Name): $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "========================================="
Write-Host " Deployment Summary"
Write-Host "========================================="
Write-Host "[*] Total computers in OU: $Total"
Write-Host "[+] GP update sent: $Success"
Write-Host "[-] GP update failed: $Failed"
Write-Host ""
Write-Host "[*] Agents will install on next GP refresh or reboot."
Write-Host "[*] Monitor check-in from Velociraptor frontend:"
Write-Host "    https://${ServerIP}:8000"
Write-Host ""
Write-Host "[*] VQL to verify check-in:"
Write-Host '    SELECT client_id, os_info.hostname, last_seen_at FROM clients() WHERE last_seen_at > now() - 600'
