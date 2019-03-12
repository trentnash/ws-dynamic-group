# Name: ws-dynamic-group
# Version: 1.0
# Author: wandersick

# Descriptions: Run as a scheduled task to monitor a flat file (CSV) for additions or removal of users in one or more groups
#               Apply the changes to system accordingly, locally or on a domain controller (Active Directory)
#               (Note: Current version aims to just 'do the job'. It could use workarounds here and there, and performance is not its priority now)
# More Details: https://github.com/wandersick/ws-dynamic-group

# ---------------------------------------------------------------------------------

# [Editable Settings]

# Script directory
# Example: c:\ws-dynamic-group where this script can be located at c:\ws-dynamic-group\Scripts\ws-dynamic-group-core.ps1
$scriptDir = "c:\ws-dynamic-group"

# CSV filename to process
$csvFile = "incoming.csv"

# 'Local' (workgroup) or 'Domain' mode - this scripts support local (workgroup) mode where local group would be enumerated, or domain mode which is only supported to be run on a domain controller (RSAT is unsupported due to the use of "net group" command)
$directoryMode = "Local"

# Create a new directory by randomizing a unique value made up of day time.
# Example: 20190227_095047AM
$currentDateTime = Get-Date -format "yyyyMMdd_hhmmsstt"

# ---------------------------------------------------------------------------------

# [Main Body of Script]

# Move 01_Incoming\incoming.csv to a directory of ransomized name inside 02_Processing
New-Item "$scriptDir\02_Processing\$currentDateTime" -Force -ItemType "directory"
Copy-Item "$scriptDir\01_Incoming\$csvFile" "$scriptDir\02_Processing\$currentDateTime\$csvFile" -Force
Remove-Item "$scriptDir\01_Incoming\$csvFile" -force 

# Import users and groups from CSV into an array
$csvItems = import-csv "$scriptDir\02_Processing\$currentDateTime\$csvFile"
# Alternative, for user deletion in sub-function
$csv2Items = import-csv "$scriptDir\02_Processing\$currentDateTime\$csvFile"

# Backup existing group members to a log file (Output File: GroupMemberBefore_GroupName.csv)
ForEach ($csvItem in $csvItems) {
    $csvGroupname = $($csvItem.groupname)
    if ($directoryMode -ieq "Local") {
        Get-LocalGroup "$csvGroupname" | Get-LocalGroupMember | Export-CSV "$scriptDir\02_Processing\$currentDateTime\LocalGroupMemberBefore_$csvGroupname.csv" -Force
    } elseif ($directoryMode -ieq "Domain") {
        Get-ADGroup "$csvGroupname" | Get-ADGroupMember | Export-CSV "$scriptDir\02_Processing\$currentDateTime\DomainGroupMemberBefore_$csvGroupname.csv" -Force 
    }
}

# Enumberate each line from CSV
ForEach ($csvItem in $csvItems) {
    $csvUsername = $($csvItem.username)
    $csvGroupname = $($csvItem.groupname)

    # For the group being processed, acquire existing group members from it in current system into an array
    if ($directoryMode -ieq "Local") {
        $sysGroupMembers = Get-LocalGroup "$csvGroupname" | Get-LocalGroupMember
    } elseif ($directoryMode -ieq "Domain") {
        $sysGroupMembers = Get-ADGroup "$csvGroupname" | Get-ADGroupMember
    }

    # Enumberate group members of the group from current system
    # For each username in CSV, compare with group member in current system
    ForEach ($sysGroupMember in $sysGroupMembers) {
        $userSysCheck = $false
        $sysGroupMemberName = $($sysGroupMember.name).split("\\")[-1]
        # Enumberate users from CSV (alternative variable) and DELETE existing users in system not found in CSV
        ForEach ($csv2Item in $csv2Items) {
            $csv2Username = $($csv2Item.username)
 
            if ($sysGroupMemberName -eq $csv2Username) {
                $userSysCheck = $true
            }
 
            if ($userSysCheck -eq $true) {
                # Break out of the ForEach loop if true to prevent from needless further processing
                Break
            }
        }
        # In case user does not exist in CSV but in system, remove the user from group in system.
        # This won't apply to users who exist in CSV and in system to prevent interruption to the users
        # Note: The code below may run more than once
        #       If the user has already been deleted by a previous run, subsequent runs have no effect and output the user cannot be found
        if ($userSysCheck -eq $false) {
            if ($directoryMode -ieq "Local") {
                # Todo*: Remove-LocalGroupMember -Group "" -Member ""
                net localgroup `"$csvGroupname`" `"$sysGroupMember`" /del 
            } elseif ($directoryMode -ieq "Domain") {
                # Todo*: Remove-ADGroupMember -Identity "" -Members ""
                net group `"$csvGroupname`" `"$sysGroupMemberName`" /del
            }
        }
    }
     # Perform usersadd action on user and group

     # This also applies to users who already exist in CSV and in system, so there can be harmless error messages that can be safely ignored:
     # "System error 1378 has occurred." "The specified account name is already a member of the group"
     if ($directoryMode -ieq "Local") {
        # Todo*: Add-LocalGroupMember -Group "" -Member ""
        net localgroup `"$csvGroupname`" `"$csvUsername`" /add
    } elseif ($directoryMode -ieq "Domain") {
        # Todo*: Add-ADGroupMember -Identity "" -Members ""
        net group `"$csvGroupname`" `"$csvUsername`" /add
        # *A workaround is currently in use to acquire correct variable content as `"...`". This requires traditional CLI commands
        #  Although this works, I left it as a todo for this part to be written in PowerShell without the workaround
    }
    
}

# Record final group members to a log file (Output File: GroupMemberAfter_GroupName.csv)
ForEach ($csvItem in $csvItems) {
    $csvGroupname = $($csvItem.groupname)
    if ($directoryMode -ieq "Local") {
        Get-LocalGroup "$csvGroupname" | Get-LocalGroupMember | Export-CSV "$scriptDir\02_Processing\$currentDateTime\LocalGroupMemberAfter_$csvGroupname.csv" -Force
    } elseif ($directoryMode -ieq "Domain") {
        Get-ADGroup "$csvGroupname" | Get-ADGroupMember | Export-CSV "$scriptDir\02_Processing\$currentDateTime\DomainGroupMemberAfter_$csvGroupname.csv" -Force
    }
}

# Move processed folder to 03_Done
Copy-Item "$scriptDir\02_Processing\$currentDateTime\" "$scriptDir\03_Done\$currentDateTime\" -Recurse -Force
Remove-Item "$scriptDir\02_Processing\$currentDateTime\" -Recurse -Force

# Write dummy file to 'Processed' folder to signal completion of script
Write-Output "The existence of this file indicates the script has been run until the end." | Out-File "$scriptDir\03_Done\$currentDateTime\Completed"