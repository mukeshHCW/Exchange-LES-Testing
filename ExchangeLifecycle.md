# Exchange Migration Lifecycle: On-Premises to Full Cloud Native

This document outlines the complete organizational lifecycle for Exchange migration, from pure on-premises to fully cloud-native infrastructure.

---

## Lifecycle Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        ORGANIZATION LIFECYCLE                                    │
└─────────────────────────────────────────────────────────────────────────────────┘

┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   STAGE 1    │     │   STAGE 2    │     │   STAGE 3    │     │   STAGE 4    │
│  Pure        │────▶│  Hybrid      │────▶│  All Cloud   │────▶│  Cloud       │
│  On-Premises │     │  Coexistence │     │  Mailboxes   │     │  Management  │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
                                                                      │
                                                                      ▼
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   STAGE 8    │     │   STAGE 7    │     │   STAGE 6    │     │   STAGE 5    │
│  Full Cloud  │◀────│  AD for      │◀────│  Object SOA  │◀────│  Shutdown    │
│  Native      │     │  Identity    │     │  Transfer    │     │  Last Exch   │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
```

---

## Stage 1: Pure On-Premises

**Description:** Traditional Exchange deployment with all infrastructure on-premises.

| Component | Location | Source of Authority |
|-----------|----------|---------------------|
| Exchange Server | On-premises | N/A |
| Mailboxes | On-premises | Exchange Server |
| User Identity | Active Directory | AD |
| Exchange Attributes | Active Directory | AD |

**Characteristics:**
- All mailboxes hosted on-premises Exchange Server
- Active Directory is the single source of authority for all user attributes
- No cloud involvement
- Full control over infrastructure

---

## Stage 2: Hybrid Coexistence

**Description:** Organization establishes hybrid connectivity between on-premises Exchange and Exchange Online.

| Component | Location | Source of Authority |
|-----------|----------|---------------------|
| Exchange Server | On-premises | N/A |
| Mailboxes | Split (On-prem + Cloud) | Respective location |
| User Identity | Active Directory | AD (synced to Entra ID) |
| Exchange Attributes | Active Directory | AD |

**Key Activities:**
1. Configure Microsoft Entra Connect or Cloud Sync
2. Run Hybrid Configuration Wizard
3. Establish mail flow connectors
4. Begin gradual mailbox migration to Exchange Online

**Prerequisites:**
- Microsoft Entra Connect Sync (v2.5.190.0+) or Cloud Sync
- Exchange Hybrid Configuration
- Proper DNS and certificate configuration

---

## Stage 3: All Mailboxes in Cloud

**Description:** All mailboxes have been migrated to Exchange Online, but on-premises Exchange Server is still required.

| Component | Location | Source of Authority |
|-----------|----------|---------------------|
| Exchange Server | On-premises (required) | N/A |
| Mailboxes | Exchange Online | EXO |
| User Identity | Active Directory | AD (synced to Entra ID) |
| Exchange Attributes | Active Directory | AD |

**The Problem:**
- On-premises Exchange Server is still needed solely for recipient management
- Dir-synced users (`IsDirSynced = True`) cannot have Exchange attributes edited in cloud
- Exchange Server is maintained just to run PowerShell commands like `Set-RemoteMailbox`

**Verification:**
```powershell
# Verify all mailboxes are in the cloud
Set-AdServerSettings -ViewEntireForest $true
Get-Mailbox  # Should return no on-premises mailboxes
```

---

## Stage 4: Cloud Management

**Description:** Enable cloud-based management of Exchange attributes to eliminate dependency on on-premises Exchange Server for recipient management.

### Two Available Paths

| Aspect | Path A: EMT | Path B: LES Feature |
|--------|-------------|---------------------|
| Full Name | Exchange Management Tools | Last Exchange Server |
| Method | PowerShell Snap-in | `IsExchangeCloudManaged = $true` |
| SOA for Exchange Attributes | On-premises AD | Exchange Online |
| Writeback to AD | N/A (AD is SOA) | Yes (Phase 2) |
| Management Location | On-premises (domain-joined machine) | Cloud (EXO PowerShell, Admin Center) |

### Path A: Exchange Management Tools (EMT)

Install Exchange Management Tools on a domain-joined machine to manage recipients without running Exchange Server.

**Installation:**
1. Install Exchange Server 2019 CU12+ Management Tools role
2. Install Windows RSAT Tools
3. Configure Scripting Agent (if applicable)
4. Create Recipient Management security group

**Usage:**
```powershell
# Load the snap-in
Add-PSSnapin *RecipientManagement

