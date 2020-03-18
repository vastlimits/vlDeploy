# vlDeploy

`vlDeploy` is a PowerShell module publically available in the PowerShell gallery. It allows the installation of applications locally, or even better, remotely. The remoting capability enables administrators to push applications to multiple machines.

Here is a list of its features:
- Gets a list of installed applications locally, or, from a remote machine
- Installs applications locally, or, on remote machines
- Uninstalls applications locally, or, on remote machines
- Support for `.exe`, `.msi`, and `.ps1` installers
  - Throw the `.msi` installer at the module and it will take care of installing the application silently. Same is true for `.ps1` files.
- Support for URLs as installer
    - The installer will be downloaded and then deployed
- PowerShell pipeline support
- Valid exit codes handover
- Reboot after success

Is it a full blown application distribution and everything else can get tossed to the void? No, of course not. It has its use-cases which I'm describing in the following.

## Prerequisites

Before you begin, ensure you have met the following requirements:

* At least PowerShell version 5.0
* Windows operating system

## Installing vlDeploy

The module is availabe in the PowerShell Gallery. To install `vlDeploy`, follow these steps:

```
Install-Module vlDeploy
```

## Using vlDeploy

`vlDeploy` exposes three functions to list installed applications, install applications, and uninstall applications. 

To see what's possible with each, use:
```
Get-Help Install-vlApplication -full
Get-Help Uninstall-vlApplication -full
Get-Help Get-vlInstalledApplication -full
```

### Examples

Simple application installation on a remote machine.
```
$cred = Get-Credential
Install-vlApplication -Computer PC1 -Sourcefiles 'C:\apps\source' -Installer Setup.exe -InstallerArguments '/silent /noreboot' -Credential $cred
```


Application installation on a remote machine with a PowerShell script downloaded from the Internet.
```
$cred = Get-Credential
Install-vlApplication -Computer PC1 -Installer 'https://somewebsite.com/apps/Install.ps1' -Credential $cred
```


`Install-vlApplication` accepts pipeline input for the `-Computer` parameter , which makes it easy to mass-deploy applications. It also recognizes `.msi` installer files and builds the full install command automatically. 
```
$cred = Get-Credential
'PC1', 'PC2', 'PC3' | Install-vlApplication -Sourcefiles 'C:\apps\source' -Installer Setup.msi -Credential $cred
```


Get the uninstall string of an application from a remote machine and uninstall it there. Valid exit codes are `0`, `3010`, and `1` (default `0` and `3010`). 
```
$cred = Get-Credential
Get-vlInstalledApplication -Computer PC1 -Name 'Google Chrome' -Credential $cred | Uninstall-vlApplication -Credential $cred -ValidExitCodes 0,3010,1
```


Get the uninstall string of an application from a remote machine and uninstall it on multiple machines. Reboot every machine if uninstallation was successful.
```
$cred = Get-Credential
$UninstallString = (Get-vlInstalledApplication -Computer PC1 -Name 'Google Chrome' -Credential $cred).UninstallString
PC1', 'PC2', 'PC3' | Uninstall-vlApplication -UninstallString $UninstallString -Credential $cred -RebootAfterSuccess
```

## Contributing to vlDeploy

To contribute to `vlDeploy`, follow these steps:

1. Fork this repository.
2. Create a branch: `git checkout -b <branch_name>`.
3. Make your changes and commit them: `git commit -m '<commit_message>'`
4. Push to the original branch: `git push origin vlDeploy/master`
5. Create the pull request.

Alternatively see the GitHub documentation on [creating a pull request](https://help.github.com/en/github/collaborating-with-issues-and-pull-requests/creating-a-pull-request).

## License

This project uses the following license: [Apache](http://www.apache.org/licenses/).

## Support

This software is released as-is. vast limits provides no warranty and no support on this software. If you have any issues with the software, please file an issue on the repository.

