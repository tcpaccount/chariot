# Technical Deployment Playbook

**Version:** 1.0
**Companion to:** SOP 01 — Network Presence Establishment

This document contains actual commands, queries, and step-by-step technical procedures for deploying and configuring the DFIR server stack on-site. It is a reference document — look up the section you need, not a sequential guide.

---

## 1. Velociraptor Agent Deployment

### 1.1 Generate Site-Specific Client Config

This step is required for ALL paths (A, B, and C). The client config tells agents where to connect. The server URL is set in `client.config.yaml`, not as a repack flag.

**Step 1: Generate server and client configs (first-time setup)**

If `client.config.yaml` does not exist yet, generate it from the server config. The interactive wizard produces both files.

```bash
# SSH into the Velociraptor VM
ssh user@<velociraptor-VM-IP>

# Run the interactive config generator
./velociraptor config generate -i
```

The wizard will prompt for:

| Prompt | What to enter |
|--------|---------------|
| Deployment type | `Self Signed SSL` (for on-prem / IR use) |
| What OS will the server be deployed on? | `linux` |
| Public DNS name or IP | `<pfsense-WAN-IP>` (the IP clients will connect to) |
| Frontend port | `8001` (client comms) |
| GUI port | `8000` (admin web UI) |
| Path to datastore | Accept default or set `/opt/velociraptor` |
| GUI admin username | Set an admin username |
| GUI admin password | Set a password |
| Path to write server config | `/opt/velociraptor/server.config.yaml` |
| Path to write client config | `/opt/velociraptor/client.config.yaml` |

Accept defaults for any other prompts. This produces two files:

- `server.config.yaml` — full server configuration with keys and certs
- `client.config.yaml` — subset with only what agents need (server URL, certs, keys)

**Step 2: Verify the client config points at the correct server**

```bash
# Check the server_urls field
grep -A2 server_urls /opt/velociraptor/client.config.yaml
# Should show: https://<pfsense-WAN-IP>:8001
```

If the IP needs to change for a new site, edit the field directly:

```bash
vim /opt/velociraptor/client.config.yaml
# Update the server_urls field to: https://<pfsense-WAN-IP>:8001
```

**Step 3: Repack the MSI with the site-specific config**

```bash
./velociraptor config repack \
  --msi /opt/velociraptor/velociraptor-windows.msi \
  /opt/velociraptor/client.config.yaml \
  /tmp/velociraptor-client-repacked.msi
```

This works on Linux — no Windows required to repack a Windows MSI.

Copy the repacked MSI to a USB drive or network share accessible from deployment targets.

### 1.2 Path A: WinRM/Invoke-Command Deployment

**Prerequisites:** Admin credentials on target machines, WinRM enabled on targets, IP list of targets.

No GPO infrastructure required. No PsExec binary required. Uses native PowerShell Remoting over WinRM (TCP 5985/5986).

**WinRM prerequisite — verify or enable on targets:**

If WinRM is not yet enabled, it must be turned on per machine (locally, or via a one-time GPO/startup script before this path is used):

```powershell
# Run locally on each target (elevated)
Enable-PSRemoting -Force
```

To verify WinRM is reachable from the deployment machine:

```powershell
Test-WSMan -ComputerName <target-IP>
```

If targets are not domain-joined or the deployment machine is in a different domain/workgroup, add them to the TrustedHosts list on the deployment machine:

```powershell
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
# Or a specific list:
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "192.168.1.10,192.168.1.11" -Force
```

**Step 1: Prepare target list**

Create a text file `targets.txt` with one IP or hostname per line:

```
192.168.1.10
192.168.1.11
192.168.1.12
```

**Step 2: Deploy using Invoke-Command**