# Manage recipients
Set-RemoteMailbox -Identity User1 -CustomAttribute1 "Value"
```

### Path B: LES Feature (IsExchangeCloudManaged)

Transfer attribute-level Source of Authority for Exchange attributes to the cloud.

**Phase 1 (GA):**
- Per-mailbox cloud management
- Edit Exchange attributes in Exchange Online
- No writeback to on-premises AD

**Phase 2 (Preview):**
- Writeback support via Entra Cloud Sync
- Cloud changes sync back to on-premises AD
- Keeps AD current for compliance/reporting

**Enable Cloud Management:**
```powershell
# Exchange Online PowerShell
Set-Mailbox -Identity User1 -IsExchangeCloudManaged $true

# Verify
Get-Mailbox -Identity User1 | Select-Object DisplayName, IsDirSynced, IsExchangeCloudManaged
```

**Enable Tenant-Wide (for new users):**
```powershell
# Exchange Online PowerShell
Set-OrganizationConfig -ExchangeAttributesCloudManagedByDefault
```

---

## Stage 5: Shutdown Last Exchange Server

**Description:** With cloud management enabled, the last on-premises Exchange Server can be shut down.

### Critical Warnings

> **SHUT DOWN, DO NOT UNINSTALL**
>
> Uninstalling the last Exchange Server removes critical Active Directory objects needed for:
> - Exchange Management Tools functionality
> - Hybrid configuration
> - Future recovery scenarios

### Pre-Shutdown Checklist

| Task | Command/Action |
|------|----------------|
| Verify all mailboxes migrated | `Get-Mailbox` returns empty |
| Verify cloud management enabled | Check `IsExchangeCloudManaged` for all users |
| Remove Federation Trust | `Remove-FederationTrust "Microsoft Federation Gateway"` |
| Remove Federation Certificate | Remove certificate with Subject "CN=Federation" |
| Clean up OAuth (if applicable) | Run `ConfigureExchangeHybridApplication.ps1 -ResetFirstPartyServicePrincipalKeyCredentials` |
| Uninstall Hybrid Agent (Modern Hybrid) | Use `Remove-HybridApplication` |

### Post-Shutdown State

| Component | Status |
|-----------|--------|
| Exchange Server | Powered off (not uninstalled) |
| Recipient Management | Via EMT snap-in or EXO (depending on path chosen) |
| Exchange RBAC | No longer functional |
| AD Objects | Preserved |

---

## Stage 6: Object-Level SOA Transfer

**Description:** Transfer the full object-level Source of Authority from on-premises AD to the cloud, making users "cloud-only."

### Understanding SOA Levels

| SOA Level | Before Transfer | After Transfer |
|-----------|-----------------|----------------|
| Object-level SOA | On-premises AD | Entra ID (Cloud) |
| Attribute-level SOA (Identity) | On-premises AD | Entra ID (Cloud) |
| Attribute-level SOA (Exchange) | Cloud (with LES) | Cloud |
| `IsDirSynced` | `True` | `False` |

### Prerequisites

- Entra Connect Sync version **2.5.76.0+** or Cloud Sync version **1.1.1370.0+**
- **Hybrid Administrator** role
- **User-OnPremisesSyncBehavior.ReadWrite.All** scope permission

### Transfer Process

```powershell
# MS Graph PowerShell
# Get user's Entra ID object ID
Connect-MgGraph -Scopes "User.Read.All"
$user = Get-MgUser -Filter "userPrincipalName eq 'user@contoso.com'"
$userId = $user.Id

# Check current SOA status
$response = Invoke-MgGraphRequest `
   -Method GET `
   -Uri "https://graph.microsoft.com/v1.0/users/$userId/onPremisesSyncBehavior?`$select=isCloudManaged"
$response | ConvertTo-Json
# Expected: isCloudManaged = false (on-premises managed)

# Transfer Object SOA to Cloud
Connect-MgGraph -Scopes "User-OnPremisesSyncBehavior.ReadWrite.All"

$body = @{
    isCloudManaged = $true
} | ConvertTo-Json

Invoke-MgGraphRequest `
   -Method PATCH `
   -Uri "https://graph.microsoft.com/v1.0/users/$userId/onPremisesSyncBehavior" `
   -Body $body `
   -ContentType "application/json"

# Verify transfer
$response = Invoke-MgGraphRequest `
   -Method GET `
   -Uri "https://graph.microsoft.com/v1.0/users/$userId/onPremisesSyncBehavior?`$select=isCloudManaged"
