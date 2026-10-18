# Shelby Edge Remover

A Windows PowerShell utility that attempts to uninstall Microsoft Edge, remove related components, and optionally restrict Edge reinstall paths through folder-permission changes.

> **Warning:** This tool makes system-level changes. It can delete files and registry keys, remove services, stop processes, and change access-control lists (ACLs) under Program Files. These changes can affect Windows features, updates, or apps that rely on Microsoft Edge or WebView2. Review the script before running it, create a restore point and a full backup, and use it only if you understand the risks.

## Features

- Attempts Edge removal through `winget` and Edge's `setup.exe` uninstaller.
- Attempts to remove selected Edge-related app packages, folders, registry keys, and update services.
- Provides separate modes for uninstalling, applying folder-permission restrictions, and attempting to restore folder permissions.
- Includes batch launchers for each mode.

Removal success can vary by Windows build and Edge installation. This script does **not** guarantee that every Edge component is removed or that Windows will never reinstall it.

## Requirements

- Windows 11 (the script is designed for Windows; other versions are not tested here).
- Windows PowerShell 5.1 or later.
- Administrator privileges.
- Backups and a recovery plan before changing system files or permissions.

## Files

| File | Purpose |
|---|---|
| `ShelbyEdgeRemove.ps1` | Main PowerShell script; supports four modes. |
| `Run_Vanish.bat` | Runs full removal followed by folder-permission blocking. |
| `Run_Uninstall.bat` | Runs removal without applying the folder-permission block. |
| `Run_Block.bat` | Applies restrictive permissions to selected Edge installation folders. |
| `Run_Unblock.bat` | Attempts to restore permissions on the selected folders. |

## Usage

1. Download or clone this repository.
2. Read `ShelbyEdgeRemove.ps1` before executing it.
3. Create a restore point and back up important data.
4. Right-click the desired `.bat` launcher and choose **Run as administrator**.
5. Review the console output. Restart Windows if requested, then check that Windows and your apps still work as expected.

### Choose a mode carefully

- **Uninstall:** Runs the removal steps but does not apply the folder-permission block.
- **Block:** Creates the configured folders if missing and applies restrictive ACLs. This can interfere with servicing and updates.
- **Unblock:** Attempts to reset permissions on the configured folders. It is not a guaranteed exact restoration of the original ACLs; use a backup or Windows repair/recovery method if permissions become damaged.
- **Vanish:** Runs uninstall and then applies the restrictive ACL block. This is the most invasive option.

You can also run a mode directly from an elevated PowerShell window:

```powershell
.\ShelbyEdgeRemove.ps1 -Mode Uninstall
.\ShelbyEdgeRemove.ps1 -Mode Block
.\ShelbyEdgeRemove.ps1 -Mode Unblock
.\ShelbyEdgeRemove.ps1 -Mode Vanish
```

## Important limitations

- This project has not been validated across all Windows 11 builds or device configurations.
- Removing Edge may affect apps, links, help experiences, or features that depend on Edge or WebView2.
- Windows servicing or updates may restore components.
- The script deletes a defined set of registry keys and files; inspect those lists in the script to understand the scope before use.
- The `Unblock` mode applies a constructed permission set and may not recreate the exact permissions that existed before the tool ran.
- Run at your own risk. No warranty is provided.

## Contributing

Issues and pull requests are welcome. Include your Windows version/build, the mode used, and relevant error messages. Do not post personal data or sensitive system logs.

## License

This project is licensed under the BSD-3-Clause license. By using our software, you acknowledge and agree to the terms of the license.
