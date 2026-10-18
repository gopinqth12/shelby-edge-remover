#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Shelby Edge Remove Script v2.0.0
    Complete Microsoft Edge removal and reinstall blocker for Windows 11.

.DESCRIPTION
    Kills, uninstalls, cleans and locks Edge out of your system.

    Modes:
      Vanish    -- Full removal + reinstall block (default)
      Uninstall -- Removal only, no folder lock
      Block     -- Lock existing protective folders (run after Uninstall)
      Unblock   -- Restore default Windows permissions on Edge folders

.PARAMETER Mode
    Vanish | Uninstall | Block | Unblock
    Default: Vanish

.EXAMPLE
    .\ShelbyEdgeRemove.ps1
    .\ShelbyEdgeRemove.ps1 -Mode Uninstall
    .\ShelbyEdgeRemove.ps1 -Mode Block
    .\ShelbyEdgeRemove.ps1 -Mode Unblock
#>

param(
    [ValidateSet('Vanish', 'Uninstall', 'Block', 'Unblock')]
    [string]$Mode = 'Vanish'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# ── Constants ──────────────────────────────────────────────────────────────────

$SCRIPT_NAME    = 'Shelby Edge Remove Script'
$SCRIPT_VERSION = '2.0.0'

$EDGE_UWP_APPS = @(
    'Microsoft.MicrosoftEdge',
    'Microsoft.MicrosoftEdgeDevToolsClient'
)

$EDGE_FOLDERS = @(
    "$env:LOCALAPPDATA\Microsoft\Edge",
    "$env:PROGRAMFILES\Microsoft\Edge",
    "${env:ProgramFiles(x86)}\Microsoft\Edge",
    "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate",
    "${env:ProgramFiles(x86)}\Microsoft\EdgeCore",
    "$env:LOCALAPPDATA\Microsoft\EdgeUpdate",
    "$env:PROGRAMDATA\Microsoft\EdgeUpdate",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Microsoft Edge.lnk",
    "$env:PUBLIC\Desktop\Microsoft Edge.lnk"
)

$EDGE_REG_KEYS = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update',
    'HKLM:\SOFTWARE\Microsoft\EdgeUpdate',
    'HKCU:\Software\Microsoft\Edge',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeUpdate',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft EdgeUpdate',
    'HKLM:\SOFTWARE\Microsoft\Edge',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Edge',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update'
)

$EDGE_SERVICES = @(
    'edgeupdate',
    'edgeupdatem',
    'MicrosoftEdgeElevationService'
)

# Folders that get ACL-locked to block reinstall
$BLOCK_FOLDERS = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge",
    "${env:ProgramFiles(x86)}\Microsoft\EdgeCore"
)

# Well-known SIDs
$SID_SYSTEM            = [System.Security.Principal.SecurityIdentifier]'S-1-5-18'
$SID_ADMINS            = [System.Security.Principal.SecurityIdentifier]'S-1-5-32-544'
$SID_USERS             = [System.Security.Principal.SecurityIdentifier]'S-1-5-32-545'
$SID_TRUSTED_INSTALLER = [System.Security.Principal.SecurityIdentifier]'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
$SID_CREATOR_OWNER     = [System.Security.Principal.SecurityIdentifier]'S-1-3-0'
$SID_ALL_APP_PACKAGES  = [System.Security.Principal.SecurityIdentifier]'S-1-15-2-1'
$SID_RESTRICTED_PKGS   = [System.Security.Principal.SecurityIdentifier]'S-1-15-2-2'
$SID_AUTH_USERS        = [System.Security.Principal.SecurityIdentifier]'S-1-5-11'

# ── Console helpers ────────────────────────────────────────────────────────────

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "  [$Title]" -ForegroundColor Yellow
}

function Write-Step  { param([string]$Msg) Write-Host "    >> $Msg" -ForegroundColor Cyan  }
function Write-Ok    { param([string]$Msg) Write-Host "    OK  $Msg" -ForegroundColor Green }
function Write-Fail  { param([string]$Msg) Write-Host "    !!  $Msg" -ForegroundColor Red   }
function Write-Skip  { param([string]$Msg) Write-Host "    --  $Msg" -ForegroundColor DarkGray }

# ── ACL builders ───────────────────────────────────────────────────────────────

