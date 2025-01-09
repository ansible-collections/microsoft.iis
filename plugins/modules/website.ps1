#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic

$spec = @{
    options = @{
        name = @{
            required = $true
            type = "str"
        }
        state = @{
            type = "str"
            default = "started"
            choices = @("absent", "restarted", "started", "stopped")
        }
        site_id = @{
            type = "str"
        }
        application_pool = @{
            type = "str"
        }
        physical_path = @{
            type = "str"
        }
        ip = @{
            type = "str"
        }
        port = @{
            type = "int"
        }
        hostname = @{
            type = "str"
        }
    }
    supports_check_mode = $true
}

$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)

$name = $module.Params.name
$state = $module.Params.state
$site_id = $module.Params.site_id
$application_pool = $module.Params.application_pool
$physical_path = $module.Params.physical_path
$bind_ip = $module.Params.ip
$bind_port = $module.Params.port
$bind_hostname = $module.Params.hostname

$check_mode = $module.CheckMode
$module.Result.changed = $false

# Ensure WebAdministration module is loaded
if ($null -eq (Get-Module "WebAdministration" -ErrorAction SilentlyContinue)) {
    Import-Module WebAdministration
}

# Site info
$site = Get-Website | Where-Object { $_.Name -eq $name }

Try {
    # Add site
    If (($state -ne 'absent') -and (-not $site)) {
        If (-not $physical_path) {
            $module.FailJson("missing required arguments: physical_path")
        }
        ElseIf (-not (Test-Path -LiteralPath $physical_path)) {
            $module.FailJson("specified folder must already exist: physical_path")
        }
        $site_parameters = @{
            Name = $name
            PhysicalPath = $physical_path
        }
        If ($application_pool) {
            $site_parameters.ApplicationPool = $application_pool
        }
        If ($site_id) {
            $site_parameters.ID = $site_id
        }
        If ($bind_port) {
            $site_parameters.Port = $bind_port
        }
        If ($bind_ip) {
            $site_parameters.IPAddress = $bind_ip
        }
        If ($bind_hostname) {
            $site_parameters.HostHeader = $bind_hostname
        }
        # Fix for error "New-Item : Index was outside the bounds of the array."
        # This is a bug in the New-WebSite commandlet. Apparently there must be at least one site configured in IIS otherwise New-WebSite crashes.
        # For more details, see http://stackoverflow.com/questions/3573889/ps-c-new-website-blah-throws-index-was-outside-the-bounds-of-the-array
        $sites_list = Get-ChildItem -LiteralPath IIS:\sites
        if ($null -eq $sites_list) {
            if ($site_id) {
                $site_parameters.ID = $site_id
            }
            else {
                $site_parameters.ID = 1
            }
        }
        if ( -not $check_mode) {
            $site = New-Website @site_parameters -Force
        }
        $module.Result.changed = $true
    }
    # Remove site
    If ($state -eq 'absent' -and $site) {
        $site = Remove-Website -Name $name -WhatIf:$check_mode
        $module.Result.changed = $true
    }
    $site = Get-Website | Where-Object { $_.Name -eq $name }
    If ($site) {
        # Change Physical Path if needed
        if ($physical_path) {
            If (-not (Test-Path -LiteralPath $physical_path)) {
                $module.FailJson("specified folder must already exist: physical_path")
            }
            $folder = Get-Item -LiteralPath $physical_path
            If ($folder.FullName -ne $site.PhysicalPath) {
                Set-ItemProperty -LiteralPath "IIS:\Sites\$($site.Name)" -name physicalPath -value $folder.FullName -WhatIf:$check_mode
                $module.Result.changed = $true
            }
        }
        # Change Application Pool if needed
        if ($application_pool) {
            If ($application_pool -ne $site.applicationPool) {
                Set-ItemProperty -LiteralPath "IIS:\Sites\$($site.Name)" -name applicationPool -value $application_pool -WhatIf:$check_mode
                $module.Result.changed = $true
            }
        }
        # Set run state
        if ((($state -eq 'stopped') -or ($state -eq 'restarted')) -and ($site.State -eq 'Started')) {
            if (-not $check_mode) {
                Stop-Website -Name $name -ErrorAction Stop
            }
            $module.Result.changed = $true
        }
        if ((($state -eq 'started') -and ($site.State -eq 'Stopped')) -or ($state -eq 'restarted')) {
            if (-not $check_mode) {
                Start-Website -Name $name -ErrorAction Stop
            }
            $module.Result.changed = $true
        }
    }
}
Catch {
    $module.FailJson("$($module.Result) - $($_.Exception.Message)", $_)
}

$module.ExitJson()
