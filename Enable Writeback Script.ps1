Connect-MgGraph -Scopes "Organization.ReadWrite.All" 
Connect-MgGraph -Scopes "Directory.ReadWrite.All"



$organizationId = (Get-MgOrganization).Id
$params = @{
	onPremisesSyncEnabled = $true
}
Update-MgOrganization -OrganizationId $organizationId -BodyParameter $params

##   1.	Create a service principal for the Exchange Online Attribute Writeback application by making the following MSGraph request on Graph PowerShell

$response = Invoke-MgGraphRequest `
   -Method POST `
   -Uri "https://graph.microsoft.com/v1.0/applicationTemplates/3b99513e-0cee-4291-aea8-84356239fb82/instantiate" `
   -Body $body `
   -ContentType "application/json"

$response | ConvertTo-Json -Depth 10

#Command to get service principal details
$servicePrincipalId = Get-MgServicePrincipal -Filter "displayName eq 'contoso.lab'" | Select-Object -ExpandProperty Id

$servicePrincipalId | ConvertTo-Json -Depth 10

## $servicePrincipalId = "4746fa4c-a724-4a85-b9b6-0d94f94d1713"

##   2.	Using the service principal ID created above, create a synchronization job by making the following MSGraph request:

$servicePrincipalId #to print the service principal ID stored above, if incorrect rerun previous command to get correct ID

$body = @{
   templateId = "Entra2ADExchangeOnlineAttributeWriteback"
} | ConvertTo-Json -Depth 10

$response = Invoke-MgGraphRequest `
   -Method POST `
   -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalId/synchronization/jobs" `
   -Body $body `
   -ContentType "application/json"

$response | ConvertTo-Json -Depth 10

##  3. Verify that the synchronization job was created successfully by making the following MSGraph request:
$response = Invoke-MgGraphRequest `
   -Method GET `
   -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs"

$response | ConvertTo-Json -Depth 10

## copy jobid from output for next steps

$jobId = "Entra2ADExchangeOnlineAttributeWriteback.59f22ce2214e453c91f06c6524112779.6e95dd52-4e52-4f66-b951-5e8430c98507" #replace with your job ID from previous step

##4. Optional: Configure Active Directory (AD) scoping for your job by manually editing the job’s schema. 
## This will restrict the set of AD objects to which changes are synchronized from Exchange Online. 

##4.1 First, get the job’s schema by making the following MSGraph request:

$schema = Invoke-MgGraphRequest `
   -Method GET `
   -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/schema"

$schema | ConvertTo-Json -Depth 10

##4.2 Next, modify the schema to include scoping filters.
#modify the schema received from previous step to include scoping filters as per your requirement

$modifiedSchema = $schema

$response = Invoke-MgGraphRequest `
   -Method PUT `
   -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/schema" `
   -Body ($modifiedSchema | ConvertTo-Json -Depth 10) `
   -ContentType "application/json"


## 5. Set the synchronization job’s secrets, including the domain name of your on-premises Active Directory, by making the following MSGraph request:

$domainName = "contoso.lab" 

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

##6. Start the Job

$response = Invoke-MgGraphRequest `
             -Method POST `
             -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/start" `
             -ContentType "application/json"


##Verify job status
$response = Invoke-MgGraphRequest `
			 -Method GET `
			 -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId"

##7. Stop the Job:*
Invoke-MgGraphRequest `
             -Method POST `
             -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId/stop" `
             -ContentType "application/json"

##8. Delete the job:
$jobId = "Entra2ADExchangeOnlineAttributeWriteback.59f22ce2214e453c91f06c6524112779.6e95dd52-4e52-4f66-b951-5e8430c98507" #replace with your job ID from previous step
$response = Invoke-MgGraphRequest `
             -Method DELETE `
             -Uri "https://graph.microsoft.com/beta/servicePrincipals/$servicePrincipalId/synchronization/jobs/$jobId"















