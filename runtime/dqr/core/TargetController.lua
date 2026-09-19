-- DQR modular runtime: core/TargetController.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Proactive physical/melee classification
-- ============================================================

PHYSICAL_ENEMY_NAMES = {
    ["Samurai Swordsman"] = true,
    ["Elite Swordsman"] = true,
    ["Ultimate Swordsman"] = true,

    -- Dormant shared-engine reference names.
    ["Demon Warrior"] = true,
    ["Blood Minion"] = true,
}

BOSS_ENEMY_NAMES = {
    ["Sanada Yukimura"] = true,
    ["Ancient Golem Guardian"] = true,
    ["Miyamoto Musashi"] = true,

    ["Demonic Overgrowth"] = true,
    ["Kolvumar"] = true,
    ["Demon Lord Azrallik"] = true,
}

if DQR_WORLD then
    if type(DQR_WORLD.PhysicalEnemyNames) == "table" then
        PHYSICAL_ENEMY_NAMES = DQR_WORLD.PhysicalEnemyNames
    end
    if type(DQR_WORLD.BossNames) == "table" then
        BOSS_ENEMY_NAMES = DQR_WORLD.BossNames
    end
end

KOLVUMAR_DIRECT_ATTACK_ANIMS = {
    ["rbxassetid://89702140030707"] = true,
}

DEMON_WARRIOR_ATTACK_ANIMS = {
    ["rbxassetid://107260711747781"] = true,
}

function isPhysicalEnemyModel(model)
    return model ~= nil and PHYSICAL_ENEMY_NAMES[model.Name] == true
end

function physicalThreatRelevantForMovement(
    enemy,
    point
)
    if enemyRelevantForEncounter(enemy) then
        return true
    end

    -- A future room-999 Blood Minion must never steal the target before the
    -- final encounter, but if it is already close enough to physically hit the
    -- player it must still affect movement.
    if enemy
        and enemy.Model
        and enemy.Model.Name == "Blood Minion"
        and enemy.Root
        and point
    then
        return
            horizontalDistance(
                point,
                enemy.Root.Position
            )
            <= CFG.BLOOD_MINION_GLOBAL_PRESSURE_RADIUS
    end

    return false
end


function physicalClosingInfo(enemy, point)
    if not enemy or not enemy.Root or not Runtime.Root then
        return CFG.MELEE_SOFT_RADIUS, 0, math.huge
    end

    local enemyPos = enemy.Root.Position
    local dist = horizontalDistance(point, enemyPos)
    local away = unitHorizontal(point - enemyPos)

    local enemyVel = horizontal(enemy.Root.AssemblyLinearVelocity)
    local playerVel = horizontal(Runtime.Root.AssemblyLinearVelocity)

    -- Positive = enemy is closing the distance.
    local closing = (enemyVel - playerVel):Dot(away)

    local bonus =
        math.clamp(
            math.max(closing, 0) * CFG.MELEE_DYNAMIC_HORIZON,
            0,
            CFG.MELEE_DYNAMIC_MAX_BONUS
        )

    local baseRadius = CFG.MELEE_SOFT_RADIUS
    local panicRadius = CFG.MELEE_PANIC_RADIUS

    if enemy.Model and enemy.Model.Name == "Blood Minion" then
        baseRadius = CFG.BLOOD_MINION_SOFT_RADIUS
        panicRadius = CFG.BLOOD_MINION_CRITICAL_RADIUS
    end

    local survivalBonus = 0

    if CFG.ADAPTIVE_SURVIVAL
        and Runtime.Humanoid
    then
        local hpRatio =
            Runtime.Humanoid.MaxHealth > 0
            and (
                Runtime.Humanoid.Health
                / Runtime.Humanoid.MaxHealth
            )
            or 1

        if Runtime.FragileMode
            or hpRatio <= CFG.LOW_HEALTH_RATIO
        then
            survivalBonus =
                CFG.FRAGILE_PHYSICAL_RADIUS_BONUS
        end
    end

    local radius =
        baseRadius
        + bonus
        + survivalBonus

    local timeToContact = math.huge
    if closing > 0.5 then
        timeToContact =
            math.max(0, dist - panicRadius) / closing
    end

    return radius, closing, timeToContact
end

function nearestPhysicalEnemy(point)
    local best, bestDist

    for _, enemy in ipairs(livingEnemies()) do
        if enemy.Root
            and enemy.Root.Parent
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and isPhysicalEnemyModel(enemy.Model)
            and physicalThreatRelevantForMovement(
                enemy,
                point
            )
        then
            local d = horizontalDistance(point, enemy.Root.Position)

            if not bestDist or d < bestDist then
                best = enemy
                bestDist = d
            end
        end
    end

    return best, bestDist or math.huge
end

function physicalEnemiesNear(point, radius)
    local out = {}

    for _, enemy in ipairs(livingEnemies()) do
        if enemy.Root
            and enemy.Root.Parent
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and isPhysicalEnemyModel(enemy.Model)
            and physicalThreatRelevantForMovement(
                enemy,
                point
            )
        then
            local d = horizontalDistance(point, enemy.Root.Position)

            if d <= radius then
                out[#out + 1] = {
                    Enemy = enemy,
                    Distance = d,
                }
            end
        end
    end

    return out
end

