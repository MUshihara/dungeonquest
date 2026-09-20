return {
    Name="Miyamoto Musashi",Room="bossRoom",RoomIndex=999,MaxHPObserved=467500000,
    ClientEvent="ReplicatedStorage.remotes.miyamotoClientEvents",
    ClientStates={"showFire","flameBeams","spinFlameShuriken","fireCyclone","endFireCyclone","hideFire"},
    Attacks={"flameShurikenHit","flameBeam","doubleFlameBeam","Flame Cyclone"},
    Rules={
        "observe client event only; never FireServer it",
        "flameBeams warning may trigger one short ordinary lateral premove",
        "flame/double-beam local gaps commit to one validated pocket until new geometry invalidates it",
        "Flame Cyclone is one moving radial hazard, not dozens of crescent threats",
        "endFireCyclone/hideFire suppress stale Cyclone recreation",
        "Ultimate Swordsman physical pressure participates in pocket validation",
        "keep boss as majority offensive target",
    },
}
