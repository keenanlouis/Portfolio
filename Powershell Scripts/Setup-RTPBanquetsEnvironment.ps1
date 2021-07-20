# This script will copy the existing RTP config and modify it to create a Banquets environment for users
# Author: Keenan Louis
# Date: 7-16-2021

$prodEnvPath = "C:\Program Files (x86)\RTP\RTPOne"

if ((Test-Path -Path $prodEnvPath))
{
    $banquetsEnvPath = "C:\Program Files (x86)\RTP\Banquets RTPOne"

    # Check if the folder is already created
    if (!(Test-Path -Path $banquetsEnvPath))
    {
        # Copy Items
        Copy-Item -Path $prodEnvPath -Destination $banquetsEnvPath -Recurse

        # Set permissions for the folder
        Get-ACL $prodEnvPath | Set-ACL $banquetsEnvPath
    }

    # Create a shortcut on the public desktop for the Test Environment
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("C:\Users\Public\Desktop\Banquets RTPOne.lnk")
    $Shortcut.TargetPath = $banquetsEnvPath + "\RTPOne.exe"
    $Shortcut.Save()
}
else {
    write-error("RTP is Not Installed, Install RTP then run this script")
}