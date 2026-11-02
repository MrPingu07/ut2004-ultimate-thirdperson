#!/usr/bin/env bash
#
# tools/package.sh - build the release zip from the tracked prebuilt package.
#
# The zip is a normal UT2004 mutator drop-in:
#
#   System/GTAThirdPerson.u    compiled mod package
#   System/GTAThirdPerson.int  mutator metadata (name/description)
#   System/GTAThirdPerson.ucl  cache record for the mutator list
#   INSTALL.txt                install + network-play notes
#
# Extract it into the UT2004 installation folder (the one containing System/).
# No build tools, source or install scripts are shipped.
#
# The binary comes from prebuilt/, which tools/build.sh refreshes. This script
# refuses to package when prebuilt/ is older than the source classes, so a
# release can never silently ship a stale .u.
#
# Usage: tools/package.sh [version] [--allow-stale]
#   version defaults to `git describe --tags` (leading "v" removed).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="GTAThirdPerson"
VERSION=""
ALLOW_STALE=0

for arg in "$@"; do
    case "$arg" in
        --allow-stale) ALLOW_STALE=1 ;;
        *) VERSION="$arg" ;;
    esac
done

if [ -z "$VERSION" ]; then
    VERSION="$(git -C "$ROOT" describe --tags 2>/dev/null || echo 0.0.0)"
fi
VERSION="${VERSION#v}"

PREBUILT="$ROOT/prebuilt"
OUTDIR="$ROOT/dist"
OUT="$OUTDIR/$PKG-$VERSION.zip"

for f in "$PREBUILT/System/$PKG.u" "$PREBUILT/System/$PKG.ucl" "$PREBUILT/System/$PKG.int"; do
    [ -f "$f" ] || { echo "ERROR: missing release artifact: $f" >&2; exit 1; }
done

# --- staleness check ---------------------------------------------------------
SRC_HASH="$(tools/source-hash.sh)"
BUILT_HASH="$(sed -n 's/^source-sha256=//p' "$PREBUILT/BUILD" 2>/dev/null || true)"
if [ "$ALLOW_STALE" -eq 0 ]; then
    if [ -z "$BUILT_HASH" ]; then
        echo "ERROR: $PREBUILT/BUILD is missing or has no source-sha256." >&2
        echo "       Run tools/build.sh (with UT2004 available) and commit prebuilt/." >&2
        exit 1
    fi
    if [ "$SRC_HASH" != "$BUILT_HASH" ]; then
        echo "ERROR: prebuilt package is stale (source changed since the last build)." >&2
        echo "       source:   $SRC_HASH" >&2
        echo "       prebuilt: $BUILT_HASH" >&2
        echo "       Run tools/build.sh and commit prebuilt/, or pass --allow-stale." >&2
        exit 1
    fi
fi

# --- stage -------------------------------------------------------------------
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/System"
cp -f "$PREBUILT/System/$PKG.u" "$STAGE/System/"
cp -f "$PREBUILT/System/$PKG.ucl" "$STAGE/System/"
cp -f "$PREBUILT/System/$PKG.int" "$STAGE/System/"

cat > "$STAGE/INSTALL.txt" <<EOF
UT2004 Ultimate ThirdPerson v$VERSION (GPLv3)
=============================================

A GTA San Andreas style third person camera for Unreal Tournament 2004.

Install
-------
Extract this zip into your UT2004 directory. It adds three files to System/:

  System/GTAThirdPerson.u    compiled mod package
  System/GTAThirdPerson.int  mutator metadata (name/description)
  System/GTAThirdPerson.ucl  cache record for the mutator list

Then pick the mutator "GTA-SA Third Person Camera" in the mutator list of
any Instant Action / network match.

Network play (host requirements!)
---------------------------------
To be joined over a LAN, the machine that HOSTS the match must advertise the
package in System/UT2004.ini, under [Engine.GameEngine]:

  ServerPackages=GTAThirdPerson

UT2004 reads that list ONLY at server startup: add/change it, then restart
the host game. Since v1.5 the mutator appends this line itself on the first
server boot if it is missing (and logs a reminder to restart) — but verify
with:  grep ServerPackages System/UT2004.ini

Every boot logs its package build on both ends: "GTA-TP: package version <N>"
— if two machines disagree on joining, copy the .u AND .ucl from one System/
to the other so the numbers match (asymmetric installs can freeze a joining
client silently).

Keys (applied automatically, rebindable in Settings > Controls)
--------------------------------------------------------------
  Z    first <-> third person toggle
  X    swap camera shoulder
  ALT  aim mode (tighter camera, body locked to crosshair)

Configure in-game: Mutators tab -> select the mutator -> [Configure Mutations].

Uninstall
---------
Delete the three files above; System/GTAThirdPerson.ini holds your settings.

Home / source
-------------
https://github.com/mrpingu07/ut2004-ultimate-thirdperson
Licensed under the GNU General Public License v3 — this program comes with
absolutely no warranty.
EOF

mkdir -p "$OUTDIR"
rm -f "$OUT"
python3 - "$STAGE" "$OUT" <<'PY'
import os, sys, zipfile

stage, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
    for base, _dirs, files in os.walk(stage):
        for name in sorted(files):
            path = os.path.join(base, name)
            zf.write(path, os.path.relpath(path, stage))
PY

echo "==> packaged: $OUT"
python3 - "$OUT" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as zf:
    for info in zf.infolist():
        print(f"    {info.file_size:>8}  {info.filename}")
PY
