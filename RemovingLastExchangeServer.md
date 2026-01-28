# Removing the Last Exchange Server: EMT vs LES Paths

This document provides guidance on permanently removing the last on-premises Exchange Server, comparing the Exchange Management Tools (EMT) path with the Last Exchange Server (LES) feature path.

---

## Executive Summary

| Aspect | EMT Path | LES Path (No Writeback) | LES Path (With Writeback) |
|--------|----------|-------------------------|---------------------------|
| Can Shut Down Exchange? | Yes | Yes | Yes |
| Can Uninstall Exchange? | **No** | **Yes (hypothesis)** | **Yes (hypothesis)** |
| AD Container Dependencies | Required | Not Required | Not Required |
| Management Location | On-premises (PowerShell) | Cloud (EXO) | Cloud (EXO) |
| AD Stays Current? | Yes (AD is SOA) | No | Yes (via Entra Cloud Sync) |
| Writeback Mechanism | N/A | N/A | Entra Cloud Sync |

---

## Background: The Last Exchange Server Problem

Organizations that have migrated all mailboxes to Exchange Online often retain an on-premises Exchange Server solely for recipient management. This happens because:

1. Directory-synchronized users (`IsDirSynced = True`) have their Source of Authority (SOA) in on-premises AD
2. Exchange attributes cannot be edited in Exchange Online for dir-synced users
3. Administrators must use `Set-RemoteMailbox` on-premises to modify attributes like email addresses

This creates a burden: maintaining Exchange Server infrastructure (patching, updates, security) just to run PowerShell commands.

---

## Two Paths to Remove the Last Exchange Server

### Path A: Exchange Management Tools (EMT)

EMT allows recipient management without running Exchange Server, but **requires Exchange AD objects to exist**.

**Key Characteristics:**
- Install Exchange 2019 CU12+ Management Tools on domain-joined machine
- Use PowerShell snap-in (`Add-PSSnapin *RecipientManagement`)
- **Cannot uninstall Exchange Server** - only shut down
- Exchange Organization container must remain in AD
- Exchange Security Groups must remain in AD

**Why You Cannot Uninstall with EMT:**

When Exchange Server is uninstalled, it removes:
- `CN=Microsoft Exchange` container under `CN=Services,CN=Configuration`
- `CN=[OrganizationName]` container (e.g., `CN=Contoso`)
- Exchange Security Groups
- System mailboxes

The EMT PowerShell snap-in depends on these AD objects. Without them, EMT fails.

### Path B: LES Feature (IsExchangeCloudManaged)

LES transfers the SOA for Exchange attributes to the cloud, eliminating the need for on-premises Exchange for management.

**Key Characteristics:**
- Set `IsExchangeCloudManaged = $true` per mailbox
- Manage Exchange attributes directly in Exchange Online
- Writeback to AD via Entra Cloud Sync (Phase 2)
- **Does NOT depend on Exchange AD containers**
- **May allow full Exchange uninstallation**

**Why LES May Allow Uninstallation:**

With LES:
1. Management happens in Exchange Online, not via EMT
2. Writeback uses Entra Cloud Sync, which writes directly to `msExch*` attributes on user objects
3. Entra Cloud Sync does NOT require Exchange Organization container or Security Groups
4. The only AD requirement is the schema extensions (`msExch*` attributes), which persist after uninstallation

---

## What Happens When Exchange is Uninstalled

### Objects Removed

| Object | Location | Impact |
|--------|----------|--------|
| `CN=Microsoft Exchange` | `CN=Services,CN=Configuration,DC=...` | Exchange configuration container deleted |
| `CN=[OrganizationName]` | Child of Microsoft Exchange container | All org-level Exchange config deleted |
| `CN=Microsoft Exchange System Objects` | Domain root | System mailboxes deleted |
| Exchange Security Groups | `CN=Microsoft Exchange Security Groups,DC=...` | All Exchange RBAC groups deleted |
| Server objects | Under `CN=Servers` | Server configuration deleted |
| Arbitration/Audit mailboxes | Various | System mailboxes deleted |

### Objects That Persist

| Object | Location | Notes |
|--------|----------|-------|
| Schema extensions | AD Schema | `msExch*` attributes remain forever |
| User `msExch*` attributes | On user objects | CustomAttribute1-15, proxyAddresses, etc. |
| `msExchRecipientTypeDetails` | On user objects | Mailbox type information |

