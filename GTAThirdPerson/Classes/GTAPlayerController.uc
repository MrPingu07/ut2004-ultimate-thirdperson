//=============================================================================
// GTAPlayerController
//
// GTA San Andreas style third person camera for UT2004, mirroring the design
// of hl-thirdperson (GoldSrc). Mouse orbits the camera, movement is
// camera-relative, and shots land exactly on the reticle (which is drawn on
// the end of the shot convergence ray).
//
// How it works (verified against decompiled stock sources):
//  - Camera: PlayerCalcView() override builds an offset orbit camera; the
//    controller Rotation stays the camera rotation, and every stock movement
//    state except PlayerWalking is already camera-relative natively.
//  - Body: the pawn's PHYSICAL rotation is decoupled from the camera. The
//    stock `bFreeCamera` flag (set per tick on foot only) keeps stock
//    UpdateRotation from re-facing the pawn at the camera; TP_FaceBody then
//    rotates the pawn towards the GTA body target (movement direction, or the
//    crosshair while aiming/firing) with FaceRotation. Because the pawn no
//    longer faces the camera, walking input is re-based on the controller
//    axes in our state PlayerWalking copy. No bone hacks, server-accurate
//    facing. Vehicles/turrets keep stock facing (and gun swivel).
//  - Shots: while in third person we compute the real crosshair ray (camera
//    origin along vector(Rotation)) and trace it into the world; the result
//    (t_aimPoint) is used by AdjustAim so bullets/projectiles converge on the
//    crosshair regardless of the shoulder offset or the look pitch (parallax fix).
//    Since the ray always ends at the screen centre the stock (custom player)
//    crosshair stays visible and needs no replacement overlay.
//=============================================================================
class GTAPlayerController extends xPlayer
    config(GTAThirdPerson);

// ------ configurable values (UT2004.ini, [GTAThirdPerson.GTAPlayerController]) ------
var config bool  tp_enable;         // master switch (0 = stock first person)
var config float tp_dist;           // camera distance
var config float tp_shoulder;       // magnitude; sign sets side in every stance
var config float tp_height;         // vertical camera offset (positive up)
var config float tp_turnspeed;      // body turn speed, DEGREES per second (eased, shortest arc)
var config float tp_easetime;       // easing time in seconds for shoulder/height/distance
var config bool  tp_autoadjust;     // use the crouch values while crouching
var config float tp_crouch_dist;
var config float tp_crouch_shoulder;
var config float tp_crouch_height;
var config float tp_aim_dist;       // tpaim stance
var config float tp_aim_shoulder;
var config float tp_aim_height;
var config bool  tp_fire_lock;      // body locked to the crosshair while firing
var config bool  tp_auto_fp;        // auto first person when there is no room behind
var config float tp_fp_in;          // free space below which it switches to first person
var config float tp_fp_out;         // free space from which it returns to third person
var config int   tp_bindver;        // internal: version of the default binds already applied
var config int   tp_turnver;        // internal: config-defaults migration marker (see TP_CFGVERSION)
var config bool  tp_debug;          // logs install details once per game (for playtesting)
var config bool  tp_autobind;       // 0 = never overwrite existing key binds; 1 = force default binds once

// ------ runtime state ------
var transient bool  bTPAim;
var transient int   t_shoulderSign;      // +1 / -1
var transient float t_camDist, t_camShoulder, t_camHeight;
var transient float t_bodyTargetYaw;     // desired body yaw (absolute)
var transient bool  t_bodyTargetValid;
var transient float t_bodyYaw;           // eased physical body yaw (absolute)
var transient bool  t_fpLock;
var transient float t_lastCamCalc;
var transient bool  t_camLogged;
var transient bool  t_unlockLogged;
var transient vector t_aimPoint;         // convergence point of the shots (world)
var transient vector t_camOrigin;        // camera origin of the last view
var transient bool  t_eF, t_eB, t_eL, t_eR, t_wasF, t_wasB, t_wasL, t_wasR;
var transient eDoubleClickDir t_dblDir;  // our copy of PlayerInput's double click state
var transient float t_dblTimer;          // (PlayerInput is private to Engine.PlayerController)
var transient float t_lastReticleScan;   // throttle for the vehicle reticle mute scan

const TP_BINDVERSION = 2;
// Config migration version (stored in tp_turnver for ini compat):
//  2 = binds v2 (historical), 3 = tp_turnspeed units->degrees (round 7),
//  4 = tp_shoulder default 20 -> 30 (round 8, user-tested).
const TP_CFGVERSION = 4;

simulated event PostBeginPlay()
{
    Super.PostBeginPlay();

    // Default keybinds, applied once (hl-thirdperson style first-run binds).
    // UT2004 has no `bind` console command; the stock UI (GUIController)
    // writes binds with `set Input <key> <command>` and reads them with
    // `KEYBINDING <key>` — that is what we use here.
    if ( tp_bindver < TP_BINDVERSION )
        TP_SetDefaultBinds();

    // Round 7+8 config migration (see TP_CFGVERSION). Legacy inis carry
    // rotator-unit turn speeds and the old 20 shoulder; fresh installs skip
    // this branch via tp_turnver=4 in defaultproperties.
    if ( tp_turnver < TP_CFGVERSION )
    {
        if ( tp_turnver < 3 )
            tp_turnspeed = FClamp( tp_turnspeed / 182.044444, 1.0, 2000.0 );
        tp_shoulder = 30.0;
        tp_turnver  = TP_CFGVERSION;
        SaveConfig();
        if ( tp_debug )
            Log( "GTA-TP: config migrated (turnspeed to deg/s if needed, shoulder to 30)" );
    }
}

exec function TP_SetDefaultBinds()   // re-runable fix for the keybinds
{
    TP_DoBind( "Z",   "TP_Toggle" );
    TP_DoBind( "X",   "TP_SwapShoulder" );
    TP_DoBind( "ALT", "TP_AimMode" );
    tp_bindver = TP_BINDVERSION;
    SaveConfig();
}

function TP_DoBind( string KeyName, string Command )
{
    local string Cur;

    Cur = ConsoleCommand( "KEYBINDING" @ KeyName );
    if ( !tp_autobind && Cur != "" && Cur != Command )
    {
        Log( "GTA-TP: key '"$KeyName$"' already bound to '"$Cur$"', skipped (tp_autobind=false)" );
        return;
    }
    if ( Cur != Command )
        Log( "GTA-TP: binding key "$KeyName$" -> "$Command$" (was '"$Cur$"')" );
    ConsoleCommand( "set Input" @ KeyName @ Command );
}

function Possess( Pawn aPawn )
{
    Super.Possess( aPawn );

    // start in third person when the mod is enabled
    bBehindView       = tp_enable;
    t_shoulderSign    = 1;
    t_camDist         = tp_dist;
    t_camShoulder     = tp_shoulder;
    t_camHeight       = tp_height;
    t_bodyYaw         = Rotation.Yaw;
    t_bodyTargetYaw   = Rotation.Yaw;
    t_bodyTargetValid = false;
    t_fpLock          = false;
    t_camLogged       = false;
    t_unlockLogged    = false;

    // a fresh HUD shows the user's own crosshair again

    if ( tp_debug )
        Log( "GTA-TP: Possess pawn="$aPawn$" controller="$Class
             $" behind="$bBehindView$" enable="$tp_enable
             $" netmode="$Level.NetMode );
}

simulated event PlayerTick( float DeltaTime )
{
    // Manage the stock bFreeCamera flag here, every tick (UpdateRotation runs
    // later, inside Super.PlayerTick). On foot, TRUE makes stock UpdateRotation
    // skip Pawn.FaceRotation(camera) (Engine/PlayerController.uc ~4406), so the
    // pawn facing is owned solely by TP_FaceBody. In vehicles it must be FALSE:
    // turret seats (ONSWeaponPawn and kin) swivel the mounted gun via that same
    // Pawn.FaceRotation call, and a stale TRUE frozen it (round-5 report).
    // Vehicles were never handled before because TP_SetCamParams does not run
    // while driving (PlayerCalcView routes them to stock), so the last on-foot
    // value leaked into the vehicle the whole time.
    bFreeCamera = tp_enable && (Pawn != None) && (Vehicle(Pawn) == None)
                  && bBehindView && !t_fpLock;

    if ( tp_enable && ((Level.TimeSeconds - t_lastReticleScan) > 1.0) )
    {
        t_lastReticleScan = Level.TimeSeconds;
        TP_MuteVehReticles();
    }

    Super.PlayerTick( DeltaTime );
}

// The stock ONS vehicles/turrets (ONSVehicle.DrawHUD, ONSWeaponPawn.DrawHUD)
// draw a SECOND screen-centred reticle (tankBarrelAligned) once the cannon has
// aligned with the camera direction (bCorrectAim). The mod keeps the player's
// own custom crosshair everywhere, so this duplicate is muted. The stock draw
// places the tile rect symmetrically around the screen centre
// ([C-X, C+X] x [C-Y, C+Y]) reading AfterCrosshairX/Y *from the class config
// vars*, so zeroing them shrinks the draw to a single 1x1 pixel at the exact
// centre (hidden under the player crosshair). Zeroing via the offset vars
// beats alternatives: CrosshairTexture=None would crash the draw (the script
// reads CrosshairTexture.USize on possibly-None) and bCorrectAim is a native
// const that also gates firing. Per-instance so other vehicles/gametypes are
// untouched; the scan catches late-spawned vehicles too.
function TP_MuteVehReticles()
{
    local ONSWeaponPawn W;
    local Vehicle       V;

    foreach AllActors( class'Vehicle', V )
    {
        W = ONSWeaponPawn(V);
        if ( W != None )
        {
            W.CrosshairX = 0;
            W.CrosshairY = 0;
        }
        else if ( ONSVehicle(V) != None )
        {
            ONSVehicle(V).CrosshairX = 0;
            ONSVehicle(V).CrosshairY = 0;
        }
    }
}

