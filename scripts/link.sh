#!/usr/bin/env bash
# Links this repo's profile sources into the Hermes profile folders (Linux/macOS).
# Same behaviour as scripts/link.ps1.
#
# For every profiles/<name>/ whose Hermes profile already exists
# (create it first with `hermes profile create <name>`), symlinks:
#   SOUL.md, config.yaml
#   skills/[<category>/]<skill>/   (any folder holding SKILL.md)
# and links every shared-skills/[<category>/]<skill>/ into each profile's skills/ folder at the
# same relative path (a profile's own skill at that path wins).
#
# Only these are linked. Runtime state (.env, auth, sessions, memories, logs, caches) stays in
# the Hermes profile and out of git. Zero-byte repo files, and skill folders holding only
# zero-byte files, count as "not written yet" and are never linked.
#
# Usage: scripts/link.sh [--adopt] [--dry-run]
#   --adopt    when a real file/folder already exists at the target:
#                repo copy missing or empty -> move the Hermes copy into the repo, then link
#                repo copy has content      -> back it up as <name>.bak-<time>, then link
#              Without --adopt such conflicts are reported and skipped.
#   --dry-run  print what would happen; change nothing.
# HERMES_HOME defaults to ~/.hermes.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
ADOPT=0
DRY=0
for arg in "$@"; do
  case "$arg" in
    --adopt) ADOPT=1 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

STAMP="$(date +%Y%m%d-%H%M%S)"
problems=0

warn() { echo "WARNING: $*" >&2; }

# true when a file is zero bytes, or a folder holds no non-empty file
is_empty() {
  if [[ -d "$1" ]]; then
    [[ -z "$(find "$1" -type f -size +0 -print -quit)" ]]
  else
    [[ ! -s "$1" ]]
  fi
}

link_item() { # source target label
  local src="$1" tgt="$2" label="$3" undo=""

  if [[ -L "$tgt" ]]; then
    if [[ "$(readlink -f "$tgt")" == "$(readlink -f "$src")" ]]; then
      echo "  ok       $label"; return
    fi
    echo "  relink   $label (pointed at $(readlink "$tgt"))"
    (( DRY )) || rm "$tgt"
  elif [[ -e "$tgt" ]]; then
    if (( ! ADOPT )); then
      warn "  conflict $label - real item exists at $tgt (rerun with --adopt)"
      problems=$((problems + 1)); return
    fi
    if is_empty "$src"; then
      echo "  adopt    $label (moving Hermes copy into repo)"
      if (( ! DRY )); then rm -rf "$src"; mv "$tgt" "$src"; undo="mv '$src' '$tgt'"; fi
    else
      local bak="$tgt.bak-$STAMP"
      echo "  backup   $label -> $(basename "$bak")"
      if (( ! DRY )); then mv "$tgt" "$bak"; undo="mv '$bak' '$tgt'"; fi
    fi
  elif is_empty "$src"; then
    echo "  skip     $label (empty in repo, nothing in Hermes)"; return
  fi

  echo "  link     $label"
  (( DRY )) && return
  if ! ln -s "$src" "$tgt"; then
    [[ -n "$undo" ]] && { eval "$undo"; warn "  rolled back $label"; }
    warn "  FAILED   $label"
    problems=$((problems + 1))
  fi
}

# prints "<relative path>" for every folder under $1 that holds a SKILL.md
skills_under() {
  [[ -d "$1" ]] || return 0
  find "$1" -type f -name SKILL.md -printf '%h\n' | sort | while read -r dir; do
    echo "${dir#"$1"/}"
  done
}

[[ -d "$HERMES_HOME/profiles" ]] || { echo "No profiles folder under $HERMES_HOME (set HERMES_HOME)" >&2; exit 1; }

mapfile -t shared < <(skills_under "$REPO/shared-skills")

for pdir in "$REPO"/profiles/*/; do
  name="$(basename "$pdir")"
  dest="$HERMES_HOME/profiles/$name"
  echo "[$name]"
  if [[ ! -d "$dest" ]]; then
    warn "  Hermes profile missing - run: hermes profile create $name"; continue
  fi

  for f in SOUL.md config.yaml; do
    # New profile: with --adopt, the file Hermes generated becomes the repo's starting copy.
    if [[ ! -e "$pdir$f" && -f "$dest/$f" && ! -L "$dest/$f" ]] && (( ADOPT )); then
      if (( DRY )); then echo "  adopt    $f (new in repo)"; continue; fi
      : > "$pdir$f"
    fi
    [[ -e "$pdir$f" ]] && link_item "$pdir$f" "$dest/$f" "$f"
  done

  mapfile -t own < <(skills_under "${pdir%/}/skills")
  for rel in "${own[@]}"; do
    [[ -n "$rel" ]] || continue
    (( DRY )) || mkdir -p "$(dirname "$dest/skills/$rel")"
    link_item "${pdir%/}/skills/$rel" "$dest/skills/$rel" "skills/$rel"
  done
  for rel in "${shared[@]}"; do
    [[ -n "$rel" ]] || continue
    printf '%s\n' "${own[@]}" | grep -qxF "$rel" && continue   # profile's own skill wins
    (( DRY )) || mkdir -p "$(dirname "$dest/skills/$rel")"
    link_item "$REPO/shared-skills/$rel" "$dest/skills/$rel" "skills/$rel"
  done
done

if (( problems )); then warn "$problems problem(s) - see above."; exit 1; fi
