Function Install-vlApplication {
    <#
.SYNOPSIS
    Installs an application either locally or remotely
.PARAMETER Installer
    Specifies the path to the installer. Supported installers are .exe, .msi, and .ps1 files.
    When the installer requires additional files the parameter '-Sourcefiles' is needed, too.
.PARAMETER InstallerArgument
    Specifies the silent installer arguments. 'Install-vlApplication' handles required silent arguments for msis und PowerShell scripts automatically.
    Arguments for PowerShell skripts are not supported.
.PARAMETER Sourcefiles
    Only needed when the installer needs additional files. If you specify this parameter, the installer has to be in the root of your sourcefiles.
        - Correct: Install-vlApplication -Sourcefiles C:\myapp -Installer Setup.exe
        - Wrong: Install-vlApplication -Sourcefiles C:\myapp -Installer C:\myapp\subfolder\Setup.exe
.PARAMETER Computer
    A computer name or a list of computer names where the application should be installed. Defaults to the local computer. Pipeline input is supported.
.PARAMETER Credential
    Specifies the credentials when installation on a remote computer is desired.
.PARAMETER RebootAfterSuccess
    Reboots the targeted computer if the installation was successful
.PARAMETER ValidExitCodes
    Specifies the exit code for a successful installation.
.EXAMPLE 
    PS C:\> Install-vlApplication -Computer PC1 -Installer Setup.exe -InstallerArguments '/silent /noreboot' -Credential (Get-Credential)
    Simple application install on a remote machine
.EXAMPLE 
    PS C:\> 'PC1', 'PC2', 'PC3' | Install-vlApplication -Installer Setup.msi -Credential (Get-Credential)
    'Install-vlApplication' accepts pipeline input for the '-Computer' parameter , which makes it easy to mass-deploy applications.
.INPUTS
    Function accepts pipeline input for '-Computer'
.OUTPUTS
    Outputs a PowerShell object containing results of the installation(s)
.NOTES
    Author: vast limits GmbH
#>
    [OutputType([System.Management.Automation.PSObject])]
    [CmdletBinding()]
    PARAM
    (
        [Parameter(Mandatory = $true)]
        [System.String]$Installer,
    
        [Parameter()]
        [System.String]$InstallerArguments,

        [Parameter()]
        [ValidateScript( {
                if (-Not ($_ | Test-Path) ) {
                    throw "Folder does not exist" 
                }
                if (-Not ($_ | Test-Path -PathType Container) ) {
                    throw "The sourcefiles argument must be a folder. File paths are not allowed."
                }
                return $true
            })]
        [System.IO.FileInfo]$Sourcefiles,

        [Parameter(ValueFromPipeline = $True)]
        [Alias('Computername', '__Server', 'CN')]
        [System.String[]]$Computer = $env:computername,

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
        Try {
            # Initialize output
            $Results = @()

            # Sourcefiles and installer checks
            $InstallerIsURL = $false
            If ($Sourcefiles) {
                $FullInstallerPath = Join-Path -Path $Sourcefiles -ChildPath $Installer.split('\\')[-1]
                if (-not (Test-Path $FullInstallerPath)) {
                    Throw "Cannot find installer. Installer has to be in the root of $Sourcefiles. Current full path: $FullInstallerPath"
                }
            }
            Else {
                if ($Installer -match '^https?://') {
                    Write-Verbose "Installer is an URL. Download installer."
                    $OutFile = Join-Path -Path $env:TMP -ChildPath $Installer.split('/')[-1]
                    if (-not(Test-Path $OutFile)) {
                        Invoke-WebRequest -UseBasicParsing -Uri $Installer -OutFile $OutFile
                        if ($OutFile.split('.')[-1] -eq 'ps1'){
                            Write-Verbose "Installer is a PowerShell script. Unblock file."
                            Unblock-File -Path $OutFile
                        }
                    }
                    else {
                        Write-Verbose "Installer $OutFile already exists"
                    }
                    $Installer = $OutFile
                    $InstallerIsURL = $true
                }
            }

            # Reset variables depending on installer
            $InstallerExtension = $Installer.Split('.')[-1]
            Write-Verbose "Installer extension = $InstallerExtension"

            switch ($InstallerExtension) {
                msi {
                    $Log = $Installer.split('\\')[-1] + '.log' # take only the installer filename and append .log
                    $PSBoundParameters['InstallerArguments'] -replace '/i', '' -replace '/qn', '' -replace '/qb', '' -replace '/quiet', '' -replace '/passive', '' -replace '/qr', '' -replace '/qf', ''
                    $PSBoundParameters['InstallerArguments'] = '/i' + ' ' + $Installer.split('\\')[-1] + ' ' + "/qn /norestart /l*v `"C:\Windows\temp\$Log`"" + ' ' + $InstallerArguments
                    $PSBoundParameters['Installer'] = 'msiexec.exe'
                }

                ps1 {
                    If ($InstallerArguments) {
                        Throw 'Running PowerShell files with arguments is not supported'
                    }
                    $PSBoundParameters['InstallerArguments'] = '-executionpolicy bypass -NoProfile -file ' + $Installer.split('\\')[-1]
                    $PSBoundParameters['Installer'] = Join-Path -Path $env:windir -ChildPath "System32\WindowsPowerShell\v1.0\powershell.exe"
                }

                exe {
                    $PSBoundParameters['Installer'] = $Installer.split('\\')[-1]
                }

                Default {
                    Throw "$InstallerExtension files are not supported"
                }
            }

            #
        }
        Catch {
            Write-Error -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)"
        }
    }
   
    Process {
        Try {
            $scriptBlock = {
                If ($args[0].ContainsKey('Verbose')) {
                    $VerbosePreference = 'Continue'
                }
                $args[0].GetEnumerator() | ForEach-Object { New-Variable -Name $_.Key -Value $_.Value }
                Write-Verbose "Start installation"
                Write-Verbose "Installer: $Installer"
                Write-Verbose "Installer arguments: $InstallerArguments"
                
                $InstallFolder = "C:\Windows\temp\vl_sourcefiles"
                Set-Location $InstallFolder
                $ExitCode = (Start-Process -FilePath $Installer -ArgumentList $InstallerArguments -Wait -Passthru).ExitCode
                Set-Location $env:SystemRoot

                Remove-Item $InstallFolder -Recurse -Force

                Write-Output -InputObject $ExitCode
            }

            if ($Computer -eq $env:COMPUTERNAME) {
                $Mode = 'local'
                $c = $env:COMPUTERNAME
                
                Write-Verbose "Clear mess of old installations if any"
                Remove-Item "C:\Windows\Temp\vl_Sourcefiles" -Recurse -Force -ErrorAction SilentlyContinue

                Write-Verbose "Copy sourcefiles"
                New-Item -Path "C:\Windows\Temp\vl_sourcefiles" -Force -ItemType Directory | Out-Null
                If ($Sourcefiles) {
                    Copy-Item -Path "$Sourcefiles\*" -Destination "C:\Windows\Temp\vl_sourcefiles" -Recurse -Force
                }
                Else {
                    Copy-Item -Path $Installer -Destination "C:\Windows\Temp\vl_sourcefiles" -Force
                }

                $ExitCode = Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $PSBoundParameters

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
                $Mode = 'remote'
                foreach ($c in $Computer) {
                    Write-Verbose "Test connectivitiy to computer $c"
                    if (Test-vlConnection -Computer $c -TestAdminShare) {

                        Write-Verbose "Clear mess of old installations if any"
                        Invoke-Command -ComputerName $c -ScriptBlock { Remove-Item "C:\Windows\Temp\vl_sourcefiles" -Recurse -Force -ErrorAction SilentlyContinue } -Credential $Credential -Verbose:$VerbosePreference

                        Write-Verbose "Copy sourcefiles to target"
                        $FreeDrive = (68..90 | ForEach-Object { $Letter = [char]$_; if ((Get-PSDrive).Name -notContains $Letter) { $Letter } })[0] # Get free drive from D onwards
                        $RemoteDrive = (New-PSDrive -Name $FreeDrive -PSProvider FileSystem -Root "\\$c\c$\windows\temp" -Credential $Credential).Root

                        New-Item -Path $RemoteDrive -Name 'vl_sourcefiles' -Force -ItemType Directory | Out-Null
                        If ($Sourcefiles) {
                            Copy-Item -Path "$Sourcefiles\*" -Destination "$RemoteDrive\vl_sourcefiles" -Recurse -Force
                        }
                        Else { 
                            Copy-Item -Path $Installer -Destination "$RemoteDrive\vl_sourcefiles" -Force
                        }
                        Remove-PSDrive -Name $FreeDrive -Force

                        $ExitCode = Invoke-Command -ComputerName $c -ScriptBlock $scriptBlock -ArgumentList $PSBoundParameters -Credential $Credential -Verbose:$VerbosePreference

                        # after installation
                        if ($ValidExitCodes -notcontains $ExitCode) {
                            $Results += [PSCustomObject]@{Computer = $c; Success = $false }
                            Write-Error "Installation not successful. Exit code: $ExitCode"
                        }
                        else {
                            Write-Verbose "Installation successful on computer $c. Exit code: $ExitCode"
                            $Results += [PSCustomObject]@{Computer = $c; Success = $true }
                            If ($RebootAfterSuccess) {
                                Write-Verbose "Reboot desired by parameter. Reboot $c."
                                Restart-Computer -ComputerName $c -Timeout 30
                            }
                        }
                    }
                }
            }
        }
        catch {
            $Results += [PSCustomObject]@{Computer = $c; Result = $false }
            Write-Error -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)"

            # cleanup
            if ($Mode -eq 'local') {
                Remove-Item "c:\windows\temp\vl_sourcefiles" -Recurse -Force -ErrorAction SilentlyContinue
            }
            elseif ($Mode -eq 'remote') {
                Invoke-Command -ComputerName $c -ScriptBlock { Remove-Item "C:\Windows\Temp\vl_sourcefiles" -Recurse -Force -ErrorAction SilentlyContinue } -Credential $Credential
                Remove-PSDrive -Name $FreeDrive -Force -ErrorAction SilentlyContinue
            }
        }

        Finally {
            
        }
        
    }
    End {
        if ($InstallerIsURL) {
            Remove-Item -Path $OutFile -Force -ErrorAction SilentlyContinue
        }
        Write-Output $Results
    }
}