<#
.SYNOPSIS
  Links this repo's profile sources into the Hermes profile folders.

.DESCRIPTION
  For every profiles/<name>/ in the repo whose Hermes profile already exists
  (create it first with `hermes profile create <name>`), links:
    SOUL.md, config.yaml   -> file symlinks   (needs Developer Mode or admin)
    skills/[<category>/]<skill>/  -> directory junctions (any folder holding SKILL.md)
  and links every shared-skills/[<category>/]<skill>/ into each profile's skills/
  folder at the same relative path (a profile's own skill at that path wins).

  Only these files are linked. Runtime state (auth, sessions, memories, logs,
  caches) stays inside the Hermes profile and out of the repo.

  Zero-byte repo files and skill folders containing only zero-byte files (the
  empty scaffold) are treated as "not written yet": they are never linked.

.PARAMETER HermesHome
  Defaults to $env:HERMES_HOME, else %LOCALAPPDATA%\hermes.

.PARAMETER Adopt
  When a real file/folder already exists at the target:
    - repo copy missing or empty -> move the Hermes copy into the repo, then link
    - repo copy has content      -> back up the Hermes copy as <name>.bak-<time>, then link
  Without -Adopt such conflicts are reported and skipped.

.PARAMETER DryRun
  Print what would happen; change nothing.
#>
[CmdletBinding()]
param(
  [string]$HermesHome = $(if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }),
  [switch]$Adopt,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:conflicts = 0

function Test-Empty([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force
  if ($item.PSIsContainer) { return -not (Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Where-Object Length -gt 0) }
  return $item.Length -eq 0
}

function Link-Item {
  param([string]$Source, [string]$Target, [string]$Label)

  $isDir = (Get-Item -LiteralPath $Source -Force).PSIsContainer
  $undo = $null
  if (Test-Path -LiteralPath $Target) {
    $existing = Get-Item -LiteralPath $Target -Force
    if ($existing.LinkType) {
      $current = @($existing.Target)[0]
      if ($current -and ((Resolve-Path -LiteralPath $current -ErrorAction SilentlyContinue).Path -eq (Resolve-Path -LiteralPath $Source).Path)) {
        Write-Host "  ok       $Label"; return
      }
      Write-Host "  relink   $Label (pointed at $current)"
      if (-not $DryRun) { $existing.Delete() }
    }
    else {
      if (-not $Adopt) {
        Write-Warning "  conflict $Label - real item exists at $Target (rerun with -Adopt)"
        $script:conflicts++; return
      }
      if (Test-Empty $Source) {
        Write-Host "  adopt    $Label (moving Hermes copy into repo)"
        if (-not $DryRun) {
          Remove-Item -LiteralPath $Source -Recurse -Force
          Move-Item -LiteralPath $Target -Destination $Source
          $undo = { Move-Item -LiteralPath $Source -Destination $Target }
        }
      }
      else {
        $bak = "$Target.bak-$stamp"
        Write-Host "  backup   $Label -> $(Split-Path -Leaf $bak)"
        if (-not $DryRun) {
          Move-Item -LiteralPath $Target -Destination $bak
          $undo = { Move-Item -LiteralPath $bak -Destination $Target }
        }
      }
    }
  }
  elseif (Test-Empty $Source) {
    Write-Host "  skip     $Label (empty in repo, nothing in Hermes)"; return
  }

  Write-Host "  link     $Label"
  if ($DryRun) { return }
  try {
    if ($isDir) {
      New-Item -ItemType Junction -Path $Target -Target $Source | Out-Null
    }
    else {
      # cmd's mklink honours Developer Mode; Windows PowerShell 5.1's New-Item does not.
      $out = cmd /c mklink "`"$Target`"" "`"$Source`"" 2>&1
      if ($LASTEXITCODE -ne 0) { throw "mklink failed: $out (enable Developer Mode or run elevated)" }
    }
  }
  catch {
    if ($undo) { & $undo; Write-Warning "  rolled back $Label" }
    Write-Warning "  FAILED   $Label - $($_.Exception.Message)"
    $script:conflicts++
  }
}

if (-not (Test-Path (Join-Path $HermesHome 'profiles'))) { throw "No profiles folder under $HermesHome (set -HermesHome or HERMES_HOME)" }

# A skill is any folder containing SKILL.md, at any depth: <skill>/ or <category>/<skill>/.
# Rel is the path below the root and is reused as the path inside the Hermes skills folder.
function Get-Skills([string]$Root) {
  if (-not (Test-Path $Root)) { return @() }
  $rootFull = (Resolve-Path $Root).Path.TrimEnd('\')
  @(Get-ChildItem $Root -Recurse -File -Filter SKILL.md -Force | ForEach-Object {
      [pscustomobject]@{ Rel = $_.Directory.FullName.Substring($rootFull.Length + 1); FullName = $_.Directory.FullName }
    })
}

$sharedSkills = Get-Skills (Join-Path $repo 'shared-skills')

foreach ($profile in Get-ChildItem (Join-Path $repo 'profiles') -Directory) {
  $dest = Join-Path $HermesHome "profiles\$($profile.Name)"
  Write-Host "[$($profile.Name)]"
  if (-not (Test-Path $dest)) {
    Write-Warning "  Hermes profile missing - run: hermes profile create $($profile.Name)"; continue
  }

  foreach ($file in 'SOUL.md', 'config.yaml') {
    $src = Join-Path $profile.FullName $file
    if (Test-Path $src) { Link-Item $src (Join-Path $dest $file) $file }
  }

  $ownSkills = Get-Skills (Join-Path $profile.FullName 'skills')
  $ownRels = @($ownSkills | ForEach-Object Rel)
  $skills = @($ownSkills) + @($sharedSkills | Where-Object { $_.Rel -notin $ownRels })
  $skillsDir = Join-Path $dest 'skills'
  foreach ($skill in $skills) {
    $target = Join-Path $skillsDir $skill.Rel
    if (-not $DryRun) { New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null }
    Link-Item $skill.FullName $target ("skills/" + ($skill.Rel -replace '\\', '/'))
  }
}

if ($script:conflicts) { Write-Warning "$script:conflicts problem(s) - see above."; exit 1 }
exit 0
