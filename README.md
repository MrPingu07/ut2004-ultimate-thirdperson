# ut2k4tp — GTA San Andreas-style third person for UT2004

A mutator for **Unreal Tournament 2004** that adds a GTA-style third person
camera (port of the design of [hl-thirdperson](https://github.com/MrPingu07/hl-thirdperson),
its own Half-Life mod): the mouse orbits the camera, movement is
camera-relative, weapons fire exactly at the crosshair, and the character's
body turns cosmetically towards the movement direction.

## Features

- Orbit camera with adjustable **shoulder / height / distance**, eased when the
  stance changes (`tp_easetime`).
- Camera-relative movement and crosshair-true shots (including **shot pitch**;
  see *How it works* below — stock UT2004 behind view loses pitch).
- Full vertical look (stock UE2 camera pitch, ~90°).
- Cosmetic body turn towards the movement direction with a configurable speed;
  the physics stays stock so swimming, ladders, vehicles are untouched and the
  server always receives your aim angles.
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
| `tp_turnspeed` | 3600 | cosmetic body turn speed, rotator units/s (~20°/s) |
| `tp_easetime` | 0.25 | easing time in seconds for shoulder/height/distance |
| `tp_autoadjust` | 1 | use crouch values while crouching |
| `tp_crouch_dist` / `tp_crouch_shoulder` / `tp_crouch_height` | 75 / 18 / 12 | crouch stance |
| `tp_aim_dist` / `tp_aim_shoulder` / `tp_aim_height` | 55 / 14 / 0 | aim mode stance |
| `tp_fire_lock` | 1 | body locked to the crosshair while firing |
| `tp_auto_fp` | 1 | auto first person when there is no room behind |
| `tp_fp_in` / `tp_fp_out` | 20 / 35 | free-space hysteresis for the auto first person |
| `tp_bone` | Bip01 | root bone used for the cosmetic turn |
| `tp_bonespace` | 1 | `SetBoneRotation` space (1 = global) |
| `tp_autobind` | 1 | auto-binds may overwrite existing keys on first run |
| `tp_debug` | 0 | logs install/probe details once per game |

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

- Stock UE2 orients movement **and weapon aim** along the controller
  `Rotation`, and the stock `Pawn.FaceRotation` makes the pawn follow it every
  tick. So keeping `Rotation` as the mouse-driven camera rotation gives
  camera-relative movement and crosshair-true aiming in every movement state
  (walking, swimming, ladders) for free.
- **AdjustAim override** (copied from stock with one fix): stock UT2004 aim
  falls back to `Pawn.Rotation` in third person, and `FaceRotation` zeroes the
  pawn pitch while walking — shots would lose their vertical aim. We return the
  controller `Rotation` (the camera direction with pitch) instead.
- **Cosmetic body turn**: the root bone (`Pawn.RootBone`, `'Bip01'` for UT2004
  characters) is rotated each frame with `SetBoneRotation` by the yaw difference
  between the camera and the desired body facing (movement direction, or the
  crosshair while firing / in aim mode). This is client-side and visual only —
  the physics pawn keeps the stock rotation.
- **Camera math** happens in `PlayerCalcView`: pivot at the pawn eye position,
  shoulder/height offsets, distance along the view direction, a wall-collision
  trace, and an auto-first-person fallback with hysteresis (`tp_fp_in/out`).

Known limitations: cosmetic turn is client-side (other players see the stock
follow-the-camera mesh, like hl-thirdperson); thrown weapons use the pawn
rotation (yaw only, stock behavior in behind view); not yet tested on dedicated
servers with remote clients.

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
