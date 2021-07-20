############################ CONNECT TO EXCHANGE TENANT ############################

$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $creds -Authentication Basic -AllowRedirection
Import-PSSession $Session -DisableNameChecking 

$OLDDOMAIN = 'oldDomain'
$NEWDOMAIN = 'newdomain'

$ReciepientData = Get-Recipient

$RecipientData | foreach-Object{
    if ($_.PrimarySMTPAddress.endswith($OLDDOMAIN)) {
        $tempAddress = $_.primarySMTPAddress.substring(0,$_.primarySMTPAddress.length - $OLDDOMAIN.length) + $NEWDOMAIN
        
        write-host ($TempAddress)
        #Set-Mailbox -Identity $_.Alias -PrimarySmtpAddress $tempAddress
    }
}