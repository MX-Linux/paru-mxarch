# paru-mxarch

Builds [paru](https://github.com/Morganamilo/paru) for the MX Linux Arch
repository (`[mxarch]`, <https://arch.mxrepo.com/>) on the Open Build Service,
package `home:mx-packaging/paru`.

## How it stays current

```
AUR paru (pkgver-pkgrel)
   │  daily, .github/workflows/update.yml → update.sh
   ▼
GitHub release v<pkgver>-<pkgrel>: PKGBUILD, paru-source.tar.gz, paru-vendor.tar.zst
   │  OBS runservice trigger (OBS_TOKEN secret)
   ▼
OBS _service downloads releases/latest/download/* → build → [mxarch]
```

- **Version source: the AUR package.** Its maintainer is paru's author, and a
  `pkgrel` bump there is how a rebuild against a new libalpm reaches users.
  OBS rebuilds keep the PKGBUILD's `pkgrel`, so installed systems would never
  see them as upgrades.
- **Why vendored crates:** OBS builds have no network, so the AUR's
  `cargo fetch` cannot run there. `update.sh` vendors the crates on GitHub
  Actions instead, after the same `cargo update alpm alpm-utils` as the AUR.
- **Upstream tarball** is the one the AUR builds, checked against the AUR's
  sha256sum before it is republished.

## When the workflow fails with "The AUR PKGBUILD changed beyond its version"

`PKGBUILD` reimplements the AUR's build for an offline build, so changes there
(new dependency, new installed file) are ported by hand:

1. Apply the change from the printed diff to `PKGBUILD`.
2. Copy the current AUR file to `aur/PKGBUILD`.
3. Push. The push runs the workflow, which publishes the new version.

## Packaging-only change

Edit `PKGBUILD`, bump `pkgrel` to a decimal (`2` → `2.1`) so pacman sees an
upgrade, and push. When the AUR moves to the next `pkgrel` it supersedes it.

## Setup (once)

- OBS package `home:mx-packaging/paru` with `_service` from this repository,
  built only in the `Arch` repository.
- `osc token --create --operation runservice home:mx-packaging paru`, stored as
  the `OBS_TOKEN` Actions secret.
