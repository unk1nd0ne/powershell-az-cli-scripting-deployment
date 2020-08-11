# TODO: set variables
$studentName = "zac"
$projectId = "lc0820-ps"
$rgName = "$studentName-$projectId-rg"
$location = "eastus"
$vmName = "$studentName-$projectId-vm"
$vmSize = "Standard_B2s"
$vmImage = "$(az vm image list --query "[? contains(urn, 'Ubuntu')] | [0].urn")"
$vmAdminUsername = "student"
$kvName = "$studentName-$projectId-kv"
$kvSecretName = "ConnectionStrings--Default"
$kvSecretValue = "server=localhost;port=3306;database=coding_events;user=coding_events;password=launchcode"
$securityGroup = "$vmName" + "NSG"

$githubUser = "unk1nd0ne"
$codingEventsBranch = "3-aadb2c"

$workingDir = $PSScriptRoot
$codingEventsLocation = "C:\Users\sanha\Desktop\lc101\API\coding-events-api"
$CommitMessage = "Updated IP address and kv name"


# TODO: provision RG

az configure --default location=$location

az group create -n $rgName

az configure --default group=$rgName

# TODO: provision VM

az vm create -n $vmName --size $vmSize --image $vmImage --admin-username $vmAdminUsername --assign-identity

az configure --default vm=$vmName

# TODO: capture the VM systemAssignedIdentity

$vmInfo = az vm show -d | ConvertFrom-Json

$publicIp = $vmInfo.publicIps

$systemAssignedIdentity = $vmInfo.identity.principalId

# TODO: open vm port 443

az network nsg rule create --nsg-name $securityGroup --name Port_443_In --access allow --protocol "*" --direction Inbound --priority 200 --source-address-prefix "*" --source-port-range "*" --destination-address-prefix "*" --destination-port-range 443

# provision KV

az keyvault create -n $kvName --enable-soft-delete false --enabled-for-deployment true

az keyvault set-policy -n "$kvName" --object-id "$systemAssignedIdentity" --secret-permissions get list

# TODO: create KV secret (database connection string)

az keyvault secret set --vault-name "$kvName" -n "$kvSecretName" --value "$kvSecretValue"

# Configure CodingEventsAPI

Set-Location $codingEventsLocation

git checkout $codingEventsBranch

$appSettings = Get-Content CodingEventsAPI\appsettings.json | ConvertFrom-Json

$appSettings.ServerOrigin = "https://$publicIp"

$appSettings.KeyVaultName = $kvName

$appSettings | ConvertTo-Json | Set-Content CodingEventsAPI\appsettings.json

git add .

git commit -m "$CommitMessage"

git push

Set-Location $workingDir

# TODO: set KV access-policy (using the vm ``systemAssignedIdentity``)

$deployUserLine = Get-Content deliver-deploy.sh | Select-String "github_username=" | Select-Object -ExpandProperty Line
$deployBranchLine = Get-Content deliver-deploy.sh | Select-String "solution_branch=" | Select-Object -ExpandProperty Line
$deployScript = Get-Content deliver-deploy.sh

$deployScript = $deployScript | ForEach-Object {$_ -replace $deployUserLine,"github_username=$githubUser"}
$deployScript | ForEach-Object {$_ -replace $deployBranchLine,"solution_branch=$codingEventsBranch"} | Set-Content deliver-deploy.sh

az vm run-command invoke --command-id RunShellScript --scripts @vm-configuration-scripts/1configure-vm.sh

az vm run-command invoke --command-id RunShellScript --scripts @vm-configuration-scripts/2configure-ssl.sh

az vm run-command invoke --command-id RunShellScript --scripts @deliver-deploy.sh


# TODO: print VM public IP address to STDOUT or save it as a file
Write-Output $publicIp