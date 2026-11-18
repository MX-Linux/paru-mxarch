# Maintainer: Adrian <adrian@mxlinux.org>
# Contributor: Morgan <morganamilo@archlinux.org>

# paru for the [mxarch] repository, built on the Open Build Service
# (home:mx-packaging/paru). Adapted from the AUR package, whose PKGBUILD is kept
# in PKGBUILD.aur for comparison.
#
# OBS build VMs have no network, so the AUR's prepare() - cargo fetch - cannot
# run there. update.sh vendors the locked crates on GitHub Actions and
# publishes the results as release assets, which the OBS _service downloads:
#   paru-source.tar.gz   upstream's release tarball, checked against the AUR's
#                        sha256sum
#   paru-vendor.tar.zst  upstream Cargo.lock and the crates it locks in vendor/
#
# update.sh rewrites pkgver, pkgrel and sha256sums - do not edit them by hand,
# except to publish a packaging-only change: bump pkgrel to a decimal (2 -> 2.1)
# and push. See README.md.

pkgname=paru
pkgver=2.2.1
pkgrel=1
pkgdesc='Feature packed AUR helper'
url='https://github.com/Morganamilo/paru'
arch=('x86_64')
license=('GPL-3.0-or-later')
depends=('git>=2.40' 'pacman>=7.1' 'libalpm.so' 'libssl.so' 'libcrypto.so')
# rust rather than the AUR's cargo: both rust and rustup provide cargo, and
# OBS refuses to choose ("have choice for cargo").
makedepends=('rust' 'gettext')
optdepends=('bat: colored pkgbuild printing'
            'devtools: build in chroot and downloading pkgbuilds')
backup=('etc/paru.conf')
source=('paru-source.tar.gz'
        'paru-vendor.tar.zst')
noextract=('paru-vendor.tar.zst')
sha256sums=('caa4a3ff8702e65a3c8124bfb153e7ea6c29f9a888e7a6381db1b341e78b819b'
            '77645b3e2fe7e99b8da6d718b3dae17a8822ce3f1b7a8ff270edf6a6ee175e4a')

prepare() {
    cd "$pkgname-$pkgver"

    # Replaces upstream's Cargo.lock with the one the crates were vendored from.
    bsdtar -xf "$srcdir/paru-vendor.tar.zst"

    mkdir -p .cargo
    cat > .cargo/config.toml <<'EOF'
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
EOF
}

build() {
    cd "$pkgname-$pkgver"

    export CARGO_HOME="$srcdir/cargo-home"
    cargo build --frozen --release --target-dir target
    ./scripts/mkmo locale/
}

package() {
    cd "$pkgname-$pkgver"

    install -Dm755 target/release/paru "$pkgdir/usr/bin/paru"
    install -Dm644 paru.conf "$pkgdir/etc/paru.conf"

    install -Dm644 man/paru.8 "$pkgdir/usr/share/man/man8/paru.8"
    install -Dm644 man/paru.conf.5 "$pkgdir/usr/share/man/man5/paru.conf.5"

    install -Dm644 completions/bash "$pkgdir/usr/share/bash-completion/completions/paru.bash"
    install -Dm644 completions/fish "$pkgdir/usr/share/fish/vendor_completions.d/paru.fish"
    install -Dm644 completions/zsh "$pkgdir/usr/share/zsh/site-functions/_paru"

    install -d "$pkgdir/usr/share"
    cp -r locale "$pkgdir/usr/share/"
}
