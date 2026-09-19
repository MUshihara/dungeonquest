return {
    Name="Miyamoto Musashi",Room="bossRoom",RoomIndex=999,MaxHPObserved=467500000,
    ClientEvent="ReplicatedStorage.remotes.miyamotoClientEvents",
    ClientStates={"showFire","flameBeams","spinFlameShuriken","fireCyclone","endFireCyclone","hideFire"},
    Attacks={"flameShurikenHit","flameBeam","doubleFlameBeam","Flame Cyclone"},
    Rules={
        "observe client event only; never FireServer it",
        "doubleFlameBeam uses hold/local-gap behavior",
        "dense doubleBeam + flameShuriken/flameBeam requires larger true clearance",
        "Ultimate Swordsman physical pressure participates in gap scoring",
        "keep boss as majority offensive target",
    },
}
