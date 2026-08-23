#!/usr/bin/env bash
#
# Sync PKGBUILD and .SRCINFO with the current upstream TMOG Linux tarball.
#
# Upstream publishes the version at /version.txt and serves the tarball from a
# mutable "latest" path, cache-keyed by a ?v=<version>-free query the website
# appends at click time. This script reads version.txt, downloads the tarball
# through the same cache key a user would, and cross-checks the two. Two
# outcomes are treated differently:
#
#   * version changed          -> pkgver=<new>, pkgrel=1
#   * version same, bytes new  -> pkgver kept, pkgrel incremented (upstream
#                                 re-rolled the same version)
#
# Anything the script cannot parse with confidence is a hard failure: pushing a
# wrong pkgver to the AUR is worse than a red workflow run.

set -euo pipefail

readonly VERSION_URL='https://tmog.org/version.txt'
# %s is the upstream version. The query is a CDN cache key, not a version pin:
# every value returns the current bytes. Using it means a version bump misses
# the edge cache and reaches the origin instead of a stale object.
readonly ARCHIVE_URL_FORMAT='https://tmog.org/downloads/TMOG-Task-Manager-Linux-x86_64.tar.gz?v=%s-free'

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
readonly PKGBUILD="$REPO_ROOT/PKGBUILD"

check_only=false
work_dir=''

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

cleanup() {
  [[ -n $work_dir && -d $work_dir ]] && rm -rf -- "$work_dir"
}

usage() {
  cat <<'USAGE'
usage: scripts/update.sh [--check]

  --check   Report whether an update is available without editing any file.
            Exits 0 when up to date, 10 when an update is pending.
USAGE
}

# emit_output appends a key=value pair to $GITHUB_OUTPUT when running under
# GitHub Actions, and is a no-op elsewhere.
emit_output() {
  [[ -n ${GITHUB_OUTPUT:-} ]] || return 0
  printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"
}

# read_pkgbuild_var echoes the value of a top-level PKGBUILD variable.
read_pkgbuild_var() {
  local name="$1"
  # Unset variables are tolerated here on purpose: sourcing the PKGBUILD
  # outside makepkg leaves makepkg's own variables (CARCH and friends)
  # undefined, and the source URL interpolates CARCH.
  ( set -eo pipefail
    local CARCH; CARCH="$(uname -m)"
    # shellcheck source=/dev/null
    source "$PKGBUILD"
    local -n value="$name"
    printf '%s' "${value[0]-${value}}" )
}

parse_args() {
  while (($# > 0)); do
    case "$1" in
      --check) check_only=true ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; die "unknown argument: $1" ;;
    esac
    shift
  done
}

# fetch_upstream_version echoes the version upstream currently advertises.
fetch_upstream_version() {
  local version
  version="$(curl --fail --silent --show-error --location --retry 3 --retry-delay 5 \
    --header 'Cache-Control: no-cache' "$VERSION_URL")" \
    || die "could not read $VERSION_URL"

  version="${version//[$'\r\n\t ']/}"
  # The same shape the website itself requires before it trusts the value.
  [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "unexpected content at $VERSION_URL: '$version'"

  printf '%s' "$version"
}

# fetch_upstream_archive downloads the tarball for $1 and echoes its sha256.
fetch_upstream_archive() {
  local version="$1"
  local archive="$work_dir/upstream.tar.gz" url
  printf -v url "$ARCHIVE_URL_FORMAT" "$version"

  curl --fail --silent --show-error --location --retry 3 --retry-delay 5 \
    --output "$archive" "$url" \
    || die "download failed: $url"

  local top_level
  top_level="$(bsdtar -tf "$archive" | head -n 1 | cut -d/ -f1)" \
    || die 'could not list the upstream tarball'
  [[ -n $top_level ]] || die 'upstream tarball has no top-level directory'

  local tarball_version
  tarball_version="$(grep -oE '[0-9]+(\.[0-9]+)+' <<<"$top_level" | head -n 1)" \
    || true
  [[ -n $tarball_version ]] \
    || die "could not parse a version from the top-level directory '$top_level'"

  # A staged website can advertise a release before its artifacts land. Refuse
  # to label a tarball with a version it does not contain; the next scheduled
  # run picks it up once the deploy settles.
  [[ $tarball_version == "$version" ]] \
    || die "version.txt reports $version but the tarball contains $tarball_version; upstream deploy looks incomplete"

  sha256sum "$archive" | cut -d' ' -f1
}

# rewrite_pkgbuild updates pkgver, pkgrel and sha256sums in place.
rewrite_pkgbuild() {
  local version="$1" pkgrel="$2" checksum="$3"

  sed -i \
    -e "s/^pkgver=.*/pkgver=$version/" \
    -e "s/^pkgrel=.*/pkgrel=$pkgrel/" \
    -e "s/^sha256sums=.*/sha256sums=('$checksum')/" \
    "$PKGBUILD"

  # Guard against a silently ineffective sed.
  [[ "$(read_pkgbuild_var pkgver)" == "$version" ]] || die 'pkgver rewrite failed'
  [[ "$(read_pkgbuild_var pkgrel)" == "$pkgrel" ]] || die 'pkgrel rewrite failed'
  [[ "$(read_pkgbuild_var sha256sums)" == "$checksum" ]] \
    || die 'sha256sums rewrite failed'
}

regenerate_srcinfo() {
  ((EUID != 0)) || die 'makepkg refuses to run as root; run this as a normal user'
  command -v makepkg >/dev/null || die 'makepkg not found; run this on Arch Linux'

  ( cd "$REPO_ROOT" && makepkg --printsrcinfo >.SRCINFO ) \
    || die 'makepkg --printsrcinfo failed'
}

main() {
  parse_args "$@"

  [[ -f $PKGBUILD ]] || die "no PKGBUILD at $PKGBUILD"

  work_dir="$(mktemp -d)"
  trap cleanup EXIT

  local current_version current_pkgrel current_checksum
  current_version="$(read_pkgbuild_var pkgver)"
  current_pkgrel="$(read_pkgbuild_var pkgrel)"
  current_checksum="$(read_pkgbuild_var sha256sums)"

  local version checksum
  version="$(fetch_upstream_version)"
  checksum="$(fetch_upstream_archive "$version")"

  info "packaged: $current_version-$current_pkgrel ($current_checksum)"
  info "upstream: $version ($checksum)"

  if [[ $version == "$current_version" && $checksum == "$current_checksum" ]]; then
    info 'already up to date'
    emit_output changed false
    emit_output version "$current_version"
    emit_output pkgrel "$current_pkgrel"
    return 0
  fi

  local pkgrel reason
  if [[ $version != "$current_version" ]]; then
    pkgrel=1
    reason="new upstream version $current_version -> $version"
  else
    pkgrel=$((current_pkgrel + 1))
    reason="upstream re-rolled $version, bumping pkgrel to $pkgrel"
  fi
  info "$reason"

  if [[ $check_only == true ]]; then
    emit_output changed true
    emit_output version "$version"
    emit_output pkgrel "$pkgrel"
    emit_output reason "$reason"
    return 10
  fi

  rewrite_pkgbuild "$version" "$pkgrel" "$checksum"
  regenerate_srcinfo
  info "updated PKGBUILD and .SRCINFO to $version-$pkgrel"

  emit_output changed true
  emit_output version "$version"
  emit_output pkgrel "$pkgrel"
  emit_output reason "$reason"
}

main "$@"
