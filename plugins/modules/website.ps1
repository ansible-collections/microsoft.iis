#!powershell

# Copyright: (c) 2025, Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

#AnsibleRequires -CSharpUtil Ansible.Basic

# Define Bindings Options
$binding_options = @{
    type = 'list'
    elements = 'dict'
    options = @{
        ip = @{ type = 'str' }
        port = @{ type = 'int' }
        hostname = @{ type = 'str' }
        protocol = @{ type = 'str' ; default = 'http' ; choices = @('http', 'https') }
        require_server_name_indication = @{ type = 'bool'; default = $false }
        use_centrelized_certificate_store = @{ type = 'bool'; default = $false }
        certificate_hash = @{ type = 'str' }
        certificate_store_name = @{ type = 'str' }
    }
    required_together = @(
        , @('certificate_hash', 'certificate_store_name')
    )
}

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
        bindings = @{
            default = @{}
            type = 'dict'
            options = @{
                add = $binding_options
                set = $binding_options
                remove = @{
                    type = 'list'
                    elements = 'dict'
                    options = @{
                        ip = @{ type = 'str' }
                        port = @{ type = 'int' }
                        hostname = @{ type = 'str' }
                    }
                }
            }
            mutually_exclusive = @(
                , @('set', 'add')
                , @('set', 'remove')
            )
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
$bindings = $module.Params.bindings

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
        # Verify that initial site has no binding
        Get-WebBinding -Name $site.Name | Remove-WebBinding -WhatIf:$check_mode
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
        # Add Remove or Set bindings if needed
        if ($bindings) {
            $site_bindings = (Get-ItemProperty -LiteralPath "IIS:\Sites\$($site.Name)").Bindings.Collection
            $toAdd = @()
            $toRemove = @()
            if ($null -ne $bindings.set) {
                $toAdd = $bindings.set | Where-Object { -not ($site_bindings.bindingInformation -contains "$($_.ip):$($_.port):$($_.hostname)") }
                $user_bindings = $bindings.set | ForEach-Object { "$($_.ip):$($_.port):$($_.hostname)" }
                if ($null -ne $site_bindings.bindingInformation) {
                    $toRemove = $site_bindings.bindingInformation | Where-Object { $_ -notin $user_bindings }
                }
            }
            else {
                if ($bindings.add) {
                    $toAdd = $bindings.add | Where-Object { -not ($site_bindings.bindingInformation -contains "$($_.ip):$($_.port):$($_.hostname)") }
                }
                if ($bindings.remove) {
                    $user_bindings = $bindings.remove | ForEach-Object { "$($_.ip):$($_.port):$($_.hostname)" }
                    $toRemove = $site_bindings.bindingInformation | Where-Object { $_ -in $user_bindings }
                }
            }
            $toAdd | ForEach-Object {
                $ssl_flags = 0
                if ($_.require_server_name_indication) {
                    If ($_.protocol -ne 'https') {
                        $module.FailJson("require_server_name_indication can only be set for https protocol")
                    }
                    If (-Not $_.hostname) {
                        $module.FailJson("must specify hostname value when require_server_name_indication is set.")
                    }
                    $ssl_flags += 1
                }
                if ($_.use_centrelized_certificate_store) {
                    If ($_.protocol -ne 'https') {
                        $module.FailJson("use_centrelized_certificate_store can only be set for https protocol")
                    }
                    If (-Not $_.hostname) {
                        $module.FailJson("must specify hostname value when use_centrelized_certificate_store is set.")
                    }
                    If ($_.certificate_hash) {
                        $module.FailJson("You set use_centrelized_certificate_store to $($_.use_centrelized_certificate_store).
                        This indicates you wish to use the Central Certificate Store feature.
                        This cannot be used in combination with certficiate_hash and certificate_store_name. When using the Central Certificate Store feature,
                        the certificate is automatically retrieved from the store rather than manually assigned to the binding.")
                    }
                    $ssl_flags += 2
                }
                If ($_.protocol -eq 'https') {
                    if (-Not $_.use_centrelized_certificate_store -and -Not $_.certificate_hash) {
                        $module.FailJson("must either specify a certficiate_hash or use_centrelized_certificate_store.")
                    }
                }
                If ($_.certificate_hash) {
                    If ($_.protocol -ne 'https') {
                        $module.FailJson("You can only provide a certificate thumbprint when protocol is set to https")
                    }
                    # Validate cert path
                    $cert_path = "cert:\LocalMachine\$($_.certificate_store_name)\$($_.certificate_hash)"
                    If (-Not (Test-Path -LiteralPath $cert_path) ) {
                        $module.FailJson("Unable to locate certificate at $cert_path")
                    }
                }
                if (-not $check_mode) {
                    New-WebBinding -Name $site.Name -IPAddress $_.ip -Port $_.port -HostHeader $_.hostname -Protocol $_.protocol -SslFlags $ssl_flags
                    If ($_.certificate_hash) {
                        $new_binding = Get-WebBinding -Name $site.Name -IPAddress $_.ip -Port $_.port -HostHeader $_.hostname
                        $new_binding.AddSslCertificate($_.certificate_hash, $_.certificate_store_name)
                    }
                }
                $module.Result.changed = $true
            }
            $toRemove | ForEach-Object {
                $remove_binding = $_ -split ':'
                Get-WebBinding -Name $site.Name -IPAddress $remove_binding[0] -Port $remove_binding[1]`
                    -HostHeader $remove_binding[2] | Remove-WebBinding -WhatIf:$check_mode
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
