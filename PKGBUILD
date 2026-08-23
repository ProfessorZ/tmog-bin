# Maintainer: Tom Geldermans <tom.geldermans@gmail.com>

pkgname=tmog-bin
pkgver=0.1.1
pkgrel=1
pkgdesc="Task Manager TMOG, a native Qt 6 system monitor and task manager by Dave Plummer (binary release)"
arch=('x86_64')
url='https://tmog.org/'
license=('LicenseRef-proprietary')
depends=('glibc' 'libgcc' 'libstdc++' 'qt6-base' 'qt6-multimedia' 'qt6-svg' 'systemd-libs')
optdepends=('qt6-wayland: native Wayland session support')
# The binary ships stripped and is not rebuilt here, so there is nothing to
# strip and no debug symbols to split out.
options=('!strip' '!debug')
# Upstream publishes a single unversioned "latest" URL; there is no per-release
# download path. The local file name is versioned so makepkg does not reuse a
# stale cached tarball after a version bump. See README.md for the caveat this
# implies for checksum failures between upstream releases.
source=("$pkgname-$pkgver.tar.gz::https://tmog.org/downloads/TMOG-Task-Manager-Linux-x86_64.tar.gz")
sha256sums=('4d319d3d27f513e83801daeec8eb64cb78ddec1f6483bbe90d57d11e607af39d')

# _srcroot echoes the single top-level directory of the extracted tarball.
# Upstream names it TaskManagerOG-<version>-linux-x86_64, but that scheme is not
# contractual, so it is resolved by glob and validated instead of hardcoded.
_srcroot() {
  local _dirs=("$srcdir"/*/)
  if (( ${#_dirs[@]} != 1 )) || [[ ! -d ${_dirs[0]} ]]; then
    error 'expected exactly one top-level directory in the upstream tarball'
    return 1
  fi
  printf '%s' "${_dirs[0]%/}"
}

package() {
  local _root
  _root="$(_srcroot)"

  install -Dm755 "$_root/bin/tmog-task-manager" "$pkgdir/usr/bin/tmog-task-manager"

  install -Dm644 "$_root/share/applications/com.tmog.taskmanager.desktop" \
    -t "$pkgdir/usr/share/applications"
  install -Dm644 "$_root/share/metainfo/com.tmog.taskmanager.metainfo.xml" \
    -t "$pkgdir/usr/share/metainfo"
  install -Dm644 "$_root/share/pixmaps/tmog-task-manager.png" \
    -t "$pkgdir/usr/share/pixmaps"

  local _icon _relative
  while read -r _icon; do
    _relative="${_icon#"$_root/share/"}"
    install -Dm644 "$_icon" "$pkgdir/usr/share/${_relative}"
  done < <(find "$_root/share/icons" -type f -name '*.png')

  # Upstream's LICENSE.txt plus the third-party font and icon notices. The
  # Debian-style share/doc/taskmanagerog/copyright tree is deliberately dropped.
  install -Dm644 "$_root/share/doc/tmog/LICENSE.txt" \
    -t "$pkgdir/usr/share/licenses/$pkgname"
  install -Dm644 \
    "$_root/share/doc/tmog/Fluent-System-Icons-LICENSE.txt" \
    "$_root/share/doc/tmog/Michroma-OFL.txt" \
    "$_root/share/doc/tmog/Selawik-OFL.txt" \
    "$_root/share/doc/tmog/THIRD_PARTY_NOTICES.md" \
    -t "$pkgdir/usr/share/licenses/$pkgname"
}
