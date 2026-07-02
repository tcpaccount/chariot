# User Account Baselining and Lateral Movement Playbook

**Version:** 1.0
**Companion to:** SOP 01 — Network Presence Establishment

This playbook is a two-step process for detecting lateral movement. Step 1 establishes a baseline of normal interactive logon behaviour — who logs onto which machines. Step 2 uses that baseline to parameterize a targeted hunt that flags users authenticating to machines outside their normal pattern.

---

## 1. Overview

**Goal:** Identify accounts authenticating to machines they do not normally use — a primary indicator of lateral movement, credential reuse, or account compromise.

**Two-step logic:**

| Step          | What you run                                                              | What you get                                                                |
| ------------- | ------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| 1 — Baseline | `Exchange.Windows.EventLogs.LogonSessions` + `Windows.Sys.Interfaces` | Normal user→machine map ordered by logon frequency                         |
| 2 — Hunt     | `Windows.EventLogs.RDPAuth` / `Windows.Packs.LateralMovement`         | Logon events where a user authenticates to a machine outside their baseline |

Run Step 1 first. The output directly informs the filter parameters for Step 2.

---

## 2. Step 1 — Baseline Interactive Logons

### 2.1 Prerequisites

Run these two hunts from the Velociraptor frontend **before** opening the notebook:

1. **Hunt → New Hunt → `Exchange.Windows.EventLogs.LogonSessions`** — collects Windows Security event 4624 (logon) from all endpoints
2. **Hunt → New Hunt → `Windows.Sys.Interfaces`** — collects IP/interface info to resolve FQDNs to IPs

Note the hunt ID (e.g., `H.XXXXXXXXX`) — replace `H.D234PQU23FK8K` in the VQL below.

**Event filter:** LogonType 2 = interactive logon (local keyboard/screen or console session). This excludes network logons (type 3), service logons (type 5), and batch logons (type 4), keeping only sessions where a user was physically or interactively present on the endpoint.

### 2.2 VQL — Build the Baseline

```sql
-- Collect interactive logons from all agents
LET the_logons = SELECT Fqdn, TargetUserName[0] AS TargetUserName, SourceHost,
                        LogonType[0] AS LogonType, count() AS count
FROM hunt_results(
    artifact='Exchange.Windows.EventLogs.LogonSessions',
    hunt_id='H.D234PQU23FK8K')
WHERE LogonType = 2
GROUP BY Fqdn, TargetUserName, SourceHost, LogonType

-- Collect interface IPs to map FQDNs to IP addresses
LET the_interfaces = SELECT Fqdn, Details.IP AS IP
FROM hunt_results(
    artifact='Windows.Sys.Interfaces',
    hunt_id='H.D234PQU23FK8K')
WHERE Details.IP =~ "10\\."

-- Join: for each logon, attach the IP of the machine that recorded it
SELECT * FROM foreach(
    row={ SELECT *, Fqdn AS Fqdn_IP FROM the_logons },
    query={
        SELECT Fqdn, IP, TargetUserName, SourceHost, LogonType, count
        FROM the_interfaces
        WHERE Fqdn = Fqdn_IP
    }
)
ORDER BY count DESC
```

### 2.3 Reading the Baseline Output

| Column             | Meaning                                                            |
| ------------------ | ------------------------------------------------------------------ |
| `Fqdn`           | Machine that recorded the logon event                              |
| `IP`             | IP address of that machine                                         |
| `TargetUserName` | Account that logged in                                             |
| `SourceHost`     | Machine the user logged in**from** (blank for local/console) |
| `count`          | How many times this user→machine pair was seen                    |

**High count = normal behaviour.** Sort descending and read top rows first — these are the established patterns. Low-count rows at the bottom are anomalies worth reviewing even at this stage.

Build a mental (or written) map of:

- Which account normally logs onto which machine(s)
- Which accounts appear on multiple machines (administrators, service accounts)
- Any account appearing on a machine far from their normal zone

This map directly feeds the exclusion filters in Step 2.

---

## 3. Step 2 — Hunt for Lateral Movement

### 3.1 Prerequisites

