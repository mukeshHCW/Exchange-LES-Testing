# Phase 2: Test Scenarios for LES Recipient Management with WriteBack

This document covers the enablement and testing of the Exchange Online Attribute Writeback feature for Last Exchange Server (LES) enabled mailboxes. This feature allows Exchange attributes modified in the cloud to be synchronized back to on-premises Active Directory.

---

## Overview

Cloud Sync LES Writeback enables customers to synchronize specific Exchange attributes from Exchange Online back to on-premises Active Directory. This is designed for directory-synchronized users who have had an LES Transfer performed, where:
- Object-level Source of Authority (SOA) remains in AD
- Attribute-level SOA for Exchange attributes is in Exchange Online/Entra ID

---

## Glossary

| Acronym | Full Name | Description |
|---------|-----------|-------------|
| LES | Last Exchange Server | Feature allowing customers to decommission their last on-premises Exchange server while maintaining hybrid functionality |
| SOA | Source of Authority | The authoritative source for an object or attribute - determines where changes should be made and synced from |
| POD | Provisioning On Demand | MSGraph API feature to trigger immediate sync for specific users without waiting for scheduled sync cycles |
| AD | Active Directory | Microsoft's on-premises directory service |
| gMSA | Group Managed Service Account | A managed domain account providing automatic password management for services |
| OU | Organizational Unit | A container in Active Directory used to organize objects |

---

## A. Detailed Steps to Enable the Writeback Feature

### Prerequisites (Assumed Already in Place)

| Prerequisite | Status |
|--------------|--------|
| Exchange Hybrid environment configured | Assumed |
| Microsoft Entra Connect Sync installed | Optional |
| Hybrid Identity Administrator role | Required |

### Required Permissions

- **Organization.ReadWrite.All** - For enabling organization sync
- **Directory.ReadWrite.All** - For directory operations
- **Hybrid Identity Administrator** - For Cloud Sync configuration
- **Exchange Online admin access** - For mailbox management

---

### A.1 Install Microsoft Entra Cloud Sync Provisioning Agent

#### A.1.1 Download the Provisioning Agent

