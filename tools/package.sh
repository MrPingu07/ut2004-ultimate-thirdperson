#!/usr/bin/env bash
# Builds the release artifact: a single zip that users extract into their
# UT2004 directory — the files land in System/ and the mutator is ready.
# Usage: tools/package.sh [version]   (after tools/build.sh + tools/install.sh)
set -euo pipefail

VERSION="${1:-1.0}"
NAME="ut2004-ultimate-thirdperson"
PKG="GTAThirdPerson"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
STAGE="$OUT/$NAME-v$VERSION"

GAME_DIR="${UT2004_DIR:-$HOME/Juegos/UT2004}"
SYS="$GAME_DIR/System"

for f in "$PKG.u" "$PKG.int" "$PKG.ucl"; do
    if [ ! -f "$SYS/$f" ]; then
        echo "ERROR: $SYS/$f is missing — run tools/build.sh && tools/install.sh first." >&2
        exit 1
    fi
done

rm -rf "$STAGE"
mkdir -p "$STAGE/System"

# the three install files, plus a readable INSTALL note at the zip root
install -m 0644 "$SYS/$PKG.u"   "$STAGE/System/"
install -m 0644 "$SYS/$PKG.int" "$STAGE/System/"
install -m 0644 "$SYS/$PKG.ucl" "$STAGE/System/"

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

cd "$STAGE"
rm -f "$OUT/$NAME-$VERSION.zip"
python3 - "$OUT/$NAME-$VERSION.zip" <<'PYEOF'
import os, sys, zipfile
zip_path = sys.argv[1]
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
    for base, dirs, files in os.walk("."):
        dirs.sort()
        for f in sorted(files):
            p = os.path.join(base, f)
            z.write(p, os.path.relpath(p, "."))
PYEOF
echo "Built $OUT/$NAME-$VERSION.zip"
python3 -c "import sys, zipfile; [print(' ', m) for m in zipfile.ZipFile(sys.argv[1]).namelist()]" "$OUT/$NAME-$VERSION.zip"
