param(
    [Parameter(Mandatory=$true)][String]$vCenter,
#    [Parameter(Mandatory=$true)][String]$ESXiRootPW,
    [String]$Path
    )
<# 
*******************************************************************************************************************
Authored Date:    March 2018
Original Author:  Graham Jensen
*******************************************************************************************************************
.SYNOPSIS
   Deploy firmware updates to list of ESXi hosts

.DESCRIPTION
   Using an target list of ESXi hosts, and a specified Firmware patch that is executable via the ESXi console,
   enable SSH on each host, transfer the firmware package to the host,  and execute it and then disable SSH. 
   
   Note, the target list must contain hosts in a single vCenter, this script is not designed to cross vCenter
   domains.

   Prompted inputs:  vCenter containing the targets, CIHS C3 credentials, ESXi Root Password, 
                     Location of target list, ZIP file to deploy 

   Outputs:          


*******************************************************************************************************************  
.NOTES
Prerequisites:

    #1  This script uses the VMware modules installed by the installation of VMware PowerCLI 10

===================================================================================================================
Update Log:   Please use this section to document changes made to this script
===================================================================================================================
-----------------------------------------------------------------------------
Update <Date>
   Author:    <Name>
   Description of Change:
      <Description>
-----------------------------------------------------------------------------
*******************************************************************************************************************
#>

# -----------------------
# Define Global Variables
# -----------------------
$Global:Folder = $env:USERPROFILE+"\Documents\DeployFirmware"
$Global:WorkingFolder = $Null
$Global:LogLocation = $Null

#*****************
# Get VC from User
#*****************
Function Get-VCenter {
    [CmdletBinding()]
    Param()
    #Prompt User for vCenter
    Write-Host "Enter the FQHN of the vCenter containing the target Hosts: " -ForegroundColor "Yellow" -NoNewline
    $Global:VCName = Read-Host 
}
#*******************
# EndFunction Get-VC
#*******************

#********************
# Function Get-RootPW
#********************
Function Get-RootPW {
    [CmdletBinding()]
    Param()
    #Prompt User for ESXi Host Root Password
    $RootPW = Read-Host -assecurestring "Please enter the Root password for the ESXi Hosts"
    $RootPW = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($RootPw))
    Return $RootPW
}
#***********************
# EndFunction Get-RootPW
#***********************

#*******************
# Connect to vCenter
#*******************
Function Connect-VC {
    [CmdletBinding()]
    Param()
    "Connecting to $Global:VCName"
    #Connect-VIServer $Global:VCName -Credential $Global:Creds -WarningAction SilentlyContinue
    Connect-VIServer $Global:VCName -WarningAction SilentlyContinue
}
#***********************
# EndFunction Connect-VC
#***********************

#*******************
# Disconnect vCenter
#*******************
Function Disconnect-VC {
    [CmdletBinding()]
    Param()
    "Disconnecting $Global:VCName"
    Disconnect-VIServer -Server $Global:VCName -Confirm:$false
}
#**************************
# EndFunction Disconnect-VC
#**************************

#****************************
# Function Get-FileToTransfer
#****************************
Function Get-FileToTransfer{
    [CmdletBinding()]
    Param($initialDirectory)
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "ZIP (*.zip)| *.zip"
    $OpenFileDialog.ShowDialog() | Out-Null
    Return $OpenFileDialog.filename

}

#**********************
# Function Get-FileName
#**********************
Function Get-FileName {
    [CmdletBinding()]
    Param($initialDirectory)
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "TXT (*.txt)| *.txt"
    $OpenFileDialog.ShowDialog() | Out-Null
    Return $OpenFileDialog.filename
}
#*************************
# EndFunction Get-FileName
#*************************

#*************************
# Function Read-TargetList
#*************************
Function Read-TargetList {
    [CmdletBinding()]
    Param($TargetFile)
    $Targets = Get-Content $TargetFile
    Return $Targets
}
#****************************
# EndFunction Read-TargetList
#****************************

#**************************
# Function Create-LogFolder
#**************************
Function Create-LogFolder {
    [CmdletBinding()]
    Param($FolderLocation)
    "Building Local folder structure"
    $Global:LogLocation = "$FolderLocation\Logs-$(Get-Date -Format yyyy-MM-dd-hh-mm-tt)" 
    If (!(Test-Path $LogLocation)) {
        New-Item $LogLocation -type Directory
        }
   "Folder Structure built"
#   $FolderLocation 
#    Return $LogLocation
}
#*****************************
# EndFunction Create-LogFolder
#*****************************

