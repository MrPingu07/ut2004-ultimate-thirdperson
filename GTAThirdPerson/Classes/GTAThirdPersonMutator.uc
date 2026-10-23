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

    if ( Level.Game != None && bEnabled )
    {
        Level.Game.PlayerControllerClassName = "GTAThirdPerson.GTAPlayerController";
        Level.Game.PlayerControllerClass     = class'GTAThirdPerson.GTAPlayerController';

        TP_PushToController();
    }
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
// it to build the numeric edit boxes; floats need the ".:" form).
static function FillPlayInfo(PlayInfo PlayInfo)
{
    Super.FillPlayInfo(PlayInfo);

    PlayInfo.AddSetting( default.RulesGroup, "bEnabled",
                         "Mod on/off (installs the GTA third person controller)",
                         0, 1, "Check" );

    PlayInfo.AddSetting( "Camera on foot", "tp_dist",       "Camera distance",         0, 1, "Text", "8;10.0:3000.0" );
    PlayInfo.AddSetting( "Camera on foot", "tp_shoulder",   "Shoulder offset",         0, 1, "Text", "8;0.0:800.0" );
    PlayInfo.AddSetting( "Camera on foot", "tp_height",     "Camera height",           0, 1, "Text", "8;-200.0:400.0" );
    PlayInfo.AddSetting( "Camera on foot", "tp_turnspeed",  "Body turn speed (deg/s)", 0, 1, "Text", "8;1.0:4000.0" );
    PlayInfo.AddSetting( "Camera on foot", "tp_easetime",   "Pose easing time (s)",    0, 1, "Text", "8;0.0:2.0" );
    PlayInfo.AddSetting( "Camera on foot", "tp_autoadjust", "Use the crouch stance while crouching", 0, 1, "Check" );

    PlayInfo.AddSetting( "Aim stance (Alt)", "tp_aim_dist",     "Distance",    0, 1, "Text", "8;10.0:3000.0" );
    PlayInfo.AddSetting( "Aim stance (Alt)", "tp_aim_shoulder", "Shoulder",    0, 1, "Text", "8;0.0:800.0" );
    PlayInfo.AddSetting( "Aim stance (Alt)", "tp_aim_height",   "Height",      0, 1, "Text", "8;-200.0:400.0" );

    PlayInfo.AddSetting( "Crouch stance", "tp_crouch_dist",     "Distance",    0, 1, "Text", "8;10.0:3000.0" );
    PlayInfo.AddSetting( "Crouch stance", "tp_crouch_shoulder", "Shoulder",    0, 1, "Text", "8;0.0:800.0" );
    PlayInfo.AddSetting( "Crouch stance", "tp_crouch_height",   "Height",      0, 1, "Text", "8;-200.0:400.0" );

    PlayInfo.AddSetting( "First person", "tp_auto_fp",
                         "Switch to first person when there is no room behind",
                         0, 1, "Check" );
}

// The PlayInfo page resolves each property's display string through
// GetDescriptionText on its class (the mutator, here).
static event string GetDescriptionText(string PropName)
{
    if ( PropName == "bEnabled" )          return "Install the GTA third person controller";
    if ( PropName == "tp_dist" )           return "Camera distance behind the pawn (UU)";
    if ( PropName == "tp_shoulder" )       return "Sideways camera offset; side via TP_SwapShoulder";
    if ( PropName == "tp_height" )         return "Vertical camera offset (positive up)";
    if ( PropName == "tp_turnspeed" )      return "Body turn speed in degrees per second";
    if ( PropName == "tp_easetime" )       return "Easing time in seconds for shoulder/height/distance";
    if ( PropName == "tp_autoadjust" )     return "Use the crouch stance while crouching";
    if ( PropName == "tp_aim_dist" )       return "Aim mode camera distance (Alt)";
    if ( PropName == "tp_aim_shoulder" )   return "Aim mode shoulder offset";
    if ( PropName == "tp_aim_height" )     return "Aim mode camera height";
    if ( PropName == "tp_crouch_dist" )    return "Crouch camera distance";
    if ( PropName == "tp_crouch_shoulder") return "Crouch shoulder offset";
    if ( PropName == "tp_crouch_height" )  return "Crouch camera height";
    if ( PropName == "tp_auto_fp" )        return "Switch to first person when there is no room behind";
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
