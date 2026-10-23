# ut2k4tp — GTA San Andreas-style third person for UT2004

Working notes / progress log for this repo. Also carries all environment facts
and decisions from the planning conversation.

## Goal

A **mutator usable on any game type** that recreates the camera of the author's
*hl-thirdperson* Half-Life mod (GTA San Andreas style third person) for Unreal
Tournament 2004:
mouse orbits the camera, movement is camera-relative, weapons fire at the
crosshair, body turns cosmetically towards the movement direction, auto first
person when blocked, crouch auto-adjust, aim mode.

- Multiplayer: deferred (singleplayer / Instant Action first).
- Activation: mutator on any gametype (fallback if the controller swap fails in
  some gametypes: also ship a minimal custom gametype).
- Keys: Z toggle 1st/3rd, X swap shoulder, Alt aim mode — rebindable.

## Environment (verified)

- Game: `/home/jdmr/Juegos/UT2004/` — **Windows build** run with **Wine 11.20
  (Staging)**. `System/UCC.exe` (UnrealScript compiler) and `UnrealEd.exe` exist
  → we can compile in place with `wine UCC.exe make`.
- Configs are local to `System/`: `UT2004.ini`, `User.ini`.
- `SystemARM64/` exists but is empty; no native Linux build.
- Project repo: `/home/jdmr/Proyectos/ut2k4tp` (git, was empty).

## UT2004 internals (verified from stock sources, see Progress)

- UE2 (build 3369). Player camera: `PlayerController.PlayerCalcView()` →
  dynamic `CalcBehindView()`. `bBehindView` toggles 3rd person stock
  (console/`F5`-style "behind view").
- Movement orientation: UE2 orients **movement and weapon aim off the
  controller's `Rotation`** — so controller Rotation = camera rotation gives
  camera-relative movement and crosshair-true shooting for free.
  The pawn facing is what we decouple (stock UE2 rotates the pawn with the
  mouse; we set the pawn's rotation ourselves each tick).
- Controller swap via mutator: `GameInfo.DefaultPlayerClassName` is used by
  `Login()`; a mutator's `InitMutator()` runs before that → set
  `Level.Game.DefaultPlayerClassName = "GTAThirdPerson.GTAPlayerController"`.
  (Verified by decompiled `GameInfo.uc`; see Progress.)

## Feature / setting naming

Mirroring hl-thirdperson's `cl_tp_*` cvars as `tp_*` config vars and execs:
`tp_dist`, `tp_shoulder`, `tp_height`, `tp_turnspeed`, `tp_easetime`,
`tp_aim_shoulder/height/dist`, `tp_crouch_*`, `tp_auto_fp*`, plus execs
`TP_Toggle`, `TP_SwapShoulder`, `TP_AimMode` and adjusters.

## Progress log

### 2026-10-22
- Plan mode: plan agreed (see `/home/jdmr/.opencode/plan/ut2k4tp-gta-thirdperson.md`).
- User approved: full hl-thirdperson feature set, mutator for any gametype,
  singleplayer first, Alt for aim mode. No code yet.
- Implementation started.

## Progress log (implementation)

### 2026-10-22 — engine research (all verified against decompiled stock b3369 sources in `reference/`)
- Stock script sources exported locally with `wine UCC.exe batchexport
  <pkg>.u Class uc Z:\path` for Core/Engine/GamePlay/UnrealGame/XGame/
  XWeapons/XPickups/Onslaught/Vehicles/SkaarjPack/UT2k4Assault(+Full)/BonusPack/
  XInterface. License: Epic code — kept in `reference/` (gitignored), local
  reference only.
- Camera pipeline: `PlayerController.PlayerCalcView()` → for `ViewTarget ==
  Pawn && bBehindView` calls `CalcBehindView(CameraLocation, CameraRotation,
  CameraDist * Pawn.Default.CollisionRadius)`; else first person. xPlayer /
  UnrealPlayer do NOT override any of this (all in Engine.PlayerController).
- Movement input: `state PlayerWalking.PlayerMove` builds accel with
  `GetAxes(Pawn.Rotation,…)` — **movement is pawn-relative** in stock; stock
  `UpdateRotation` then `Pawn.FaceRotation(controller Rotation)` every tick
  (pitch zeroed while walking/falling), so the pawn follows the mouse. Net
  effect: keeping the controller rotation as the camera gives camera-relative
  movement + crosshair aim automatically; the pawn "follows the mouse" which we
  override cosmetically.
- Firing: `WeaponFire.AdjustAim` → `Pawn.AdjustAim` →
  `PlayerController.AdjustAim` which, in `bBehindView`, returns **Pawn.Rotation**
  (yaw only on foot — pitch zeroed). Both hitscan and projectile weapons rely on
  it ⇒ we override `AdjustAim` (copy of stock sources) to return the controller
  `Rotation` (camera direction with pitch). Weapon visuals (`GetViewRotation()`
  = pawn rotation in 3rd person) may differ slightly — same class of limitation
  as hl-thirdperson.
- Full vertical look: `Pawn.LimitPitch` defaults are ~±90° (PitchUpLimit=18000,
  PitchDownLimit=49153), xPawn doesn't override them ⇒ camera pitch is ~free.
- Cosmetic body turn: root bone via `Pawn.RootBone` (default `'Bip01'` on
  xPawn, verified in xPawn.uc defaultproperties). `Actor.SetBoneRotation(name,
  rot, Space, Force)`; Space **0 = local, 1 = global** (UnrealWiki).
- Mutator install point: XGame/DeathMatch only set `PlayerControllerClassName`
  in defaultproperties; `GameInfo.InitGame` spawns mutators
  (`AddMutator(MutatorClass)` at line ~730) before any `Login()`, which resolves
  `PlayerControllerClass` at line ~1141 (defaultprops only, no later assignment
  anywhere in stock) ⇒ overriding `Level.Game.PlayerControllerClassName/Class`
  in the mutator's `PostBeginPlay` is reliable and gametype-agnostic.
- UT2004 `Mutator` has **no InitMutator/ClientConfigKeys** (those are UT3);
  hooks: PostBeginPlay/ModifyPlayer/CheckReplacement(chain-managed by
  `IsRelevant`, individual CheckReplacement just returns its own verdict).
- HUD crosshair is drawn unconditionally (no `bBehindView` skip) ✔.
- Keybinds: User.ini `[Engine.Input]` `Key=Command`; Z=Strafe, X=ShowVoteMenu,
  Alt free on this install. install.sh only binds to empty keys (never clobbers).
  The controller also tries `ConsoleCommand("bind …")` once (tp_bindver).
- UnrealScript gotchas hit during compile: identifiers are case-insensitive
  (`TP_Dist` collided with `var tp_dist` → renamed execs `TP_SetDist`...);
  `rot()` needs simple integer expressions (no casts → use a local rotator and
  set components); string `$` chaining can't put a trailing `$` at a line end.

### 2026-10-22 — first working build
- Package `GTAThirdPerson` compiles clean (`wine UCC.exe make`, build tree
  symlinked into the game dir `UT2004/GTAThirdPerson → repo/GTAThirdPerson`).
- `.ucl` auto-generated by `ucc make` (Exporting Cache); `.int` hand written.
- Server smoke test (`wine UCC.exe server "DM-Antalus?game=XGame.xDeathMatch?mutator=GTAThirdPerson.GTAThirdPersonMutator"`,
  45 s): mutator loads and is listed, map + gametype boot, **no script errors**
  (`Mutators GTAThirdPerson.GTAThirdPersonMutator`, no "accessed None").
  Notable: `ucc server` / `UT2004.exe` URLs get the local player profile
  (Name/Class/Character) appended automatically by the game launcher logic;
  only a real client login exercises the controller spawn.
- `UT2004.exe` windowed run: process started fine; log stayed empty because we
  killed with SIGTERM (logs only flush on clean exit). For playtests, quit
  through the menu instead of killing the process, or use `ucc server` stdout.
- Git commit c949915 ("First build").

### 2026-10-22 — first playtest round (user) + fixes

User report: (1) auto-FP latched forever until death/re-entry, (2) keybinds
didn't work, (3) cosmetic body turn not visible (body fixed to crosshair like
stock), (4) question: which commands change camera panning (answered: the
`TP_Set*` execs exist, README updated).

