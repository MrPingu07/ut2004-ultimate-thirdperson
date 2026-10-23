//=============================================================================
// GTAPlayerController
//
// GTA San Andreas style third person camera for UT2004, mirroring the design
// of hl-thirdperson (GoldSrc). Mouse orbits the camera, movement is
// camera-relative (UE2 orients movement off the controller rotation natively),
// shots stay on the crosshair, and the body turns cosmetically towards the
// movement direction.
//
// How it works (verified against decompiled stock sources):
//  - Camera: PlayerCalcView() override. Movement input and weapon aim follow
//    the controller Rotation, so keeping Rotation as the camera rotation keeps
//    movement camera-relative and aiming crosshair-true for free.
//  - Shots: stock PlayerController.AdjustAim() returns Pawn.Rotation when
//    bBehindView (yaw only, pitch zeroed while walking). We return the
//    controller Rotation instead so shots keep their pitch at the crosshair.
//    The aims (target scanning / aiming help) stays stock.
//  - Body: UE2 rotates the pawn with the mouse (Pawn.FaceRotation with
//    controller rotation each tick). We keep that (movement stays camera
//    relative in every movement state) and instead rotate the root bone
//    ('Bip01') by the difference between the camera yaw and the desired body
//    facing? movement direction (or camera crosshair while firing / aiming).
//    Purely visual and client-side, exactly like hl-thirdperson.
//=============================================================================
class GTAPlayerController extends xPlayer
    config(GTAThirdPerson);

// ------ configurable values (UT2004.ini, [GTAThirdPerson.GTAPlayerController]) ------
var config bool  tp_enable;         // master switch (0 = stock first person)
var config float tp_dist;           // camera distance
var config float tp_shoulder;       // magnitude; sign sets side in every stance
var config float tp_height;         // vertical camera offset (positive up)
var config float tp_turnspeed;      // cosmetic body turn speed, rotator units per second
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
var config name  tp_bone;           // root bone used for the cosmetic yaw
var config int   tp_bonespace;      // SetBoneRotation space (1 = global)
var config int   tp_bindver;        // internal: version of the default binds already applied
var config bool  tp_debug;          // logs install details once per game (for playtesting)

// ------ runtime state ------
var transient bool  bTPAim;
var transient int   t_shoulderSign;      // +1 / -1
var transient float t_camDist, t_camShoulder, t_camHeight;
var transient float t_bodyYawOffset;
var transient float t_bodyTargetYaw;
var transient bool  t_bodyTargetValid;
var transient bool  t_fpLock;
var transient float t_lastCamCalc;
var transient bool  t_camLogged;

const TP_BINDVERSION = 1;

simulated event PostBeginPlay()
{
    Super.PostBeginPlay();

    // Default keybinds, applied once (hl-thirdperson style first-run binds).
    // Works directly in singleplayer/listen; overridden binds stay user-owned.
    if ( tp_bindver < TP_BINDVERSION )
    {
        ConsoleCommand("bind Z TP_Toggle");
        ConsoleCommand("bind X TP_SwapShoulder");
        ConsoleCommand("bind ALT TP_AimMode");
        tp_bindver = TP_BINDVERSION;
        SaveConfig();
    }
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
    t_bodyYawOffset   = 0.0;
    t_bodyTargetYaw   = Rotation.Yaw;
    t_bodyTargetValid = false;
    t_fpLock          = false;
    t_lastCamCalc     = Level.TimeSeconds;

    if ( tp_debug )
        Log( "GTA-TP: Possess pawn="$aPawn$" controller="$Class
             $" behind="$bBehindView$" enable="$tp_enable
             $" netmode="$Level.NetMode );
}

simulated event PlayerTick( float DeltaTime )
{
    Super.PlayerTick( DeltaTime );
    TP_UpdateTick( DeltaTime );
}

// ---------------------------------------------------------------------------
// cosmetic body + safety rerouting
// ---------------------------------------------------------------------------
function TP_UpdateTick( float dt )
{
    local Pawn P;

    P = Pawn;

    if ( P == None || !tp_enable )
    {
        return;
    }

    if ( Vehicle(P) != None || P.Health <= 0
         || P.Physics == PHYS_Ladder || P.Physics == PHYS_Spider )
    {
        // stock situations: cancel the cosmetic offset
        TP_ResetBody( P );
        return;
    }

    TP_UpdateBody( dt, P );
}

function TP_ResetBody( Pawn P )
{
    t_bodyYawOffset   = 0.0;
    t_bodyTargetValid = false;
    P.SetBoneRotation( tp_bone, rot(0,0,0), tp_bonespace, 1.0 );
}