Runtime.ShortSkillOpportunity = function()
    if not CFG.SHORT_SKILL_STAGING_ENABLED
        or not Runtime.Root
        or not Runtime.Target
        or not Runtime.TargetRoot
        or not Runtime.TargetHumanoid
        or Runtime.TargetHumanoid.Health <= 0
        or Runtime.DodgeActive
        or Runtime.BossWave
        or activeThreatCount() > 0
    then
        return nil
    end

    if isPhysicalEnemyModel(Runtime.Target) then
        return nil
    end

    local char = Runtime.Character
    if not char then
        return nil
    end

    local busy = char:FindFirstChild("busyCasting")
    if busy and busy.Value == true then
        return nil
    end

    local now = os.clock()
    local tool = Runtime.ShortSkillTool

    if not tool
        or not tool.Parent
        or now - Runtime.LastShortSkillToolProbe
            >= CFG.SHORT_SKILL_TOOL_REFRESH
    then
        Runtime.LastShortSkillToolProbe = now
        tool = nil

        local backpack =
            LP:FindFirstChild("Backpack")

        for _, container in ipairs({
            backpack,
            char,
        }) do
            if container then
                for _, candidate in ipairs(
                    container:GetChildren()
                ) do
                    if candidate:IsA("Tool") then
                        local slotValue =
                            candidate:FindFirstChild(
                                "abilitySlot"
                            )

                        if slotValue
                            and tostring(slotValue.Value)
                                == CFG.SHORT_SKILL_STAGING_SLOT
                        then
                            tool = candidate
                            break
                        end
                    end
                end
            end

            if tool then
                break
            end
        end

        Runtime.ShortSkillTool = tool
    end

    if not tool
        or not tool:FindFirstChild("localEvent")
    then
        return nil
    end

    local readyAt =
        Runtime.LastAbilityCast[CFG.SHORT_SKILL_STAGING_SLOT]
        or -math.huge

    if now < readyAt then
        return nil
    end

    local cooldown = tool:FindFirstChild("cooldown")

    if cooldown
        and tonumber(cooldown.Value)
        and cooldown.Value > 0
    then
        return nil
    end

    local abilityRange =
        CFG.ABILITY_RANGE_HINTS[tool.Name]
        or Profile.AbilityRange

    for _, attributeName in ipairs({
        "Range",
        "range",
        "CastRange",
        "castRange",
        "AbilityRange",
        "abilityRange",
    }) do
        local ok, value =
            pcall(function()
                return tool:GetAttribute(attributeName)
            end)

        if ok
            and type(value) == "number"
            and value > 0
        then
            abilityRange = value
            break
        end
    end

    if abilityRange > CFG.SHORT_SKILL_MAX_RANGE then
        return nil
    end

    local hpRatio =
        Runtime.Humanoid
        and Runtime.Humanoid.MaxHealth > 0
        and (
            Runtime.Humanoid.Health
            / Runtime.Humanoid.MaxHealth
        )
        or 1

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            Runtime.TargetRoot.Position
        )

    if Runtime.ActiveBossName then
        if not CFG.SHORT_SKILL_BOSS_ALLOW[Runtime.ActiveBossName] then
            return nil
        end

        if Runtime.FragileMode
            or hpRatio < CFG.SHORT_SKILL_BOSS_MIN_HP_RATIO
            or distance > CFG.SHORT_SKILL_BOSS_START_DISTANCE
        then
            return nil
        end
    else
        if hpRatio < CFG.SHORT_SKILL_NORMAL_MIN_HP_RATIO
            or distance > CFG.SHORT_SKILL_NORMAL_START_DISTANCE
        then
            return nil
        end

        local physical, physicalDistance =
            nearestPhysicalEnemy(Runtime.Root.Position)

        if physical
            and physical.Model ~= Runtime.Target
            and physicalDistance
                <= CFG.SHORT_SKILL_PHYSICAL_GUARD_RADIUS
        then
            return nil
        end
    end

    local stageRange =
        math.max(
            6.0,
            abilityRange - CFG.SHORT_SKILL_STAGE_BUFFER
        )

    if now - Runtime.LastShortSkillStageLog
        >= CFG.SHORT_SKILL_STAGE_LOG_COOLDOWN
    then
        Runtime.LastShortSkillStageLog = now

        logKV("SHORT_SKILL_STAGE", {
            skill = tool.Name,
            distance = string.format("%.1f", distance),
            stage_range = string.format("%.1f", stageRange),
            boss = tostring(Runtime.ActiveBossName or "none"),
        })
    end

    return stageRange
end


Runtime.MageFreePressureActive = function()
    if not CFG.MAGE_FREE_PRESSURE_ENABLED
        or Runtime.ActiveBossName
        or not Runtime.Root
        or not Runtime.Target
        or not Runtime.TargetRoot
        or not Runtime.TargetHumanoid
        or Runtime.TargetHumanoid.Health <= 0
    then
        return false
    end

    local targetName =
        string.lower(
            tostring(
                Runtime.Target.Name
            )
        )

    if not (
        Runtime.IsRangedPressureName(
            Runtime.Target.Name
        )
        or string.find(
            targetName,
            "mage",
            1,
            true
        )
    ) then
        return false
    end

    local physical, physicalDistance =
        nearestPhysicalEnemy(
            Runtime.Root.Position
        )

    if physical
        and physicalDistance
            <= CFG.MAGE_FREE_PRESSURE_PHYSICAL_GUARD
    then
        return false
    end

    return true
end