1. Sign in to the [Microsoft Entra admin center](https://entra.microsoft.com) as a **Hybrid Identity Administrator**
2. Navigate to **Identity** > **Hybrid management** > **Microsoft Entra Connect** > **Cloud sync**
3. Select **Agents** from the left menu
4. Click **Download on-premises agent**
5. Select **Accept terms & download**
6. Save the file `AADConnectProvisioningAgentSetup.exe` to your downloads folder

![Download Agent](images/download-agent.png)
*Screenshot: Download on-premises agent from Entra Admin Center*

#### A.1.2 Install the Agent

1. Run `AADConnectProvisioningAgentSetup.exe` from your downloads folder
2. Check the **"I agree to the license terms and conditions"** checkbox
3. Select **Install**
4. Wait for installation to complete - the configuration wizard opens automatically

![Install Agent](images/license-terms.png)
*Screenshot: Agent installation wizard - License terms*

#### A.1.3 Configure Service Account (gMSA)

1. On the **Select Extension** screen, select:
   - **HR-driven provisioning (Workday and SuccessFactors) / Microsoft Entra Connect cloud sync**
2. Select **Next**
3. Sign in with your **Microsoft Entra Hybrid Identity Administrator** account
4. On the **Configure Service Account** screen:
   - Select **Create gMSA** (recommended) - creates `provAgentgMSA$` managed service account
   - OR select **Use custom gMSA** if you have a pre-created account
5. If creating gMSA, provide **Active Directory domain administrator credentials**
6. Select **Next**

![Configure gMSA](images/configure-gmsa.png)
*Screenshot: Configure service account options*

#### A.1.4 Connect Active Directory Domain

1. On the **Connect Active Directory** screen:
   - If your domain name appears under "Configured domains", skip to next step
   - Otherwise, enter your **Active Directory domain name**
2. Click **Add directory**
3. Sign in with your **Active Directory domain administrator account**
4. Select **OK**, then **Next**
5. On "Configuration complete" screen, select **Confirm**
6. Wait for agent registration and restart
7. Select **Exit** after verification notification

#### A.1.5 Verify Agent Installation

**In Azure Portal:**
1. Sign in to [Microsoft Entra admin center](https://entra.microsoft.com)
2. Navigate to **Identity** > **Hybrid management** > **Microsoft Entra Connect** > **Cloud sync**
3. Select **Agents**
4. Verify the agent appears with status **"Active"**

**On Local Server:**
1. Open **Services** (run `Services.msc`)
2. Verify both services are present and **Running**:
   - Microsoft Azure AD Connect Agent Updater
   - Microsoft Azure AD Connect Provisioning Agent

**Version Check:**
- Navigate to `C:\Program Files\Microsoft Azure AD Connect Provisioning Agent`
- Right-click `AADConnectProvisioningAgent.exe` > **Properties** > **Details**
- Verify version is **1.1.1107.0 or later** (required for Exchange hybrid writeback)

---

### A.2 Configure Cloud Sync

#### A.2.1 Create New Configuration

1. Sign in to [Microsoft Entra admin center](https://entra.microsoft.com) as **Hybrid Identity Administrator**
2. Navigate to **Identity** > **Hybrid management** > **Microsoft Entra Connect** > **Cloud sync**
3. Click **+ New configuration**

![New Configuration](images/configured-domains.png)
*Screenshot: Cloud Sync configuration with configured domains*

#### A.2.2 Select Sync Direction

1. Select **AD to Microsoft Entra ID sync**
2. On the configuration screen, select your domain
3. Enable **Password hash sync** (optional but recommended)
4. Click **Create**

![Configuration Settings](images/configure-1.png)
*Screenshot: Cloud Sync configuration settings*

#### A.2.3 Configure Scoping (Optional)

To restrict which AD objects receive synchronized changes:

**OU-based Scoping:**
1. In your Cloud Sync configuration, go to **Scoping filters**
2. Add distinguished names of OUs to include (e.g., `OU=CloudUsers,DC=contoso,DC=com`)

**Group-based Scoping:**
1. In your Cloud Sync configuration, go to **Scoping filters**
2. Add distinguished names of groups to include

---

### A.3 Enable LES Writeback via MSGraph API

LES Writeback is configured using Microsoft Graph API to create a service principal and synchronization job. This is different from the standard Exchange Hybrid Writeback checkbox in Cloud Sync.

> **Important - LES Writeback vs Exchange Hybrid Writeback:**
>
> | Feature | Exchange Hybrid Writeback (GA) | LES Writeback (This Document) |
> |---------|-------------------------------|-------------------------------|
> | Configuration Method | Checkbox in Cloud Sync UI | MSGraph API calls |
> | Application Template ID | N/A | `3b99513e-0cee-4291-aea8-84356239fb82` |
> | Job Template ID | N/A | `Entra2ADExchangeOnlineAttributeWriteback` |
> | Target Scenario | Standard hybrid writeback | LES-enabled mailboxes with cloud SOA for Exchange attributes |
>
> This document covers **LES Writeback** using the MSGraph API method, NOT the GA checkbox feature.

#### A.3.1 Connect to Microsoft Graph

Open PowerShell and connect with the required scopes:

```powershell
# MS Graph PowerShell
# Connect with required permissions
Connect-MgGraph -Scopes "Organization.ReadWrite.All"
Connect-MgGraph -Scopes "Directory.ReadWrite.All"
```

#### A.3.2 Enable Organization for Sync

```powershell
# MS Graph PowerShell
# Get organization ID and enable on-premises sync
$organizationId = (Get-MgOrganization).Id
$params = @{
    onPremisesSyncEnabled = $true
}
Update-MgOrganization -OrganizationId $organizationId -BodyParameter $params
```

#### A.3.3 Create Service Principal for LES Writeback

Create a service principal using the LES Writeback application template:

**Using MS Graph PowerShell:**
```powershell
# MS Graph PowerShell
# Application Template ID for Exchange Online Attribute Writeback
$body = @{
    displayName = "contoso.lab"  # Replace with your AD domain name
} | ConvertTo-Json

$response = Invoke-MgGraphRequest `
   -Method POST `
   -Uri "https://graph.microsoft.com/v1.0/applicationTemplates/3b99513e-0cee-4291-aea8-84356239fb82/instantiate" `
   -Body $body `
   -ContentType "application/json"

$response | ConvertTo-Json -Depth 10
```

**Using Graph Explorer:**
```
POST https://graph.microsoft.com/v1.0/applicationTemplates/3b99513e-0cee-4291-aea8-84356239fb82/instantiate
Content-type: application/json

{
    "displayName": "[your AD domain name here]"
}
```

> **Important:** Save the **Service Principal ID** from the response - you'll need it for subsequent steps.

#### A.3.4 Get Service Principal ID

```powershell
# MS Graph PowerShell
# Get the service principal ID (replace domain name with yours)
$servicePrincipalId = Get-MgServicePrincipal -Filter "displayName eq 'contoso.lab'" | Select-Object -ExpandProperty Id
$servicePrincipalId
```

#### A.3.5 Create Synchronization Job

**Using MS Graph PowerShell:**
```powershell
# MS Graph PowerShell
$body = @{
   templateId = "Entra2ADExchangeOnlineAttributeWriteback"
} | ConvertTo-Json -Depth 10

$response = Invoke-MgGraphRequest `
   -Method POST `
   -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalId/synchronization/jobs" `
   -Body $body `
   -ContentType "application/json"

$response | ConvertTo-Json -Depth 10
```

**Using Graph Explorer:**
```
POST https://graph.microsoft.com/v1.0/servicePrincipals/[SERVICE_PRINCIPAL_ID]/synchronization/jobs
Content-type: application/json

{
    "templateId": "Entra2ADExchangeOnlineAttributeWriteback"
}
```

> **Important:** Save the **Job ID** from the response for subsequent steps.

#### A.3.6 Verify Job Creation

```powershell
# MS Graph PowerShell
$response = Invoke-MgGraphRequest `
   -Method GET `
   -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs"

$response | ConvertTo-Json -Depth 10
```

Copy the Job ID from the output (format: `Entra2ADExchangeOnlineAttributeWriteback.[unique-id].[unique-id]`)

#### A.3.7 (Optional) Configure AD Scoping

To restrict which AD objects receive synchronized changes, modify the job schema:

**Step 1: Get the job schema:**
```powershell
# MS Graph PowerShell
$jobId = "your-job-id-here"  # Replace with your job ID

$schema = Invoke-MgGraphRequest `
   -Method GET `
   -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/schema"

$schema | ConvertTo-Json -Depth 10
```

**Step 2: Modify and update the schema with scoping:**

For **OU-based scoping**, add distinguished names to `includedContainers`:
```json
"containerFilter": {
    "includedContainers": [
        "OU=CloudUsers,DC=contoso,DC=lab",
        "OU=RemoteMailboxes,DC=contoso,DC=lab"
    ]
}
```

For **Group-based scoping**, add distinguished names to `includedGroups`:
```json
"groupFilter": {
    "includedGroups": [
        "CN=LESWritebackGroup,OU=Groups,DC=contoso,DC=lab"
    ]
}
```

**Step 3: Apply the modified schema:**
```powershell
# MS Graph PowerShell
$modifiedSchema = $schema  # After adding your scoping filters

$response = Invoke-MgGraphRequest `
   -Method PUT `
   -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/schema" `
   -Body ($modifiedSchema | ConvertTo-Json -Depth 10) `
   -ContentType "application/json"
```

#### A.3.8 Set Synchronization Job Secrets

Configure the on-premises AD domain name:

```powershell
# MS Graph PowerShell
$domainName = "contoso.lab"  # Replace with your AD domain name

$body = @{
    value = @(
        @{
            key   = "Domain"
            value = "{`"domain`":`"$domainName`"}"
        }
    )
} | ConvertTo-Json -Depth 5

$response = Invoke-MgGraphRequest `
   -Method PUT `
   -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/secrets" `
   -Body $body `
   -ContentType "application/json"
```

#### A.3.9 Start the Synchronization Job

```powershell
# MS Graph PowerShell
$response = Invoke-MgGraphRequest `
   -Method POST `
   -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/start" `
   -ContentType "application/json"
```

**Using Graph Explorer:**
```
POST https://graph.microsoft.com/v1.0/servicePrincipals/[SERVICE_PRINCIPAL_ID]/synchronization/jobs/[JOB_ID]/start
Content-type: application/json
{}
```

#### A.3.10 Verify Job Status

```powershell
# MS Graph PowerShell
$response = Invoke-MgGraphRequest `
   -Method GET `
   -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId"

$response | ConvertTo-Json -Depth 10
```

Look for `status.code` to be **Active** or **Running**.

---

### Job Management Operations

#### Stop the Synchronization Job

```powershell
# MS Graph PowerShell
Invoke-MgGraphRequest `
   -Method POST `
   -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/stop" `
   -ContentType "application/json"
```

#### Delete the Synchronization Job

```powershell
# MS Graph PowerShell
Invoke-MgGraphRequest `
   -Method DELETE `
   -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId"
```

---

### A.4 Verify LES Writeback Configuration

#### A.4.1 Enable Cloud Management for Test User

Before writeback can work, the test user must have Exchange attributes managed in the cloud:

```powershell
# Exchange Online PowerShell
# Connect to Exchange Online
Connect-ExchangeOnline

# Verify user exists
Get-Mailbox -ResultSize Unlimited | Select-Object Alias, DisplayName

