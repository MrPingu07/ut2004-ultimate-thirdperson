# UT2004 Ultimate ThirdPerson — GTA San Andreas-style third person for UT2004

A mutator for **Unreal Tournament 2004** that adds a GTA-style third person
camera (port of the design of [hl-thirdperson](https://github.com/MrPingu07/hl-thirdperson),
its own Half-Life mod): the mouse orbits the camera, movement is
camera-relative, weapons fire exactly at the crosshair, and the character's
body turns cosmetically towards the movement direction.

## Features

- Orbit camera with adjustable **shoulder / height / distance**, eased when the
  stance changes (`tp_easetime`).
- **Free character facing (GTA-style)**: the body is decoupled from the mouse —
  it turns towards the movement direction with a configurable speed (`tp_turnspeed`),
  locks to the crosshair while firing or in aim mode, and stays put while you
  orbit the camera standing still. The walking input is re-based on the camera
  axes (pitch-free) so you always move where the camera points, no matter where
  the body looks.
- **Crosshair-true shots, no parallax**: shots leave the pawn's eyes but are
  aimed at the point the camera ray hits (traced up to 10000 units), so the
  shoulder offset and looking straight up/down never displace the impact. The
  stock (custom player-chosen) crosshair keeps working unchanged — the
  convergence point always projects to the screen centre.
- Full vertical look (stock UE2 camera pitch, ~90°).
- **Automatic first person** when there is no room behind the character (walking
  backwards into a wall), back to third person when there is (with hysteresis).
- **Crouch auto-adjust**: tighter camera values while crouching.
- **Aim mode** (`tpaim`-style): tighter camera and body locked to the crosshair;
  the body also locks to the crosshair while firing (`tp_fire_lock`).
- Works as a **mutator on any gametype** (DM, CTF, DOM, Assault...). Bots are
  untouched. No pawn replacement, no weapon replacement.
- All values configurable — in-game via the Mutators tab **[Configure Mutations]**
  page, or console commands / `System/GTAThirdPerson.ini`.

## Keys (defaults, applied once, rebindable)

| Key | Command | Action |
|---|---|---|
| `Z` | `TP_Toggle` | first <-> third person |
| `X` | `TP_SwapShoulder` | swap camera shoulder (eased swing through the centre) |
| `Alt` | `TP_AimMode` | toggle aim mode |

On first run the mod applies these itself using the stock UT2004 mechanism
(`set Input <key> <command>` — UT2004 has **no** `bind` console command). With
`tp_autobind=True` (default) it **overwrites** whatever `Z`, `X` and `Alt` were
bound to (this install: `Z=Strafe` legacy key and `X=ShowVoteMenu`); set
`tp_autobind=False` to only bind keys that are free. Restore at any time from
**Settings > Controls** or the console:

```
set Input Z TP_Toggle          ; re-apply
set Input Z Strafe             ; restore the old bind
set Input X ShowVoteMenu
```

If binds ever stop working, run the console command `TP_SetDefaultBinds`.

## Settings

Tuning is stored in `System/GTAThirdPerson.ini` and can be changed three ways:

1. **In-game GUI** — Mutators tab → select the mutator → `[Configure Mutations]`
   (grouped sliders/checkboxes; applies on the next map load).
2. **Console commands** (recommended — they clamp and save, and apply at once).
3. A text editor.

The 13 simple values (camera/stance/toggle set) live in **two synced places**:
the mutator section `[GTAThirdPerson.GTAThirdPersonMutator]` is what the GUI
edits, and `[GTAThirdPerson.GTAPlayerController]` is what the console commands
and the in-game behaviour use. The mutator pushes its section into the
controller at every map start; the console commands sync back into the mutator
section. For hand edits, change the **mutator** section (or use the GUI) —
manual edits of these 13 keys in the controller section are overwritten at
map start.

### Configure Mutators page (in-game GUI)

Menu → Mutators tab → tick/select *GTAThirdPersonMutator* → `[Configure Mutations]`
— exactly ten options, distinguished by name (no hover needed):

`Regular Dist` · `Regular Shoulder` · `Regular Height` · `Aim Dist` ·
`Aim Shoulder` · `Aim Height` · `Crouch Dist` · `Crouch Shoulder` ·
`Crouch Height` · `AutoFP` (checkbox)

Values are saved on **OK** and apply on the **next map load** (same as console
commands). Deliberately not on that page — console/ini only:

- mod on/off (`bEnabled`, mutator ini section)
- body turn speed (`TP_SetTurnSpeed`), pose easing time (`TP_SetEaseTime`)
- crouch-stance toggle (`tp_autoadjust`)
- keybinds and the auto-FP hysteresis (`tp_fp_in` / `tp_fp_out`)

### Player keys (applied once on first run, rebindable)

| Key | Command | Action |
|---|---|---|
| `Z` | `TP_Toggle` | first <-> third person |
| `X` | `TP_SwapShoulder` | swap camera shoulder (eased swing through the centre) |
| `Alt` | `TP_AimMode` | toggle aim mode |

On first run the mod applies these itself using the stock UT2004 mechanism
(`set Input <key> <command>` — UT2004 has **no** `bind` console command). With
`tp_autobind=True` (default) it **overwrites** whatever `Z`, `X` and `Alt` were
bound to (this install: `Z=Strafe` legacy key and `X=ShowVoteMenu`); set
`tp_autobind=False` to only bind keys that are free. Restore at any time from
**Settings > Controls** or the console:

```
set Input Z TP_Toggle          ; re-apply
set Input Z Strafe             ; restore the old bind
set Input X ShowVoteMenu
```

If binds ever stop working, run the console command `TP_SetDefaultBinds`.

### Console commands (persist to the ini)

| Command | Default | Range | Description |
|---|---|---|---|
| `TP_SetDist <D>` | 110 | 10–3000 | camera distance behind the pawn |
| `TP_SetShoulder <S>` | 30 | 0–800 | sideways offset, units ≈ UU; side = `X` (or ini sign) |
| `TP_SetHeight <H>` | 0 | −200–400 | vertical camera offset (positive up) |
| `TP_SetTurnSpeed <T>` | 1373 | 1–10000 | body turn speed in **°/s** (1373 ≈ 3.8 turns/s); always the shortest arc |
| `TP_SetEaseTime <E>` | 0.25 | ≥ 0 | pose easing time for shoulder/height/distance switches |
| `TP_SetCrouchDist <D>` / `TP_SetCrouchShoulder <S>` / `TP_SetCrouchHeight <H>` | 75 / 18 / 12 | like `Dist/Shoulder/Height` | crouch stance — used while crouched if `tp_autoadjust` is on |
| `TP_SetAimDist <D>` / `TP_SetAimShoulder <S>` / `TP_SetAimHeight <H>` | 55 / 14 / 0 | like `Dist/Shoulder/Height` | aim-mode (`Alt`) stance overrides |
| `TP_Toggle` / `TP_SwapShoulder` / `TP_AimMode` | — | — | your already-playing view toggles |
| `TP_SetDefaultBinds` | — | — | re-apply the `Z` / `X` / `Alt` binds |
| `TP_Info` | — | — | dump the current camera/body state to `UT2004.log` |

The body turn speed used to be configured in raw engine rotator units
(65536 = one turn); configs saved before round 7 are converted automatically
to the degrees scale on first run.

### ini-only settings

(`tp_dist`, `tp_shoulder`, `tp_height`, `tp_turnspeed`, `tp_easetime`,
`tp_autoadjust`, `tp_auto_fp` and the aim/crouch stances are editable in the
GUI page and/or console commands above; also in the **mutator** ini section.)

| Setting | Default | Description |
|---|---|---|
| `tp_enable` | 1 | 0 = stock first person everywhere |
| `tp_fire_lock` | 1 | body locked to the crosshair while firing (0 = only aim mode locks) |
| `tp_fp_in` / `tp_fp_out` | 20 / 35 | free-space hysteresis for the auto first person |
| `tp_autobind` | 1 | first-run binds may overwrite existing keys |
| `tp_debug` | 0 | one-line info logs (possess/camera/ migrations) |
| `tp_bindver`, `tp_turnver`, `tp_cfgver` | internal | migration markers — leave alone |

## Install

The repo symlinks its source into the game directory, so the compiler sees it.

> ### ⚠️ REQUIRED to host a network match — read this before joining tests
>
> The **host's** `System/UT2004.ini` must advertise the mutator package, or
> joining clients **hard-freeze mid-load** (UE2 dies at the class handshake:
> no error, no disconnect message, the client log just stops before
> `Precaching:` — see the round 14–20 saga in CONTEXT.md):
>
> ```ini
> [Engine.GameEngine]
> ...
> ServerPackages=GTAThirdPerson
> ```
>
> UT2004 reads this list **only at server startup**, so a freshly added line
> (or the automatic registration below) takes effect **after the next server
> start**. Verify on the host:
>
> ```
> grep ServerPackages System/UT2004.ini
> ```
>
> From **round 21** the mod self-registers this line on its first server
> boot: if `ServerPackages=GTAThirdPerson` is missing, the mutator appends it
> under `[Engine.GameEngine]` and logs
> `GTA-TP: host UT2004.ini had no ServerPackages=GTAThirdPerson — appended ...`.
> Older installs (and every machine you copy `.u` files to by hand) still
> need the edit, prefixed by a game restart.
>
> This exact line was the root cause of months of "joining client freeze"
> reports across two machines: the round-14 fly RPC deferral never mattered
> — frozen clients never received a single RPC; they died before any
> client-side mod code ran. Also keep `.u`/`.ucl` copies **byte-identical on
> both machines** (see Multiplayer) — each boot logs
> `GTA-TP: package version <N>` on both ends; the two numbers must match.

Two options:

### One-step install (release zip)

Download the release zip (`ut2004-ultimate-thirdperson-vX.Y.zip`) from the
[releases page](https://github.com/mrpingu07/ut2004-ultimate-thirdperson/releases)
and **extract it into your UT2004 directory** (the zip contains `System/` with
the package, so the files land where they belong). Then pick the mutator
**GTA-SA Third Person Camera** in any Instant Action / network match.

To uninstall, delete `System/GTAThirdPerson.u`, `.int` and `.ucl` (and
`System/GTAThirdPerson.ini` to remove your settings).

### From source

On a fresh machine:

```bash
ln -sfn /path/to/ut2004-ultimate-thirdperson/GTAThirdPerson /path/to/UT2004/GTAThirdPerson
tools/build.sh            # adds EditPackages=GTAThirdPerson + wine UCC.exe make
tools/install.sh          # copies .u/.int/.ucl into System/
tools/install.sh --binds  # additionally binds Z/X/Alt if those keys are free
```

The release zip is built from an installed game with
`tools/package.sh <version>` after `build.sh` + `install.sh`.

Requires Wine (the game is the Windows build here) — `UCC.exe` compiles the
UnrealScript.

## Multiplayer

Primary use is instant action, but the mod is written so a listen-server works;
tested/verified behaviour and known limits:

- The mutator must be installed (`.u`/`.int`/`.ucl`) on **both** the server and every
  joining client. Joining clients download/get the package through UT2004's normal
  mechanism, **or just copy these three files next to their `System/`**.
- **Keep both installs byte-identical.** Downloading the package is not free of
  surprises (the 333networks/openspy re-release may silently not re-fetch a
  package it already has locally, even when the server's copy changed):
  an `.u` from a different build on one machine is an **asymmetric class
  layout**, which can hard-freeze the joining client mid-load with no error
  string in the log. After every rebuild, copy `.u` + `.ucl` to **both**
  machines before testing. Verify with the round-20 version stamp: each boot
  logs `GTA-TP: package version <N>` next to the player seed line —
  `grep "package version" UT2004.log` on both sides must print the same number.
- **Server config (mandatory for hosting):** add `ServerPackages=GTAThirdPerson`
  to the host's `System/UT2004.ini` **under `[Engine.GameEngine]`** and restart
  the game — the list is read only at server startup. Since round 21 the mutator
  appends the line itself on first server boot if it is missing. Without the
  line the symptom is NOT "Connection Lost": the joining client
  silently hard-freezes mid-load before precache (proven with swapped host
  roles on 2026-10-25 — the round 14–20 freeze was this exact config gap
  on the host that never got it).
- **Keep `.u`/`.ucl` byte-identical on host and clients.** Copies that drift
  are asymmetric class layouts and can freeze a joining client just as
  quietly. Each boot seals its log with `GTA-TP: package version <N>` on
  both ends — compare the numbers once per machine per session.
- The third-person view is pushed to joining clients with the stock
  `ClientSetBehindView` replication path, so remote players get the orbit
  camera, keybinds and their **own local tuning** (each client's ini applies).
- **Aim accuracy:** remote clients stream their crosshair convergence point
  to the server (one small unreliable vector per frame while in third
  person), so their shots converge on the crosshair just like the host's. If
  a client stops streaming (first person, auto-FP lock, death/hover wait),
  its shots fall back to the stock aim direction until it returns to third
  person. The point is trusted at the same level stock already trusts each
  client's view rotation. Keys and tuning remain per-machine as described.
- The body-facing fix is server-authoritative (pawn rotation replicates to
  everyone), so other players see the body turning toward your movement.
- **Camera config sync:** the server's `tp_dist`/`tp_shoulder`/`tp_height`/
  `tp_auto_fp` are replicated to joining clients, so remote players use the
  host's camera tuning instead of their own ini defaults (or compiled
  defaults). Server-side console changes to these values reach clients through
  the same replication path.

## How it works

All logic lives in `GTAThirdPerson.GTAPlayerController`, a subclass of
`XGame.xPlayer` that the mutator installs via
`Level.Game.PlayerControllerClassName` (gametypes only set that in
defaultproperties, and mutators load during `InitGame`, before `Login()`
resolves the class — verified against the stock sources).

- **Camera** math happens in `PlayerCalcView`: pivot at the pawn eye position,
  shoulder/height offsets, distance along the view direction, a wall-collision
  trace, and an auto-first-person fallback with hysteresis (`tp_fp_in/out`).
  The controller `Rotation` stays the mouse-driven camera rotation.
- **Free body facing**: after the stock `UpdateRotation` faces the pawn at the
  camera, we rotate the pawn back towards the body target — the movement
  direction while running (GTA-style), the crosshair while firing or in aim
  mode, wherever it last was while idle — always with `tp_turnspeed` and
  `Pawn.FaceRotation` (the pawn's real physical rotation, so animations match
  and other players/bots see the correct facing). Only walking/falling/swimming
  physics get this; ladders, spider mode and vehicles keep stock behaviour.
  The stock `bFreeCamera` flag is set (on foot only) so stock UpdateRotation
  skips its own pawn-facing and does not fight us; inside vehicles it is left
  FALSE so turrets (ONSWeaponPawn seats) keep their stock mouse-driven swivel.
  Because the pawn no longer faces the camera, `state PlayerWalking.PlayerMove`
  is copied with its acceleration basis switched from `Pawn.Rotation` to the
  controller `Rotation` (with the **pitch stripped** — otherwise looking 90°
  down makes the forward axis vertical and forward/back movement collapses;
  this is how the stock camera-pitch ~90° is kept for looking, not moving).
  The other movement states (swimming, climbing, spider) already use the
  controller axes in stock code. The double-click dodge bookkeeping is
  mirrored too (`PlayerInput` is private to the stock controller class).
- **Vehicle reticles are muted** (round 6): stock Onslaught draws its own
  second screen-centred reticle in ONS vehicles/turrets once the cannon aligns
  with the camera (`bCorrectAim`). Per instance we zero the stock
  `CrosshairX/CrosshairY` offsets, shrinking that draw to a 1px dot hidden
  under the player crosshair; the player's own custom crosshair is the only
  visible one everywhere. The mounted gun follow of round 5 (per-tick
  `bFreeCamera`) is unaffected.
- **Body turn speed is measured in degrees/second** (`tp_turnspeed`, default
  1373 deg/s ~ 3.8 turns/s — a quick GTA-style whip; the config value converts
  once to the new unit, since round<=6 stored raw engine rotator units). It
  always eases over the shortest arc, so high values never spin the long way.
- **Aim ray (convergence)**: every camera frame we trace the true crosshair ray
  (camera origin along `vector(Rotation)`, 10000 units, actors enabled) into
  the world — that intersection is `t_aimPoint`. `AdjustAim` returns the
  direction from the real fire origin (pawn's muzzle/eyes) to `t_aimPoint`, so
  shots converge on the crosshair exactly (no parallax from the shoulder
  offset or look pitch); `AdjustAim` also fixes stock third person losing
  shot pitch. Because the ray ends on the screen centre, the stock (custom
  player-chosen) crosshair stays valid and no HUD replacement is needed.

Known limitations: first-person `AdjustAim` scanning (aiming help) is stock
and only active in first person; thrown weapons keep stock yaw behaviour.

## Repo layout

```
GTAThirdPerson/Classes/   UnrealScript sources
GTAThirdPerson.int/.ucl   localized name + mutator menu entry
reference/                exported stock UT2004 b3369 script sources (gitignored)
tools/build.sh            register package + wine UCC make (also regenerates .ucl)
tools/install.sh          copy to System/ [--binds applies key bindings]
CONTEXT.md                working notes / progress log
```

See `CONTEXT.md` for the full verified-engine-notes and progress history.

## License

Released under the **GNU General Public License version 3** — see
[LICENSE](LICENSE) in the repository root and the short headers in the
`.uc` sources. This program comes with absolutely no warranty.
