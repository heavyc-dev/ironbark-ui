<#
.SYNOPSIS
  Back up WoW Forever addon settings and switch between EllesmereUI and Ironbark UI.

.EXAMPLE
  .\tools\ui-switch.ps1 status
  .\tools\ui-switch.ps1 backup -Label baseline -IncludeAddOns
  .\tools\ui-switch.ps1 ironbark      # test Ironbark UI
  .\tools\ui-switch.ps1 ellesmere     # go back to exactly how things were
  .\tools\ui-switch.ps1 restore -Zip .\backups\2026-11-20_1130-baseline.zip

.NOTES
  - WoW must be closed to switch/restore: the game rewrites WTF on exit and would
    overwrite whatever we put there.
  - Before switching back to EllesmereUI, type /ibui revert in game first. Edit Mode
    layouts and some settings are stored on Blizzard's servers, so restoring
    files alone may not undo them.
  - Backups are zips in .\backups (git-ignored). Nothing is ever deleted.
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'backup', 'ironbark', 'ellesmere', 'restore')]
    [string]$Action = 'status',
    [string]$Label = 'manual',
    [switch]$IncludeAddOns,
    [string]$Zip,
    [string]$GameDir = 'C:\Program Files (x86)\World of Warcraft\_forever_'
)

$ErrorActionPreference = 'Stop'
$RepoDir    = Split-Path -Parent $PSScriptRoot
$BackupDir  = Join-Path $RepoDir 'backups'
$StateFile  = Join-Path $BackupDir 'state.json'
$WtfDir     = Join-Path $GameDir 'WTF'
$AddOnsDir  = Join-Path $GameDir 'Interface\AddOns'
$LinkPath   = Join-Path $AddOnsDir 'IronbarkUI'
$SourcePath = Join-Path $RepoDir 'IronbarkUI'

# Addons turned off while testing Ironbark (anything starting with these names).
$EllesmerePrefixes = @('EllesmereUI', 'Tust_EUI')

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

function Test-WowRunning {
    return [bool](Get-Process -Name 'Wow', 'WowClassic', 'Wow-64' -ErrorAction SilentlyContinue)
}

function Assert-WowClosed {
    if (Test-WowRunning) {
        throw 'World of Warcraft is running. Exit the game completely, then run this again.'
    }
}

function Get-State {
    if (Test-Path $StateFile) { return Get-Content $StateFile -Raw | ConvertFrom-Json }
    return [pscustomobject]@{ mode = 'ellesmere'; ironbarkBackup = $null }
}

function Save-State($state) {
    New-Item -ItemType Directory -Force $BackupDir | Out-Null
    $state | ConvertTo-Json | Set-Content -Encoding utf8 $StateFile
}

function New-Backup([string]$label, [switch]$withAddOns) {
    New-Item -ItemType Directory -Force $BackupDir | Out-Null
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $zip = Join-Path $BackupDir "$stamp-$label.zip"
    Write-Step "Backing up WTF -> $zip"
    Compress-Archive -Path $WtfDir -DestinationPath $zip -CompressionLevel Optimal
    if ($withAddOns) {
        $azip = Join-Path $BackupDir "$stamp-$label-AddOns.zip"
        Write-Step "Backing up Interface\AddOns -> $azip (this one takes a minute)"
        # skip our own junction so the backup only holds third-party addons
        $items = Get-ChildItem $AddOnsDir | Where-Object { $_.Name -ne 'IronbarkUI' }
        Compress-Archive -Path $items.FullName -DestinationPath $azip -CompressionLevel Optimal
    }
    return $zip
}

function Restore-Wtf([string]$zip) {
    if (-not (Test-Path $zip)) { throw "Backup not found: $zip" }
    $tmp = Join-Path $BackupDir ('_restore_' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -Path $zip -DestinationPath $tmp
    $restored = Join-Path $tmp 'WTF'
    if (-not (Test-Path (Join-Path $restored 'Account'))) {
        Remove-Item -Recurse -Force $tmp
        throw "Zip doesn't contain a WTF folder: $zip"
    }
    Write-Step "Restoring WTF from $zip"
    Remove-Item -Recurse -Force $WtfDir
    Move-Item $restored $WtfDir
    Remove-Item -Recurse -Force $tmp
}

function Set-AddOnStates([hashtable]$wanted, [string[]]$disablePrefixes) {
    # Addons missing from AddOns.txt load by default, so every installed addon
    # matching a prefix gets an explicit "disabled" line.
    $wanted = $wanted.Clone()
    Get-ChildItem $AddOnsDir -Directory | ForEach-Object {
        $n = $_.Name
        if (-not $wanted.ContainsKey($n) -and ($disablePrefixes | Where-Object { $n.StartsWith($_) })) {
            $wanted[$n] = 'disabled'
        }
    }
    $files = Get-ChildItem -Path (Join-Path $WtfDir 'Account') -Recurse -Filter 'AddOns.txt'
    foreach ($f in $files) {
        $lines = [System.Collections.Generic.List[string]](Get-Content $f.FullName)
        $seen = @{}
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^(?<name>[^:]+):\s*(?<state>\w+)') {
                $name = $Matches['name']
                $seen[$name] = $true
                if ($wanted.ContainsKey($name)) {
                    $lines[$i] = "${name}: $($wanted[$name])"
                } elseif ($disablePrefixes | Where-Object { $name.StartsWith($_) }) {
                    $lines[$i] = "${name}: disabled"
                }
            }
        }
        foreach ($name in $wanted.Keys) {
            if (-not $seen[$name]) { $lines.Add("${name}: $($wanted[$name])") }
        }
        Set-Content -Path $f.FullName -Value $lines -Encoding ascii
        Write-Host "    updated $($f.Directory.Name)"
    }
}