```powershell
$Targets = Get-Content "targets.txt"
$MSIPath = ".\velociraptor-client-repacked.msi"
$Credential = Get-Credential  # Prompts for admin username/password
$MSIBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $MSIPath))

foreach ($Target in $Targets) {
    Write-Host "[*] Deploying to $Target..."

    # Establish WinRM session
    $Session = New-PSSession -ComputerName $Target -Credential $Credential

    # Copy MSI via session (no admin share access required)
    Invoke-Command -Session $Session -ScriptBlock {
        param($Bytes)
        [System.IO.File]::WriteAllBytes("C:\Windows\Temp\velociraptor-client.msi", $Bytes)
    } -ArgumentList (,$MSIBytes)

    # Install silently
    Invoke-Command -Session $Session -ScriptBlock {
        Start-Process -FilePath "msiexec.exe" `
            -ArgumentList '/i "C:\Windows\Temp\velociraptor-client.msi" /qn /norestart' `
            -Wait -NoNewWindow
    }

    # Verify service
    Invoke-Command -Session $Session -ScriptBlock {
        Get-Service -Name "Velociraptor" | Select-Object Status
    }

    Remove-PSSession $Session
    Write-Host "[+] Deployed to $Target"
}
```

See: `scripts/deploy-velo-winrm.ps1` for the full scripted version with error handling and check-in verification.

**Rollback:**

```powershell
# Remote uninstall via Invoke-Command
$Session = New-PSSession -ComputerName <target-IP> -Credential (Get-Credential)
Invoke-Command -Session $Session -ScriptBlock {
    Start-Process -FilePath "msiexec.exe" `
        -ArgumentList '/x "C:\Windows\Temp\velociraptor-client.msi" /qn' `
        -Wait -NoNewWindow
    sc.exe delete Velociraptor
}
Remove-PSSession $Session
```

### 1.3 Path B: Local/PsExec Deployment

**Prerequisites:**

