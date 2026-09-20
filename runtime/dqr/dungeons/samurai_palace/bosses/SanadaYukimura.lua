return {
    Name="Sanada Yukimura",Room="room4",MaxHPObserved=408000000,
    Attacks={"shurikenThrow","crossShuriken"},Adds={"Elite Swordsman"},
    Rules={
        "upper-floor transition owns movement until player and boss are on the same combat level",
        "boss hazards respect vertical separation and cannot control the lower floor",
        "hard boss-majority target",
        "crossShuriken pocket requires real edge clearance and rejects physical-add hard-pressure candidates before commit",
        "once a crossShuriken pocket is valid, commit to it for the wave and replan only if new geometry/add pressure invalidates it",
        "generic Samurai boss emergency shift is allowed only when the bounded shift endpoint reaches zero active geometry overlap",
        "crossShuriken pocket scoring preserves progress toward ~26-stud boss range",
    },
}
