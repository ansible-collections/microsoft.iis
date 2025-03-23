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
* ``community.windows.win_iis_webbinding`` -> ``microsoft.iis.website`` - :ref:`details <ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_webbinding>`
* ``community.windows.win_iis_virtualdirectory`` -> ``microsoft.iis.virtual_directory`` - :ref:`details <ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_virtualdirectory>`
* ``community.windows.win_iis_webapppool`` -> ``microsoft.iis.web_app_pool`` - :ref:`details <ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_webapppool>`
* ``community.windows.win_iis_webapplication`` -> ``microsoft.iis.web_application`` - :ref:`details <ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_webapplication>`

While these modules are mostly drop in place compatible there are some breaking changes that need to be considered. See each module entry for more information.

.. _ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_website:

Module ``win_iis_website``
--------------------------

Migrated to :ansplugin:`microsoft.iis.website#module`.

The following options have been removed:

* ``parameters`` - Not currently implemented in the new module
* ``hostname``, ``ip``, ``port`` - Moved to the ``bindings`` parameter, see :ref:`details <ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_webbinding>` for more details

The return values have also been removed in favour of the :ansplugin:`microsoft.iis.website_info#module` module.

This example shows how a website was defined in the old module and the equivalent definition in the new module:

.. code-block:: yaml

  - name: Build website in win_iis_webbinding
    community.windows.win_iis_website:
      name: Acme
      state: started
      ip: 127.0.0.1
      port: 80
      application_pool: acme
      physical_path: C:\sites\acme

  - name: Build website in microsoft.iis.website
    microsoft.iis.website:
      name: Acme
      state: started
      bindings:
        set:
          - ip: 127.0.0.1
            port: 80
      application_pool: acme
      physical_path: C:\sites\acme

.. _ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_webbinding:

Module ``win_iis_webbinding``
-----------------------------

Migrated to :ansplugin:`microsoft.iis.website#module`.

The entire module has been removed and the functionality has been merged into the :ansplugin:`microsoft.iis.website#module` module. The bindings are now specified by the ``bindings`` parameter in the website module and can be used to add, remove, or set multiple bindings in one operation on the website. While most of the ``bindings`` entries follow the same format as the old module, there are some changes to a binding entry:

* ``host_header`` - Has been renamed to ``hostname``
* ``ssl_flags`` - Has been split into ``use_sni`` and ``use_ccs``
* ``state`` - Controlled by specifying the binding into the relevant ``add``, ``remote``, or ``set`` key

.. _ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_virtualdirectory:

Module ``win_iis_virtualdirectory``
-----------------------------------

Migrated to :ansplugin:`microsoft.iis.virtual_directory#module`.

The new ``microsoft.iis.virtual_directory`` module is largely unchanged from the old module, with the exception of the return values being removed. The new :ansplugin:`microsoft.iis.virtual_directory_info#module` module can be used to retrieve information about virtual directories instead.

.. _ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_webapppool:

Module ``win_iis_webapppool``
-----------------------------

Migrated to :ansplugin:`microsoft.iis.web_app_pool#module`.

The new ``microsoft.iis.web_app_pool`` module is largely unchanged from the old module, with the exception of the return values being removed. The new :ansplugin:`microsoft.iis.web_app_pool_info#module` module can be used to retrieve information about web app pools instead.

.. _ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_webapplication:

Module ``win_iis_webapplication``
---------------------------------

Migrated to :ansplugin:`microsoft.iis.web_application#module`.

The new ``microsoft.iis.web_application`` module is largely unchanged from the old module, with the exception of the return values being removed. The new :ansplugin:`microsoft.iis.web_application_info#module` module can be used to retrieve information about web applications instead.
