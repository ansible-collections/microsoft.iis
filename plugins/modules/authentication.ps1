#!powershell
# GNU General Public License v3.0+
# (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
#AnsibleRequires -CSharpUtil Ansible.Basic

# Note: If troubleshooting, use $DebugPreference = 'Continue' and Start-Transcript <filepath>
# in order to get debug output to a readable location. Ansible does not store debug stream output.

$ErrorActionPreference = 'Stop'
$spec = @{
    options = @{
        site = @{ required = $true; type = 'str' }
        application = @{ required = $false; type = 'str' }
        auth_type = @{
            required = $true
            type = 'str'
            choices = @(
                'AnonymousAuthentication'
                'BasicAuthentication'
                'ClientCertificateMappingAuthentication'
                'DigestAuthentication'
                'IISClientCertificateMappingAuthentication'
                'WindowsAuthentication'
            )
        }
        enabled = @{ required = $false; type = 'bool' }
        providers = @{ required = $false; type = 'list'; elements = 'str' }
        use_kernel_mode = @{ required = $false; type = 'bool' }
        token_checking = @{ required = $false; type = 'str'; no_log = $false; choices = @('None', 'Allow', 'Require') }
    }
    supports_check_mode = $true
}
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
try {
    if ($null -eq (Get-Module 'WebAdministration' -ErrorAction SilentlyContinue)) {
        Import-Module WebAdministration
    }
}
catch {
    $module.FailJson("Failed to ensure WebAdministration module is loaded: $($_.Exception.Message)", $_)
}

$site = $module.Params.site
$application = $module.Params.application
$authType = $module.Params.auth_type
$enabled = $module.Params.enabled
$providers = $module.Params.providers
$useKernelMode = $module.Params.use_kernel_mode
$tokenChecking = $module.Params.token_checking

$module.Diff.before = $null
$module.Diff.after = $null

if ($authType -ne 'WindowsAuthentication') {
    $windowsOnlySupplied = @()
    if ($null -ne $providers) { $windowsOnlySupplied += 'providers' }
    if ($null -ne $useKernelMode) { $windowsOnlySupplied += 'use_kernel_mode' }
    if ($null -ne $tokenChecking) { $windowsOnlySupplied += 'token_checking' }
    if ($windowsOnlySupplied.Count -gt 0) {
        $module.Warn("The option(s) $($windowsOnlySupplied -join ', ') are only valid with auth_type=WindowsAuthentication and are ignored for $authType.")
    }
}

function Get-IISAuthConfig {
    <#
        Reads the current authentication configuration at the target location and returns it as a
        hashtable whose keys map to the module options.
    #>
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [Ansible.Basic.AnsibleModule]
        $Module,

        [Parameter(Mandatory = $true)]
        [String]
        $PSPath,

        [Parameter(Mandatory = $true)]
        [String]
        $Location,

        [Parameter(Mandatory = $true)]
        [String]
        $AuthType
    )

    $filter = "system.webServer/security/authentication/$AuthType"
    try {
        $currentConfig = Get-WebConfiguration -PSPath $PSPath -Location $Location -Filter $filter
    }
    catch {
        $Module.FailJson("Error retrieving authentication configuration for '$AuthType': $($_.Exception.Message)", $_)
    }

    $current = @{ enabled = [bool]$currentConfig.enabled }
    if ($AuthType -eq 'WindowsAuthentication') {
        $current.providers = @($currentConfig.providers.Collection | ForEach-Object { $_.value })
        $current.use_kernel_mode = [bool]$currentConfig.useKernelMode
        $current.token_checking = [string]$currentConfig.extendedProtection.tokenChecking
    }
    return $current
}

function Compare-IISAuth {
    <#
        Returns $true when the current and desired authentication states describe the same
        configuration for the given authentication type.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $CurrentState,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $DesiredState,

        [Parameter(Mandatory = $true)]
        [String]
        $AuthType
    )

    if ($CurrentState.enabled -ne $DesiredState.enabled) {
        return $false
    }
    if ($AuthType -eq 'WindowsAuthentication') {
        return (($CurrentState.providers -join ',') -eq ($DesiredState.providers -join ',')) -and
        ($CurrentState.use_kernel_mode -eq $DesiredState.use_kernel_mode) -and
        ($CurrentState.token_checking -eq $DesiredState.token_checking)
    }
    return $true
}

