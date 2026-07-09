#!/usr/bin/env bash
set -euo pipefail

# Refetch Copilot skills from a GitHub repo
# and install them into the local Copilot skills directory (~/.copilot/skills).
#
# Usage:
#   ./install-skills.sh              # fetch + install all skills
#   ./install-skills.sh --list       # list skills available in the repo, don't install
#   ./install-skills.sh --prune      # also remove local copies of skills deleted upstream
#   ./install-skills.sh --help
#
# Config (override via env):
#   SKILLS_REPO   repo to fetch from      
#   SKILLS_REF    branch/tag/sha          (default: main)
#   SKILLS_SUBDIR path to skills in repo  (default: skills)
#   SKILLS_DEST   local install dir       (default: $HOME/.copilot/skills)

SKILLS_REPO="${SKILLS_REPO}"
SKILLS_REF="${SKILLS_REF:-main}"
SKILLS_SUBDIR="${SKILLS_SUBDIR:-skills}"
SKILLS_DEST="${SKILLS_DEST:-$HOME/.copilot/skills}"

info() { printf "\033[1;34m::\033[0m %s\n" "$1"; }
warn() { printf "\033[1;33m::\033[0m %s\n" "$1"; }
ok()   { printf "\033[1;32m::\033[0m %s\n" "$1"; }
err()  { printf "\033[1;31m::\033[0m %s\n" "$1" >&2; }

usage() {
    cat <<'EOF'
Refetch Copilot skills from a GitHub repo 
and install them into the local Copilot skills directory (~/.copilot/skills).

Usage:
  ./install-skills.sh              # fetch + install all skills
  ./install-skills.sh --list       # list skills available in the repo, don't install
  ./install-skills.sh --prune      # also remove local copies of skills deleted upstream
  ./install-skills.sh --help

Config (override via env):
  SKILLS_REPO   repo to fetch from      
  SKILLS_REF    branch/tag/sha          (default: main)
  SKILLS_SUBDIR path to skills in repo  (default: skills)
  SKILLS_DEST   local install dir       (default: $HOME/.copilot/skills)
EOF
    exit 0
}

LIST_ONLY=false
PRUNE=false
for arg in "$@"; do
    case "$arg" in
        --list)  LIST_ONLY=true ;;
        --prune) PRUNE=true ;;
        -h|--help) usage ;;
        *) err "Unknown argument: $arg"; usage ;;
    esac
done

require() {
    command -v "$1" &>/dev/null || { err "Required tool not found: $1"; exit 1; }
}
require git

# Prefer gh for authenticated clones (graphql-platform is a private/internal repo).
clone_repo() {
    local dest="$1"
    if command -v gh &>/dev/null; then
        gh repo clone "$SKILLS_REPO" "$dest" -- \
            --depth 1 --branch "$SKILLS_REF" --filter=blob:none --sparse --quiet
    else
        warn "gh CLI not found; falling back to git (requires credentials for $SKILLS_REPO)"
        git clone --depth 1 --branch "$SKILLS_REF" --filter=blob:none --sparse --quiet \
            "https://github.com/$SKILLS_REPO.git" "$dest"
    fi
}

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

info "Fetching skills from $SKILLS_REPO@$SKILLS_REF ($SKILLS_SUBDIR/)"
clone_repo "$TMP_DIR"
git -C "$TMP_DIR" sparse-checkout set "$SKILLS_SUBDIR" >/dev/null 2>&1 || true

SRC_DIR="$TMP_DIR/$SKILLS_SUBDIR"
if [[ ! -d "$SRC_DIR" ]]; then
    err "No '$SKILLS_SUBDIR' directory found in $SKILLS_REPO@$SKILLS_REF"
    exit 1
fi

# A skill is any subdirectory that contains a SKILL.md.
SKILLS=()
while IFS= read -r line; do
    SKILLS+=("$line")
done < <(cd "$SRC_DIR" && find . -maxdepth 2 -name SKILL.md -print | sed 's#^\./##;s#/SKILL.md$##' | sort)

if [[ ${#SKILLS[@]} -eq 0 ]]; then
    err "No skills (directories containing SKILL.md) found under $SRC_DIR"
    exit 1
fi

if $LIST_ONLY; then
    info "${#SKILLS[@]} skill(s) available in $SKILLS_REPO@$SKILLS_REF:"
    for s in "${SKILLS[@]}"; do echo "   - $s"; done
    exit 0
fi

mkdir -p "$SKILLS_DEST"
info "Installing into $SKILLS_DEST"
echo

installed=0 updated=0 unchanged=0
for skill in "${SKILLS[@]}"; do
    src="$SRC_DIR/$skill"
    dest="$SKILLS_DEST/$skill"

    if [[ -e "$dest" ]]; then
        if diff -rq --exclude=.skills-source "$src" "$dest" >/dev/null 2>&1; then
            ok "Unchanged: $skill"
            ((unchanged++)) || true
            continue
        fi
        rm -rf "$dest"
        cp -R "$src" "$dest"
        ok "Updated:   $skill"
        ((updated++)) || true
    else
        cp -R "$src" "$dest"
        ok "Installed: $skill"
        ((installed++)) || true
    fi
done

# Optionally remove local skills that came from this repo but were deleted upstream.
if $PRUNE; then
    echo
    info "Pruning skills removed upstream (only those previously fetched from $SKILLS_REPO)"
    for dir in "$SKILLS_DEST"/*/; do
        [[ -d "$dir" ]] || continue
        name="$(basename "$dir")"
        for s in "${SKILLS[@]}"; do [[ "$s" == "$name" ]] && continue 2; done
        # Not present upstream. Only prune if it looks repo-managed (has a marker file we drop below).
        if [[ -f "$dir/.skills-source" ]] && grep -qx "$SKILLS_REPO" "$dir/.skills-source" 2>/dev/null; then
            rm -rf "$dir"
            warn "Pruned:    $name (deleted upstream)"
        fi
    done
fi

# Drop a provenance marker so --prune can safely identify repo-managed skills later.
for skill in "${SKILLS[@]}"; do
    echo "$SKILLS_REPO" > "$SKILLS_DEST/$skill/.skills-source"
done

echo
ok "Done. Installed: $installed, Updated: $updated, Unchanged: $unchanged (of ${#SKILLS[@]} skills)."
info "Local skills that were not in $SKILLS_REPO were left untouched."
