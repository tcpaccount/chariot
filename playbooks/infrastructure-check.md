# Infrastructure Check

**Version:** 1.0
**Companion to:** SOP 01 — Network Presence Establishment

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