function TP_UpdateBody( float dt, Pawn P )
{
    local float Step, Diff, HVel;
    local vector HV;
    local bool bLockBody;

    bLockBody = ( bTPAim || (tp_fire_lock && (P.PressingFire() || P.PressingAltFire())) );
    if ( bLockBody )
    {
        // body locked to the crosshair (tpaim or firing)
        t_bodyTargetYaw   = Rotation.Yaw;
        t_bodyTargetValid = true;
    }
    else
    {
        HV   = P.Velocity;
        HV.Z = 0;
        HVel = VSize(HV);
        if ( HVel > 40.0 )
        {
            // body turns towards the movement direction
            t_bodyTargetYaw   = rotator(HV).Yaw;
            t_bodyTargetValid = true;
        }
        // while idle the last target is kept, so the camera can orbit freely
    }

    if ( !t_bodyTargetValid )
    {
        t_bodyYawOffset = 0.0;
        TP_ApplyBody( P, 0.0 );
        return;
    }

    Diff = TP_YawShort( t_bodyTargetYaw - Rotation.Yaw );
    Step = FMax( 1.0, tp_turnspeed * dt );
    if ( Diff - t_bodyYawOffset > Step )
        t_bodyYawOffset += Step;
    else if ( Diff - t_bodyYawOffset < -Step )
        t_bodyYawOffset -= Step;
    else
        t_bodyYawOffset = Diff;

    TP_ApplyBody( P, t_bodyYawOffset );
}

function TP_ApplyBody( Pawn P, float YawOff )
{
    local rotator BodyRot;

    BodyRot.Pitch = 0;
    BodyRot.Yaw   = int(YawOff);
    BodyRot.Roll  = 0;
    P.SetBoneRotation( tp_bone, BodyRot, tp_bonespace, 1.0 );
}

function float TP_YawShort( float Diff )
{
    while ( Diff >  32768.0 ) Diff -= 65536.0;
    while ( Diff < -32768.0 ) Diff += 65536.0;
    return Diff;
}

// ---------------------------------------------------------------------------
// camera
// ---------------------------------------------------------------------------
event PlayerCalcView( out actor ViewActor, out vector CameraLocation, out rotator CameraRotation )
{
    if ( tp_enable && bBehindView && (ViewTarget == Pawn) && (Pawn != None)
         && !Pawn.bSpecialCalcView && (Vehicle(Pawn) == None)
         && !IsSpectating() && (Pawn.Health > 0) )
    {
        ViewActor      = Pawn;
        CameraLocation = Pawn.Location;
        TP_CalcCam( CameraLocation, CameraRotation );
        return;
    }

    // dead, spectating, vehicles, other view targets, or disabled: stock path
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
        if ( FreeDist < tp_fp_in )  t_fpLock = true;
        if ( FreeDist > tp_fp_out ) t_fpLock = false;
    }
    else
        t_fpLock = false;

    if ( t_fpLock )
    {
        // no room behind: stock first person until there is space again
        bBehindView = false;
        CalcFirstPersonView( CamLoc, CamRot );
        return;
    }
    bBehindView = true;

    CamLoc = Anchor - FreeDist * Dir;

    if ( tp_debug && !t_camLogged )
    {
        t_camLogged = true;
        Log( "GTA-TP: camera active dist="$t_camDist$
             " shoulder="$t_camShoulder$" height="$t_camHeight );
    }
}

function TP_SetCamParams( float dt )
{
    local float D, S, H;

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
// shots stay on the crosshair in third person
// ---------------------------------------------------------------------------
// Copy of the stock PlayerController.AdjustAim with one change: in third
// person it returned Pawn.Rotation (yaw only, pitch zeroed while walking),
// which put shots off the crosshair. We return the controller Rotation
// (the camera direction) instead. The aiming help (target scanning) is stock.
function rotator AdjustAim( FireProperties FiredAmmunition, vector projStart, int aimerror )
{
    local vector FireDir, AimSpot, HitNormal, HitLocation, OldAim, AimOffset;
    local actor BestTarget;
    local float bestAim, bestDist, projspeed;
    local actor HitActor;
    local bool bNoZAdjust, bLeading;
    local rotator AimRot;

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
}

exec function TP_SetShoulder( float S )
{
    tp_shoulder = FClamp( S, 0.0, 800.0 );
    SaveConfig();
}

exec function TP_SetHeight( float H )
{
    tp_height = FClamp( H, -200.0, 400.0 );
    SaveConfig();
}

exec function TP_SetTurnSpeed( float T )
{
    tp_turnspeed = FMax( 1.0, T );
    SaveConfig();
}

exec function TP_SetEaseTime( float E )
{
    tp_easetime = FMax( 0.0, E );
    SaveConfig();
}

exec function TP_Info()
{
    Log( "GTA-TP: enabled="$tp_enable
         $" dist="$tp_dist
         $" shoulder="$tp_shoulder
         $" height="$tp_height
         $" aim="$bTPAim
         $" bodyOff="$t_bodyYawOffset
         $" fpLock="$t_fpLock
         $" behind="$bBehindView
         $" bone="$tp_bone );
}

// ============================================================================
// default values
// ============================================================================
defaultproperties
{
     tp_enable=True
     tp_dist=110.000000
     tp_shoulder=20.000000
     tp_height=0.000000
     tp_turnspeed=3600.000000
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
     tp_bone=Bip01
     tp_bonespace=1
     tp_bindver=0
     tp_debug=False
}
