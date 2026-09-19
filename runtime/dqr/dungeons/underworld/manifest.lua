return {
    Name="The Underworld",Slug="underworld",LogSlug="Underworld",
    UniverseId=9931749389,BattlePlaceId=85776757589518,FinalBossName="Demon Lord Azrallik",
    BossNames={["Demonic Overgrowth"]=true,["Kolvumar"]=true,["Demon Lord Azrallik"]=true},
    BossAddNames={["Blood Minion"]=true,["Azrallik's Heart"]=true},
    PhysicalEnemyNames={["Demon Warrior"]=true,["Blood Minion"]=true},
    RangedPressureNames={["Dark Mage"]=true,["Elder Dark Mage"]=true},
    Priorities={
        Physical={["Elder Dark Mage"]=140,["Dark Mage"]=130,["Demon Warrior"]=170,["Blood Minion"]=460,["Demonic Overgrowth"]=300,["Kolvumar"]=300,["Demon Lord Azrallik"]=350,["Azrallik's Heart"]=360},
        Tank={["Elder Dark Mage"]=135,["Dark Mage"]=125,["Demon Warrior"]=170,["Blood Minion"]=460,["Demonic Overgrowth"]=300,["Kolvumar"]=300,["Demon Lord Azrallik"]=350,["Azrallik's Heart"]=360},
        Spell={["Elder Dark Mage"]=145,["Dark Mage"]=135,["Demon Warrior"]=150,["Blood Minion"]=450,["Demonic Overgrowth"]=300,["Kolvumar"]=300,["Demon Lord Azrallik"]=350,["Azrallik's Heart"]=360},
    },
    Config={TRANSIT_TWEEN_ENABLED=false,TELEPORT_GLOBAL_COOLDOWN=3.00},
    BossModules={
        ["Demonic Overgrowth"]="dungeons/underworld/bosses/DemonicOvergrowth.lua",
        ["Kolvumar"]="dungeons/underworld/bosses/Kolvumar.lua",
        ["Demon Lord Azrallik"]="dungeons/underworld/bosses/DemonLordAzrallik.lua",
    },
}
