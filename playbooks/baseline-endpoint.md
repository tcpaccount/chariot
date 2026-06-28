# Endpoint Baselining Playbook

**Version:** 1.0
**Companion to:** SOP 01 — Network Presence Establishment

This playbook covers quick network discovery and endpoint baselining techniques for IR engagements. Start with nmap for rapid network-level visibility, then use Velociraptor VQL for agent-level asset reconciliation.

---

## 1. Network Discovery with nmap

Lightweight scans to discover live hosts without heavy port scanning. These are safe to run early in an engagement to build an initial asset map.

### 1.1 Ping Sweep (ICMP — Fastest)

Discovers live hosts via ICMP echo. No port scanning.

```bash
# Single subnet
nmap -sn 10.0.20.0/24

# Multiple subnets
nmap -sn 10.0.0.0/24 10.0.10.0/24 10.0.20.0/24 10.0.30.0/24

# Entire /16
nmap -sn 10.0.0.0/16

# Output to file for later use
nmap -sn 10.0.0.0/16 -oG ping-sweep.gnmap
```

`-sn` = ping scan only, no port scan. Fast and non-intrusive.

### 1.2 ARP Discovery (Local Subnet Only — Most Reliable)

ARP-based discovery works even when ICMP is blocked by host firewalls. Only works on the local broadcast domain.

```bash
# ARP scan on the local subnet
nmap -sn -PR 10.0.20.0/24

# ARP scan with MAC vendor identification
nmap -sn -PR 10.0.20.0/24 -oX arp-scan.xml
```

`-PR` = ARP ping. Cannot be firewalled on the local segment.

### 1.3 TCP SYN Ping (When ICMP Is Blocked)

If ICMP is disabled on endpoints, use a TCP SYN to common ports to detect live hosts without a full port scan.

```bash
# SYN ping to common ports — no port scan
nmap -sn -PS22,80,135,443,445,3389 10.0.20.0/24

# Combine TCP and UDP ping for maximum coverage
nmap -sn -PS22,80,135,443,445,3389 -PU53,137,161 10.0.0.0/16
```

`-PS` = TCP SYN ping, `-PU` = UDP ping. Still no port scan — just host discovery.

### 1.4 List Scan (DNS Resolution Only — Zero Traffic)

Resolves hostnames via DNS without sending any packets to targets. Useful for building an inventory from DNS records.

```bash
nmap -sL 10.0.20.0/24
```

`-sL` = list scan. Zero packets sent to targets — DNS only.

### 1.5 Quick Reference

| Method | Flag | Works when ICMP blocked | Local subnet only | Speed |
|--------|------|------------------------|--------------------|-------|
| Ping sweep | `-sn` | No | No | Fastest |
| ARP discovery | `-sn -PR` | Yes | Yes | Fast |
| TCP SYN ping | `-sn -PS<ports>` | Yes | No | Medium |
| DNS list scan | `-sL` | N/A (no packets) | No | Instant |

### 1.6 Export and Parse Results

```bash
# Export all live hosts to a simple IP list (for use as targets.txt)
nmap -sn 10.0.0.0/16 -oG - | grep "Up" | awk '{print $2}' > discovered-hosts.txt

# Count discovered hosts
wc -l discovered-hosts.txt
```

This `discovered-hosts.txt` can feed directly into the Velociraptor or SO agent deployment scripts as `targets.txt`.

---

## 2. Velociraptor VQL — Endpoint Baseline and Reconciliation

![Network IP Discovery Map](playbooks/images/baseline.png)

After deploying Velociraptor agents, use these VQL notebooks to reconcile discovered assets against known asset lists. The Venn diagram above illustrates the three data sources and their overlaps — the VQL queries below operationalize each region of this map. This identifies rogue devices, missing agents, and network anomalies.

### 2.1 Prerequisites

Run these two hunts from the Velociraptor frontend **before** using the notebook below:

1. **Hunt → New Hunt → `Windows.Network.ArpCache`** — collects ARP tables from all endpoints
2. **Hunt → New Hunt → `Generic.Network.InterfaceAddresses`** — collects IP/interface info from all endpoints

Note the hunt ID (e.g., `H.XXXXXXXXX`) — you'll need it in the VQL below.

### 2.2 Known Asset List

Populate this list with the IPs from the client's asset inventory. This is the "expected" state — the VQL will compare it against what agents and ARP tables actually report.

```sql
LET known_IPS = (
-- EXAMPLE: Populate with client's known asset IPs per department/zone
-- MANAGEMENT
"10.0.20.11", "10.0.20.12", "10.0.20.13",
-- SERVERS
"10.0.0.10", "10.0.0.12", "10.0.0.14",
-- WORKSTATIONS
"10.0.20.21", "10.0.20.22", "10.0.20.23"
-- Add all known IPs here, grouped by function/department
)
```

### 2.3 Collect Hunt Results

Replace `<HUNT-ID>` with the actual hunt ID from step 2.1.

```sql
LET discovered_arp = SELECT *
FROM hunt_results(
    artifact='Windows.Network.ArpCache',
    hunt_id='<HUNT-ID>')

LET discovered_ips <= SELECT IP, Fqdn FROM hunt_results(
    artifact='Generic.Network.InterfaceAddresses',
    hunt_id='<HUNT-ID>')
WHERE IP =~ "10."
```

The `<=` operator on `discovered_ips` materializes the result into a static list, enabling set operations in later queries.

### 2.4 Find Unknown Endpoints (Agent Installed but Not in Asset List)

Identifies endpoints that have a Velociraptor agent but were not in the client's known asset list — potential rogue or undocumented devices.

```sql
SELECT Fqdn, IP FROM discovered_ips
WHERE IP =~ "10."
AND NOT IP =~ ":"
AND NOT IP =~ "169.254."
AND NOT IP =~ "127.0.0.1"
AND NOT IP IN known_IPS
GROUP BY Fqdn
```

### 2.5 Find Missing Endpoints (In Asset List but No Agent)

Identifies IPs from the known asset list that do not have a Velociraptor agent reporting in — these need investigation (offline, compromised, or agent deployment failed).

```sql
SELECT * FROM foreach(
    row=known_IPS,
    query={
        SELECT _value AS Missing_IP FROM scope()
        WHERE NOT _value IN discovered_ips.IP
    }
)
```

### 2.6 Discover Unknown Devices via ARP (No Agent, Seen on Network)

Finds devices that appeared in ARP caches but are not in the known asset list and have no agent. These are the most suspicious — devices on the network that nobody documented.

```sql
SELECT RemoteAddress, RemoteMACAddress, count() AS count
FROM discovered_arp
WHERE AddressFamily = "IPv4"
AND RemoteAddress =~ "10."
AND NOT RemoteAddress =~ "\\.255"
AND NOT RemoteAddress =~ "\\.1"
AND NOT RemoteAddress IN known_IPS
GROUP BY RemoteAddress, RemoteMACAddress
```

### 2.7 Interpretation Guide

| Query | Result means | Action |
|-------|-------------|--------|
| 2.4 — Unknown endpoints | Device has agent but wasn't in the asset list | Investigate: is it a legitimate device the client forgot to list, or unauthorized? |
| 2.5 — Missing endpoints | Known asset has no agent reporting | Check if the device is offline, unreachable, or if agent deployment failed. Redeploy or investigate. |
| 2.6 — ARP unknowns | Device seen on the wire with no agent and no asset record | Highest priority: could be rogue device, attacker infrastructure, or unmanaged IoT/OT. Investigate MAC vendor and network location. |

### 2.8 Adapting for a New Engagement

1. Replace `known_IPS` with the client's actual asset inventory
2. Adjust the IP prefix filter (`=~ "10."`) to match the client's network ranges
3. Run the two prerequisite hunts and update the `hunt_id` values
4. Run each query as a separate notebook cell in the Velociraptor frontend
