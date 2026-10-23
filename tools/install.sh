#!/usr/bin/env bash
# Installs the mod into the game: copy .u/.int/.ucl, optionally apply key binds.
# Usage: tools/install.sh [--binds]
set -euo pipefail

GAME_DIR="${UT2004_DIR:-$HOME/Juegos/UT2004}"
SYS="$GAME_DIR/System"
PKG="GTAThirdPerson"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# the compiled .u lives in System after build.sh (fresh build if missing)
if [ ! -f "$SYS/$PKG.u" ]; then
    echo "No compiled $PKG.u — running build first..."
    "$ROOT/tools/build.sh"
fi

install -m 0644 "$SYS/$PKG.u"            "$SYS/" 2>/dev/null || true
install -m 0644 "$ROOT/$PKG/$PKG.int"    "$SYS/"
# the generated cache entry lives in System; keep it (fallback descriptions)
if [ -f "$ROOT/$PKG/$PKG.ucl" ] && [ ! -f "$SYS/$PKG.ucl" ]; then
    install -m 0644 "$ROOT/$PKG/$PKG.ucl" "$SYS/"
fi
echo "Installed $PKG into $SYS"

apply_bind() {
    local KEY="$1" CMD="$2"
    # only bind to keys that are currently empty, never clobber existing binds
    if grep -qE "^${KEY}=" "$SYS/User.ini"; then
        CUR=$(grep -E "^${KEY}=" "$SYS/User.ini" | head -1 | cut -d= -f2-)
        if [ -z "$CUR" ]; then
            sed -i "s/^${KEY}=${CUR}/${KEY}=${CMD}/" "$SYS/User.ini"
            echo "Binded [${KEY}] -> ${CMD}"
        else
            echo "Key [${KEY}] already bound to '${CUR}' — not touching it."
            echo "Set it yourself in game: Settings > Controls, or console: bind ${KEY} ${CMD}"
        fi
    fi
}

if [ "${1:-}" = "--binds" ]; then
    cp "$SYS/User.ini" "$SYS/User.ini.bak.$(date +%s)"
    apply_bind Z   TP_Toggle
    apply_bind X   TP_SwapShoulder
    apply_bind ALT TP_AimMode
fi
