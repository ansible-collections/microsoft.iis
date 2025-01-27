#!powershell

# Copyright: (c) 2024, Hen Yaish <hyaish@redhat.com>
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic

# Define the argument specification
$spec = @{
    options = @{
        name = @{ type = "str" }
        site = @{ type = "str" }
        application = @{ type = "str" }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
$name = $module.Params.name
$site = $module.Params.site
$application = $module.Params.application

try {
    # Ensure WebAdministration module is loaded
    if ($null -eq (Get-Module "WebAdministration" -ErrorAction SilentlyContinue)) {
        Import-Module WebAdministration
    }
}
catch {
    $module.FailJson("Failed to ensure WebAdministration module is loaded: $_", $_)
}

# Get directory information
try {
    $getParams = @{}
    if ($name) {
        $getParams.Name = $name
    }
    if ($site) {
        $getParams.Site = $site
    }
    if ($application) {
        $getParams.Application = $application
    }

    $module.Result.exists = $false
    $module.Result.directories = @()
    $directories = Get-WebVirtualDirectory @getParams

    if ($directories) {
        $module.Result.exists = $true
        $module.Result.directories = @(
            foreach ($directory in $directories) {
                # Dynamically calculate directory path for each directory
                $directory_path = if ($application) {
                    "IIS:\Sites\$($site)\$($application)\$($name)"
                }
                else {
                    "IIS:\Sites\$($site)\$($name)"
                }

                $directory_properties = $directory | Get-ItemProperty -LiteralPath $directory_path

                @{
                    name = $name
                    site = $site
                    physical_path = $directory_properties.PhysicalPath
                    application = $application
                    username = if ($null -ne $directory_properties.userName) { $directory_properties.userName } else { "" }
                }
            }
        )
    }
}
catch {
    $module.FailJson($_.Exception.Message, $_ )
}

$module.ExitJson()