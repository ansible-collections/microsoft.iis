#!powershell

# Copyright: (c) 2024, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        name = @{ type = "str" }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$name = $module.Params.name

$module.Result.exists = $false
$module.Result.appPools = @()


# Ensure WebAdministration module is loaded
if ($null -eq (Get-Module -Name "WebAdministration" -ErrorAction SilentlyContinue)) {
    Import-Module WebAdministration
    $web_admin_dll_path = Join-Path $env:SystemRoot system32\inetsrv\Microsoft.Web.Administration.dll
    Add-Type -LiteralPath $web_admin_dll_path
}

function Get-AppPoolInfo ($name) {

    # Get all the current attributes for the pool
    $pool = Get-Item -LiteralPath IIS:\AppPools\$name #-ErrorAction SilentlyContinue
    if ($null -ne $pool) {
        $module.Result.exists = $true
    }
    $appPoolInfoDict = @{
        name = $name
        info = @{}
    }

    $elements = @("attributes", "cpu", "failure", "processModel", "recycling")
    foreach ($element in $elements) {
        if ($element -eq "attributes") {
            $attribute_collection = $pool.Attributes
            $attribute_parent = $pool
        }
        else {
            $attribute_collection = $pool.$element.Attributes
            $attribute_parent = $pool.$element
        }


        foreach ($attribute in $attribute_collection) {
            $attribute_name = $attribute.Name
            if ($attribute_name -notlike "*password*") {
                $attribute_value = $attribute_parent.$attribute_name
                if (-not $appPoolInfoDict.info[$element]) {
                    $appPoolInfoDict.info[$element] = @{}
                }
                $appPoolInfoDict.info[$element].Add($attribute_name, $attribute_value)
            }
        }
    }
    # Ensure periodicRestart is initialized
    if (-not $appPoolInfoDict.info.recycling.ContainsKey("periodicRestart")) {
    $appPoolInfoDict.info.recycling["periodicRestart"] = @{}
    }
    # Manually get the periodicRestart attributes in recycling
    foreach ($attribute in $pool.recycling.periodicRestart.Attributes) {
        $attribute_name = $attribute.Name
        $attribute_value = $pool.recycling.periodicRestart.$attribute_name
        $appPoolInfoDict.info.recycling.periodicRestart.Add($attribute_name, $attribute_value)
    }
    return $appPoolInfoDict
}
try {
    # In case a user specified app pool name return information only for this app pool
    if ($null -ne $name) {
        [array]$module.Result.appPools = Get-AppPoolInfo -name $name
    }
    # Return information of all the app pools available on the system
    else {
        $appPoolList = (Get-ChildItem IIS:\AppPools).Name
        [array]$module.Result.appPools = $appPoolList | ForEach-Object { Get-AppPoolInfo -name $_ }
    }
}
catch {
    $msg = -join @(
        "Failed to fetch the info of the required application pool "
        "Exception: $($_.Exception.Message)"
    )
    $module.FailJson($msg, $_)
}

$module.ExitJson()