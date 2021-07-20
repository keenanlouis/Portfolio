################################################################################################################################################################

# File:         Get-Group-Members.ps1
# Author:       Keenan Louis
# Date:         4/16/2020
# Description   This Script will get all groups and return a list of members and their associated group in a formatted csv file

################################################################################################################################################################

class O365Group{

}
    param ([String]$objectID)

    [String]getMembers()
    {
        return Get-UnifiedGroupLinks -Identity $objectID -LinkType Members | foreach {$_.Name}
    }

    [String]getOwners()
    {
        return Get-UnifiedGroupLinks -Identity $objectID -LinkType Owners | foreach {$_.Name}
    }

    [String]getName()
    {
        return Get-UnifiedGroup -Identity $objectID | ForEach-Object{$_.DisplayName}
    }

    [String]getAlias()
    {
        return Get-UnifiedGroup -Identity $objectID | ForEach-Object{$_.Name}
    }

    [String]getObjectID()
    {
        return $objectID
    }

    [String]getGroupType()
    {
        return Get-UnifiedGroup -Identity $objectID| ForEach-Object{$_.GroupType}
    }
}