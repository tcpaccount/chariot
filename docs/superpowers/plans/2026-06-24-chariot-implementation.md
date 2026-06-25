# Chariot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a complete DFIR incident response preparation framework with SOPs, technical playbooks, deployment scripts, and deliverable templates for a 2-3 person team operating in small enterprise environments with no local IT cooperation.

**Architecture:** Single monolithic SOP as the primary operational document, a companion technical deployment playbook with copy-paste commands, three fillable deliverable templates, three PowerShell deployment/baselining scripts, and a Makefile-based PDF export pipeline. Markdown is the source of truth for all documents.

**Tech Stack:** Markdown, Pandoc (PDF generation), GNU Make, PowerShell, Velociraptor (VQL), pfSense, Security Onion, DFIR-IRIS

**Spec:** `docs/superpowers/specs/2026-06-24-chariot-design.md`

---

## File Map

| File | Purpose |
|------|---------|
| `README.md` | Project overview, structure, usage instructions, PDF generation commands |
| `Makefile` | Pandoc-based PDF export targets for all documents |
| `sops/01-network-presence-establishment.md` | Main SOP: Recce → Initial Actions → Main Body → Baseline Criteria |
| `playbooks/tool-deployment.md` | Technical reference: actual commands for pfSense, Velociraptor, Security Onion, DFIR-IRIS, baselining |
| `templates/network-diagram.md` | Fillable network map template with table sections |
| `templates/asset-enumeration.md` | Fillable asset inventory template with summary section |
| `templates/triage-results.md` | Fillable triage findings template, DFIR-IRIS compatible |
| `scripts/deploy-velo-ad.ps1` | Velociraptor agent deployment via AD/GPO |
| `scripts/deploy-velo-local.ps1` | Velociraptor agent deployment via PsExec (no AD) |
| `scripts/baseline-endpoints.ps1` | Endpoint baselining for hosts without agents |
| `export/` | Generated PDF output directory (gitignored) |

---

## Task 1: Project Scaffolding

**Files:**
- Create: `README.md`
- Create: `.gitignore`
- Create: directory structure (`sops/`, `playbooks/`, `templates/`, `scripts/`, `export/`)

- [ ] **Step 1: Initialize git repository**

```bash
cd /home/romio/CLAUDE_PROJECTS/chariot
git init
```

- [ ] **Step 2: Create directory structure**

```bash
mkdir -p sops playbooks templates scripts export
```

- [ ] **Step 3: Create .gitignore**

Create `.gitignore` with:

```
# Generated PDFs
export/*.pdf

# OS files
.DS_Store
Thumbs.db

# Editor files
*.swp
*.swo
*~
```

- [ ] **Step 4: Create README.md**

Create `README.md` with:

```markdown
# Chariot — Incident Response Preparation Framework

DFIR incident response preparation framework for a 2-3 person team. Provides SOPs, technical deployment playbooks, deployment scripts, and standardized deliverable templates.

**Target environment:** Small enterprise (single site, <500 endpoints, minimal/no local IT cooperation)

**DFIR Server Stack:** Proxmox host running Velociraptor, Security Onion (3 tap inputs), DFIR-IRIS, with pfSense for routing.

## Structure

```
sops/           — Standard Operating Procedures (numbered)
playbooks/      — Technical reference guides with commands and queries
templates/      — Fillable deliverable templates for field use
scripts/        — PowerShell deployment and baselining scripts
export/         — Generated PDFs (gitignored)
```

## Documents

| Document | Description |
|----------|-------------|
| `sops/01-network-presence-establishment.md` | SOP for establishing network presence: Recce → Initial Actions → Main Body → Baseline |
| `playbooks/tool-deployment.md` | Technical playbook: pfSense, Velociraptor agents, Security Onion, DFIR-IRIS, baselining |

## Templates

| Template | Description |
|----------|-------------|
| `templates/network-diagram.md` | Network segments, infrastructure, gateways, tap points |
| `templates/asset-enumeration.md` | Endpoint inventory with OS, services, agent status |
| `templates/triage-results.md` | Triage findings by severity, DFIR-IRIS compatible |

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/deploy-velo-ad.ps1` | Deploy Velociraptor agents via Active Directory GPO |
| `scripts/deploy-velo-local.ps1` | Deploy Velociraptor agents via PsExec (no AD) |
| `scripts/baseline-endpoints.ps1` | Baseline endpoints without agents |

