#!/usr/bin/env bash
# Entry point for VS Code devcontainer "dotfiles" feature.
# Ensures GNU Stow is available, then symlinks every package folder in this
# repo (e.g. "bash") into $HOME using stow.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${HOME}"

install_stow() {
  if command -v stow >/dev/null 2>&1; then
    return 0
  fi

  echo "stow not found, attempting to install it..."

  if command -v apt-get >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then
      apt-get update && apt-get install -y stow
    else
      sudo apt-get update && sudo apt-get install -y stow
    fi
  elif command -v dnf >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then dnf install -y stow; else sudo dnf install -y stow; fi
  elif command -v yum >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then yum install -y stow; else sudo yum install -y stow; fi
  elif command -v apk >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then apk add --no-cache stow; else sudo apk add --no-cache stow; fi
  elif command -v pacman >/dev/null 2>&1; then
    if [ "$(id -u)" -eq 0 ]; then pacman -Sy --noconfirm stow; else sudo pacman -Sy --noconfirm stow; fi
  elif command -v brew >/dev/null 2>&1; then
    brew install stow
  else
    echo "Error: could not find a supported package manager to install stow." >&2
    exit 1
  fi
}

stow_packages() {
  local package
  for package in "${DOTFILES_DIR}"/*/; do
    package="$(basename "${package}")"
    echo "Stowing '${package}' -> ${TARGET_DIR}"
    stow --dir="${DOTFILES_DIR}" --target="${TARGET_DIR}" --no-folding --restow "${package}"
  done
}

install_stow
stow_packages
