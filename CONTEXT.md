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

### 2026-10-22 — playtest round 2 (user) + facing/reticle rewrite

User report: (1) body still ALWAYS faces the crosshair in both aim modes (the
bone cosmetic turn never showed), (2) reticle accuracy degrades with shoulder
offset and vertical look — bullets converge off the reticle because they
actually originate at the pawn's eyes, not at the screen centre.

- **Bone cosmetic turn abandoned**. The `SetBoneRotation`/`GetBoneRotation`
  probe was self-referential: setting a rotation in space S and reading it
  back in space S "passes" for ANY (bone, space) pair with no evidence the
  *rendered mesh* rotates (log: `probe: bone='Bip01' space=1` while the user
  still saw a fixed body). Stock code never applies per-frame bone rotations
  to player pawns either — no ground truth to copy.
- **Physical pawn facing instead**: our `UpdateRotation` override runs
  `Super` (camera/input/shake/pitch limit + stock pawn facing) and then calls
  `Pawn.FaceRotation(bodyRot, dt)` with the GTA body target — absolute yaw,
  eased by `tp_turnspeed`: movement direction while running, crosshair while
  firing/`TP_AimMode`, last value while idle (camera orbits the body). Gated
  to PHYS_Walking/Falling/Swimming; ladder/spider/vehicle/death/FP keep stock
  facing. The pawn rotation is physical & replicated, so anims, bots and other
  players all agree (better than the bone hack would ever be).
- **Movement re-based on camera axes**: stock `PlayerWalking.PlayerMove`
  builds acceleration from `GetAxes(Pawn.Rotation)` — with the pawn facing the
  movement direction that input becomes self-referential, so the state is
  copied verbatim with the basis switched to `GetAxes(Rotation)`. Verified the
  other states (PlayerSwimming 5050, PlayerClimbing 4619, PlayerSpidering) are
  ALREADY camera-relative in stock code — no copies needed. ProcessMove (dodge
  handling, UnrealPlayer) and NotifyLanded resolve through class-major state
  lookup because the same state name is reused (this is exactly the pattern
  UnrealPlayer itself uses).
- **PlayerInput is `private`** to Engine.PlayerController →
  `CheckForDoubleClickMove` unreachable from a subclass. The input-edge
  bookkeeping (bEdge*/bWas* XOR of aBaseY/aStrafe, PlayerInput.uc:54-61) and
  CheckForDoubleClickMove (275-340) are mirrored in the controller with own
  state vars (`TP_DblClickMove`), `DoubleClickTime` read from the PlayerInput
  defaults. Dodging/double-jump still work.
- **Convergence aim (parallax fix)**: each camera frame, `TP_CalcCam` traces
  the true crosshair ray (origin on the view line — anchor and pulled-in
  camera sit on the same line, Pawn.Trace so the pawn is not self-hit —
  direction = camera direction, range 10000 like stock AdjustAim) and stores
  it in `t_aimPoint`. The `AdjustAim` copy now returns
  `rotator(t_aimPoint - projStart)` while in third person: shots start at the
  real muzzle/eyes but AIM AT the reticle point, so shoulder offset or
  looking straight up/down can never displace the impact. Verified beam
  weapons (LinkFire 53/166/183...) also route through AdjustAim. First person
  keeps the full stock AdjustAim (scanning/aiming help).
- **Black & white dot reticle**: new class `GTAThirdPerson.GTAInteraction
  extends Engine.Interaction` — Interactions get PostRender + a per-viewport
  registry (`Player.InteractionMaster.AddInteraction(id, Player)`,
  InteractionMaster.uc) and natives `Canvas.WorldToScreen`. It draws a white
  core with a black outline (two tiles of Engine.WhiteSquareTexture, the same
  solid-box pattern Engine/Canvas.uc:161 uses) at `WorldToScreen(t_aimPoint)`,
  with a behind-camera check (dot(ViewDir) like HudBase.DrawTargeting:821+).
  Added once per viewport (scans `Player.LocalInteractions` — interactions
  survive map changes). The stock centre crosshair is hidden while the
  reticle is up by setting `myHUD.bCrosshairShow=false` and restoring the
  user value on disable — identical to stock screenshot mode
  (PlayerController.uc:727-739).
- Compile notes: `Outer` is an intrinsic Object property (don't name locals
  that); `ERenderStyle` is scoped inside Actor and not reachable from an
  Interaction (Object subtree) — Canvas.Style defaults to 1 (STY_Normal)
  anyway, so no assignment needed.
- Rebuilt (0 errors), reinstalled, `ucc server` smoke clean (mutator listed,
  no script errors). Awaiting playtest round 3.

### 2026-10-22 — playtest round 3 (user) + pitch fix + crosshair restore + body instrumentation

User report: (1) aim much better now — shots land on the reticle, BUT (2) the
black & white dot never moves from the screen centre: it projects there by
CONSTRUCTION (the convergence ray goes THROUGH the screen centre), so the user
asks for their own custom HUD crosshair back instead; (3) body STILL does not
rotate, not even a little; (4) NEW BUG: looking exactly 90° up/down kills
forward/back movement (only A/D works).

Fixes/changes:

- **Overlay removed, stock crosshair restored**: the dot was pointless (the
  convergence ray always ends on the screen centre), so `GTAInteraction` was
  deleted, crosshair suppression (myHUD.bCrosshairShow) is gone entirely, and
  the user's own HUD crosshair texture shows again. The CONVERGENCE aim stays
  (TP_CalcAimPoint + AdjustAim branch — user confirms the accuracy improved).
  Design note: an off-centre reticle would have to project the MUZZLE
  trajectory rather than the camera ray — a different design; the user
  accepted the centre-crosshair solution.
- **90° look movement bug (confirmed)**: our camera-based walking accel used
  the FULL camera rotation; at pitch ±16384 the X axis ≈ (0,0,±1), so
  `NewAccel.Z = 0` removed everything and W/S went dead (stock never sees this
  because it uses the pitch-zeroed pawn rotation). Fix: basis now built from
  `CamYaw = Rotation` with Pitch=0 (yaw-only). Swimming state keeps stock
  behaviour (unchanged).
- **Body rotation still not rendering — instrumented debug** (tp_debug):
  `UpdateRotation` logs once that the override runs; `TP_FaceBody` logs once
  per second: gate fields (enable/behind/fpLock/alive/veh/physics) plus
  camYaw / pawnYaw / bodyYaw / target / valid. When we get the user's log we
  can see whether (a) the override never runs, (b) a gate kills it, or
  (c) FaceRotation applies but something reverts the pawn yaw.
  Verified against stock: no pawn class (UnrealPawn/xPawn) overrides
  FaceRotation or SetRotation; xPawn sets bRotateToDesired=False (1280, 2378);
  Pawn.FaceRotation (1283) just zeroes pitch & SetRotation; the only
  FaceRotation call site in the controller chain is inside UpdateRotation,
  which we override.
- Rebuilt (0 errors), reinstalled, `ucc server` smoke clean.

### 2026-10-22 — playtest round 4 (user) + smoking guns from the debug log