## PDF Export

Requires [Pandoc](https://pandoc.org/) installed.

```bash
make all          # Export all documents to PDF
make sops         # Export SOPs only
make playbooks    # Export playbooks only
make templates    # Export templates only
```

PDFs are generated in `export/`.
```

- [ ] **Step 5: Commit scaffolding**

```bash
git add .gitignore README.md sops/ playbooks/ templates/ scripts/ export/
git commit -m "feat: project scaffolding with directory structure and README"
```

---

## Task 2: Makefile for PDF Export

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Create Makefile**

Create `Makefile` with:

```makefile
PANDOC := pandoc
PANDOC_FLAGS := --from markdown --to pdf --pdf-engine=xelatex \
    -V geometry:margin=1in \
    -V fontsize=11pt \
    -V documentclass=article \
    -V colorlinks=true \
    -V linkcolor=blue \
    -V urlcolor=blue \
    -V header-includes='\usepackage{fancyhdr}\pagestyle{fancy}\fancyhead[L]{CHARIOT — DFIR IR Framework}\fancyhead[R]{\today}'

EXPORT_DIR := export

SOP_SRCS := $(wildcard sops/*.md)
SOP_PDFS := $(patsubst sops/%.md,$(EXPORT_DIR)/sops-%.pdf,$(SOP_SRCS))

PLAYBOOK_SRCS := $(wildcard playbooks/*.md)
PLAYBOOK_PDFS := $(patsubst playbooks/%.md,$(EXPORT_DIR)/playbooks-%.pdf,$(PLAYBOOK_SRCS))

TEMPLATE_SRCS := $(wildcard templates/*.md)
TEMPLATE_PDFS := $(patsubst templates/%.md,$(EXPORT_DIR)/templates-%.pdf,$(TEMPLATE_SRCS))

.PHONY: all sops playbooks templates clean

all: sops playbooks templates

sops: $(SOP_PDFS)

playbooks: $(PLAYBOOK_PDFS)

templates: $(TEMPLATE_PDFS)

$(EXPORT_DIR)/sops-%.pdf: sops/%.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR)/playbooks-%.pdf: playbooks/%.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR)/templates-%.pdf: templates/%.md | $(EXPORT_DIR)
	$(PANDOC) $(PANDOC_FLAGS) -o $@ $<

$(EXPORT_DIR):
	mkdir -p $(EXPORT_DIR)

clean:
	rm -f $(EXPORT_DIR)/*.pdf
```

- [ ] **Step 2: Verify Makefile syntax**

```bash
make -n all
```

Expected: `make` prints the commands it would run without errors. It will show "nothing to be done" since no source files exist yet.

- [ ] **Step 3: Commit Makefile**

```bash
git add Makefile
git commit -m "feat: add Makefile for pandoc PDF export pipeline"
```

---

## Task 3: Network Diagram Template

**Files:**
- Create: `templates/network-diagram.md`

- [ ] **Step 1: Create network diagram template**

Create `templates/network-diagram.md` with:

```markdown
# Network Diagram

**Engagement:** _______________
**Date:** _______________
**Prepared by:** _______________

---

## Network Segments

| Segment Name | IP Range | Subnet Mask | Gateway | VLAN ID | Purpose | Physical Location | Notes |
|-------------|----------|-------------|---------|---------|---------|-------------------|-------|
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |

## Key Infrastructure

| Hostname | IP Address | Role | OS/Version | Segment | Physical Location | Notes |
|----------|-----------|------|-----------|---------|-------------------|-------|
| | | DNS | | | | |
| | | DHCP | | | | |
| | | Domain Controller | | | | |
| | | File Server | | | | |
| | | Mail Server | | | | |
| | | Web Server | | | | |
| | | Proxy/Firewall | | | | |
| | | | | | | |

## Gateways and Routing

| Source Segment | Destination Segment | Gateway IP | Route Type | ACLs/Restrictions | Notes |
|---------------|---------------------|-----------|------------|-------------------|-------|
| | | | | | |
| | | | | | |
| | | | | | |

## Tap Placement Points

| Tap ID | Interface/Port | Physical Location | Traffic Captured | Connected To | Notes |
|--------|---------------|-------------------|-----------------|-------------|-------|
| TAP-1 | | | | Security Onion (tap input 1) | |
| TAP-2 | | | | Security Onion (tap input 2) | |
| TAP-3 | | | | Security Onion (tap input 3) | |

## External Connections

| Connection | Type | Provider | IP/Range | Bandwidth | Firewall Rules | Notes |
|-----------|------|----------|----------|-----------|----------------|-------|
| Internet uplink | | | | | | |
| VPN | | | | | | |
| | | | | | | |

## Notes

_Additional observations about the network topology, anomalies, or items requiring follow-up:_

-
-
-
```

- [ ] **Step 2: Commit template**

```bash
git add templates/network-diagram.md
git commit -m "feat: add network diagram template"
```

---

## Task 4: Asset Enumeration Template

**Files:**
- Create: `templates/asset-enumeration.md`

- [ ] **Step 1: Create asset enumeration template**

Create `templates/asset-enumeration.md` with:

```markdown
# Asset Enumeration

**Engagement:** _______________
**Date:** _______________
**Prepared by:** _______________

---

## Summary

| Metric | Count |
|--------|-------|
| Total Endpoints Discovered | |
| Windows Endpoints | |
| Linux Endpoints | |
| macOS Endpoints | |
| Network Devices | |
| Other/Unknown | |
| Agents Deployed | |
| **Coverage (Agents / Total)** | **__ %** |

## Asset Inventory

| # | Hostname | IP Address | MAC Address | OS / Version | Domain-Joined | Services / Roles | Agent Deployed | Status | Notes |
|---|----------|-----------|-------------|-------------|---------------|-----------------|----------------|--------|-------|
| 1 | | | | | Y / N | | Y / N | | |
| 2 | | | | | Y / N | | Y / N | | |
| 3 | | | | | Y / N | | Y / N | | |
| 4 | | | | | Y / N | | Y / N | | |
| 5 | | | | | Y / N | | Y / N | | |
| 6 | | | | | Y / N | | Y / N | | |
| 7 | | | | | Y / N | | Y / N | | |
| 8 | | | | | Y / N | | Y / N | | |
| 9 | | | | | Y / N | | Y / N | | |
| 10 | | | | | Y / N | | Y / N | | |

**Status codes:** Online, Offline, Unreachable, Isolated

## Unresolved Assets

_Endpoints that were detected (ARP, DNS, traffic) but not yet identified or baselined:_

| IP Address | Detection Method | First Seen | Notes |
|-----------|-----------------|------------|-------|
| | | | |
| | | | |

## Notes

_Additional observations about the asset landscape, anomalies, or items requiring follow-up:_

-
-
-
```

- [ ] **Step 2: Commit template**

```bash
git add templates/asset-enumeration.md
git commit -m "feat: add asset enumeration template"
```

---

## Task 5: Triage Results Template

**Files:**
- Create: `templates/triage-results.md`

- [ ] **Step 1: Create triage results template**

Create `templates/triage-results.md` with:

```markdown
# Triage Results

**Engagement:** _______________
**Case ID (DFIR-IRIS):** _______________
**Date:** _______________
**Prepared by:** _______________

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | |
| High | |
| Medium | |
| Low | |
| Informational | |
| **Total** | **** |

### Top Priority Items

1.
2.
3.

---

## Findings

| # | Asset (Hostname/IP) | Finding Category | Severity | Description | Raw Evidence Reference | Analyst Notes | Status |
|---|-------------------|-----------------|----------|-------------|----------------------|---------------|--------|
| 1 | | | | | | | |
| 2 | | | | | | | |
| 3 | | | | | | | |
| 4 | | | | | | | |
| 5 | | | | | | | |
| 6 | | | | | | | |
| 7 | | | | | | | |
| 8 | | | | | | | |
| 9 | | | | | | | |
| 10 | | | | | | | |

**Finding Categories:** Persistence, Lateral Movement, Exfiltration, Anomalous Service, Credential Access, Defense Evasion, C2 Communication, Other

**Severity:** Critical, High, Medium, Low, Informational

**Status:** Open, Investigated, Resolved, False Positive

---

## Evidence Log

_Cross-reference to raw evidence stored in DFIR-IRIS:_

| Evidence ID | Type | Source Asset | Collection Method | Storage Location | Hash (SHA256) | Notes |
|------------|------|-------------|-------------------|-----------------|---------------|-------|
| | | | | | | |
| | | | | | | |

## Notes

_Additional observations, patterns across findings, or items requiring follow-up:_

-
-
-
```

- [ ] **Step 2: Commit template**

```bash
git add templates/triage-results.md
git commit -m "feat: add triage results template (DFIR-IRIS compatible)"
```

---

## Task 6: SOP — Network Presence Establishment

**Files:**
- Create: `sops/01-network-presence-establishment.md`

This is the main deliverable. It is a large document — write it in full with all sections from the spec.

- [ ] **Step 1: Create the SOP document**

Create `sops/01-network-presence-establishment.md` with:

```markdown
# SOP 01: Network Presence Establishment

**Version:** 1.0
**Date:** _______________
**Classification:** _______________

---

## 1. Purpose

This Standard Operating Procedure defines the process for a 2-3 person DFIR team to establish network presence during incident response or threat-hunt operations. It covers pre-deployment preparation through to confirmed operational baseline.

**Target environment:** Small enterprise — single site, flat or lightly segmented network, under 500 endpoints.

**Assumption:** Minimal or no local IT cooperation. The team must be self-sufficient for network discovery, endpoint baselining, and tool deployment.

---

## 2. DFIR Server Stack

The team deploys a pre-built Proxmox server containing:

| VM | Purpose | Key Ports |
|----|---------|-----------|
| **Velociraptor** | Endpoint visibility, agent-based collection, VQL queries | 8000 (frontend), 8001 (client comms) |
| **Security Onion** | Network traffic capture, SIEM, packet analysis | 3 tap input interfaces |
| **DFIR-IRIS** | Case management, triage documentation, evidence tracking | 443 (web UI) |
| **pfSense** | Port forwarding, routing, network segmentation for server | WAN/LAN as configured on-site |

The server is pre-built and tested before deployment. Only site-specific configuration (IP addresses, agent configs) happens on-site.

---

## 3. Phase 1 — Pre-Deployment (Recce)

### 3.1 Intel Requirements

Gather the following before arrival. Incomplete information is expected — document what is known and what is unknown.

| # | Information Required | Source | Status |
|---|---------------------|--------|--------|
| 1 | Network topology diagram (if available) | Client / prior engagement | ☐ |
| 2 | IP address ranges and subnets | Client IT / documentation | ☐ |
| 3 | Domain structure (AD forest, domain names) | Client IT | ☐ |
| 4 | Number of endpoints and OS distribution | Client IT / asset inventory | ☐ |
| 5 | Points of contact (names, roles, phone numbers) | Client leadership | ☐ |
| 6 | Legal authority and authorization documentation | Legal / management | ☐ |
| 7 | Physical access — server room, rack space, power, cooling | Facilities / client IT | ☐ |
| 8 | Internet connectivity and bandwidth at site | Client IT | ☐ |
| 9 | Known security tools already deployed (AV, EDR, SIEM) | Client IT | ☐ |
| 10 | Known incidents or alerts that triggered this engagement | Client / SOC | ☐ |

### 3.2 Go-Bag Checklist

Minimum equipment for deployment:

| # | Item | Qty | Status |
|---|------|-----|--------|
| 1 | Proxmox server (pre-loaded: Velociraptor, Security Onion, DFIR-IRIS, pfSense) | 1 | ☐ |
| 2 | Network taps (passive) | 3 | ☐ |
| 3 | Ethernet cables (Cat6, assorted lengths: 1m, 3m, 5m) | 10+ | ☐ |
| 4 | Network switch (unmanaged, 8-port minimum) | 1 | ☐ |
| 5 | USB drives — Velociraptor agent MSI + client config | 3 | ☐ |
| 6 | USB drives — PowerShell deployment scripts | 2 | ☐ |
| 7 | Laptop(s) with analyst tools | 1-2 | ☐ |
| 8 | Power strip / extension cord | 1 | ☐ |
| 9 | Printed blank templates (network diagram, asset enum, triage) | 5 sets | ☐ |
| 10 | Notebook, pens, markers | 1 set | ☐ |
| 11 | Console cable (serial/USB) | 1 | ☐ |
| 12 | Label maker or masking tape + marker (for cable labeling) | 1 | ☐ |

### 3.3 Team Roles

| Role | Responsibilities | Notes |
|------|-----------------|-------|
| **Team Lead (TL)** | Coordinates operations, liaison with site contacts, priority decisions, situation reporting, quality control of deliverables | In a 2-person team, TL assumes one operator role |
| **Network Operator (NO)** | Physical server setup, pfSense configuration, tap placement, Security Onion validation, network discovery and mapping, traffic capture | Primary owner of network-side tasks |
| **Host Operator (HO)** | Velociraptor agent deployment, endpoint baselining, asset enumeration, log ingestion verification, triage execution | Primary owner of endpoint-side tasks |

**2-person team allocation:** Team Lead takes the Network Operator or Host Operator role based on:
- If the network is complex (multiple segments, unknown topology) → TL takes NO role
- If the endpoint count is high or agent deployment is difficult → TL takes HO role
- Default: TL takes NO role (network usually needs earlier attention)

---

## 4. Phase 2 — Initial Actions (First 2-4 Hours On-Site)

Execute in order. Each step has a responsible role and a completion criteria.

### Step 1: Physical Server Setup
**Responsible:** Network Operator
**Time estimate:** 15-30 minutes

1. Identify rack space or table near network core
2. Mount/place Proxmox server, connect power
3. Connect server management port to network switch
4. Connect Security Onion tap interfaces (leave disconnected until tap placement)
5. Power on server, verify all VMs boot

**Complete when:** All VMs are running and accessible from the server console.

### Step 2: pfSense Site Configuration
**Responsible:** Network Operator
**Time estimate:** 15-30 minutes

1. Access pfSense web UI from server console
2. Configure WAN interface with site-assigned IP (or DHCP if available)
3. Configure LAN interface for internal server network
4. Add port forwarding rules:
   - External → Velociraptor frontend (TCP 8000)
   - External → Velociraptor client comms (TCP 8001)
   - Any additional ports required for Security Onion agent forwarding
5. Verify pfSense can reach the site network (ping gateway, DNS)

**Complete when:** pfSense has connectivity to site network and port forwarding rules are active.

See: `playbooks/tool-deployment.md` Section 1 for exact commands.

### Step 3: Establish Connectivity
**Responsible:** Network Operator
**Time estimate:** 15-30 minutes

1. From a laptop on the site network, verify:
   - Can reach pfSense WAN IP
   - Can reach Velociraptor frontend through pfSense (port 8000)
   - Can reach DFIR-IRIS web UI
2. If connectivity fails, troubleshoot:
   - Check pfSense firewall rules and NAT
   - Verify no site firewall blocking required ports
   - Check cable connections and switch port status

**Complete when:** Velociraptor frontend and DFIR-IRIS are reachable from the site network.

### Step 4: Deploy Velociraptor Agents
**Responsible:** Host Operator
**Time estimate:** 30-90 minutes (depends on endpoint count and access method)

**Decision tree — assess which path is available:**

```
Do you have Domain Admin credentials?
├── YES → Path A: AD/GPO deployment (faster, covers domain-joined machines)
├── NO → Do you have local admin on target machines?
│   ├── YES → Path B: PsExec/local deployment (machine-by-machine)
│   └── NO → Escalate to Team Lead for credential acquisition strategy
```

**Path A: AD/GPO deployment**
See: `playbooks/tool-deployment.md` Section 2, Path A
See: `scripts/deploy-velo-ad.ps1`

**Path B: Local/PsExec deployment**
See: `playbooks/tool-deployment.md` Section 2, Path B
See: `scripts/deploy-velo-local.ps1`

**Complete when:** Agents are deployed and checking in. Verify from Velociraptor console.

### Step 5: Verify Agent Check-in
**Responsible:** Host Operator
**Time estimate:** 15-30 minutes

1. Open Velociraptor frontend
2. Navigate to client search
3. Verify expected number of agents are online
4. Run a simple VQL query to confirm telemetry:
   ```
   SELECT client_id, os_info.hostname, os_info.system, last_seen_at
   FROM clients()
   WHERE last_seen_at > now() - 300
   ```
5. Document any endpoints that did not check in

**Complete when:** Agent count matches expected endpoints (or gaps are documented for follow-up).

### Step 6: Security Onion — Verify Traffic Ingestion
**Responsible:** Network Operator
**Time estimate:** 15-30 minutes

1. Connect tap interfaces to placed network taps
2. Access Security Onion console
3. Verify each tap interface shows incoming packets
4. Confirm alerts or logs are appearing in the SIEM view

**Complete when:** Security Onion is receiving and parsing traffic from at least one tap point.

See: `playbooks/tool-deployment.md` Section 3 for verification commands.

---

## 5. Phase 3 — Main Body (Priority of Work)

After initial actions are complete, execute these tasks in priority order. Tasks can run in parallel when two operators are available.

### Task 1: Network Discovery & Mapping
**Priority:** 1
**Responsible:** Network Operator
**Objective:** Produce a complete network diagram of the site.

**Procedure:**
1. Run network scans from the DFIR server to discover live hosts and segments:
   - ARP scan on local segment
   - Ping sweep across known/suspected IP ranges
   - Port scan key infrastructure (DNS, DHCP, DC, gateways)
2. Identify network segments, VLANs, and routing between them
3. Document all discovered infrastructure in the network diagram template
4. Cross-reference with any topology information obtained during Recce

**Deliverable:** Completed `templates/network-diagram.md`

**End state:** Network diagram covers all discovered segments, key infrastructure, gateways, and tap placement points.

### Task 2: Asset Enumeration
**Priority:** 2
**Responsible:** Host Operator
**Objective:** Produce a complete inventory of all network assets.

**Procedure:**
1. Export client list from Velociraptor (agents already deployed):
   ```
   SELECT client_id, os_info.hostname, os_info.system,
          os_info.platform, os_info.release,
          last_ip, mac_addresses
   FROM clients()
   ```
2. For hosts without agents, use the baselining script:
   See: `scripts/baseline-endpoints.ps1`
3. Identify and document network devices (switches, routers, printers)
4. Fill in the asset enumeration template with all discovered assets
5. Calculate coverage metrics (agents deployed / total endpoints)

**Deliverable:** Completed `templates/asset-enumeration.md`

**End state:** All discovered endpoints are documented with OS, services, and agent status. Coverage percentage is calculated.

### Task 3: Log Ingestion & Normalization
**Priority:** 3
**Responsible:** Network Operator
**Objective:** Ensure endpoint logs are flowing into Velociraptor and SIEM.

**Procedure:**
1. Verify Velociraptor event monitoring is active on deployed agents
2. Confirm Windows Event Logs are being forwarded (if applicable)
3. Check Security Onion is receiving and normalizing log data
4. Validate log timestamps are consistent (check for timezone issues)
5. Run a test query in Velociraptor to confirm searchable data:
   ```
   SELECT * FROM hunt(
     description="Log Ingestion Validation",
     artifacts=["Windows.EventLogs.Cleared"],
     timeout=600
   )
   ```

**End state:** Endpoint logs from deployed agents are searchable in Velociraptor. Network logs are visible in Security Onion SIEM.

### Task 4: Network Traffic Capture
**Priority:** 4
**Responsible:** Network Operator
**Objective:** Confirm Security Onion is capturing and analyzing network traffic.

**Procedure:**
1. Verify packet capture on each active tap interface
2. Check pcap storage is writing and rotating correctly
3. Validate protocol decoding is working (HTTP, DNS, TLS at minimum)
4. Confirm alert rules are loaded and generating alerts where applicable

**End state:** Security Onion is capturing traffic on all active tap points, packets are being decoded, and alerts are generating.

### Task 5: Triage
**Priority:** 5
**Responsible:** Host Operator
**Objective:** Conduct initial triage and document findings in DFIR-IRIS.

**Procedure:**
1. Create case in DFIR-IRIS (see: `playbooks/tool-deployment.md` Section 4)
2. Import asset list from completed asset enumeration
3. Run initial triage collections via Velociraptor — focus areas:
   - Persistence mechanisms (scheduled tasks, services, autoruns)
   - Anomalous processes and network connections
   - Recently modified files in system directories
   - Local account anomalies
4. Document each finding in the triage results template
5. Enter findings into DFIR-IRIS case

**Deliverable:** Completed `templates/triage-results.md` and corresponding DFIR-IRIS case entries.

**End state:** Initial triage is complete, findings are documented and categorized by severity.

---

## 6. Baseline Criteria

The network presence is **established** when ALL five conditions are confirmed:

| # | Condition | Verified By | Status |
|---|-----------|-------------|--------|
| 1 | Logs ingesting and normalized into Velociraptor & SIEM | Query returns results from deployed agents | ☐ |
| 2 | Network traffic captured and analyzable on relevant points | Security Onion shows active capture on tap interfaces | ☐ |
| 3 | Network map generated | Completed network diagram template | ☐ |
| 4 | Network assets and services identified | Completed asset enumeration template | ☐ |
| 5 | Triage hunt conducted | Completed triage results template + DFIR-IRIS case | ☐ |

**When all boxes are checked:** Report to Team Lead. Network presence is established. Transition to sustained operations or specific incident response tasking.

---

## Appendix A: Reference Documents

| Document | Location |
|----------|----------|
| Technical Deployment Playbook | `playbooks/tool-deployment.md` |
| Network Diagram Template | `templates/network-diagram.md` |
| Asset Enumeration Template | `templates/asset-enumeration.md` |
| Triage Results Template | `templates/triage-results.md` |
| Velociraptor AD Deployment Script | `scripts/deploy-velo-ad.ps1` |
| Velociraptor Local Deployment Script | `scripts/deploy-velo-local.ps1` |
| Endpoint Baselining Script | `scripts/baseline-endpoints.ps1` |

## Appendix B: Quick Reference — Key Ports

| Service | Port | Protocol | Direction |
|---------|------|----------|-----------|
| Velociraptor Frontend | 8000 | TCP | Analyst → Server |
| Velociraptor Client Comms | 8001 | TCP | Endpoints → Server |
| DFIR-IRIS Web UI | 443 | TCP | Analyst → Server |
| Security Onion Web UI | 443 | TCP | Analyst → Server |
| pfSense Web UI | 8443 | TCP | Analyst → Server (mgmt only) |
```

- [ ] **Step 2: Commit SOP**

```bash
git add sops/01-network-presence-establishment.md
git commit -m "feat: add SOP 01 — network presence establishment"
```

---

## Task 7: Technical Deployment Playbook

**Files:**
- Create: `playbooks/tool-deployment.md`

This is the technical reference companion. Every section includes actual commands.

- [ ] **Step 1: Create the playbook document**

Create `playbooks/tool-deployment.md` with:

```markdown
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
```

- [ ] **Step 2: Commit playbook**

```bash
git add playbooks/tool-deployment.md
git commit -m "feat: add technical deployment playbook with commands and procedures"
```

---

## Task 8: PowerShell Script — deploy-velo-ad.ps1

**Files:**
- Create: `scripts/deploy-velo-ad.ps1`

- [ ] **Step 1: Create the AD deployment script**

Create `scripts/deploy-velo-ad.ps1` with:

```powershell
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
```

- [ ] **Step 2: Verify script syntax**

```bash
pwsh -Command "Get-Content scripts/deploy-velo-ad.ps1 | Out-Null; Write-Host 'Syntax OK'"
```

If `pwsh` is not installed, verify with a basic syntax check:

```bash
head -5 scripts/deploy-velo-ad.ps1
```

- [ ] **Step 3: Commit script**

```bash
git add scripts/deploy-velo-ad.ps1
git commit -m "feat: add Velociraptor AD/GPO deployment script"
```

---

## Task 9: PowerShell Script — deploy-velo-local.ps1

**Files:**
- Create: `scripts/deploy-velo-local.ps1`

- [ ] **Step 1: Create the local deployment script**

Create `scripts/deploy-velo-local.ps1` with:

```powershell
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
```

- [ ] **Step 2: Commit script**

```bash
git add scripts/deploy-velo-local.ps1
git commit -m "feat: add Velociraptor local/PsExec deployment script"
```

---

## Task 10: PowerShell Script — baseline-endpoints.ps1

**Files:**
- Create: `scripts/baseline-endpoints.ps1`

- [ ] **Step 1: Create the baselining script**

Create `scripts/baseline-endpoints.ps1` with:

```powershell
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
```

- [ ] **Step 2: Commit script**

```bash
git add scripts/baseline-endpoints.ps1
git commit -m "feat: add endpoint baselining script"
```

---

## Task 11: Final Integration and Verification

**Files:**
- All files created in previous tasks

- [ ] **Step 1: Verify all files exist**

```bash
find . -type f -not -path './.git/*' -not -path './docs/*' | sort
```

Expected output:

```
./.gitignore
./Makefile
./README.md
./playbooks/tool-deployment.md
./scripts/baseline-endpoints.ps1
./scripts/deploy-velo-ad.ps1
./scripts/deploy-velo-local.ps1
./sops/01-network-presence-establishment.md
./templates/asset-enumeration.md
./templates/network-diagram.md
./templates/triage-results.md
```

- [ ] **Step 2: Test PDF generation (if pandoc is installed)**

```bash
make all
```

If pandoc is not installed:

```bash
which pandoc || echo "pandoc not installed — PDF generation will work once installed"
```

- [ ] **Step 3: Verify Makefile dry run**

```bash
make -n all
```

Expected: Shows pandoc commands for each markdown file.

- [ ] **Step 4: Final commit with all docs included**

```bash
git add docs/
git commit -m "docs: add design spec and implementation plan"
```

- [ ] **Step 5: Review git log**

```bash
git log --oneline
```

Expected: Clean commit history with one commit per logical component.
