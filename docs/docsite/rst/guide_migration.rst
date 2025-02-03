.. _ansible_collections.microsoft.iis.docsite.guide_migration:

***************
Migration guide
***************

Some of the modules in this collection have come from the `community.windows collection <https://galaxy.ansible.com/community/windows>`_. This document will go through some of the changes made to help ease the transition from the older modules to the ones in this collection.

.. contents::
  :local:
  :depth: 1

.. _ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules:

Migrated Modules
================

The following modules have been migrated in some shape or form into this collection

* ``community.windows.win_iis_website`` -> ``microsoft.iis.website`` - :ref:`details <ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_website>`
* ``community.windows.win_iis_virtualdirectory`` -> ``microsoft.iis.virtual_directory`` - :ref:`details <ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_virtualdirectory>`
* ``community.windows.win_iis_webapppool`` -> ``microsoft.iis.web_app_pool`` - :ref:`details <ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_webapppool>`
* ``community.windows.win_iis_webapplication`` -> ``microsoft.iis.web_application`` - :ref:`details <ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_webapplication>`

While these modules are mostly drop in place compatible there are some breaking changes that need to be considered. See each module entry for more information.

.. _ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_website:

Module ``win_iis_website``
--------------------------

Migrated to :ref:`microsoft.iis.website <ansible_collections.microsoft.iis.website_module>`.

community.windows.win_iis_website has been split into two modules:
  * ansible.microsoft.iis.website.
  * ansible.microsoft.iis.website_info.

Custom site Parameters from string ($parameters) removed from the module
win_iis_webbinding was consolidated into microsoft.iis.website
Parameters bind_ip, bind_port, bind_hostname moved into $bindings ip, port, hostname
$bindings now include add/set/remove functionality
Updated from ``Ansible.ModuleUtils.Legacy`` to ``-CSharpUtil Ansible.Basic``

.. code-block:: yaml

  - name: Create a default website in 'Started' state
    microsoft.iis.website:
      name: WebSite
      physical_path: C:\inetpub\wwwroot
      state: started
      bindings:
        set:
          - ip: 127.0.0.1
            port: 80
            hostname: my-website.com

  - name: Create a website with two bindings, set all values and start it
    microsoft.iis.website:
      name: WebSite
      site_id: 2
      state: started
      physical_path: C:\wwwroot\websites\my-website
      application_pool: DefaultAppPool
      bindings:
        set:
          - ip: 127.0.0.1
            port: 8081
            hostname: my-website.com
          - ip: 127.0.0.2
            port: 8082
            hostname: my-website.net
            protocol: https
            use_sni: true
            use_ccs: false
            certificate_hash: 5409124040FA1C8FA74939BDA2EF8FD5975BD25B
            certificate_store_name: MY

  - name: Remove all the bindings from an existing website
    microsoft.iis.website:
      name: WebSite
      bindings:
        set: []

  - name: Remove a binding from an existing website
    microsoft.iis.website:
      name: WebSite
      bindings:
        remove:
          - ip: 127.0.0.1
            port: 8081
            hostname: my-website.com

  - name: Add bindings to an existing website
    microsoft.iis.website:
      name: WebSite
      bindings:
        add:
          - ip: 127.0.0.3
            port: 8083
            hostname: new-website.com
          - ip: 127.0.0.4
            port: 8084
            hostname: new-website.net

  - name: Stop a website
    microsoft.iis.website:
      name: WebSite
      state: stopped

  - name: Restart a website (non-idempotent)
    microsoft.iis.website:
      name: WebSite
      state: restarted

  - name: Change a website application pool
    microsoft.iis.website:
      name: WebSite
      application_pool: NewAppPool

  - name: Change a website physical path
    microsoft.iis.website:
      name: WebSite
      physical_path: C:\wwwroot\websites\my-website

Module ``website_info``
-------------------------------

Migrated to :ref:`microsoft.iis.website <ansible_collections.microsoft.iis.website_info_module>`.

Returns information about IIS websites

.. code-block:: yaml

  - name: Return information about an existing website
    microsoft.iis.website_info:
      name: 'Default Web Site'
    register: stored_info

  - name: Returns information about all websites that exist on the system
    microsoft.iis.website_info:
    register: stored_info_all


.. _ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_virtualdirectory:

Module ``win_iis_virtualdirectory``
----------------------------------

Migrated to :ref:`microsoft.iis.virtual_directory <ansible_collections.microsoft.iis.virtual_directory_module>`.

community.windows.win_iis_virtualdirectory has been split into two modules:
  * ansible.microsoft.iis.virtual_directory.
  * ansible.microsoft.iis.virtual_directory_info.

Virtual_directory module is responsible for adding, editing, and deleting virtual directories in Windows IIS.
Updated from ``Ansible.ModuleUtils.Legacy`` to ``-CSharpUtil Ansible.Basic``

.. code-block:: yaml

  - name: Create a virtual directory if it does not exist
    microsoft.iis.virtual_directory:
      name: somedirectory
      site: somesite
      state: present
      physical_path: C:\virtualdirectory\some

  - name: Remove a virtual directory if it exists
    microsoft.iis.virtual_directory:
      name: somedirectory
      site: somesite
      state: absent

  - name: Create a virtual directory on an application if it does not exist
    microsoft.iis.virtual_directory:
      name: somedirectory
      site: somesite
      application: someapp
      state: present
      physical_path: C:\virtualdirectory\some


