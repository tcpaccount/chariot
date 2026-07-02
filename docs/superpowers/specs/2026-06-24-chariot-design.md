# Chariot — Incident Response Preparation Framework

## Design Spec

**Date:** 2026-06-24
**Status:** Draft

---

## 1. Overview

Chariot is a DFIR incident response preparation framework that provides Standard Operating Procedures (SOPs), technical deployment playbooks, and standardized deliverable templates for a 2-3 person team conducting threat-hunt and incident response operations.

The framework targets small enterprise environments (single site, flat or lightly segmented network, under 500 endpoints) where the team operates with minimal or no local IT cooperation — requiring self-sufficient discovery and baselining.

### DFIR Server Stack

- **Proxmox** host running:
  - **Velociraptor** — endpoint visibility and collection
  - **Security Onion** — network traffic capture and SIEM (3 tap inputs)
  - **DFIR-IRIS** — case management and triage documentation
- **pfSense** — port forwarding and network routing for agent comms and traffic ingestion
- Server is pre-built; IP configuration and agent deployment happen on-site

### Document Format

All documents are authored in Markdown (source of truth) with PDF export via `pandoc` and a `Makefile`.

---

## 2. Project Structure

```
chariot/
├── sops/
│   └── 01-network-presence-establishment.md
├── playbooks/
│   └── tool-deployment.md
├── templates/
│   ├── network-diagram.md
│   ├── asset-enumeration.md
│   └── triage-results.md
├── scripts/
│   ├── deploy-velo-ad.ps1
│   ├── deploy-velo-local.ps1
│   └── baseline-endpoints.ps1
├── export/
├── Makefile
└── README.md
```

- `sops/` — numbered SOPs, starting with network presence establishment
- `playbooks/` — technical reference guides with actual commands and queries
- `templates/` — fillable deliverable templates used during operations
- `scripts/` — PowerShell deployment and baselining scripts
- `export/` — generated PDFs
- `Makefile` — PDF generation targets via pandoc

---

## 3. SOP: Network Presence Establishment

Single monolithic SOP following the chronological flow of the operation. Phases: Recce → Initial Actions → Main Body → Baseline Confirmation.

### 3.1 Pre-Deployment (Recce)

#### Intel Requirements (answers needed before arrival)

- Network topology (if available), IP ranges, domain structure
- Number of endpoints, OS distribution
- Points of contact (even if uncooperative)
- Legal authority and authorization documentation
- Physical access requirements (server room, rack space, power)

#### Go-Bag Checklist (minimum equipment)

- Proxmox server (pre-loaded with Velociraptor, Security Onion, DFIR-IRIS)
- Network taps, cables, switch
- USB drives with deployment packages (Velociraptor agent MSI, PowerShell scripts)
- Laptop(s) with analyst tools
- Documentation kit (printed blank templates, pens)

#### Team Roles (2-3 person element)

| Role | Responsibilities |
|------|-----------------|
| **Team Lead** | Coordinates operations, handles liaison with site contacts, makes priority calls, doubles as operator in 2-person team |
| **Network Operator** | Server setup, pfSense configuration, tap placement, traffic ingestion validation |
| **Host Operator** | Agent deployment, endpoint baselining, asset enumeration |

In a 2-person team, Team Lead assumes either the Network Operator or Host Operator role based on the situation.

### 3.2 Initial Actions (First 2-4 hours on-site)

1. Physical server setup — rack, power, network connectivity
2. pfSense IP configuration for the site network
3. Establish connectivity — verify server is reachable from the network
4. Deploy Velociraptor agents (decision tree: AD/GPO path vs local/PsExec path)
5. Verify agent check-in and basic telemetry flowing
6. Security Onion — verify traffic ingestion from tap points

### 3.3 Main Body (Priority of Work)

Each task includes: objective, responsible role, procedure, and end state.

| Priority | Task | Responsible | End State |
|----------|------|-------------|-----------|
| 1 | Network Discovery & Mapping | Network Operator | Completed network diagram |
| 2 | Asset Enumeration | Host Operator | Completed asset inventory (OS, services, IPs) |
| 3 | Log Ingestion & Normalization | Network Operator | Endpoint logs flowing into Velociraptor & SIEM |
| 4 | Network Traffic Capture | Network Operator | Security Onion capturing on relevant points |
| 5 | Triage | Host Operator | Initial triage results documented in DFIR-IRIS |

### 3.4 Baseline Criteria

The network presence is considered **established** when all five conditions are met:

1. Logs ingesting and normalized into Velociraptor & SIEM tools
2. Network traffic captured and analyzable on relevant points
3. Network map generated
4. Network assets and services identified
5. Triage hunt conducted

---

## 4. Technical Deployment Playbook

Companion reference document with actual commands, queries, and step-by-step procedures. Consulted during execution, not a sequential process.

### 4.1 Proxmox Server — Site Configuration