function desiredRangeForTarget()
    if Runtime.MageFreePressureActive
        and Runtime.MageFreePressureActive()
    then
        return CFG.MAGE_FREE_PRESSURE_DESIRED_RANGE
    end

    local shortSkillRange =
        Runtime.ShortSkillOpportunity
        and Runtime.ShortSkillOpportunity()

    if shortSkillRange then
        return shortSkillRange
    end

    if Runtime.Target
        and Runtime.Target.Name == "Azrallik's Heart"
    then
        return CFG.AZRALLIK_HEART_ATTACK_RANGE
    end

    if Runtime.Target and CFG.BOSS_DESIRED_RANGE[Runtime.Target.Name] then
        return math.max(
            Profile.DesiredRange,
            CFG.BOSS_DESIRED_RANGE[Runtime.Target.Name]
        )
    end

    if CFG.PROACTIVE_MELEE_AVOIDANCE and Runtime.Target then
        if isPhysicalEnemyModel(Runtime.Target) then
            return math.max(Profile.DesiredRange, CFG.MELEE_TARGET_SKILL_RANGE)
        end

        -- If a physical mob is sharing the room, avoid diving to point-blank
        -- range on a mage just to basic-swing it.
        if Runtime.Root then
            local _, d = nearestPhysicalEnemy(Runtime.Root.Position)
            if d <= CFG.MELEE_SOFT_RADIUS + 8 then
                return math.max(Profile.DesiredRange, CFG.MELEE_TARGET_SKILL_RANGE)
            end
        end
    end

    local desired =
        Profile.DesiredRange

    if CFG.ADAPTIVE_SURVIVAL
        and Runtime.Humanoid
    then
        local hpRatio =
            Runtime.Humanoid.MaxHealth > 0
            and (
                Runtime.Humanoid.Health
                / Runtime.Humanoid.MaxHealth
            )
            or 1

        if Runtime.FragileMode then
            desired +=
                CFG.FRAGILE_RANGE_BONUS
        end

        if hpRatio <= CFG.LOW_HEALTH_RATIO then
            desired +=
                CFG.LOW_HEALTH_RANGE_BONUS
        end
    end

    return desired
end

function targetScore(enemy)
    if not Runtime.Root
        or not enemyRelevantForEncounter(enemy)
    then
        return -math.huge
    end

    local name = enemy.Model.Name
    local pri = Profile.Priority[name] or 80

    local dist =
        horizontalDistance(
            enemy.Root.Position,
            Runtime.Root.Position
        )

    -- V6: stacked mages were the largest remaining normal-room damage source.
    -- If multiple mages share the active room, prioritize deleting that red-line
    -- pressure instead of letting several synchronized casts build up.
    if Runtime.IsRangedPressureName(name)
        or name == "Dark Mage"
        or name == "Elder Dark Mage"
    then
        local mageCount = 0

        for _, other in ipairs(livingEnemies()) do
            if other.RoomIndex == enemy.RoomIndex
                and other.Model
                and (
                    Runtime.IsRangedPressureName(
                        other.Model.Name
                    )
                    or other.Model.Name == "Dark Mage"
                    or other.Model.Name == "Elder Dark Mage"
                )
            then
                mageCount += 1
            end
        end

        if mageCount >= 2 then
            pri += 70 + (mageCount - 2) * 20
        end
    end

    -- V7.2: if a normal physical enemy is already close enough to pin the
    -- player, kill it instead of endlessly kiting it while aiming at a distant
    -- mage. This is especially important near walls.
    if name == "Samurai Swordsman"
        or name == "Demon Warrior"
    then
        if dist <= 14 then
            pri += 1100
        elseif dist <= 20 then
            pri += 700
        elseif dist <= 26 then
            pri += 320
        end
    end

    -- V6 boss add rule: Blood Minions become the immediate target when they
    -- are close enough to pressure the player. Do not tunnel the boss while
    -- an add is already in its dangerous/lunge range.
    if Runtime.ActiveBossName == "Demon Lord Azrallik"
        and name == "Blood Minion"
        and enemy.RoomIndex == 999
        and dist <= CFG.BLOOD_MINION_ADD_PRIORITY_RANGE
    then
        pri += 1000
    end

    -- Higher room means progression, but never skip living current-room mobs.
    local roomBonus =
        enemy.RoomIndex == Runtime.CurrentRoomIndex
        and 35
        or 0

    local lowHpBonus =
        enemy.Humanoid.MaxHealth > 0
        and (1 - enemy.Humanoid.Health / enemy.Humanoid.MaxHealth) * 15
        or 0

    local maxHealthMillions =
        enemy.Humanoid.MaxHealth > 0
        and (
            enemy.Humanoid.MaxHealth
            / 1000000
        )
        or 0

    local strengthBonus =
        maxHealthMillions
            * CFG.TARGET_STRENGTH_MAXHP_WEIGHT
        + pri
            * CFG.TARGET_STRENGTH_PRIORITY_WEIGHT

    -- Distance is intentionally a weak tiebreaker now. The strongest relevant
    -- enemy in the active floor should not lose focus merely because another
    -- weaker enemy happens to be a few studs closer.
    return
        strengthBonus
        + roomBonus
        + lowHpBonus
        - dist * CFG.TARGET_DISTANCE_WEIGHT
end

function bossAddInterceptRange()
    if Runtime.FragileMode then
        return
            CFG.BOSS_ADD_INTERCEPT_FRAGILE_RANGE
    end

    return
        CFG.BOSS_ADD_INTERCEPT_RANGE
end

function clearBossAddFocus(reason)
    if Runtime.BossAddFocusModel then
        local now = os.clock()

        if now - Runtime.LastBossAddFocusLog
            >= CFG.BOSS_ADD_INTERCEPT_LOG_COOLDOWN
        then
            Runtime.LastBossAddFocusLog = now

            logKV("BOSS_ADD_FOCUS_END", {
                add =
                    Runtime.BossAddFocusModel.Name,
                reason = tostring(reason),
            })
        end
    end

    Runtime.BossAddFocusModel = nil
    Runtime.BossAddFocusStartedAt = nil
end

