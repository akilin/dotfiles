#!/usr/bin/env bash
# Entry point for VS Code devcontainer "dotfiles" feature.
# Ensures GNU Stow and jq are available, symlinks every package folder in this
# repo (e.g. "bash") into $HOME using stow, and sets up Claude's config dir.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}"
# Same rules as Claude: CLAUDE_CONFIG_DIR holds settings.json and .claude.json when set.
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
CLAUDE_GLOBAL_CONFIG="${CLAUDE_CONFIG_DIR:-${HOME}}/.claude.json"

ensure_installed() {
  local pkg="$1"
  if command -v "${pkg}" >/dev/null 2>&1; then
    return 0
  fi

  echo "${pkg} not found, attempting to install it..."

  if command -v apt-get >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
      apt-get update && apt-get install -y "${pkg}"
    else
      sudo apt-get update && sudo apt-get install -y "${pkg}"
    fi
  elif command -v dnf >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then dnf install -y "${pkg}"; else sudo dnf install -y "${pkg}"; fi
  elif command -v yum >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then yum install -y "${pkg}"; else sudo yum install -y "${pkg}"; fi
  elif command -v apk >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then apk add --no-cache "${pkg}"; else sudo apk add --no-cache "${pkg}"; fi
  elif command -v pacman >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then pacman -Sy --noconfirm "${pkg}"; else sudo pacman -Sy --noconfirm "${pkg}"; fi
  elif command -v brew >/dev/null 2>&1; then
    brew install "${pkg}"
  else
    echo "Error: could not find a supported package manager to install ${pkg}." >&2
    exit 1
  fi
}

stow_packages() {
  local package
  for package in "${DOTFILES_DIR}"/*/; do
    package="$(basename "${package}")"
    # claude goes to Claude's config dir, see stow_claude_files.
    [ "${package}" = claude ] && continue
    echo "Stowing '${package}' -> ${TARGET_DIR}"
    stow --dir="${DOTFILES_DIR}" --target="${TARGET_DIR}" --no-folding --restow "${package}"
  done
}

# Only claude/.claude is linked; the json files next to it are merged below.
stow_claude_files() {
  mkdir -p "${CLAUDE_DIR}"
  echo "Stowing 'claude/.claude' -> ${CLAUDE_DIR}"
  stow --dir="${DOTFILES_DIR}/claude" --target="${CLAUDE_DIR}" --no-folding --restow .claude
}

# Claude rewrites both files at runtime, so merge instead of symlinking.
# Repo values win; arrays defined in the repo replace existing ones.
merge_json() {
  local base="$1"
  local target="$2"
  local current='{}'

  mkdir -p "$(dirname "${target}")"
  if [ -s "${target}" ]; then
    current="$(cat "${target}")"
  fi

  echo "Merging '${base}' -> ${target}"
  local merged
  merged="$(jq -n --argjson cur "${current}" --slurpfile base "${base}" '$cur * $base[0]')"
  printf '%s\n' "${merged}" > "${target}"
}

# Claude only installs plugins from settings.json in the background after it
# starts, so they are missing from the first session. Install them up front.
install_claude_plugins() {
  local settings="${DOTFILES_DIR}/claude/settings.json"
  local claude_bin
  claude_bin="$(command -v claude || echo "${HOME}/.local/bin/claude")"
  if [ ! -x "${claude_bin}" ]; then
    echo "claude not found, skipping plugin install"
    return 0
  fi

  local source plugin
  jq -r '.extraKnownMarketplaces // {} | .[].source | .repo // .url // .path' "${settings}" |
    while read -r source; do
      echo "Adding marketplace '${source}'"
      "${claude_bin}" plugin marketplace add "${source}" </dev/null ||
        echo "Warning: could not add marketplace '${source}'" >&2
    done
  "${claude_bin}" plugin marketplace update </dev/null ||
    echo "Warning: could not update marketplaces" >&2

  jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key | select(endswith("@builtin") | not)' "${settings}" |
    while read -r plugin; do
      echo "Installing plugin '${plugin}'"
      { "${claude_bin}" plugin install "${plugin}" </dev/null &&
        "${claude_bin}" plugin update "${plugin}" </dev/null; } ||
        echo "Warning: could not install plugin '${plugin}'" >&2
    done
}

ensure_installed stow
ensure_installed jq
stow_packages
stow_claude_files
merge_json "${DOTFILES_DIR}/claude/settings.json" "${CLAUDE_DIR}/settings.json"
merge_json "${DOTFILES_DIR}/claude/claude.json" "${CLAUDE_GLOBAL_CONFIG}"
install_claude_plugins
