return {
    Name="Ancient Golem Guardian",Room="room7",MaxHPObserved=425000000,
    Attacks={"golemRockThrow","golemRockThrowSmall","rockExplosion","rockExplosionSmall","rockshatter"},
    AnimationTells={RockThrow="rbxassetid://119729303097590",RockShatter="rbxassetid://94282152705851"},
    RockShatterObservedDelay={1.25,1.61},
    Rules={"predict rockshatter from Action animation","normal lateral premove first","solve live 9-line batch with a local gap","do not walk back into delayed explosions"},
}
