#!/bin/bash
# Publish the sources OBS builds paru from. Run by .github/workflows/update.yml;
# needs network, cargo, zstd, gh (GH_TOKEN) and OBS_TOKEN.
#
# Version: follows the AUR package's pkgver-pkgrel. Its maintainer is paru's
# author, and a pkgrel bump there is how a rebuild against a new libalpm reaches
# users - OBS rebuilds keep the PKGBUILD's pkgrel, so they never would.
#
# A release named v<pkgver>-<pkgrel> is the record that a version was published.
# The script does nothing if the AUR has not moved and that release exists, so
# it is safe to run as often as the schedule likes.

set -euo pipefail

repo=${GITHUB_REPOSITORY:-MX-Linux/paru-mxarch}
obs_trigger='https://api.opensuse.org/trigger/runservice?project=home:mx-packaging&package=paru'
aur_plain='https://aur.archlinux.org/cgit/aur.git/plain'

cd "$(dirname "$0")"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --- Read the AUR package ---------------------------------------------------

curl -fsSL -o "$work/aur-PKGBUILD" "$aur_plain/PKGBUILD?h=paru"
curl -fsSL -o "$work/aur-SRCINFO" "$aur_plain/.SRCINFO?h=paru"

srcinfo() { sed -n "s/^\t$1 = //p" "$work/aur-SRCINFO"; }
aur_ver=$(srcinfo pkgver)
aur_rel=$(srcinfo pkgrel)
aur_sum=$(srcinfo sha256sums)
[[ $aur_ver && $aur_rel && $aur_sum =~ ^[0-9a-f]{64}$ ]] || {
    echo "Could not read pkgver/pkgrel/sha256sums from the AUR .SRCINFO" >&2
    exit 1
}

# PKGBUILD reimplements the AUR's build for an offline OBS build, so a change
# there beyond the version - a new dependency, a new install line - has to be
# ported by hand. Stop rather than publish a package that silently diverges.
strip_version() { grep -vE '^(pkgver|pkgrel|sha256sums)=' "$1"; }
if ! diff -u <(strip_version aur/PKGBUILD) <(strip_version "$work/aur-PKGBUILD"); then
    echo "::error::The AUR PKGBUILD changed beyond its version (diff above)." \
        "Port the change into PKGBUILD, copy the AUR file to aur/PKGBUILD, and push." >&2
    exit 1
fi
cp "$work/aur-PKGBUILD" aur/PKGBUILD

# --- Decide what to publish -------------------------------------------------

ver=$(sed -n 's/^pkgver=//p' PKGBUILD)
rel=$(sed -n 's/^pkgrel=//p' PKGBUILD)
# A decimal pkgrel (2.1) is a packaging-only change on top of AUR pkgrel 2.
if [[ $aur_ver != "$ver" || $aur_rel != "${rel%%.*}" ]]; then
    ver=$aur_ver
    rel=$aur_rel
fi
tag="v$ver-$rel"

if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    echo "$tag is already published."
    exit 0
fi
: "${OBS_TOKEN:?OBS_TOKEN is not set, so OBS could not be told to fetch the release}"
echo "Publishing $tag"

# --- Sources ----------------------------------------------------------------

# The same upstream tarball the AUR builds, verified against its checksum.
curl -fsSL -o "$work/paru-source.tar.gz" \
    "https://github.com/Morganamilo/paru/archive/v$ver.tar.gz"
echo "$aur_sum  $work/paru-source.tar.gz" | sha256sum -c --quiet

tar -xzf "$work/paru-source.tar.gz" -C "$work"
(
    cd "$work/paru-$ver"
    # What the AUR's prepare() does before fetching.
    cargo update alpm alpm-utils
    cargo vendor --locked vendor >/dev/null
    tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 \
        -cf - Cargo.lock vendor
) | zstd -19 -T0 -q -c > "$work/paru-vendor.tar.zst"

sum() { sha256sum "$1" | cut -d' ' -f1; }
awk -v ver="$ver" -v rel="$rel" -v q="'" \
    -v src="$(sum "$work/paru-source.tar.gz")" \
    -v vendor="$(sum "$work/paru-vendor.tar.zst")" '
    /^pkgver=/ { print "pkgver=" ver; next }
    /^pkgrel=/ { print "pkgrel=" rel; next }
    /^sha256sums=\(/ {
        print "sha256sums=(" q src q
        print "            " q vendor q ")"
        skip = 1
    }
    skip { if (/\)$/) skip = 0; next }
    { print }
' PKGBUILD > "$work/PKGBUILD"
cp "$work/PKGBUILD" PKGBUILD

# --- Publish ----------------------------------------------------------------

if [[ ${GITHUB_ACTIONS:-} == true ]]; then
    git config user.name 'github-actions[bot]'
    git config user.email '41898273+github-actions[bot]@users.noreply.github.com'
fi
git add PKGBUILD aur/PKGBUILD
git diff --cached --quiet || git commit -q -m "Update to $ver-$rel"
git push -q

# The OBS _service downloads releases/latest/download/<asset>. gh uploads the
# assets to a draft and publishes it only afterwards, so "latest" never points
# at a release that is missing one.
gh release create "$tag" --repo "$repo" --target "$(git rev-parse HEAD)" \
    --title "paru $ver-$rel" --latest \
    --notes "Sources for home:mx-packaging/paru on OBS, published to [mxarch]." \
    "$work/PKGBUILD" "$work/paru-source.tar.gz" "$work/paru-vendor.tar.zst"

curl -fsS -X POST -H "Authorization: Token $OBS_TOKEN" "$obs_trigger"
echo
