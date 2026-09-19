return {
    Name="Demon Lord Azrallik",Room="bossRoom",RoomIndex=999,
    Attacks={"horizontalBeam","azrallikPunch","azrallikPunchSpread","fingerBlastHit"},
    AnimationTells={Finger="rbxassetid://106525745261065",PunchSpread="rbxassetid://130043568559097"},
    ObservedTellDelays={Finger=1.03,PunchSpread=2.52},
    Rules={"Heart is mandatory phase objective","horizontal beam exact safe lane","Finger proactive normal movement","PunchSpread hold/local-gap","direct Azrallik shifts suppressed"},
}
