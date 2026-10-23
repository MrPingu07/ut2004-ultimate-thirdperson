# ut2k4tp — GTA San Andreas-style third person for UT2004

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
- All values configurable, stored in `System/GTAThirdPerson.ini`.

## Keys (defaults, applied once, rebindable)

| Key | Command | Action |
|---|---|---|
| `Z` | `TP_Toggle` | first <-> third person |
| `X` | `TP_SwapShoulder` | swap camera shoulder (eased) |
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

`System/GTAThirdPerson.ini`, section `[GTAThirdPerson.GTAPlayerController]`
(all also changeable at runtime via `set GTAThirdPerson.GTAPlayerController <name> <value>`
or the exec commands below):

| Setting | Default | Description |
|---|---|---|
| `tp_enable` | 1 | 0 = stock first person |
| `tp_dist` | 110 | camera distance |
| `tp_shoulder` | 20 | camera shoulder (magnitude; the sign or `TP_SwapShoulder` sets the side) |
| `tp_height` | 0 | vertical camera offset (positive up) |
| `tp_turnspeed` | 3600 | body turn speed, rotator units/s (~20°/s) |
| `tp_easetime` | 0.25 | easing time in seconds for shoulder/height/distance |
| `tp_autoadjust` | 1 | use crouch values while crouching |
| `tp_crouch_dist` / `tp_crouch_shoulder` / `tp_crouch_height` | 75 / 18 / 12 | crouch stance |
| `tp_aim_dist` / `tp_aim_shoulder` / `tp_aim_height` | 55 / 14 / 0 | aim mode stance |
| `tp_fire_lock` | 1 | body locked to the crosshair while firing |
| `tp_auto_fp` | 1 | auto first person when there is no room behind |
| `tp_fp_in` / `tp_fp_out` | 20 / 35 | free-space hysteresis for the auto first person |
| `tp_autobind` | 1 | auto-binds may overwrite existing keys on first run |
| `tp_debug` | 0 | logs install details once per game |

Exec commands on the player controller: `TP_Toggle`, `TP_SwapShoulder`,
`TP_AimMode`, `TP_SetDist <f>`, `TP_SetShoulder <f>`, `TP_SetHeight <f>`,
`TP_SetTurnSpeed <f>`, `TP_SetEaseTime <f>`, `TP_SetDefaultBinds`, `TP_Info`
(logs state to the log).

## Install

The repo symlinks its source into the game directory, so the compiler sees it.
On a fresh machine:

```bash
ln -sfn /path/to/ut2k4tp/GTAThirdPerson /path/to/UT2004/GTAThirdPerson
tools/build.sh            # adds EditPackages=GTAThirdPerson + wine UCC.exe make
tools/install.sh          # copies .u/.int/.ucl into System/
tools/install.sh --binds  # additionally binds Z/X/Alt if those keys are free
```

Then pick the mutator **GTA-SA Third Person Camera** in the mutator list of any
Instant Action match (or add
`?mutator=GTAThirdPerson.GTAThirdPersonMutator` to the map URL).

Requires Wine (the game is the Windows build here) — `UCC.exe` compiles the
UnrealScript.

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
- **Aim ray (convergence)**: every camera frame we trace the true crosshair ray
  (camera origin along `vector(Rotation)`, 10000 units, actors enabled) into
  the world — that intersection is `t_aimPoint`. `AdjustAim` returns the
  direction from the real fire origin (pawn's muzzle/eyes) to `t_aimPoint`, so
  shots converge on the crosshair exactly (no parallax from the shoulder
  offset or look pitch); `AdjustAim` also fixes stock third person losing
  shot pitch. Because the ray ends on the screen centre, the stock (custom
  player-chosen) crosshair stays valid and no HUD replacement is needed.

Known limitations: first-person `AdjustAim` scanning (aiming help) is stock
and only active in first person; thrown weapons keep stock yaw behaviour; not
yet tested on dedicated servers with remote clients.

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