// ---------------------------------------------------------------------------
// body facing (decoupled from the camera)
// ---------------------------------------------------------------------------

// Overrides the stock version, which the mouse view code calls after facing
// the pawn at the camera. The Super call keeps all of that (input, shake,
// pitch limits, FP facing); afterwards we physically rotate the pawn towards
// the GTA body target. Stock facing for ladder/spider/vehicles/death/FP.
function UpdateRotation( float DeltaTime, float maxPitch )
{
    Super.UpdateRotation( DeltaTime, maxPitch );

    TP_FaceBody( DeltaTime );
}

simulated function TP_FaceBody( float dt )
{
    local Pawn     P;
    local bool     bLock;
    local vector   HV;
    local rotator  BodyRot;
    local float    Diff, Step;

    P = Pawn;

    if ( !tp_enable || !bBehindView || t_fpLock )
        return;    // first person: stock facing applies

    if ( P == None || (Vehicle(P) != None) || (P.Health <= 0) )
        return;
    if ( P.Physics != PHYS_Walking && P.Physics != PHYS_Falling && P.Physics != PHYS_Swimming )
        return;    // ladders, spider walls, etc: stock behaviour

    bLock = bTPAim || (tp_fire_lock && (P.PressingFire() || P.PressingAltFire()));
    if ( bLock )
    {
        // aiming/firing: the body is locked to the crosshair
        t_bodyTargetYaw   = Rotation.Yaw;
        t_bodyTargetValid = true;
    }
    else
    {
        HV   = P.Velocity;
        HV.Z = 0.0;
        if ( VSize(HV) > 40.0 )
        {
            // moving: the body faces the movement direction
            t_bodyTargetYaw   = rotator(HV).Yaw;
            t_bodyTargetValid = true;
        }
        // idle: keep the last target, so the mouse can orbit around the body
    }

    if ( !t_bodyTargetValid )
        return;

    t_bodyYaw = TP_YawShort( t_bodyYaw );
    // tp_turnspeed is degrees/second; UE2 yaw units are 1/360th of 65536,
    // so 1 deg = 182.044444 units.
    Step = tp_turnspeed * dt * 182.044444;
    Diff = TP_YawShort( t_bodyTargetYaw - t_bodyYaw );
    if      ( Diff >  Step )
        t_bodyYaw += Step;
    else if ( Diff < -Step )
        t_bodyYaw -= Step;
    else
        t_bodyYaw = t_bodyTargetYaw;

    BodyRot.Pitch = 0;
    BodyRot.Yaw   = int(TP_YawShort( t_bodyYaw )) & 65535;
    BodyRot.Roll  = 0;
    P.FaceRotation( BodyRot, dt );
}

function float TP_YawShort( float Diff )
{
    while ( Diff >  32768.0 ) Diff -= 65536.0;
    while ( Diff < -32768.0 ) Diff += 65536.0;
    return Diff;
}

// ---------------------------------------------------------------------------
// third person movement: walking input re-based on the camera axes
// ---------------------------------------------------------------------------

// Mirror of Engine.PlayerInput.CheckForDoubleClickMove using our own state
// vars (see the notes in the PlayerWalking copy below).
function eDoubleClickDir TP_DblClickMove( float DeltaTime )
{
    local eDoubleClickDir DoubleClickMove, OldDoubleClick;
    local float DClickTime;

    if ( !DodgingIsEnabled() )
        return DCLICK_None;

    DClickTime = class'PlayerInput'.default.DoubleClickTime;

    if ( t_dblDir == DCLICK_Active )
        DoubleClickMove = DCLICK_Active;
    else
        DoubleClickMove = DCLICK_None;

    if ( DClickTime > 0.0 )
    {
        if ( t_dblDir == DCLICK_Active )
        {
            if ( (Pawn != None) && (Pawn.Physics == PHYS_Walking) )
            {
                t_dblTimer = 0;
                t_dblDir   = DCLICK_Done;
            }
        }
        else if ( t_dblDir != DCLICK_Done )
        {
            OldDoubleClick = t_dblDir;
            t_dblDir       = DCLICK_None;

            if ( t_eF && t_wasF )
                t_dblDir = DCLICK_Forward;
            else if ( t_eB && t_wasB )
                t_dblDir = DCLICK_Back;
            else if ( t_eL && t_wasL )
                t_dblDir = DCLICK_Left;
            else if ( t_eR && t_wasR )
                t_dblDir = DCLICK_Right;

            if ( t_dblDir == DCLICK_None )
                t_dblDir = OldDoubleClick;
            else if ( t_dblDir != OldDoubleClick )
                t_dblTimer = DClickTime + 0.5 * DeltaTime;
            else
                DoubleClickMove = t_dblDir;
        }

        if ( t_dblDir == DCLICK_Done )
        {
            t_dblTimer = FMin( t_dblTimer - DeltaTime, 0.0 );
            if ( t_dblTimer < -0.35 )
            {
                t_dblDir   = DCLICK_None;
                t_dblTimer = DClickTime;
            }
        }
        else if ( (t_dblDir != DCLICK_None) && (t_dblDir != DCLICK_Active) )
        {
            t_dblTimer -= DeltaTime;
            if ( t_dblTimer < 0 )
            {
                t_dblDir   = DCLICK_None;
                t_dblTimer = DClickTime;
            }
        }
    }
    return DoubleClickMove;
}