Debug round 1 flushed from the user's clean exit (`UT2004.log` now readable):
controller possessed fine, camera active with correct params — so the core
camera works; the failures were specific:

- **Auto-FP latch root cause (confirmed)**: when the lock sets
  `bBehindView=false`, the next frame's `PlayerCalcView` routed to `Super`
  (stock first person), so the unlock evaluation in `TP_CalcCam` never ran
  again. Fix: `PlayerCalcView` now stays on our branch while
  `bBehindView || t_fpLock`, and a new `TP_RefreshFP()` re-evaluates the room
  test every frame while locked (unlock when free room > `tp_fp_out`).
- **Keybinds root cause (confirmed)**: UT2004 has **no `bind` console command**
  (that is UT99). Stock `GUIController.SetKeyBind` uses
  `ConsoleCommand("set Input <key> <command>")` and reads bindings with
  `KEYBINDING <key>` (verified in reference/XInterface/GUIController.uc:1248).
  Also `tp_bindver` had already been saved as applied by the failed attempt,
  masking retries. Fix: binds now use `set Input` + `KEYBINDING` check,
  `TP_BINDVERSION` bumped to 2, `TP_SetDefaultBinds` exec re-runable,
  `tp_autobind` config (default True = overwrite Z/X/Alt once, like hl mod
  first-run binds; False = never clobber).
- **Cosmetic body probe added**: semantics of `SetBoneRotation` Space and
  per-mesh root bone names can't be trusted from code alone, so the controller
  now probes at first possess: applies a ~22.5° yaw to candidate bones
  ('Bip01' → 'Bip01 Pelvis' → 'root' → 'head'), Space 1 then 0, reads
  `GetBoneRotation` back next tick, adopts the first pair whose rotation really
  changed, logs the result under `tp_debug` ("cosmetic body probe: bone=…
  space=…"). Note: UE2 name literals reject `-` (compiler), so hyphenated bone
  names can't be literals; string→name coercion doesn't exist in UE2 script.
- UnrealScript details: ternaries on int assignments rejected by the UT2004
  compiler ("Type mismatch in '='"); use if/else.
- Rebuilt, reinstalled, `ucc server` smoke clean. Awaiting retest.
