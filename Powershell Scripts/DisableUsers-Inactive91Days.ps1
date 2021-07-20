#requires -version 2

<#
.SYNOPSIS
Produces a report of Azure and OnPremise AD users and their last logon date, this script will also modify on premise AD if the $modifyAD flag is set to true

.DESCRIPTION
Run the script, it will output a report of all inactive users to a CSV file.

.OUTPUTS
The report outputs to CSV file.

inactiveTime is formatted to the local inactiveTimezone on the computer where the script was executed.

.EXAMPLE
.\GetInactiveUser-AZ-AD.ps1
.\GetInactiveUser-AZ-AD.ps1 -modifyAD (Will set the switch to true)

.NOTES
Requires AzureAD Module installed
You will need to have the required Microsoft Graph API permissions to run this script. 
According to this https://docs.microsoft.com/en-us/azure/active-directory/reports-monitoring/howto-manage-inactive-user-accounts you will need AuditLogs.Read.All, Organisation.Read.All
I recommend reviewing the report and verifing the items that will be changed based on the "TakeAction" Variable before enabling the modifyAD flag to ensure that nothing is disabled or moved that you do not want to move. 
You can also Adjust the $DAYS_INACTIVE variable to control the number of days that it checks for (Default 91)
Adjustments will obviously need to be made depending on your environment and naming conventions etc... 

.AUTHOR
    Keenan Louis
    Mark Recek - Connection and query of Microsoft Graph, Report Items along with some other code snippets 
    
.DATE
    04-17-2021 - Inital Version
#>

param (
    ###### WARNING #####
    # SET ONLY IF YOU WANT TO MOVE AND EDIT OBJECTS IN AD, VERIFY THE REPORT FIRST
    [switch] $modifyAD = $FALSE
    
)
# Warning message if modify AD is set
if ($modifyAD)
{
    write-host ("WARNING: Modify AD is set to $modifyAD") -ForegroundColor Cyan
    if ($(Read-Host ("Are you sure you want to conitnue? (Y/N)")).toLower() -ne "y")
    {
        exit
    }
}


# Capture start Time to log the runTime of the script
$Start = Get-Date
$date = Get-Date -Format "MM-dd-yyyy"

# List of exceptions by UserPrincipalName
$ACCOUNT_EXCEPTIONS = ""

#Group membership we're interested in
$AD_GROUPS = ""

### Constants ###

# These values will be specific to your environment
$DISABLED_USERS_OU = "OU=Disabled Users,DC=squawnet,DC=com"
$DISABLED_USERS_MAILBOX_ACCESS_OU = "OU=Disabled Users - Mailbox Access,DC=squawnet,DC=com"

# Days before last login
$DAYS_INACTIVE = 91 # Change this value to adjust inactive time. 

# Message that the user description in AD will change to
$DISABLED_MESSAGE = "Disabled $date due to inactivity"

# Date/time in UTC format
$DateTimeUtc = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")

# Date & CSV file name
$OutputFileName = $OutputFilePath + "Report-AZ-AD-UsersToDisable-" + $DateTimeUtc + ".csv"
$Report = New-Object System.Collections.ArrayList

# Azure AD Tenant ID
$TenantId = "bb43b24f-1139-4bd9-821c-6cebb99a16cf"

# Azure AD App 'Microsoft.Graph.API - IT Ops'. Find it in Azure AD. This app is configured for delegated access using a device code and Azure AD
$AppId_ITOps = ""

## Azure AD App 'Microsoft.Graph.API - MEGA'. Find it in Azure AD. The client secret is in IDStore under the name 'Microsoft.Graph.API - MEGA'
$AppId_MEGA = ""

# MS Graph resource Uri
$Resource = "https://graph.microsoft.com/"

# Azure Key Vault
$KeyVaultName = ""
$SecretName = ""

### Variables ###

# Calculate the inactiveTime filter
$inactiveTime = (Get-Date).Adddays(-($DAYS_INACTIVE))

# Get a list of all the DC's in the domain
$dcs = Get-ADDomainController -Filter {Name -like "*"}

# Connect to Microsoft Graph