Module ``virtual_director_info``
---------------------------------------

Migrated to :ref:`microsoft.iis.virtual_directory <ansible_collections.microsoft.iis.virtual_directory_info_module>`.

Retrieves information from Windows Server IIS virtual directories.
virtual_directory_info can retrieve all IIS directories.
virtual_directory_info can retrieve a specific IIS directory by site, name, or application.

.. code-block:: yaml

  - name: Get information for virtual directory on a specific site.
    microsoft.iis.virtual_directory_info:
      site: somesite
      name: somedirectory
    register: vdir_info

  - name: Get information for virtual directory on a specific site and application.
    microsoft.iis.virtual_directory_info:
      site: somesite
      name: somedirectory
      application: someapplication
    register: vdir_info


.. _ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_webapppool:

Module ``win_iis_webapppool``
-----------------------------

Migrated to :ref:`microsoft.iis.web_app_pool <ansible_collections.microsoft.iis.web_app_pool_module>`.

community.windows.win_iis_webapppool has been split into two modules:
  * ansible.microsoft.iis.web_app_pool.
  * ansible.microsoft.iis.web_app_pool_info.

Returns information about IIS Web Application Pools
Date-time attributes are returned in string representation of Timespan value, before that it was returned in json representation.
Updated from ``Ansible.ModuleUtils.Legacy`` to ``-CSharpUtil Ansible.Basic``

.. code-block:: yaml

  - name: Create a new application pool in 'Started' state
    microsoft.iis.web_app_pool:
      name: AppPool
      state: started

  - name: Stop an application pool
    microsoft.iis.web_app_pool:
      name: AppPool
      state: stopped

  - name: Restart an application pool (non-idempotent)
    microsoft.iis.web_app_pool:
      name: AppPool
      state: restarted

  - name: Change application pool attributes using new dict style
    microsoft.iis.web_app_pool:
      name: AppPool
      attributes:
        managedRuntimeVersion: v4.0
        autoStart: false

  - name: Creates an application pool, sets attributes and starts it
    microsoft.iis.web_app_pool:
      name: AnotherAppPool
      state: started
      attributes:
        managedRuntimeVersion: v4.0
        autoStart: false

  - name: Creates an application pool with "No Managed Code" for .Net compatibility
    microsoft.iis.web_app_pool:
      name: AnotherAppPool
      state: started
      attributes:
        managedRuntimeVersion: ''
        autoStart: false

  - name: Manage child element and set identity of application pool
    microsoft.iis.web_app_pool:
      name: IdentitiyAppPool
      state: started
      attributes:
        managedPipelineMode: Classic
        processModel.identityType: SpecificUser
        processModel.userName: "{{ ansible_user }}"
        processModel.password: "{{ ansible_password }}"
        processModel.loadUserProfile: true

  - name: Manage a timespan attribute
    microsoft.iis.web_app_pool:
      name: TimespanAppPool
      state: started
      attributes:
        recycling.periodicRestart.time: "00:00:05:00.000000"
        recycling.periodicRestart.schedule: ["00:10:00", "05:30:00"]
        processModel.pingResponseTime: "00:03:00"


Module ``web_app_pool_info``
----------------------------------

Migrated to :ref:`microsoft.iis.website <ansible_collections.microsoft.iis.web_app_pool_info_module>`.

Returns information about IIS Web Application Pools

.. code-block:: yaml

  - name: Return information about an existing application pool
    microsoft.iis.web_app_pool_info:
      name: DefaultAppPool
    register: stored_info

  - name: Returns information about all application pools that exist on the system
    microsoft.iis.web_app_pool_info:
    register: stored_info_all


.. _ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_webapplication:

Module ``win_iis_webapplication``
---------------------------------

Migrated to :ref:`microsoft.iis.website <ansible_collections.microsoft.iis.web_application_module>`.

community.windows.win_iis_virtualdirectory has been split into two modules:
  * ansible.microsoft.iis.virtual_directory.
  * ansible.microsoft.iis.virtual_directory_info.

Creates, removes, and configures IIS web applications.
Updated from ``Ansible.ModuleUtils.Legacy`` to ``-CSharpUtil Ansible.Basic``

.. code-block:: yaml

  - name: Add ACME web application on IIS.
    microsoft.iis.web_application:
      name: api
      site: acme
      state: present
      physical_path: C:\apps\acme\api

  - name: Change connect_as to be specific user.
    microsoft.iis.web_application:
      name: api
      site: acme
      connect_as: specific_user
      username: acmeuser
      password: acmepassword

  - name: Delete ACME web application on IIS.
    microsoft.iis.web_application:
      state: absent
      name: api
      site: acme


Module ``web_application_info``
--------------------------------------

Migrated to :ref:`microsoft.iis.website <ansible_collections.microsoft.iis.web_application_info_module>`.

Returns information about IIS web applications.
web_application_info returns username as-well.

.. code-block:: yaml

  - name: Fetch info for all applications under siteA
    web_application_info:
      site: SiteA
    register: info

  - name: Fetch info for web application MyApp
    web_application_info:
      name: MyApp
    register: info

  - name: Fetch info for web application MyApp using site and name - Useful when multiple sites have same app name
    web_application_info:
      name: MyApp
      site: SiteA
    register: info

  - name: Fetch info for all web applications that present in the system
    web_application_info:
    register: info
