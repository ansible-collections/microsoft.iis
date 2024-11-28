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

While these modules are mostly drop in place compatible there are some breaking changes that need to be considered. See each module entry for more information.

.. _ansible_collections.microsoft.iis.docsite.guide_migration.migrated_modules.win_iis_website:

Module ``win_iis_website``
--------------------------

Migrated to :ref:`microsoft.iis.website <ansible_collections.microsoft.iis.website_module>`.

To complete.