// Copy of the stock (Engine.PlayerController) state PlayerWalking.PlayerMove.
// UE2 orients ground movement off the pawn rotation; since our pawn faces the
// movement target instead of the camera, the acceleration basis is switched
// from Pawn.Rotation to the controller Rotation. The other states
// (PlayerSwimming, PlayerClimbing, PlayerSpidering, ...) already build their
// acceleration from the controller axes in stock code, no copy needed.
// ProcessMove/NotifyLanded/BeginState/etc. are not redeclared and keep
// resolving to the UnrealPlayer/Engine implementations (class-major lookup).
state PlayerWalking
{
    function PlayerMove( float DeltaTime )
    {
        local vector X,Y,Z, NewAccel;
        local eDoubleClickDir DoubleClickMove;
        local rotator OldRotation, ViewRotation, CamYaw;
        local bool  bSaveJump;

        if( Pawn == None )
        {
            GotoState('Dead'); // this was causing instant respawns in mp games
            return;
        }

        // GTA-TP: movement is re-based on the CAMERA axes (the pawn faces the
        // movement direction, not the camera), but with the pitch removed: at
        // full look up/down the pitched X axis would collapse into Z and kill
        // forward/back movement entirely (walking has no vertical accel).
        CamYaw.Pitch = 0;
        CamYaw.Yaw   = Rotation.Yaw;
        CamYaw.Roll  = 0;
        GetAxes(CamYaw,X,Y,Z);

        // Update acceleration.
        NewAccel = aForward*X + aStrafe*Y;
        NewAccel.Z = 0;
        if ( VSize(NewAccel) < 1.0 )
            NewAccel = vect(0,0,0);

        // double click (dodging) bookkeeping. PlayerInput itself is private to
        // Engine.PlayerController, so the edge flags and the double click state
        // are mirrored here exactly like Engine.PlayerInput.PlayerInput and
        // Engine.PlayerInput.CheckForDoubleClickMove do it.
        t_eF = (t_wasF ^^ (aBaseY > 0));
        t_eB = (t_wasB ^^ (aBaseY < 0));
        t_eL = (t_wasL ^^ (aStrafe < 0));
        t_eR = (t_wasR ^^ (aStrafe > 0));
        t_wasF = (aBaseY > 0);
        t_wasB = (aBaseY < 0);
        t_wasL = (aStrafe < 0);
        t_wasR = (aStrafe > 0);
        DoubleClickMove = TP_DblClickMove( 1.1*DeltaTime/Level.TimeDilation );

        GroundPitch = 0;
        ViewRotation = Rotation;
        if ( Pawn.Physics == PHYS_Walking )
        {
            // tell pawn about any direction changes to give it a chance to play appropriate animation
            //if walking, look up/down stairs - unless player is rotating view
             if ( (bLook == 0)
                && (((Pawn.Acceleration != Vect(0,0,0)) && bSnapToLevel) || !bKeyboardLook) )
            {
                if ( bLookUpStairs || bSnapToLevel )
                {
                    GroundPitch = FindStairRotation(deltaTime);
                    ViewRotation.Pitch = GroundPitch;
                }
                else if ( bCenterView )
                {
                    ViewRotation.Pitch = ViewRotation.Pitch & 65535;
                    if (ViewRotation.Pitch > 32768)
                        ViewRotation.Pitch -= 65536;
                    ViewRotation.Pitch = ViewRotation.Pitch * (1 - 12 * FMin(0.0833, deltaTime));
                    if ( (Abs(ViewRotation.Pitch) < 250) && (ViewRotation.Pitch < 100) )
                        ViewRotation.Pitch = -249;
                }
            }
        }
        else
        {
            if ( !bKeyboardLook && (bLook == 0) && bCenterView )
            {
                ViewRotation.Pitch = ViewRotation.Pitch & 65535;
                if (ViewRotation.Pitch > 32768)
                    ViewRotation.Pitch -= 65536;
                ViewRotation.Pitch = ViewRotation.Pitch * (1 - 12 * FMin(0.0833, deltaTime));
                if ( (Abs(ViewRotation.Pitch) < 250) && (ViewRotation.Pitch < 100) )
                    ViewRotation.Pitch = -249;
            }
        }
        Pawn.CheckBob(DeltaTime, Y);

        // Update rotation.
        SetRotation(ViewRotation);
        OldRotation = Rotation;
        UpdateRotation(DeltaTime, 1);
        bDoubleJump = false;

        if ( bPressedJump && Pawn.CannotJumpNow() )
        {
            bSaveJump = true;
            bPressedJump = false;
        }
        else
            bSaveJump = false;

        if ( Role < ROLE_Authority ) // then save this move and replicate it
            ReplicateMove(DeltaTime, NewAccel, DoubleClickMove, OldRotation - Rotation);
        else
            ProcessMove(DeltaTime, NewAccel, DoubleClickMove, OldRotation - Rotation);
        bPressedJump = bSaveJump;
    }
}

