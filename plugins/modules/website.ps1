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
        ssl_flags = @{ type = 'str' ; default = '0' ; choices = @('0', '1', '2', '3') }
        certificate_hash = @{ type = 'str' ; default = ([string]::Empty) }
        certificate_store_name = @{ type = 'str' ; default = ([string]::Empty) }
    }
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
        parameters = @{
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

# Custom site Parameters from string where properties are separated by a pipe and property name/values by colon.
# Ex. "foo:1|bar:2"
$parameters = $module.Params.parameters
if ($null -ne $parameters) {
    $parameters = @($parameters -split '\|' | ForEach-Object {
            return , ($_ -split "\:", 2)
        })
}

$check_mode = $module.CheckMode
$module.Result.changed = $false

if ($check_mode) {
    Write-Output "in check mode"
}

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
            $module.FailJson("missing required arguments: physical_path $($_.Exception.Message)")
        }
        ElseIf (-not (Test-Path -LiteralPath $physical_path)) {
            $module.FailJson("specified folder must already exist: physical_path $($_.Exception.Message)")
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
                $module.FailJson("specified folder must already exist: physical_path $($_.Exception.Message)")
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
            $user_bindings = if ($Module.Params.bindings.add) { $Module.Params.bindings.add }
            elseif ($Module.Params.bindings.remove) { $Module.Params.bindings.remove }
            elseif ($Module.Params.bindings.set) { $Module.Params.bindings.set }
            # Validate User Bindings Information
            $user_bindings | ForEach-Object {
                # Make sure ssl flags only specified with https protocol
                If ($_.protocol -ne 'https' -and $_.ssl_flags -gt 0) {
                    $module.FailJson("SSLFlags can only be set for https protocol")
                }
                # Validate certificate details if provided
                If ($_.certificate_hash -and $_.operation -ne 'remove') {
                    If ($_.protocol -ne 'https') {
                        $module.FailJson("You can  only provide a certificate thumbprint when protocol is set to https")
                    }
                    # Apply default for cert store name
                    If (-Not $_.certificate_store_name) {
                        $_.certificate_store_name = 'my'
                    }
                    # Validate cert path
                    $cert_path = "cert:\LocalMachine\$($_.certificate_store_name)\$($_.certificate_hash)"
                    If (-Not (Test-Path -LiteralPath $cert_path) ) {
                        $module.FailJson("Unable to locate certificate at $cert_path")
                    }
                }
                # Make sure binding info is valid for central cert store if sslflags -gt 1
                If ($_.ssl_flags -gt 1 -and ($_.certificate_hash -ne [string]::Empty -or $_.certificate_store_name -ne [string]::Empty)) {
                    $module.FailJson("You set sslFlags to $($_.ssl_flags). This indicates you wish to use the Central Certificate Store feature.
                    This cannot be used in combination with certficiate_hash and certificate_store_name. When using the Central Certificate Store feature,
                    the certificate is automatically retrieved from the store rather than manually assigned to the binding.")
                }
            }
            if ($null -ne $bindings.add) {
                $add_binding = $user_bindings | Where-Object { -not ($site_bindings.bindingInformation -contains "$($_.ip):$($_.port):$($_.hostname)") }
                if ($add_binding) {
                    $add_binding | ForEach-Object {
                        if (-not $check_mode) {
                            New-WebBinding -Name $site.Name -IPAddress $_.ip -Port $_.port -HostHeader $_.hostname -Protocol $_.protocol -SslFlags $_.ssl_flags
                            If ($_.certificate_hash) {
                                $new_binding = Get-WebBinding -Name $site.Name -IPAddress $_.ip -Port $_.port -HostHeader $_.hostname
                                $new_binding.AddSslCertificate($_.certificate_hash, $_.certificate_store_name)
                            }
                        }
                        $module.Result.changed = $true
                    }
                }
            }
            if ($null -ne $bindings.remove) {
                $remove_binding = $user_bindings | Where-Object { ($site_bindings.bindingInformation -contains "$($_.ip):$($_.port):$($_.hostname)") }
                if ($remove_binding) {
                    $remove_binding | ForEach-Object {
                        Get-WebBinding -Name $site.Name -IPAddress $_.ip -Port $_.port -HostHeader $_.hostname | Remove-WebBinding -WhatIf:$check_mode
                        $module.Result.changed = $true
                    }
                }
            }
            if ($null -ne $bindings.set) {
                $set_binding = $user_bindings | ForEach-Object { "$($_.ip):$($_.port):$($_.hostname)" }
                $diff = Compare-Object -ReferenceObject @($set_binding | Select-Object) -DifferenceObject  @($site_bindings.bindingInformation | Select-Object)
                if ($diff.Count -ne 0) {
                    # Remove All Bindings
                    Get-WebBinding -Name $site.Name | Remove-WebBinding -WhatIf:$check_mode
                    # Set Bindings
                    $user_bindings | ForEach-Object {
                        if (-not $check_mode) {
                            New-WebBinding -Name $site.Name -IPAddress $_.ip -Port $_.port -HostHeader $_.hostname -Protocol $_.protocol -SslFlags $_.ssl_flags
                            If ($_.certificate_hash) {
                                $new_binding = Get-WebBinding -Name $site.Name -IPAddress $_.ip -Port $_.port -HostHeader $_.hostname
                                $new_binding.AddSslCertificate($_.certificate_hash, $_.certificate_store_name)
                            }
                        }
                    }
                    $module.Result.changed = $true
                }
            }
        }
        # Set properties
        if ($parameters) {
            $parameters | ForEach-Object {
                $property_value = Get-ItemProperty -LiteralPath "IIS:\Sites\$($site.Name)" $_[0]

                switch ($property_value.GetType().Name) {
                    "ConfigurationAttribute" { $parameter_value = $property_value.value }
                    "String" { $parameter_value = $property_value }
                }

                if ((-not $parameter_value) -or ($parameter_value) -ne $_[1]) {
                    Set-ItemProperty -LiteralPath "IIS:\Sites\$($site.Name)" $_[0] $_[1] -WhatIf:$check_mode
                    $module.Result.changed = $true
                }
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
    $module.FailJson("$($module.Result) - $($_.Exception.Message)")
}

$module.ExitJson()
