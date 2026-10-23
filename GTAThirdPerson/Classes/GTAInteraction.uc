//=============================================================================
// GTAInteraction
//
// Local interaction drawing the third person reticle for GTAThirdPerson.
//
// Registered through the viewport (Engine.Player) InteractionMaster:
//
//     Player.InteractionMaster.AddInteraction(
//         "GTAThirdPerson.GTAInteraction", Player );
//
// It only ever renders while the GTAPlayerController says so
// (TP_WantsReticle): a small black-outlined white dot at the exact world point
// where the camera ray (and therefore the shot convergence ray) ends, replacing
// the stock centred crosshair, which the controller hides while this overlay is
// active. Interactions persist across map changes, so the controller only ever
// adds one instance (it scans LocalInteractions for this class first).
//=============================================================================
class GTAInteraction extends Interaction;

simulated event Initialized()
{
    Super.Initialized();
    bActive  = true;
    bVisible = true;
}

function PostRender( Canvas C )
{
    local GTAPlayerController PC;
    local vector AimPoint, Screen, ToAim;
    local float  DotOuter, DotInner;

    if ( ViewportOwner == None )
        return;

    PC = GTAPlayerController( ViewportOwner.Actor );
    if ( PC == None || !PC.TP_WantsReticle( AimPoint ) )
        return;

    // WorldToScreen wraps on points behind the camera, so skip them using the
    // camera origin the controller stored with the last view (HudBase
    // DrawTargeting does the same dot-product visibility check).
    ToAim = AimPoint - PC.t_camOrigin;
    if ( ToAim Dot vector(PC.Rotation) <= 0.0 )
        return;

    Screen = C.WorldToScreen( AimPoint );

    // black and white dot reticle: white centre, black outline (square tiles of
    // the pure-white stock texture — the same pattern Canvas itself uses to
    // draw solid boxes)
    DotOuter = FMax( 5.0, float(C.SizeX) / 320.0 );
    DotInner = DotOuter * 0.55;

    // black outline
    C.SetPos( Screen.X - DotOuter * 0.5, Screen.Y - DotOuter * 0.5 );
    C.SetDrawColor( 0, 0, 0, 255 );
    C.DrawTile( Texture'Engine.WhiteSquareTexture', DotOuter, DotOuter, 0.0, 0.0, 2.0, 2.0 );

    // white centre
    C.SetPos( Screen.X - DotInner * 0.5, Screen.Y - DotInner * 0.5 );
    C.SetDrawColor( 255, 255, 255, 255 );
    C.DrawTile( Texture'Engine.WhiteSquareTexture', DotInner, DotInner, 0.0, 0.0, 2.0, 2.0 );
}

defaultproperties
{
     bActive=True
     bVisible=True
}
