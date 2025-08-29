
#!powershell
# GNU General Public License v3.0+
# (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)
#AnsibleRequires -CSharpUtil Ansible.Basic
#AnsibleRequires -PowerShell Ansible.ModuleUtils.AddType

# Note: If troubleshooting, use $DebugPreference = 'Continue' and Start-Transcript <filepath>
# in order to get debug output to a readable location. Ansible does not store debug stream output.


$ErrorActionPreference = 'Stop'
$spec = @{
    options             = @{
        ps_path         = @{ type = 'str' }
        website_path    = @{ type = 'str' }
        page_order      = @{ type = 'str' }
        filter          = @{ type = 'str' }
        collection_name = @{ type = 'str' }
    }
    required_one_of     = @(
        , @('ps_path', 'website_path')
    )
    mutually_exclusive  = @(
        , @('ps_path', 'website_path')
    )
    supports_check_mode = $true
}
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
write-debug $module
try {
    if ($null -eq (Get-Module 'WebAdministration' -ErrorAction SilentlyContinue)) {
        Import-Module WebAdministration
    }
}
catch {
    $module.FailJson("Failed to ensure WebAdministration module is loaded: $_", $_)
}
if ($module.Params.ps_path) {
    $iisPath = $module.Params.ps_path
}
elseif ($module.Params.website_path) {
    $iisPath = $module.Params.website_path
}
else {
    throw 'No ps_path or website_path specified'
    return
}
$pageOrder = $module.Params.page_order
$filter = $module.Params.filter
$collectionName = $module.Params.collection_name
$module.Result.diff = @{
    before = ''
    after  = ''
}
$module.Result.msg = ''

function Get-IISPageOrder {
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [Ansible.Basic.AnsibleModule]
        $Module,

        [Parameter(Mandatory = $true)]
        [String]
        $IisPath,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $Filter,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $CollectionName
    )

    Process {
        $ret = ''
        try {
            Write-Debug "Calling Get-WebConfiguration -PSPath $IisPath -filter $($Filter)/$($CollectionName)"
            $testResult = Get-WebConfiguration -PSPath $IisPath -filter "$Filter/$CollectionName"
        }
        catch {
            $module.FailJson("Error retrieving web configuration: $($_.Exception.Message)", $_)
        }
        $ret = $testResult.Value -join ','
        $ret
    }
}

function Remove-IISPageOrder {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Ansible.Basic.AnsibleModule]
        $Module,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $IisPath,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $Filter,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $CollectionName
    )
    Process {
        if ($PSCmdlet.ShouldProcess($IisPath, 'Remove Current Page Order')) {
            try {
                $module.Result.msg += "Removing page order from path $IisPath with filter $Filter.`n"
                Write-Debug "Calling Remove-WebConfigurationProperty -PSPath $IisPath -filter $Filter -name 'collection'"
                $module.Result.msg += Remove-WebConfigurationProperty -PSPath $IisPath -filter $Filter -name 'collection'
                $module.Result.msg += "`n"
            }
            catch {
                $module.FailJson("Error removing page order. Exception: $($_.Exception.Message)", $_)
            }
        }
    }
}

function Set-IISPageOrder {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Ansible.Basic.AnsibleModule]
        $Module,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $IisPath,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $Filter,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $CollectionName,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]
        $PageOrder
    )
    Process {
        if ($PSCmdlet.ShouldProcess($PageOrder, 'Add Page Order')) {
            $splitValue = $PageOrder -split ','
            # Need to reverse the order since Add-WebConfigurationProperty inserts at the beginning rather than appending.
            for ($i = $splitValue.length - 1; $i -ge 0; $i--) {
                try {
                    Write-Debug "Calling Add-WebConfigurationProperty -PSPath $IisPath -filter $Filter -name 'Collection' -value $($splitValue[$i])"
                    Add-WebConfigurationProperty -PSPath $IisPath -filter $Filter -name 'Collection' -value $splitValue[$i] -ErrorAction 'Stop'
                    $module.Result.msg += "Added $($splitValue[$i]) to path $IisPath with filter $Filter.`n"
                }
                catch {
                    $module.FailJson("Error adding page order. Exception: $($_.Exception.Message)", $_)
                }
            }
        }
    }
}

# NOTE: If you try to use $module properties in these conditions, it can cause the module to just hang forever and have
# powershell slowly bloat in memory forever.
Write-Debug "Calling Get-IISPageOrder -Module $module -IisPath $iisPath -Filter $filter -CollectionName $collectionName"
$orderCheck = Get-IISPageOrder -Module $module -IisPath $iisPath -Filter $filter -CollectionName $collectionName
$module.Result.diff.before = $orderCheck
Write-Debug "Value of orderCheck: $($orderCheck | Out-String)"
if ($orderCheck -ne $pageOrder) {
    $module.Result.msg += "Mismatch detected: '$orderCheck' is not equal to '$pageOrder'"
    if ($orderCheck) {
        Write-Debug "Calling Remove-IISPageOrder -Module $module -IisPath $iisPath -Filter $filter -CollectionName $collectionName -WhatIf:$($module.CheckMode)"
        Remove-IISPageOrder -Module $module -IisPath $iisPath -Filter $filter -CollectionName $collectionName -WhatIf:$module.CheckMode
    }
    Write-Debug "Calling Set-IISPageOrder -Module $module -IisPath $iisPath -Filter $filter -CollectionName $collectionName -PageOrder $pageOrder -WhatIf:$($module.CheckMode)"
    Set-IISPageOrder -Module $module -IisPath $iisPath -Filter $filter -CollectionName $collectionName -PageOrder $pageOrder -WhatIf:$module.CheckMode
    $orderCheck = $NULL
    $orderCheck = Get-IISPageOrder -Module $module -IisPath $iisPath -Filter $filter -CollectionName $collectionName
    $module.Result.changed = $true
    if (!($module.CheckMode)) {
        $module.Result.diff.after = $orderCheck
        if ($orderCheck -ne $pageOrder) {
            $module.FailJson("Page order does not match after attempting to set new value. Current order: $($orderCheck), desired order: $pageOrder")
        }
    }
}
else {
    $module.Result.msg += "$orderCheck value is identical to $pageOrder, nothing to do."
}
$module.ExitJson()