$response | ConvertTo-Json
# Expected: isCloudManaged = true
```

### Impact of Object SOA Transfer

| Aspect | Before | After |
|--------|--------|-------|
| User sync direction | AD → Entra ID | None (cloud-only) |
| Identity attribute management | On-premises AD | Entra ID / M365 Admin Center |
| Exchange attribute management | Cloud (EXO) | Cloud (EXO) |
| LES Writeback scope | In scope | **Out of scope** (no AD object to write to) |
| AD object status | Active, synced | `blockOnPremisesSync = true` |

### Key Insight

After Object SOA transfer:
- User becomes cloud-only (`IsDirSynced = False`)
- User automatically moves **OUT** of LES Writeback scope
- `IsExchangeCloudManaged` property becomes irrelevant (no AD object to write back to)
- On-premises AD object is no longer updated

---

## Stage 7: AD for Identity Only (Transitional)

**Description:** Organization operates in a mixed state where some users remain dir-synced while others are cloud-only.

### Typical Scenarios

| User Type | SOA | Management Location |
|-----------|-----|---------------------|
| Legacy/Compliance users | On-premises AD | AD + LES Writeback |
| Standard users | Cloud (Entra ID) | M365 Admin Center / Entra ID |
| New hires | Cloud (Entra ID) | M365 Admin Center / Entra ID |

### Considerations

- **Compliance Requirements:** Some industries require on-premises identity management
- **Gradual Transition:** Move users to cloud-only in batches
- **Hybrid Identity:** AD continues to serve other purposes (file servers, apps, GPO)

### Objects Beyond Users

| Object Type | SOA Transfer Status |
|-------------|---------------------|
| Users | Available (Stage 6) |
| Groups | Public Preview |
| Contacts | On Roadmap |

---

## Stage 8: Full Cloud Native (End State)

**Description:** Organization has fully transitioned to cloud-native identity and messaging with no on-premises dependencies.

### Target State

| Component | Location | Management |
|-----------|----------|------------|
| User Identity | Entra ID | M365 Admin Center / Entra ID |
| Exchange Attributes | Exchange Online | EXO Admin Center / PowerShell |
| Groups | Entra ID / M365 | M365 Admin Center |
| Mailboxes | Exchange Online | EXO Admin Center |
| On-premises AD | Decommissioned or minimal | N/A |
| On-premises Exchange | Decommissioned | N/A |

### Prerequisites for Full Cloud Native

1. All users have Object SOA transferred to cloud
2. All groups have SOA transferred to cloud
3. All contacts have SOA transferred to cloud
4. No AD-dependent applications remain
5. No GPO dependencies (or migrated to Intune)
6. No on-premises file server dependencies (or migrated to SharePoint/OneDrive)

### Open Questions

| Question | Current Answer |
|----------|----------------|
| Can AD be fully decommissioned? | Depends on other AD-dependent services |
| Is there AD cleanup guidance post-migration? | Similar to `CleanupActiveDirectoryEMT.ps1` but for user objects - TBD |
| What about domain-joined devices? | Requires Entra ID Join or Hybrid Join strategy |
| Kerberos authentication for legacy apps? | May require Azure AD Kerberos or app modernization |

---

## Summary: SOA Progression Through Stages

| Stage | Object SOA | Identity Attributes SOA | Exchange Attributes SOA | IsDirSynced |
|-------|------------|-------------------------|-------------------------|-------------|
| 1-3 | On-prem AD | On-prem AD | On-prem AD | True |
| 4 (EMT) | On-prem AD | On-prem AD | On-prem AD | True |
| 4 (LES) | On-prem AD | On-prem AD | **Cloud** | True |
| 5 | On-prem AD | On-prem AD | Cloud | True |
| 6 | **Cloud** | **Cloud** | Cloud | **False** |
| 7 | Mixed | Mixed | Cloud | Mixed |
| 8 | Cloud | Cloud | Cloud | False |

---

## References

- [Introducing Cloud-Managed Remote Mailboxes](https://techcommunity.microsoft.com/blog/exchange/introducing-cloud-managed-remote-mailboxes-a-step-to-last-exchange-server-retire/4446042)
- [Enable Exchange Attributes Cloud Management](https://learn.microsoft.com/en-us/exchange/hybrid-deployment/enable-exchange-attributes-cloud-management)
- [Manage Hybrid Exchange Recipients with Management Tools](https://learn.microsoft.com/en-us/exchange/manage-hybrid-exchange-recipients-with-management-tools)
- [Configure User Source of Authority](https://learn.microsoft.com/en-us/entra/identity/hybrid/how-to-user-source-of-authority-configure)
- [Exchange Hybrid Writeback with Cloud Sync](https://learn.microsoft.com/en-us/entra/identity/hybrid/cloud-sync/exchange-hybrid)