function Set-IISAuthConfig {
    <#
        Writes the desired authentication state at the target location, changing only the properties
        that differ from the current state. Every authentication section is delegated down to the
        site/application level, so the write is addressed at 'IIS:\' with the site/application as the
        Location, which commits a <location> entry to ApplicationHost.config.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [Ansible.Basic.AnsibleModule]
        $Module,

        [Parameter(Mandatory = $true)]
        [String]
        $PSPath,

        [Parameter(Mandatory = $true)]
        [String]
        $Location,

        [Parameter(Mandatory = $true)]
        [String]
        $AuthType,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $CurrentState,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]
        $DesiredState
    )

    $filter = 'system.webServer/security/authentication'
    $setSplat = @{ PSPath = $PSPath; Location = $Location }

    if ($AuthType -eq 'WindowsAuthentication') {
        if ($CurrentState.enabled -ne $DesiredState.enabled) {
            if ($PSCmdlet.ShouldProcess($AuthType, "Set enabled to $($DesiredState.enabled)")) {
                try {
                    Set-WebConfigurationProperty @setSplat -Filter "$filter/WindowsAuthentication" -Name 'enabled' -Value $DesiredState.enabled
                }
                catch {
                    $Module.FailJson("Error setting WindowsAuthentication enabled to $($DesiredState.enabled): $($_.Exception.Message)", $_)
                }
            }
        }
        if (($CurrentState.providers -join ',') -ne ($DesiredState.providers -join ',')) {
            if ($PSCmdlet.ShouldProcess($AuthType, 'Set providers')) {
                try {
                    Remove-WebConfigurationProperty @setSplat -Filter "$filter/WindowsAuthentication/providers" -Name 'collection'
                    foreach ($provider in $DesiredState.providers) {
                        Add-WebConfigurationProperty @setSplat -Filter "$filter/WindowsAuthentication/providers" -Name '.' -Value @{ value = $provider }
                    }
                }
                catch {
                    $Module.FailJson("Error setting providers for WindowsAuthentication: $($_.Exception.Message)", $_)
                }
            }
        }
        if ($CurrentState.use_kernel_mode -ne $DesiredState.use_kernel_mode) {
            if ($PSCmdlet.ShouldProcess($AuthType, "Set useKernelMode to $($DesiredState.use_kernel_mode)")) {
                try {
                    Set-WebConfigurationProperty @setSplat -Filter "$filter/WindowsAuthentication" -Name 'useKernelMode' -Value $DesiredState.use_kernel_mode
                }
                catch {
                    $Module.FailJson("Error setting useKernelMode for WindowsAuthentication: $($_.Exception.Message)", $_)
                }
            }
        }
        if ($CurrentState.token_checking -ne $DesiredState.token_checking) {
            if ($PSCmdlet.ShouldProcess($AuthType, "Set tokenChecking to $($DesiredState.token_checking)")) {
                try {
                    Set-WebConfigurationProperty @setSplat -Filter "$filter/WindowsAuthentication/extendedProtection" -Name 'tokenChecking' -Value $DesiredState.token_checking
                }
                catch {
                    $Module.FailJson("Error setting tokenChecking for WindowsAuthentication: $($_.Exception.Message)", $_)
                }
            }
        }
    }
    elseif ($CurrentState.enabled -ne $DesiredState.enabled) {
        if ($PSCmdlet.ShouldProcess($AuthType, "Set enabled to $($DesiredState.enabled)")) {
            try {
                Set-WebConfigurationProperty @setSplat -Filter "$filter/$AuthType" -Name 'enabled' -Value $DesiredState.enabled
            }
            catch {
                $Module.FailJson("Error setting $AuthType enabled to $($DesiredState.enabled): $($_.Exception.Message)", $_)
            }
        }
    }
}

if (-not (Get-Website -Name $site)) {
    $module.FailJson("Unable to resolve an IIS site named '$site'. Verify the site exists on the target host.")
}
if ($application -and -not (Test-Path -LiteralPath "IIS:\Sites\$site\$application")) {
    $module.FailJson("Unable to resolve an application or virtual directory named '$application' under site '$site'. Verify it exists on the target host.")
}
$location = if ($application) { "$site/$application" } else { $site }
$module.Result.target = if ($application) { "IIS:\Sites\$site\$application" } else { "IIS:\Sites\$site" }

# Authentication sections are delegated to the site/application level, so every read and write is
# addressed at 'IIS:\' with the site/application supplied as the Location, which resolves to the
# matching <location> entry in ApplicationHost.config.
$authSplat = @{
    PSPath = 'IIS:\'
    Location = $location
    AuthType = $authType
}

$before = Get-IISAuthConfig -Module $module @authSplat
$module.Diff.before = $before

# A supplied option overrides the current value; an option left unset keeps the current value so it
# is not changed.
$after = @{ enabled = if ($null -ne $enabled) { $enabled } else { $before.enabled } }
if ($authType -eq 'WindowsAuthentication') {
    $after.providers = if ($null -ne $providers) { @($providers) } else { $before.providers }
    $after.use_kernel_mode = if ($null -ne $useKernelMode) { $useKernelMode } else { $before.use_kernel_mode }
    $after.token_checking = if ($null -ne $tokenChecking) { $tokenChecking } else { $before.token_checking }
}

if (Compare-IISAuth -CurrentState $before -DesiredState $after -AuthType $authType) {
    $module.Diff.after = $before
}
else {
    $module.Result.changed = $true
    Set-IISAuthConfig -Module $module @authSplat -CurrentState $before -DesiredState $after -WhatIf:$module.CheckMode
    if ($module.CheckMode) {
        $module.Diff.after = $after
    }
    else {
        $afterState = Get-IISAuthConfig -Module $module @authSplat
        $module.Diff.after = $afterState
        if (-not (Compare-IISAuth -CurrentState $afterState -DesiredState $after -AuthType $authType)) {
            $module.FailJson("Authentication settings did not match the desired state after applying changes for '$authType'.")
        }
    }
}

$module.ExitJson()
