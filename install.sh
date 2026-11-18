#!/usr/bin/env bash
# Build and install cosmic-comp-evdi, replacing the stock cosmic-comp package.
#
# Usage: ./install.sh [--yes] [--force]
#   --yes    do not ask for confirmation (pacman --noconfirm, auto-replace cosmic-comp)
#   --force  build even if the installed cosmic-comp version differs from PKGBUILD
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

yes=0
force=0
for arg in "$@"; do
    case "$arg" in
        --yes) yes=1 ;;
        --force) force=1 ;;
        -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

command -v pacman >/dev/null || die "pacman not found; this package targets Arch Linux and derivatives"
command -v makepkg >/dev/null || die "makepkg not found; install base-devel"
[ "$(id -u)" -ne 0 ] || die "run as a regular user, not root (makepkg refuses to run as root)"

# shellcheck disable=SC1091
pkgver=$(. ./PKGBUILD && echo "${epoch}:${pkgver}")

installed=$(pacman -Q cosmic-comp 2>/dev/null | awk '{print $2}' || true)
if pacman -Q cosmic-comp-evdi >/dev/null 2>&1; then
    info "cosmic-comp-evdi is already installed ($(pacman -Q cosmic-comp-evdi | awk '{print $2}')); it will be rebuilt and reinstalled"
elif [ -n "$installed" ]; then
    # Strip pkgrel and any distro suffix (e.g. 1:1.11.0-1.1 -> 1:1.11.0)
    installed_ver=${installed%%-*}
    if [ "$installed_ver" != "$pkgver" ] && [ "$force" -eq 0 ]; then
        die "installed cosmic-comp is $installed, but this PKGBUILD builds $pkgver.
       Mixing COSMIC component versions is not supported. Update the PKGBUILD
       (pkgver + b2sums) and check that the patches still apply, or pass --force."
    fi
else
    die "cosmic-comp is not installed; install the COSMIC desktop first"
fi

pkgfile=$(makepkg --packagelist | head -n1)
if [ -f "$pkgfile" ] && [ -z "$(find PKGBUILD ./*.patch -newer "$pkgfile")" ]; then
    info "Using existing build $pkgfile"
else
    info "Building cosmic-comp-evdi $pkgver (this takes a while)"
    makepkg -f -s --needed $([ "$yes" -eq 1 ] && echo --noconfirm)
fi
[ -f "$pkgfile" ] || die "built package not found: $pkgfile"

info "Installing $pkgfile (replaces cosmic-comp)"
if [ "$yes" -eq 1 ]; then
    # --ask 4: answer "yes" to removing the conflicting cosmic-comp package
    sudo pacman -U --noconfirm --ask 4 "$pkgfile"
else
    sudo pacman -U "$pkgfile"
fi

pacman -Qo /usr/bin/cosmic-comp | grep -q cosmic-comp-evdi \
    || die "/usr/bin/cosmic-comp is not owned by cosmic-comp-evdi after install"

info "Installed. Log out and back in to start the patched compositor."
info "Verify with: ./tools/measure.sh"
