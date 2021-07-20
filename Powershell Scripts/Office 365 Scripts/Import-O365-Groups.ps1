################################################################################################################################################################

# File:         Import-O365-Groups.ps1
# Author:       Keenan Louis
# Date:         3/25/2020
# Description   This script will take the contents of a CSV and create a Distribution List with the contents

################################################################################################################################################################

$groupPath = "C:\PowerShell-Export\OldGroups.csv"

Import-CSV $groupPath | ForEach-Object{
    $userlist = Get-AzureADGroupMember -ObjectID $_.ObjectID
}




Import-CSV $groupPath | ForEach-Object{
    # Create normal O365 Groups
    if ($_.GroupType -eq "Universal")
    {
        # Split memeber and owner list into individual users
        $members = $_.Members.split(",")
        $owners = $_.ManagedBy.split(" ")

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
        
        # Add Users
        For ($i=0; $i -lt $members.Count; $i++) 
        {
            Add-UnifiedGroupLinks -Identity $_.Alias -LinkType Members -Links $members[$i]
        }

        # Set Owners
        For ($i=0; $i -lt $owners.Count; $i++) 
        {
            Add-UnifiedGroupLinks -Identity $_.Alias -LinkType Owners -Links $owners[$i]
        }

        #Remove Migration Account from the group
        Remove-UnifiedGroupLinks -Identity $_.Alias –LinkType Owners -Links "emailAccount" -Confirm:$false
        Remove-UnifiedGroupLinks -Identity $_.Alias –LinkType Members -Links "emailAccount" -Confirm:$false
    }
}



    # Create Distribution Lists
    if ($_.GroupType -eq "Distribution")
    {
        if ($_.MangaedBy -eq "")
        {
            New-DistributionGroup -Name $_.DisplayName -PrimarySMTPAddress $_.PrimarySMTPAddress -Notes $_.Notes 
        }
        else  
        {
            New-DistributionGroup -Name $_.DisplayName -ManagedBy $_.ManagedBy -PrimarySMTPAddress $_.primarySMTPAddress -Notes $_.Notes
        }
    }
    
    # Create Teams Groups
    if ($_.GroupType -eq "Teams")
    {
        New-Team -DisplayName $_.DisplayName -Alias $_.Alias -AccessType $_.AccessType -PrimarySMTPAddress $_.primarySMTPAddress -Notes $_.Notes
    }

    