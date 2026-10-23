#!/usr/bin/env bash
# Compiles the mod against the local UT2004 (Windows build, run with Wine).
# Usage: tools/build.sh
set -euo pipefail

GAME_DIR="${UT2004_DIR:-$HOME/Juegos/UT2004}"
SYS="$GAME_DIR/System"
PKG="GTAThirdPerson"

if [ ! -f "$SYS/UCC.exe" ]; then
    echo "UCC.exe not found in $SYS — set UT2004_DIR" >&2
    exit 1
fi

# --- register the package so ucc compiles it -------------------------------
if ! grep -q "^EditPackages=$PKG$" "$SYS/UT2004.ini"; then
    if grep -q "^EditPackages=" "$SYS/UT2004.ini"; then
        LINE=$(grep -n "^EditPackages=" "$SYS/UT2004.ini" | tail -1 | cut -d: -f1)
        sed -i "${LINE}a EditPackages=$PKG" "$SYS/UT2004.ini"
    else
        sed -i "s/^\[Editor.EditorEngine\]/[Editor.EditorEngine]\nEditPackages=$PKG/" "$SYS/UT2004.ini"
    fi
    echo "Added EditPackages=$PKG to UT2004.ini"
fi

# --- compile (fresh) --------------------------------------------------------
rm -f "$SYS/$PKG.u"
cd "$SYS"
WINEDEBUG=-all DISPLAY= wine UCC.exe make