function Install-Link {
    if (Test-Path $LinkPath) {
        $item = Get-Item $LinkPath -Force
        if ($item.LinkType -eq 'Junction') { return }
        throw "$LinkPath exists and is not our link. Move it away first."
    }
    Write-Step "Linking AddOns\IronbarkUI -> $SourcePath"
    cmd /c mklink /J "`"$LinkPath`"" "`"$SourcePath`"" | Out-Null
    if (-not (Test-Path $LinkPath)) { throw 'Could not create the AddOns link (permissions?).' }
}

function Remove-Link {
    if (-not (Test-Path $LinkPath)) { return }
    $item = Get-Item $LinkPath -Force
    if ($item.LinkType -ne 'Junction') {
        Write-Warning "$LinkPath is a real folder, not our link; leaving it alone."
        return
    }
    Write-Step 'Removing AddOns\IronbarkUI link (repo files are untouched)'
    # rmdir on a junction removes only the link, never the target's contents
    cmd /c rmdir "`"$LinkPath`""
}

switch ($Action) {
    'status' {
        $state = Get-State
        Write-Host "Mode:          $($state.mode)"
        Write-Host "WoW running:   $(Test-WowRunning)"
        Write-Host "Ironbark link: $(Test-Path $LinkPath)"
        if ($state.ironbarkBackup) { Write-Host "Revert point:  $($state.ironbarkBackup)" }
        Write-Host 'Backups:'
        if (Test-Path $BackupDir) {
            Get-ChildItem $BackupDir -Filter *.zip | Sort-Object Name |
                ForEach-Object { '    {0}  ({1:N1} MB)' -f $_.Name, ($_.Length / 1MB) }
        }
    }
    'backup' {
        if (Test-WowRunning) {
            Write-Warning 'WoW is running: this captures the last saved state (last /reload or logout).'
        }
        New-Backup $Label -withAddOns:$IncludeAddOns | Out-Null
        Write-Host 'Done.'
    }
    'ironbark' {
        Assert-WowClosed
        $state = Get-State
        if ($state.mode -eq 'ironbark') {
            Write-Host 'Already in Ironbark mode; re-applying link and addon states.'
            Install-Link
            Set-AddOnStates @{ 'IronbarkUI' = 'enabled' } $EllesmerePrefixes
            break
        }
        $zip = New-Backup 'before-ironbark'
        Install-Link
        Write-Step 'Disabling EllesmereUI addons, enabling IronbarkUI (all characters)'
        Set-AddOnStates @{ 'IronbarkUI' = 'enabled' } $EllesmerePrefixes
        Save-State ([pscustomobject]@{ mode = 'ironbark'; ironbarkBackup = $zip })
        Write-Host ''
        Write-Host 'Ironbark mode on. Launch WoW; you will be asked to apply the layout.' -ForegroundColor Green
        Write-Host "To go back: in game type /ibui revert, exit WoW, then run: .\tools\ui-switch.ps1 ellesmere"
    }
    'ellesmere' {
        Assert-WowClosed
        $state = Get-State
        if (-not $state.ironbarkBackup) { throw 'No revert point recorded. Use: restore -Zip <file>' }
        New-Backup 'ironbark-session' | Out-Null   # keep the test session too, just in case
        Restore-Wtf $state.ironbarkBackup
        Remove-Link
        Save-State ([pscustomobject]@{ mode = 'ellesmere'; ironbarkBackup = $null })
        Write-Host ''
        Write-Host 'Back to EllesmereUI, settings exactly as before testing.' -ForegroundColor Green
    }
    'restore' {
        Assert-WowClosed
        if (-not $Zip) { throw 'Pass -Zip <path to a WTF backup zip>.' }
        New-Backup 'before-restore' | Out-Null
        Restore-Wtf (Resolve-Path $Zip).Path
        Write-Host 'Restored.' -ForegroundColor Green
    }
}
