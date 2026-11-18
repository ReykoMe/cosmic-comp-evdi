#!/usr/bin/env bash
# Remove cosmic-comp-evdi and restore the stock cosmic-comp package.
#
# Usage: ./uninstall.sh [--yes] [--keep-build]
#   --yes         do not ask for confirmation
#   --keep-build  keep build artifacts (src/, pkg/, built packages) in this directory
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

yes=0
keep_build=0
for arg in "$@"; do
    case "$arg" in
        --yes) yes=1 ;;
        --keep-build) keep_build=1 ;;
        -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

command -v pacman >/dev/null || die "pacman not found"

if pacman -Q cosmic-comp-evdi >/dev/null 2>&1; then
    info "Replacing cosmic-comp-evdi with the stock cosmic-comp from the repositories"
    if [ "$yes" -eq 1 ]; then
        # --ask 4: answer "yes" to removing the conflicting cosmic-comp-evdi package
        sudo pacman -S --noconfirm --ask 4 cosmic-comp
    else
        sudo pacman -S cosmic-comp
    fi
    pacman -Q cosmic-comp-evdi >/dev/null 2>&1 && die "cosmic-comp-evdi is still installed"
    pacman -Qo /usr/bin/cosmic-comp | grep -q ' cosmic-comp ' \
        || die "/usr/bin/cosmic-comp is not owned by the stock cosmic-comp package"
    info "Stock cosmic-comp $(pacman -Q cosmic-comp | awk '{print $2}') restored"
else
    info "cosmic-comp-evdi is not installed; nothing to remove"
fi

if [ "$keep_build" -eq 0 ]; then
    info "Removing build artifacts"
    rm -rf -- src pkg cosmic-comp
    rm -f -- ./*.pkg.tar.* ./*.log
fi

info "Done. Log out and back in to start the stock compositor."
