return {
    Name = "Samurai Palace", Slug = "samurai_palace", LogSlug = "Samurai_Palace",
    UniverseId = 9931749389, BattlePlaceId = 85776757589518, FinalBossName = "Miyamoto Musashi",
    BossNames = {["Sanada Yukimura"]=true,["Ancient Golem Guardian"]=true,["Miyamoto Musashi"]=true},
    BossAddNames = {["Elite Swordsman"]=true,["Ultimate Swordsman"]=true},
    PhysicalEnemyNames = {["Samurai Swordsman"]=true,["Elite Swordsman"]=true,["Ultimate Swordsman"]=true},
    RangedPressureNames = {["Shuriken Thrower"]=true},
    Priorities = {
        Physical = {["Shuriken Thrower"]=185,["Samurai Swordsman"]=170,["Elite Swordsman"]=455,["Ultimate Swordsman"]=470,["Sanada Yukimura"]=320,["Ancient Golem Guardian"]=340,["Miyamoto Musashi"]=370},
        Tank = {["Shuriken Thrower"]=180,["Samurai Swordsman"]=170,["Elite Swordsman"]=455,["Ultimate Swordsman"]=470,["Sanada Yukimura"]=320,["Ancient Golem Guardian"]=340,["Miyamoto Musashi"]=370},
        Spell = {["Shuriken Thrower"]=190,["Samurai Swordsman"]=155,["Elite Swordsman"]=450,["Ultimate Swordsman"]=465,["Sanada Yukimura"]=320,["Ancient Golem Guardian"]=340,["Miyamoto Musashi"]=370},
    },
    Config = {TRANSIT_TWEEN_ENABLED=false, TELEPORT_GLOBAL_COOLDOWN=3.00},
    BossModules = {
        ["Sanada Yukimura"]="dungeons/samurai_palace/bosses/SanadaYukimura.lua",
        ["Ancient Golem Guardian"]="dungeons/samurai_palace/bosses/AncientGolemGuardian.lua",
        ["Miyamoto Musashi"]="dungeons/samurai_palace/bosses/MiyamotoMusashi.lua",
    },
}
