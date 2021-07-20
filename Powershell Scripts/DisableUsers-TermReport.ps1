<#
.SYNOPSIS

.DESCRIPTION

.OUTPUTS

.EXAMPLE

.NOTES

.AUTHOR
    Keenan Louis
    
.DATE

#>

Add-Type -AssemblyName System.Windows.Forms

#Group membership we're interested in
$global:KEY_GROUPS = 'ChefTecUsers', 'SMSUsers', 'AdobeCreativeCloudUsers', 'DynamicsUsers', 'RetailProUsers', 'VPNusers', 'Cellular Users'
$PUFlag = $True

function getCSVFile {
    #File Selection window	
    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath('UserProfile') + "\Downloads"
        Filter = 'Spreadsheet (*.csv, *.xlsx)|*.csv;*.xlsx'
        Title = "Select Term Report"
    }
    $null = $FileBrowser.ShowDialog()
    $FileName = $FileBrowser.FileName

    #Convert xlsx to csv
    if ($FileBrowser.FileName -match '.xlsx') {
        $Excel = New-Object -ComObject Excel.Application
        $wb = $Excel.Workbooks.Open($FileBrowser.FileNames)
        $FileName = $FileBrowser.FileName.replace("xlsx","csv")
        foreach ($ws in $wb.Worksheets) {
            $ws.SaveAs($FileName, 6)
        }
        $Excel.Quit()
    }

    start-sleep -s 1
    $firstline = Get-Content $FileName -First 1

    #Parse out junk first line
    if($firstline -match "Termination Report") {
        (Get-Content $FileName | Select-Object -Skip 1) | Set-Content $FileName
    }

    return Import-CSV $FileName
}


function teamsUser
{
    param(
        $user
    )
    # Users Name and Display Name for Teams Items
    if (($user.Name.ToLower().contains("teams") -AND $user.Name.ToLower().contains("only")) -OR ($user.DisplayName.ToLower().contains("teams") -and $user.DisplayName.ToLower().contains("only")))
    {
        return $true
    }
    else 
    {
        return $false
    }
}

################
##### MAIN #####
################

# Get the date, format and save for later if needed
$date = Get-Date -Format "MM/dd/yyyy"
$description = "Disabled $date | HR Term Report"
# Date/time in UTC format
$DateTimeUtc = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
# Date & CSV file name
$OutputFileName = ".\Reports\Report-DisabledUsers-" + $DateTimeUtc + ".csv"
$Report = New-Object System.Collections.ArrayList
$PotentialUsersReport = New-Object System.Collections.ArrayList

$userlist = getCSVFile