# Enable cloud management for the user
Set-Mailbox -Identity <alias> -IsExchangeCloudManaged $true
```

#### A.4.2 Verify User Eligibility

```powershell
# Exchange Online PowerShell
Get-Mailbox -Identity <alias> | Select-Object DisplayName, IsDirSynced, RecipientType, IsExchangeCloudManaged
```

**Expected values:**
- `IsDirSynced = True`
- `RecipientType = UserMailbox`
- `IsExchangeCloudManaged = True`

#### A.4.3 Test Attribute Writeback

1. Modify an Exchange attribute in Exchange Online:
```powershell
# Exchange Online PowerShell
Set-Mailbox -Identity <alias> -CustomAttribute1 "TestValue_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
```

> **Note:** This tests CustomAttribute1. Testing of all 23 writeback attributes is covered in **Section B Test Scenarios**.

2. Wait for sync cycle (delta sync runs every ~2 minutes) or use **Provisioning On Demand (POD)**

**Using Provisioning On Demand (POD) for Immediate Sync:**

POD allows you to trigger an immediate sync for a specific user without waiting for the regular delta sync cycle. This is especially useful for:
- Testing writeback functionality
- Users moving into scope for the first time (who don't get provisioned during delta sync)

```powershell
# MS Graph PowerShell
# Trigger on-demand provisioning for a specific user
$userObjectId = "user-object-id-here"  # The Entra ID object ID of the user

$body = @{
    parameters = @(
        @{
            subjects = @(
                @{
                    objectId = $userObjectId
                    objectTypeName = "user"
                }
            )
            ruleId = "yourRuleId"  # Get from schema
        }
    )
} | ConvertTo-Json -Depth 10

$response = Invoke-MgGraphRequest `
   -Method POST `
   -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/provisionOnDemand" `
   -Body $body `
   -ContentType "application/json"

$response | ConvertTo-Json -Depth 10
```

> **Important:** Users moving into scope for the first time do NOT get provisioned during delta sync cycles (only initial sync cycles). Use **Provisioning On Demand (POD)** API calls to move these objects into scope during delta sync.

#### A.4.4 Verify Attributes in AD

**Method 1: Using Active Directory Users and Computers**
1. Open **Active Directory Users and Computers**
2. Enable **Advanced Features** (View > Advanced Features)
3. Navigate to the test user
4. Right-click > **Properties** > **Attribute Editor** tab
5. Verify `extensionAttribute1` contains the value set in Exchange Online

**Method 2: Using On-Premises Exchange Management Shell (Recommended)**

This is the ultimate verification - confirming the value is visible in Exchange Server:

```powershell
# On-Premises Exchange Management Shell
Get-RemoteMailbox -Identity <alias> | Select-Object CustomAttribute1, CustomAttribute2, ExtensionCustomAttribute1
```

**Expected Result:** The `CustomAttribute1` value should match what was set in Exchange Online.

---

### Attributes Written Back by Cloud Sync

| AD Attribute | Exchange Cmdlet Parameter | Description |
|--------------|---------------------------|-------------|
| extensionAttribute1 | CustomAttribute1 | Custom attribute 1 |
| extensionAttribute2 | CustomAttribute2 | Custom attribute 2 |
| extensionAttribute3 | CustomAttribute3 | Custom attribute 3 |
| extensionAttribute4 | CustomAttribute4 | Custom attribute 4 |
| extensionAttribute5 | CustomAttribute5 | Custom attribute 5 |
| extensionAttribute6 | CustomAttribute6 | Custom attribute 6 |
| extensionAttribute7 | CustomAttribute7 | Custom attribute 7 |
| extensionAttribute8 | CustomAttribute8 | Custom attribute 8 |
| extensionAttribute9 | CustomAttribute9 | Custom attribute 9 |
| extensionAttribute10 | CustomAttribute10 | Custom attribute 10 |
| extensionAttribute11 | CustomAttribute11 | Custom attribute 11 |
| extensionAttribute12 | CustomAttribute12 | Custom attribute 12 |
| extensionAttribute13 | CustomAttribute13 | Custom attribute 13 |
| extensionAttribute14 | CustomAttribute14 | Custom attribute 14 |
| extensionAttribute15 | CustomAttribute15 | Custom attribute 15 |
| msExchExtensionCustomAttribute1 | ExtensionCustomAttribute1 | Extended custom attribute 1 |
| msExchExtensionCustomAttribute2 | ExtensionCustomAttribute2 | Extended custom attribute 2 |
| msExchExtensionCustomAttribute3 | ExtensionCustomAttribute3 | Extended custom attribute 3 |
| msExchExtensionCustomAttribute4 | ExtensionCustomAttribute4 | Extended custom attribute 4 |
| msExchExtensionCustomAttribute5 | ExtensionCustomAttribute5 | Extended custom attribute 5 |
| msExchRecipientDisplayType | Type | Recipient display type |
| msExchRecipientTypeDetails | Type | Recipient type details |
| proxyAddresses | EmailAddresses, WindowsEmailAddress | Email proxy addresses |

---

### Important Warnings and Recommendations

> **Offboarding Warning:**
> Before migrating a mailbox back to on-premises, you **MUST** set `IsExchangeCloudManaged` to `$false`. Failure to do so may cause synchronization conflicts where cloud and on-premises values compete for authority.
>
> ```powershell
> # Exchange Online PowerShell
> # ALWAYS run this BEFORE migrating mailbox back on-premises
> Set-Mailbox -Identity <alias> -IsExchangeCloudManaged $false
> ```

> **Backup Before Rollback:**
> Before reverting SOA to on-premises (setting `IsExchangeCloudManaged = $false`), backup any cloud modifications that are not in the writeback scope. These non-writeback attributes will be overwritten by on-premises values during the next sync cycle. Export the mailbox properties first:
>
> ```powershell
> # Exchange Online PowerShell
> # Backup mailbox properties before rollback
> Get-Mailbox -Identity <alias> | Export-Csv -Path "MailboxBackup_$(Get-Date -Format 'yyyyMMdd').csv" -NoTypeInformation
> ```

---

### Troubleshooting Tips

> **Bug Reporting:** If you encounter bugs or unexpected behavior with the LES Writeback feature, please report to: **Mukesh**, **Aditi**, and **Tristan**.

| Issue | Resolution |
|-------|------------|
| Agent status not Active | Check Windows services are running; verify network connectivity; restart services if needed |
| Attributes not writing back | Verify user has `IsExchangeCloudManaged = True`; check provisioning logs |
| First-time users not syncing | Use Provisioning On Demand (POD) - delta sync only works after initial sync |
| Sync delays | Delta sync runs every ~2 minutes; use POD for immediate sync |
| Service Principal creation fails | Verify you have Organization.ReadWrite.All and Directory.ReadWrite.All permissions |
| Job creation fails | Verify Service Principal ID is correct; check template ID spelling |
| Job status shows error | Check job secrets (domain name); verify agent connectivity |

---

## B. Test Scenarios for Writeback Feature Evaluation

### Test Environment Requirements