#**************************
# Funtion Enable-VMHost-SSH
#**************************
Function Enable-VMHost-SSH {
    [CmdletBinding()]
    Param($vmhost)
    "Enabling SSH on $vmhost"
    Start-VMHostService -HostService (Get-VMHostService -vmhost $vmhost | Where {$_.key -eq "TSM-SSH"}) >$null
}
#*****************************
# EndFuntion Enable-VMHost-SSH
#*****************************

#***************************
# Function Disable-VMHost-SSH
#***************************
Function Disable-VMHost-SSH {
    [CmdletBinding()]
    Param($vmhost)
    "Disabling SSH on $VMhost"
    Stop-VMHostService -HostService (Get-VMHostService -vmhost $vmhost | Where {$_.key -eq "TSM-SSH"}) -Confirm:$False >$null
}
#******************************
# EndFunction Disable-VMHost-SSH
#******************************

#***************************
# Funtion Build-Host-Strings
#***************************
Function Build-Host-Strings {
    [CmdletBinding()]
    Param($vmhost)
    
    $SSHInfo = "" | Select TransferTo,Host
    
    $SSHInfo.TransferTo = "root@"+$vmhost+":/tmp"
    $SSHInfo.Host = "root@"+$vmhost
    Return $SSHInfo
}
#************************************
# EndFuntion Build-Transfer-to-String
#************************************

#***********************
# Funtion Accept-SSH-Key
#***********************
Function Accept-SSH-Key {
    [CmdletBinding()]
    Param($vmsshhost)
    "Doing initial SSH connection to $vmsshhost to register it's SSH Key"
    echo y | plink.exe -ssh $vmsshhost "exit" > $null    
    
}
#**************************
# EndFuntion Accept-SSH-Key
#**************************

#*********************************
# Funtion Transfer-Payload-to-Host
#*********************************
Function Transfer-Payload-to-Host{
    [CmdletBinding()]
    Param($TransferTo,$FileToTransfer,$RootPW,$Log)
    "Transfering $FileToTransfer to $TransferTo"
    pscp.exe -pw $RootPW $FileToTransfer $TransferTo > $Log
    
}
#************************************
# EndFuntion Transfer-Payload-to-Host
#************************************

#************************
# Funtion Execute-Payload
#************************
Function Execute-Payload{
    [CmdletBinding()]
    Param($SSHHost, $RootPW, $CmdTxt, $Log)
    "Executing Payload on $SSHHost"
    #$CmdTxt = "$Global:Folder\command.txt"
    plink -ssh $SSHHost -pw $RootPW -m $CmdTxt >> $Log
}
#************************
# EndFuntion Execute-Payload
#************************

#***************
# Execute Script
#***************
CLS
$ErrorActionPreference="SilentlyContinue"

"=========================================================="
" "
#Write-Host "Get CIHS credentials" -ForegroundColor Yellow
#$Global:Creds = Get-Credential -Credential $null

#Get-VCenter
$Global:VCName = $vCenter
Connect-VC
"----------------------------------------------------------"
#$RootPW = $ESXiRootPW
$RootPW = Get-RootPW
"----------------------------------------------------------"
"Get Zip file to be transfered to host"
$FileToTransfer = Get-FileToTransfer $Global:Folder
$Global:WorkingFolder = Split-Path -Path $FileToTransfer
#$Global:WorkingFolder = Split-Path -Path $OpenFileDialog.FileName
$Global:WorkingFolder
"----------------------------------------------------------"
"Get Target List"
#$inputFile = Get-FileName $Global:WorkingFolder
$inputFile = "$Global:WorkingFolder\Targets.txt"
$inputFile
"----------------------------------------------------------"
"Get Command File for execution of payload"
#$CommandFile = Get-FileName $Global:WorkingFolder
$CommandFile = "$Global:WorkingFolder\Commands.txt"
$CommandFile
"----------------------------------------------------------"
"Reading Target List"
$VMHostList = Read-TargetList $inputFile
"----------------------------------------------------------"
"Creating LogFile Location for this run"
Create-LogFolder $Global:Folder
"----------------------------------------------------------"
"Processing Target List"
ForEach ($VMhost in $VMHostList){
    $Logfile = $null
    Enable-VMHost-SSH $VMhost 
    $SSHInfo = Build-Host-Strings $VMhost
    Accept-SSH-Key $SSHInfo.host
    $LogFile = "$Global:LogLocation\$VMHost.txt"
    $LogFile
    Transfer-Payload-to-Host $SSHInfo.TransferTo $FileToTransfer $RootPW $LogFile
    Execute-Payload $SSHInfo.host $RootPW $CommandFile $LogFile
    Disable-VMHost-SSH $VMHost
    #Shutdown-VMs $VMhost
    "----------------------------------------------------------"
}
Disconnect-VC
#Clean-Up