// ---------------------------------------------------------------------------
// camera
// ---------------------------------------------------------------------------
event PlayerCalcView( out actor ViewActor, out vector CameraLocation, out rotator CameraRotation )
{
    local bool bGTA;

    bGTA = tp_enable && (ViewTarget == Pawn) && (Pawn != None)
           && !Pawn.bSpecialCalcView && (Vehicle(Pawn) == None)
           && !IsSpectating() && (Pawn.Health > 0);

    // bBehindView OR t_fpLock: while the auto first person lock is engaged we
    // must keep re-evaluating the room behind the pawn to unlock it, so stay
    // routed on our branch even when bBehindView is false (fix for the latch
    // where the lock was never released until death/respawn).
    if ( bGTA && (bBehindView || t_fpLock) )
    {
        ViewActor      = Pawn;
        CameraLocation = Pawn.Location;

        if ( bBehindView )
        {
            TP_CalcCam( CameraLocation, CameraRotation );
            return;
        }

        // auto-FP engaged: refresh the room test; unlock when there is space
        TP_RefreshFP();
        if ( !t_fpLock )
        {
            bBehindView = true;
            if ( tp_debug && !t_unlockLogged )
            {
                t_unlockLogged = true;
                Log( "GTA-TP: room recovered, back to third person" );
            }
            TP_CalcCam( CameraLocation, CameraRotation );
        }
        else
        {
            CalcFirstPersonView( CameraLocation, CameraRotation );
        }
        return;
    }

    // dead, spectating, vehicles, other view targets, disabled, or manual FP: stock path
    Super.PlayerCalcView( ViewActor, CameraLocation, CameraRotation );
}

function TP_CalcCam( out vector CamLoc, out rotator CamRot )
{
    local vector Anchor, Dir, RightVec, HitLoc, HitNormal;
    local float  FreeDist, dt;
    local rotator YawOnly;

    dt = FMin( Level.TimeSeconds - t_lastCamCalc, 0.5 );
    if ( dt < 0.0 ) dt = 0.0;
    t_lastCamCalc = Level.TimeSeconds;

    CamRot = Rotation;      // mouse controls the camera directly, like the stock FPS aim

    TP_SetCamParams( dt );

    Dir = vector(CamRot);
    YawOnly.Pitch = 0;
    YawOnly.Yaw   = CamRot.Yaw;
    YawOnly.Roll  = 0;
    RightVec = vect(0,1,0) >> YawOnly;

    Anchor = Pawn.Location + Pawn.EyePosition();
    Anchor.Z += t_camHeight;
    Anchor += t_shoulderSign * t_camShoulder * RightVec;

    // desired camera, pulled in on walls (world geometry only, like the stock shader)
    FreeDist = t_camDist;
    if ( Trace( HitLoc, HitNormal, Anchor - t_camDist * Dir, Anchor, false, vect(10,10,10) ) != None )
        FreeDist = FMax( 8.0, FMin( ((Anchor - HitLoc) Dot Dir) - 8.0, t_camDist ) );

    if ( tp_auto_fp )
    {
        if ( FreeDist < tp_fp_in )
        {
            t_fpLock = true;
            // no room behind: stock first person until there is space again
            bBehindView = false;
            CalcFirstPersonView( CamLoc, CamRot );
            return;
        }
        if ( FreeDist > tp_fp_out )
            t_fpLock = false;
    }
    else
        t_fpLock = false;

    bBehindView = true;
    t_unlockLogged = false;

    CamLoc = Anchor - FreeDist * Dir;

    // convergence ray for the reticle & AdjustAim. The camera sits on the
    // view line (the pull-in moves along the view direction), so tracing from
    // the anchor along the camera direction IS the true crosshair ray.
    t_camOrigin = CamLoc;
    TP_CalcAimPoint( Anchor, Dir );

    if ( tp_debug && !t_camLogged )
    {
        t_camLogged = true;
        Log( "GTA-TP: camera active dist="$t_camDist
             $" shoulder="$t_camShoulder$" height="$t_camHeight );
    }
}

