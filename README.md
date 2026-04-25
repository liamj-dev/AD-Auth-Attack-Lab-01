# AD Authentication Attack Lab

> A virtualized enterprise security lab simulating credential-based attacks against a Windows Active Directory environment, with full detection and alerting via a self-deployed SIEM.

![Windows Server 2022](https://img.shields.io/badge/Windows_Server-2022-0078D4?style=flat-square&logo=windows)
![Kali Linux](https://img.shields.io/badge/Kali_Linux-2025.4-557C94?style=flat-square&logo=kalilinux)
![Wazuh](https://img.shields.io/badge/Wazuh-4.14-005571?style=flat-square)
![VMware](https://img.shields.io/badge/VMware_Workstation_Pro-blue?style=flat-square&logo=vmware)

---

## Overview

This lab builds a realistic corporate Active Directory environment from scratch inside VMware Workstation Pro, then executes a multi-technique credential attack chain against it. Every attack is detected and alerted on by a self-deployed Wazuh SIEM using custom detection rules mapped to MITRE ATT&CK.

The goal is to demonstrate hands-on skills in Active Directory administration, Windows event log analysis, detection engineering, and defensive security tooling — end to end, from domain setup to SIEM alert.

**Skills demonstrated:** Active Directory, Windows Event Forwarding, Sysmon, Wazuh SIEM, custom detection rule authoring, MITRE ATT&CK mapping, PowerShell, brute force simulation, Kerberoasting detection.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    VMware Workstation Pro                         │
│                  VMnet1 — Host-Only — 192.168.100.0/24           │
│                                                                  │
│  ┌─────────────────┐   ┌─────────────────┐   ┌───────────────┐  │
│  │   BANK-DC01     │   │   BANK-WS01     │   │  BANK-KALI    │  │
│  │ Windows Server  │   │  Windows 11     │   │ Kali 2025.4   │  │
│  │    2022         │◄──│  192.168.100.20 │   │192.168.100.40 │  │
│  │ 192.168.100.10  │   │  WEF Forwarder  │   │  Attacker VM  │  │
│  │  Domain Controller  │  Sysmon Agent  │   └───────────────┘  │
│  │  DNS, WEF Collector │                │           │           │
│  │  Sysmon, Wazuh Agent│                │           │ attacks   │
│  └────────┬────────┘   └─────────────────┘           ▼           │
│           │                                  ┌───────────────┐  │
│           │ Wazuh events                     │  BANK-SIEM01  │  │
│           └─────────────────────────────────►│  Ubuntu 24.04 │  │
│                                              │192.168.100.30 │  │
│                                              │ Wazuh Manager │  │
│                                              │  + Dashboard  │  │
│                                              └───────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

### VM Inventory

| Hostname     | OS                   | IP               | Role                                      |
|--------------|----------------------|------------------|-------------------------------------------|
| BANK-DC01    | Windows Server 2022  | 192.168.100.10   | Domain Controller, DNS, WEF Collector     |
| BANK-WS01    | Windows 11           | 192.168.100.20   | Domain Workstation, WEF Forwarder         |
| BANK-SIEM01  | Ubuntu 24.04 LTS     | 192.168.100.30   | Wazuh Manager + Indexer + Dashboard       |
| BANK-KALI    | Kali Linux 2025.4    | 192.168.100.40   | Attacker VM                               |

**Domain:** `oakridgebank.local`  
**Network:** VMnet1 (host-only, isolated — no internet access)

---

## AD Structure

- **OUs:** Employees, IT, HR, Executives, Service Accounts
- **Security Groups:** Finance-Users, HR-Team, IT-Support (RBAC model)
- **Domain Admin:** built-in Administrator only (least privilege)
- **Test Account:** `oakridgebank\jsmith`

---

## Security Stack

### Sysmon
Deployed on both BANK-DC01 and BANK-WS01 using the [SwiftOnSecurity config](https://github.com/SwiftOnSecurity/sysmon-config). Captures process creation, network connections, registry changes, and more with low noise.

### Windows Event Forwarding (WEF)
Source-initiated subscription with BANK-DC01 as the collector. Forwards the following channels from BANK-WS01:
- `Microsoft-Windows-Sysmon/Operational`
- `Security`
- `System`
- `Application`

### Wazuh 4.14 SIEM
Self-deployed on BANK-SIEM01 (Ubuntu 24.04). Agents installed on both DC01 and WS01. Custom detection rules in `Scripts/local_rules.xml` extend Wazuh's built-in ruleset with lab-specific logic.

**Dashboard panels:** Failed Logon Attempts, Brute Force Alerts, Privileged Group Changes, Kerberoasting Attempts, AS-REP Roasting Attempts, Attacker Source IPs, MITRE Technique Breakdown, Top Targeted Accounts.

---

## Audit Policy

Configured via `auditpol` on BANK-DC01. Key subcategories enabled (success + failure):

| Subcategory                        | Success | Failure |
|------------------------------------|---------|---------|
| Logon                              | ✓       | ✓       |
| Credential Validation              | ✓       | ✓       |
| Kerberos Authentication Service    | ✓       | ✓       |
| Kerberos Service Ticket Operations | ✓       | ✓       |
| User Account Management            | ✓       | ✓       |

**Account Lockout Policy:** Threshold 5 attempts | Observation window 30 min | Lockout duration 15 min

---

## Lab Phases

### Phase 1 — Domain Setup
Promoted BANK-DC01 to domain controller for `oakridgebank.local`. Created OU structure, security groups, and test user account `jsmith`. Configured advanced audit policy via `auditpol` and set account lockout policy via `Set-ADDefaultDomainPasswordPolicy`.

### Phase 2 — Detection Infrastructure
Deployed Sysmon on DC01 and WS01 with SwiftOnSecurity config. Configured source-initiated WEF subscription (fixed SDDL to include Network Service SID). Deployed Wazuh 4.14 on BANK-SIEM01, enrolled both agents, and authored three custom detection rules.

### Phase 3 — Attack Simulation
Ran `brute_force_sim.ps1` from BANK-KALI targeting `jsmith` with 10 incorrect passwords. Triggered account lockout after 5 failures. Also simulated a Kerberoasting attempt (TGS request with RC4 encryption) and a privileged group membership change.

### Phase 4 — Detection & Response
Wazuh fired Rule 100001 (brute force) at alert level 12. Active response automatically blocked BANK-KALI's IP via `iptables` on BANK-SIEM01 for 300 seconds. All three custom rules validated end-to-end.

---

## Detection Results

| Technique              | MITRE ID   | Windows Event IDs    | Wazuh Rule | Alert Level |
|------------------------|------------|----------------------|------------|-------------|
| Brute Force            | T1110      | 4625, 4771, 4740     | 100001     | 12          |
| Privileged Group Change| T1078      | 4728                 | 100002     | 14          |
| Kerberoasting          | T1558.003  | 4769 (RC4 / 0x17)   | 100003     | 14          |

---

## Key Event IDs Reference

| Event ID | Description                                      | Log Location          |
|----------|--------------------------------------------------|-----------------------|
| 4624     | Successful logon                                 | Security              |
| 4625     | Failed logon attempt                             | Security              |
| 4740     | Account locked out                               | Security              |
| 4771     | Kerberos pre-authentication failed               | Security (DC only)    |
| 4769     | Kerberos service ticket (TGS) requested          | Security (DC only)    |
| 4728     | Member added to security-enabled global group    | Security              |

---

## Screenshots

Evidence screenshots are in the [`screenshots/`](./screenshots/) folder.

| File | What It Shows |
|------|---------------|
| `screenshot_01_4624_baseline.png` | Normal successful logon event (4624 detail) |
| `screenshot_02_4625_flood_list.png` | Burst of failed logon events in log list view |
| `screenshot_03_4625_detail.png` | Single 4625 event — failure reason "Unknown user name or bad password", source IP 192.168.100.40 |
| `screenshot_04_4769_kerberoasting.png` | 4769 Kerberos TGS request — jsmith targeting svc_backup, encryption type 0x17 (RC4/Kerberoasting) |
| `screenshot_05_4740_lockout.png` | Account lockout event (4740) — jsmith locked out |
| `screenshot_06_auditpol.png` | `auditpol /get /category:*` showing enabled policies on DC01 |
| `screenshot_07_lockout_policy.png` | `Get-ADDefaultDomainPasswordPolicy` output for oakridgebank.local |
| `screenshot_08_aduc.png` | Active Directory Users and Computers — oakridgebank.local OU structure |
| `screenshot_09_wazuh_dashboard_mitre.png` | Wazuh dashboard — Kerberoasting count, attacker source IPs, MITRE ATT&CK breakdown |
| `screenshot_10_wazuh_threat_hunting.png` | Wazuh Threat Hunting — all 3 custom rules fired (100001, 100002, 100003) |
| `screenshot_11_wazuh_dashboard_summary.png` | Wazuh dashboard — 9 failed logons, 1 brute force alert, 2 privileged group changes |
| `screenshot_12_4740_lockout_list.png` | Event Viewer 4740 list — 2 lockout events for jsmith |
| `screenshot_13_4728_group_change.png` | Event Viewer 4728 — jsmith added to Domain Admins by svc_backup |
| `screenshot_14_kali_privilege_escalation.png` | Kali — `net rpc group addmem` command adding jsmith to Domain Admins |
| `screenshot_15_wazuh_100001_alerts.png` | Wazuh — Rule 100001 brute force alert hits over time |
| `screenshot_16_wazuh_100001_rule_hits.png` | Wazuh — Rule 100001 query showing 4 total brute force detections |
| `screenshot_17_4625_flood_earlier.png` | Event Viewer 4625 — earlier attack run, 92 events clustered at 10:16 AM |
| `screenshot_18_wazuh_dashboard_early.png` | Wazuh dashboard from earlier attack run |
| `screenshot_19_wazuh_initial_setup.png` | Wazuh SIEM01 initial deployment and dashboard |
| `screenshot_20_kali_nmap_scan.png` | Kali — Zenmap/nmap scan identifying BANK-DC01 |
| `screenshot_21_kali_recon_results.png` | Kali — CrackMapExec/nmap recon results listing AD hosts |
| `screenshot_22_kali_terminal.png` | Kali terminal output during attack |
| `screenshot_23_kali_output.png` | Kali terminal — encoded/script output |

---

## Scripts

| File | Description |
|------|-------------|
| [`Scripts/brute_force_sim.ps1`](./Scripts/brute_force_sim.ps1) | Simulates 10 failed logon attempts against a domain account using DirectoryServices. Run from WS01 as a domain user — no admin required. |
| [`Scripts/local_rules.xml`](./Scripts/local_rules.xml) | Custom Wazuh detection rules (100001–100003) for brute force, privileged group changes, and Kerberoasting. Deployed to `/var/ossec/etc/rules/` on BANK-SIEM01. |
| [`Scripts/subscription.xml`](./Scripts/subscription.xml) | WEF source-initiated subscription config. Deployed on BANK-DC01 via `wecutil cs subscription.xml`. |

---

## Skills Demonstrated

- Active Directory deployment and administration (Windows Server 2022)
- Advanced audit policy configuration (`auditpol`, GPO)
- Windows Event Log analysis (4624, 4625, 4740, 4771, 4769, 4728)
- Sysmon deployment and tuning (SwiftOnSecurity config)
- Windows Event Forwarding (source-initiated subscriptions, SDDL, Kerberos auth)
- SIEM deployment and management (Wazuh 4.14 on Linux)
- Custom detection rule authoring (XML, frequency-based correlation)
- MITRE ATT&CK mapping (T1110, T1078, T1558.003)
- Attack simulation (brute force, Kerberoasting, privilege escalation)
- Automated active response (firewall-drop via iptables)
- PowerShell scripting
- VMware network configuration (host-only isolated lab)