function chooseBossAddIntercept(enemies)
    if not CFG.BOSS_ADD_INTERCEPT_ENABLED
        or not Runtime.Root
        or not Runtime.ActiveBossName
        or Runtime.AzrallikHeartPhaseActive
    then
        clearBossAddFocus("disabled_or_phase")
        return nil
    end

    local now = os.clock()

    -- Continue only the CURRENT short burst.
    if Runtime.BossAddFocusModel
        and Runtime.BossAddFocusModel.Parent
        and now <= (
            Runtime.BossAddFocusUntil
            or -math.huge
        )
    then
        for _, enemy in ipairs(enemies) do
            if enemy.Model
                == Runtime.BossAddFocusModel
                and enemy.Humanoid
                and enemy.Humanoid.Health > 0
                and enemy.Root
            then
                local d =
                    horizontalDistance(
                        enemy.Root.Position,
                        Runtime.Root.Position
                    )

                if d
                    <= CFG.BOSS_ADD_INTERCEPT_RELEASE_RANGE
                then
                    return enemy
                end

                break
            end
        end
    end

    -- Burst ended: force boss focus for a real cooldown window.
    if Runtime.BossAddFocusModel then
        Runtime.BossAddCooldownUntil =
            math.max(
                Runtime.BossAddCooldownUntil
                    or -math.huge,
                now
                    + CFG.BOSS_ADD_BURST_COOLDOWN
            )

        clearBossAddFocus("burst_complete")
    end

    local best
    local bestScore = -math.huge
    local criticalCandidate = false

    for _, enemy in ipairs(enemies) do
        if enemy.Model
            and enemy.Model ~= Runtime.ActiveBossModel
            and enemy.Model.Name ~= "Azrallik's Heart"
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and enemy.Root
        then
            local d =
                horizontalDistance(
                    enemy.Root.Position,
                    Runtime.Root.Position
                )

            local physical =
                isPhysicalEnemyModel(
                    enemy.Model
                )

            local range =
                Runtime.FragileMode
                and CFG.BOSS_ADD_INTERCEPT_FRAGILE_RANGE
                or (
                    physical
                    and CFG.BOSS_ADD_PHYSICAL_INTERCEPT_RANGE
                    or CFG.BOSS_ADD_INTERCEPT_RANGE
                )

            local room =
                enemy.RoomIndex or 0

            local localEncounterAdd =
                room == Runtime.CurrentRoomIndex
                or room == 999
                or d <= 12

            if localEncounterAdd
                and d <= range
            then
                local eReady =
                    now >= (
                        Runtime.LastAbilityCast["e"]
                        or -math.huge
                    )

                local qReady =
                    now >= (
                        Runtime.LastAbilityCast["q"]
                        or -math.huge
                    )

                local immediateShot =
                    (
                        eReady
                        and d <= (
                            CFG.ABILITY_RANGE_HINTS["Infernal Strike"]
                            or 30
                        )
                    )
                    or (
                        qReady
                        and d <= (
                            CFG.ABILITY_RANGE_HINTS["Ground Slam"]
                            or 14
                        )
                    )

                -- If no damage skill is immediately available, keep offense on
                -- the boss. The movement/threat engine still dodges this add.
                if not immediateShot then
                    continue
                end

                local hpRatio =
                    enemy.Humanoid.MaxHealth > 0
                    and (
                        enemy.Humanoid.Health
                        / enemy.Humanoid.MaxHealth
                    )
                    or 1

                local critical =
                    d <= CFG.BOSS_ADD_CRITICAL_RANGE

                local finishable =
                    hpRatio
                        <= CFG.BOSS_ADD_FINISH_HP_RATIO

                -- During the forced boss-focus cooldown, only an enemy that is
                -- literally in critical melee range may interrupt again.
                if now >= (
                    Runtime.BossAddCooldownUntil
                    or -math.huge
                )
                    or critical
                then
                    local maxHealthMillions =
                        enemy.Humanoid.MaxHealth
                        / 1000000

                    local profilePri =
                        Profile.Priority[
                            enemy.Model.Name
                        ]
                        or 80

                    local score =
                        (critical and 5000 or 0)
                        + (physical and 1500 or 400)
                        + (finishable and 500 or 0)
                        + maxHealthMillions * 24
                        + profilePri * 2
                        - d * 22

                    if score > bestScore then
                        bestScore = score
                        best = enemy
                        criticalCandidate = critical
                    end
                end
            end
        end
    end

    if not best then
        return nil
    end

    Runtime.BossAddFocusModel =
        best.Model
    Runtime.BossAddFocusStartedAt =
        now
    Runtime.BossAddFocusUntil =
        now + CFG.BOSS_ADD_BURST_MAX

    if now - Runtime.LastBossAddFocusLog
        >= CFG.BOSS_ADD_INTERCEPT_LOG_COOLDOWN
    then
        Runtime.LastBossAddFocusLog = now

        logKV("BOSS_ADD_BURST_START", {
            boss =
                tostring(
                    Runtime.ActiveBossName
                ),
            add =
                best.Model.Name,
            distance =
                string.format(
                    "%.1f",
                    horizontalDistance(
                        best.Root.Position,
                        Runtime.Root.Position
                    )
                ),
            hp =
                math.floor(
                    best.Humanoid.Health
                ),
            critical =
                tostring(
                    criticalCandidate
                ),
            burst =
                string.format(
                    "%.2f",
                    CFG.BOSS_ADD_BURST_MAX
                ),
        })
    end

    return best
end

-- ------------------------------------------------------------
-- Generic post-boss cleanup.
-- Runtime table methods avoid consuming more top-level local registers.
-- ------------------------------------------------------------

