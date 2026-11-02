#!/usr/bin/env bash
# Compiles the mod against the local UT2004 (Windows build, run with Wine).
# Usage: tools/build.sh
set -euo pipefail

GAME_DIR="${UT2004_DIR:-$HOME/Juegos/UT2004}"
SYS="$GAME_DIR/System"
PKG="GTAThirdPerson"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -f "$SYS/UCC.exe" ]; then
    echo "UCC.exe not found in $SYS — set UT2004_DIR" >&2
    exit 1
fi

# --- register the package so ucc compiles it -------------------------------
if ! grep -q "^EditPackages=$PKG" "$SYS/UT2004.ini"; then
    if grep -q "^EditPackages=" "$SYS/UT2004.ini"; then
        LINE=$(grep -n "^EditPackages=" "$SYS/UT2004.ini" | tail -1 | cut -d: -f1)
        sed -i "${LINE}a EditPackages=$PKG" "$SYS/UT2004.ini"
    else
        sed -i "s/^\[Editor.EditorEngine\]/[Editor.EditorEngine]\nEditPackages=$PKG/" "$SYS/UT2004.ini"
    fi
    echo "Added EditPackages=$PKG to UT2004.ini"
fi

# --- advertise it to joining clients ---------------------------------------
# UT2004 only reads ServerPackages at server startup; the client needs the
# package to resolve GTAPlayerController on join, otherwise "Connection Lost".
if ! grep -q "^ServerPackages=$PKG" "$SYS/UT2004.ini"; then
    sed -i "/^ServerPackages=AssaultBP/a ServerPackages=$PKG" "$SYS/UT2004.ini"
    echo "Added ServerPackages=$PKG to UT2004.ini — restart the server to take effect"
fi

# --- compile (fresh) --------------------------------------------------------
rm -f "$SYS/$PKG.u"
cd "$SYS"
WINEDEBUG=-all DISPLAY= wine UCC.exe make

# --- refresh tracked release artifacts ---------------------------------------
# The release workflow cannot run ucc (it needs the retail game files), so the
# compiled package is kept in prebuilt/ and packaged from there. Commit it
# whenever the source changes; tools/package.sh refuses to package stale ones.
mkdir -p "$ROOT/prebuilt/System"
cp -f "$SYS/$PKG.u" "$ROOT/prebuilt/System/$PKG.u"
cp -f "$ROOT/$PKG/$PKG.int" "$ROOT/prebuilt/System/$PKG.int"
if [ -f "$ROOT/$PKG/$PKG.ucl" ]; then
    cp -f "$ROOT/$PKG/$PKG.ucl" "$ROOT/prebuilt/System/$PKG.ucl"
fi
SRC_HASH="$("$ROOT/tools/source-hash.sh")"
GIT_COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
{
    echo "source-sha256=$SRC_HASH"
    echo "commit=$GIT_COMMIT"
    echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$ROOT/prebuilt/BUILD"
echo "== release artifacts refreshed in $ROOT/prebuilt"