| Component | Requirement |
|-----------|-------------|
| Exchange Hybrid | Configured and functional |
| Cloud Sync Agent | Version 1.1.1107.0 or later, Active status |
| LES Writeback Job | Service Principal created, Sync Job running (via MSGraph API) |
| Test Users | Directory-synced cloud mailboxes with `IsExchangeCloudManaged = True` |
| Exchange Online Module | Installed for PowerShell (`Install-Module ExchangeOnlineManagement`) |
| Microsoft Graph Module | Installed for PowerShell (`Install-Module Microsoft.Graph`) |

### Test Users and Groups

| User Type | Description | Example Alias |
|-----------|-------------|---------------|
| CU1, CU2, CU3 | Cloud-managed remote mailboxes (dir-synced) | CloudUser1, CloudUser2 |
| COU1, COU2 | Cloud-only mailboxes (not dir-synced) | CloudOnlyUser1 |

---

### Test Category 1: Prerequisites Validation

#### Test-1.1: Verify Cloud Sync Agent Installation

**Objective:** Confirm the Cloud Sync provisioning agent is properly installed and active.

**Prerequisites:** Cloud Sync agent installed on domain-joined server.

**Steps:**
1. Sign in to Microsoft Entra admin center
2. Navigate to **Identity** > **Hybrid management** > **Microsoft Entra Connect** > **Cloud sync**
3. Select **Agents**
4. Verify agent status

**Expected Results:**
- Agent appears in the list
- Status shows **"Active"**
- Last heartbeat is within the last few minutes

---

#### Test-1.2: Verify LES Writeback Job is Running

**Objective:** Confirm the LES Writeback synchronization job is created and running.

**Prerequisites:** LES Writeback configured via MSGraph API (Section A.3 completed).

**Steps:**
1. Connect to Microsoft Graph and check job status:
   ```powershell
   # MS Graph PowerShell
   # Connect to Microsoft Graph
   Connect-MgGraph -Scopes "Directory.ReadWrite.All"

   # Get the Service Principal ID (replace domain name with yours)
   $servicePrincipalId = Get-MgServicePrincipal -Filter "displayName eq 'contoso.lab'" | Select-Object -ExpandProperty Id

   # Check job status
   $response = Invoke-MgGraphRequest `
      -Method GET `
      -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs"
   $response | ConvertTo-Json -Depth 10
   ```

**Expected Results:**
- Job exists with template ID `Entra2ADExchangeOnlineAttributeWriteback`
- Job status shows **Active** or **Running**
- No error states in the job status

---

#### Test-1.3: Verify User Eligibility for Writeback

**Objective:** Confirm test user meets eligibility requirements for LES writeback.

**Prerequisites:** Test user CU1 exists as a dir-synced cloud mailbox.

**Steps:**
1. Connect to Exchange Online and verify the mailbox has Exchange attributes managed in the cloud:
   ```powershell
   # Exchange Online PowerShell
   # Connect to Exchange Online
   Connect-ExchangeOnline

   # Verify the mailbox has Exchange attributes managed in the cloud
   Get-Mailbox -Identity CU1 | Select-Object DisplayName, IsDirSynced, RecipientType, IsExchangeCloudManaged
   ```

**Expected Results:**
- `IsDirSynced = True`
- `RecipientType = UserMailbox`
- `IsExchangeCloudManaged = True`

---

### Test Category 2: LES Attribute Writeback Validation

#### Test-2.1: Writeback of CustomAttribute1-15 (extensionAttribute1-15)

**Objective:** Verify changes to all 15 CustomAttributes in Exchange Online are written back to corresponding extensionAttributes in AD.

**Prerequisites:**
- Test user CU1 with `IsExchangeCloudManaged = True`
- LES Writeback job running (Test-1.2 passed)

**Steps:**
1. Connect to Exchange Online PowerShell
2. Set all 15 custom attributes:
   ```powershell
   # Exchange Online PowerShell
   $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
   Set-Mailbox -Identity CU1 `
       -CustomAttribute1 "Test1_$timestamp" `
       -CustomAttribute2 "Test2_$timestamp" `
       -CustomAttribute3 "Test3_$timestamp" `
       -CustomAttribute4 "Test4_$timestamp" `
       -CustomAttribute5 "Test5_$timestamp" `
       -CustomAttribute6 "Test6_$timestamp" `
       -CustomAttribute7 "Test7_$timestamp" `
       -CustomAttribute8 "Test8_$timestamp" `
       -CustomAttribute9 "Test9_$timestamp" `
       -CustomAttribute10 "Test10_$timestamp" `
       -CustomAttribute11 "Test11_$timestamp" `
       -CustomAttribute12 "Test12_$timestamp" `
       -CustomAttribute13 "Test13_$timestamp" `
       -CustomAttribute14 "Test14_$timestamp" `
       -CustomAttribute15 "Test15_$timestamp"
   ```
3. Wait for sync cycle (up to 2 minutes) OR trigger on-demand provisioning
4. Verify in AD using Active Directory Users and Computers:
   - Navigate to user CU1 > **Properties** > **Attribute Editor**
   - Check `extensionAttribute1` through `extensionAttribute15`
5. Verify in On-Premises Exchange Management Shell:
   ```powershell
   # On-Premises Exchange Management Shell
   Get-RemoteMailbox -Identity CU1 | Select-Object CustomAttribute1, CustomAttribute2, CustomAttribute3, CustomAttribute4, CustomAttribute5, CustomAttribute6, CustomAttribute7, CustomAttribute8, CustomAttribute9, CustomAttribute10, CustomAttribute11, CustomAttribute12, CustomAttribute13, CustomAttribute14, CustomAttribute15
   ```

**Expected Results:**

| Exchange Online Parameter | AD Attribute | Expected Value |
|---------------------------|--------------|----------------|
| CustomAttribute1 | extensionAttribute1 | Test1_[timestamp] |
| CustomAttribute2 | extensionAttribute2 | Test2_[timestamp] |
| CustomAttribute3 | extensionAttribute3 | Test3_[timestamp] |
| CustomAttribute4 | extensionAttribute4 | Test4_[timestamp] |
| CustomAttribute5 | extensionAttribute5 | Test5_[timestamp] |
| CustomAttribute6 | extensionAttribute6 | Test6_[timestamp] |
| CustomAttribute7 | extensionAttribute7 | Test7_[timestamp] |
| CustomAttribute8 | extensionAttribute8 | Test8_[timestamp] |
| CustomAttribute9 | extensionAttribute9 | Test9_[timestamp] |
| CustomAttribute10 | extensionAttribute10 | Test10_[timestamp] |
| CustomAttribute11 | extensionAttribute11 | Test11_[timestamp] |
| CustomAttribute12 | extensionAttribute12 | Test12_[timestamp] |
| CustomAttribute13 | extensionAttribute13 | Test13_[timestamp] |
| CustomAttribute14 | extensionAttribute14 | Test14_[timestamp] |
| CustomAttribute15 | extensionAttribute15 | Test15_[timestamp] |

- All 15 attributes in AD contain the values set in Exchange Online
- Provisioning audit logs show successful writeback for all attributes

---

#### Test-2.2: Writeback of ExtensionCustomAttribute1-5 (msExchExtensionCustomAttribute1-5)

**Objective:** Verify changes to all 5 ExtensionCustomAttributes in Exchange Online are written back to corresponding msExchExtensionCustomAttributes in AD.

**Prerequisites:** Test user CU1 with `IsExchangeCloudManaged = True`

**Steps:**
1. Connect to Exchange Online PowerShell
2. Set all 5 extension custom attributes:
   ```powershell
   # Exchange Online PowerShell
   $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
   Set-Mailbox -Identity CU1 `
       -ExtensionCustomAttribute1 "ExtTest1_$timestamp" `
       -ExtensionCustomAttribute2 "ExtTest2_$timestamp" `
       -ExtensionCustomAttribute3 "ExtTest3_$timestamp" `
       -ExtensionCustomAttribute4 "ExtTest4_$timestamp" `
       -ExtensionCustomAttribute5 "ExtTest5_$timestamp"
   ```
