# Technical Deployment Playbook

**Version:** 1.0
**Companion to:** SOP 01 — Network Presence Establishment

This document contains actual commands, queries, and step-by-step technical procedures for deploying and configuring the DFIR server stack on-site. It is a reference document — look up the section you need, not a sequential guide.

---

## 1. Proxmox Server — Site Configuration

### 1.1 Verify All VMs Are Running

SSH into the Proxmox host or use the web UI:

```bash
# List all VMs and their status
qm list
```

Expected output shows Velociraptor, Security Onion, DFIR-IRIS, and pfSense VMs in "running" state. If any VM is stopped:

```bash
# Start a VM by its ID
qm start <VMID>
```

### 1.2 pfSense — Configure Site IP

1. Access pfSense web UI: `https://<proxmox-host-ip>:8443`
   - Default credentials: admin / pfsense (change on first use)

2. Navigate to **Interfaces → WAN**:
   - Set IPv4 Configuration Type: Static IPv4
   - IPv4 Address: `<site-assigned-IP>` / `<subnet-mask>`
   - IPv4 Upstream Gateway: `<site-gateway-IP>`
   - Save and Apply

3. Navigate to **System → General Setup**:
   - DNS Servers: `<site-DNS-1>`, `<site-DNS-2>`
   - Save

### 1.3 pfSense — Port Forwarding Rules

Navigate to **Firewall → NAT → Port Forward**. Create rules:

| Interface | Protocol | Dest Port | Redirect Target IP | Redirect Port | Description |
|-----------|----------|-----------|-------------------|---------------|-------------|
| WAN | TCP | 8000 | `<velociraptor-VM-IP>` | 8000 | Velociraptor Frontend |
| WAN | TCP | 8001 | `<velociraptor-VM-IP>` | 8001 | Velociraptor Client Comms |
| WAN | TCP | 443 | `<dfir-iris-VM-IP>` | 443 | DFIR-IRIS Web UI |

After adding rules: **Firewall → Rules → WAN** — verify corresponding allow rules were auto-created.

### 1.4 Verify Inter-VM Connectivity

From the Proxmox host console:

```bash
# Ping each VM from the host
ping -c 3 <velociraptor-VM-IP>
ping -c 3 <security-onion-VM-IP>
ping -c 3 <dfir-iris-VM-IP>
ping -c 3 <pfsense-LAN-IP>
```

From a laptop on the site network:

```bash
# Verify external access through pfSense
curl -k https://<pfsense-WAN-IP>:8000   # Velociraptor frontend
curl -k https://<pfsense-WAN-IP>:443    # DFIR-IRIS
```

---

## 2. Velociraptor Agent Deployment

### 2.0 Generate Site-Specific Client Config

This step is required for BOTH Path A and Path B. The client config tells agents where to connect.

```bash
# SSH into the Velociraptor VM
ssh user@<velociraptor-VM-IP>

# Repack the client config with the site-specific server URL
velociraptor config repack \
  --exe /opt/velociraptor/velociraptor-client.msi \
  --config /opt/velociraptor/client.config.yaml \
  --server_url https://<pfsense-WAN-IP>:8001 \
  --output /tmp/velociraptor-client-repacked.msi
```

Copy the repacked MSI to a USB drive or network share accessible from deployment targets.

### 2.1 Path A: AD/GPO Deployment

**Prerequisites:** Domain Admin credentials, network connectivity to a Domain Controller.

**Step 1: Copy MSI to a network share accessible by domain machines**

```powershell
# Create a share on a DC or file server (or use existing SYSVOL)
$SharePath = "\\<DC-hostname>\NETLOGON\Velociraptor"
New-Item -Path $SharePath -ItemType Directory -Force
Copy-Item "velociraptor-client-repacked.msi" -Destination $SharePath
```

**Step 2: Create GPO for MSI deployment**

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

### 2.2 Path B: Local/PsExec Deployment

**Prerequisites:** Local admin credentials on target machines, PsExec available, IP list of targets.

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

### 2.3 Agent Config Reference

**Changes per site (must be updated):**
- `server_url` — pfSense WAN IP and Velociraptor client comms port
- TLS certificates — if using site-specific certs

**Stays standard (do not change):**
- Collection artifacts and monitoring configuration
- Client labels and metadata settings
- Writeback file location (`C:\Program Files\Velociraptor\velociraptor.writeback.yaml`)

---

## 3. Security Onion — Traffic Ingestion Verification

### 3.1 Verify Tap Interfaces Are Receiving Traffic

```bash
# SSH into Security Onion VM
ssh user@<security-onion-VM-IP>

# Check each tap interface for packet counts
sudo tcpdump -i <tap-interface-1> -c 10 -q
sudo tcpdump -i <tap-interface-2> -c 10 -q
sudo tcpdump -i <tap-interface-3> -c 10 -q
```

Each command should show packets being captured. If no packets appear, check physical tap connections and pfSense interface assignments.

### 3.2 Verify Parsing and Normalization

```bash
# Check Zeek (network metadata) is processing
sudo so-zeek-status

# Check Suricata (IDS alerts) is running
sudo so-suricata-status

# Check recent Zeek logs
ls -lt /nsm/zeek/logs/current/
```

### 3.3 Verify Logs in SIEM View

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

---

## 4. DFIR-IRIS — Case Setup

### 4.1 Create New Case

1. Open DFIR-IRIS web UI: `https://<dfir-iris-VM-IP>`
2. Log in (default: administrator / changeme — update on first use)
3. Navigate to **Manage → Cases → Add Case**
4. Fill in:
   - Case name: `<client-name>-IR-<date>`
   - Description: Brief engagement description
   - Client: Add client if not existing
   - Classification: Select appropriate type
5. Save

### 4.2 Import Asset List

After completing asset enumeration:

1. Navigate to the case → **Assets**
2. Use **Import from CSV** or add manually
3. For each asset, enter: hostname, IP, OS, type (server/workstation/network device), description
4. Asset types map to DFIR-IRIS categories:
   - Windows workstation → "Windows - Computer"
   - Windows server → "Windows - Server"
   - Linux → "Linux - Computer"
   - Network device → "Other"

### 4.3 Triage Result Entry

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

## 5. Endpoint Baselining (Self-Sufficient Discovery)

### 5.1 Velociraptor-Based Collection

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

### 5.2 PowerShell Fallback (No Agent)

For endpoints where agents could not be deployed, use the baselining script:

See: `scripts/baseline-endpoints.ps1`

Run locally on the target or remotely via PsExec:

```powershell
.\PsExec.exe \\<target-IP> -c baseline-endpoints.ps1
```

### 5.3 Baselining Reference — Normal vs Suspicious

| Area | Normal | Investigate Further |
|------|--------|-------------------|
| Scheduled Tasks | OS defaults, known software updaters | Tasks with encoded commands, tasks running from temp/user dirs, recently created tasks |
| Services | OS services, known AV/software | Services with random names, services running from temp dirs, unsigned binaries |
| Autoruns | Known startup items, OS components | Unknown DLLs in Run keys, unsigned binaries, recently added entries |
| Network Connections | DNS, DHCP, internal services, known cloud IPs | Connections to unusual ports, high-frequency beaconing, connections to unknown external IPs |
| Local Accounts | Administrator (disabled), default accounts | Recently created admin accounts, accounts with blank descriptions, enabled Guest account |