User report: crosshair custom + accurate (GOOD), body rotation STILL invisible.

Debug log analysis (the user's clean-exit UT2004.log, 68 throttled samples):

- `our UpdateRotation override is running` every frame ✔ (the override chain
  works — also proven earlier by the pitch movement bug being a symptom of
  our PlayerMove copy running).
- `body gate ...` samples: all gate fields fine (phys=1 walking, alive, no
  vehicle, behind=True), the body target/easing code runs (bodyYaw progresses
  from -4096 toward the movement target every line) — **AND THE EASING RATE
  WAS ~69 rotator units per second ≈ `Step=1` per tick — the user's
  `System/GTAThirdPerson.ini` has `tp_turnspeed=1.0`!!** Root cause of the
  invisible turn from round 2 on: an early `TP_SetTurnSpeed 0` (issued while
  the cosmetic bone approach was being debugged) was clamped by
  `FMax(1.0, T)` and SavedConfig'd as `1` — 1 unit/tick ≈ 1°/s, nothing to
  see. The user never re-raised it.
- **AND** `pawnYaw == camYaw` EXACTLY on every sample, while bodyYaw lags
  thousands of units behind — so a second mechanism also re-faces the pawn
  to the camera every tick beyond tp_turnspeed.

Fixes this round:
1. **Config migration**: new `tp_turnver=2` (same pattern as tp_bindver):
   on first possess, a saved `tp_turnspeed` below the version is reset to
   3600 and SavedConfig'd (logged under tp_debug). Edit: PostBeginPlay.
2. **bFreeCamera decoupling**: while the GTA camera is up,
   `bFreeCamera = tp_enable && bBehindView && !t_fpLock` is set. Stock
   `UpdateRotation` then SKIPS `Pawn.FaceRotation(camera)`
   (Engine/PlayerController.uc:4406: `!bFreeCamera || !bBehindView`), so the
   pawn facing is controlled solely by our TP_FaceBody → FaceRotation(body).
   bFreeCamera returns to its config value when in FP. SET IN TP_SetCamParams
   (already called every camera frame, so it self-restores on stance change).
3. **Sharper diagnostics**: body debug now logs at 0.25 s and includes
   `freedCam=` and `pawnYawPre=`; a second throttled line `body apply
   ... pawnYawAfter=` logs immediately after FaceRotation. If the pawn yaw
   STILL snaps back to camYaw with bFreeCamera enabled, the reverter is
   native (physicsRotation per the Engine.dll symbol
   `?physicsRotation@APawn@@UEAAXMVFVector@@`) and we take the native path
   (pawn.bRotateToDesired + pawn.DesiredRotation = body target) or accept the
   bFreeCamera's stock consequence.

Rebuilt (0 errors), reinstalled, `ucc server` smoke clean.

### 2026-10-22 — round 5 analysis: vehicle bFreeCamera leak fixed; on-foot rotation verified applied

Round-5 report: (a) body still "doesn't rotate" for the user; (b) NEW: mounted
guns/turrets (ONSArtillery turret) don't follow the mouse, while camera orbit +
1st/3rd toggle in vehicles work.

Debug log findings:

- On foot, round-4 build works mechanically: `pawnYawPre` eases toward the
  movement target at ~3800 units/s (tp_turnspeed=3600) and STICKS across ticks
  (`body apply eased=X pawnYawAfter=X`, next line's pawnYawPre=X). The saved
  tp_turnspeed=1 was also confirmed auto-reset by the tp_turnver migration
  ("tp_turnspeed reset to 3600" in the log). The pawn's Rotation genuinely
  decouples from the camera.
- `strings` checks: NO "FaceRotation"/"RootBone" strings in XGame.dll nor
  Onslaught.dll (Engine.dll's known rejection was the marker) => no
  XGame/Ons native mesh-yaw machinery; rendered pawn yaw comes from pawn
  Rotation like the stock game. On-foot visual question now rests on the user
  watching the artillery during most of the test (ONS-IslandHop possess log
  alternates xPawn0/ONSArtillery0 a lot).

Vehicle bug root cause (proven in the log + stock source):

- The veh segments logged `freedCam=True` while driving: our bFreeCamera was
  set only in TP_SetCamParams, which never runs in vehicles
  (PlayerCalcView routes them to stock), so the last on-foot value leaked and
  stayed TRUE inside the vehicle.
- With bFreeCamera=TRUE, stock UpdateRotation skips
  `Pawn.FaceRotation(camera)` (Engine/PlayerController.uc line ~4406,
  gate `(!bFreeCamera || !bBehindView)`). Turret seats are
  `ONSWeaponPawn extends Vehicle` — their mounted gun swivels exactly via that
  pawn FaceRotation call — so it froze. ONSVehicle's own FaceRotation is an
  EMPTY stub (Engine/Vehicle.uc:1413), and our TP_FaceBody skips vehicles: no
  other rotator touched the seat.

Fix:

1. bFreeCamera is now maintained EVERY tick in PlayerTick with the condition
   `tp_enable && Pawn && Vehicle(Pawn)==None && bBehindView && !t_fpLock`
   (vehicles get FALSE => stock turret swivel restored; single source of
   truth; TP_SetCamParams no longer writes it).
2. Body debug log no longer prints for vehicles (veh=True noise gone).

Rebuilt (0 errors), reinstalled, `ucc server` smoke clean.

### 2026-10-23 — round 6: stock ONS vehicle reticle muted; body-spin render probe added

Round-6 report: (a) vehicle/turret gun follows the mouse again (bFreeCamera
fix confirmed); caveat: the stock ONS aiming reticle drawn by the vehicle only
appears AFTER the cannon finished aligning — user wants it GONE entirely,
keeping only the player's custom crosshair. (b) body rotation STILL invisible
even across FP toggles; aim mode / auto-FP / shoulder swap all work.

Vehicle reticle root cause: NOT ours. Stock Onslaught draws a second
screen-centred reticle itself: ONSVehicle.DrawHUD (~line 1539, gate
`Weapons[ActiveWeapon].bShowAimCrosshair && bCorrectAim`) and
ONSWeaponPawn.DrawHUD (~line 753, gate `Gun.bCorrectAim`), texture
'tankBarrelAligned', appearing exactly when bCorrectAim becomes true = after
the cannon aligns. Kill paths analysed:

- bCorrectAim: `var const bool` set natively AND gates firing logic (ONSVehicle
  line 296 / ONSWeapon.uc:360) — cannot zero.
- CrosshairTexture=None: draw call reads `CrosshairTexture.USize` in script →
  AccessedNone crash — cannot.
- Off-screen offsets: the drawn rect is symmetric around screen centre
  ([C-X, C+X] x [C-Y, C+Y]) — any large offset draws a screen-covering tile —
  cannot.
=> Mute via `CrosshairX=0, CrosshairY=0` per instance: collapse to a 1x1 pixel
at screen centre, hidden behind the player crosshair. Done in
TP_MuteVehReticles() (per-instance, for ONSVehicle + ONSWeaponPawn, throttled
1s scan in PlayerTick so late-spawned vehicles are covered).

Body rotation: round-5/6 logs keep proving the ACTOR rotation eases away from
the camera (this session: pawnYaw ~107° off camYaw through a running segment)
yet the user sees zero rotation at all. Native-string checks found no
XGame/ONS mesh-yaw machinery. Decisive render probe added: `TP_SpinTest` exec
(toggle) forces a continuous ~88 deg/s spin (16000 units/s) on foot regardless
of movement. If the model visibly spins -> the pipeline works and it is a
behaviour/expectation/timing question. If the model does NOT spin while the
camera stays still -> the rendered yaw does not come from Pawn.Rotation for
the local player pawn and the next layer is the render path.

Rebuilt (0 errors, 0 warnings), reinstalled, smoke clean.

### 2026-10-23 — round 7: turn speed confirmed working by user — polish pass

Round-7 report: **strafing visibly rotates the body** — the render pipeline was
fine all along; it was slow. User-tested default: TP_SetTurnSpeed 250000
rotator units/s (~1373 deg/s, ~3.8 rev/s) = the "visually attractive" GTA whip.
No render-path work needed; TP_SpinTest probe answered its question.

Polish implemented:

1. **tp_turnspeed reinterpreted as DEGREES per second** (user: "remove the
   zeros" — raw 65536-unit rotator numbers like 250000 are unwieldy):
   - Compiled default 1373 deg/s (= the user-tested 250000 units/s).
   - Versioned migration tp_turnver=3 converts any legacy units value once:
     tp_turnspeed /= 182.044444 (1 deg = 65536/360 units), clamped [1, 2000].
     Fresh installs skip it: defaultproperties now carry tp_turnver=3.
   - TP_FaceBody Step = tp_turnspeed * dt * 182.044444 (the FMax(1.0) unit-era
     floor removed); TP_SetTurnSpeed clamps [1, 10000] deg/s.
2. **Debug bloat removed** (the mystery is solved, nothing left to observe):
   - TP_SpinTest exec + t_spinTest + forced-spin branch (gone).
   - 0.25 s "body enable/pawnYawPre/..." dump and 1 s "body apply" dump, with
     t_lastBodyLog/t_lastApplyLog throttle vars (gone).
   - one-shot "our UpdateRotation override is running" line (gone).
   - Kept (tp_debug-gated, one-liners): Possess info, camera-active info,
     room-recovered info, migration logs; TP_Info unchanged.

Rebuilt (0 errors, 0 warnings), reinstalled, `ucc server` smoke clean. User's
ini verified pre-state: tp_turnspeed=250000 + tp_turnver=2 → migrates to
1373.3 deg/s on next possession.

### 2026-10-23 — round 8: shoulder default 30, stance setters, README docs overhaul

Round-8 report (play-testing): the tuned shoulder is 30 (default was 20).
Docs did not reflect the real command set; crouch/aim stance values had no
in-game setters.

1. **tp_shoulder default 20 -> 30** (compiled default), migrated once for
   existing configs by bumping TP_CFGVERSION (= tp_turnver marker) to 4.
   Renamed the const from TP_TURNVERSION to TP_CFGVERSION since it now covers
   general defaults migration (3 = turnspeed units->deg, 4 = shoulder 30);
   the ini var tp_turnver must keep its name (already stored).
2. **Six new exec commands** (each clamps + SaveConfig, same ranges as the
   parent stance): TP_SetCrouchDist / TP_SetCrouchShoulder /
   TP_SetCrouchHeight (75/18/12) and TP_SetAimDist / TP_SetAimShoulder /
   TP_SetAimHeight (55/14/0).
3. **README rewritten**: keys table kept; new "Console commands" table with
   all defaults/ranges (incl. degrees/s note and legacy-units migration
   note); ini-only settings table (tp_enable, tp_autoadjust, tp_fire_lock,
   tp_auto_fp, tp_fp_in/out, tp_autobind, tp_debug, migration markers).
   Stale 20/3600-units values removed.

Rebuilt (0 errors, 0 warnings), reinstalled, smoke clean.

### 2026-10-23 — round 9: in-game [Configure Mutators] page wired up

Request: expose the "less complicated" tunings in the Mutators tab page —
shoulder/height/dist, aim + crouch stances, AutoFP toggle (master on/off came
along naturally).

**Research (exported GUI2K4 sources, System/MutExport/ — `ucc batchexport PKG
class uc DIR`; signature: 4th arg is the output dir, NOT a class mask):**

- `MutatorConfigMenu.Initialize()`: builds ONE PlayInfo from all chosen
  mutators (`xUtil.GetMutatorClasses`), then per mutator shows only settings
  with `ClassFrom == MutClasses[i]` (plus non-Mutator classes trailing the
  bFoundMutatorSettings flag — irrelevant for us). Gates: `MutatorHasProps()`
  requires the mutator itself to contribute ≥1 setting (ClassFrom == its own
  class). No `Sort` call on this page — fill order preserved.
- `AddRule` parses Text extras `"dec;min:max"` — decimals count then range
  (float when the min contains a "." → moFloatEdit). The OK button calls
  native `PlayInfo.SaveSettings()` which writes each setting into **its**
  `ClassFrom`'s config ini section (no mirrored save glue needed).
- `PlayInfo.AddClass()` wants `class<Info>` — PlayerController IS NOT an
  Info subclass → `AddClass(controller)` impossible ("Cast will always
  fail"). Mutator-mirrored config vars are therefore the stock idiom.

**Implementation (GTAThirdPersonMutator, now config(GTAThirdPerson)):**

- Master `bEnabled` config bool (False = don't install the controller →
  stock first person). Doubles as the mutator's own PlayInfo setting,
  satisfying MutatorHasProps/bFoundMutatorSettings.
- 13 mirrored config vars (same names as the controller's): tp_dist,
  tp_shoulder, tp_height, tp_turnspeed, tp_easetime, tp_autoadjust,
  tp_auto_fp, tp_aim_dist/shoulder/height, tp_crouch_dist/shoulder/height
  + `tp_cfgver` one-time-init marker.
- `FillPlayInfo` adds 14 settings (bEnabled Check + 12 Text/Check with
  ranges matching the exec clamps; turn-speed UI max 4000 °/s). The 3rd arg
  becomes the label (verified: native copies it into DisplayName);
  `GetDescriptionText` overridden on the mutator for property descriptions.
- One-time `TP_InitMirror` (tp_cfgver<1): copies the controller's class
  defaults (= its own ini values at load) into the mirror, replicating the
  controller's turn/shoulder migration math when tp_turnver<4 so user tuning
  is not lost (e.g. saved 250000 units → converts; shoulder bumped to 30).
- Per map start `TP_PushToController` (only when installing): assigns the
  controller class defaults (stock idiom `class'X'.default.Y = v`, see
  Engine/PlayerController.uc ~1674) + `class'...'.static.StaticSaveConfig()`;
  sets `tp_turnver=4` so the controller's migration branch never re-converts
  the already-converted pushed values.
- Controller: `TP_SyncMirror()` (same idiom reversed) called from all 11
  value execs, so console changes are mirrored back and can't be reverted by
  the push at the next map. Controller's GetDescriptionText removed (the
  mutator's is what PlayInfo consults now).

**Headless verification + UCC quirk:** `ucc <pkg>.<commandlet>` loads script
commandlets, but native PlayInfo.AddSetting CRASHES in the bare UCC
environment ("Failed to find function None in <Mutator> None") — even for the
stock MutLightweightVehicles. Workaround: temporary probe in PostBeginPlay
(real server context) building the same PlayInfo + stock `PI.Dump()` —
verified 14 settings, correct ClassFrom/groups/ranges/render types,
DisplayName = passed description, values round-trip (mutator ini ↔ controller
defaults), `tp_cfgver=1` written, migration markers intact. Probe +
`TPConfigDumpCommandlet.uc` deleted afterwards (bloat rule).

**Also noted:** user ini carried user's tuning (dist 150, height 30,
shoulder 0, turn 1000 °/s, aim 50/30/0) — snapshot kept it (no reset to
compiled defaults); `tp_debug=True` still on. `ucc batchexport` needs
`<pkg> <exporter> <ext> <dir>`; bare `ucc <cmdlet name>` without package
prefix fails ("not found"), IOW use `ucc GTAThirdPerson.<Cmdlet>` to run a
mod commandlet.

Rebuilt (0 errors, 0 warnings), reinstalled, `ucc server` smoke clean.

**Deferred/user-test needed:** actual GUI page render (labels/values) and
OK-and-persist flow can't be verified headlessly — mutators tab → select
GTAThirdPersonMutator → [Configure Mutations]; confirm the fields appear,
change e.g. Shoulder, press OK, restart the map, then check
`[GTAThirdPerson.GTAThirdPersonMutator]` in GTAThirdPerson.ini and the
in-game behaviour.

### 2026-10-23 — round 10: Configure page trimmed to 10 named options; eased shoulder swap

User feedback on round 9: the page should list ONLY the ten simple values,
with names that distinguish the three stances (previously "Dist/Shoulder/
Height" repeated per group and only hovered descriptions told them apart).
Also: shoulder switching (X key) was the only camera change without easing.

1. **FillPlayInfo trimmed + renamed.** Exactly: Regular Dist/Shoulder/Height,
   Aim Dist/Shoulder/Height, Crouch Dist/Shoulder/Height, AutoFP (Check).
   Labels carry the stance prefix so no hover is needed; all in one group
   (default.RulesGroup). Removed from the page: bEnabled master toggle,
   tp_turnspeed, tp_easetime, tp_autoadjust — those stay console/ini-only
   (they are still mirrored + synced, the page is just a view).
   MutatorHasProps still satisfied (all ten are ClassFrom == mutator).
   GetDescriptionText updated to match.

2. **Eased shoulder swap.** New runtime var t_shoulderEased (signed): eased
   in TP_SetCamParams with the same TP_FEase/tp_easetime path as
   dist/height, target = t_shoulderSign * t_camShoulder. TP_CalcCam AND
   TP_RefreshFP anchors now use t_shoulderEased * RightVec instead of
   instant t_shoulderSign * t_camShoulder, so X swings the camera smoothly
   through the centre. Possess seeds t_shoulderEased = tp_shoulder.
   TP_SwapShoulder is unchanged (still just flips the sign; the ease makes
   the swing).

Headless re-verify via the temporary PostBeginPlay probe (removed again):
exactly 10 settings with the new DisplayName labels (the stock native
orders the PlayInfo array itself — observed AutoFP/Aim/Crouch/Regular
ordering, not fill order; groups are identical anyway).

Rebuilt (0 errors, 0 warnings), reinstalled, `ucc server` smoke clean (0
criticals). README: Configure table replaced by the ten names + "not on the
page" list; X key description says eased swing.

### 2026-10-23 — round 11: multiplayer audit before 1.0 (2 fixes, nothing "trivial")

"Mod ready for 1.0 — MP was never tested" — audited replication behaviour
against Engine/PlayerController.uc sources; NOT trivial. Findings:

1. **Remote clients stayed first person.** bBehindView is a plain var, NOT
   replicated; stock reaches clients only through the ClientSetBehindView
   RPC (replication block: reliable if Role==ROLE_Authority). We never sent
   it. FIX: Possess now calls
   `ClientSetBehindView(true)` when tp_enable && NetMode!=NM_Standalone &&
   Vehicle(Pawn)==None (vehicle possession manages its own camera, and
   stock's vehicle branch Pawn.SaveConfig()s a junk ini entry. Host-local /
   standalone don't need the RPC — but the RPC is simply not executed for
   those (Role==authority), and the direct assignment covers them).
2. **Remote players' shots would fly to the world origin.** t_aimPoint is
   computed in PlayerCalcView = client-side only; on a server it stayed
   (0,0,0) while AdjustAim believed TP_ShootConvergence()==true (bBehindView
   is server-side set in Possess). FIX: new transient t_aimValid set right
   after TP_CalcAimPoint in TP_CalcCam, reset at Possess, added to
   TP_ShootConvergence(). Remote players (and any server) fall back to the
   stock aim branch. Listen-host keeps full convergence (same machine).
3. **Dedicated servers polluted their UT2004.ini Input section**: simulated
   PostBeginPlay ran TP_SetDefaultBinds server-side; gated with
   `Level.NetMode != NM_DedicatedServer`.

Other checks done (no change needed): client-side tuning comes from each
client's own ini section (config vars not replicated, per-player tuning
works); pawn body facing is server-authoritative (Rotation replicates);
binds/keybind version run client-side (simulated); PlayerTick reticle mute
runs client-side on the client's local ONS instances so vehicle HUD works;
no replicated custom vars added anywhere (children inherit xPlayer
replication); remote TP execs run locally+replicate (standard UE2 exec
semantics), mirrored ini writes happen on both machines as intended.

**Not verifiable headlessly:** an actual two-machine test. Server-side
smokes (dedicated `ucc server`) clean: 0 errors/warnings, 0 criticals.
User to MP-test: listen server + a second PC joining, check (a) remote
player enters third person on join, (b) orbit/keys work, (c) shots behave
(stock-style convergence for remote, crosshair-true for host).

README gained a Multiplayer section (requirements + the remote-aim limit).

### 2026-10-23 — v1.0 published

Repo: https://github.com/MrPingu07/ut2004-ultimate-thirdperson (public, gh CLI,
pushed master + tag v1.0, release v1.0 with single-file zip).

Packaging: tools/package.sh [ver] stages INSTALL.txt + System/GTAThirdPerson
.{u,int,ucl} and zips to dist/ (gitignored; no `zip` binary on this box — the
script uses python3 zipfile). Users extract the zip into the UT2004 root.
GPLv3: LICENSE + short GPL headers in both .uc sources; README renamed to
"UT2004 Ultimate ThirdPerson", one-step zip install section + license section;
.gitignore gained dist/. Multiplayer section already in README; MP playtest +
the pending publish questions (license visibility) resolved by user's call:
public + GPLv3.

### 2026-10-23 — round 12: underwater rendering followed the pawn's eyes (found + fixed)

Report: with the mod in third person, the underwater blue fog "doesn't update
unless I manually go in and out of third person", and its state "is determined
in relation to the player's eyes" instead of the camera.

Root cause (Engine/PlayerController.uc):

- PlayerController.ViewFlash (~1109) IS already camera-based in third person:
  `ViewVolume = Level.GetPhysicsVolume(CalcViewLocation)` when bBehindView,
  `Pawn.HeadVolume` (head/eyes) in first person; the blend per-step
  (UpdateFlashComponent, ScreenFlashScaling) drives the on-screen water fog.
- CalcViewLocation is filled by the stock PlayerCalcView wrapper via
  CacheCalcView() — every one of its branches calls CacheCalcView before
  returning (PlayerCalcView is also wrapped in a per-frame dedupe).
- OUR override's third-person branch returned early WITHOUT CacheCalcView, so
  CalcViewLocation held the last first-person eye position; the water fog kept
  following the eyes and only refreshed when a fresh first-person calc ran
  (manual toggle) — exactly the report.

Fix: call CacheCalcView(ViewActor, CameraLocation, CameraRotation) on all
three direct returns in our PlayerCalcView (third-person, auto-FP unlock
re-entry into third person, auto-FP locked first person). With latched FP the
camera == eyes anyway, so behaviour is unchanged there, and everything is fed.

Rebuilt (0 errors/warnings), reinstalled, `ucc server` smoke clean (0
criticals).

User test recipe: third person at a water edge; step in until the CAMERA
crosses the surface (not the eyes) — blue fog should appear; stand so the
eyes are submerged but the camera is above — no fog, no manual toggle needed;
diving down with the camera under — fog appears immediately. Also verify the
converse: exit the water and the fog clears with the camera, not after the
eyes leave. First-person behaviour is unchanged (eyes == camera there, and
stock uses HeadVolume correctly).

### 2026-10-23 — round 13: crosshair-true aim for remote clients (round-11 fallback removed)

Report: remote players' shots don't converge on their crosshair (v1.0/v1.0.1
intentionally fell back to the stock aim branch server-side — the camera with
the true ray only exists on the client).

Implementation (GTAPlayerController):

- New `ServerTPAimPoint(vector Aim)` + unreliable replication entry
  `unreliable if (Role < ROLE_Authority) ServerTPAimPoint;` (child classes may
  add statements; xPlayer rules stay). TP_CalcAimPoint — which only runs on
  the machine that renders the view, and only in the applied third-person
  branch — now stamps freshness (`t_aimRecv = Level.TimeSeconds`) and, when
  the controller is NOT authoritative (remote client), streams its point.
- Server fills t_aimPoint/t_aimValid/t_aimRecv from the stream. Host and
  standalone keep stamping locally every camera frame, so the same freshness
  gate covers both source types.
- TP_ShootConvergence gained `(Level.TimeSeconds - t_aimRecv < 0.2)`: a client
  that stops streaming (FP toggle, auto-FP lock, death) silently falls back
  to the stock aim branch — the round-11 fail-safe, tightened by clock instead
  of trusting stale bBehindView (which is not replicated).
- Possess keeps t_aimValid=false; stream presence or its own camera calc makes
  it true within a frame. Possess needn't stamp t_aimRecv (validity is the
  gate until data exists).

Trust model: same level as stock (clients already send view rotation per move
and their hitscan aim angles). Bandwidth: ~small vector per frame while in
third person, unreliable — comparable to stock ServerMove chatter.

Can't verify headlessly: real two-machine convergence. All failure paths
degrade to the v1.0.1 (stock-aim) behaviour by design.

README MP section's "Aim difference" limitation replaced by the streaming
description.

Rebuilt (0 errors/warnings), reinstalled, smoke clean (0 criticals).

### 2026-10-25 — round 14: joining client freeze fixed + ServerPackages requirement

Report: a client connecting from LAN to a listen server with the mutator enabled
freezes (effectively crashes) at level load.

Diagnosis (client log /home/jdmr/Proyectos/clientlog.txt, then UT2004.log):

- The freeze was native: `xD3D9Helper::Init` during the joining client's
  fullscreen↔windowed D3D device creation. Zero script errors, zero `GTA-TP:`
  lines before the hang.
- Root cause: `bBehindView` is not replicated, so the mod tells remote clients
  to go third person via the stock `ClientSetBehindView(true)` reliable RPC.
  That RPC was sent from `Possess()` / the first `PlayerTick()` — while the
  client was still toggling fullscreen and creating the D3D device — and on
  that client's Wine + Intel HD Graphics 4000 setup it hung device creation.
- Fix: deferred the `ClientSetBehindView(true)` RPC to 3 seconds after
  `Possess()` (past level load / D3D init), via a `t_clientActivate` stamp and
  a one-shot gate in `PlayerTick()` retried every frame until sent. `Possess()`
  still sets `bBehindView = tp_enable` directly (covers local host / standalone).
- Rebuilt: 0 errors / 0 warnings. Client now gets past `xD3D9Helper::Init`
  and joins; server log confirms `GTA-TP: deferred ClientSetBehindView(true) sent`
  after level load, then the client enters third person.

Separate discovery — client never received the package:

- The client joined, loaded the level, then got "Connection Lost" because the
  server never advertised `GTAThirdPerson` in `ServerPackages`
  (`UT2004.ini`, `[Engine.Engine]`), so UT2004 never offered the client the
  `GTAThirdPerson.u` download. Without the package the client can't resolve
  `GTAThirdPerson.GTAPlayerController` and is rejected.
- Fix: added `ServerPackages=GTAThirdPerson` to the server ini and restarted
  the server. `tools/build.sh` now registers both `EditPackages` and
  `ServerPackages` automatically (server restart still required for
  `ServerPackages` to take effect). Clients auto-download the package on
  connect after that.

README MP section updated with the `ServerPackages` requirement; "not yet tested
on dedicated servers with remote clients" limitation replaced by this finding.

Client joined successfully with the mutator enabled after both fixes.

### 2026-10-25 — round 15: server→client camera config sync

Report: joining clients used their own (or default) `tp_dist`/`tp_shoulder`/`tp_height`
instead of the host's values — e.g. a client with no tuned ini started with
shoulder=0 instead of the host's 30.

Root cause: camera settings are `config` vars, which UT2004 does **not**
replicate. Each machine loads them from its own `GTAThirdPerson.ini`. The
mutator's `TP_PushToController()` only sets class defaults on the machine it
runs on (server or client), never across the network.

Fix: added replicated mirror vars `t_syncDist`, `t_syncShoulder`, `t_syncHeight`,
`t_syncAutoFp`, `t_syncReady`. The server stamps them from its own config in
`PostBeginPlay()`; they replicate reliably server→clients. Clients apply them
in `Possess()` (overriding local ini defaults for dist/shoulder/height/auto-FP)
and `TP_SetCamParams()` uses them as easing targets for the regular stance so
host-driven console changes reach clients too.

Rebuilt: 0 errors / 0 warnings.

### 2026-10-25 — round 16: camera config sync made authoritative (periodic enforcement)

Round 15's one-shot `Possess()` apply was insufficient: replication arrives
after `Possess()` on the client, so `t_syncReady` was still false and the
client kept using its own ini defaults (shoulder=0 instead of the host's 30).

Fix: made the sync authoritative with periodic enforcement every 1000ms in
`PlayerTick()`:
- **Server** (`Role == ROLE_Authority`): restamps `t_syncDist`/`t_syncShoulder`/
  `t_syncHeight`/`t_syncAutoFp`/`t_syncReady` from its own config every second,
  so config changes during gameplay (console commands / GUI edits) propagate
  to clients too.
- **Client** (`Role < ROLE_Authority`): once `t_syncReady` arrives via
  replication, enforces the host-synced dist/shoulder/height/auto-FP every
  second, overriding local ini defaults. Handles late-arriving replication
  and mid-game config changes.

Rebuilt: 0 errors / 0 warnings.

### 2026-10-25 — round 17: per-second camera diagnostics (router + cam state)

Report: user reports the client still shows "shoulder=0" on screen even though
the round-16 logs prove the sync fired (`enforced ... dist=200 shoulder=20
height=20 autoFP=True` every second) and even `camera active` with the same
values. Values in ini, sync logs and cam-render math all agree — the visual
resolution is elsewhere, so instrumentation was added:

- `PlayerCalcView` stock-route fallback: once per second (tp_debug) logs WHY the
  view fell back to the stock centre-behind camera
  (`bBehindView/fpLock/vtPawn/health/specialCalcView/vehicle/spectating/syncReady`).
  A "no shoulder" look almost certainly means this stock branch is rendering.
- `TP_CalcCam` third-person win path: once per second (tp_debug) logs the full
  final render inputs (`dist/shoulderEased/sign/camShoulder/height/freeDist/
  fpLock/aimMode/syncReady`) — what the screen actually renders.

Note: UnrealScript `$` string concat only coerces plain locals — parenthesised
expressions need to be precomputed into local bools.

Rebuilt: 0 errors / 0 warnings.

### 2026-10-25 — round 18: root cause found via diagnostics — client-side state never seeded + profile-only enforcement

The round-17 per-second dumps pinpointed both real defects on the next run:

Client cam-state dump showed `sign=0 shoulderEased=0.00` while the host showed
`sign=1 shoulderEased=20.00`. **`Possess()` never executes on the client copy**
of the controller (engine-side: it runs authoritative-server-only), so the
per-machine camera state (`t_shoulderSign`, `t_shoulderEased`, t_cam*) stayed
at their zero defaults forever → camera rendered with zero side offset — the
original "client has no shoulder" report. Fix: `PostBeginPlay()` (which DOES
run on the client copy) seeds the same state the server's Possess would have
seeded, for `Role != ROLE_Authority` copies. `bBehindView` is deliberately not
seeded: third-person activation stays deferred to the round-14 RPC (freeze fix).

Client also showed the reported aim-mode loop: dist easing toward the aim
stance (140→138…), then snapping straight back to 200 the next second, easing
in again, forever — ~1 s period. That was the round-15/16 enforcement writing
the **eased runtime camera state** (`t_camDist`/`t_shoulderEased`) directly
every second. Fix: enforcement now writes ONLY the config profile vars
(`tp_dist/tp_shoulder/tp_height/tp_aim_*/tp_crouch_*/tp_fp_in/tp_fp_out/
tp_easetime/tp_turnspeed/tp_auto_fp`) — in-memory, no SaveConfig — so
`TP_SetCamParams` eases the *current* stance toward the host profile naturally.

Extended: the server now replicates the FULL camera profile (aim + crouch
stances, FP thresholds, ease/turn speeds) via `TP_StampSyncVars()` — 14 synced
floats + `t_syncReady`. `TP_SetCamParams`'s round-15 t_sync override was
reverted (tp_* is now the single source of truth on every machine).

Rebuilt: 0 errors / 0 warnings.

### 2026-10-25 — round 19: remote shot accuracy — dead-reckoned convergence + wider freshness gate

Report: client shots drift relative to the crosshair more than the host's.

Cause: AdjustAim resolves server-side, so a remote player's shots are aimed at
the last convergence point streamed from the client — same-frame on the host,
but one or several frames late for remotes over the unreliable stream (and the
stock parallax fallback after a 0.2 s lapse, e.g. packet loss on Wi-Fi).

Fix:
- `ServerTPAimPoint` now samples the point's velocity (teleport-sized deltas
  ignored, >5k s/s discarded) when a plausible interval arrives.
- `AdjustAim`'s convergence branch advances the point to the moment of firing:
  `t_aimPoint + t_aimVel * min(age, 0.1)`. On the local host age ≈ 0 and no
  velocity is tracked, so it is a no-op there.
- Freshness gate widened 0.2 -> 0.35 s: a slightly stale convergence point
  still aims at what the crosshair painted recently, which beats the stock
  third-person parallax path; dead reckoning is capped so long gaps never
  lead far.
- tp_debug diagnostic: logs when a known-but-stale convergence point is
  dismissed and a shot takes the stock path (stream lapse detection).

Remaining inherent limit (documented): remote clients see other pawns at their
replicated interpolation positions, so the crosshair point on a fast-moving
target lags the server's authoritative position by ~ping/2 — not fixable from
scripts; it is small on LAN.

Rebuilt: 0 errors / 0 warnings.

### 2026-10-25 — round 20: package version stamp, remote-only deferral gate, honest aim-path diagnostic

Incident: first time the roles were swapped (laptop hosts SpaceNoxx, desktop
joins), the desktop client froze during join-load — twice (03:51 and 04:10).
Both frozen client logs end between the local `New Player` + garbage collect
and the `Precaching:` line that always follows in successful joins, with NO
GTA-TP client-side lines (no seed) and no download lines; the host logs show
no `Possess` for the joining player's server copy and (04:10) only
self-addressed `deferred ClientSetBehindView(true) sent` lines (host player's
own respawns).

Diagnosis evolution:
- Round-14 RPC trigger ruled out twice: the client froze before any client-side
  mod code ran, and no RPC could have been delivered to it.
- Package drift CONFIRMED flagged: laptop's GTAThirdPerson.u md5 ended
  ...cc57a vs desktop round-19 4f5c2325... — the user synced after checking.
- Native map load ruled out: Instant Action SpaceNoxx (19 bots) runs flawless
  on the desktop solo. The failure is specific to the desktop as a JOINING
  client to the laptop's server, on any map (Tutorial test pending).

Round 20 changes (all in GTAPlayerController):
- `const TP_MODVERSION = 20` + one-line `GTA-TP: package version 20` logged in
  PostBeginPlay on BOTH copies of any controller. Two installs that drift
  apart (asymmetric class layouts) can hang a joining client with no error
  string; from now on, parity is one `grep` in each log.
- Deferredround-14 activation gate now also requires `Player == None` — this
  only passes on REMOTE clients' server copies. The local host's own
  controller on a listen server has Player set and used to re-send the RPC to
  itself 3 s after every respawn (the confusing self-sends in the host logs).
- tp_debug AdjustAim fallback diagnostic relabeled: was
  "convergence stale (age=…)" which mislabeled non-age refusals (host's own
  first-person frames, fpLock, vehicle, dead pawn logged "stale age=0.01").
  Now "convergence unused (age=…, behind=…, fpLock=…, vehicle=…, health=…)"
  so the dump is attributable ("age>0.35" = stream lapse, "behind=False" =
  first-person frame, etc.).

Rebuild procedure note: rm -f the .u/.ucl before UCC make (incremental builds
silently skip rewriting the package).

New package md5 (round 20): da1a2544097e106fc9f6eb107c175efe (.u), the .ucl
must be copied alongside it (de8f0d61…).

Rebuilt: 0 errors / 0 warnings.

### 2026-10-25 — round 21: ROOT CAUSE of the client-join freeze — missing ServerPackages on the host; automatic self-registration

Resolution of the rounds 14-20 saga: the swapped pair (desktop joins
laptop-hosted SpaceNoxx) froze every time while instant action on the same
machine/map/bot count ran flawless. The frozen client died before ANY
client-side mod code ran (no seed line, no precache line, no downloads), and
the round-14 deferred ClientSetBehindView RPC never reached it (no "deferred
sent" addressed to the remote, twice).

Adding ServerPackages=GTAThirdPerson to the LAPTOP's UT2004.ini
([Engine.GameEngine]) — the host for the failing tests — FIXED the join
instantly. Round 14's RPC deferral was a red herring all along: the actual
round-14 fix was the same ini line added to the desktop's ini (then host).

Code (GTAThirdPersonMutator):
- TP_EnsureServerPackage(): on every server boot with the mod active, scan
  class'Engine.GameEngine'.default.ServerPackages (dynamic array; verified by
  UCC compiling cleanly) and, if "GTAThirdPerson" is absent, append it and
  StaticSaveConfig() the class defaults (writes [Engine.GameEngine] in the
  host's UT2004.ini). UT2004 reads the list only at server startup, so the
  reg: takes effect on the NEXT start; logged loudly accordingly.

Docs:
- README "Install" now opens with a big REQUIRED-to-host warning block:
  the symptom is a silent mid-load freeze (not Connection Lost), ini location
  [Engine.GameEngine], restart requirement, the grep verification, and the
  auto-registration from round 21.
- Multiplayer bullets updated: correct failure description + keep .u/.ucl
  byte-identical + version-stamp grep.

Sandbox verification (temp ini, headless UCC server): removed the line, one
boot appended it back at exactly the same spot; rewritten ini byte-identical
to the original otherwise (diff = only that line).

Rebuilt: 0 errors / 0 warnings (round-21 .u md5 7bb1cd4ab8fccc8a74b79c36611
...dbf13; also confirm the round-20 changes: version stamp 21, remote-only
deferral gate, "convergence unused" diagnostic with gate reasons).

### 2026-10-25 — round 22: loose ends — the 3-second RPC deferral is gone

With round 21 having established the missing host ServerPackages line as THE
root cause of every join freeze, the round-14 deferral (wait 3 s after
Possess before sending ClientSetBehindView(true) to a remote) had no left
justification: frozen clients were proven to never receive any RPC, and the
wait was pure first-person latency for joining players.

Changes (GTAPlayerController):
- Removed var t_clientActivate and its Possess-time stamp.
- The one-shot remote activation sender in PlayerTick keeps (round 20's)
  remote-only gate (Player == None) and its per-tick retry, but no longer
  consults any timer: the RPC fires on the first tick where
  Role==AUTH && Player==None && tp_enable && !Standalone && !vehicle &&
  bBehindView && ViewTarget==Pawn — for a joining client that moment is the
  end of its level load, so activation is now near-instant after join.
- tp_debug line renamed to "remote ClientSetBehindView(true) sent" (the old
  "deferred ..." wording no longer matches anything).
- Comments updated at Possess / PostBeginPlay seed / PlayerTick sites.
- TP_MODVERSION 21 -> 22.

Kept on purpose: the one-shot gate and the retry loop — they guarantee
exactly one RPC per remote session and survive transient early-tick misses
(ViewTarget not yet set), which are engine facts independent of the freeze
myth.

Rebuilt: 0 errors / 0 warnings. Round-22 package md5
e29492a32b26d7113c63cbd50d22f6d6 (never care how incrementally odd the .u
rewrite dance looks — rm the package first, see round 20 note).

Test plan for the user (same ladder, only faster): laptop hosts, desktop
joins — third person should now engage the moment the client controller
ticks, instead of 3 s after join. Watch for:
- "package version 22" on BOTH ends,
- "remote ClientSetBehindView(true) sent" no longer self-sending to the
  host player (round 20 guard),
- no freeze (ServerPackages line must still exist on the host — the mod now
  self-registers it in round 21+, but verify once).

### 2026-10-29 — round 23: scopes and Redeemer guidance force first person; third-person weapon shake

Two gaps left by the "third person is the normal view" model:

1. Scoped fire and Redeemer guidance are camera-critical. In third person the
   sniper scope is unusable (the scope overlay does not match the over-shoulder
   ray) and the guided Redeemer puts the camera behind the missile instead of
   in its nose. Both now force first person for their duration, remember the
   view the player was using, and restore it on exit.
2. First-person weapon shake (Assault Rifle, Minigun spin-up, damage shake)
   never reached the third-person camera because stock only applies
   ShakeRot/ShakeOffset inside CalcFirstPersonView.

Changes (GTAPlayerController):
- New transient memory vars: t_scopeActive / t_scopeWasBehind / t_scopeWasFpLock
  and t_guideActive / t_guideWasBehind / t_guideWasFpLock.
- StartZoomWithMax() override: on the first call of a zoom episode, save
  bBehindView + t_fpLock, set bBehindView=false, then Super. EndZoom() override:
  Super first, then restore the saved view. Rationale: SniperRifle's scope-on
  path calls ToggleZoom -> StartZoomWithMax (and StartZoom when already ramped),
  scope-off calls StopZoom (ramp halt only) or EndZoom (full exit), so hooking
  StartZoomWithMax/EndZoom is the pair that brackets the whole scoped episode;
  the t_scopeActive guard makes repeated StartZoomWithMax/StartZoom calls
  idempotent without re-saving an already-forced value.
- Possess() rewritten around `aPawn.IsA('RedeemerWarhead')` (stock idiom):
  * warhead possessed and no guide active: remember bBehindView + t_fpLock
    BEFORE Super, then force first person after it;
  * a non-warhead possessed while a guide is active: we are back on the player
    pawn (RedeemerWarhead.RelinquishController repossesses the old pawn; stock
    UnPossess does not touch bBehindView, so the pre-guidance value survives),
    restore the saved view;
  * anything else is a normal spawn/restart: tp_enable / t_fpLock=false as
    before. Removed the old t_guideOldPawn/GetPropertyText hack.
  * bBehindView is not replicated, so on a remote player's server copy
    (Role==AUTH && Player==None && !Standalone) the restore also sends
    ClientSetBehindView(bBehindView), otherwise the remote client would stay
    in the first person that Super.Possess -> Restart -> BehindView installed.
- TP_CalcCam(): after the normal camera placement, add ShakeRot to the camera
  rotation and ShakeOffset to CamLoc along the (post-shake) camera axes, plus
  the ambient-shake rot/offset when bEnableAmbientShake, mirroring
  CalcFirstPersonView. ViewShake() runs every tick via Super.UpdateRotation, so
  those vars are current by the time PlayerCalcView runs. The shake is applied
  after the wall trace, so it deliberately does not pull the camera out of
  walls (stock does not trace shake either).
- Removed unused locals left over from the draft (YawOnly, UpVec) to keep the
  build at 0 warnings.
- TP_MODVERSION 22 -> 23.

Rebuilt: 0 errors / 0 warnings. Round-23 package md5
5a71726d7314ce1f35072e13d30daa58. Headless server load of
DM-Antalus + the mutator is clean (only the usual unrelated Infestation map
and DNS noise).

Test plan for the user:
- Third person + sniper zoom in/out: view must snap to first person on scope-in
  and return to the exact previous view (third or first) on scope-out, with
  "package version 23" in the log.
- Third person + Redeemer guided missile: first person while flying, back to
  the previous view after the warhead detonates; on a remote client too
  (ClientSetBehindView restore).
- Fire the AR / spin the Minigun in third person: the camera should now kick
  like the first-person view does.

### 2026-10-30 — round 24: clients never got the forced third person on spawn; view now survives respawns

Two reports from playtesting:

1. Clients did not start in third person even with the mutator enabled; they
   had to press TP_Toggle after joining.
2. The chosen view was not remembered across respawns: the host always came
   back in third person (the default), clients in first person.

Root cause of (1): a wrong "remote controller" test. The remote activation
sender was gated on `Player == None`, on the belief that only the local host's
controller has a Player. In UE2/UT2004 a remote player's SERVER-side
controller HAS Player set (the net connection object); what it does not have
is a Viewport. Stock distinguishes local from remote with
`Viewport(Player) != None` (Engine/PlayerController.AcknowledgePossession,
XGame/xPlayer.PlayerTick). So the gate never matched a remote controller and
`ClientSetBehindView(true)` was never sent — clients stayed in the stock first
person that ClientRestart installs. The round-23 Redeemer restore RPC had the
same gate and the same dead path.

Root cause of (2): both `PlayerController.Restart()` and `ClientRestart()`
apply `bBehindView = Pawn.PointOfView()` (false for normal pawns) on every
spawn, and Possess then unconditionally used `tp_enable`, so the previous
choice was lost. TP_Toggle was also a purely local exec: the server's copy of
bBehindView never learned about a remote player's toggle.

Changes (GTAPlayerController):
- Remote-controller gates in the PlayerTick activation sender and in the
  Redeemer guidance-end restore now use `Viewport(Player) == None`, with
  comments citing the stock idiom.
- New replicated view preference: t_viewPrefSet / t_viewPrefBehind
  (authority -> client) plus a client -> server reliable `ServerTPViewPref`
  that also sets the server's bBehindView (so bFreeCamera / server-side pawn
  facing follow the client's choice).
- TP_Toggle records the new state in the preference and, on a remote client,
  sends it to the server.
- Possess normal branch: first possession of a session = tp_enable (third
  person); afterwards restore t_viewPrefBehind.
- New ClientRestart() override: after Super (which just installed
  Pawn.PointOfView), re-apply the remembered preference, or default to true on
  the first possession of a session. Runs on the server copy via Restart and
  on the owning client copy via the reliable RPC, which is what makes the
  choice stick on both ends. Skips RedeemerWarhead (round-23 guidance must
  stay first person) and vehicles (keep stock chase-camera decision).
- Removed the unused/incorrect comment claiming remote copies have no Player.
- TP_MODVERSION 23 -> 24.

Rebuilt: 0 errors / 0 warnings. Round-24 package md5
00bd3582e44a5b5bcceb1c3a8523aa72. Headless server load clean.

Test plan for the user:
- Client joins a match with the mutator: must spawn in third person with no
  key press ("package version 24" on both ends).
- Toggle to first person, die, respawn: stays first person. Toggle back, die,
  respawn: stays third person. Same on the host.
- Toggle on a remote client and watch your body facing on the host's screen:
  it should match stock first person when you are in first person.
- Redeemer guide from third person as a remote client: first person in the
  missile, back to third person after detonation.

### 2026-10-30 — round 25: client view fixed locally on every pawn change (no RPC dependency)

Round 24 fixed the host but the remote client still spawned/respawned in first
person and still stayed first person after Redeemer guidance. The client-side
pieces of round 24 all depended on either the server's ClientSetBehindView
RPC or the replicated preference arriving in the right order relative to
stock's own ClientRestart -> BehindView(false) call. Whichever packet landed
last won, and on the client that was stock's false.

Rather than keep chasing RPC ordering, the client now observes its own Pawn.
PlayerTick on the local copy takes exactly the same path as every other
client-side feature (input, PlayerCalcView, TP_Toggle), so it cannot be
starved by replication:

- New transient t_viewPawn + t_viewReassertUntil.
- When Pawn changes (spawn, respawn, or the warhead -> player pawn swap at the
  end of Redeemer guidance), the controller starts a 2-second re-assertion
  window and applies the remembered view. During the window it keeps
  re-applying bBehindView = t_viewPrefBehind unless the view is legitimately
  overridden: auto first person (t_fpLock), a scope (t_scopeActive), the
  Redeemer missile (Pawn is a RedeemerWarhead), a vehicle, death
  (Pawn.Health <= 0) or spectating.
- A manual TP_Toggle updates the preference, so the window does not fight it.
- The same code runs on the host, where Possess already applied the view, so
  it is a no-op there.
- The view preference vars are NO LONGER replicated (round-24 replication
  removed). Each machine owns its copy: the server's from Possess +
  ServerTPViewPref, the client's from its own TP_Toggle and this local
  re-assertion. Server -> client replication could overwrite a fresh client
  choice with a stale value at exactly the wrong moment (the likely reason
  round 24 still failed on the client).
- ClientRestart override kept as the immediate path; the pawn-change
  re-assertion is the safety net that survives late stock RPCs.
- TP_MODVERSION 24 -> 25.

Rebuilt: 0 errors / 0 warnings. Round-25 package md5
91c663c660a3c5e540cbb212827aff5d. Headless server load clean.

Also note for testers: the client must actually have the round-25 .u. The
round-24 symptoms are exactly what a round-23 client would show, so check
`grep "package version" UT2004.log` on the client before judging the fix —
it must print 25.

Test plan for the user:
- Client joins / respawns: third person, no key press.
- Client toggles first person, dies, respawns: still first person.
- Client guides a Redeemer launched from third person: back to third person
  after the warhead detonates (and first person if launched from first person).
- Host behaviour unchanged.
