#!powershell

# Copyright: (c) 2025, Ansible Project
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
$module.Result.site = @()

# Ensure WebAdministration module is loaded
if ($null -eq (Get-Module -Name "WebAdministration" -ErrorAction SilentlyContinue)) {
    Import-Module WebAdministration
    $web_admin_dll_path = Join-Path $env:SystemRoot system32\inetsrv\Microsoft.Web.Administration.dll
    Add-Type -LiteralPath $web_admin_dll_path
}

function Get-WebsiteInfo ($name) {
    # Get all the current site details
    $site = Get-Item -LiteralPath IIS:\Sites\$name
    if ($null -ne $site) {
        $module.Result.exists = $true
    }
    $site_bindings = Get-WebBinding -Name $name
    $WebsiteInfoDict = @{
        name = $site.Name
        id = $site.ID
        state = $site.State
        physical_path = $site.PhysicalPath
        application_pool = $site.applicationPool
        ip = $($site_bindings.bindingInformation -split ":")[0]
        port = [int]$($site_bindings.bindingInformation -split ":")[1]
        hostname = $($site_bindings.bindingInformation -split ":")[2]
    }
    return $WebsiteInfoDict
}

try {
    # In case a user specified website name return information only for this website
    if ($null -ne $name) {
        [array]$module.Result.site = Get-WebsiteInfo -name $name
    }
    # Return information of all the websites available on the system
    else {
        $WebsiteList = $(Get-Website).Name
        [array]$module.Result.site = $WebsiteList | ForEach-Object { Get-WebsiteInfo -name $_ }
    }
}
catch {
    $msg = -join @(
        "Failed to fetch the info of the required Website "
        "Exception: $($_.Exception.Message)"
    )
    $module.FailJson($msg, $_)
}

$module.ExitJson()