Runtime.BeginBossCleanup = function(oldBossName)
    if not CFG.BOSS_POST_CLEANUP_ENABLED
        or not Runtime.Root
        or not oldBossName
    then
        return
    end

    Runtime.BossCleanupModels = {}
    Runtime.BossCleanupBoss = oldBossName
    Runtime.BossCleanupUntil =
        os.clock()
        + CFG.BOSS_POST_CLEANUP_TIMEOUT
    Runtime.BossCleanupTarget = nil

    local captured = 0

    for _, enemy in ipairs(
        livingEnemies()
    ) do
        if enemy.Model
            and enemy.Model.Name ~= oldBossName
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and enemy.Root
        then
            local d =
                horizontalDistance(
                    enemy.Root.Position,
                    Runtime.Root.Position
                )

            local room =
                enemy.RoomIndex or 0

            local sameEncounter =
                room == Runtime.CurrentRoomIndex
                or room == 999
                or room == 0

            if sameEncounter
                and d <= CFG.BOSS_POST_CLEANUP_RADIUS
            then
                Runtime.BossCleanupModels[
                    enemy.Model
                ] = true

                captured += 1
            end
        end
    end

    -- The active boss-add focus is always part of cleanup if still alive,
    -- even if its room metadata is unusual.
    if Runtime.BossAddFocusModel
        and Runtime.BossAddFocusModel.Parent
    then
        Runtime.BossCleanupModels[
            Runtime.BossAddFocusModel
        ] = true
    end

    if captured > 0
        or Runtime.BossAddFocusModel
    then
        logKV("BOSS_CLEANUP_START", {
            boss = tostring(oldBossName),
            captured = captured,
            timeout =
                string.format(
                    "%.1f",
                    CFG.BOSS_POST_CLEANUP_TIMEOUT
                ),
        })
    end
end

Runtime.ChooseBossCleanupTarget = function(enemies)
    if not Runtime.Root
        or not Runtime.BossCleanupBoss
    then
        return nil
    end

    local now = os.clock()

    if now > Runtime.BossCleanupUntil then
        if now - Runtime.LastBossCleanupLog
            >= CFG.BOSS_POST_CLEANUP_LOG_COOLDOWN
        then
            Runtime.LastBossCleanupLog = now

            logKV("BOSS_CLEANUP_END", {
                boss =
                    tostring(
                        Runtime.BossCleanupBoss
                    ),
                reason = "timeout",
            })
        end

        Runtime.BossCleanupModels = {}
        Runtime.BossCleanupBoss = nil
        Runtime.BossCleanupTarget = nil
        return nil
    end

    local aliveByModel = {}

    for _, enemy in ipairs(enemies) do
        aliveByModel[enemy.Model] = enemy
    end

    -- Keep finishing the current cleanup target if it is still local.
    if Runtime.BossCleanupTarget then
        local focused =
            aliveByModel[
                Runtime.BossCleanupTarget
            ]

        if focused
            and focused.Humanoid
            and focused.Humanoid.Health > 0
            and focused.Root
        then
            local d =
                horizontalDistance(
                    focused.Root.Position,
                    Runtime.Root.Position
                )

            if d
                <= CFG.BOSS_POST_CLEANUP_RELEASE_RADIUS
            then
                return focused
            end
        end

        Runtime.BossCleanupModels[
            Runtime.BossCleanupTarget
        ] = nil

        Runtime.BossCleanupTarget = nil
    end

    local best
    local bestScore = -math.huge
    local remaining = 0

    for model in pairs(
        Runtime.BossCleanupModels
    ) do
        local enemy =
            aliveByModel[model]

        if enemy
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and enemy.Root
        then
            local d =
                horizontalDistance(
                    enemy.Root.Position,
                    Runtime.Root.Position
                )

            if d
                <= CFG.BOSS_POST_CLEANUP_RELEASE_RADIUS
            then
                remaining += 1

                local physical =
                    isPhysicalEnemyModel(
                        enemy.Model
                    )

                local hpRatio =
                    enemy.Humanoid.MaxHealth > 0
                    and (
                        enemy.Humanoid.Health
                        / enemy.Humanoid.MaxHealth
                    )
                    or 1

                local maxHealthMillions =
                    enemy.Humanoid.MaxHealth
                    / 1000000

                local profilePri =
                    Profile.Priority[
                        enemy.Model.Name
                    ]
                    or 80

                local score =
                    maxHealthMillions
                        * CFG.BOSS_POST_CLEANUP_STRENGTH_WEIGHT
                    + profilePri * 2.0
                    + (
                        physical
                        and CFG.BOSS_POST_CLEANUP_PHYSICAL_BONUS
                        or 0
                    )
                    - d * 7
                    + (1 - hpRatio) * 650

                if score > bestScore then
                    bestScore = score
                    best = enemy
                end
            else
                Runtime.BossCleanupModels[
                    model
                ] = nil
            end
        else
            Runtime.BossCleanupModels[
                model
            ] = nil
        end
    end

    if best then
        Runtime.BossCleanupTarget =
            best.Model

        if now - Runtime.LastBossCleanupLog
            >= CFG.BOSS_POST_CLEANUP_LOG_COOLDOWN
        then
            Runtime.LastBossCleanupLog = now

            logKV("BOSS_CLEANUP_TARGET", {
                boss =
                    tostring(
                        Runtime.BossCleanupBoss
                    ),
                target =
                    best.Model.Name,
                physical =
                    tostring(
                        isPhysicalEnemyModel(
                            best.Model
                        )
                    ),
                distance =
                    string.format(
                        "%.1f",
                        horizontalDistance(
                            best.Root.Position,
                            Runtime.Root.Position
                        )
                    ),
                remaining = remaining,
            })
        end

        return best
    end

    if now - Runtime.LastBossCleanupLog
        >= CFG.BOSS_POST_CLEANUP_LOG_COOLDOWN
    then
        Runtime.LastBossCleanupLog = now

        logKV("BOSS_CLEANUP_END", {
            boss =
                tostring(
                    Runtime.BossCleanupBoss
                ),
            reason = "clear",
        })
    end

    Runtime.BossCleanupModels = {}
    Runtime.BossCleanupBoss = nil
    Runtime.BossCleanupTarget = nil

    return nil
