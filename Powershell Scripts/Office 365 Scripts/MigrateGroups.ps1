################################################################################################################################################################

# File:         Get-GroupData.ps1
# Author:       Keenan Louis
# Date:         4/16/2020
# Description   This Script will get all groups and return a list of members and their associated group in a formatted csv file

################################################################################################################################################################

$newGroups = 0
$newTeams = 0
$NTGroupData | foreach-Object{
    if ($_.ResourceProvisioningOptions -eq "Team")
    {
        $newTeams++
    }
    else{
        $newGroups++
    }
}
$OldGroups = 0
$OldTeams = 0
$OTGroupData | foreach-Object{
    if ($_.ResourceProvisioningOptions -eq "Team")
    {
        $OldTeams++
    }
    else{
        $OldGroups++
    }
}


$newGroups
$OldGroups




# Cycle through each old group
$difference = 0
$OTGroupData | Foreach-Object{
	$objAlias = $_.Alias
            # Don't migrate teams
            if ($_.ResourceProvisioningOptions -eq "Team")
            {
                # Count Number of Team accounts skipped
                $teamCount--
            }
            # is not a team therefore migrate it
            else 
            {
                # Create Group only if its not already Created
		Write-Host ($_.Alias)
                if (-not ($NTGroupData.Alias.contains($_.Alias)))
                {
			$difference++

		}
	    }
	}
$difference


$script = {
    #Main-function
    function main {
        # UI Items
        $OTCreds = Get-Credential -Message "Please enter your credentials for the Old O365 Tenant"
        $NTCreds = Get-Credential -Message "Please enter your credentials for the New O365 Tenant"

        $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $OTcreds -Authentication Basic -AllowRedirection
        Import-PSSession $Session -DisableNameChecking 
        Connect-AzureAD -Credential $OTCreds
    
        # Constants (Change this to make a different account default owner)
        $defaultOwner = "useraccount@email.com"
        
        # Decalre Variables
        $distMembers = @{}
        $distOwners = @{}
        $OTGroupMembers = @{}
        $OTGroupOwners = @{}
        $teamCount = 0
        $groupCount = 0
        $distListCount = 0
        $orphanedGroups = @()
        
        # Get and store Unified-Group data
        $OTGroupData = Get-UnifiedGroup
        $OTGroupData | Foreach-Object{
            #Write-Host $OTGroupData
            if ($_.ResourceProvisioningOptions -eq "Team")
            {
                # Count Number of Team accounts skipped
                $teamCount++
            }
            else
            {
                $members = getMembers -alias $_.Name -groupType "Universal"
                $owners = getowners -alias $_.Name -grouptype "Universal"
                $OTGroupMembers.add($_.Alias, $members)
                $OTGroupOwners.add($_.Alias, $owners)
                $groupCount++

                if ($OTGroupOwners[$_.Alias].Count -eq 0)
                {
                    $orphanedGroups += $_.Alias
                }
            }
        }

        # Get distribution lists and me
        $OTDistGroupData = Get-DistributionGroup
        $OTDistGroupData | Foreach-Object{
            $members = getMembers -alias $_.Name -groupType "Distribution"
            $owners = getowners -alias $_.Name -grouptype "Distribution"
            $distMembers.add($_.Alias, $members)
            $distowners.add($_.Alias, $owners)
            $distListCount++
        }

        Remove-PSSession $Session

        # Connect to New Tenant Session
        $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $NTcreds -Authentication Basic -AllowRedirection
        Import-PSSession $Session -DisableNameChecking 
        Connect-AzureAD -Credential $NTCreds

        # Get Existing New Tenant Data
        $NTGroupData = Get-UnifiedGroup

        # Cycle through each old group
        $OTGroupData | Foreach-Object{
            $objAlias = $_.Alias
            # Don't migrate teams
            if ($_.ResourceProvisioningOptions -eq "Team")
            {
                # Count Number of Team accounts skipped
                $teamCount--
            }
            # is not a team therefore migrate it
            else 
            {
                # Create Group
                New-UnifiedGroup -DisplayName $_.DisplayName -Alias  $_.Alias -AccessType $_.AccessType -Notes $_.Notes
                # Changet some of the settings depending on values
                if ($_.AutoSubscribeNewMembers -eq "FALSE")
                {
                    Set-UnifiedGroup -Identity $_.Alias -AutoSubscribenewMembers:$false
                }
                if ($_.AlwaysSubscribeMembersToCalendarEvents -eq "FALSE")
                {
                    Set-UnifiedGroup -Identity $_.Alias -AlwaysSubscribeMembersToCalendarEvents:$false
                }
                if ($_.RequireSenderAuthenticationEnabled -eq "FALSE")
                {
                    Set-UnifiedGroup -Identity $_.Alias -RequireSenderAuthenticationEnabled:$false
                }
                if ($_.RequireSenderAuthenticationEnabled -eq "TRUE")
                {
                    Set-UnifiedGroup -Identity $_.Alias -RequireSenderAuthenticationEnabled:$true
                }
                
                if ($OTGroupMembers[$_.Alias].count -ne 0)
                {
                    # Get the members for the current Group
                    $OTGroupMembers[$_.Alias] | Foreach-Object{
                        # Cycle Through Each Member
                        $_ | Foreach-Object{
                            # Add the member to the group
                            addMember -objAlias $objAlias -userID $_
                        }      
                    }
                }
                
                # Set Owners if there are owners (Must be completed after the members are already added)
                if ($OTGroupOwners[$_.Alias].count -eq 0)
                {
                    addMember -objAlias $objAlias -userID $defaultOwner
                    addOwner -objAlias $objAlias -userID $defaultOwner
                }
                else
                {
                    # Get the Owners for the current group
                    $OTGroupOwners[$_.Alias] | Foreach-Object{
                        $_ | Foreach-Object{
                            # Add the Owners to the group
                            addOwner -objAlias $objAlias -userID $_
                        }      
                    }
                }

                # Try to remove Migration Account from the group 
                removeOwner -objAlias $objAlias -userID $NTCreds.UserName
                removeMember -objAlias $objAlias -userID $NTCreds.UserName
            }
        }

        # Get Distribution list data from the new tenant
        $NTDistGroupData = Get-DistributionGroup

        $OTDistGroupData | Foreach-Object{
            # Store Group Alias
            $objAlias = $_.Alias

            # Check if the group is already created
            if (-not ($NTDistGroupData.Alias.contains($_.Alias)))
            {
                # Create the Group
                New-DistributionGroup -Name $_.DisplayName -PrimarySMTPAddress $_.primarySMTPAddress -Notes $_.Notes
            }
        
            # Add Members to the group
            if ($distMembers[$objAlias].count -ne 0)
            {
                $distMembers[$_.Alias] | ForEach-Object{
                    Add-DistributionGroupMember -Identity $objAlias -Member $_
                }
            }
            # Add Owners to the group
            if ($distOwners[$_.Alias].count -ne 0)
            {
                $distOwners[$_.Alias] | ForEach-Object{
                    Set-DistributionGroup -Identity $objAlias -ManagedBy $_
                }
            }      
        }

        Remove-PSSession $NTSession

        if ($teamCount -ne 0)
        {
            write-Host "Error, the teams do not match ... Check Tenant"
        }
    }

    function connectToOfficeAdmin(){
        param ($credentials)

        $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $credentials -Authentication Basic -AllowRedirection
        Import-PSSession $Session -DisableNameChecking
        Connect-AzureAD -Confirm 
    
        return $Session
    }
    
    function getMembers(){        
        param($alias, $groupType)
        $members = @()
        
        if ($groupType -eq "Distribution")
        {

            $members = Get-DistributionGroupMember -Identity $alias | Foreach-Object{$_.Name}
        }
        elseif ($groupType -eq "Universal")
        {
            $members = Get-UnifiedGroupLinks -Identity $alias -LinkType Members | Foreach-Object{$_.Name}
        }
        elseif ($groupType -eq "Teams")
        {
            # Do Nothing
        }

        return $members

    }
    
    function getOwners(){
        param ([String]$Alias,[String]$groupType)

        $owners = @()
        if ($groupType -eq "Distribution")
        {
            $owners =  Get-DistributionGroup -Identity $Alias | Foreach-Object{$_.ManagedBy}
        }
        elseif ($groupType -eq "Universal")
        {
            $owners =  Get-UnifiedGroupLinks -Identity $Alias -LinkType Owners | Foreach-Object{$_.Name}
        }
        elseif ($groupType -eq "Teams")
        {
            # Do Nothing
        }
        return $owners
    }
    
    function addMember(){
        param ([String]$objAlias,[String]$userID)

        Add-UnifiedGroupLinks -Identity $objAlias -LinkType Members -Links $userID
    }

    function addOwner(){
        param ([String]$objAlias,[String]$userID)

        Add-UnifiedGroupLinks -Identity $objAlias -LinkType Owners -Links $userID
    }

    function removeMember(){
        param ([String]$objAlias,[String]$userID)

        Remove-UnifiedGroupLinks -Identity $objAlias –LinkType Members -Links $userID -Confirm:$false
    }

    function removeOwner(){
        param ([String]$objAlias,[String]$userID)

        Remove-UnifiedGroupLinks -Identity $objAlias –LinkType Owners -Links $userID -Confirm:$false
    }

    function disconnectSession() {
        param ($session)
        Remove-PSSession $Session
    }


    #Entry point
    main
}

Invoke-Command -Scriptblock $script