- Local admin credentials on target machines (or domain admin)
- PsExec.exe on the deployment machine (download from [Sysinternals](https://docs.microsoft.com/en-us/sysinternals/downloads/psexec))
- SMB (TCP 445) open on targets — PsExec uses this for file copy and remote execution
- Admin shares enabled on targets (`C$`) — on by default, but may be disabled by hardening policies
- IP list of targets

**Verify prerequisites from the deployment machine:**

```powershell
# Test SMB connectivity
Test-NetConnection -ComputerName <target-IP> -Port 445

# Test admin share access
dir "\\<target-IP>\C$"
```

If `dir \\target\C$` returns "Access is denied," either credentials lack admin rights or admin shares are disabled. If the connection times out, TCP 445 is blocked by the firewall.

**Enable SMB and open the firewall on a target (run locally, elevated):**

```powershell
# Enable the SMB server feature (usually already enabled)
Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force

# Open File and Printer Sharing firewall rule
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
```

**Step 1: Prepare target list**

Create a text file `targets.txt` with one IP per line:

```
192.168.1.10
192.168.1.11
192.168.1.12
```

**Step 2: Deploy using PsExec**

```powershell
# For each target, copy the MSI and install silently
$Targets = Get-Content "targets.txt"
$MSIPath = ".\velociraptor-client-repacked.msi"
$Credential = Get-Credential  # Prompts for admin username/password

foreach ($Target in $Targets) {
    Write-Host "[*] Deploying to $Target..."

    # Copy MSI to target
    $RemotePath = "\\$Target\C$\Windows\Temp\velociraptor-client.msi"
    Copy-Item $MSIPath -Destination $RemotePath -Force

    # Install silently via PsExec
    .\PsExec.exe \\$Target -accepteula -u $Credential.UserName -p $Credential.GetNetworkCredential().Password `
        msiexec /i "C:\Windows\Temp\velociraptor-client.msi" /qn /norestart

    Write-Host "[+] Deployed to $Target"
}
```

See: `scripts/deploy-velo-local.ps1` for the full scripted version with error handling and check-in verification.

**Step 3: Manual USB deployment (isolated hosts)**

For hosts not reachable over the network:

1. Copy `velociraptor-client-repacked.msi` to USB drive
2. Plug USB into target machine
3. Open elevated Command Prompt
4. Run: `msiexec /i E:\velociraptor-client-repacked.msi /qn /norestart`
   (Replace `E:` with the USB drive letter)
5. Verify the Velociraptor service is running: `sc query Velociraptor`

**Rollback:**

```powershell
# Remote uninstall via PsExec
.\PsExec.exe \\<target-IP> msiexec /x "C:\Windows\Temp\velociraptor-client.msi" /qn

# Or locally
msiexec /x "C:\Windows\Temp\velociraptor-client.msi" /qn
sc delete Velociraptor
```

### 1.4 Path C: AD/GPO Deployment

**Prerequisites:**

- Domain Admin credentials
- Network connectivity to a Domain Controller
- SMB (TCP 445) open on targets — machines pull the MSI from the NETLOGON share over SMB
- File and Printer Sharing firewall rule enabled on targets

If SMB is blocked on targets, the GPO will apply but the MSI install will silently fail because the machine cannot reach `\\DC\NETLOGON\...`. Enable it on targets:

```powershell
Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
```

#### 1.4.0 GPO Prerequisite — Enable Remote Scheduled Tasks Firewall Rule

If `Invoke-GPUpdate` fails with "computer is not responding," the target machine's firewall is blocking Remote Scheduled Tasks Management. Deploy this fix as a GPO startup script so all machines enable the rule automatically at boot.

```powershell
Enable-NetFirewallRule -DisplayGroup "Remote Scheduled Tasks Management"
```

**Deployment steps:**

1. Copy the script to `\\<DC-hostname>\NETLOGON\Scripts\`
2. Open `gpmc.msc` → create or edit a GPO (e.g., "Enable Remote Tasks FW Rule")
3. **Computer Configuration → Policies → Windows Settings → Scripts → Startup**
4. Add `enable-remote-tasks-fw.ps1`
5. Link the GPO to the domain root or target OU
6. Machines will apply the rule on next reboot or `gpupdate /force`

**Force GP update on all domain machines remotely:**

```powershell
Get-ADComputer -Filter * | ForEach-Object {
    Invoke-GPUpdate -Computer $_.Name -Force -RandomDelayInMinutes 0
}
```

**Parallel version (PowerShell 7+):**

```powershell
Get-ADComputer -Filter * | ForEach-Object -Parallel {
    Invoke-GPUpdate -Computer $_.Name -Force -RandomDelayInMinutes 0
} -ThrottleLimit 10
```

#### 1.4.1 GPO Deployment Steps

**Step 1: Copy MSI to a network share accessible by domain machines**

```powershell
# Create a share on a DC or file server (or use existing SYSVOL)
$SharePath = "\\<DC-hostname>\NETLOGON\Velociraptor"
New-Item -Path $SharePath -ItemType Directory -Force
Copy-Item "velociraptor-client-repacked.msi" -Destination $SharePath
```

**Step 2: Create GPO for MSI deployment**

Note: to check domain name - Get-ADDomain

```powershell
# Import Group Policy module
Import-Module GroupPolicy

# Create new GPO
$GPO = New-GPO -Name "Deploy Velociraptor Agent" -Comment "DFIR - Velociraptor agent deployment"

# Link GPO to target OU (use the domain root to cover all machines, or a specific OU)
$GPO | New-GPLink -Target "<target-OU-DN>"
# Example: $GPO | New-GPLink -Target "DC=contoso,DC=com"
# Example: $GPO | New-GPLink -Target "OU=Workstations,DC=contoso,DC=com"
```

**Step 3: Assign MSI package to the GPO**

This must be done via GPMC UI or AGPM since PowerShell doesn't natively support software installation GPO settings:

1. Open `gpmc.msc`
2. Navigate to the "Deploy Velociraptor Agent" GPO
3. Edit → Computer Configuration → Policies → Software Settings → Software Installation
4. Right-click → New → Package
5. Browse to `\\<DC-hostname>\NETLOGON\Velociraptor\velociraptor-client-repacked.msi`
6. Select "Assigned" deployment method
7. OK

**IMPORTANT:** The path in step 5 MUST use the UNC hostname (`\\DC-HOSTNAME\NETLOGON\...`), NOT an IP address (`\\192.168.x.x\...`). GPO software installation resolves the path on the client side via the domain — using an IP will cause the install to silently fail on target machines.

**Step 4: Force group policy update**

```powershell
# Force GP update on all domain machines (requires PsExec or Invoke-GPUpdate)
# Option 1: Using Invoke-GPUpdate (Windows Server 2012+)
Get-ADComputer -Filter * | ForEach-Object {
    Invoke-GPUpdate -Computer $_.Name -Force -RandomDelayInMinutes 0
}

# Option 2: Using PsExec for broader compatibility
# See scripts/deploy-velo-ad.ps1 for the full scripted version
```

**Step 5: Verify deployment**

```
# From Velociraptor frontend — VQL query to check connected clients
SELECT client_id, os_info.hostname, os_info.system, last_seen_at
FROM clients()
WHERE last_seen_at > now() - 600
ORDER BY os_info.hostname
```

**Rollback:**

```powershell
# Remove the GPO link
Remove-GPLink -Name "Deploy Velociraptor Agent" -Target "<target-OU-DN>"

# Remove the GPO
Remove-GPO -Name "Deploy Velociraptor Agent"

# Uninstall agent from endpoints (run remotely or via another GPO)
msiexec /x velociraptor-client-repacked.msi /qn
```

### 1.5 Agent Config Reference

**Changes per site (must be updated):**
- `server_url` — pfSense WAN IP and Velociraptor client comms port
- TLS certificates — if using site-specific certs

**Stays standard (do not change):**
- Collection artifacts and monitoring configuration
- Client labels and metadata settings
- Writeback file location (`C:\Program Files\Velociraptor\velociraptor.writeback.yaml`)

---

## 2. Security Onion — Traffic Ingestion Verification

### 2.1 Verify Tap Interfaces Are Receiving Traffic

```bash
# SSH into Security Onion VM
ssh user@<security-onion-VM-IP>

# Check each tap interface for packet counts
sudo tcpdump -i <tap-interface-1> -c 10 -q
sudo tcpdump -i <tap-interface-2> -c 10 -q
sudo tcpdump -i <tap-interface-3> -c 10 -q
```

Each command should show packets being captured. If no packets appear, check physical tap connections and pfSense interface assignments.

### 2.2 Verify Parsing and Normalization

```bash
# Check Zeek (network metadata) is processing
sudo so-zeek-status

# Check Suricata (IDS alerts) is running
sudo so-suricata-status

# Check recent Zeek logs
ls -lt /nsm/zeek/logs/current/
```

### 2.3 Verify Logs in SIEM View

1. Open Security Onion web UI: `https://<security-onion-VM-IP>`
2. Navigate to Hunt or Dashboards
3. Set time range to "Last 15 minutes"
4. Confirm events are appearing (DNS queries, HTTP connections, etc.)

If no events appear but tcpdump shows traffic, check:

```bash
# Elasticsearch status
sudo so-elasticsearch-status

# Logstash pipeline
sudo so-logstash-status
```

### 2.4 Fix: Fleet Agent Certificate Failure Behind pfSense/NAT

When Security Onion sits behind pfSense with port forwarding, Elastic Fleet agents fail to register with a certificate validation error. The Fleet server certificate's SANs don't include the pfSense WAN IP that agents connect through.

**Root cause:** The Fleet certificate is generated by Salt in `/opt/so/saltstack/default/salt/elasticfleet/ssl.sls`. The SAN line builds entries from the SO hostname, URL base, and node IP — but not the external pfSense IP. When `custom_fqdn` is set, it's added with a `DNS:` prefix, which fails validation if the value is an IP address (IPs require `IP:` prefix).

The original SAN line in `ssl.sls`:

```jinja
- subjectAltName: DNS:{{ GLOBALS.hostname }},DNS:{{ GLOBALS.url_base }},IP:{{ GLOBALS.node_ip }}{% if ELASTICFLEETMERGED.config.server.custom_fqdn | length > 0 %},DNS:{{ ELASTICFLEETMERGED.config.server.custom_fqdn | join(',DNS:') }}{% endif %}
```

**Fix — Step 1: Set the pfSense WAN IP as custom_fqdn**

```bash
sudo so-elasticfleet-config-set server.custom_fqdn <pfsense-WAN-IP>
```

**Fix — Step 2: Copy the default ssl.sls to local override**

```bash
sudo cp /opt/so/saltstack/default/salt/elasticfleet/ssl.sls \
        /opt/so/saltstack/local/salt/elasticfleet/ssl.sls
```

**Fix — Step 3: Edit the local copy to use `IP:` prefix for IP-based custom FQDNs**

```bash
sudo vim /opt/so/saltstack/local/salt/elasticfleet/ssl.sls
```

Change the SAN line to handle IPs correctly (from github):

```jinja
- subjectAltName: DNS:{{ GLOBALS.hostname }},DNS:{{ GLOBALS.url_base }},IP:{{ GLOBALS.node_ip }}{% if ELASTICFLEETMERGED.config.server.custom_fqdn | length > 0 %}{% for fqdn in ELASTICFLEETMERGED.config.server.custom_fqdn %}{% if fqdn | is_ip %},IP:{{ fqdn }}{% else %},DNS:{{ fqdn }}{% endif %}{% endfor %}{% endif %}
```

Change the SAN line to handle IPs correctly (my fix that worked in the past. DNS changed to IP). Find 2 placed to change in the file:
```jinja
- subjectAltName: DNS:{{ GLOBALS.hostname }},DNS:{{ GLOBALS.url_base }},IP:{{ GLOBALS.node_ip }}{% if ELASTICFLEETMERGED.config.server.custom_fqdn | length > 0 %},DNS:{{ ELASTICFLEETMERGED.config.server.custom_fqdn | join(',IP:') }}{% endif %}
```

**Fix — Step 4: Apply changes and regenerate certificates**

```bash
sudo salt-call state.highstate
```

Verify the new certificate includes the pfSense IP:

```bash
openssl x509 -in /etc/pki/elasticfleet-server.crt -noout -text | grep -A1 "Subject Alternative Name"
```

The output should show `IP Address:<pfsense-WAN-IP>` in the SAN list.

**Fix — Step 5: Re-download and redeploy Fleet agent installers**

After certificate regeneration, existing agent installers are stale. Download fresh ones:

```bash
sudo so-elastic-agent-get-installers
```

Then redeploy to endpoints.

### 2.5 SO Elastic Agent Deployment

Both paths below produce a **full SO agent** — same binary, same integrations (Elastic Defend, osquery, endpoint telemetry), same indices and views in SO. The enrollment token determines which Fleet policy the agent receives, not how it was installed. As long as the token maps to SO's agent policy, the agent is fully functional.

**Prerequisites (both paths):** Admin credentials on target machines, WinRM enabled on targets, IP list of targets (same as Velociraptor Path A).

**Prepare on the SO manager before deployment:**

```bash
# Generate bundled installers (Path A)
sudo so-elastic-agent-get-installers
# Installers are written to /nsm/elastic-agent/

# Retrieve enrollment token (Path B)
sudo so-elastic-agent-get-token
```

The Fleet URL is `https://<pfsense-WAN-IP>:8220` (or `https://<SO-IP>:8220` if agents connect directly to SO without NAT).

### 2.5.1 Path A: SO Bundled Installer via WinRM

Security Onion generates self-contained MSI installers with the Fleet URL and enrollment token already baked in — no flags needed on the endpoint. This path requires the Fleet certificate to be valid (if behind NAT, apply section 2.4 first).

**Step 1: Prepare target list**

Create a text file `targets.txt` with one IP or hostname per line:

```
192.168.1.10
192.168.1.11
192.168.1.12
```

**Step 2: Deploy using Invoke-Command**

```powershell
$Targets = Get-Content "targets.txt"
$MSIPath = ".\so-elastic-agent_windows_amd64.msi"
$Credential = Get-Credential
$MSIBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $MSIPath))

foreach ($Target in $Targets) {
    Write-Host "[*] Deploying SO agent to $Target..."

    # Establish WinRM session
    $Session = New-PSSession -ComputerName $Target -Credential $Credential

    # Copy MSI via session
    Invoke-Command -Session $Session -ScriptBlock {
        param($Bytes)
        [System.IO.File]::WriteAllBytes("C:\Windows\Temp\so-elastic-agent.msi", $Bytes)
    } -ArgumentList (,$MSIBytes)

    # Install silently
    Invoke-Command -Session $Session -ScriptBlock {
        Start-Process -FilePath "msiexec.exe" `
            -ArgumentList '/i "C:\Windows\Temp\so-elastic-agent.msi" /qn /norestart' `
            -Wait -NoNewWindow
    }

    # Verify Elastic Agent service is running
    Invoke-Command -Session $Session -ScriptBlock {
        Get-Service -Name "Elastic Agent" -ErrorAction SilentlyContinue | Select-Object Status
    }

    Remove-PSSession $Session
    Write-Host "[+] Deployed to $Target"
}
```

**Override Fleet host or token if needed:**

```powershell
# Inside the Invoke-Command install block, replace the ArgumentList with:
'/i "C:\Windows\Temp\so-elastic-agent.msi" /qn /norestart FLEET=https://<alt-fleet-IP>:8220 TOKEN=<enrollment-token>'
```

**Step 3: Verify enrollment**

Check the SO Fleet UI: **SO Web UI → Fleet → Agents** — deployed agents should appear as "Healthy."

**Note:** If agents fail to enroll due to certificate errors (common behind pfSense/NAT), fix the certificate first (section 2.4). The SO bundled installer does not support `--insecure` — use Path B instead as a workaround.

**Rollback:**

```powershell
$Session = New-PSSession -ComputerName <target-IP> -Credential (Get-Credential)
Invoke-Command -Session $Session -ScriptBlock {
    Start-Process -FilePath "msiexec.exe" `
        -ArgumentList '/x "C:\Windows\Temp\so-elastic-agent.msi" /qn' `
        -Wait -NoNewWindow
}
Remove-PSSession $Session
```

### 2.5.2 Path B: Raw Elastic Agent with --insecure via WinRM

Uses the standard `elastic-agent install` command directly, bypassing SO's bundled installer. This allows the `--insecure` flag to skip certificate validation — useful when SO is behind pfSense/NAT and the certificate fix (section 2.4) hasn't been applied yet.

**Prerequisites (in addition to WinRM):**

- Elastic Agent zip on the deployment machine (download from Elastic's website or extract from SO)
- SO enrollment token (from `sudo so-elastic-agent-get-token` on the SO manager)
- Fleet URL (`https://<pfsense-WAN-IP>:8220`)

**Step 1: Prepare target list**

Create a text file `targets.txt` with one IP or hostname per line:

```
192.168.1.10
192.168.1.11
192.168.1.12
```

**Step 2: Deploy using Invoke-Command**

```powershell
$Targets = Get-Content "targets.txt"
$AgentZip = ".\elastic-agent-windows-x86_64.zip"
$Credential = Get-Credential
$FleetURL = "https://<pfsense-WAN-IP>:8220"
$Token = "<enrollment-token>"
$ZipBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $AgentZip))

foreach ($Target in $Targets) {
    Write-Host "[*] Deploying SO agent (insecure) to $Target..."

    # Establish WinRM session
    $Session = New-PSSession -ComputerName $Target -Credential $Credential

    # Copy agent zip via session
    Invoke-Command -Session $Session -ScriptBlock {
        param($Bytes)
        [System.IO.File]::WriteAllBytes("C:\Windows\Temp\elastic-agent.zip", $Bytes)
    } -ArgumentList (,$ZipBytes)

    # Extract and install with --insecure
    Invoke-Command -Session $Session -ScriptBlock {
        param($FleetURL, $Token)
        Expand-Archive -Path "C:\Windows\Temp\elastic-agent.zip" `
            -DestinationPath "C:\Windows\Temp\elastic-agent" -Force
        $AgentDir = Get-ChildItem "C:\Windows\Temp\elastic-agent" | Select-Object -First 1
        & "$($AgentDir.FullName)\elastic-agent.exe" install `
            --url=$FleetURL `
            --enrollment-token=$Token `
            --insecure `
            --non-interactive
    } -ArgumentList $FleetURL, $Token

    # Verify Elastic Agent service is running
    Invoke-Command -Session $Session -ScriptBlock {
        Get-Service -Name "Elastic Agent" -ErrorAction SilentlyContinue | Select-Object Status
    }

    Remove-PSSession $Session
    Write-Host "[+] Deployed to $Target"
}
```

The `--insecure` flag skips all certificate chain verification. The `--non-interactive` flag prevents the installer from prompting for confirmation.

**Step 3: Verify enrollment**

Check the SO Fleet UI: **SO Web UI → Fleet → Agents** — agents should appear as "Healthy" with full policy applied.

**Important:** The agent is fully functional — same policy, same data collection, same indices as Path A. The only difference is the transport is not certificate-verified. Suitable for IR engagements where speed matters and the network is trusted. For long-term deployments, apply the certificate fix (section 2.4) and redeploy via Path A.

**Rollback:**

```powershell
$Session = New-PSSession -ComputerName <target-IP> -Credential (Get-Credential)
Invoke-Command -Session $Session -ScriptBlock {
    & "C:\Program Files\Elastic\Agent\elastic-agent.exe" uninstall --force
}
Remove-PSSession $Session
```

---

## 3. DFIR-IRIS — Case Setup

### 3.1 Create New Case

1. Open DFIR-IRIS web UI: `https://<dfir-iris-VM-IP>`
2. Log in (default: administrator / changeme — update on first use)
3. Navigate to **Manage → Cases → Add Case**
4. Fill in:
   - Case name: `<client-name>-IR-<date>`
   - Description: Brief engagement description
   - Client: Add client if not existing
   - Classification: Select appropriate type
