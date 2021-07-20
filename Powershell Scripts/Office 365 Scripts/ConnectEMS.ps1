# This Script will connect to the exchange management console


Set-ExecutionPolicy RemoteSigned {A}



$Credentials = Get-Credential

$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $Credential -Authentication Basic -AllowRedirection

Import-PSSession $Session