return {
    Name="Sanada Yukimura",Room="room4",MaxHPObserved=408000000,
    Attacks={"shurikenThrow","crossShuriken"},Adds={"Elite Swordsman"},
    Rules={
        "upper-floor transition owns movement until player and boss are on the same combat level",
        "boss hazards respect vertical separation and cannot control the lower floor",
        "hard boss-majority target",
        "crossShuriken: hold only if geometry-safe, physical-add-safe, and inside the boss DPS envelope",
        "crossShuriken: route-safe local gap prefers progress toward ~26-stud boss range",
        "Elite Swordsman physical pressure participates in gap scoring",
    },
}
