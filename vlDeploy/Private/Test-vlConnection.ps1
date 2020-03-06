function Test-vlConnection {
    <#
        .SYNOPSIS
        Tests the connectivity to a remote copmuter
    #>

    [OutputType([System.Boolean])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Alias('Computername', '__Server', 'CN')]
        [System.String]
        $Computer,
        
        [Switch]
        $TestAdminShare
    )
    
    $Success = $true
    If (-not (Test-Connection -ComputerName $Computer -Count 1 -quiet)) {
        Write-Error "$Computer cannot be reached"
        $Success = $false
    }
    If ($TestAdminShare.IsPresent) {
        If (-not (Test-Path "\\$Computer\c$")) {
            Write-Error "$Computer 's admin share is unavailable"
            $Success = $false
        }
    }

    Write-Output -InputObject $Success
}