- pfSense VM: setting site-specific WAN/LAN IPs, port forwarding rules for Velociraptor (ports 8000/8001) and Security Onion
- Verifying inter-VM connectivity (Velociraptor ↔ pfSense, Security Onion ↔ tap interfaces)
- Quick health checks for each VM on arrival

### 4.2 Velociraptor Agent Deployment — Decision Tree

Four paths based on available access level and tooling:

**Path A: WinRM/Invoke-Command**

- Native PowerShell Remoting, no GPO or PsExec required
- Deploys via `Invoke-Command` over WinRM (TCP 5985/5986)
- Rollback procedure

**Path B: Local/PsExec**

- PsExec-based remote deployment script (accepts IP list as input)
- Manual USB-based deployment for isolated/unreachable hosts
- Per-host check-in verification
- Rollback procedure

**Path C: AD/GPO**

- PowerShell commands to create GPO, link to target OU, assign MSI package
- `gpupdate /force` and verification steps
- VQL queries to verify agent check-in from Velociraptor console
- Rollback procedure (GPO removal, agent uninstall)

**Path D: Ansible (from dedicated Ansible VM on Proxmox stack)**

- Pre-configured Ubuntu VM on the IR server with Ansible, pywinrm, and playbooks pre-staged
- Uses WinRM transport (same as Path A) but wrapped in idempotent Ansible roles
- Parallel deployment across all targets from a single command
- On-site workflow: edit inventory with target IPs, run `ansible-playbook`
- Extensible to SO agent and baselining via additional roles
- Rollback via dedicated playbook

**Agent config:** What changes per site (server URL, certs) vs what stays standard (collection config, labels).

### 4.3 Security Onion — Traffic Ingestion

- Verifying tap interfaces are receiving traffic
- Basic validation that packets are being parsed
- Confirming logs appear in the SIEM view

### 4.4 DFIR-IRIS — Case Setup

- Creating the case for the engagement
- Importing asset list from enumeration
- Setting up triage result entry workflow

### 4.5 Endpoint Baselining (Self-Sufficient Discovery)

- Velociraptor-based collection: installed software, running services, scheduled tasks, local accounts, network connections, autoruns
- PowerShell fallback script for hosts without agents
- What "normal" looks like vs what to flag for triage

---

## 5. Deliverable Templates

### 5.1 Network Diagram Template

Markdown table format with sections for:

- Network segments/VLANs: IP range, subnet mask, gateway, purpose
- Key infrastructure: DNS, DHCP, domain controllers, file servers
- Gateways and routing: connections between segments
- Tap placement points: interface, location, what traffic is captured
- Each entry: IP/range, function, physical location (if known), notes
- Filled during Main Body Task 1 (Network Discovery & Mapping)

### 5.2 Asset Enumeration Template

Table format with columns:

| Hostname | IP | MAC | OS/Version | Domain-Joined | Services/Roles | Agent Deployed | Notes |
|----------|-----|-----|-----------|---------------|----------------|----------------|-------|

- Pre-populated column headers, ready for copy-paste from Velociraptor collection
- Summary section at top: total endpoints, OS distribution breakdown, coverage percentage (agents deployed vs total)
- Filled during Main Body Task 2 (Asset Enumeration)

### 5.3 Triage Results Template (DFIR-IRIS compatible)

Structured to match DFIR-IRIS case/evidence format:

| Asset | Finding Category | Severity | Raw Evidence Ref | Analyst Notes | Status |
|-------|-----------------|----------|------------------|---------------|--------|

- Finding categories: persistence, lateral movement, exfiltration, anomalous service, other
- Severity: critical, high, medium, low, informational
- Status: open, investigated, resolved
- Summary section: total findings by severity, top-priority items
- Filled during Main Body Task 5 (Triage)

---

## 6. Scripts

### 6.1 deploy-velo-ad.ps1

PowerShell script for Velociraptor agent deployment via Active Directory GPO. Accepts site-specific parameters (server IP, config path, target OU). Creates GPO, assigns MSI, forces group policy update, and verifies agent check-in.

### 6.2 deploy-velo-local.ps1

PowerShell script for Velociraptor agent deployment via PsExec to a list of target IPs. Accepts site-specific parameters (server IP, config path, IP list file). Deploys agent, starts service, verifies check-in per host.

### 6.3 baseline-endpoints.ps1

PowerShell script for endpoint baselining on hosts without Velociraptor agents. Collects: installed software, running services, scheduled tasks, local accounts, network connections, autoruns. Outputs structured data for import into asset enumeration template.

---

## 7. PDF Export

- `Makefile` with targets for each document and an `all` target
- Uses `pandoc` with a clean, professional template
- Output directory: `export/`
- Commands: `make sops`, `make playbooks`, `make templates`, `make all`

---

## 8. Out of Scope

- Specific triage hunt queries and procedures (handled on-site)
- Security Onion tap placement decisions (handled on-site)
- Multi-site or large enterprise scenarios (future project)
- Incident remediation procedures (separate SOP)
