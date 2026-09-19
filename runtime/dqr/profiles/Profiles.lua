-- DQR modular runtime: profiles/Profiles.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Style profiles
-- ============================================================

STYLES = {
    Physical = {
        DesiredRange = CFG.PHYSICAL_RANGE,
        AbilityRange = CFG.PHYSICAL_ABILITY_RANGE,
        BasicRange = CFG.BASIC_SWING_RANGE_PHYSICAL,

        -- Physical should still dodge aggressively.
        EnemyBuffer = 7.0,

        -- Dangerous ranged mobs first.
        Priority = {
            ["Shuriken Thrower"] = 185,
            ["Samurai Swordsman"] = 170,
            ["Elite Swordsman"] = 455,
            ["Ultimate Swordsman"] = 470,

            ["Sanada Yukimura"] = 320,
            ["Ancient Golem Guardian"] = 340,
            ["Miyamoto Musashi"] = 370,

            -- Dormant Underworld reference priorities.
            ["Elder Dark Mage"] = 140,
            ["Dark Mage"] = 130,
            ["Demon Warrior"] = 170,
            ["Blood Minion"] = 460,
            ["Demonic Overgrowth"] = 300,
            ["Kolvumar"] = 300,
            ["Demon Lord Azrallik"] = 350,
            ["Azrallik's Heart"] = 360,
        },
    },

    Tank = {
        DesiredRange = CFG.TANK_RANGE,
        AbilityRange = CFG.TANK_ABILITY_RANGE,
        BasicRange = CFG.BASIC_SWING_RANGE_TANK,
        EnemyBuffer = 5.5,

        Priority = {
            ["Shuriken Thrower"] = 180,
            ["Samurai Swordsman"] = 170,
            ["Elite Swordsman"] = 455,
            ["Ultimate Swordsman"] = 470,

            ["Sanada Yukimura"] = 320,
            ["Ancient Golem Guardian"] = 340,
            ["Miyamoto Musashi"] = 370,

            ["Elder Dark Mage"] = 135,
            ["Dark Mage"] = 125,
            ["Demon Warrior"] = 170,
            ["Blood Minion"] = 460,
            ["Demonic Overgrowth"] = 300,
            ["Kolvumar"] = 300,
            ["Demon Lord Azrallik"] = 350,
            ["Azrallik's Heart"] = 360,
        },
    },

    Spell = {
        DesiredRange = CFG.SPELL_RANGE,
        AbilityRange = CFG.SPELL_ABILITY_RANGE,
        BasicRange = CFG.BASIC_SWING_RANGE_SPELL,
        EnemyBuffer = 10.0,

        Priority = {
            ["Shuriken Thrower"] = 190,
            ["Samurai Swordsman"] = 155,
            ["Elite Swordsman"] = 450,
            ["Ultimate Swordsman"] = 465,

            ["Sanada Yukimura"] = 320,
            ["Ancient Golem Guardian"] = 340,
            ["Miyamoto Musashi"] = 370,

            ["Elder Dark Mage"] = 145,
            ["Dark Mage"] = 135,
            ["Demon Warrior"] = 150,
            ["Blood Minion"] = 450,
            ["Demonic Overgrowth"] = 300,
            ["Kolvumar"] = 300,
            ["Demon Lord Azrallik"] = 350,
            ["Azrallik's Heart"] = 360,
        },
    },
}

Profile = STYLES[CFG.STYLE] or STYLES.Physical



if DQR_WORLD and type(DQR_WORLD.Priorities) == "table" then
    for styleName, priorities in pairs(DQR_WORLD.Priorities) do
        local style = STYLES[styleName]
        if style and type(priorities) == "table" then
            for enemyName, weight in pairs(priorities) do
                style.Priority[enemyName] = weight
            end
        end
    end
end
Profile = STYLES[CFG.STYLE] or STYLES.Physical