function Get-MSGraphAuthHeader {
    param (
        [Parameter(Mandatory)]
        [string]
        $TenantId,
        [Parameter(Mandatory)]
        [string]
        $ClientId,
        [Parameter(Mandatory)]
        [string]
        $ClientSecret
    )
    # Create a hashtable for the body, the data needed for the token request
    # The variables used are explained above
    $Body = @{
        'tenant' = $TenantId
        'client_id' = $ClientId
        'scope' = 'https://graph.microsoft.com/.default'
        'client_secret' = $ClientSecret
        'grant_type' = 'client_credentials'
    }
    # Assemble a hashtable for splatting parameters, for readability
    # The tenant id is used in the uri of the request as well as the body
    $Params = @{
        'Uri' = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        'Method' = 'Post'
        'Body' = $Body
        'ContentType' = 'application/x-www-form-urlencoded'
    }
    try {
        $AuthResponse = Invoke-RestMethod @Params
    }
    catch {
        throw "Could not get authentication token. $($_.Exception.Message)"
    }
    $Headers = @{
        'Authorization' = "Bearer $($AuthResponse.access_token)"
    }
    return $Headers
}
function Get-AzureDeviceCodeToken {
    # Function created by Mark Recek, inspired by code found here: https://blog.simonw.se/getting-an-access-token-for-azuread-using-powershell-and-device-login-flow/
    [cmdletbinding()]
    param( 
        [Parameter(Mandatory)]
        $ClientID,
        [Parameter(Mandatory)]
        $TenantID,
        [Parameter()]
        $Resource = "https://graph.microsoft.com/",
        # Timeout in seconds to wait for user to complete sign in process
        [Parameter(DontShow)]
        $Timeout = 300
    )
    try {
        $DeviceCodeRequestParams = @{
            Method = 'POST'
            Uri    = "https://login.microsoftonline.com/$TenantId/oauth2/devicecode"
            Body   = @{
                resource  = $Resource
                client_id = $ClientId
            }
        }
        $DeviceCodeRequest = Invoke-RestMethod @DeviceCodeRequestParams

        Write-Host $DeviceCodeRequest.message -ForegroundColor Yellow

        $TokenRequestParams = @{
            Method = 'POST'
            Uri    = "https://login.microsoftonline.com/$TenantId/oauth2/token"
            Body   = @{
                grant_type = "urn:ietf:params:oauth:grant-type:device_code"
                code       = $DeviceCodeRequest.device_code
                client_id  = $ClientId
            }
        }
        $TimeoutTimer = [System.Diagnostics.Stopwatch]::StartNew()
        while ([string]::IsNullOrEmpty($TokenRequest.access_token)) {
            if ($TimeoutTimer.Elapsed.TotalSeconds -gt $Timeout) {
                throw 'Login timed out, please try again.'
            }
            $TokenRequest = try {
                Invoke-RestMethod @TokenRequestParams -ErrorAction Stop
            }
            catch {
                $Message = $_.ErrorDetails.Message | ConvertFrom-Json
                if ($Message.error -ne "authorization_pending") {
                    throw
                }
            }
            Start-Sleep -Seconds 1
        }
        Write-Output $TokenRequest.access_token
    } Catch {
        throw "Could not get a token using via a device code request. $($_.Exception.Message)"
    }
}

################
##### MAIN #####
################

# Connect to AzureAD Portal

# Tell the user they may be required to authenticate to the AzureAD module
Write-host "You may be asked for your Azure AD credentials twice" -ForegroundColor Yellow

# Check if connected to AzureAD, if not call the Connect-AzureAD command
try {
    Get-AzureADTenantDetail -ErrorAction Stop
} catch {
    if ($_.Exception.Message -ieq "You must call the Connect-AzureAD cmdlet before calling any other cmdlets.") {
        #Connect to Azure AD
        try {
            Connect-AzureAD -ErrorAction Stop
        } catch {
            throw $_.Exception.Message
        }
    } else {
        throw $_.Exception.Message
    }
}

