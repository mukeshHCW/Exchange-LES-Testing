# Phase 2: Test Scenarios for LES Recipient Management with WriteBack

This document covers the enablement and testing of the Exchange Online Attribute Writeback feature for Last Exchange Server (LES) enabled mailboxes. This feature allows Exchange attributes modified in the cloud to be synchronized back to on-premises Active Directory.

---

## A. Detailed Steps to Enable the Writeback Feature

### Overview

Cloud Sync LES Writeback enables customers to synchronize specific Exchange attributes from Exchange Online back to on-premises Active Directory. This is designed for directory-synchronized users who have had an LES Transfer performed, where:
- Object-level Source of Authority (SOA) remains in AD
- Attribute-level SOA for Exchange attributes is in Exchange Online/Entra ID

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

### Part 1: Install Microsoft Entra Cloud Sync Provisioning Agent

#### 1.1 Download the Provisioning Agent

1. Sign in to the [Microsoft Entra admin center](https://entra.microsoft.com) as a **Hybrid Identity Administrator**
2. Navigate to **Identity** > **Hybrid management** > **Microsoft Entra Connect** > **Cloud sync**
3. Select **Agents** from the left menu
4. Click **Download on-premises agent**
5. Select **Accept terms & download**
6. Save the file `AADConnectProvisioningAgentSetup.exe` to your downloads folder

![Download Agent](images/download-agent.png)
*Screenshot: Download on-premises agent from Entra Admin Center*

#### 1.2 Install the Agent

1. Run `AADConnectProvisioningAgentSetup.exe` from your downloads folder
2. Check the **"I agree to the license terms and conditions"** checkbox
3. Select **Install**
4. Wait for installation to complete - the configuration wizard opens automatically

![Install Agent](images/license-terms.png)
*Screenshot: Agent installation wizard - License terms*

#### 1.3 Configure Service Account (gMSA)

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

#### 1.4 Connect Active Directory Domain

1. On the **Connect Active Directory** screen:
   - If your domain name appears under "Configured domains", skip to next step
   - Otherwise, enter your **Active Directory domain name**
2. Click **Add directory**
3. Sign in with your **Active Directory domain administrator account**
4. Select **OK**, then **Next**
5. On "Configuration complete" screen, select **Confirm**
6. Wait for agent registration and restart
7. Select **Exit** after verification notification

#### 1.5 Verify Agent Installation

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

### Part 2: Configure Cloud Sync

#### 2.1 Create New Configuration

1. Sign in to [Microsoft Entra admin center](https://entra.microsoft.com) as **Hybrid Identity Administrator**
2. Navigate to **Identity** > **Hybrid management** > **Microsoft Entra Connect** > **Cloud sync**
3. Click **+ New configuration**

![New Configuration](images/configured-domains.png)
*Screenshot: Cloud Sync configuration with configured domains*

#### 2.2 Select Sync Direction

1. Select **AD to Microsoft Entra ID sync**
2. On the configuration screen, select your domain
3. Enable **Password hash sync** (optional but recommended)
4. Click **Create**

![Configuration Settings](images/configure-1.png)
*Screenshot: Cloud Sync configuration settings*

#### 2.3 Configure Scoping (Optional)

To restrict which AD objects receive synchronized changes:

**OU-based Scoping:**
1. In your Cloud Sync configuration, go to **Scoping filters**
2. Add distinguished names of OUs to include (e.g., `OU=CloudUsers,DC=contoso,DC=com`)

**Group-based Scoping:**
1. In your Cloud Sync configuration, go to **Scoping filters**
2. Add distinguished names of groups to include

---

### Part 3: Enable LES Writeback via MSGraph API

LES Writeback is configured using Microsoft Graph API to create a service principal and synchronization job. This is different from the standard Exchange Hybrid Writeback checkbox in Cloud Sync.

#### 3.1 Connect to Microsoft Graph

Open PowerShell and connect with the required scopes:

```powershell
# Connect with required permissions
Connect-MgGraph -Scopes "Organization.ReadWrite.All"
Connect-MgGraph -Scopes "Directory.ReadWrite.All"
```

#### 3.2 Enable Organization for Sync

```powershell
# Get organization ID and enable on-premises sync
$organizationId = (Get-MgOrganization).Id
$params = @{
    onPremisesSyncEnabled = $true
}
Update-MgOrganization -OrganizationId $organizationId -BodyParameter $params
```

#### 3.3 Create Service Principal for LES Writeback

Create a service principal using the LES Writeback application template:

**Using PowerShell:**
```powershell
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

#### 3.4 Get Service Principal ID

```powershell
# Get the service principal ID (replace domain name with yours)
$servicePrincipalId = Get-MgServicePrincipal -Filter "displayName eq 'contoso.lab'" | Select-Object -ExpandProperty Id
$servicePrincipalId
```

#### 3.5 Create Synchronization Job

**Using PowerShell:**
```powershell
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

#### 3.6 Verify Job Creation

```powershell
$response = Invoke-MgGraphRequest `
   -Method GET `
   -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs"

$response | ConvertTo-Json -Depth 10
```

Copy the Job ID from the output (format: `Entra2ADExchangeOnlineAttributeWriteback.[unique-id].[unique-id]`)

#### 3.7 (Optional) Configure AD Scoping

To restrict which AD objects receive synchronized changes, modify the job schema:

**Step 1: Get the job schema:**
```powershell
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
$modifiedSchema = $schema  # After adding your scoping filters

$response = Invoke-MgGraphRequest `
   -Method PUT `
   -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/schema" `
   -Body ($modifiedSchema | ConvertTo-Json -Depth 10) `
   -ContentType "application/json"
```

#### 3.8 Set Synchronization Job Secrets

Configure the on-premises AD domain name:

```powershell
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

#### 3.9 Start the Synchronization Job

```powershell
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

#### 3.10 Verify Job Status

```powershell
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
Invoke-MgGraphRequest `
   -Method POST `
   -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/stop" `
   -ContentType "application/json"
```

#### Delete the Synchronization Job

```powershell
Invoke-MgGraphRequest `
   -Method DELETE `
   -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId"
```

---

### Part 4: Verify LES Writeback Configuration

#### 4.1 Enable Cloud Management for Test User

Before writeback can work, the test user must have Exchange attributes managed in the cloud:

```powershell
# Connect to Exchange Online
Connect-ExchangeOnline

# Verify user exists
Get-Mailbox -ResultSize Unlimited | Select-Object Alias, DisplayName

# Enable cloud management for the user
Set-Mailbox -Identity <alias> -IsExchangeCloudManaged $true
```

#### 4.2 Verify User Eligibility

```powershell
Get-Mailbox -Identity <alias> | Select-Object DisplayName, IsDirSynced, RecipientType, IsExchangeCloudManaged
```

**Expected values:**
- `IsDirSynced = True`
- `RecipientType = UserMailbox`
- `IsExchangeCloudManaged = True`

#### 4.3 Test Attribute Writeback

1. Modify an Exchange attribute in Exchange Online:
```powershell
Set-Mailbox -Identity <alias> -CustomAttribute1 "TestValue_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
```

2. Wait for sync cycle (delta sync runs every ~2 minutes) or use **Provisioning On Demand**

> **Important:** Users moving into scope for the first time do NOT get provisioned during delta sync cycles (only initial sync cycles). Use **Provisioning On Demand (POD)** API calls to move these objects into scope during delta sync.

#### 4.4 Verify Attributes in AD

1. Open **Active Directory Users and Computers**
2. Enable **Advanced Features** (View > Advanced Features)
3. Navigate to the test user
4. Right-click > **Properties** > **Attribute Editor** tab
5. Verify `extensionAttribute1` contains the value set in Exchange Online

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

### Troubleshooting Tips

| Issue | Resolution |
|-------|------------|
| Service Principal creation fails | Verify you have Organization.ReadWrite.All and Directory.ReadWrite.All permissions |
| Job creation fails | Verify Service Principal ID is correct; check template ID spelling |
| Agent status not Active | Check Windows services are running; verify network connectivity |
| Attributes not writing back | Verify user has `IsExchangeCloudManaged = True`; check provisioning logs |
| First-time users not syncing | Use Provisioning On Demand (POD) - delta sync only works after initial sync |
| Sync delays | Delta sync runs every ~2 minutes; use POD for immediate sync |
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
| OP1, OP2 | On-premises mailboxes (not migrated) | OnPremUser1, OnPremUser2 |
| COU1, COU2 | Cloud-only mailboxes (not dir-synced) | CloudOnlyUser1 |

---

### Category 1: Prerequisites Validation

#### Scenario 1.1: Verify Cloud Sync Agent Installation

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

#### Scenario 1.2: Verify LES Writeback Job is Running

**Objective:** Confirm the LES Writeback synchronization job is created and running.

**Prerequisites:** LES Writeback configured via MSGraph API (Part 3 completed).

**Steps:**
1. Connect to Microsoft Graph:
   ```powershell
   Connect-MgGraph -Scopes "Directory.ReadWrite.All"
   ```
2. Get the Service Principal ID:
   ```powershell
   $servicePrincipalId = Get-MgServicePrincipal -Filter "displayName eq 'contoso.lab'" | Select-Object -ExpandProperty Id
   ```
3. Check job status:
   ```powershell
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

#### Scenario 1.3: Verify User Eligibility for Writeback

**Objective:** Confirm test user meets eligibility requirements for LES writeback.

**Prerequisites:** Test user CU1 exists as a dir-synced cloud mailbox.

**Steps:**
1. Connect to Exchange Online PowerShell:
   ```powershell
   Connect-ExchangeOnline
   ```
2. Run the following command:
   ```powershell
   Get-Mailbox -Identity CU1 | Select-Object DisplayName, IsDirSynced, RecipientType, IsExchangeCloudManaged
   ```

**Expected Results:**
- `IsDirSynced = True`
- `RecipientType = UserMailbox`
- `IsExchangeCloudManaged = True`

---

### Category 2: Attribute Writeback Validation

#### Scenario 2.1: Writeback of CustomAttribute (extensionAttribute)

**Objective:** Verify changes to CustomAttribute in Exchange Online are written back to AD.

**Prerequisites:**
- Test user CU1 with `IsExchangeCloudManaged = True`
- LES Writeback job running (Scenario 1.2 passed)

**Steps:**
1. Connect to Exchange Online PowerShell
2. Set a custom attribute:
   ```powershell
   Set-Mailbox -Identity CU1 -CustomAttribute1 "TestValue_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
   ```
3. Wait for sync cycle (up to 2 minutes) OR trigger on-demand provisioning
4. Open **Active Directory Users and Computers** on-premises
5. Navigate to user CU1 > **Properties** > **Attribute Editor**
6. Locate `extensionAttribute1`

**Expected Results:**
- `extensionAttribute1` in AD contains the value set in Exchange Online
- Provisioning audit logs show successful writeback

---

#### Scenario 2.2: Writeback of ExtensionCustomAttribute

**Objective:** Verify changes to ExtensionCustomAttribute are written back to AD.

**Prerequisites:** Test user CU1 with `IsExchangeCloudManaged = True`

**Steps:**
1. Connect to Exchange Online PowerShell
2. Set an extension custom attribute:
   ```powershell
   Set-Mailbox -Identity CU1 -ExtensionCustomAttribute1 "ExtTestValue_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
   ```
3. Wait for sync cycle or trigger on-demand provisioning
4. Check AD attribute `msExchExtensionCustomAttribute1` for user CU1

**Expected Results:**
- `msExchExtensionCustomAttribute1` in AD matches the value set in Exchange Online

---

#### Scenario 2.3: Writeback of proxyAddresses (EmailAddresses)

**Objective:** Verify changes to email addresses are written back to AD.

**Prerequisites:** Test user CU1 with `IsExchangeCloudManaged = True`

**Steps:**
1. Connect to Exchange Online PowerShell
2. Add a new email address:
   ```powershell
   Set-Mailbox -Identity CU1 -EmailAddresses @{Add="smtp:testalias@contoso.com"}
   ```
3. Wait for sync cycle or trigger on-demand provisioning
4. Check AD attribute `proxyAddresses` for user CU1

**Expected Results:**
- New email address appears in `proxyAddresses` attribute in AD
- Existing addresses are preserved

---

#### Scenario 2.4: Writeback of Multiple Attributes Simultaneously

**Objective:** Verify multiple attribute changes are written back correctly in a single sync.

**Prerequisites:** Test user CU1 with `IsExchangeCloudManaged = True`

**Steps:**
1. Connect to Exchange Online PowerShell
2. Set multiple attributes:
   ```powershell
   Set-Mailbox -Identity CU1 -CustomAttribute2 "MultiTest1" -CustomAttribute3 "MultiTest2" -ExtensionCustomAttribute2 "ExtMultiTest"
   ```
3. Wait for sync cycle or trigger on-demand provisioning
4. Verify all three attributes in AD

**Expected Results:**
- `extensionAttribute2` = "MultiTest1"
- `extensionAttribute3` = "MultiTest2"
- `msExchExtensionCustomAttribute2` = "ExtMultiTest"

---

### Category 3: Out-of-Scope Behavior Tests

#### Scenario 3.1: Writeback Skipped When IsExchangeCloudManaged is False

**Objective:** Verify attribute changes are NOT written back when user is not cloud-managed.

**Prerequisites:** Test user CU2 with `IsExchangeCloudManaged = False`

**Steps:**
1. Verify user status:
   ```powershell
   Get-Mailbox -Identity CU2 | Select-Object IsExchangeCloudManaged
   ```
2. Attempt to set a custom attribute:
   ```powershell
   Set-Mailbox -Identity CU2 -CustomAttribute5 "ShouldNotSync"
   ```
3. Wait for sync cycle
4. Check AD attribute `extensionAttribute5` for user CU2

**Expected Results:**
- `extensionAttribute5` in AD does NOT contain "ShouldNotSync"
- Audit logs show operation was skipped (ImportSkipped event)

---

#### Scenario 3.2: User Moves Out of Scope After SOA Transfer

**Objective:** Verify writeback stops when object-level SOA is transferred to cloud.

**Prerequisites:** Test user CU3 initially with attribute-level SOA in cloud

**Steps:**
1. Document current state of user CU3 in AD
2. Transfer object-level SOA to cloud (making user cloud-only)
3. Set a custom attribute in Exchange Online:
   ```powershell
   Set-Mailbox -Identity CU3 -CustomAttribute6 "AfterSOATransfer"
   ```
4. Wait for sync cycle
5. Check if attribute was written back to AD

**Expected Results:**
- User is now out of scope for LES writeback
- Attribute changes are NOT written to AD
- Audit logs reflect user is out of scope

---

#### Scenario 3.3: User Moves Back In Scope

**Objective:** Verify writeback resumes when user moves back in scope.

**Prerequisites:** Test user previously out of scope

**Steps:**
1. Enable cloud management for user:
   ```powershell
   Set-Mailbox -Identity CU2 -IsExchangeCloudManaged $true
   ```
2. Set a custom attribute:
   ```powershell
   Set-Mailbox -Identity CU2 -CustomAttribute7 "BackInScope"
   ```
3. Trigger on-demand provisioning or wait for sync cycle
4. Check AD attribute

**Expected Results:**
- `extensionAttribute7` in AD contains "BackInScope"
- Writeback is functioning for this user again

---

### Category 4: Integration Tests

#### Scenario 4.1: Mail Flow After Enabling Writeback

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

#### Scenario 4.2: Free/Busy Lookup with Writeback Enabled

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

#### Scenario 4.3: Mailbox Migration with Writeback Active

**Objective:** Verify mailbox migration continues to work with writeback enabled.

**Prerequisites:**
- Writeback enabled
- On-premises mailbox OP2 ready for migration

**Steps:**
1. Initiate migration of OP2 to Exchange Online:
   ```powershell
   New-MoveRequest -Identity OP2 -Remote -RemoteHostName "mail.contoso.com" -TargetDeliveryDomain "contoso.mail.onmicrosoft.com"
   ```
2. Monitor migration progress
3. After migration completes, enable cloud management:
   ```powershell
   Set-Mailbox -Identity OP2 -IsExchangeCloudManaged $true
   ```
4. Set a custom attribute and verify writeback

**Expected Results:**
- Migration completes successfully
- User can be enabled for cloud management
- Writeback functions correctly for newly migrated user

---

### Category 5: Rollback and Disable Tests

#### Scenario 5.1: Stop LES Writeback Job

**Objective:** Verify the LES Writeback synchronization job can be stopped cleanly.

**Prerequisites:** LES Writeback job currently running and functional

**Steps:**
1. Connect to Microsoft Graph:
   ```powershell
   Connect-MgGraph -Scopes "Directory.ReadWrite.All"
   ```
2. Get Service Principal and Job IDs:
   ```powershell
   $servicePrincipalId = Get-MgServicePrincipal -Filter "displayName eq 'contoso.lab'" | Select-Object -ExpandProperty Id
   # Get job ID from previous configuration
   ```
3. Stop the synchronization job:
   ```powershell
   Invoke-MgGraphRequest `
      -Method POST `
      -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/stop" `
      -ContentType "application/json"
   ```
4. Verify job status:
   ```powershell
   $response = Invoke-MgGraphRequest `
      -Method GET `
      -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId"
   $response | ConvertTo-Json -Depth 10
   ```
5. Set a custom attribute for a test user:
   ```powershell
   Set-Mailbox -Identity CU1 -CustomAttribute8 "AfterJobStop"
   ```
6. Wait for what would be a sync cycle
7. Check AD attribute

**Expected Results:**
- Job status shows **Paused** or **Stopped**
- New attribute changes are NOT written to AD
- Existing AD attributes remain unchanged

---

#### Scenario 5.2: Restart LES Writeback Job

**Objective:** Verify the LES Writeback job can be restarted after being stopped.

**Prerequisites:** LES Writeback job previously stopped (Scenario 5.1)

**Steps:**
1. Restart the synchronization job:
   ```powershell
   Invoke-MgGraphRequest `
      -Method POST `
      -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/start" `
      -ContentType "application/json"
   ```
2. Verify job status shows **Active** or **Running**
3. Set a custom attribute:
   ```powershell
   Set-Mailbox -Identity CU1 -CustomAttribute9 "AfterJobRestart"
   ```
4. Wait for sync cycle or trigger on-demand provisioning
5. Check AD attribute

**Expected Results:**
- Job status shows **Active** or **Running**
- New attribute changes ARE written to AD

---

#### Scenario 5.3: Delete LES Writeback Job

**Objective:** Verify the LES Writeback job can be completely deleted.

**Prerequisites:** LES Writeback job exists (stopped or running)

**Steps:**
1. Stop the job first (if running):
   ```powershell
   Invoke-MgGraphRequest `
      -Method POST `
      -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/stop" `
      -ContentType "application/json"
   ```
2. Delete the synchronization job:
   ```powershell
   Invoke-MgGraphRequest `
      -Method DELETE `
      -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId"
   ```
3. Verify job no longer exists:
   ```powershell
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

#### Scenario 5.4: Revert User to On-Premises Management

**Objective:** Verify user can be reverted to on-premises management and writeback stops.

**Prerequisites:** Test user CU1 with `IsExchangeCloudManaged = True`

**Steps:**
1. Disable cloud management:
   ```powershell
   Set-Mailbox -Identity CU1 -IsExchangeCloudManaged $false
   ```
2. Verify setting:
   ```powershell
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

### Monitoring and Audit Log Verification

#### Checking Provisioning Logs

1. Navigate to **Cloud sync** > select your configuration
2. Select **Provisioning logs** from the left menu
3. Filter by:
   - **Status:** Success, Failure, Skipped
   - **Action:** Create, Update, Delete
   - **Date range:** As needed

#### Key Events to Monitor

| Event Type | Description |
|------------|-------------|
| Success | Attribute successfully written back to AD |
| ImportSkipped | User out of scope (IsExchangeCloudManaged = False) |
| Failure | Writeback failed - check error details |
| SOA Violation | Attribute-level SOA conflict detected |

#### PowerShell for Audit Log Review

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "AuditLog.Read.All"

# Get recent provisioning logs
Get-MgAuditLogProvisioning -Filter "activityDateTime ge 2024-01-01" |
    Where-Object {$_.TargetSystem.DisplayName -eq "Active Directory"} |
    Select-Object ActivityDateTime, Action, ProvisioningStatusInfo
```

---

## References

- [Exchange hybrid writeback with Cloud Sync](https://learn.microsoft.com/en-us/entra/identity/hybrid/cloud-sync/exchange-hybrid)
- [Cloud-managed Exchange attributes](https://learn.microsoft.com/en-us/exchange/hybrid-deployment/enable-exchange-attributes-cloud-management)
- [Cloud Sync Prerequisites](https://learn.microsoft.com/en-us/entra/identity/hybrid/cloud-sync/how-to-prerequisites)
- [Provisioning Agent Installation](https://learn.microsoft.com/en-us/entra/identity/hybrid/cloud-sync/how-to-install)
- [Cloud Sync Configuration](https://learn.microsoft.com/en-us/entra/identity/hybrid/cloud-sync/how-to-configure)
