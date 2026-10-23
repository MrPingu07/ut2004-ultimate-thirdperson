class GTAThirdPersonMutator extends Mutator;

// Installs the GTA-style third person player controller for human players on
// any gametype. Bots keep the stock xBot controller and are untouched.
//
// Timing note (verified against Engine.GameInfo source): gametypes only set
// PlayerControllerClassName in their defaultproperties; mutators are spawned
// during InitGame and Login() resolves the class later, so it is safe
// (and persistent across all gametypes) to override here.

function PostBeginPlay()
{
    Super.PostBeginPlay();

    if ( Level.Game != None )
    {
        Level.Game.PlayerControllerClassName = "GTAThirdPerson.GTAPlayerController";
        Level.Game.PlayerControllerClass     = class'GTAThirdPerson.GTAPlayerController';
    }
}
