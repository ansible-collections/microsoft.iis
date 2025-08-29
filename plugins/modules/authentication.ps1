
#!powershell
# GNU General Public License v3.0+
# (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell Ansible.ModuleUtils.AddType

# Note: If troubleshooting, use $DebugPreference = 'Continue' and Start-Transcript <filepath>
# in order to get debug output to a readable location. Ansible does not store debug stream output.
$ErrorActionPreference = 'Stop'
$spec = @{
    options = @{
        ps_path = @{ default = 'IIS:\'; required = $false; type = 'str' }
        location = @{ required = $false; type = 'str' }
        auth_type = @{ required = $true; type = 'str' }
        enabled = @{ required = $true; type = 'bool' }
        providers = @{ required = $false; type = 'str' }
        usekernelmode = @{ required = $false; type = 'bool' }
        # yamllint disable rule:no-log-needed
        tokenchecking = @{ required = $false; type = 'str' }
    }
    required_if = @(
        , @('auth_type', 'WindowsAuthentication', @('providers', 'usekernelmode', 'tokenchecking'))
    )
    supports_check_mode = $true
}
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
Write-Debug $module
try {
    if ($null -eq (Get-Module 'WebAdministration' -ErrorAction SilentlyContinue)) {
        Import-Module WebAdministration
    }
}
catch {
    $module.FailJson("Failed to ensure WebAdministration module is loaded: $_", $_)
}

$psPath = $module.Params.ps_path
$location = $module.Params.location
$authType = $module.Params.auth_type
$enabled = $module.Params.enabled
$Providers = $module.Params.providers
$UseKernelMode = $module.Params.usekernelmode
$tokenChecking = $module.Params.tokenchecking
$module.Result.diff = @{
    before = ''
    after = ''
}
$module.Result.msg = ''
function Get-IISAuthConfig {
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [Ansible.Basic.AnsibleModule]
        $Module,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [String]
        $PSPath = 'IIS:/',

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $AuthType,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [bool]
        $Enabled,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [String]
        $Location,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [bool]
        $UseKernelMode,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]
        $TokenChecking,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Providers
    )

    Process {
        $filter = "system.webServer/security/authentication/$($AuthType)"
        $returnValue = [ordered]@{
            'result' = $true
            'providerMatch' = $true
            'enabledMatch' = $true
            'kernelModeMatch' = $true
            'tokenCheckingMatch' = $true
            'diffString' = ''
        }
        try {
            Write-Debug "Calling Get-WebConfiguration -pspath $PSPath -Location $Location -filter $filter"
            $testResult = Get-WebConfiguration -pspath $PSPath -Location $Location -filter $filter
        }
        catch {
            $module.FailJson("Error retrieving web configuration: $($_.Exception.Message)", $_)
        }
        if (!$testResult -and $authType -eq 'WindowsAuthentication') {
            Write-Debug "No testresult value for $AuthType, assuming that all values need to be set"
            $returnValue['result'] = $false
            $returnValue['enabledMatch'] = $false
            $returnValue['providerMatch'] = $false
            $returnValue['kernelModeMatch'] = $false
            $returnValue['tokenCheckingMatch'] = $false
            return $returnValue
        }
        elseif (!$testResult) {
            Write-Debug "No testresult value for $AuthType, assuming that it needs to be enabled"
            $returnValue['result'] = $false
            $returnValue['enabledMatch'] = $false
            return $returnValue
        }
        elseif ($AuthType -eq 'WindowsAuthentication') {
            # WindowsAuthentication requires additional checks
            if (($testResult.providers.collection.value -join ',') -ne ($Providers -split ',')) {
                Write-Debug "Setting result to false due to 'provider' mismatch: $($testResult.providers.collection.value):$($Providers -split ',')"
                $returnValue['result'] = $false
                $returnValue['providerMatch'] = $false
            }
            if ($testResult.enabled -ne $Enabled) {
                Write-Debug "Setting result to false due to 'Enabled' mismatch (WindowsAuth): $($testResult.enabled):$($Enabled)"
                $returnValue['result'] = $false
                $returnValue['enabledMatch'] = $false
            }
            if ($testResult.usekernelmode -ne $UseKernelMode) {
                Write-Debug "Setting result to false due to 'usekernelmode' mismatch: $($testResult.usekernelmode):$($UseKernelMode)"
                $returnValue['result'] = $false
                $returnValue['kernelModeMatch'] = $false
            }
            if ($testResult.extendedProtection.TokenChecking -ne $TokenChecking) {
                Write-Debug "Setting result to false due to 'TokenChecking' mismatch: $($testResult.TokenChecking):$($TokenChecking)"
                $returnValue['result'] = $false
                $returnValue['tokenCheckingMatch'] = $false
            }
        }
        elseif ( ( $testResult.enabled -ne $Enabled ) -and ( $AuthType -ne 'WindowsAuthentication') ) {
            Write-Debug "Setting result to false due to 'Enabled' mismatch (non-WindowsAuth): $($testResult.enabled):$($Enabled)"
            $returnValue['result'] = $false
            $returnValue['enabledMatch'] = $false
        }
        # diffString is used for result reporting, have to use a separate variable because modifying a value in the hash breaks the loop
        $diffString = ''
        foreach ($key in $returnValue.Keys) {
            if ($key -eq 'diffString') {
                continue
            }
            if ($diffString -ne '') {
                $diffString += ';'
            }
            Write-Debug "Adding '$($key):$($returnValue[$key])' to $diffString"
            $diffString += "$($key):$($returnValue[$key])"
        }
        $returnValue['diffString'] = $diffString
        return $returnValue

    }
}
function Set-IISAuthConfig {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [Ansible.Basic.AnsibleModule]
        $Module,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [System.Collections.IDictionary]
        $GetResult,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [String]
        $PSPath = 'IIS:/',

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $AuthType,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [bool]
        $Enabled,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [String]
        $Location,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [bool]
        $UseKernelMode,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]
        $TokenChecking,

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Providers
    )

    Process {
        # Override filter for authentication to allow for specific set paths
        $filter = 'system.webServer/security/authentication'
        $setSplat = @{ PSPath = $PSPath }
        if ($Location) {
            $setSplat.Add('Location', $Location)
        }
        # Configure properties and settings
        if ($authType -eq 'WindowsAuthentication') {
            # Step 1: Set 'enabled' first if needed
            if (!$GetResult.enabledMatch) {
                if ($PSCmdlet.ShouldProcess($authType, 'Set to enabled')) {
                    try {
                        Write-Debug "Calling Set-WebConfiguration @setSplat -filter `"$($filter)/WindowsAuthentication`" -value $Enabled"
                        Set-WebConfiguration @setSplat -filter "$($filter)/WindowsAuthentication" -value $Enabled
                    }
                    catch {
                        $module.FailJson("Error setting WindowsAuthentication to $($Enabled): $($_.Exception.Message)", $_)
                    }
                }
                # After enabling, re-read config to get updated state
                $GetResult = Get-IISAuthConfig -Module $Module -PSPath $PSPath -AuthType $AuthType -Enabled $Enabled -Location $Location -UseKernelMode $UseKernelMode -TokenChecking $TokenChecking -Providers $Providers
            }

            # Step 2: Set other properties if needed (now that enabled is set)
            if (!$GetResult.kernelModeMatch) {
                if ($PSCmdlet.ShouldProcess($UseKernelMode, 'Set useKernelMode')) {
                    try {
                        Write-Debug "Calling Set-WebConfigurationProperty @setSplat -filter `"$($filter)/WindowsAuthentication`" -Name 'useKernelMode' -Value $UseKernelMode"
                        Set-WebConfigurationProperty @setSplat -filter "$($filter)/WindowsAuthentication" -Name 'useKernelMode' -Value $UseKernelMode
                    }
                    catch {
                        $module.FailJson("Error setting kernel mode for WindowsAuthentication: $($_.Exception.Message)", $_)
                    }
                }
            }
            if (!$GetResult.tokenCheckingMatch) {
                if ($PSCmdlet.ShouldProcess($TokenChecking, 'Set TokenChecking')) {
                    try {
                        Write-Debug "Calling Set-WebConfigurationProperty -pspath $PSPath -location $location -filter `"$($filter)/WindowsAuthentication/extendedProtection`" -Name 'TokenChecking' -Value $TokenChecking"
                        Set-WebConfigurationProperty @setSplat -filter "$($filter)/WindowsAuthentication/extendedProtection" -Name 'TokenChecking' -Value $TokenChecking
                    }
                    catch {
                        $module.FailJson("Error setting token checking for WindowsAuthentication: $($_.Exception.Message)", $_)
                    }
                }
            }
            if (!$GetResult.providerMatch) {
                if ($PSCmdlet.ShouldProcess($AuthType, 'Remove WindowsAuthentication provider order')) {
                    try {
                        Write-Debug "Calling Remove-WebConfigurationProperty @setSplat -Filter `"$($filter)/WindowsAuthentication/providers`" -name 'collection'"
                        Remove-WebConfigurationProperty @setSplat -Filter "$($filter)/WindowsAuthentication/providers" -name 'collection'
                    }
                    catch {
                        $module.FailJson("Error removing providers for WindowsAuthentication: $($_.Exception.Message)", $_)
                    }
                }
                foreach ($provider in ($Providers -split ',')) {
                    if ($PSCmdlet.ShouldProcess($provider, 'Add WindowsAuthentication provider')) {
                        try {
                            Write-Debug "Calling Add-WebConfiguration -Location $location -filter `"$($filter)/WindowsAuthentication/providers`" -Value $provider"
                            Add-WebConfiguration -Location $location -filter "$($filter)/WindowsAuthentication/providers" -Value $provider
                        }
                        catch {
                            $module.FailJson("Error adding $provider to WindowsAuthentication: $($_.Exception.Message)", $_)
                        }
                    }
                }
            }
        }
        else {
            # Simple enable/disable for other stuff
            if ($PSCmdlet.ShouldProcess($AuthType, "Set to $Enabled")) {
                try {
                    Write-Debug "Calling Set-WebConfigurationProperty @setSplat -Filter `"$($filter)/$($AuthType)`" -Name 'Enabled' -Value $Enabled"
                    Set-WebConfigurationProperty @setSplat -Filter "$($filter)/$($AuthType)" -Name 'Enabled' -Value $Enabled
                }
                catch {
                    $module.FailJson("Error setting $AuthType to $($Enabled): $($_.Exception.Message)", $_)
                }
            }
        }
    }
}
# Build conditional splat for modules, windows auth requires extra args
$authSplat = @{
    PSPath = $psPath
    AuthType = $authType
    Enabled = $enabled
}
if ($null -ne $location) {
    $authSplat.Add('Location', $location)
}
if ($null -ne $Providers) {
    $authSplat.Add('providers', $Providers)
}
if ($null -ne $UseKernelMode) {
    $authSplat.Add('UseKernelMode', $UseKernelMode)
}
if ($null -ne $tokenChecking) {
    $authSplat.Add('tokenChecking', $tokenChecking)
}

Write-Debug "authSplat value: $($authSplat | Out-String)"
Write-Debug "Calling Get-IISAuthConfig -Module $module @authSplat"
$beforeCheck = Get-IISAuthConfig -Module $module @authSplat
$module.Result.diff.before = $beforeCheck.diffString
if (!$beforeCheck.result) {
    # Converting k/v pairs into strings with extra whitespace replacement, so it shows it all inline.
    $module.Result.msg += $('Mismatch detected, performing set operation, check result: ' +
        "$(($beforeCheck | Out-String -Stream | Select-Object -skip 3) -replace '\s+',':' -join ',')")
    Write-Debug "Calling Set-IISAuthConfig -Module $module @authSplat -WhatIf:$($module.CheckMode)"
    Set-IISAuthConfig -Module $module -GetResult $beforeCheck @authSplat -WhatIf:$module.CheckMode
    $module.Result.changed = $true
    if (!($module.CheckMode)) {
        $afterCheck = Get-IISAuthConfig -Module $module @authSplat
        $module.Result.diff.after = $afterCheck.diffString
        if (!$afterCheck.result) {
            $module.FailJson("Settings still mismatched after running Set-IISAuthConfig: $($beforeCheck.diffString) vs $($afterCheck.diffString)")
        }
    }
}
$module.ExitJson()