forEach ($user in $userlist)
{
    $groupString = ""
    $OU = $null
    $groups = $null
    $splitname = $user."Employee Name (Last Suffix, First MI)".Split(",")
        
    #Break if full name not specified in this line
    if($splitname[1] -eq $null) { break; }    
    
    $firstName = $splitname[1].substring(1)
    $lastName = $splitname[0]


    write-host "==========================================="  
    write-host -NoNewLine -ForegroundColor Green $firstName $lastName - $user."Termination Reason" `n
    $fnInitial = $firstName

    # Remove Middle initial
    if($firstName -match '\.$') {
        $firstName = $firstName -replace "...$"
    }

    $employee = Get-ADUser -Filter 'GivenName -eq $firstName -and sn -eq $lastName' -Properties *


    if ($employee -ne $null)
    {
        write-host "Exact Match" `n`n -ForegroundColor Yellow 
        Disable-ADAccount -Identity $employee.ObjectGUID
        Set-ADUser -Identity $employee.ObjectGUID -Description ($description + " | " +  $employee.description)

        if (teamsUser($employee))
        {
            $OU = "OU=Disabled Users,DC=squawnet,DC=com"
            Move-ADObject -Identity $employee.ObjectGUID -TargetPath "OU=Disabled Users,DC=squawnet,DC=com"
        }
        else 
        {
            $OU = "OU=Disabled Users - Mailbox Access,DC=squawnet,DC=com"
            $memberships = Get-ADPrincipalGroupMembership $employee.ObjectGUID | select-object -ExpandProperty name
            $keyMemberships = New-Object -TypeName 'System.Collections.ArrayList'
        
            foreach ($group in $KEY_GROUPS) 
            {
                if ($memberships -contains $group) 
                {
                    $keyMemberships.add($group)
                }     
            }

            foreach ($group in $keyMemberships)
            {
                $groupString += "$group, "
            }
            Move-ADObject -Identity $employee.ObjectGUID -TargetPath "OU=Disabled Users - Mailbox Access,DC=squawnet,DC=com"
        }

        $reportData = [Ordered]@{
            "Name" = $employee.name
            "DisplayName" = $employee.DisplayName
            "SamAccountName" = $employee.SamAccountName
            "Groups" = $groups
            "Moved To" = $OU
            "Termination Reason" = $User."Termination Reason"
        }
    
        # Create PSObject and add the ObjectProperties data
        $Row = New-Object -TypeName PSObject -Property $reportData
    
        # Add the user's details to the array for the report data
        [void]$Report.Add($Row)
    }
    else {
        $name = $user."Employee Name (Last Suffix, First MI)".substring(0,3) + "*" 
        $potentialEmployees = Get-ADUser -Filter 'Surname -like $name' -Properties *


        if ($potentialEmployees -ne $null)
        {
            $PotentialUsersReportData = [Ordered]@{
                "Name" = "$fnInitial $lastName"
                "DisplayName" = ""
                "ObjectGUID" = ""
                "SamAccountName" = ""
                "Job Title" = $user."Job Title"
                "Termination Reason" = $User."Termination Reason"
            }
            # Create PSObject and add the ObjectProperties data
            $PERow = New-Object -TypeName PSObject -Property $PotentialUsersReportData
    
             # Add the user's details to the array for the report data
            [void]$PotentialUsersReport.Add($PERow)
    
            foreach ($potentialEmployee in $potentialEmployees)
            {
                $PotentialUsersReportData = [Ordered]@{
                    "Name" = $potentialEmployee.Name
                    "DisplayName" = $potentialEmployee.DisplayName
                    "ObjectGUID" = $potentialEmployee.ObjectGUID
                    "SamAccountName" = $potentialEmployee.SamAccountName
                    "Job Title" = $potentialEmployee.Description
                    "Termination Reason" = $User."Termination Reason"
                }
                 # Create PSObject and add the ObjectProperties data
                $PERow = New-Object -TypeName PSObject -Property $PotentialUsersReportData
        
                # Add the user's details to the array for the report data
                [void]$PotentialUsersReport.Add($PERow)
            }

            $PERow = New-Object -TypeName PSObject
            [void]$PotentialUsersReport.Add($PERow)
        }
        else 
        {
            write-host -ForegroundColor cyan 'Employee Not Found'`n`n
        }        
    }
}

if ($PotentialUsersReport -ne $null)
{
    # Output the report to a CSV file
    Write-host "Writing the Potential Users Report file..." -ForegroundColor Cyan
    $potentialUsersReportPath = ".\Reports\PotentialUsersReport.csv" + $DateTimeUtc + ".csv"
    $PotentialUsersReport | Export-Csv $potentialUsersReportPath -Force -NoTypeInformation
    Write-host "Edit and Save this File Press Enter when Done" -ForegroundColor Yellow
    Invoke-Item $potentialUsersReportPath
    Read-Host -Prompt "Mash Enter To Continue ..."
    $NewReport = Import-Csv $potentialUsersReportPath

    if ($PUFlag)
    {
        foreach ($employee in $NewReport)
        {
            $groupString = ""
            
            if ($employee.ObjectGUID -ne "" -AND $employee.ObjectGUID -ne $null)
            {
                write-host "==========================================="  
                write-host -NoNewLine -ForegroundColor Green $employee.Name `n

                Disable-ADAccount -Identity $employee.ObjectGUID
                Set-ADUser -Identity $employee.ObjectGUID -Description ($description + " | " +  $employee.description)

                if (teamsUser($employee))
                {
                    $OU = "OU=Disabled Users,DC=squawnet,DC=com"
                    Move-ADObject -Identity $employee.ObjectGUID -TargetPath "OU=Disabled Users,DC=squawnet,DC=com"
                }
                else 
                {
                    $OU = "OU=Disabled Users - Mailbox Access,DC=squawnet,DC=com"
                    $memberships = Get-ADPrincipalGroupMembership $employee.ObjectGUID | select-object -ExpandProperty name
                    $keyMemberships = New-Object -TypeName 'System.Collections.ArrayList'
            
                    foreach ($group in $KEY_GROUPS) 
                    {
                        if ($memberships -contains $group) 
                        {
                            $keyMemberships.add($group)
                        }     
                    }

                    foreach ($group in $groups)
                    {
                        $groupString += "$group, "
                    }

                    Move-ADObject -Identity $employee.ObjectGUID -TargetPath "OU=Disabled Users - Mailbox Access,DC=squawnet,DC=com"
                }

                $reportData = [Ordered]@{
                    "Name" = $employee.name
                    "DisplayName" = $employee.DisplayName
                    "SamAccountName" = $employee.SamAccountName
                    "Groups" = $groupString
                    "Moved To" = $OU
                    "Termination Reason" = $User."Termination Reason"
                }
            
                # Create PSObject and add the ObjectProperties data
                $Row = New-Object -TypeName PSObject -Property $reportData
            
                # Add the user's details to the array for the report data
                [void]$Report.Add($Row)
            }
        }
    }
}


if ($Report -ne $null)
{
    # Output the report to a CSV file
    Write-host "Writing the CSV file..." -ForegroundColor Cyan
    $Report | Export-Csv $OutputFileName -Force -NoTypeInformation
    $OutputFileName_Resolved = Resolve-Path $OutputFileName
    Write-Host "================================================================" -ForegroundColor Gray
    Write-Host "Report outputed to: $OutputFileName_Resolved" -ForegroundColor Cyan
}
else {
    Write-Warning 'Problem With File'
}