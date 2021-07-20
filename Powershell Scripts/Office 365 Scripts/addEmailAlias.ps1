################################################################################################################################################################

# File:         addEmailAlias.ps1
# Author:       Keenan Louis
# Date:         4/21/2020
# Description   This Script will get user data from one tenant and add the user email alias' to the new tenant

################################################################################################################################################################

$script={
    ############################ CONNECT TO NEW TENANT POWERSHELL ############################

    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $creds -Authentication Basic -AllowRedirection
    Import-PSSession $Session -DisableNameChecking 

    # Constants
    $OLDDOMAIN = 'OLD DOMAIN'
    $NEWDOMAIN = 'NEW DOMAIN'

    # UPDATE THIS WITH THE PATH TO YOUR CSV FILE
    $CSVPATH = 'C:\PowerShell-Export\OldUserData.csv'

    # Instantiate Variables
    $users = @{}

    # Get User Data
    $userData = Import-CSV -Path $CSVPATH

    # Cycle through the data and store key information
    $userData | foreach-object{
        # Reset Variables
        $userAddresses = @()
        $alias = $_.alias

        # Split the address into an array
        $emailAddress = $_.EmailAddresses.split(' ')

        # Cycle through address and only store DOMAIN and smtp addresses
        for($i= 0; $i -lt $emailAddress.length; $i++){
            if (($emailAddress[$i] -is [String]) -and $emailAddress[$i].endswith($NEWDOMAIN) -and $emailAddress[$i].startswith('smtp:')){
                $userAddresses += $emailAddress[$i]
            }     
        }
        # Add to the array if there is a value
        if ($userAddresses.length -gt 0){
            $users.add($_.alias, $userAddresses)
        }
        
    }

    # Update Primary SMTP Address to NEWDOMAIN
    Get-Recipient | foreach-Object{
        $addresses =@()
        if ($_.PrimarySMTPAddress.endswith($OLDDOMAIN)) {

            # Split the address into an array
            $emailAddress = $_.EmailAddresses.split(' ')

            # Replace primary SMTP with the new domain address
            $addresses += "SMTP:" + $_.primarySMTPAddress.substring(0,$_.primarySMTPAddress.length - $OLDDOMAIN.length) + $NEWDOMAIN
            $addresses += "smtp:" + $_.primarySMTPAddress

            # Cycle through address and store smtp addresses
            for($i= 0; $i -lt $emailAddress.length; $i++){

                # The item is a string and is an alias
                if (($emailAddress[$i] -is [String]) -and $emailAddress[$i].startswith('smtp:')){
                    $addresses +=  $emailAddress[$i]
                }
            }
            Set-Mailbox -Identity $_.Alias -EmailAddresses $addresses
        }
    }

    # Add Alias' to the accounts
    $users.keys | foreach-object{
        # Store the user ID (key)
        $ID = $_

        # Cycle through each address and add it to the account
        $users[$ID] | foreach-Object{

            # Adds the address 
            Set-Mailbox -Identity $ID -EmailAddresses @{add=$_}
        }
    }

    # Disconnect from sesson
    Remove-PSSession $Session

    #Entry point
    main
}

Invoke-Command -Scriptblock $script