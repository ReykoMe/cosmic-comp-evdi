# Maintainer: ReykoMe <ReykoMe@users.noreply.github.com>
# Based on the Arch Linux cosmic-comp PKGBUILD by
# Maxime Gauduin <alucryd@archlinux.org> and Peter Jung <ptr1337@archlinux.org>

_pkgname=cosmic-comp
pkgname=cosmic-comp-evdi
pkgver=1.11.0
pkgrel=1
epoch=1
pkgdesc='COSMIC compositor patched to render DisplayLink (evdi) outputs on the GPU instead of llvmpipe'
arch=(x86_64)
url='https://github.com/ReykoMe/cosmic-comp-evdi'
license=(GPL-3.0-only)
groups=(cosmic)
depends=(
  fontconfig
  libgcc
  glibc
  libdisplay-info
  libseat.so
  libinput
  libxcb
  libxkbcommon
  mesa
  pixman
  systemd-libs
  wayland
)
makedepends=(
  cargo
  git
  just
  lld
)
provides=("${_pkgname}=${epoch}:${pkgver}")
conflicts=("${_pkgname}")
source=(
  "git+https://github.com/pop-os/cosmic-comp.git#tag=epoch-${pkgver}"
  0001-render-evdi-outputs-on-primary-gpu.patch
  0002-offscreen-capture-on-primary-gpu.patch
)
b2sums=('4f6e0dbb8e7028ae8a47765ebd8ab198f87bacfe6d15e5856be51142f46aabddcb29b9f2dbf99acaf9b74fd45f6611330c19f7d29013719fecdf746c9e14ace2'
        'd6d2645a77b25f6cb8c4baa1d155f3a25c4235888ffbf354e155ac7a65a7878345af885a7b9f0977e12b0a8846a4827de67fde2c5dd0e90418771811fdb5247c'
        'c66068a79c3484197d867c68cc9be93c51bade2fb91f0a56a6980fcf83950c2c4d89f409ec42b648c547ba716a3405948697784f7c0aa4bae61ad03278caca75')

prepare() {
  cd "${_pkgname}"

  local p
  for p in "${srcdir}"/*.patch; do
    echo "Applying ${p##*/}"
    patch -Np1 -i "${p}"
  done

  cargo fetch --locked
  sed 's/lto = "fat"/lto = "thin"/' -i Cargo.toml
}

build() {
  cd "${_pkgname}"
  RUSTFLAGS+=" -C link-arg=-fuse-ld=lld"
  just build-release --frozen
}

package() {
  cd "${_pkgname}"
  just rootdir="${pkgdir}" install
}

# vim: ts=2 sw=2 et:
