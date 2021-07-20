$script{
    ############################ CONNECT TO OLD TENANT POWERSHELL ############################
    
    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $creds -Authentication Basic -AllowRedirection
    Import-PSSession $Session -DisableNameChecking 

    # CSVPATHS
    $GroupDATAPath = "C:\PowerShell-Export\CogitativoData\GoDaddyGroupData.csv"
    $UserDATAPath = "C:\PowerShell-Export\CogitativoData\GoDaddyUserData.csv"
    $DistLISTPath = "C:\PowerShell-Export\CogitativoData\GoDaddyDistListData.csv"

    # Get Data and Store in CSV Files
    Get-Recipient | Export-CSV $UserDATAPath
    Get-UnifiedGroup | Export-CSV $GroupDATAPath
    Get-DistributionGroup | Export-CSV $DistLISTPath

    # Import Data Back into Variables
    $GoDaddyUserData = Import-CSV -Path $UserDATAPath
    $GoDaddyGroupData = Import-CSV -Path $GroupDATAPath
    $GoDaddyDistData = Import-CSV -Path $DistLISTPath

    Remove-PSSession $Session

    ############################ CONNECT TO NEW TENANT POWERSHELL ############################

    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $creds -Authentication Basic -AllowRedirection
    Import-PSSession $Session -DisableNameChecking 

    # CSVPATHS
    $NewGroupDATAPath = "C:\PowerShell-Export\CogitativoData\GroupData.csv"
    $NewUserDATAPath = "C:\PowerShell-Export\CogitativoData\UserData.csv"
    $NewDistLISTPath = "C:\PowerShell-Export\CogitativoData\DistListData.csv"

    # Get Data and Store in CSV Files
    Get-Recipient | Export-CSV $NewUserDATAPath
    Get-UnifiedGroup | Export-CSV $NewGroupDATAPath
    Get-DistributionGroup | Export-CSV $NewDistLISTPath

    # Import Data Back into Variables
    $UserData = Import-CSV -Path $NewUserDATAPath
    $GroupData = Import-CSV -Path $NewGroupDATAPath
    $DistData = Import-CSV -Path $NewDistLISTPath

    $ErrorString =
    $missingusers = @()

    $missingUsers = checkData -Data $GoDaddyUserData -newData $UserData
    $missingGroups = checkData -Data $GoDaddyGroupData -newData $GroupData
    $missingDistList = checkData -Data $GoDaddyDistData -newData $DistData


    function checkData($Data, $newData){
        $missingItems = @()
        $itemMissing = $true

        $Data | foreach-object{
            $itemMissing = $true
            $currentItem = $_

            $newData | foreach-Object{
                $_.Alias
                if ($itemMissing)
                {
                    if ($_.Alias -Contains $currentItem.Alias){
                        $itemMissing = $false
                    }
                }
            }
            if ($itemMissing){
                $missingItems += $currentItem.Alias
                write-Host ($currentItem.Alias)
            }
        }
        
        return $missingItems
    }

    Remove-PSSession $Session
}
    