### Impact by Path

| Scenario | EMT Impact | LES Impact |
|----------|------------|------------|
| Exchange Shut Down (not uninstalled) | **Works** | **Works** |
| CleanupActiveDirectoryEMT.ps1 Run | **Works** - Script designed to work with EMT | **Works** - Not dependent on these |
| Exchange Uninstalled | **BROKEN** - Cannot manage recipients | **Works** - Cloud management continues (hypothesis) |
| Schema Extensions Remain | Required for EMT | Required for writeback |

### Understanding CleanupActiveDirectoryEMT.ps1 vs Exchange Uninstall

There is an important distinction between these two operations:

| Operation | What It Removes | EMT Works After? |
|-----------|-----------------|------------------|
| **CleanupActiveDirectoryEMT.ps1** | System mailboxes, *unnecessary* Exchange containers, Exchange Security Groups, permissions | **Yes** - Script designed to work with EMT |
| **Exchange Uninstall** | *All* Exchange AD objects including organization container, server objects, all config | **No** - EMT depends on these objects |

**Key Point:** `CleanupActiveDirectoryEMT.ps1` is specifically designed to be used WITH EMT. It removes security-sensitive objects (like security groups that could be exploited by attackers) while **preserving** the AD objects that EMT needs to function.

**Source:** [Manage Hybrid Exchange Recipients with Management Tools - Active Directory Cleanup](https://learn.microsoft.com/en-us/exchange/manage-hybrid-exchange-recipients-with-management-tools#active-directory-clean-up)

---

## Hypothesis: LES Allows Full Exchange Uninstallation

> **IMPORTANT: This section contains logical analysis that requires testing/verification.**

The hypothesis is that with LES (with or without writeback), Exchange Server can be fully uninstalled because:

### Hypothesis A: LES Without Writeback

1. **Management happens in EXO** - No dependency on EMT or on-premises tools
2. **No writeback needed** - AD doesn't need to stay current with cloud changes
3. **No Exchange AD container dependency** - Cloud management doesn't query Exchange containers
4. **Schema extensions persist** - `msExch*` attributes remain in AD schema (unused without writeback)

**Test Cases:** TC-6B.1 through TC-6B.7

### Hypothesis B: LES With Writeback

1. **Management happens in EXO** - No dependency on EMT or on-premises tools
2. **Writeback uses Entra Cloud Sync** - Writes directly to `msExch*` user attributes, not via Exchange
3. **Entra Cloud Sync doesn't need Exchange AD containers** - Only needs schema extensions on user objects
4. **Schema extensions persist** - `msExch*` attributes remain in AD schema after uninstall

**Test Cases:** TC-6A.1 through TC-6A.7

**Both hypotheses should be validated through testing before production use.**

---

## Prerequisites for Exchange Uninstallation with LES

Before attempting to uninstall Exchange Server with the LES path, ensure:

### 1. All Mailboxes Cloud-Managed

```powershell
# Exchange Online PowerShell
# Verify all dir-synced mailboxes have IsExchangeCloudManaged = True
Get-Mailbox -ResultSize Unlimited |
    Where-Object { $_.IsDirSynced -eq $true } |
    Select-Object DisplayName, IsDirSynced, IsExchangeCloudManaged |
    Where-Object { $_.IsExchangeCloudManaged -eq $false }

# This should return EMPTY if all mailboxes are cloud-managed
```

### 2. LES Writeback Configured (Optional)

LES Writeback is **optional** depending on customer requirements:

| Scenario | Writeback Needed? | Use Case |
|----------|-------------------|----------|
| AD must stay current with cloud changes | Yes | Compliance, reporting, on-prem apps reading AD |
| AD doesn't need cloud changes | No | Cloud-only management, AD is legacy |

**If using LES Writeback:**

```powershell
# MS Graph PowerShell
# Verify LES Writeback job is running
$servicePrincipalId = Get-MgServicePrincipal -Filter "displayName eq 'contoso.lab'" | Select-Object -ExpandProperty Id

$response = Invoke-MgGraphRequest `
   -Method GET `
   -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs"

$response | ConvertTo-Json -Depth 10
# Verify job status is Active/Running
```

**If NOT using LES Writeback:**
- Skip this prerequisite
- Cloud management works without writeback
- AD attributes will NOT reflect cloud changes

### 3. Entra Cloud Sync Agent Active (Required for Writeback Only)

- Agent version 1.1.1107.0 or later
- Status: Active in Entra Admin Center
- Heartbeat within last few minutes

### 4. Writeback Tested and Verified

```powershell
# Exchange Online PowerShell
# Set a test attribute
Set-Mailbox -Identity TestUser -CustomAttribute15 "PreUninstallTest_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

# Wait for sync cycle (2 minutes) or use POD

# On-Premises (AD or Exchange if still running)
# Verify the attribute was written back
Get-ADUser -Identity TestUser -Properties extensionAttribute15 | Select-Object extensionAttribute15
```

### 5. All Mailboxes Migrated to Exchange Online

```powershell
# On-Premises Exchange Management Shell (before shutdown)
Set-AdServerSettings -ViewEntireForest $true
Get-Mailbox  # Should return empty

# Disable any remaining system mailboxes
Get-Mailbox -Arbitration | Disable-Mailbox
Get-Mailbox -AuditLog | Disable-Mailbox
```

### 6. Public Folders Migrated (If Applicable)

```powershell
# Exchange Online PowerShell
Get-OrganizationConfig | Select-Object PublicFoldersEnabled
# Should NOT be 'Remote' - migrate PFs first if so
```

### 7. No SMTP Relay Dependencies

Ensure on-premises applications using Exchange for SMTP relay have alternatives:
- Exchange Online SMTP relay
- Azure Communication Services
- Third-party SMTP service
- Exchange Edge Transport server

---

## Step-by-Step: Removing Last Exchange Server with LES

### Phase 1: Pre-Removal Verification

#### Step 1.1: Inventory Current State

```powershell
# Exchange Online PowerShell
# Get all dir-synced mailboxes and their cloud management status
$mailboxes = Get-Mailbox -ResultSize Unlimited | Where-Object { $_.IsDirSynced -eq $true }
$mailboxes | Select-Object DisplayName, PrimarySmtpAddress, IsExchangeCloudManaged | Export-Csv "PreRemoval_MailboxInventory.csv" -NoTypeInformation

# Count summary
$total = $mailboxes.Count
$cloudManaged = ($mailboxes | Where-Object { $_.IsExchangeCloudManaged -eq $true }).Count
Write-Host "Total Dir-Synced Mailboxes: $total"
Write-Host "Cloud-Managed: $cloudManaged"
Write-Host "Not Cloud-Managed: $($total - $cloudManaged)"
```

#### Step 1.2: Enable Cloud Management for All Remaining Mailboxes

```powershell
# Exchange Online PowerShell
# Enable cloud management for all dir-synced mailboxes not yet enabled
Get-Mailbox -ResultSize Unlimited |
    Where-Object { $_.IsDirSynced -eq $true -and $_.IsExchangeCloudManaged -eq $false } |
    ForEach-Object {
        Write-Host "Enabling cloud management for: $($_.DisplayName)"
        Set-Mailbox -Identity $_.Alias -IsExchangeCloudManaged $true
    }
```

#### Step 1.3: Verify LES Writeback is Functional

```powershell
# Exchange Online PowerShell
# Set test attribute on multiple users
$testUsers = @("User1", "User2", "User3")
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

foreach ($user in $testUsers) {
    Set-Mailbox -Identity $user -CustomAttribute15 "WritebackTest_$timestamp"
    Write-Host "Set CustomAttribute15 for $user"
}

Write-Host "Wait 2-3 minutes for sync, then verify in AD..."
```

```powershell
# On-Premises PowerShell (AD Module)
# Verify writeback occurred
$testUsers = @("User1", "User2", "User3")

foreach ($user in $testUsers) {
    $adUser = Get-ADUser -Identity $user -Properties extensionAttribute15
    Write-Host "$user - extensionAttribute15: $($adUser.extensionAttribute15)"
}
```

### Phase 2: Hybrid Cleanup (While Exchange Still Running)

#### Step 2.1: Update DNS Records

Point MX and Autodiscover to Exchange Online:
- MX: `contoso-com.mail.protection.outlook.com`
- Autodiscover: `autodiscover.outlook.com` (CNAME)

#### Step 2.2: Remove Service Connection Points

```powershell
# On-Premises Exchange Management Shell
# Exchange 2016 or later
Get-ClientAccessService | Set-ClientAccessService -AutoDiscoverServiceInternalUri $Null
```

#### Step 2.3: Delete Hybrid Connectors

In Exchange Admin Center (on-premises):
1. Navigate to **Mail Flow** > **Connectors**
2. Delete inbound connector: `Inbound from <unique identifier>`
3. Delete outbound connector: `Outbound from <unique identifier>`

#### Step 2.4: Remove Organization Relationship

In Exchange Admin Center (on-premises):
1. Navigate to **Organization** > **Sharing**
2. Remove: `O365 to On-Premises - <unique identifier>`

#### Step 2.5: Disable OAuth Configuration

```powershell
# On-Premises Exchange Management Shell
Get-IntraorganizationConnector -Identity ExchangeHybridOnPremisesToOnline |
    Set-IntraOrganizationConnector -Enabled $False

# Exchange Online PowerShell
Get-IntraorganizationConnector -Identity ExchangeHybridOnlineToOnPremises |
    Set-IntraOrganizationConnector -Enabled $False
```

#### Step 2.6: Remove Federation Trust

```powershell
# On-Premises Exchange Management Shell
Remove-FederationTrust "Microsoft Federation Gateway"
```

#### Step 2.7: Remove Federation Certificate

```powershell
# On-Premises Exchange Management Shell
$fedThumbprint = (Get-ExchangeCertificate | Where-Object {$_.Subject -eq "CN=Federation"}).Thumbprint
Remove-ExchangeCertificate -Thumbprint $fedThumbprint
```

#### Step 2.8: Remove OAuth Service Principal (If Applicable)

```powershell
# On-Premises Exchange Management Shell
& $env:ExchangeInstallPath\Scripts\ConfigureExchangeHybridApplication.ps1 -ResetFirstPartyServicePrincipalKeyCredentials
```

#### Step 2.9: Remove Hybrid Agent (Modern Hybrid Only)

```powershell
# On-Premises PowerShell
Import-Module "C:\Program Files\Microsoft Hybrid Service\HybridManagement.psm1"

# Get AppId from Organization Relationship
$appId = (Get-OrganizationRelationship ((Get-OnPremisesOrganization).OrganizationRelationship) |
    Select-Object -ExpandProperty TargetSharingEpr) -replace '.*appId=([^&]+).*', '$1'

# Remove the Hybrid Application
Remove-HybridApplication -appId $appId -Credential (Get-Credential)
```

### Phase 3: Uninstall Exchange Server (LES Path Only)

> **WARNING:** This step is only supported with the LES path where all mailboxes have `IsExchangeCloudManaged = True` and LES Writeback is configured via Entra Cloud Sync.
>
> If you are using EMT for management, **DO NOT proceed with uninstallation**.

#### Step 3.1: Verify No Mailboxes Remain

```powershell
# On-Premises Exchange Management Shell
Set-AdServerSettings -ViewEntireForest $true
Get-Mailbox  # Must return empty
Get-Mailbox -Arbitration  # Disable any remaining
Get-Mailbox -AuditLog  # Disable any remaining
```

#### Step 3.2: Uninstall Exchange Server

Run Exchange Setup to uninstall:

```cmd
# Command Prompt (Administrator)
cd /d D:\ExchangeSetup  # Path to Exchange installation media
Setup.exe /mode:Uninstall /IAcceptExchangeServerLicenseTerms
```

Or via Control Panel:
1. **Control Panel** > **Programs and Features**
2. Select **Microsoft Exchange Server 2019**
3. Click **Uninstall**

#### Step 3.3: Verify AD Objects Removed

```powershell
# On-Premises PowerShell (AD Module)
# Check if Exchange containers are removed
Get-ADObject -Filter 'Name -like "*Exchange*"' -SearchBase "CN=Services,CN=Configuration,DC=contoso,DC=com"

# Check if Exchange Security Groups are removed
Get-ADGroup -Filter 'Name -like "*Exchange*"'
```

### Phase 4: Post-Uninstall Verification

#### Step 4.1: Verify LES Writeback Still Functions

This is the critical test - verify that Entra Cloud Sync writeback continues to work after Exchange uninstallation.

```powershell
# Exchange Online PowerShell
# Set a test attribute
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
Set-Mailbox -Identity TestUser -CustomAttribute13 "PostUninstallTest_$timestamp"
Write-Host "Set CustomAttribute13 = PostUninstallTest_$timestamp"
```

Wait for sync cycle (2-3 minutes), then verify:

```powershell
# On-Premises PowerShell (AD Module)
Get-ADUser -Identity TestUser -Properties extensionAttribute13 | Select-Object extensionAttribute13
# Should show: PostUninstallTest_[timestamp]
```

#### Step 4.2: Verify All 23 Writeback Attributes Function

```powershell
# Exchange Online PowerShell
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

Set-Mailbox -Identity TestUser `
    -CustomAttribute1 "Test1_$timestamp" `
    -CustomAttribute2 "Test2_$timestamp" `
    -ExtensionCustomAttribute1 "ExtTest1_$timestamp"

# Wait for sync, then verify in AD
```

```powershell
# On-Premises PowerShell (AD Module)
Get-ADUser -Identity TestUser -Properties extensionAttribute1, extensionAttribute2, msExchExtensionCustomAttribute1 |
    Select-Object extensionAttribute1, extensionAttribute2, msExchExtensionCustomAttribute1
```

#### Step 4.3: Verify Email Address Changes Writeback

```powershell
# Exchange Online PowerShell
Set-Mailbox -Identity TestUser -EmailAddresses @{Add="smtp:postuninstall@contoso.com"}

# Wait for sync, then verify in AD
```

```powershell
# On-Premises PowerShell (AD Module)
Get-ADUser -Identity TestUser -Properties proxyAddresses | Select-Object -ExpandProperty proxyAddresses
# Should include: smtp:postuninstall@contoso.com
```

---

## Test Cases for LES Verification After Exchange Removal

### Test Category 1: Basic Writeback Functionality

| Test ID | Test Name | Steps | Expected Result |
|---------|-----------|-------|-----------------|
| TC-1.1 | CustomAttribute Writeback | Set CustomAttribute1 in EXO | Value appears in AD extensionAttribute1 |
| TC-1.2 | ExtensionCustomAttribute Writeback | Set ExtensionCustomAttribute1 in EXO | Value appears in AD msExchExtensionCustomAttribute1 |
| TC-1.3 | Email Address Writeback | Add email address in EXO | Address appears in AD proxyAddresses |
| TC-1.4 | Mailbox Type Writeback | Change mailbox type (User → Shared) | msExchRecipientTypeDetails updated in AD |

### Test Category 2: All 23 Attributes Writeback

| Test ID | EXO Parameter | AD Attribute | Verify |
|---------|---------------|--------------|--------|
| TC-2.1 | CustomAttribute1 | extensionAttribute1 | Value syncs |
| TC-2.2 | CustomAttribute2 | extensionAttribute2 | Value syncs |
| TC-2.3 | CustomAttribute3 | extensionAttribute3 | Value syncs |
| TC-2.4 | CustomAttribute4 | extensionAttribute4 | Value syncs |
| TC-2.5 | CustomAttribute5 | extensionAttribute5 | Value syncs |
| TC-2.6 | CustomAttribute6 | extensionAttribute6 | Value syncs |
| TC-2.7 | CustomAttribute7 | extensionAttribute7 | Value syncs |
| TC-2.8 | CustomAttribute8 | extensionAttribute8 | Value syncs |
| TC-2.9 | CustomAttribute9 | extensionAttribute9 | Value syncs |
| TC-2.10 | CustomAttribute10 | extensionAttribute10 | Value syncs |
| TC-2.11 | CustomAttribute11 | extensionAttribute11 | Value syncs |
| TC-2.12 | CustomAttribute12 | extensionAttribute12 | Value syncs |
| TC-2.13 | CustomAttribute13 | extensionAttribute13 | Value syncs |
| TC-2.14 | CustomAttribute14 | extensionAttribute14 | Value syncs |
| TC-2.15 | CustomAttribute15 | extensionAttribute15 | Value syncs |
| TC-2.16 | ExtensionCustomAttribute1 | msExchExtensionCustomAttribute1 | Value syncs |
| TC-2.17 | ExtensionCustomAttribute2 | msExchExtensionCustomAttribute2 | Value syncs |
| TC-2.18 | ExtensionCustomAttribute3 | msExchExtensionCustomAttribute3 | Value syncs |
| TC-2.19 | ExtensionCustomAttribute4 | msExchExtensionCustomAttribute4 | Value syncs |
| TC-2.20 | ExtensionCustomAttribute5 | msExchExtensionCustomAttribute5 | Value syncs |
| TC-2.21 | EmailAddresses | proxyAddresses | Addresses sync |
| TC-2.22 | Type (Shared) | msExchRecipientTypeDetails | Type syncs |
| TC-2.23 | Type (Room) | msExchRecipientDisplayType | Type syncs |

### Test Category 3: Negative Tests

| Test ID | Test Name | Steps | Expected Result |
|---------|-----------|-------|-----------------|
| TC-3.1 | Non-Cloud-Managed User | Set attribute for user with `IsExchangeCloudManaged = False` | Error returned, attribute NOT written to AD |
| TC-3.2 | Cloud-Only User | Set attribute for user with `IsDirSynced = False` | No AD writeback (user not in AD) |
| TC-3.3 | Non-Writeback Attribute | Set ArchiveName in EXO | Value NOT written to AD |

### Test Category 4: Integration Tests

| Test ID | Test Name | Steps | Expected Result |
|---------|-----------|-------|-----------------|
| TC-4.1 | Mail Flow | Send email to/from cloud mailbox | Email delivered successfully |
| TC-4.2 | Free/Busy | Check calendar availability | Free/Busy works |
| TC-4.3 | New User Onboarding | Create AD user, sync, assign license, enable cloud management | User can be managed in EXO |
| TC-4.4 | User Offboarding | Set `IsExchangeCloudManaged = False`, verify on-prem SOA | On-prem becomes SOA again |

### Test Category 5: Recovery Tests

| Test ID | Test Name | Steps | Expected Result |
|---------|-----------|-------|-----------------|
| TC-5.1 | Entra Cloud Sync Agent Restart | Restart Cloud Sync agent | Writeback resumes after restart |
| TC-5.2 | LES Writeback Job Restart | Stop and start sync job | Writeback resumes |
| TC-5.3 | Network Interruption | Simulate network outage, restore | Writeback catches up |

### Test Category 6: Hypothesis Verification - LES After Exchange Uninstall

These tests validate the hypothesis that LES continues to function after Exchange Server is uninstalled. Tests cover both scenarios: **with writeback** and **without writeback**.

#### 6A: LES WITH Writeback - After Exchange Uninstall

| Test ID | Test Name | Prerequisites | Steps | Expected Result | Status |
|---------|-----------|---------------|-------|-----------------|--------|
| TC-6A.1 | Writeback After Uninstall | Exchange uninstalled, writeback configured | Set CustomAttribute1 in EXO, verify in AD | Value written to AD | To Test |
| TC-6A.2 | Entra Cloud Sync Status | Exchange uninstalled | Check Cloud Sync agent status in Entra portal | Agent Active, no errors | To Test |
| TC-6A.3 | LES Writeback Job Status | Exchange uninstalled | Query job via MSGraph API | Job Active/Running | To Test |
| TC-6A.4 | All 23 Attributes Writeback | Exchange uninstalled | Set all 23 writeback attributes, verify in AD | All values sync to AD | To Test |
| TC-6A.5 | New User Creation | Exchange uninstalled | Create AD user, sync to Entra, assign license, enable cloud mgmt, set attributes | User created, attributes written back to AD | To Test |
| TC-6A.6 | User Deletion | Exchange uninstalled | Delete user from AD, verify sync removes from Entra/EXO | User removed from Entra and EXO | To Test |
| TC-6A.7 | AD Container Verification | Exchange uninstalled | Query AD for Exchange containers | Containers removed, schema remains | To Test |

#### 6B: LES WITHOUT Writeback - After Exchange Uninstall

| Test ID | Test Name | Prerequisites | Steps | Expected Result | Status |
|---------|-----------|---------------|-------|-----------------|--------|
| TC-6B.1 | Cloud Management After Uninstall | Exchange uninstalled, NO writeback | Set CustomAttribute1 in EXO | Value accepted in EXO | To Test |
| TC-6B.2 | AD Not Updated (Expected) | Exchange uninstalled, NO writeback | Set attribute in EXO, check AD | AD value unchanged (expected) | To Test |
| TC-6B.3 | All EXO Operations Work | Exchange uninstalled, NO writeback | Set all Exchange attributes in EXO | All operations succeed | To Test |
| TC-6B.4 | New User Creation | Exchange uninstalled, NO writeback | Create AD user, sync to Entra, assign license, enable cloud mgmt, set attributes | User created in EXO, attributes set in EXO, AD not updated | To Test |
| TC-6B.5 | User Deletion | Exchange uninstalled, NO writeback | Delete user from AD, verify sync removes from Entra/EXO | User removed from Entra and EXO | To Test |
| TC-6B.6 | Email Address Management | Exchange uninstalled, NO writeback | Add/remove email addresses in EXO | Operations succeed, AD proxyAddresses unchanged | To Test |
| TC-6B.7 | Mailbox Type Change | Exchange uninstalled, NO writeback | Convert User → Shared in EXO | Conversion succeeds, AD msExchRecipientTypeDetails unchanged | To Test |

**Test Environment Requirements:**

| Environment | Writeback | Exchange State | Purpose |
|-------------|-----------|----------------|---------|
| Lab A | Configured | To be uninstalled | Test 6A scenarios |
| Lab B | NOT configured | To be uninstalled | Test 6B scenarios |

**Test Procedure:**

**For Lab A (With Writeback):**
1. **Baseline:** Verify LES writeback works with Exchange running
2. **Uninstall:** Uninstall Exchange Server
3. **Verify:** Verify writeback continues after uninstallation
4. **Extended Test:** Test all 23 attributes, new user provisioning

**For Lab B (Without Writeback):**
1. **Baseline:** Verify LES cloud management works with Exchange running (no writeback)
2. **Uninstall:** Uninstall Exchange Server
3. **Verify:** Verify cloud management continues after uninstallation
4. **Negative Test:** Verify AD is NOT updated (expected behavior without writeback)

**Documentation:** Record results in a test log with timestamps, screenshots, and any error messages.

---

## Comparison: EMT vs LES After Exchange Removal

| Capability | EMT (Shutdown Only) | LES (Uninstall Possible) |
|------------|---------------------|--------------------------|
| Exchange Server Status | Shut down, NOT uninstalled | Can be uninstalled |
| AD Container Dependency | Required | Not required |
| Management Interface | PowerShell snap-in (on-prem) | EXO Admin Center / PowerShell |
| Recipient Management | `Set-RemoteMailbox` | `Set-Mailbox` (EXO) |
| GUI Available | No | Yes (EXO Admin Center) |
| RBAC | Not functional | EXO RBAC |
| Audit Logging | Not available | EXO Audit Logs |
| Writeback to AD | N/A (AD is SOA) | Via Entra Cloud Sync |
| Recovery Path | Power on Exchange | Re-install Exchange + PrepareAD |

---

## Report Bugs

If you encounter bugs or unexpected behavior during Exchange uninstallation testing with the LES feature, please report to:

- **Mukesh**
- **Aditi**
- **Tristan**

### Information to Include in Bug Reports

| Information | Description |
|-------------|-------------|
| Test Case ID | Which test case failed (e.g., TC-6A.3) |
| Environment | Lab A (with writeback) or Lab B (without writeback) |
| Exchange Version | Exchange Server version before uninstallation |
| Cloud Sync Agent Version | Version number from agent properties |
| Steps to Reproduce | Exact steps taken |
| Expected Result | What should have happened |
| Actual Result | What actually happened |
| Error Messages | Full error text, screenshots |
| Timestamps | When the issue occurred |
| Provisioning Logs | Export from Entra Admin Center if applicable |

---

## Security Considerations

### Why Remove Exchange?

Keeping an unused Exchange Server poses security risks:

- **CVE vulnerabilities:** Exchange has been a frequent target (e.g., ProxyLogon, ProxyShell)
- **CISA Emergency Directives:** Organizations have been mandated to patch or shut down Exchange
- **Attack surface:** Even a "management only" server can be compromised
- **Maintenance burden:** Ongoing patching and updates required

### Post-Removal Security

After Exchange removal:

1. **Monitor Entra Cloud Sync** - Ensure writeback continues functioning
2. **Audit EXO changes** - Use Exchange Online audit logs for compliance
3. **Secure AD** - Exchange removal reduces AD attack surface
4. **Update documentation** - Reflect new management procedures

---

## References

### Microsoft Official Documentation

- [Enable Exchange Attributes Cloud Management](https://learn.microsoft.com/en-us/exchange/hybrid-deployment/enable-exchange-attributes-cloud-management) - LES feature documentation
- [Manage Hybrid Exchange Recipients with Management Tools](https://learn.microsoft.com/en-us/exchange/manage-hybrid-exchange-recipients-with-management-tools) - EMT documentation, CleanupActiveDirectoryEMT.ps1
- [Decommission On-Premises Exchange](https://learn.microsoft.com/en-us/exchange/decommission-on-premises-exchange) - Official decommissioning guidance

### Microsoft Community/Blog

- [Introducing Cloud-Managed Remote Mailboxes](https://techcommunity.microsoft.com/blog/exchange/introducing-cloud-managed-remote-mailboxes-a-step-to-last-exchange-server-retire/4446042) - LES feature announcement
- [Removing Your Last Exchange Server FAQ](https://techcommunity.microsoft.com/blog/exchange/removing-your-last-exchange-server-faq/3455411) - EMT FAQ, why not to uninstall

### Community Articles

- [Stages of AD Changes When Installing and Uninstalling Exchange](https://blog.rmilne.ca/2021/04/03/stages-of-ad-changes-when-installing-and-uninstalling-exchange/) - AD objects created/removed during install/uninstall
- [How IsExchangeCloudManaged Can Liberate You](https://www.mistercloudtech.com/2025/08/22/how-isexchangecloudmanaged-can-finally-liberate-you-from-the-last-exchange-server/) - LES feature analysis
- [The Last Exchange Server in the Organization](https://jaapwesselius.com/2025/08/25/the-last-exchange-server-in-the-organization/) - LES and AD dependencies
- [De-Hybridizing Exchange: Shut Off or Uninstall](https://www.checkyourlogs.net/de-hybridizing-exchange-to-shut-it-off-or-uninstall-pros-cons-and-workarounds/) - Pros/cons analysis

---

## Source Attribution for Key Claims

| Claim | Source | Type |
|-------|--------|------|
| Exchange uninstall removes CN=Microsoft Exchange container | [Removing Your Last Exchange Server FAQ](https://techcommunity.microsoft.com/blog/exchange/removing-your-last-exchange-server-faq/3455411) | Documented |
| Exchange uninstall removes CN=[OrgName] container | [Stages of AD Changes](https://blog.rmilne.ca/2021/04/03/stages-of-ad-changes-when-installing-and-uninstalling-exchange/) | Documented |
| Schema extensions persist after uninstall | [Stages of AD Changes](https://blog.rmilne.ca/2021/04/03/stages-of-ad-changes-when-installing-and-uninstalling-exchange/) | Documented |
| CleanupActiveDirectoryEMT.ps1 works WITH EMT | [Manage Hybrid Exchange Recipients](https://learn.microsoft.com/en-us/exchange/manage-hybrid-exchange-recipients-with-management-tools#active-directory-clean-up) | Documented |
| EMT breaks after Exchange uninstall | [Removing Your Last Exchange Server FAQ](https://techcommunity.microsoft.com/blog/exchange/removing-your-last-exchange-server-faq/3455411) | Documented |
| LES writeback uses Entra Cloud Sync | [Enable Exchange Attributes Cloud Management](https://learn.microsoft.com/en-us/exchange/hybrid-deployment/enable-exchange-attributes-cloud-management) | Documented |
| LES (no writeback) continues working after Exchange uninstall | N/A | **Hypothesis - Requires Testing (TC-6B)** |
| LES (with writeback) continues working after Exchange uninstall | N/A | **Hypothesis - Requires Testing (TC-6A)** |
| Entra Cloud Sync doesn't need Exchange AD containers | N/A | **Logical inference - Requires Testing** |