# If the -ClientScretAuth switch is set ($true), then use get the client secret from Azure Key Vault
# and use it to authenticate using the 'Microsoft.Graph.API - MEGA' Azure app, otherwise authenticate
# the user using the Azure AD and device code method using the 'Microsoft.Graph.API - IT Ops' Azure app
IF ($ClientSecretAuth) {
    # Get the client scret from Azure Key Vault
    $Secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName
    $SsPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret.SecretValue)
    try {
        $SecretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($SsPtr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
    }

    # Set the headers for connecting to the Microsoft Graph
    $Headers = Get-MSGraphAuthHeader -TenantId $TenantId -ClientId $AppId_MEGA -ClientSecret $SecretValueText
} Else {
    # Get a token from Azure AD using the device code request method
    $Token = Get-AzureDeviceCodeToken -ClientID $AppId_ITOps -TenantID $TenantId -ErrorAction Stop

    # Set the headers for connecting to the Microsoft Graph
    $Headers = @{'Authorization' = "Bearer $Token" }
}

# Pull all users from the domain that meet the requirements:
#   Last sign on was prior to inactiveTime
#   Password last set is prior to inactiveTime
#   Account is currently enabled
#   Password is set to expire at some point
#   Account was created before inactiveTime
$inactiveADUsers = Get-ADUser -Filter {(passwordlastset -le $inactiveTime) -and (enabled -eq $True) -and (PasswordNeverExpires -eq $false) -and (whencreated -le $inactiveTime)} -Properties Name, ObjectGUID, DisplayName

# Request to run, this will get all users that haven't signed in since the inactive date. 

# There seems to be a bug with the graph API when using the Filter and select at the same time, but theoretically this should work. 
#$URIRequest = "https://graph.microsoft.com/beta/users?$filter=signInActivity/lastSignInDateTime le $inactiveTimeFormated&$select=displayName,userPrincipalName,accountEnabled,signInActivity,createdDateTime"

# hopefully this URI can be updated in the future to pull a more refined group of users increasing efficiency
$URIRequest = "https://graph.microsoft.com/beta/users?select=displayName,userPrincipalName,accountEnabled,signInActivity,createdDateTime"

# Query Microsoft Graph for all users in the tenant
Try {
    $GraphQueryResult = Invoke-RestMethod -Uri $URIRequest -Headers $Headers -ErrorAction Stop
} Catch {
    throw "Error querying Microsoft Graph. $($_.Exception.Message)"
}

# First populate the first query result (group of 100), then cycle through all remaining pages until complete
Write-host "Getting all the users in the Azure AD tenant from Microsoft Graph (used for pulling report data)..." -ForegroundColor Cyan

# Save the initial value from the result as the result
$graphQueryUsers = $graphQueryResult.value

# Print out the total number of users searched
Write-Host "Total users fetched so far:" $GraphQueryUsers.Count -ForegroundColor Gray

# Cycle through all the pages
while ($graphQueryResult.'@odata.nextLink') {
    # Get the next page of data
    $graphQueryResult = Invoke-RestMethod -Uri $graphQueryResult.'@odata.nextLink' -Headers $Headers

    # Add the value of this page to the result
    $GraphQueryUsers += $graphQueryResult.value

    # Print out the total number of users searched
    Write-Host "Total users fetched so far:" $GraphQueryUsers.Count -ForegroundColor Gray
}

# Status Message
Write-host "Microsft Graph user fetching is complete. Total users fetched via Microsoft Graph:" $GraphQueryUsers.Count -ForegroundColor Gray

# Convert the array to a generic list to make it quicker to search through the data in the ForEach loops
$GraphyQueryUsersGeneric = [Collections.Generic.List[Object]]($GraphQueryUsers)