3. Wait for sync cycle or trigger on-demand provisioning
4. Verify in AD using Active Directory Users and Computers:
   - Navigate to user CU1 > **Properties** > **Attribute Editor**
   - Check `msExchExtensionCustomAttribute1` through `msExchExtensionCustomAttribute5`
5. Verify in On-Premises Exchange Management Shell:
   ```powershell
   # On-Premises Exchange Management Shell
   Get-RemoteMailbox -Identity CU1 | Select-Object ExtensionCustomAttribute1, ExtensionCustomAttribute2, ExtensionCustomAttribute3, ExtensionCustomAttribute4, ExtensionCustomAttribute5
   ```

**Expected Results:**

| Exchange Online Parameter | AD Attribute | Expected Value |
|---------------------------|--------------|----------------|
| ExtensionCustomAttribute1 | msExchExtensionCustomAttribute1 | ExtTest1_[timestamp] |
| ExtensionCustomAttribute2 | msExchExtensionCustomAttribute2 | ExtTest2_[timestamp] |
| ExtensionCustomAttribute3 | msExchExtensionCustomAttribute3 | ExtTest3_[timestamp] |
| ExtensionCustomAttribute4 | msExchExtensionCustomAttribute4 | ExtTest4_[timestamp] |
| ExtensionCustomAttribute5 | msExchExtensionCustomAttribute5 | ExtTest5_[timestamp] |

- All 5 ExtensionCustomAttributes in AD contain the values set in Exchange Online
- Provisioning audit logs show successful writeback for all attributes

---

#### Test-2.3: Writeback of proxyAddresses (EmailAddresses)

**Objective:** Verify changes to email addresses are written back to AD.

**Prerequisites:** Test user CU1 with `IsExchangeCloudManaged = True`

**Steps:**
1. Connect to Exchange Online and add a new email address:
   ```powershell
   # Exchange Online PowerShell
   # Connect to Exchange Online
   Connect-ExchangeOnline

   # Add a new email address
   Set-Mailbox -Identity CU1 -EmailAddresses @{Add="smtp:testalias@contoso.com"}
   ```
2. Wait for sync cycle (up to 2 minutes) or trigger on-demand provisioning
3. Verify in AD using Active Directory Users and Computers:
   - Navigate to user CU1 > **Properties** > **Attribute Editor**
   - Check `proxyAddresses` attribute
4. Verify in On-Premises Exchange Management Shell:
   ```powershell
   # On-Premises Exchange Management Shell
   Get-RemoteMailbox -Identity CU1 | Select-Object EmailAddresses
   ```

**Expected Results:**
- New email address appears in `proxyAddresses` attribute in AD
- `Get-RemoteMailbox` shows the new email address in EmailAddresses
- Existing addresses are preserved

---

#### Test-2.4: Writeback of Multiple Attributes Simultaneously

**Objective:** Verify multiple attribute changes are written back correctly in a single sync.

**Prerequisites:** Test user CU1 with `IsExchangeCloudManaged = True`

**Steps:**
1. Connect to Exchange Online and set multiple attributes:
   ```powershell
   # Exchange Online PowerShell
   # Connect to Exchange Online
   Connect-ExchangeOnline

   # Set multiple attributes in a single command
   Set-Mailbox -Identity CU1 -CustomAttribute2 "MultiTest1" -CustomAttribute3 "MultiTest2" -ExtensionCustomAttribute2 "ExtMultiTest"
   ```
2. Wait for sync cycle (up to 2 minutes) or trigger on-demand provisioning
3. Verify in AD using Active Directory Users and Computers:
   - Navigate to user CU1 > **Properties** > **Attribute Editor**
   - Check `extensionAttribute2`, `extensionAttribute3`, and `msExchExtensionCustomAttribute2`
4. Verify in On-Premises Exchange Management Shell:
   ```powershell
   # On-Premises Exchange Management Shell
   Get-RemoteMailbox -Identity CU1 | Select-Object CustomAttribute2, CustomAttribute3, ExtensionCustomAttribute2
   ```

**Expected Results:**
- `extensionAttribute2` = "MultiTest1"
- `extensionAttribute3` = "MultiTest2"
- `msExchExtensionCustomAttribute2` = "ExtMultiTest"
- All attributes verified via `Get-RemoteMailbox` on-premises

---

#### Test-2.5: Writeback of Mailbox Type Change (RecipientTypeDetails)

**Objective:** Verify changes to mailbox type (User to Equipment, Shared, Room, etc.) are written back to AD via msExchRecipientTypeDetails attribute.

**Prerequisites:**
- Test user CU1 with `IsExchangeCloudManaged = True`
- User currently has a regular User mailbox

**Steps:**
1. Connect to Exchange Online PowerShell
2. Record current recipient type details:
   ```powershell
   # Exchange Online PowerShell
   Get-Mailbox -Identity CU1 | Select-Object DisplayName, RecipientTypeDetails
   ```
3. Convert mailbox to Shared mailbox:
   ```powershell
   # Exchange Online PowerShell
   Set-Mailbox -Identity CU1 -Type Shared
   ```
4. Wait for sync cycle or trigger on-demand provisioning
5. Verify in On-Premises Exchange Management Shell:
   ```powershell
   # On-Premises Exchange Management Shell
   Get-RemoteMailbox -Identity CU1 | Select-Object DisplayName, RecipientTypeDetails
   ```
6. Verify in AD Attribute Editor:
   - Check `msExchRecipientTypeDetails` and `msExchRecipientDisplayType` values

**Expected Results:**
- `msExchRecipientTypeDetails` in AD reflects the new mailbox type
- `msExchRecipientDisplayType` in AD is updated accordingly
- On-Premises Exchange shows the correct RecipientTypeDetails

