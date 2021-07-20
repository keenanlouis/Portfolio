Get-msoluser | foreach-Object{git
    $guid = [guid] $_.objectID
    $immutableId = [System.Convert]::ToBase64String($guid.ToByteArray())
    Set-MsolUser -UserPrincipalName $_.UserPrincipalName -ImmutableId $immutableId
}