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
        page_order = @{ required = $true; type = 'list'; elements = 'str' }
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
$pageOrder = $module.Params.page_order
$filter = 'system.webServer/defaultDocument/files'

$module.Diff.before = $null
$module.Diff.after = $null

function Get-IISPageOrder {
    <#
        Returns the currently configured default document order as an ordered array of page names.
    #>
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [Ansible.Basic.AnsibleModule]
        $Module,

        [Parameter(Mandatory = $true)]
        [String]
        $IisPath,

        [Parameter(Mandatory = $true)]
        [String]
        $Filter
    )

    try {
        $config = Get-WebConfigurationProperty -PSPath $IisPath -Filter $Filter -Name 'collection'
    }
    catch {
        $Module.FailJson("Error retrieving web configuration: $($_.Exception.Message)", $_)
    }
    @($config | ForEach-Object { $_.value })
}

function Set-IISPageOrder {
    <#
        Applies the desired default document order. The existing collection is removed first because
        Add-WebConfigurationProperty inserts at the beginning, so the desired order is added in reverse.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [Ansible.Basic.AnsibleModule]
        $Module,

        [Parameter(Mandatory = $true)]
        [String]
        $IisPath,

        [Parameter(Mandatory = $true)]
        [String]
        $Filter,

        [Parameter(Mandatory = $true)]
        [String[]]
        $PageOrder,

        [Parameter(Mandatory = $true)]
        [bool]
        $HasExisting
    )

    if ($PSCmdlet.ShouldProcess($IisPath, 'Set default document order')) {
        if ($HasExisting) {
            try {
                Remove-WebConfigurationProperty -PSPath $IisPath -Filter $Filter -Name 'collection'
            }
            catch {
                $Module.FailJson("Error removing existing page order. Exception: $($_.Exception.Message)", $_)
            }
        }
        for ($index = $PageOrder.Length - 1; $index -ge 0; $index--) {
            try {
                Add-WebConfigurationProperty -PSPath $IisPath -Filter $Filter -Name 'Collection' -Value $PageOrder[$index] -ErrorAction 'Stop'
            }
            catch {
                $Module.FailJson("Error adding page order. Exception: $($_.Exception.Message)", $_)
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
$target = if ($application) { "IIS:\Sites\$site\$application" } else { "IIS:\Sites\$site" }
$module.Result.target = $target
$currentOrder = @(Get-IISPageOrder -Module $module -IisPath $target -Filter $filter)
$desiredOrder = @($pageOrder)

if ($currentOrder.Count -gt 0) {
    $module.Diff.before = @{ page_order = $currentOrder }
}

if (($currentOrder -join ',') -ne ($desiredOrder -join ',')) {
    $module.Result.changed = $true
    Set-IISPageOrder -Module $module -IisPath $target -Filter $filter -PageOrder $desiredOrder `
        -HasExisting ($currentOrder.Count -gt 0) -WhatIf:$module.CheckMode
    if ($module.CheckMode) {
        $module.Diff.after = @{ page_order = $desiredOrder }
    }
    else {
        $afterOrder = @(Get-IISPageOrder -Module $module -IisPath $target -Filter $filter)
        $module.Diff.after = @{ page_order = $afterOrder }
        if (($afterOrder -join ',') -ne ($desiredOrder -join ',')) {
            $module.FailJson("Default document order did not match the desired state after applying changes. Current: $($afterOrder -join ','), desired: $($desiredOrder -join ',').")
        }
    }
}
elseif ($currentOrder.Count -gt 0) {
    $module.Diff.after = @{ page_order = $currentOrder }
}

$module.ExitJson()