5. Save

### 3.2 Import Asset List

After completing asset enumeration:

1. Navigate to the case → **Assets**
2. Use **Import from CSV** or add manually
3. For each asset, enter: hostname, IP, OS, type (server/workstation/network device), description
4. Asset types map to DFIR-IRIS categories:
   - Windows workstation → "Windows - Computer"
   - Windows server → "Windows - Server"
   - Linux → "Linux - Computer"
   - Network device → "Other"

### 3.3 Triage Result Entry

For each triage finding:

1. Navigate to the case → **IOCs** or **Evidence** (depending on finding type)
2. Add IOC/Evidence entry:
   - Type: file hash, IP, domain, registry key, etc.
   - Value: the actual indicator
   - Description: what was found and why it's suspicious
   - Tags: map to finding categories (persistence, lateral-movement, etc.)
3. Link to the relevant asset(s)
4. Set TLP level as appropriate

---

## 4. Endpoint Baselining (Self-Sufficient Discovery)

### 4.1 Velociraptor-Based Collection

For endpoints with deployed agents, run these VQL artifacts to baseline:

**Installed Software:**

```
SELECT * FROM Artifact.Windows.Sys.Programs()
```

**Running Services:**

```
SELECT Name, DisplayName, Status, StartMode, PathName, StartName
FROM Artifact.Windows.System.Services()
```

