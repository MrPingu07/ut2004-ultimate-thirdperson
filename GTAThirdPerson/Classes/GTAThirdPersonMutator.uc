// UT2004 Ultimate ThirdPerson — GTA San Andreas style third person camera.
// Copyright (C) 2026 MrPingu07
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the
// Free Software Foundation, version 3 of the License. See the LICENSE file
// at <https://github.com/mrpingu07/ut2004-ultimate-thirdperson> for details.
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
// or FITNESS FOR A PARTICULAR PURPOSE.
class GTAThirdPersonMutator extends Mutator
    config(GTAThirdPerson);

// Installs the GTA-style third person player controller for human players on
// any gametype. Bots keep the stock xBot controller and are untouched.
//
// Timing note (verified against Engine.GameInfo source): gametypes only set
// PlayerControllerClassName in their defaultproperties; mutators are spawned
// during InitGame and Login() resolves the class later, so it is safe
// (and persistent across all gametypes) to override here.
//
// In-game "Configure Mutators" page (round 9): GUI2K4.MutatorConfigMenu builds
// a PlayInfo from each mutator's static FillPlayInfo (verified in the exported
// GUI2K4 sources). The page can only edit properties of classes that are
// "Info" subclasses — PlayerController is not one, so AddClass(controller) is
// impossible; instead the settings are bound to THESE config vars (which also
// satisfies the page's MutatorHasProps()/bFoundMutatorSettings gates, since
// they require the mutator class to contribute settings of its own). On OK the
// native PlayInfo.SaveSettings() writes this ini section, and every map start
// TP_PushToController() applies the mirror to the controller class defaults
// (idiom verified in stock sources: class'X'.default.Y = v +
// class'X'.static.StaticSaveConfig(), Engine/PlayerController.uc ~1674).
// Ownership per map, after the one-time init: mutator values win, so the
// console commands (TP_SetDist & co) sync the mirror back (TP_SyncMirror) —
// otherwise a GUI edit would be silently reverted. Manual ini edits of these
// 13 keys in the controller section are therefore overwritten too.
//
// Once-only mirror init (TP_InitMirror): copies the controller's current
// class defaults (which already mirror its own ini values at load) and
// replicates the controller's turn/shoulder migration math when its ini is
// still pre-migration, so no user tuning is lost on the way in.
//
// Round 21 (TP_EnsureServerPackage): self-registers ServerPackages=
// GTAThirdPerson in the HOST's System/UT2004.ini ([Engine.GameEngine]) so a
// fresh host install advertised the package to joining clients without any
// manual ini editing. This was THE root cause of the long-running
// "joining client freezes" (rounds 14-20): with the line missing on the host,
// clients hard-froze mid-load, silently, before ANY client-side mod code ran
// (no seed line, no precache, no disconnect). Two hosts + swapped roles never
// joined until the line was added by hand on the host. UT2004 reads
// ServerPackages only at server startup, so a first-run append takes effect
// after the NEXT server start; we log that loudly.

var config bool  bEnabled;               // master: install the controller

// GUI mirror of the camera values (owner: GTAPlayerController's ini)
var config float tp_dist, tp_shoulder, tp_height, tp_turnspeed, tp_easetime;
var config bool  tp_autoadjust, tp_auto_fp;
var config float tp_crouch_dist, tp_crouch_shoulder, tp_crouch_height;
var config float tp_aim_dist, tp_aim_shoulder, tp_aim_height;
var config int   tp_cfgver;              // one-time mirror init marker

const TP_MIRRORVER = 1;

function PostBeginPlay()
{
    Super.PostBeginPlay();

    if ( tp_cfgver < TP_MIRRORVER )
        TP_InitMirror();

    // Round 21: make the host ini advertise the package (see class comment).
    if ( bEnabled )
        TP_EnsureServerPackage();

    if ( Level.Game != None && bEnabled )
    {
        Level.Game.PlayerControllerClassName = "GTAThirdPerson.GTAPlayerController";
        Level.Game.PlayerControllerClass     = class'GTAThirdPerson.GTAPlayerController';

        TP_PushToController();
    }
}

