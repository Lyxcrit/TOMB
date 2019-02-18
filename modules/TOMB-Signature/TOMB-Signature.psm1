﻿<#
    .SYNOPSIS: 
    This block of code will parse thru folders and grab the file name and signature of the file.

    .DESCRIPTION: 
    By default this module scans the following directories:
        C:\Windows\System32
        C:\Program Files
        C:\Program Files (x86)
        C:\Users
    For all files ending in .exe, .dll, .txt, .ps1, .psm1, .xls
    This module gathers file information for the following:
        FileName, Digital Signature, SHA1, MD5, FileVersion.

    .NOTES
    DATE:       18 FEB 19
    VERSION:    1.0.4a
    AUTHOR:     Brent Matlock -Lyx

    .PARAMETER Computer
    Used to specify list of computers to collect against, if not provided then hosts are pulled from .\includes\tmp\DomainList.txt

    .EXAMPLE
    Will capture signatures of default directories against localhost
        TOMB-Signature -Computer localhost -Path .

    .EXAMPLE
    Will capture file information against DC01 in the System32 folder
        TOMB-Signature -Computer DC01 -Path .
#>

[cmdletbinding()]
Param (
    # ComputerName of the host you want to connect to.
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)][System.Array] $Computer,    
    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)][System.Array] $Path
)

#Build Variable Scope
$(Set-Variable -name Computer -Scope Global) 2>&1 | Out-null
$(Set-Variable -name Path -Scope Global) 2>&1 | Out-null

#Main Script, collects Processess off hosts and converts the output to Json format in preperation to send to Splunk
Function TOMB-Signature($Computer, $Path){
    cd $Path
    Try {
        $ConnectionCheck = $(Test-Connection -Count 1 -ComputerName $Computer -ErrorAction Stop)
        }
    #If host is unreachable this is placed into the Errorlog: ScheduledTask.log
    Catch [System.Net.NetworkInformation.PingException] {
        "$(Get-Date): Host ${Computer} Status unreachable." |
        Out-File -FilePath $Path\logs\ErrorLog\signature.log -Append
        }
    Catch [System.Management.Automation.Remoting.PSRemotingTransportException] {
        "$(Get-Date): Host ${Computer} Access Denied" |
        Out-File -FilePath $Path\logs\ErrorLog\signature.log -Append
        }
    If ($ConnectionCheck){ SignatureCollect($Computer) }
    Else {
        "$(Get-Date) : ERROR MESSAGE : $($Error[0])" | Out-File -FilePath $Path\logs\ErrorLog\signature.log -Append
    }
}

#Prepare function to be passed to remote host
Function Sigs {
    $FileDirectory = Get-ChildItem -File "C:\Windows\System32\*", "C:\Program Files\*", "C:\Program Files (x86)\*", "C:\Users\*" `
                     -Include "*.txt","*.dll","*.exe", "*.rtf", "*.xls*" -Depth 10 -Recurse
    Foreach ($File in $FileDirectory) {
        $Signature = (Get-AuthenticodeSignature "$File").SignerCertificate.Subject
        $Sha1 = Get-FileHash -a SHA1 $File
        $Sha1 = $Sha1.Hash
        $MD5 = Get-FileHash -a MD5 $File
        $MD5 = $MD5.Hash
        $FileVersion = Get-ChildItem $File | Foreach-Object { "{0}" -f [System.Diagnostics.FileVersionInfo]::GetVersionInfo($_).FileVersion }
        $obj = $obj + "[{ File: $File, Signature: $Signature, SHA1: $Sha1, MD5: $MD5, FileVersion: $FileVersion }]`r`n"
    }
    return $obj
}

Function SignatureCollect($Computer){
    $Signatures = $(Invoke-Command -ComputerName $Computer -ScriptBlock ${function:Sigs} -ErrorVariable Message 2>$Message)
    Try { $Signatures
        If($Signatures -ne $null){
            Foreach($obj in $Signatures){
                #Output is encoded with UTF8 in order to Splunk to parse correctly
                $obj | Out-File -FilePath $Path\Files2Forward\Signature\${Computer}_Signature.json -Append -Encoding utf8
            }
        }
        Else {
            "$(Get-Date) : $($Message)" | Out-File -FilePath $Path\logs\ErrorLog\signature.log -Append
        }
    }
    Catch [System.Net.NetworkInformation.PingException] {
        "$(Get-Date): Host ${Computer} Status unreachable after."
    Out-File -FilePath $Path\logs\ErrorLog\signature.log
    }
}

#Alias registration for deploying with -Collects parameter via TOMB.ps1
New-Alias -Name Signature -Value TOMB-Signature
Export-ModuleMember -Alias * -Function * -ErrorAction SilentlyContinue