// Real crosshair ray: what the camera ray hits in the world becomes the point
// where the bullets/projectiles converge. Pawn.Trace excludes the pawn itself.
// Range 10000 matches the stock AdjustAim instant-hit trace.
function TP_CalcAimPoint( vector Origin, vector Dir )
{
    local actor  Hit;
    local vector HitLoc, HitNormal;

    Hit = Pawn.Trace( HitLoc, HitNormal, Origin + 10000.0 * Dir, Origin, true );
    if ( Hit != None )
        t_aimPoint = HitLoc;
    else
        t_aimPoint = Origin + 10000.0 * Dir;
}

// Room check while we are already in first person because of the auto-FP lock
// (uses the same anchor/trace math as TP_CalcCam; only un-locks on room).
function TP_RefreshFP()
{
    local vector Anchor, Dir, RightVec, HitLoc, HitNormal;
    local float  FreeDist, dt;
    local rotator YawOnly;

    dt = FMin( Level.TimeSeconds - t_lastCamCalc, 0.5 );
    if ( dt < 0.0 ) dt = 0.0;
    t_lastCamCalc = Level.TimeSeconds;

    TP_SetCamParams( dt );

    Dir = vector(Rotation);
    YawOnly.Pitch = 0;
    YawOnly.Yaw   = Rotation.Yaw;
    YawOnly.Roll  = 0;
    RightVec = vect(0,1,0) >> YawOnly;

    Anchor = Pawn.Location + Pawn.EyePosition();
    Anchor.Z += t_camHeight;
    Anchor += t_shoulderSign * t_camShoulder * RightVec;

    FreeDist = t_camDist;
    if ( Trace( HitLoc, HitNormal, Anchor - t_camDist * Dir, Anchor, false, vect(10,10,10) ) != None )
        FreeDist = FMax( 0.0, FMin( ((Anchor - HitLoc) Dot Dir) - 8.0, t_camDist ) );

    if ( FreeDist > tp_fp_out )
        t_fpLock = false;
}

function TP_SetCamParams( float dt )
{
    local float D, S, H;

    // (bFreeCamera is maintained per-tick in PlayerTick so vehicles get the
    // stock value again — see the comment there.)

    if ( bTPAim )
    {
        D = tp_aim_dist;
        S = tp_aim_shoulder;
        H = tp_aim_height;
    }
    else if ( tp_autoadjust && (Pawn != None) && Pawn.bIsCrouched )
    {
        D = tp_crouch_dist;
        S = tp_crouch_shoulder;
        H = tp_crouch_height;
    }
    else
    {
        D = tp_dist;
        S = tp_shoulder;
        H = tp_height;
    }

    t_camDist     = TP_FEase( t_camDist,     D, dt );
    t_camShoulder = TP_FEase( t_camShoulder, S, dt );
    t_camHeight   = TP_FEase( t_camHeight,   H, dt );
}

function float TP_FEase( float Current, float Target, float dt )
{
    if ( tp_easetime <= 0.01 )
        return Target;
    return Current + (Target - Current) * FMin( 1.0, dt / tp_easetime );
}

// ---------------------------------------------------------------------------
// shots
// ---------------------------------------------------------------------------

// Conditions under which the third person convergence aim is active (shots
// are aimed at the point the camera ray hits, t_aimPoint).
simulated function bool TP_ShootConvergence()
{
    return tp_enable && bBehindView && !t_fpLock && (Pawn != None)
           && (Vehicle(Pawn) == None) && (Pawn.Health > 0);
}