**Additional Test Variations:**
| Conversion | Command | Expected msExchRecipientTypeDetails |
|------------|---------|-------------------------------------|
| User → Shared | `Set-Mailbox -Identity CU1 -Type Shared` | SharedMailbox |
| User → Room | `Set-Mailbox -Identity CU1 -Type Room` | RoomMailbox |
| User → Equipment | `Set-Mailbox -Identity CU1 -Type Equipment` | EquipmentMailbox |
| Shared → User | `Set-Mailbox -Identity CU1 -Type Regular` | UserMailbox |

---

### Test Category 3: Behavior When IsExchangeCloudManaged is False

This category tests the behavior when a user's `IsExchangeCloudManaged` property is set to `False`. In this state:
- Cloud-to-on-premises writeback should **NOT** occur
- On-premises values should become the source of authority and sync **TO** the cloud

#### Test-3.1: Verify Writeback Stops and On-Premises Becomes Source of Authority

**Objective:** Verify that when `IsExchangeCloudManaged = False`:
1. Changes made in Exchange Online are NOT written back to on-premises AD
2. On-premises AD becomes the source of authority
3. Changes made on-premises sync UP to Exchange Online

**Prerequisites:**
- Test user CU2 initially with `IsExchangeCloudManaged = True` (cloud-managed)
- LES Writeback job running

**Steps:**

**Part A: Disable Cloud Management**
1. Connect to Exchange Online PowerShell
2. Record current attribute values:
   ```powershell
   # Exchange Online PowerShell
   Get-Mailbox -Identity CU2 | Select-Object IsExchangeCloudManaged, CustomAttribute5, CustomAttribute6
   ```
3. Disable cloud management:
   ```powershell
   # Exchange Online PowerShell
   Set-Mailbox -Identity CU2 -IsExchangeCloudManaged $false
   ```
4. Verify the change:
   ```powershell
   # Exchange Online PowerShell
   Get-Mailbox -Identity CU2 | Select-Object IsExchangeCloudManaged
   ```

**Part B: Verify Limited Cloud Editing Capabilities**

When `IsExchangeCloudManaged = False`, only mailbox **Type** changes are allowed in Exchange Online. All other writeback attribute changes should result in an error.

1. **Verify attribute changes are blocked** - Attempt to change a custom attribute (should fail):
   ```powershell
   # Exchange Online PowerShell
   # This should return an ERROR because IsExchangeCloudManaged = False
   Set-Mailbox -Identity CU2 -CustomAttribute5 "CloudValue_ShouldFail"
   ```
   **Expected:** Error message indicating the attribute cannot be modified when cloud management is disabled.

2. **Verify mailbox type change is allowed** - Change the mailbox type (should succeed):
   ```powershell
   # Exchange Online PowerShell
   # This should SUCCEED - Type changes are allowed even when IsExchangeCloudManaged = False
   Set-Mailbox -Identity CU2 -Type Shared
   ```
   **Expected:** Command succeeds. Mailbox type is changed.

3. Wait for sync cycle (up to 5 minutes)

4. Verify mailbox type change synced to on-premises:
   ```powershell
   # On-Premises Exchange Management Shell
   Get-RemoteMailbox -Identity CU2 | Select-Object RecipientTypeDetails
   ```
   **Expected:** RecipientTypeDetails reflects the new type (SharedMailbox).

**Part C: Verify On-Premises Changes Sync TO Cloud**
1. Make a change on-premises in AD or Exchange Server:
   ```powershell
   # On-Premises Exchange Management Shell
   Set-RemoteMailbox -Identity CU2 -CustomAttribute6 "OnPremValue_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
   ```
2. Wait for Entra Connect Sync cycle (or force sync with `Start-ADSyncSyncCycle -PolicyType Delta`)
3. Check Exchange Online:
   ```powershell
   # Exchange Online PowerShell
   Get-Mailbox -Identity CU2 | Select-Object CustomAttribute5, CustomAttribute6
   ```

**Expected Results:**

| Test | Expected Outcome |
|------|------------------|
| Part A | `IsExchangeCloudManaged = False` |
| Part B | `CustomAttribute5` on-premises does NOT contain "CloudValue_ShouldNotSync" |
| Part B | Audit logs show operation was skipped (ImportSkipped event) |
| Part C | `CustomAttribute6` in Exchange Online contains the value set on-premises |
| Part C | On-premises is now source of authority for Exchange attributes |

---

#### Test-3.2: Non-Writeback Exchange Attribute Changes Do Not Sync to On-Premises

**Objective:** Verify that changes to Exchange attributes that are NOT in the writeback scope do NOT sync to on-premises AD.

**Prerequisites:**
- Test user CU1 with `IsExchangeCloudManaged = True`
- LES Writeback job running

**Background - Attribute Categories:**

There are three categories of attributes in LES:

| Category | SOA | Writeback | Examples |
|----------|-----|-----------|----------|
| **Identity Attributes** | Always on-premises | N/A (cannot edit in EXO) | DisplayName, Department, Title, givenName, sn |
| **Exchange Attributes (Writeback)** | Cloud when enabled | ✓ Yes | CustomAttribute1-15, ExtensionCustomAttribute1-5, proxyAddresses, msExchRecipientTypeDetails |
| **Exchange Attributes (Non-Writeback)** | Cloud when enabled | ✗ No | ArchiveName, RetentionComment, EnableModeration, ModeratedBy |

**Important:** This test focuses on **Exchange Non-Writeback** attributes - attributes that CAN be edited in Exchange Online but are NOT synced back to on-premises AD. Do not confuse with Identity attributes (like DisplayName) which cannot be edited in Exchange Online at all.

**Steps:**
1. Connect to Exchange Online PowerShell
2. Record current ArchiveName value:
   ```powershell
   # Exchange Online PowerShell
   Get-Mailbox -Identity CU1 | Select-Object ArchiveName
   ```
3. Record current on-premises ArchiveName (if archive exists):
   ```powershell
   # On-Premises Exchange Management Shell
   Get-RemoteMailbox -Identity CU1 | Select-Object ArchiveName
   ```
4. Change a non-writeback Exchange attribute in Exchange Online:
   ```powershell
   # Exchange Online PowerShell
   # Enable archive if not already enabled
   Enable-Mailbox -Identity CU1 -Archive

   # Set archive name (non-writeback Exchange attribute)
   Set-Mailbox -Identity CU1 -ArchiveName "CloudArchive_$(Get-Date -Format 'yyyyMMdd')"
   ```
5. Wait for multiple sync cycles (10+ minutes)
6. Check on-premises value:
   ```powershell
   # On-Premises Exchange Management Shell
   Get-RemoteMailbox -Identity CU1 | Select-Object ArchiveName
   ```

**Expected Results:**
- ArchiveName in Exchange Online is updated to "CloudArchive_[date]"
- ArchiveName on-premises remains UNCHANGED (or null if not previously set)
- Only the 23 writeback-scoped attributes are synced to on-premises
- Audit logs do NOT show any sync attempt for non-writeback attributes