end

Runtime.ChooseLocalFinisher = function(enemies)
    if not CFG.LOCAL_FINISH_ENABLED
        or Runtime.ActiveBossName
        or Runtime.BossCleanupBoss
        or not Runtime.Root
    then
        return nil
    end

    local best
    local bestScore = -math.huge

    for _, enemy in ipairs(enemies) do
        if enemy
            and enemy.Model
            and enemy.Root
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and enemyRelevantForEncounter(enemy)
            and enemy.RoomIndex
                == Runtime.CurrentRoomIndex
        then
            local maxHp =
                enemy.Humanoid.MaxHealth

            local hpRatio =
                maxHp > 0
                and (
                    enemy.Humanoid.Health
                    / maxHp
                )
                or 1

            local distance =
                horizontalDistance(
                    Runtime.Root.Position,
                    enemy.Root.Position
                )

            if hpRatio
                    <= CFG.LOCAL_FINISH_HP_RATIO
                and distance
                    <= CFG.LOCAL_FINISH_RANGE
            then
                local score =
                    (1 - hpRatio) * 2400
                    - distance * 18
                    + (
                        isPhysicalEnemyModel(
                            enemy.Model
                        )
                        and CFG.LOCAL_FINISH_PHYSICAL_BONUS
                        or 0
                    )

                if score > bestScore then
                    bestScore = score
                    best = enemy
                end
            end
        end
    end

    if best then
        local now = os.clock()

        if now - Runtime.LastLocalFinishLog
            >= CFG.LOCAL_FINISH_LOG_COOLDOWN
        then
            Runtime.LastLocalFinishLog = now

            logKV("LOCAL_FINISH", {
                target = best.Model.Name,
                hp =
                    math.floor(
                        best.Humanoid.Health
                    ),
                ratio =
                    string.format(
                        "%.2f",
                        best.Humanoid.MaxHealth > 0
                        and (
                            best.Humanoid.Health
                            / best.Humanoid.MaxHealth
                        )
                        or 1
                    ),
                distance =
                    string.format(
                        "%.1f",
                        horizontalDistance(
                            Runtime.Root.Position,
                            best.Root.Position
                        )
                    ),
            })
        end
    end

    return best
end


Runtime.StabilizeNormalTarget = function(
    enemies,
    candidate,
    candidateScore
)
    if not CFG.TARGET_LOCK_ENABLED
        or Runtime.ActiveBossName
        or Runtime.BossCleanupBoss
        or not Runtime.Root
    then
        return candidate, candidateScore
    end

    local current

    if Runtime.Target then
        for _, enemy in ipairs(enemies) do
            if enemy.Model == Runtime.Target
                and enemy.Humanoid
                and enemy.Humanoid.Health > 0
                and enemy.Root
                and enemyRelevantForEncounter(enemy)
            then
                current = enemy
                break
            end
        end
    end

    if not current then
        return candidate, candidateScore
    end

    local now = os.clock()
    local currentDistance =
        horizontalDistance(
            current.Root.Position,
            Runtime.Root.Position
        )

    if currentDistance
        > CFG.TARGET_LOCK_RELEASE_DISTANCE
    then
        return candidate, candidateScore
    end

    -- If the current target is already a physical threat, keep it latched
    -- while it remains local. This prevents mage -> warrior -> mage ping-pong
    -- that wastes rotations and leaves the warrior alive beside the player.
    if isPhysicalEnemyModel(current.Model)
        and currentDistance
            <= CFG.TARGET_LOCK_PHYSICAL_HOLD_RANGE
    then
        return
            current,
            targetScore(current)
    end

    -- A close physical mob is the only immediate override to a sticky ranged
    -- target. This keeps safety without rapid mage-to-mage rotations.
    local physicalOverride
    local physicalDistance = math.huge

    for _, enemy in ipairs(enemies) do
        if enemy.Model ~= current.Model
            and enemy.Root
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and isPhysicalEnemyModel(
                enemy.Model
            )
            and enemyRelevantForEncounter(enemy)
        then
            local d =
                horizontalDistance(
                    enemy.Root.Position,
                    Runtime.Root.Position
                )

            if d
                <= CFG.TARGET_LOCK_PHYSICAL_OVERRIDE_RANGE
                and d < physicalDistance
            then
                physicalDistance = d
                physicalOverride = enemy
            end
        end
    end

    if physicalOverride then
        return
            physicalOverride,
            math.huge
    end

    if candidate
        and candidate.Model ~= current.Model
        and candidate.Root
        and currentDistance
            <= CFG.TARGET_LOCK_LOCAL_HOLD_DISTANCE
        and not isPhysicalEnemyModel(candidate.Model)
    then
        local challengerDistance =
            horizontalDistance(
                candidate.Root.Position,
                Runtime.Root.Position
            )

        if challengerDistance
            > currentDistance
                - CFG.TARGET_LOCK_CHALLENGER_DISTANCE_GAIN
        then
            return
                current,
                targetScore(current)
        end
    end

    local hpRatio =
        current.Humanoid.MaxHealth > 0
        and (
            current.Humanoid.Health
            / current.Humanoid.MaxHealth
        )
        or 1

    local age =
        now - (
            Runtime.TargetSince
            or -math.huge
        )

    local keep =
        age < CFG.TARGET_LOCK_MIN_SECONDS
        or hpRatio
            <= CFG.TARGET_LOCK_FINISH_HP_RATIO

    local currentScore =
        targetScore(current)

    if not keep
        and candidate
        and candidate.Model ~= current.Model
    then
        keep =
            candidateScore
            < currentScore
                + CFG.TARGET_LOCK_SWITCH_MARGIN
    end

    if keep then
        if now - Runtime.LastTargetLockLog
            >= CFG.TARGET_LOCK_LOG_COOLDOWN
            and candidate
            and candidate.Model ~= current.Model
        then
            Runtime.LastTargetLockLog = now

            logKV("TARGET_LOCK_HOLD", {
                target =
                    current.Model.Name,
                hp_ratio =
                    string.format(
                        "%.2f",
                        hpRatio
                    ),
                age =
                    string.format(
                        "%.2f",
                        age
                    ),
                challenger =
                    candidate.Model.Name,
                current_score =
                    string.format(
                        "%.1f",
                        currentScore
                    ),
                challenger_score =
                    string.format(
                        "%.1f",
                        candidateScore
                    ),
            })
        end

        return current, currentScore
    end

    return candidate, candidateScore