// ---------------------------------------------------------------------------
// AdjustAim: stock copy, with third person switching to crosshair convergence
// ---------------------------------------------------------------------------
// First person keeps the full stock behaviour (scanning/aiming help included).
// Third person returns the direction from the fire origin to the point the
// camera ray hit (t_aimPoint): the shot origin still is the pawn's muzzle/eye,
// but it is aimed AT the crosshair, so the shoulder offset and the look pitch
// cannot introduce parallax any more. This is the hl-thirdperson aim fix.
function rotator AdjustAim( FireProperties FiredAmmunition, vector projStart, int aimerror )
{
    local vector FireDir, AimSpot, HitNormal, HitLocation, OldAim, AimOffset;
    local actor BestTarget;
    local float bestAim, bestDist, projspeed;
    local actor HitActor;
    local bool bNoZAdjust, bLeading;
    local rotator AimRot;

    if ( TP_ShootConvergence() )
        return rotator( t_aimPoint - projStart );

    FireDir = vector(Rotation);
    if ( FiredAmmunition.bInstantHit )
        HitActor = Trace(HitLocation, HitNormal, projStart + 10000 * FireDir, projStart, true);
    else
        HitActor = Trace(HitLocation, HitNormal, projStart + 4000 * FireDir, projStart, true);
    if ( (HitActor != None) && HitActor.bProjTarget )
    {
        BestTarget = HitActor;
        bNoZAdjust = true;
        OldAim = HitLocation;
        BestDist = VSize(BestTarget.Location - Pawn.Location);
    }
    else
    {
        // adjust aim based on FOV
        bestAim = 0.90;
        if ( (Level.NetMode == NM_Standalone) && bAimingHelp )
        {
            bestAim = 0.93;
            if ( FiredAmmunition.bInstantHit )
                bestAim = 0.97;
            if ( FOVAngle < DefaultFOV - 8 )
                bestAim = 0.99;
        }
        else if ( FiredAmmunition.bInstantHit )
                bestAim = 1.0;

        if (Role == ROLE_Authority) // Allow for this function being called by mods on client. PickTarget is only available on server/instant action.
            BestTarget = PickTarget(bestAim, bestDist, FireDir, projStart, FiredAmmunition.MaxRange);

        if ( BestTarget == None )
            return Rotation;

        OldAim = projStart + FireDir * bestDist;
    }
    InstantWarnTarget(BestTarget,FiredAmmunition,FireDir);
    ShotTarget = Pawn(BestTarget);
    if ( !bAimingHelp || (Level.NetMode != NM_Standalone) )
        return Rotation;

    // aim at target - help with leading also
    if ( !FiredAmmunition.bInstantHit )
    {
        projspeed = FiredAmmunition.ProjectileClass.default.speed;
        BestDist = vsize(BestTarget.Location + BestTarget.Velocity * FMin(1, 0.02 + BestDist/projSpeed) - projStart);
        bLeading = true;
        FireDir  = BestTarget.Location + BestTarget.Velocity * FMin(1, 0.02 + BestDist/projSpeed) - projStart;
        AimSpot  = projStart + bestDist * Normal(FireDir);
        // if splash damage weapon, try aiming at feet - trace down to find floor
        if ( FiredAmmunition.bTrySplash
            && ((BestTarget.Velocity != vect(0,0,0)) || (BestDist > 1500)) )
        {
            HitActor = Trace(HitLocation, HitNormal, AimSpot - BestTarget.CollisionHeight * vect(0,0,2), AimSpot, false);
            if ( (HitActor != None)
                && FastTrace(HitLocation + vect(0,0,4),projstart) )
                return rotator(HitLocation + vect(0,0,6) - projStart);
        }
    }
    else
    {
        FireDir = BestTarget.Location - projStart;
        AimSpot = projStart + bestDist * Normal(FireDir);
    }
    AimOffset = AimSpot - OldAim;

    // adjust Z of shooter if necessary
    if ( bNoZAdjust || (bLeading && (Abs(AimOffset.Z) < BestTarget.CollisionHeight)) )
        AimSpot.Z = OldAim.Z;
    else if ( AimOffset.Z < 0 )
        AimSpot.Z = BestTarget.Location.Z + 0.4 * BestTarget.CollisionHeight;
    else
        AimSpot.Z = BestTarget.Location.Z - 0.7 * BestTarget.CollisionHeight;

    if ( !bLeading )
    {
        // if not leading, add slight random error ( significant at long distances )
        if ( !bNoZAdjust )
        {
            AimRot = rotator(AimSpot - projStart);
            if ( FOVAngle < DefaultFOV - 8 )
                AimRot.Yaw = AimRot.Yaw + 200 - Rand(400);
            else
                AimRot.Yaw = AimRot.Yaw + 375 - Rand(750);
            return AimRot;
        }
    }
    else if ( !FastTrace(projStart + 0.9 * bestDist * Normal(FireDir), projStart) )
    {
        FireDir = BestTarget.Location - projStart;
        AimSpot = projStart + bestDist * Normal(FireDir);
    }

    return rotator(AimSpot - projStart);
}

// ---------------------------------------------------------------------------
// console commands (bound by PostBeginPlay; all rebindingable)
// ---------------------------------------------------------------------------
exec function TP_Toggle()       // 1st <-> 3rd person
{
    if ( tp_enable )
        bBehindView = !bBehindView;
    if ( !bBehindView )
        t_fpLock = false;
}

exec function TP_SwapShoulder() // eased shoulder swap
{
    t_shoulderSign = -t_shoulderSign;
}

exec function TP_AimMode()      // tighter camera, body locked to the crosshair
{
    bTPAim = !bTPAim;
}

exec function TP_SetDist( float D )
{
    tp_dist = FClamp( D, 10.0, 3000.0 );
    SaveConfig();
    TP_SyncMirror();
}

