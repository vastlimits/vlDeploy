Function Uninstall-vlApplication {
<#
.SYNOPSIS
    Uninstalls an application either locally or remotely
.PARAMETER Computer
    A computer name or a list of computer names where the application should be uninstalled. Defaults to the local computer. Pipeline input is supported.
.PARAMETER UninstallString
    The command to run to uninstall the application. Valid examples are:
        - MsiExec.exe /X{DC87320F-6CBA-3BC0-BC1E-65AF3961076C}
            - If 'MsiExec.exe' is detected the necessary silent parameter '/qn' is added automatically.
        - "`"C:\ProgramData\Package Cache\{ce085a78-074e-4823-8dc1-8a721b94b76d}\vcredist_x86.exe`" /uninstall /quiet"
            - Note that quotation marks in paths need to be escaped like above
.PARAMETER Credential
    Specifies the credentials when uninstallation on a remote computer is desired.
.EXAMPLE
    PS C:\> Get-vlInstalledApplication -Computer PC1 -Name 'Google Chrome' | Uninstall-vlApplication -ValidExitCodes 0,3010,1
    Gets the uninstall string of an application from a remote machine and uninstall it there. Valid exit codes are 0, 3010, and 1. 
.EXAMPLE
    PS C:\> $UninstallString = (Get-vlInstalledApplication -Computer PC1 -Name 'Google Chrome').UninstallString
    PS C:\> PC1', 'PC2', 'PC3' | Uninstall-vlApplication -UninstallString $UninstallString -RebootAfterSuccess
    Gets the uninstall string of an application from a remote machine and uninstalls it on multiple machines. Reboots every machine if uninstallation was successful.
.NOTES
    Author: vast limits GmbH
#>
    [OutputType([System.String])]
    [Cmdletbinding()]
    Param( 
        [Parameter(ValueFromPipelineByPropertyName = $True)]
        [Alias('Computername', 'PSComputername', '__Server', 'CN')]
        [System.String[]]$Computer = $env:COMPUTERNAME,
        
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $True)]
        [Alias('QuietUninstallString')]
        [System.String]$UninstallString,

        [Parameter()]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter()]
        [switch]$RebootAfterSuccess,

        [Parameter()]
        [int32[]]$ValidExitCodes = @("0", "3010")
    )

    Begin {
        $ErrorActionPreference = 'Stop'
        try {
            # Initialize output
            $Results = @()

        }
        catch {
            Write-Error -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)"
        }


    }

    Process {
        try {
            $scriptblock = {
                If ($args[0].ContainsKey('Verbose')) {
                    $VerbosePreference = 'Continue'
                }
                $args[0].GetEnumerator() | ForEach-Object { New-Variable -Name $_.Key -Value $_.Value }


                Write-Verbose "Reset variables based on uninstaller"
                if ($UninstallString -match 'msiexec') {
                    $Uninstaller = 'msiexec.exe'
                    $Uninstallstring = $UninstallString -replace 'msiexec.exe', '' -replace 'msiexec', '' -replace '/i', '' -replace '/qn', '' -replace '/qb', '' -replace '/quiet', '' -replace '/passive', '' -replace '/qr', '' -replace '/qf', ''
                    $Uninstallstring = $UninstallString + ' ' + '/qn'

                    Write-Verbose "Start uninstallation"
                    Write-Verbose "Uninstaller: $Uninstaller"
                    Write-Verbose "Uninstall arguments: $UninstallString"
                    $ExitCode = (Start-Process -FilePath $Uninstaller -ArgumentList $UninstallString -Wait -PassThru).ExitCode
                }
                elseif ($UninstallString -match '.exe') {
                    Write-Verbose "Start uninstallation"
                    Write-Verbose "Uninstall command: $UninstallString"
                    & $UninstallString | Out-Null
                    $ExitCode = $LASTEXITCODE
                }
                else {
                    Throw "Error: Only '.msi' and '.exe' files are supported. If you need to run a script to uninstall something please use 'Install-vlApplication'. - Line Number: $($_.InvocationInfo.ScriptLineNumber)"
                }

                Write-Output -InputObject $ExitCode
            }
            
            if ($Computer -eq $env:COMPUTERNAME) {
                # running locally
                $c = $env:COMPUTERNAME
                $ExitCode = Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $PSBoundParameters -Verbose:$VerbosePreference

                # after installation
                if ($ValidExitCodes -notcontains $ExitCode) {
                    $Results += [PSCustomObject]@{Computer = $c; Success = $false }
                    Write-Error "Installation not successful. Exit code: $ExitCode"
                }
                else {
                    Write-Verbose "Installation successful. Exit code: $ExitCode"
                    $Results += [PSCustomObject]@{Computer = $c; Success = $true }
                    If ($RebootAfterSuccess) {
                        Write-Verbose "Reboot desired by parameter. Reboot $c."
                        Restart-Computer -ComputerName $c -Timeout 30
                    }
                }
            }
            else {
                # running remotely
                foreach ($c in $Computer) {
                    Write-Verbose "Test connectivitiy to computer $c"
                    if (Test-vlConnection -Computer $c) {
                        $ExitCode = Invoke-Command -ComputerName $c -ScriptBlock $scriptBlock -ArgumentList $PSBoundParameters -Credential $Credential -Verbose:$VerbosePreference
                    }

                    # after installation
                    if ($ValidExitCodes -notcontains $ExitCode) {
                        $Results += [PSCustomObject]@{Computer = $c; Success = $false }
                        Write-Error "Installation not successful. Exit code: $ExitCode"
                    }
                    else {
                        Write-Verbose "Installation successful. Exit code: $ExitCode"
                        $Results += [PSCustomObject]@{Computer = $c; Success = $true }
                        If ($RebootAfterSuccess) {
                            Write-Verbose "Reboot desired by parameter. Reboot $c."
                            Restart-Computer -ComputerName $c -Timeout 30
                        }
                    }
                }
        
            }
        }
        catch {
            $Results += [PSCustomObject]@{Computer = $c; Result = $false }
            Write-Error -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)"
        }
        finally {
        }
    }

    end {
        Write-Output $Results
    }
}