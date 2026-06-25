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