function New-LockedAcl {
    <#
    Grants current user FullControl + TakeOwnership + ChangePermissions.
    Denies TakeOwnership + ChangePermissions to SYSTEM, Admins,
    TrustedInstaller, and AuthenticatedUsers so Windows Update cannot
    reclaim the folder and reinstall Edge.
    #>
    param([string]$OwnerName)

    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetOwner([System.Security.Principal.NTAccount]$OwnerName)
    $acl.SetAccessRuleProtection($true, $false)   # cut inheritance, clear inherited ACEs

    $allow = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $OwnerName,
        'FullControl,TakeOwnership,ChangePermissions',
        'ContainerInherit,ObjectInherit',
        'None',
        'Allow'
    )
    $acl.AddAccessRule($allow)

    foreach ($sid in @($SID_SYSTEM, $SID_ADMINS, $SID_TRUSTED_INSTALLER, $SID_AUTH_USERS)) {
        $deny = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sid,
            'TakeOwnership,ChangePermissions',
            'ContainerInherit,ObjectInherit',
            'None',
            'Deny'
        )
        $acl.AddAccessRule($deny)
    }

    return $acl
}

function New-DefaultAcl {
    <#
    Restores the standard Program Files ACL:
    TrustedInstaller/SYSTEM/Admins = FullControl
    Users/AllAppPackages/RestrictedPackages = ReadAndExecute
    CreatorOwner = FullControl
    Inheritance re-enabled.
    #>
    $acl = New-Object System.Security.AccessControl.DirectorySecurity
    $acl.SetOwner($SID_ADMINS)
    $acl.SetAccessRuleProtection($false, $true)   # restore inheritance

    $perms = @(
        @{ Sid = $SID_TRUSTED_INSTALLER; Rights = 'FullControl'      },
        @{ Sid = $SID_SYSTEM;            Rights = 'FullControl'      },
        @{ Sid = $SID_ADMINS;            Rights = 'FullControl'      },
        @{ Sid = $SID_USERS;             Rights = 'ReadAndExecute'   },
        @{ Sid = $SID_CREATOR_OWNER;     Rights = 'FullControl'      },
        @{ Sid = $SID_ALL_APP_PACKAGES;  Rights = 'ReadAndExecute'   },
        @{ Sid = $SID_RESTRICTED_PKGS;   Rights = 'ReadAndExecute'   }
    )

    foreach ($p in $perms) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $p.Sid,
            $p.Rights,
            'ContainerInherit,ObjectInherit',
            'None',
            'Allow'
        )
        $acl.AddAccessRule($rule)
    }

    return $acl
}

# ── Removal steps ──────────────────────────────────────────────────────────────

function Stop-EdgeProcesses {
    Write-Header 'Terminating Edge processes'
    $procs = Get-Process | Where-Object { $_.Name -like '*edge*' }
    if ($procs) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Ok "Stopped $($procs.Count) process(es)"
    } else {
        Write-Skip 'No Edge processes running'
    }
}

function Remove-ViaWinget {
    Write-Header 'Winget uninstall'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Start-Process winget `
            -ArgumentList 'uninstall --id Microsoft.Edge --silent --accept-source-agreements' `
            -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        Write-Ok 'Winget uninstall invoked'
    } else {
        Write-Skip 'Winget not found'
    }
}

function Remove-ViaSetup {
    Write-Header 'setup.exe force-uninstall'
    $searchPaths = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe",
        "$env:PROGRAMFILES\Microsoft\Edge\Application\*\Installer\setup.exe"
    )
    $found = $false
    foreach ($pattern in $searchPaths) {
        $setups = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue
        foreach ($s in $setups) {
            Start-Process $s.FullName `
                -ArgumentList '--uninstall --system-level --verbose-logging --force-uninstall' `
                -Wait -ErrorAction SilentlyContinue
            Write-Ok "Ran: $($s.FullName)"
            $found = $true
        }
    }
    if (-not $found) { Write-Skip 'No setup.exe found' }
}

function Remove-UWPPackages {
    Write-Header 'UWP package removal'
    foreach ($app in $EDGE_UWP_APPS) {
        Get-AppxPackage -Name "*$app*" -AllUsers -ErrorAction SilentlyContinue |
            Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue

        Get-AppxPackage -Name "*$app*" -ErrorAction SilentlyContinue |
            Remove-AppxPackage -ErrorAction SilentlyContinue

        Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*$app*" } |
            Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue

        Write-Ok "Processed: $app"
    }
}

function Remove-EdgeFolders {
    Write-Header 'Folder cleanup'
    foreach ($path in $EDGE_FOLDERS) {
        if (Test-Path $path) {
            Write-Step "Cleaning: $path"
            & takeown /F $path /R /D Y 2>&1 | Out-Null
            & icacls $path /grant 'administrators:F' /T 2>&1 | Out-Null
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $path) {
                Write-Fail "Partial removal: $path"
            } else {
                Write-Ok "Removed: $path"
            }
        }
    }
}

