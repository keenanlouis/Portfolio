# This script will copy the existing RTP config and modify it to create a test environment for users
# Author: Keenan Louis
# Date: 7-16-2021

$prodEnvPath = "C:\Program Files (x86)\RTP\RTPOne"

if ((Test-Path -Path $prodEnvPath))
{
    $testEnvPath = "C:\Program Files (x86)\RTP\Test RTPOne"

    # Check if the folder is already created
    if (!(Test-Path -Path $testEnvPath))
    {
        # Copy Items
        Copy-Item -Path $prodEnvPath -Destination $testEnvPath -Recurse

        # Set permissions for the folder
        Get-ACL $prodEnvPath | Set-ACL $testEnvPath
    }


    # Path to the Test configuration
    $testConfigPath = $testEnvPath + "\AppSettings.config"

    # Get the template file
    $testConfigAppSettings = [XML](Get-Content $testConfigPath -ErrorAction Stop)

    # Set new values for the test environment
    $testConfigAppSettings.SelectSingleNode('REMOVED') # Removed Sensitive Info
    $testConfigAppSettings.SelectSingleNode('//appSettings/add[@key="VerboseTitleBar"]/@value').'#text' = 'true'
    $testConfigAppSettings.SelectSingleNode('REMOVED') # Removed Sensitive Info
    $testConfigAppSettings.Save($testConfigPath)

    # Create a shortcut on the public desktop for the Test Environment
    $WshShell = New-Object -comObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("C:\Users\Public\Desktop\Test RTPOne.lnk")
    $Shortcut.TargetPath = $testEnvPath + "\RTPOne.exe"
    $Shortcut.Save()
}
else {
    write-error("RTP is Not Installed, Install RTP then run this script")

}