// Appends ServerPackages=GTAThirdPerson to [Engine.GameEngine] in the host's
// UT2004.ini if absent. Writes the class's config defaults via
// StaticSaveConfig() (same idiom TP_PushToController uses). Takes effect on
// the NEXT server start, because UT2004 reads ServerPackages only at startup.
function TP_EnsureServerPackage()
{
    local class<GameEngine> GE;
    local int i;

    GE = class'Engine.GameEngine';
    for ( i = 0; i < GE.default.ServerPackages.Length; i++ )
        if ( GE.default.ServerPackages[i] ~= "GTAThirdPerson" )
            return;

    i = GE.default.ServerPackages.Length;
    GE.default.ServerPackages[i] = "GTAThirdPerson";
    GE.static.StaticSaveConfig();
    Log( "GTA-TP: host UT2004.ini had no ServerPackages=GTAThirdPerson — appended under [Engine.GameEngine]" );
    Log( "GTA-TP: UT2004 reads ServerPackages only at server startup — RESTART the game (clients froze at join without it: rounds 14-20)" );
}

// One-time copy of the controller's tunings into this ini's mirror, with the
// controller's own in-place migrations replicated when its ini is older
// (same math as GTAPlayerController.PostBeginPlay; see TP_CFGVERSION there).
function TP_InitMirror()
{
    tp_dist          = class'GTAPlayerController'.default.tp_dist;
    tp_shoulder      = class'GTAPlayerController'.default.tp_shoulder;
    tp_height        = class'GTAPlayerController'.default.tp_height;
    tp_turnspeed     = class'GTAPlayerController'.default.tp_turnspeed;
    tp_easetime      = class'GTAPlayerController'.default.tp_easetime;
    tp_autoadjust    = class'GTAPlayerController'.default.tp_autoadjust;
    tp_auto_fp       = class'GTAPlayerController'.default.tp_auto_fp;
    tp_crouch_dist     = class'GTAPlayerController'.default.tp_crouch_dist;
    tp_crouch_shoulder = class'GTAPlayerController'.default.tp_crouch_shoulder;
    tp_crouch_height   = class'GTAPlayerController'.default.tp_crouch_height;
    tp_aim_dist        = class'GTAPlayerController'.default.tp_aim_dist;
    tp_aim_shoulder    = class'GTAPlayerController'.default.tp_aim_shoulder;
    tp_aim_height      = class'GTAPlayerController'.default.tp_aim_height;

    if ( class'GTAPlayerController'.default.tp_turnver < 3 )
        tp_turnspeed = FClamp( tp_turnspeed / 182.044444, 1.0, 2000.0 );
    if ( class'GTAPlayerController'.default.tp_turnver < 4 )
        tp_shoulder = 30.0;

    tp_cfgver = TP_MIRRORVER;
    SaveConfig();
}

// Applies the mirror to the controller class's config defaults and ini. Must
// run before any player logs in, because the controller instance then loads
// exactly those values from [GTAThirdPerson.GTAPlayerController].
function TP_PushToController()
{
    class'GTAPlayerController'.default.tp_dist          = tp_dist;
    class'GTAPlayerController'.default.tp_shoulder      = tp_shoulder;
    class'GTAPlayerController'.default.tp_height        = tp_height;
    class'GTAPlayerController'.default.tp_turnspeed     = tp_turnspeed;
    class'GTAPlayerController'.default.tp_easetime      = tp_easetime;
    class'GTAPlayerController'.default.tp_autoadjust    = tp_autoadjust;
    class'GTAPlayerController'.default.tp_auto_fp       = tp_auto_fp;
    class'GTAPlayerController'.default.tp_crouch_dist   = tp_crouch_dist;
    class'GTAPlayerController'.default.tp_crouch_shoulder = tp_crouch_shoulder;
    class'GTAPlayerController'.default.tp_crouch_height = tp_crouch_height;
    class'GTAPlayerController'.default.tp_aim_dist      = tp_aim_dist;
    class'GTAPlayerController'.default.tp_aim_shoulder  = tp_aim_shoulder;
    class'GTAPlayerController'.default.tp_aim_height    = tp_aim_height;

    // mark the controller's own migration consumed; the pushed values are
    // already converted, and its migration branch must not run over them
    class'GTAPlayerController'.default.tp_turnver = 4;

    class'GTAPlayerController'.static.StaticSaveConfig();
}

