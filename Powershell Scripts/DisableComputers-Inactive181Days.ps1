#requires -version 2

<#
.SYNOPSIS
    Moves and Disables Workstations that have not logged into AD in the last 181 Days.

.DESCRIPTION
    Moves and Disables Workstations that have not logged into AD in the last 181 Days.
    Adds a decription to the object saying "Disabled for inactivity [today's date]"

.INPUTS
    None.

.OUTPUTS
    A .CSV File containing the computers objects and information regarding the disabled computers.
    Also Sends an email to SysAdmins@squawalpine.com with a report of the disabled items

.NOTES
    Version:        1.0
    Author:         Keenan Louis (SVAM)
    Creation Date:  3-16-2021
    Purpose/Change: Initial script development

.EXAMPLE
    DisabledComputers-Inactive181Days.ps1

#>


#---------------------------------------------------------[Initializations]--------------------------------------------------------



#----------------------------------------------------------[Declarations]----------------------------------------------------------

# CSV file Info
$month = (Get-Date).toString("MMM")
$csvPath = "C:\disabledComputers-$month.csv"

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function ModifyComputerObject{
    Param(
        $computerObject)
  
    Process{
        Try{
            #Get the date to update the description
            $date = Get-Date -Format "MM-dd-yyyy"

            # Move the computer to the disabled OU if it isn't already
            if ($computerObject.DistinguishedName -ne "CN=$($computerObject.Name),OU=Disabled Computers,DC=squawnet,DC=com")
            {
                Disable-ADAccount -Identity $computer.ObjectGUID

                # Update the description of the Computer
                Set-ADComputer -Identity $computerObject.ObjectGUID -Description "Disabled $date due to inactivity | Last Logon - $($computerObject.lastlogondate)"

                # Move the computer to the Disabled Computers OU
                Move-ADObject -Identity $computerObject.ObjectGUID -TargetPath "OU=Disabled Computers,DC=squawnet,DC=com"
            }
        }
        Catch{
            Write-Error $_.Exception -ExitGracefully $True
            Break
        }
    }
} #END Function ModifyComputerObject


Function disableWorkstations{
    Process{
        Try{
            # Inactive Days to Check
            $DaysInactive = 191

            # Calculate the time filter
            $time = (Get-Date).Adddays(-($DaysInactive))

            # Get the computer list that meets the category
            $computerList = Get-ADComputer -Filter {(LastLogonTimeStamp -lt $time) -AND (enabled -eq $True)} -Properties Name, lastlogondate, ObjectGUID, DistinguishedName, Enabled

            # For each computer in the list
            ForEach ($computer in $computerList)
            {
                # Check if the computer is a desktop, laptop or VM
                if ($computer.Name.StartsWith("DT-") -or $computer.Name.StartsWith("LT-") -or $computer.Name.StartsWith("VM-"))
                {
                    # Exclude the IT Computers and Servers OU
                    if (($computer.DistinguishedName -ne "CN=$($computer.Name),OU=Computers,OU=IT,DC=squawnet,DC=com") -AND ($computer.DistinguishedName -ne "CN=$($computer.Name),OU=Servers,OU=IT,DC=squawnet,DC=com"))
                    {
                        ModifyComputerObject($computer)
                        
                        # Create Computer Line
                        $compInfo = [pscustomobject]@{
                                Name = $computer.Name
                                LastLogon = $computer.lastLogondate
                                OU = "Disabled Computers"
                                DistinguishedName = $computer.DistinguishedName
                            } | Export-CSV -Path $csvPath -Append -NoTypeInformation
                    }
                }
            }   
        }
    Catch
    {
        Write-Error $_.Exception 
        Break
    }
  }
} #END Function DisableWorkstations

Function disablePOS{
  Process{
    Try{
        # Change the date to 271 days for the POS, CST, Lift Tablets 
        $DaysInactive = 271

        # Calculate the time filter
        $time = (Get-Date).Adddays(-($DaysInactive))

        # Get the computers that fall into this category
        $computerList = Get-ADComputer -Filter {LastLogonTimeStamp -lt $time} -Properties Name, lastlogondate, ObjectGUID, DistinguishedName, Enabled

        # For each POS in the list
        ForEach ($computer in $computerList)
        {
            # Check if the computer is a desktop, laptop or VM
            if ($computer.Name.StartsWith("DIN") -or $computer.Name.StartsWith("CST") -or $computer.Name.StartsWith("POS") -or $computer.Name.StartsWith("TABLET") -or $computer.Name.StartsWith("RTP"))
            {
                # Exclude the IT OU
                if (($computer.DistinguishedName -ne "CN=$($computer.Name),OU=Computers,OU=IT,DC=squawnet,DC=com")  -AND ($computer.DistinguishedName -ne "CN=$($computer.Name),OU=Servers,OU=IT,DC=squawnet,DC=com"))
                {
                    # Move the computer to the disabled OU if it isn't already
                    if ($computer.DistinguishedName -ne "CN=$($computer.Name),OU=Disabled Computers,DC=squawnet,DC=com")
                    {
                        ModifyComputerObject($computer)
                            
                        $compInfo = [pscustomobject]@{
                                Name = $computer.Name
                                LastLogon = $computer.lastLogondate
                                OU = "Disabled Computers"
                                DistinguishedName = $computer.DistinguishedName
                            } | Export-CSV -Path $csvPath -Append -NoTypeInformation
                    }
                }
            }
        }
    }
    Catch
    {
        Write-Error $_.Exception -ExitGracefully $True
        #Break
    }
  }
  
} #END DisablePOS


#-----------------------------------------------------------[Execution]------------------------------------------------------------

disableWorkstations
disablePOS