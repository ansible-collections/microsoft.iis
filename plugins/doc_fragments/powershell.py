# Copyright: Ansible Project
# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

from __future__ import annotations


class ModuleDocFragment:

    # This doc fragment is for PowerShell support information for modules in this collection.
    DOCUMENTATION = r"""
attributes:
  powershell:
    description:
      - List of target PowerShell versions specified by O(versions) supported by
        this module.
      - Version V(7) without a minor version specified means the V(7.x) versions
        should be supported by Ansible should work but see O(details) for more
        information.
      - PowerShell V(5.1) is supported on Windows only while V(7.x) is
        cross-platform. See O(platform) for more details on what platforms are
        supported.
    support: N/A
"""
