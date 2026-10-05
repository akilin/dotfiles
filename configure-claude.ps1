#Requires -Version 7
# Windows counterpart of install.sh, limited to Claude Code.
# Links every file under claude/.claude into ~/.claude (copies instead when
# symlinks aren't allowed, i.e. no admin / Developer Mode) and merges
# claude/settings.json into ~/.claude/settings.json.
$ErrorActionPreference = 'Stop'

$DotfilesDir = $PSScriptRoot
$TargetDir = Join-Path $HOME '.claude'

function Link-ClaudeFiles {
    $sourceRoot = Join-Path $DotfilesDir 'claude/.claude'
    $copied = $false

    foreach ($file in Get-ChildItem $sourceRoot -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($sourceRoot, $file.FullName)
        $target = Join-Path $TargetDir $relative
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null

        $existing = Get-Item $target -Force -ErrorAction SilentlyContinue
        if ($existing -and $existing.LinkTarget -eq $file.FullName) {
            continue
        }
        if ($existing) {
            Remove-Item $target -Force
        }

        try {
            New-Item -ItemType SymbolicLink -Path $target -Target $file.FullName | Out-Null
            Write-Host "Linked '$relative' -> $target"
        } catch {
            Copy-Item $file.FullName $target
            Write-Host "Copied '$relative' -> $target"
            $copied = $true
        }
    }

    if ($copied) {
        Write-Warning 'Symlinks unavailable (enable Developer Mode or run as admin); files were copied, re-run after editing them.'
    }
}

# Mirrors jq's '$cur * $base': objects merge recursively, everything else
# (scalars, arrays) is replaced by the repo value.
function Merge-Json($current, $base) {
    foreach ($key in $base.Keys) {
        if ($current[$key] -is [Collections.IDictionary] -and $base[$key] -is [Collections.IDictionary]) {
            Merge-Json $current[$key] $base[$key]
        } else {
            $current[$key] = $base[$key]
        }
    }
}

# Claude rewrites its settings file at runtime, so merge instead of linking.
function Merge-ClaudeSettings {
    $base = Join-Path $DotfilesDir 'claude/settings.json'
    $target = Join-Path $TargetDir 'settings.json'

    $current = [ordered]@{}
    if ((Test-Path $target) -and (Get-Item $target).Length -gt 0) {
        $current = Get-Content $target -Raw | ConvertFrom-Json -AsHashtable
    }

    Write-Host "Merging '$base' -> $target"
    Merge-Json $current (Get-Content $base -Raw | ConvertFrom-Json -AsHashtable)
    $json = ($current | ConvertTo-Json -Depth 100) -replace "`r`n", "`n"
    [IO.File]::WriteAllText($target, "$json`n")
}

New-Item -ItemType Directory -Force $TargetDir | Out-Null
Link-ClaudeFiles
Merge-ClaudeSettings