// PlayInfo support: the Configure Mutators page shows these controls. The
// extras format is "decimals;min:max" (verified in AddRule, the native reads
// it to build the numeric edit boxes; floats need the ".:" form). Deliberately
// trimmed to the ten simple values, labels carry the stance name — turn speed,
// easing time, crouch-toggle and the master switch stay console/ini-only.
static function FillPlayInfo(PlayInfo PlayInfo)
{
    Super.FillPlayInfo(PlayInfo);

    PlayInfo.AddSetting( default.RulesGroup, "tp_dist",           "Regular Dist",     0, 1, "Text", "8;10.0:3000.0" );
    PlayInfo.AddSetting( default.RulesGroup, "tp_shoulder",       "Regular Shoulder", 0, 1, "Text", "8;0.0:800.0" );
    PlayInfo.AddSetting( default.RulesGroup, "tp_height",         "Regular Height",   0, 1, "Text", "8;-200.0:400.0" );

    PlayInfo.AddSetting( default.RulesGroup, "tp_aim_dist",       "Aim Dist",         0, 1, "Text", "8;10.0:3000.0" );
    PlayInfo.AddSetting( default.RulesGroup, "tp_aim_shoulder",   "Aim Shoulder",     0, 1, "Text", "8;0.0:800.0" );
    PlayInfo.AddSetting( default.RulesGroup, "tp_aim_height",     "Aim Height",       0, 1, "Text", "8;-200.0:400.0" );

    PlayInfo.AddSetting( default.RulesGroup, "tp_crouch_dist",    "Crouch Dist",      0, 1, "Text", "8;10.0:3000.0" );
    PlayInfo.AddSetting( default.RulesGroup, "tp_crouch_shoulder","Crouch Shoulder",  0, 1, "Text", "8;0.0:800.0" );
    PlayInfo.AddSetting( default.RulesGroup, "tp_crouch_height",  "Crouch Height",    0, 1, "Text", "8;-200.0:400.0" );

    PlayInfo.AddSetting( default.RulesGroup, "tp_auto_fp", "AutoFP", 0, 1, "Check" );
}

// The PlayInfo page resolves each property's description text through
// GetDescriptionText on its class (the mutator, here).
static event string GetDescriptionText(string PropName)
{
    if ( PropName == "tp_dist" )           return "Camera distance behind the pawn (UU)";
    if ( PropName == "tp_shoulder" )       return "Sideways offset for the regular stance (side via TP_SwapShoulder)";
    if ( PropName == "tp_height" )         return "Vertical camera offset for the regular stance (positive up)";
    if ( PropName == "tp_aim_dist" )       return "Camera distance in aim mode (Alt)";
    if ( PropName == "tp_aim_shoulder" )   return "Sideways camera offset in aim mode";
    if ( PropName == "tp_aim_height" )     return "Vertical camera offset in aim mode";
    if ( PropName == "tp_crouch_dist" )    return "Camera distance while crouched";
    if ( PropName == "tp_crouch_shoulder" )return "Sideways camera offset while crouched";
    if ( PropName == "tp_crouch_height" )  return "Vertical camera offset while crouched";
    if ( PropName == "tp_auto_fp" )        return "Switch to first person automatically when there is no room behind";
    return Super.GetDescriptionText(PropName);
}

defaultproperties
{
    bEnabled=True
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
    tp_auto_fp=True
    tp_cfgver=0
}
