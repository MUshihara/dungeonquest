return {
    Name="Sanada Yukimura",Room="room4",MaxHPObserved=408000000,
    Attacks={"shurikenThrow","crossShuriken"},Adds={"Elite Swordsman"},
    Rules={
        "hard boss-majority target",
        "crossShuriken: hold only if geometry-safe AND physical-add-safe",
        "crossShuriken: nearest route-safe local gap if inside/pressured",
        "Elite Swordsman physical pressure participates in gap scoring",
    },
}