> **Note:** Despite its name, `Windows.EventLogs.RDPAuth` is not limited to RDP connections. It collects all Windows authentication events and covers interactive, network, and remote logon types — RDP is just one of them.

Run this hunt from the Velociraptor frontend:

**Hunt → New Hunt → `Windows.EventLogs.RDPAuth`**

Configure the hunt parameter before launching:

| Parameter         | Value                               | Notes                                                                                                                |
| ----------------- | ----------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `UserNameRegex` | `.(Roman.Nester\|First.LastName).` | Pipe-delimited list of accounts identified in Step 1 as high-value targets. Leading/trailing`.` anchors the regex. |

Note the new hunt ID — replace `H.D2377GDR44Q20` in the VQL below.

Alternatively run **`Windows.Packs.LateralMovement`** for a broader artifact covering pass-the-hash, pass-the-ticket, and token impersonation in addition to RDP authentication.

### 3.2 VQL — Detect Lateral Movement

Replace the `UserName =~ / NOT Computer =~` pairs with the user→machine baseline from Step 1. Each pair asserts: "flag this user logging onto any machine **except** their known home machine."

```sql
SELECT EventTime, Computer, Channel, EventID, UserName, LogonType,
       SourceIP, Description, Message, Fqdn
FROM hunt_results(
    artifact='Windows.EventLogs.RDPAuth',
    hunt_id='H.D2377GDR44Q20')
WHERE (
    -- Flag: user seen on a machine other than their normal workstation
    (UserName =~ "romio"         AND NOT Computer =~ "DESKTOP-GJB37HJ")
    OR
    (UserName =~ "Administrator" AND NOT Computer =~ "WIN-R42UU0TEM40")
    -- Add one OR block per user from the Step 1 baseline
)
AND NOT EventID = 4634                                          -- exclude logoff events
AND NOT (Computer =~ "dc" OR Computer =~ "exchange" OR Computer =~ "fs1")
-- Exclude infrastructure servers: lateral movement to user workstations is the signal
ORDER BY EventTime
```

### 3.3 Filter Logic Explained

**`NOT EventID = 4634`** — EventID 4634 is logoff. Including it would flood results with normal session teardowns and obscure actual logon anomalies.

**`NOT (Computer =~ "dc" OR Computer =~ "exchange" OR Computer =~ "fs1")`** — Admins and service accounts legitimately touch servers. Excluding them focuses the hunt on user workstations, where lateral movement to non-owner accounts is inherently suspicious.

**`UserName =~ "x" AND NOT Computer =~ "y"`** — Each block reads: "user X appeared somewhere other than their known machine Y." The baseline from Step 1 provides the `y` values.

### 3.4 Interpretation Guide

| Finding                                                 | Likely meaning                                                  | Action                                                         |
| ------------------------------------------------------- | --------------------------------------------------------------- | -------------------------------------------------------------- |
| User on single unfamiliar workstation                   | Credential reuse or borrowed session                            | Verify with user; check SourceIP for originating machine       |
| User on multiple unfamiliar machines in short timeframe | Active lateral movement                                         | Escalate; contain originating machine; review SourceIP chain   |
| Administrator account on user workstation               | Admin tool abuse, pass-the-hash, or attacker using stolen creds | High priority; correlate with`Windows.Packs.LateralMovement` |
| `SourceIP` = external or VPN IP                       | Remote access abuse or compromised remote session               | Investigate VPN/remote access logs                             |

---

## 4. Adapting for a New Engagement

1. **Step 1:** Replace hunt IDs in both `LET` blocks; adjust the IP prefix (`=~ "10\\."`) to match the client's range
2. **Step 1 output:** Document the user→machine map before building Step 2 filters
3. **Step 2 `UserNameRegex`:** Include accounts of interest identified in Step 1 — privileged users, shared accounts, and any anomalies already spotted
4. **Step 2 exclusions:** Update `NOT Computer =~ "..."` pairs with actual machine names from the baseline; update the server exclusion list (`dc`, `exchange`, `fs1`) to match the client's infrastructure naming
5. Run Step 2 hunt and notebook only **after** Step 1 results are reviewed — the baseline is what makes the hunt signal meaningful
