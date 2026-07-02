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
| **pfSense** | Routing and port forwarding between target network and IR tools | WAN (internet) / Mission (target network — port forwarding inbound) / LAN (IR tools + analyst access) |

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

pfSense has three interfaces with fixed purposes — only the Mission IP changes per site:

| Interface | Connects to | Role |
|-----------|-------------|------|
| **WAN** | Internet | Upstream internet access (updates, threat intel) |
| **Mission** | Target / client network | Inbound port forwarding for agent and sensor traffic from client endpoints |
| **LAN** | IR tools + analyst switch | Velociraptor, Security Onion, DFIR-IRIS; analyst laptops plug into the physical switch on this segment |

**Procedure:**

1. Connect analyst laptop to the physical switch on the LAN segment; access pfSense web UI
2. Configure **Mission** interface with a site-assigned IP on the client network (request fixed IP to assign)
3. Confirm **LAN** interface is on the pre-configured IR tools subnet (static — should already be set)
4. Confirm port forwarding rules on the **Mission** interface:
   - Mission IP TCP 8001 → Velociraptor server (LAN) TCP 8001 — Velociraptor agent comms
   - Mission IP TCP 8220 → Security Onion (LAN) TCP 8220 — SO Fleet Server (Elastic Agent ingestion)
   - Mission IP TCP 5044 → Security Onion (LAN) TCP 5044 — Logstash / Beats ingestion (if used)
5. Verify Mission interface can reach the client network (ping client gateway and DNS)

**Complete when:** Mission interface has a client network IP, port forwarding rules are active, and client gateway is reachable.

See: `playbooks/tool-deployment.md` Section 1 for exact commands.

### Step 3: Establish Connectivity
**Responsible:** Network Operator
**Time estimate:** 15-30 minutes

Two planes to verify — analyst access (LAN) and agent ingestion (Mission):

**LAN — analyst access (from analyst laptop on the LAN switch):**
1. Verify Velociraptor frontend is reachable: `https://<velo-lan-ip>:8000`
2. Verify DFIR-IRIS is reachable: `https://<iris-lan-ip>`
3. Verify Security Onion web UI is reachable: `https://<so-lan-ip>`

**Mission — agent ingestion (port forwarding validation):**
4. From a machine on the client network, confirm the Mission IP is reachable (ping or TCP test to port 8001. If there are other target network different from the one our mission interface IP belongs to, probably default route must be estalished.)
5. Deploy a test Velociraptor agent to one endpoint; confirm it checks in through the Mission IP

If connectivity fails:
- LAN tools unreachable → check LAN interface IP and switch cabling
- Mission port forwarding fails → check pfSense NAT rules, confirm Mission IP is correct, verify no client-side firewall blocking the port

**Complete when:** All three IR tools are reachable from the analyst switch, and at least one test agent checks in through the Mission interface.

### Step 4: Deploy Velociraptor Agents
**Responsible:** Host Operator
**Time estimate:** 30-90 minutes (depends on endpoint count and access method)

**Prerequisite — MSI repack (required before any deployment path):**

The stock Velociraptor MSI must be repacked with a client config pointing at the pfSense **Mission** IP on port 8001 — this is the address target endpoints will connect to. Done once per engagement on the Velociraptor VM.
See: `playbooks/tool-deployment.md` Section 1.1

**Deployment paths — in priority order:**

```
DEFAULT → Path A: WinRM/Invoke-Command (no extra tools required)
          Requires: admin credentials + WinRM (TCP 5985) reachable on targets
          See: playbooks/tool-deployment.md Section 1.2
          See: scripts/deploy-velo-winrm.ps1

PREFERRED FOR SCALE → Path D: Ansible (parallel, idempotent, pre-built VM on IR stack)
          Requires: admin credentials + WinRM on targets + Ansible VM running
          See: playbooks/tool-deployment.md Section 1.5
          See: ansible/deploy-velo.yml

FALLBACK → Path B: PsExec/local (if WinRM unavailable, SMB is open)
          Requires: admin credentials + SMB (TCP 445) + admin share (C$) on targets
          See: playbooks/tool-deployment.md Section 1.3
          See: scripts/deploy-velo-local.ps1

FALLBACK → Path C: AD/GPO (if domain admin available and WinRM/SMB blocked at scale)
          Requires: Domain Admin credentials + DC access + SMB on targets
          See: playbooks/tool-deployment.md Section 1.4
          See: scripts/deploy-velo-ad.ps1

LAST RESORT → USB manual install (isolated hosts with no network access)
          See: playbooks/tool-deployment.md Section 1.3, Step 3
```

**Complete when:** Agents are deployed and checking in. Verify from Velociraptor console (see Step 5).

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

| Service | Port | Protocol | Interface | Direction |
|---------|------|----------|-----------|-----------|
| Velociraptor Frontend | 8000 | TCP | LAN | Analyst laptop → Velociraptor |
| Velociraptor Agent Comms | 8001 | TCP | Mission (forwarded → LAN) | Target endpoints → Velociraptor |
| DFIR-IRIS Web UI | 443 | TCP | LAN | Analyst laptop → DFIR-IRIS |
| Security Onion Web UI | 443 | TCP | LAN | Analyst laptop → Security Onion |
| SO Fleet Server (Elastic Agent) | 8220 | TCP | Mission (forwarded → LAN) | Target endpoints → Security Onion |
| SO Logstash / Beats | 5044 | TCP | Mission (forwarded → LAN) | Target endpoints → Security Onion |
| pfSense Web UI | 8443 | TCP | LAN | Analyst laptop → pfSense (mgmt only) |