function Remove-EdgeRegistry {
    Write-Header 'Registry cleanup'
    foreach ($key in $EDGE_REG_KEYS) {
        if (Test-Path $key) {
            Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok "Deleted: $key"
        }
    }
}

function Remove-EdgeUpdateExe {
    Write-Header 'EdgeUpdate.exe uninstall'
    $exe = "${env:ProgramFiles(x86)}\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe"
    if (Test-Path $exe) {
        Start-Process $exe -ArgumentList '/uninstall' -Wait -ErrorAction SilentlyContinue
        Write-Ok 'EdgeUpdate uninstalled'
    } else {
        Write-Skip 'EdgeUpdate.exe not present'
    }
}

function Remove-EdgeServices {
    Write-Header 'Service removal'
    foreach ($svc in $EDGE_SERVICES) {
        if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            & sc.exe delete $svc | Out-Null
            Write-Ok "Deleted service: $svc"
        } else {
            Write-Skip "Service not found: $svc"
        }
    }
}

function Restart-WindowsExplorer {
    Write-Header 'Restarting Explorer'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
    Start-Process explorer
    Write-Ok 'Explorer restarted'
}

# ── Block / Unblock ────────────────────────────────────────────────────────────

function Invoke-Block {
    Write-Header 'Locking reinstall-block folders'
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $lockedAcl   = New-LockedAcl -OwnerName $currentUser

    foreach ($folder in $BLOCK_FOLDERS) {
        # Create if missing
        if (-not (Test-Path $folder)) {
            New-Item -Path $folder -ItemType Directory -Force | Out-Null
            Write-Ok "Created: $folder"
        }

        # Lock children first, then root
        $items = @(Get-ChildItem -Path $folder -Recurse -ErrorAction SilentlyContinue) + (Get-Item $folder)
        foreach ($item in $items) {
            try {
                Set-Acl -Path $item.FullName -AclObject $lockedAcl -ErrorAction Stop
                Write-Ok "Locked: $($item.FullName)"
            } catch {
                Write-Fail "Could not lock: $($item.FullName) -- $_"
            }
        }
    }
}

function Invoke-Unblock {
    Write-Header 'Restoring default folder permissions'
    $defaultAcl = New-DefaultAcl

    foreach ($folder in $BLOCK_FOLDERS) {
        if (-not (Test-Path $folder)) {
            Write-Skip "Folder absent, skipping: $folder"
            continue
        }

        $items = @(Get-ChildItem -Path $folder -Recurse -ErrorAction SilentlyContinue) + (Get-Item $folder)
        foreach ($item in $items) {
            try {
                Set-Acl -Path $item.FullName -AclObject $defaultAcl -ErrorAction Stop
                Write-Ok "Restored: $($item.FullName)"
            } catch {
                Write-Fail "Could not restore: $($item.FullName) -- $_"
            }
        }
    }
}

# ── Mode entry points ──────────────────────────────────────────────────────────

function Invoke-Uninstall {
    Stop-EdgeProcesses
    Remove-ViaWinget
    Remove-ViaSetup
    Remove-UWPPackages
    Remove-EdgeFolders
    Remove-EdgeRegistry
    Remove-EdgeUpdateExe
    Remove-EdgeServices
    Restart-WindowsExplorer
}

function Invoke-Vanish {
    Invoke-Uninstall
    Invoke-Block
}

# ── Banner + dispatch ──────────────────────────────────────────────────────────

Clear-Host
Write-Host ""
Write-Host "  ==========================================" -ForegroundColor DarkCyan
Write-Host "   $SCRIPT_NAME  v$SCRIPT_VERSION" -ForegroundColor White
Write-Host "   Mode: $Mode" -ForegroundColor Gray
Write-Host "  ==========================================" -ForegroundColor DarkCyan
Write-Host ""

switch ($Mode) {
    'Vanish'    { Invoke-Vanish   }
    'Uninstall' { Invoke-Uninstall }
    'Block'     { Invoke-Block    }
    'Unblock'   { Invoke-Unblock  }
}

Write-Host ""
Write-Host "  ===========================================" -ForegroundColor DarkCyan
Write-Host "   $Mode complete." -ForegroundColor Green
Write-Host "  ===========================================" -ForegroundColor DarkCyan
Write-Host ""

if ($Mode -in @('Vanish', 'Uninstall')) {
    Write-Host "  Restart your PC to finish cleanup." -ForegroundColor Yellow
    Write-Host ""
}