# Cycle through each user in the List of inactive AD Users
forEach ($ADUser in $inactiveADUsers)
{
    Write-Host("Checking $($ADUser.Name)...") -ForegroundColor Gray

    # Reset Variables
    $UserDisplayName = $ADUser.DisplayName
    $OU = "N/A"
    $groupMembership = ""
    $LastSigninDateTime = "N/A"
    $UserLastAZLogon = "N/A"
    $CreatedDateTime = "N/A"
    $UserCreatedDate = "N/A"
    $UserExists = $False
    $TakeAction = $False
    $teamsOnly = $False
    $lastLoginTime = 0
    $exception = $false

    # Check the exception list
    if (!($ACCOUNT_EXCEPTIONS.contains($ADUser.UserPrincipalName)))
    {
        # Search each DC for the most updated timestamp because the LastLogin attribute is not synced between DC's
        ForEach ($dc in $dcs)
        {   
            # Get the AD User data from each DC
            $ADUser = Get-AdUser $ADUser.objectGUID | Get-ADObject -Server $dc.hostname -Properties Name, LastLogon, ObjectGUID, DistinguishedName, UserPrincipalName, DisplayName

            # Check if the new time is greater than the old value
            if (($null -ne $ADUser.lastLogon) -and ($ADUser.lastLogon -gt $lastLoginTime))
            {
                # Update the Last Login Time
                $lastLoginTime = $ADUser.lastLogon
            }
        }

        # Convert the time to a DateTime object
        $lastADLogon = [DateTime]::FromFileTime($lastLoginTime)
        
        # Check that the time is less than the specified days inactive
        if ($lastADLogon -le $inactiveTime)
        {
            $TakeAction = $True

            # Find the index value of the current $User in the array of all users pulled from MS Graph
            ## a -1 value means the user provided was not found inthe MS Graph list
            $Index = $GraphyQueryUsersGeneric.FindIndex({$args[0].userPrincipalName -eq $ADUser.UserPrincipalName})
            
            # Check if User Exists in Azure
            If (!($Index -eq -1) -and ($null -ne $Index) -and ($Index -ne ""))
            {
                # Populate user values from the MS Graph generic list array
                $UserExists = $True
                $UserDisplayName = $GraphyQueryUsersGeneric[$Index].displayName
                $LastSigninDateTime = $GraphyQueryUsersGeneric[$Index].SignInActivity.lastSignInDateTime
                $CreatedDateTime = $GraphyQueryUsersGeneric[$Index].createdDateTime

                # This will get the date from the createDateTime value and then format it into a datetime object of a specific format
                $UserCreatedDate = [datetime]::parseexact($(Get-Date -Date $CreatedDateTime -Format "yyyy-MM-dd HH:mm"), 'yyyy-MM-dd HH:mm', $null)
                
                # Check if the user ever signed in
                If (!$LastSigninDateTime -or $LastSigninDateTime -eq "") 
                {
                    
                    $UserLastAZLogon = "Never Signed In"

                    # Check if the account was created before the inactiveTime Specified
                    if ($UserCreatedDate -ge $inactiveTime)
                    {
                        # The user is active, do nothing
                        $TakeAction = $False
                    }
                } 
                Else # User has signed into Azure
                {
                    # Gets the date string and converts it to a dateTime object so we can compare dates later
                    $UserLastAZLogon = [datetime]::parseexact($(Get-Date -Date $LastSigninDateTime -Format "yyyy-MM-dd HH:mm"), 'yyyy-MM-dd HH:mm', $null)

                    # Check if the user has signed in after the inactiveTime Specified
                    if (($UserLastAZLogon -gt $inactiveTime))
                    {
                        # The user is active, do nothing
                        $TakeAction = $False
                    }
                }
            } 

            # Check if we should still do something to the account based on previous activity checks
            if ($TakeAction)
            {
                #Grab group membership for user and output if they are a member of any groups requiring account removal
	            $membership = Get-ADPrincipalGroupMembership $ADUser.objectGUID | select-object -ExpandProperty name

	            foreach ($group in $AD_GROUPS) 
                {
                    if ($membership -contains $group) 
                    {
                        $groupMembership += "$group;"
                    }     
                }

                if ($modifyAD)
                {
                    # Disabled the user
                    Disable-ADAccount -Identity $ADuser.ObjectGUID
                }

                # Check if the user exists in AD or if it is a Teams Only based on naming conventions
                if (!$userExists -or ($ADUser.Name.ToLower().contains("teams") -AND $ADUser.Name.ToLower().contains("only")) -OR ($ADUser.DisplayName.ToLower().contains("teams") -and $ADUser.DisplayName.ToLower().contains("only")))
                {
                    # Set Teams Only Flag
                    if (!$userExists)
                    {
                        $teamsOnly = $False 
                    }
                    else {
                        $teamsOnly = $True 
                    }
                    
                    # Update this value with the OU specific to your environment
                    $OU = "Disabled Users"

                    # Move the user to the disabled user OU if it isn't already
                    if ($ADUser.DistinguishedName -ne "CN=$($ADUser.Name),OU=Disabled Users,DC=squawnet,DC=com") # Edit this to be the location of your Disabled Users OU
                    {  
                        # Check if user ever logged in
                        if (($lastADLogon -eq "") -OR ($lastADLogon -eq "12/31/1600 16:00:00") -OR ($lastADLogon -eq "12/31/1600 4:00:00 PM")) # Default Values if user never logged in
                        {
                            $lastADLogon = "Never Logged In"

                            if ($modifyAD)
                            {
                                # Update the description of the user
                                Set-ADUser -Identity $ADUser.ObjectGUID -Description $DISABLED_MESSAGE
                            }
                        }
                        else 
                        {
                            if ($modifyAD)
                            {
                                # Update the description of the user
                                Set-ADUser -Identity $ADUser.ObjectGUID -Description "$DISABLED_MESSAGE | Last Logon - $lastADLogon"
                            }
                        }

                        if ($modifyAD)
                        {
                            # Move the computer to the Disabled User OU
                            Move-ADObject -Identity $ADUser.ObjectGUID -TargetPath $DISABLED_USERS_OU
                        }
                    }   
                }
                Else
                {    
                    # Update this value with the OU specific to your environment
                    $OU = "Disabled Users - Mailbox Enabled"

                    # Move the user to the disabled user - mailbox enabled OU if it isn't already
                    if ($ADUser.DistinguishedName -ne "CN=$($ADUser.Name),OU=Disabled Users - Mailbox Access,DC=squawnet,DC=com") # Edit this to be the location of your Mailbox access OU
                    {    
                        # User never Logged in
                        if (($lastADLogon -eq "") -OR ($lastADLogon -eq "12/31/1600 16:00:00") -OR ($lastADLogon -eq "12/31/1600 4:00:00 PM"))
                        {
                            $lastADLogon = "Never Logged In"

                            if ($modifyAD)
                            {
                                # Update the description of the user
                                Set-ADUser -Identity $ADUser.ObjectGUID -Description $DISABLED_MESSAGE
                            }
                        }
                        else 
                        { 
                            if ($modifyAD)
                            {
                                # Update the description of the user
                                Set-ADUser -Identity $ADUser.ObjectGUID -Description "$DISABLED_MESSAGE | Last Logon - $lastADLogon"  
                            } 
                        }
                
                        if ($modifyAD)
                        {
                            # Move the computer to the Disabled User OU
                            Move-ADObject -Identity $ADUser.ObjectGUID -TargetPath $DISABLED_USERS_MAILBOX_ACCESS_OU
                        }
                    }   
                }            
            }
        }
    }
    else # Item is an exception but still add it to the report 
    {
       $exception = $true
    }
    if ($takeAction)
    {
        if ($exception)
        {
            $takeAction = "Exception"
        }

        # Populate the data for the row
        $ObjectProperties = [Ordered]@{
            "Action Taken" = $takeAction
            "UPN" = $ADUser.UserPrincipalName
            "Display Name" = $UserDisplayName
            "Last Azure Logon" = $UserLastAZLogon
            "Last AD Logon" = $lastADLogon
            "Azure Creation Date" = $UserCreatedDate
            "AD Group Membership" = $groupMembership
            "OU Moved To" = $OU
            "Teams Only" = $teamsOnly
            "User Exists in Azure AD?" = $UserExists
        }
        # Create PSObject and add the ObjectProperties data
        $Row = New-Object -TypeName PSObject -Property $ObjectProperties
    
        # Add the user's details to the array for the report data
        [void]$Report.Add($Row)
    }
}

# Output the report to a CSV file
Write-host "Writing the CSV file..." -ForegroundColor Cyan
$Report | Export-Csv $OutputFileName -Force -NoTypeInformation
$OutputFileName_Resolved = Resolve-Path $OutputFileName
Write-Host "================================================================" -ForegroundColor Gray
Write-Host "Report outputed to: $OutputFileName_Resolved" -ForegroundColor Cyan

# Write the runtime of the script
$End = Get-Date
Write-Output "Total minutes of runtime:" ($End - $Start).TotalMinutes

# Clean-up session
Get-PSSession | Remove-PSSession