end


function selectTarget()
    local enemies = livingEnemies()

    if #enemies == 0 then
        Runtime.Target = nil
        Runtime.TargetHumanoid = nil
        Runtime.TargetRoot = nil
        return
    end

    -- Infer active room from smallest room index that still has enemies.
    local minRoom = math.huge

    for _, e in ipairs(enemies) do
        local room =
            e.RoomIndex or 0

        local room999Allowed =
            Runtime.ActiveBossName == "Demon Lord Azrallik"
            or Runtime.ActiveBossName == "Miyamoto Musashi"
            or Runtime.FinalBossDefeated
            or Runtime.CurrentRoomIndex == 999

        -- A preloaded Blood Minion must not temporarily turn the run into
        -- room 999 between earlier rooms.
        if room > 0
            and room < minRoom
            and (
                room < 999
                or room999Allowed
            )
        then
            minRoom = room
        end
    end

    if minRoom < math.huge then
        local previousRoom =
            Runtime.CurrentRoomIndex

        Runtime.CurrentRoomIndex =
            minRoom

        if previousRoom ~= minRoom then
            Runtime.TransitSnapbackCount = 0
            Runtime.TransitSnapbackRoom = minRoom
            Runtime.TransitDisabledRoom = nil
            Runtime.TransitBackoffUntil = -math.huge
        end
    end

    local best
    local bestScore = -math.huge

    local cleanupTarget =
        Runtime.ChooseBossCleanupTarget(
            enemies
        )

    if cleanupTarget then
        best = cleanupTarget
        bestScore = math.huge
    end

    if not best
        and not Runtime.ActiveBossName
    then
        local localFinisher =
            Runtime.ChooseLocalFinisher(
                enemies
            )

        if localFinisher then
            best = localFinisher
            bestScore = math.huge
        end
    end

    -- Samurai Palace boss-majority rule. Keep offense/movement on the
    -- boss; local adds are handled by opportunistic skill bursts and physical
    -- pressure movement instead of stealing the route.
    if not best
        and Runtime.ActiveBossModel
        and Runtime.IsSamuraiBossName(
            Runtime.ActiveBossName
        )
    then
        for _, enemy in ipairs(enemies) do
            if enemy.Model
                == Runtime.ActiveBossModel
                and enemyRelevantForEncounter(
                    enemy
                )
            then
                best = enemy
                bestScore = math.huge
                break
            end
        end
    end

    -- Boss is the PRIMARY target. A nearby add may steal only a short,
    -- duty-cycled emergency burst; movement avoidance still protects against
    -- adds even while offense returns to the boss.
    if not best
        and Runtime.ActiveBossModel
        and (
            Runtime.ActiveBossName == "Demonic Overgrowth"
            or Runtime.ActiveBossName == "Kolvumar"
        )
    then
        -- Primary movement/offense lock remains the boss. Nearby adds are
        -- handled by attack-only opportunism so they never steal our route.
        for _, enemy in ipairs(enemies) do
            if enemy.Model == Runtime.ActiveBossModel
                and enemyRelevantForEncounter(enemy)
            then
                best = enemy
                bestScore = math.huge
                break
            end
        end
    end

    -- V8.3 final-boss target discipline.
    -- "Azrallik's Heart" is a mandatory phase objective.
    if not best
        and Runtime.ActiveBossName == "Demon Lord Azrallik"
        and Runtime.ActiveBossModel
    then
        local bossEnemy
        local heartEnemy
        local emergencyAdd
        local emergencyScore = -math.huge

        for _, enemy in ipairs(enemies) do
            if enemyRelevantForEncounter(enemy) then
                if enemy.Model == Runtime.ActiveBossModel then
                    bossEnemy = enemy

                elseif enemy.Model
                    and enemy.Model.Name == "Azrallik's Heart"
                then
                    heartEnemy = enemy

                elseif enemy.Model
                    and enemy.Model.Name == "Blood Minion"
                then
                    local d =
                        horizontalDistance(
                            enemy.Root.Position,
                            Runtime.Root.Position
                        )

                    if d <= CFG.AZRALLIK_BLOOD_MINION_EMERGENCY_RANGE then
                        local score = 10000 - d

                        if score > emergencyScore then
                            emergencyScore = score
                            emergencyAdd = enemy
                        end
                    end
                end
            end
        end

        if CFG.AZRALLIK_HEART_PHASE_LOCK
            and heartEnemy
        then
            best = heartEnemy
            bestScore = math.huge

            if not Runtime.AzrallikHeartPhaseActive
                or Runtime.AzrallikHeartModel ~= heartEnemy.Model
            then
                Runtime.AzrallikHeartPhaseActive = true
                Runtime.AzrallikHeartModel = heartEnemy.Model
                Runtime.AzrallikHeartStartedAt = os.clock()

                logKV("AZRALLIK_HEART_PHASE_START", {
                    hp = math.floor(heartEnemy.Humanoid.Health),
                    distance = string.format(
                        "%.1f",
                        horizontalDistance(
                            heartEnemy.Root.Position,
                            Runtime.Root.Position
                        )
                    ),
                })
            end
        else
            if Runtime.AzrallikHeartPhaseActive then
                local elapsed =
                    Runtime.AzrallikHeartStartedAt
                    and (os.clock() - Runtime.AzrallikHeartStartedAt)
                    or 0

                logKV("AZRALLIK_HEART_PHASE_END", {
                    elapsed = string.format("%.2f", elapsed),
                })

                Runtime.AzrallikHeartPhaseActive = false
                Runtime.AzrallikHeartModel = nil
                Runtime.AzrallikHeartStartedAt = nil
            end

            best = bossEnemy

            bestScore =
                best and math.huge
                or -math.huge
        end
    end

    if not best
        and not Runtime.ActiveBossName
        and Runtime.Root
        and CFG.MAGE_FREE_PRESSURE_ENABLED
    then
        local physical, physicalDistance =
            nearestPhysicalEnemy(
                Runtime.Root.Position
            )

        if not physical
            or physicalDistance
                > CFG.MAGE_FREE_PRESSURE_PHYSICAL_GUARD
        then
            local mageBest
            local mageScore = -math.huge

            for _, enemy in ipairs(enemies) do
                if enemyRelevantForEncounter(enemy)
                    and enemy.Model
                    and enemy.Root
                    and enemy.Humanoid
                    and enemy.Humanoid.Health > 0
                then
                    local name =
                        string.lower(
                            tostring(
                                enemy.Model.Name
                            )
                        )

                    if Runtime.IsRangedPressureName(
                        enemy.Model.Name
                    )
                        or string.find(
                            name,
                            "mage",
                            1,
                            true
                        )
                    then
                        local d =
                            horizontalDistance(
                                Runtime.Root.Position,
                                enemy.Root.Position
                            )

                        if d
                            <= CFG.MAGE_FREE_PRESSURE_ACQUIRE_RANGE
                        then
                            local maxHpMillions =
                                enemy.Humanoid.MaxHealth
                                / 1000000

                            local hpRatio =
                                enemy.Humanoid.MaxHealth > 0
                                and (
                                    enemy.Humanoid.Health
                                    / enemy.Humanoid.MaxHealth
                                )
                                or 1

                            local score =
                                maxHpMillions * 120
                                + (1 - hpRatio) * 700
                                - d * 8

                            if score > mageScore then
                                mageScore = score
                                mageBest = enemy
                            end
                        end
                    end
                end
            end

            if mageBest then
                best = mageBest
                bestScore = math.huge

                local now = os.clock()

                if now - Runtime.LastMageFreePressureLog
                    >= CFG.MAGE_FREE_PRESSURE_LOG_COOLDOWN
                then
                    Runtime.LastMageFreePressureLog = now

                    logKV("MAGE_FREE_FOCUS", {
                        target = mageBest.Model.Name,
                        distance =
                            string.format(
                                "%.1f",
                                horizontalDistance(
                                    Runtime.Root.Position,
                                    mageBest.Root.Position
                                )
                            ),
                        physical =
                            physical
                            and string.format(
                                "%.1f",
                                physicalDistance
                            )
                            or "none",
                    })
                end
            end
        end
    end

    if not best then
        for _, enemy in ipairs(enemies) do
            if enemyRelevantForEncounter(enemy) then
                local score = targetScore(enemy)

                if score > bestScore then
                    bestScore = score
                    best = enemy
                end
            end
        end

        best, bestScore =
            Runtime.StabilizeNormalTarget(
                enemies,
                best,
                bestScore
            )
    end

    if not best then
        Runtime.Target = nil
        Runtime.TargetHumanoid = nil
        Runtime.TargetRoot = nil
        Runtime.TargetSince = -math.huge
        Runtime.ApproachWaypoints = nil
        Runtime.ApproachFallbackPosition = nil
        Runtime.ApproachTarget = nil
        return
    end

    if best and Runtime.Target ~= best.Model then
        Runtime.ApproachWaypoints = nil
        Runtime.ApproachFallbackPosition = nil
        Runtime.ApproachTarget = nil

        Runtime.Target = best.Model
        Runtime.TargetHumanoid = best.Humanoid
        Runtime.TargetRoot = best.Root
        Runtime.TargetSince = os.clock()

        logKV("TARGET", {
            name = best.Model.Name,
            room = best.RoomIndex,
            hp = math.floor(best.Humanoid.Health),
            distance = string.format(
                "%.1f",
                horizontalDistance(
                    best.Root.Position,
                    Runtime.Root.Position
                )
            ),
        })
    elseif best then
        Runtime.Target = best.Model
        Runtime.TargetHumanoid = best.Humanoid
        Runtime.TargetRoot = best.Root
    end
end