**Additional Non-Writeback Exchange Attributes to Test:**
| Attribute | Exchange Online Command | Writeback? |
|-----------|-------------------------|------------|
| ArchiveName | `Set-Mailbox -ArchiveName "..."` | ✗ No |
| RetentionComment | `Set-Mailbox -RetentionComment "..."` | ✗ No |
| ModeratedBy | `Set-Mailbox -ModeratedBy "..."` | ✗ No |
| ModerationEnabled | `Set-Mailbox -ModerationEnabled $true` | ✗ No |

**Note:** Identity attributes (DisplayName, Department, Title, etc.) cannot be edited in Exchange Online at all - they must be modified in on-premises Active Directory.

---

#### Test-3.3: Object SOA Transfer - User Becomes Cloud-Only (IsDirSynced = False)

**Objective:** Verify the behavior when a user's full Object-level Source of Authority (SOA) is transferred to the cloud, making the user cloud-only (`IsDirSynced = False`). In this state, the user should move OUT of LES Writeback scope entirely.

**Background:** LES Writeback is designed for directory-synced users (`IsDirSynced = True`) where:
- Object-level SOA remains in AD
- Only attribute-level SOA for Exchange attributes is in the cloud

When a user becomes cloud-only (full object SOA transferred to cloud), they are no longer in scope for LES Writeback because there is no longer an AD object to write back to.

**Prerequisites:**
- Test user CU3 initially with:
  - `IsDirSynced = True`
  - `IsExchangeCloudManaged = True`
- LES Writeback job running and functional
- Entra Connect Sync configured

**Steps:**

**Part A: Verify Initial State (Dir-Synced with Writeback)**
1. Verify user is dir-synced and cloud-managed:
   ```powershell
   # Exchange Online PowerShell
   Get-Mailbox -Identity CU3 | Select-Object DisplayName, IsDirSynced, IsExchangeCloudManaged
   ```
2. Set a custom attribute and verify writeback works:
   ```powershell
   # Exchange Online PowerShell
   Set-Mailbox -Identity CU3 -CustomAttribute10 "BeforeSOATransfer_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
   ```
3. Wait for sync cycle and verify on-premises:
   ```powershell
   # On-Premises Exchange Management Shell
   Get-RemoteMailbox -Identity CU3 | Select-Object CustomAttribute10
   ```

**Part B: Transfer Object SOA to Cloud**

