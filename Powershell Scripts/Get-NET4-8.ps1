$computers = Import-CSV C:\Computers.csv

foreach ($computer in $computers.Name)
{
    if (Test-Connection $computer -Count 2 -Quiet)
    {
        try{
            $ver = (REG Query "\\$computer\HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" /v Version)
        }
        catch{
            Write-Output $Computer
        }
        

        #New-Object -TypeName PSCustomObject -Property @{
        #    Name = $computer
        #    Version = $ver[2].Split()[$ver[2].Split().length-1]
        #} | Export-CSV -Path 'C:\NetVersion.csv' -Append
    }
    else {
        Write-Output $Computer
    }
}



REG Query "\HKLM\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" /v Version