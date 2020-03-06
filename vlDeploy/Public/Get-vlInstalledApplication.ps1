Function Get-vlInstalledApplication {
    <#
.SYNOPSIS
    Retrieves a list of all software installed on a Windows computer.
.EXAMPLE
    PS C:\> Get-vlInstalledApplication
    This example retrieves all software installed on the local computer.
.EXAMPLE
    PS C:\> (Get-vlInstalledApplication -Computer PC1 -Name 'Google Chrome').UninstallString
    Returns only the uninstall string of Google Chrome from PC1
.PARAMETER Computer
    If querying a remote computer, use the computer name here.
.PARAMETER Name
    The software title you'd like to limit the query to. Does a '-match' comparison.
.PARAMETER Guid
    The software GUID you'd like to limit the query to.
.PARAMETER SilentUninstallerAvailable
    Limit the output to software with a silent uninstall string available.
.NOTES
    Based on https://adamtheautomator.com/powershell-get-installed-software/

    Author: vast limits GmbH
#>
    [OutputType([System.Management.Automation.PSObject])]
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]$Computer = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,
        
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]$Name,
        
        [Parameter()]
        [guid]$Guid,
        
        [Parameter()]
        [switch]$SilentUninstallerAvailable
    )
    begin {

    }
    process {
        try {
            $scriptBlock = {
                If ($args[0].ContainsKey('Verbose')) {
                    $VerbosePreference = 'Continue'
                }
                $args[0].GetEnumerator() | ForEach-Object { New-Variable -Name $_.Key -Value $_.Value }

                $UninstallKeys = @(
                    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
                    "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
                )
                New-PSDrive -Name HKU -PSProvider Registry -Root Registry::HKEY_USERS | Out-Null
                $UninstallKeys += Get-ChildItem HKU: | Where-Object { $_.Name -match 'S-\d-\d+-(\d+-){1,14}\d+$' } | ForEach-Object {
                    "HKU:\$($_.PSChildName)\Software\Microsoft\Windows\CurrentVersion\Uninstall"
                }
                if (-not $UninstallKeys) {
                    Write-Warning -Message 'No software registry keys found'
                }
                else {
                    foreach ($UninstallKey in $UninstallKeys) {
                        $friendlyNames = @{
                            'DisplayName'    = 'Name'
                            'DisplayVersion' = 'Version'
                        }
                        Write-Verbose -Message "Checking uninstall key [$($UninstallKey)]"
                        if ($Name) {
                            $WhereBlock = { $_.GetValue('DisplayName') -match "$Name" }
                        }
                        elseif ($GUID) {
                            $WhereBlock = { $_.PsChildName -eq $Guid.Guid }
                        }
                        else {
                            $WhereBlock = { $_.GetValue('DisplayName') }
                        }
                        
                        Write-Verbose "where block = $WhereBlock"
                        if ($SilentUninstallerAvailable.IsPresent) {
                            $WhereBlock2 = { ($_.GetValue('UninstallString') -match 'msiexec.exe') -OR ($_.GetValue('QuietUninstallString')) }
                            $SwKeys = Get-ChildItem -Path $UninstallKey -ErrorAction SilentlyContinue | Where-Object $WhereBlock | Where-Object $WhereBlock2
                            
                        }
                        else {
                            $SwKeys = Get-ChildItem -Path $UninstallKey -ErrorAction SilentlyContinue | Where-Object $WhereBlock
                        }
                        
                        if (-not $SwKeys) {
                            Write-Verbose -Message "No software keys in uninstall key $UninstallKey"
                        }
                        else {
                            foreach ($SwKey in $SwKeys) {
                                $output = @{ }
                                foreach ($ValName in $SwKey.GetValueNames()) {
                                    if ($ValName -ne 'Version') {
                                        $output.InstallLocation = ''
                                        if ($ValName -eq 'InstallLocation' -and 
                                            ($SwKey.GetValue($ValName)) -and 
                                            (@('C:', 'C:\Windows', 'C:\Windows\System32', 'C:\Windows\SysWOW64') -notcontains $SwKey.GetValue($ValName).TrimEnd('\'))) {
                                            $output.InstallLocation = $SwKey.GetValue($ValName).TrimEnd('\')
                                        }
                                        [string]$ValData = $SwKey.GetValue($ValName)
                                        if ($friendlyNames[$ValName]) {
                                            $output[$friendlyNames[$ValName]] = $ValData.Trim() # Some registry values have trailing spaces.
                                        }
                                        else {
                                            $output[$ValName] = $ValData.Trim() # Some registry values trailing spaces
                                        }
                                    }
                                }
                                $output.GUID = ''
                                if ($SwKey.PSChildName -match '\b[A-F0-9]{8}(?:-[A-F0-9]{4}){3}-[A-F0-9]{12}\b') {
                                    $output.GUID = $SwKey.PSChildName
                                }
                                If ($output.QuietUninstallString) {
                                    $output.UninstallString = $output.QuietUninstallString # if this is not a msiexec uninstall than make sure that we only get back silent uninstall strings
                                    $output.QuietUninstallString = $output.QuietUninstallString -replace '"', '`"' # escape quotation marks so that 'Uninstall-vlApplication' can handle pipeline input correctly
                                    #$output.QuietUninstallString = '"' + $output.QuietUninstallString + '"'
                                }
                                $output.UninstallString = $output.UninstallString -replace '"', '`"'  # escape quotation marks so that 'Uninstall-vlApplication' can handle pipeline input correctly
                                #$output.UninstallString = '"' + $output.UninstallString + '"'
                                New-Object -TypeName PSObject -Prop $output
                            }
                        }
                    }
                }
            }

            if ($Computer -eq $env:COMPUTERNAME) {
                Invoke-Command -ScriptBlock $scriptBlock -ArgumentList $PSBoundParameters -Verbose:$VerbosePreference
            }
            else {
                Invoke-Command -ComputerName $Computer -ScriptBlock $scriptBlock -ArgumentList $PSBoundParameters -Credential $Credential -Verbose:$VerbosePreference
            }
        }
        catch {
            Write-Error -Message "Error: $($_.Exception.Message) - Line Number: $($_.InvocationInfo.ScriptLineNumber)"
        }
    }
}