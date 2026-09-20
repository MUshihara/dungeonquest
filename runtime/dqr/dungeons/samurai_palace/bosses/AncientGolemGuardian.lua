return {
    Name="Ancient Golem Guardian",Room="room7",MaxHPObserved=425000000,
    Attacks={"golemRockThrow","golemRockThrowSmall","golemRockClap","rockshatter","rockExplosion","rockExplosionSmall"},
    Rules={
        "rockshatter tell begins ordinary lateral premove before the 9-line burst",
        "rockshatter local gap commits to one validated pocket while the wave remains valid",
        "main rock landing remains dangerous through the delayed rockExplosion handoff",
        "small rock landing zones remain dangerous through rockExplosionSmall",
        "do not repeatedly replan a still-safe shatter pocket",
    },
}
