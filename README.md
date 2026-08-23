# tmog-bin

AUR packaging for [Task Manager TMOG](https://tmog.org/) — Dave Plummer's native
Qt 6 system monitor and task manager — with automated release tracking.

This repository contains packaging files only. No upstream binary is committed,
mirrored, or attached to a release: the TMOG beta licence does not permit
redistribution. `makepkg` downloads the tarball straight from `tmog.org` on the
user's machine, which is how every other proprietary `-bin` package on the AUR
works.

| | |
| --- | --- |
| AUR package | `tmog-bin` |
| Upstream | <https://tmog.org/> |
| Source | `TMOG-Task-Manager-Linux-x86_64.tar.gz` (official Linux tarball) |
| Architectures | `x86_64` — upstream ships no other Linux build |

## Installing

```bash
git clone https://aur.archlinux.org/tmog-bin.git && cd tmog-bin && makepkg -si
```

Or with an AUR helper:

```bash
paru -S tmog-bin
```

The package installs `/usr/bin/tmog-task-manager` plus its desktop entry,
AppStream metainfo, and hicolor icons. Upstream links against the system Qt 6,
so nothing is vendored: `qt6-base`, `qt6-multimedia`, `qt6-svg` and
`systemd-libs` come from the repositories. Install `qt6-wayland` for a native
Wayland session.

## The unversioned-URL caveat

Upstream publishes exactly one Linux download URL, and it always points at the
newest build:

```
https://tmog.org/downloads/TMOG-Task-Manager-Linux-x86_64.tar.gz
```

There is no per-release path, no version manifest, and no GitHub release to pin
against. That has one consequence worth knowing before you file a bug:

> **When upstream ships a new build, `makepkg` fails with a sha256 mismatch
> until this package catches up.** The URL now serves different bytes than the
> checksum in the `PKGBUILD` describes.

That failure is the checksum doing its job, not a broken package. The
[`update` workflow](.github/workflows/update.yml) polls upstream every six hours
and pushes a corrected `PKGBUILD` to the AUR, so the window is short. Retry
after the package version catches up, or run `updpkgsums` locally if you need it
immediately and accept the unverified download.

Using `sha256sums=('SKIP')` would paper over this, at the cost of every user
silently accepting whatever the URL serves. Real checksums are the right
trade-off.

## How the automation works

[`scripts/update.sh`](scripts/update.sh) fetches the upstream tarball, reads the
version out of its top-level directory name (`TaskManagerOG-<version>-linux-x86_64`),
and compares both the version and the checksum against the `PKGBUILD`:

* **new version** → `pkgver` updated, `pkgrel` reset to `1`
* **same version, different bytes** (an upstream re-roll) → `pkgrel` incremented
* **no change** → nothing is written

It then regenerates `.SRCINFO`. Anything it cannot parse with confidence is a
hard failure rather than a guess, because a wrong `pkgver` on the AUR is worse
than a failed workflow run.

```bash
./scripts/update.sh --check   # report only; exit 10 when an update is pending
./scripts/update.sh           # rewrite PKGBUILD and .SRCINFO
```

The [`update` workflow](.github/workflows/update.yml) runs that script on a
schedule inside an `archlinux:base-devel` container, builds and installs the
result to prove it still works, commits, and then copies `PKGBUILD` and
`.SRCINFO` into a clean clone of the AUR repository. The
[`build` workflow](.github/workflows/build.yml) does the same build on every
push and pull request, and additionally verifies that `.SRCINFO` matches the
`PKGBUILD` and that `namcap` is happy with both the `PKGBUILD` and the built
package.

### Repository setup

The AUR push step is skipped unless a secret is present, so the rest of the
automation works without it.

1. Create an AUR account and add an SSH public key to it.
2. Add the matching private key as the `AUR_SSH_PRIVATE_KEY` repository secret.
3. Push the first version manually — the AUR repository has to exist before the
   workflow can clone it:

   ```bash
   git clone ssh://aur@aur.archlinux.org/tmog-bin.git aur && cp PKGBUILD .SRCINFO aur/ && cd aur && git add -A && git commit -m 'Initial import' && git push
   ```

GitHub disables scheduled workflows in repositories with no activity for 60
days; a manual `workflow_dispatch` run re-enables them.

## Licence

The packaging files in this repository are MIT-licensed (see [LICENSE](LICENSE)).

Task Manager TMOG itself is **proprietary** — © Plummers' Software LLC, released
under a beta licence that permits personal use but forbids redistribution.
Installing this package downloads it from the vendor and agrees to those terms;
the full text lands in `/usr/share/licenses/tmog-bin/LICENSE.txt`.
