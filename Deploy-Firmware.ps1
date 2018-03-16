<# 
*******************************************************************************************************************
Authored Date:    March 2018
Original Author:  Graham Jensen
*******************************************************************************************************************
.SYNOPSIS
   Deploy firmware updates to list of ESXi hosts

.DESCRIPTION
   Using an target list of ESXi hosts, and a specified Firmware patch that is executable via the ESXi console,
   enable SSH on each host, transfer the firmware package to the host, execute it, and then reboot the
   host to complete the installation.  Once host is confirmed to be back online, disable SSH. 
   
   Note, the target list must contain hosts in a single vCenter, this script is not designed to cross vCenter
   domains.

   Prompted inputs:  ESXi Root Credentials, Location of target list, vCenter containing the targets

   Outputs:          


*******************************************************************************************************************  
.NOTES
Prerequisites:

    #1  This script uses the VMware modules installed by the installation of VMware PowerCLI
        ENSURE that VMware PowerCLI has been installed.  
    
        Installation media can be found here: 
        \\cihs.ad.gov.on.ca\tbs\Groups\ITS\DCO\RHS\RHS\Software\VMware


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

# +------------------------------------------------------+
# |        Load VMware modules if not loaded             |
# +------------------------------------------------------+
"Loading VMWare Modules"
$ErrorActionPreference="SilentlyContinue" 
if ( !(Get-Module -Name VMware.VimAutomation.Core -ErrorAction SilentlyContinue) ) {
    if (Test-Path -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VMware, Inc.\VMware vSphere PowerCLI' ) {
        $Regkey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\VMware, Inc.\VMware vSphere PowerCLI'
       
    } else {
        $Regkey = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\VMware, Inc.\VMware vSphere PowerCLI'
    }
    . (join-path -path (Get-ItemProperty  $Regkey).InstallPath -childpath 'Scripts\Initialize-PowerCLIEnvironment.ps1')
}
$ErrorActionPreference="Continue"

# -----------------------
# Define Global Variables
# -----------------------
$Global:Folder = $env:USERPROFILE+"\Documents\DeployFirmware"

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
    Connect-VIServer $Global:VCName -Credential $Global:Creds -WarningAction SilentlyContinue
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
# Function Get-CommandFile
#*************************
Function Get-CommandFile {
    [CmdletBinding()]
    Param($initialDirectory)
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $initialDirectory
    $OpenFileDialog.filter = "TXT (*.txt)| *.txt"
    $OpenFileDialog.ShowDialog() | Out-Null
    Return $OpenFileDialog.filename
}
#****************************
# EndFunction Get-CommandFile
#****************************

#******************************
# Function Generate-Command-Txt
#******************************
Function Generate-Command-Txt{
    [CmdletBinding()]
    Param($FileToTransfer)
    $FileName = [System.IO.Path]::GetFileName("$FileToTransfer")
    $FileNameSplit = $FileName.split('.')
    $VMexe = $FileNameSplit[0]+".vmexe"
    "unzip -o /tmp/$FileName -d /tmp" | Out-File -Encoding ascii $Global:Folder\command.txt
    "cd /tmp" | Out-File -Encoding ascii $Global:Folder\command.txt -Append
    "./$VMexe" | Out-File -Encoding ascii $Global:Folder\command.txt -Append
}
#*********************************
# EndFunction Generate-Command-Txt
#*********************************

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

#*********************
# Function Shutdown-VMs
#*********************
Function Shutdown-VMs {
    [CmdletBinding()]
    Param($vmhost)
    $vms = get-vmhost -Name $vmhost | get-vm | where {$_.PowerState -eq "PoweredOn"}
    foreach ($vm in $vms) {
        "Shutting Down $vm on $vmhost"
        Shutdown-VMGuest -VM $vm -Confirm:$false >$null
        }
   # Sleep 60
    
}
#************************
# EndFunction Shutdown-VMs
#************************


#*********************
# Function Reboot-Host
#*********************
Function Reboot-Host {
    [CmdletBinding()]
    Param($vmhost)
    $vms = get-vmhost -Name $vmhost | get-vm | where {$_.PowerState -eq "PoweredOn"} 
    If ($vms.count -eq 0) {
        "Restarting $vmhost"
        Restart-VMHost -VMHost $vmhost -Force -Confirm:$false >$null
        }
        Else {
            Sleep 30
            Reboot-Host $VMhost
            }
}
#************************
# EndFunction Reboot-Host
#************************

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
    echo y | plink.exe -ssh $vmsshhost "exit" #> $null    
    
}
#**************************
# EndFuntion Accept-SSH-Key
#**************************

#*********************************
# Funtion Transfer-Payload-to-Host
#*********************************
Function Transfer-Payload-to-Host{
    [CmdletBinding()]
    Param($TransferTo,$FileToTransfer,$RootPW)
    "Transfering $FileToTransfer to $TransferTo"
    pscp.exe -pw $RootPW $FileToTransfer $TransferTo
    
}
#************************************
# EndFuntion Transfer-Payload-to-Host
#************************************

#************************
# Funtion Execute-Payload
#************************
Function Execute-Payload{
    [CmdletBinding()]
    Param($SSHHost, $RootPW, $CmdTxt)
    #$CmdTxt = "$Global:Folder\command.txt"
    plink -ssh $SSHHost -pw $RootPW -m $CmdTxt
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
Write-Host "Get CIHS credentials" -ForegroundColor Yellow
$Global:Creds = Get-Credential -Credential $null

Get-VCenter
Connect-VC
"----------------------------------------------------------"
$RootPW = Get-RootPW
"----------------------------------------------------------"
"Get Zip file to be transfered to host"
$FileToTransfer = Get-FileToTransfer $Global:Folder
"----------------------------------------------------------"
"Get Target List"
$inputFile = Get-FileName $Global:Folder
"----------------------------------------------------------"
#"Generate Command.txt to be used later during payload execution"
"Get Command File for execution of payload"
#Generate-Command-Txt $FileToTransfer
$CommandFile = Get-FileName $Global:Folder
"----------------------------------------------------------"
"Reading Target List"
$VMHostList = Read-TargetList $inputFile
"----------------------------------------------------------"
"Processing Target List"
ForEach ($VMhost in $VMHostList){
    Enable-VMHost-SSH $VMhost
    $SSHInfo = Build-Host-Strings $VMhost
    Accept-SSH-Key $SSHInfo.host
    Transfer-Payload-to-Host $SSHInfo.TransferTo $FileToTransfer $RootPW
    Execute-Payload $SSHInfo.host $RootPW $CommandFile
    Disable-VMHost-SSH $VMHost
    Shutdown-VMs $VMhost
    "----------------------------------------------------------"
}
#Loop through again and initiate host reboots
"Processing Target List for Host Reboots"
ForEach ($VMhost in $VMHostList){
    Reboot-Host $VMhost  
}

Disconnect-VC
#Clean-Up