Reference: [Configure user source of authority](https://learn.microsoft.com/en-us/entra/identity/hybrid/how-to-user-source-of-authority-configure)

**Prerequisites for SOA Transfer:**
- Entra Connect Sync version **2.5.76.0+** or Cloud Sync version **1.1.1370.0+**
- **Hybrid Administrator** role
- **User-OnPremisesSyncBehavior.ReadWrite.All** scope permission

1. Get the user's Entra ID object ID:
   ```powershell
   # MS Graph PowerShell
   Connect-MgGraph -Scopes "User.Read.All"
   $user = Get-MgUser -Filter "userPrincipalName eq 'CU3@contoso.com'"
   $userId = $user.Id
   $userId
   ```

2. Check current SOA status (should be `false` = on-premises managed):
   ```powershell
   # MS Graph PowerShell
   $response = Invoke-MgGraphRequest `
      -Method GET `
      -Uri "https://graph.microsoft.com/v1.0/users/$userId/onPremisesSyncBehavior?`$select=isCloudManaged"
   $response | ConvertTo-Json
   ```

3. Transfer Object SOA to Cloud:
   ```powershell
   # MS Graph PowerShell
   Connect-MgGraph -Scopes "User-OnPremisesSyncBehavior.ReadWrite.All"

   $body = @{
       isCloudManaged = $true
   } | ConvertTo-Json

   Invoke-MgGraphRequest `
      -Method PATCH `
      -Uri "https://graph.microsoft.com/v1.0/users/$userId/onPremisesSyncBehavior" `
      -Body $body `
      -ContentType "application/json"
   ```

4. Validate the SOA transfer:
   ```powershell
   # MS Graph PowerShell
   $response = Invoke-MgGraphRequest `
      -Method GET `
      -Uri "https://graph.microsoft.com/v1.0/users/$userId/onPremisesSyncBehavior?`$select=isCloudManaged"
   $response | ConvertTo-Json
   ```
   **Expected:** `isCloudManaged = true`

5. Verify user is now cloud-managed:
   ```powershell
   # Exchange Online PowerShell
   Get-Mailbox -Identity CU3 | Select-Object DisplayName, IsDirSynced, IsExchangeCloudManaged
   ```

**Note:** After SOA transfer, the sync client will set `blockOnPremisesSync = true` on the AD object. Changes in on-premises AD will no longer sync to this user.

**Part C: Verify User is Out of Writeback Scope**
1. Make a change in Exchange Online:
   ```powershell
   # Exchange Online PowerShell
   Set-Mailbox -Identity CU3 -CustomAttribute10 "AfterSOATransfer_ShouldNotWriteBack"
   ```
2. Wait for sync cycle
3. Check provisioning logs for the user - should show user out of scope
4. Verify AD object (if it still exists) is NOT updated

**Expected Results:**

| Test | Expected Outcome |
|------|------------------|
| Part A | `IsDirSynced = True`, writeback functions normally |
| Part B | `IsDirSynced = False` after SOA transfer |
| Part C | User is OUT of LES Writeback scope |
| Part C | Provisioning logs show user skipped (out of scope) |
| Part C | No writeback occurs for cloud-only users |

**Key Insight:** When full Object SOA transfers to the cloud:
- User becomes cloud-only (`IsDirSynced = False`)
- User automatically moves OUT of LES Writeback scope
- `IsExchangeCloudManaged` property becomes irrelevant for writeback (no AD object to write to)
- This is different from Test-3.1 where `IsExchangeCloudManaged = False` but user is still dir-synced

---

### Test Category 4: Integration Tests

#### Test-4.1: Mail Flow After Enabling Writeback

**Objective:** Verify mail flow continues to work correctly with writeback enabled.

**Prerequisites:**
- Writeback enabled and functional
- Test users CU1 (cloud) and OP1 (on-prem)

**Steps:**
1. Send email from CU1 to OP1
2. Send email from OP1 to CU1
3. Send email from CU1 to external recipient
4. Receive email from external sender to CU1

**Expected Results:**
- All emails delivered successfully
- No NDRs or delivery delays
- Mail flow unaffected by writeback feature

---

#### Test-4.2: Free/Busy Lookup with Writeback Enabled

**Objective:** Verify Free/Busy functionality works correctly with writeback enabled.

**Prerequisites:**
- Writeback enabled
- Test users CU1 and OP1 with calendar items

**Steps:**
1. From CU1's mailbox, create a new meeting
2. Add OP1 as attendee
3. Check Free/Busy availability for OP1
4. Repeat in reverse: OP1 checking CU1's availability

**Expected Results:**
- Free/Busy information is correctly displayed
- Cross-premises calendar lookup functions normally

---

#### Test-4.3: Mailbox Migration with Writeback Active

**Objective:** Verify mailbox migration continues to work with writeback enabled.

**Prerequisites:**
- Writeback enabled
- On-premises mailbox OP2 ready for migration

**Steps:**
1. Connect to Exchange Online and initiate migration of OP2:
   ```powershell
   # Exchange Online PowerShell
   # Connect to Exchange Online
   Connect-ExchangeOnline

   # Initiate migration from on-premises to Exchange Online
   New-MoveRequest -Identity OP2 -Remote -RemoteHostName "mail.contoso.com" -TargetDeliveryDomain "contoso.mail.onmicrosoft.com"
   ```
2. Monitor migration progress until completion:
   ```powershell
   # Exchange Online PowerShell
   # Check move request status
   Get-MoveRequest -Identity OP2 | Select-Object DisplayName, Status, StatusDetail

   # Get detailed migration statistics
   Get-MoveRequestStatistics -Identity OP2 | Select-Object DisplayName, StatusDetail, PercentComplete
   ```
3. After migration completes (Status = Completed), enable cloud management and test writeback:
   ```powershell
   # Exchange Online PowerShell
   # Enable cloud management for the migrated mailbox
   Set-Mailbox -Identity OP2 -IsExchangeCloudManaged $true

   # Set a custom attribute to test writeback
   Set-Mailbox -Identity OP2 -CustomAttribute1 "MigrationTest_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
   ```
4. Wait for sync cycle (up to 2 minutes) or trigger on-demand provisioning
5. Verify writeback in On-Premises Exchange Management Shell:
   ```powershell
   # On-Premises Exchange Management Shell
   Get-RemoteMailbox -Identity OP2 | Select-Object CustomAttribute1
   ```

**Expected Results:**
- Migration completes successfully (Status = Completed, PercentComplete = 100)
- User can be enabled for cloud management (`IsExchangeCloudManaged = True`)
- Writeback functions correctly - CustomAttribute1 value synced to on-premises

---

### Test Category 5: Rollback and Disable Tests

#### Test-5.1: Stop LES Writeback Job

**Objective:** Verify the LES Writeback synchronization job can be stopped cleanly.

**Prerequisites:** LES Writeback job currently running and functional

**Steps:**
1. Connect to Microsoft Graph:
   ```powershell
   # MS Graph PowerShell
   Connect-MgGraph -Scopes "Directory.ReadWrite.All"
   ```
2. Get Service Principal and Job IDs:
   ```powershell
   # MS Graph PowerShell
   $servicePrincipalId = Get-MgServicePrincipal -Filter "displayName eq 'contoso.lab'" | Select-Object -ExpandProperty Id
   # Get job ID from previous configuration
   ```
3. Stop the synchronization job:
   ```powershell
   # MS Graph PowerShell
   Invoke-MgGraphRequest `
      -Method POST `
      -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/stop" `
      -ContentType "application/json"
   ```
4. Verify job status:
   ```powershell
   # MS Graph PowerShell
   $response = Invoke-MgGraphRequest `
      -Method GET `
      -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId"
   $response | ConvertTo-Json -Depth 10
   ```
5. Set a custom attribute for a test user:
   ```powershell
   # Exchange Online PowerShell
   Set-Mailbox -Identity CU1 -CustomAttribute8 "AfterJobStop"
   ```
6. Wait for what would be a sync cycle
7. Check AD attribute

**Expected Results:**
- Job status shows **Paused** or **Stopped**
- New attribute changes are NOT written to AD
- Existing AD attributes remain unchanged

---

#### Test-5.2: Restart LES Writeback Job

**Objective:** Verify the LES Writeback job can be restarted after being stopped.

**Prerequisites:** LES Writeback job previously stopped (Test-5.1)

**Steps:**
1. Restart the synchronization job:
   ```powershell
   # MS Graph PowerShell
   Invoke-MgGraphRequest `
      -Method POST `
      -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/start" `
      -ContentType "application/json"
   ```
2. Verify job status shows **Active** or **Running**
3. Set a custom attribute:
   ```powershell
   # Exchange Online PowerShell
   Set-Mailbox -Identity CU1 -CustomAttribute9 "AfterJobRestart"
   ```
4. Wait for sync cycle or trigger on-demand provisioning
5. Check AD attribute

**Expected Results:**
- Job status shows **Active** or **Running**
- New attribute changes ARE written to AD

---

#### Test-5.3: Delete LES Writeback Job

**Objective:** Verify the LES Writeback job can be completely deleted.

**Prerequisites:** LES Writeback job exists (stopped or running)

**Steps:**
1. Stop the job first (if running):
   ```powershell
   # MS Graph PowerShell
   Invoke-MgGraphRequest `
      -Method POST `
      -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/stop" `
      -ContentType "application/json"
   ```
2. Delete the synchronization job:
   ```powershell
   # MS Graph PowerShell
   Invoke-MgGraphRequest `
      -Method DELETE `
      -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId"
   ```
3. Verify job no longer exists:
   ```powershell
   # MS Graph PowerShell
   $response = Invoke-MgGraphRequest `
      -Method GET `
      -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs"
   $response | ConvertTo-Json -Depth 10
   ```

**Expected Results:**
- Job is deleted successfully
- Job no longer appears in the jobs list
- No writeback occurs for any users

---

#### Test-5.4: Revert User to On-Premises Management

**Objective:** Verify user can be reverted to on-premises management and writeback stops.

**Prerequisites:** Test user CU1 with `IsExchangeCloudManaged = True`

**Steps:**
1. Disable cloud management:
   ```powershell
   # Exchange Online PowerShell
   Set-Mailbox -Identity CU1 -IsExchangeCloudManaged $false
   ```
2. Verify setting:
   ```powershell
   # Exchange Online PowerShell
   Get-Mailbox -Identity CU1 | Select-Object IsExchangeCloudManaged
   ```
3. On-premises, modify the user's custom attribute in AD
4. Wait for sync cycle
5. Verify the on-premises value syncs to Exchange Online

**Expected Results:**
- `IsExchangeCloudManaged = False`
- On-premises AD becomes source of authority
- Changes made on-premises sync UP to Exchange Online
- Cloud changes no longer write back to AD

---

## References

- [Exchange hybrid writeback with Cloud Sync](https://learn.microsoft.com/en-us/entra/identity/hybrid/cloud-sync/exchange-hybrid)
- [Cloud-managed Exchange attributes](https://learn.microsoft.com/en-us/exchange/hybrid-deployment/enable-exchange-attributes-cloud-management)
- [Cloud Sync Prerequisites](https://learn.microsoft.com/en-us/entra/identity/hybrid/cloud-sync/how-to-prerequisites)
- [Provisioning Agent Installation](https://learn.microsoft.com/en-us/entra/identity/hybrid/cloud-sync/how-to-install)
- [Cloud Sync Configuration](https://learn.microsoft.com/en-us/entra/identity/hybrid/cloud-sync/how-to-configure)