exec function TP_SetShoulder( float S )
{
    tp_shoulder = FClamp( S, 0.0, 800.0 );
    SaveConfig();
    TP_SyncMirror();
}

exec function TP_SetHeight( float H )
{
    tp_height = FClamp( H, -200.0, 400.0 );
    SaveConfig();
    TP_SyncMirror();
}

exec function TP_SetTurnSpeed( float T )   // degrees per second
{
    tp_turnspeed = FClamp( T, 1.0, 10000.0 );
    SaveConfig();
    TP_SyncMirror();
}

exec function TP_SetCrouchDist( float D )
{
    tp_crouch_dist = FClamp( D, 10.0, 3000.0 );
    SaveConfig();
    TP_SyncMirror();
}

exec function TP_SetCrouchShoulder( float S )
{
    tp_crouch_shoulder = FClamp( S, 0.0, 800.0 );
    SaveConfig();
    TP_SyncMirror();
}

exec function TP_SetCrouchHeight( float H )
{
    tp_crouch_height = FClamp( H, -200.0, 400.0 );
    SaveConfig();
    TP_SyncMirror();
}

exec function TP_SetAimDist( float D )
{
    tp_aim_dist = FClamp( D, 10.0, 3000.0 );
    SaveConfig();
    TP_SyncMirror();
}

exec function TP_SetAimShoulder( float S )
{
    tp_aim_shoulder = FClamp( S, 0.0, 800.0 );
    SaveConfig();
    TP_SyncMirror();
}

exec function TP_SetAimHeight( float H )
{
    tp_aim_height = FClamp( H, -200.0, 400.0 );
    SaveConfig();
    TP_SyncMirror();
}

exec function TP_SetEaseTime( float E )
{
    tp_easetime = FMax( 0.0, E );
    SaveConfig();
    TP_SyncMirror();
}

exec function TP_Info()
{
    Log( "GTA-TP: enabled="$tp_enable
         $" dist="$tp_dist
         $" shoulder="$tp_shoulder
         $" height="$tp_height
         $" aim="$bTPAim
         $" bodyYaw="$t_bodyYaw
         $" bodyTarget="$t_bodyTargetYaw
         $" fpLock="$t_fpLock
         $" behind="$bBehindView );
}

// These 13 tunings have a second owner now: the mutator's Configure Mutators
// page (PlayInfo) edits the mutator's own config vars, and the mutator pushes
// them to this class on every map start (GTAThirdPersonMutator.TP_PushToController).
// To keep a console-command change from being reverted at the next map, every
// value exec also mirrors the change back into the mutator's class defaults
// (stock idiom, Engine/PlayerController.uc ~1674).
function TP_SyncMirror()
{
    class'GTAThirdPersonMutator'.default.tp_dist          = tp_dist;
    class'GTAThirdPersonMutator'.default.tp_shoulder      = tp_shoulder;
    class'GTAThirdPersonMutator'.default.tp_height        = tp_height;
    class'GTAThirdPersonMutator'.default.tp_turnspeed     = tp_turnspeed;
    class'GTAThirdPersonMutator'.default.tp_easetime      = tp_easetime;
    class'GTAThirdPersonMutator'.default.tp_autoadjust    = tp_autoadjust;
    class'GTAThirdPersonMutator'.default.tp_auto_fp       = tp_auto_fp;
    class'GTAThirdPersonMutator'.default.tp_crouch_dist   = tp_crouch_dist;
    class'GTAThirdPersonMutator'.default.tp_crouch_shoulder = tp_crouch_shoulder;
    class'GTAThirdPersonMutator'.default.tp_crouch_height = tp_crouch_height;
    class'GTAThirdPersonMutator'.default.tp_aim_dist      = tp_aim_dist;
    class'GTAThirdPersonMutator'.default.tp_aim_shoulder  = tp_aim_shoulder;
    class'GTAThirdPersonMutator'.default.tp_aim_height    = tp_aim_height;

    class'GTAThirdPersonMutator'.static.StaticSaveConfig();
}

// ============================================================================
// default values
// ============================================================================
defaultproperties
{
     tp_enable=True
     tp_dist=110.000000
     tp_shoulder=30.000000
     tp_height=0.000000
     tp_turnspeed=1373.000000
     tp_easetime=0.250000
     tp_autoadjust=True
     tp_crouch_dist=75.000000
     tp_crouch_shoulder=18.000000
     tp_crouch_height=12.000000
     tp_aim_dist=55.000000
     tp_aim_shoulder=14.000000
     tp_aim_height=0.000000
     tp_fire_lock=True
     tp_auto_fp=True
     tp_fp_in=20.000000
     tp_fp_out=35.000000
     tp_bindver=0
     tp_turnver=4
     tp_debug=False
     tp_autobind=True
}