**Scheduled Tasks:**

```
SELECT * FROM Artifact.Windows.System.TaskScheduler()
```

**Local User Accounts:**

```
SELECT * FROM Artifact.Windows.Sys.Users()
```

**Network Connections:**

```
SELECT * FROM Artifact.Windows.Network.Netstat()
```

**Autoruns (Persistence):**

```
SELECT * FROM Artifact.Windows.Sys.StartupItems()
```

Run these as a hunt across all clients:

1. Velociraptor frontend → Hunts → New Hunt
2. Select artifacts listed above
3. Target: All clients
4. Launch hunt
5. Download results for analysis

### 4.2 PowerShell Fallback (No Agent)

For endpoints where agents could not be deployed, use the baselining script:

See: `scripts/baseline-endpoints.ps1`

Run locally on the target or remotely via PsExec:

```powershell
.\PsExec.exe \\<target-IP> -c baseline-endpoints.ps1
```

### 4.3 Baselining Reference — Normal vs Suspicious

| Area | Normal | Investigate Further |
|------|--------|-------------------|
| Scheduled Tasks | OS defaults, known software updaters | Tasks with encoded commands, tasks running from temp/user dirs, recently created tasks |
| Services | OS services, known AV/software | Services with random names, services running from temp dirs, unsigned binaries |
| Autoruns | Known startup items, OS components | Unknown DLLs in Run keys, unsigned binaries, recently added entries |
| Network Connections | DNS, DHCP, internal services, known cloud IPs | Connections to unusual ports, high-frequency beaconing, connections to unknown external IPs |
| Local Accounts | Administrator (disabled), default accounts | Recently created admin accounts, accounts with blank descriptions, enabled Guest account |

