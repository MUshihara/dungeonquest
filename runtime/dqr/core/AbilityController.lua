-- DQR modular runtime: core/AbilityController.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Attacks / abilities
-- ============================================================

function busyCasting()
    local char = Runtime.Character

    if not char then return true end

    local busy =
        char:FindFirstChild("busyCasting")

    if not busy then
        return false
    end

    return busy.Value == true
end

function abilityTool(slot)
    local backpack =
        LP:FindFirstChild("Backpack")

    local function scan(container)
        if not container then return nil end

        for _,tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local abilitySlot =
                    tool:FindFirstChild(
                        "abilitySlot"
                    )

                if abilitySlot
                    and tostring(
                        abilitySlot.Value
                    ) == slot
                then
                    return tool
                end
            end
        end

        return nil
    end

    return scan(backpack)
        or scan(Runtime.Character)
end

function castAbility(slot, allowGeometryDanger)
    if not CFG.AUTO_ABILITIES
        or busyCasting()
    then
        return false
    end

    -- V3 blocked skills for the entire lifetime of any warning object.
    -- V6 only blocks a cast when danger is actually imminent at our position.
    if allowGeometryDanger then
        if not CFG.DODGE_CAST_ENABLED
            or Runtime.DodgeCastBlocked()
        then
            return false
        end
    elseif abilityDangerImminent() then
        return false
    end

    local tool = abilityTool(slot)
    if not tool then return false end

    local now = os.clock()
    local localReadyAt = Runtime.LastAbilityCast[slot] or -math.huge

    if now < localReadyAt then
        return false
    end

    local cooldown =
        tool:FindFirstChild("cooldown")

    if cooldown
        and tonumber(cooldown.Value)
        and cooldown.Value > 0
    then
        return false
    end

    local localEvent =
        tool:FindFirstChild("localEvent")

    if not localEvent then
        return false
    end

    local distance = math.huge
    local verticalGap = math.huge

    if Runtime.TargetRoot
        and Runtime.Root
    then
        verticalGap =
            verticalDistance(
                Runtime.TargetRoot.Position,
                Runtime.Root.Position
            )

        if verticalGap
            > CFG.TARGET_LEVEL_VERTICAL_TOLERANCE
        then
            local levelKey =
                tool.Name .. ":level"

            local lastLog =
                Runtime.LastAbilityRangeSkipLog[
                    levelKey
                ]
                or -math.huge

            if now - lastLog
                >= CFG.ABILITY_RANGE_SKIP_LOG_COOLDOWN
            then
                Runtime.LastAbilityRangeSkipLog[
                    levelKey
                ] = now

                logKV("ABILITY_LEVEL_SKIP", {
                    slot = slot,
                    name = tool.Name,
                    vertical_gap =
                        string.format("%.1f", verticalGap),
                    target =
                        Runtime.Target
                        and Runtime.Target.Name
                        or "none",
                })
            end

            return false
        end

        distance =
            horizontalDistance(
                Runtime.TargetRoot.Position,
                Runtime.Root.Position
            )
    end

    local abilityRange =
        CFG.ABILITY_RANGE_HINTS[tool.Name]
        or Profile.AbilityRange

    -- Prefer a legitimate numeric range exposed by the equipped Tool itself
    -- when the game provides one. Do not invent or call any extra remote.
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
                return
                    tool:GetAttribute(
                        attributeName
                    )
            end)

        if ok
            and type(value) == "number"
            and value > 0
        then
            abilityRange = value
            break
        end
    end

    if distance > abilityRange then
        local lastLog =
            Runtime.LastAbilityRangeSkipLog[
                tool.Name
            ]
            or -math.huge

        if now - lastLog
            >= CFG.ABILITY_RANGE_SKIP_LOG_COOLDOWN
        then
            Runtime.LastAbilityRangeSkipLog[
                tool.Name
            ] = now

            logKV("ABILITY_RANGE_SKIP", {
                slot = slot,
                name = tool.Name,
                distance =
                    string.format(
                        "%.1f",
                        distance
                    ),
                range =
                    string.format(
                        "%.1f",
                        abilityRange
                    ),
            })
        end

        return false
    end

    if now - Runtime.LastAnyAbilityCast
        < CFG.ABILITY_CAST_CHAIN_GAP
    then
        return false
    end

    -- A distant/stale warning no longer suppresses skills. Lock facing onto
    -- the selected enemy immediately before the client fires the ability.
    beginAimLock()

    local cooldownLength =
        tool:FindFirstChild("cooldownLength")

    local localCooldown =
        cooldownLength
        and tonumber(cooldownLength.Value)
        or 0.8

    -- Set the lock BEFORE firing so a delayed replicated cooldown value cannot
    -- allow duplicate casts on consecutive controller ticks.
    Runtime.LastAbilityCast[slot] =
        now + math.max(localCooldown * 0.96, 0.45)

    Runtime.LastAnyAbilityCast = now

    pcall(function()
        localEvent:Fire()
    end)

    local abilityUsed =
        ReplicatedStorage
        :FindFirstChild("remotes")

    abilityUsed =
        abilityUsed
        and abilityUsed:FindFirstChild(
            "abilityUsed"
        )

    if abilityUsed
        and abilityUsed:IsA("RemoteEvent")
    then
        pcall(function()
            abilityUsed:FireServer(
                slot,
                tool
            )
        end)
    end

    logKV("ABILITY", {
        slot = slot,
        name = tool.Name,
        distance = string.format("%.1f",distance),
        range =
            string.format(
                "%.1f",
                abilityRange
            ),
    })

    if CFG.ABILITY_RESULT_DIAGNOSTIC
        and Runtime.TargetHumanoid
        and Runtime.Target
    then
        local probeHumanoid =
            Runtime.TargetHumanoid
        local probeModel =
            Runtime.Target
        local probeHp =
            probeHumanoid.Health
        local probeDistance =
            distance
        local probeName =
            tool.Name
        local probeSlot =
            slot

        task.delay(
            CFG.ABILITY_RESULT_DELAY,
            function()
                if not Runtime.Alive
                    or not probeHumanoid
                    or not probeHumanoid.Parent
                then
                    return
                end

                local hpDelta =
                    math.max(
                        0,
                        probeHp
                        - probeHumanoid.Health
                    )

                local stats =
                    Runtime.AbilityStats[
                        probeName
                    ]

                if not stats then
                    stats = {
                        Casts = 0,
                        Positive = 0,
                        MaxPositiveDistance = 0,
                    }

                    Runtime.AbilityStats[
                        probeName
                    ] = stats
                end

                stats.Casts += 1

                if hpDelta > 0 then
                    stats.Positive += 1
                    stats.MaxPositiveDistance =
                        math.max(
                            stats.MaxPositiveDistance,
                            probeDistance
                        )
                end

                logKV("ABILITY_RESULT", {
                    slot = probeSlot,
                    name = probeName,
                    sample_delay =
                        string.format(
                            "%.2f",
                            CFG.ABILITY_RESULT_DELAY
                        ),
                    cast_distance =
                        string.format(
                            "%.1f",
                            probeDistance
                        ),
                    hp_delta =
                        string.format(
                            "%.0f",
                            hpDelta
                        ),
                    same_target =
                        tostring(
                            Runtime.Target
                            == probeModel
                        ),
                    positive =
                        tostring(
                            hpDelta > 0
                        ),
                })
            end
        )
    end

    return true
end

function equippedWeaponEvent()
    local char = Runtime.Character
    if not char then return nil end

    for _,inst in ipairs(char:GetChildren()) do
        if inst:IsA("Accessory")
            and inst:FindFirstChild("Weapon")
        then
            return
                inst:FindFirstChildOfClass(
                    "RemoteEvent"
                )
        end
    end

    return nil
end


Runtime.CastAbilityOnEnemy = function(
    slot,
    enemy,
    allowGeometryDanger
)
    if not enemy
        or not enemy.Model
        or not enemy.Root
        or not enemy.Humanoid
        or enemy.Humanoid.Health <= 0
        or not enemy.Model.Parent
    then
        return false
    end

    local savedTarget =
        Runtime.Target
    local savedHumanoid =
        Runtime.TargetHumanoid
    local savedRoot =
        Runtime.TargetRoot

    Runtime.Target =
        enemy.Model
    Runtime.TargetHumanoid =
        enemy.Humanoid
    Runtime.TargetRoot =
        enemy.Root

    local used =
        castAbility(
            slot,
            allowGeometryDanger
        )

    Runtime.Target =
        savedTarget
    Runtime.TargetHumanoid =
        savedHumanoid
    Runtime.TargetRoot =
        savedRoot

    return used
end


Runtime.TryOpportunisticAttack = function(
    allowGeometryDanger
)
    if not CFG.OPPORTUNISTIC_ATTACK_ENABLED
        or not Runtime.Root
    then
        return false
    end

    -- If the current primary is a lone mage, save every ready cast for that
    -- mage. V9.8 was incorrectly spending Infernal Strike on a distant Demon
    -- Warrior while the mage was still the primary target.
    if Runtime.MageFreePressureActive
        and Runtime.MageFreePressureActive()
    then
        return false
    end

    local now = os.clock()
    local physical, physicalDistance =
        nearestPhysicalEnemy(
            Runtime.Root.Position
        )

    local physicalUrgent =
        physical
        and physicalDistance
            <= CFG.OPPORTUNISTIC_PHYSICAL_PRIORITY_RANGE

    local function bestForRange(range)
        local best
        local bestScore = -math.huge

        for _, enemy in ipairs(livingEnemies()) do
            if enemy.Model
                and enemy.Model ~= Runtime.Target
                and enemy.Root
                and enemy.Humanoid
                and enemy.Humanoid.Health > 0
            then
                local sameLevel =
                    sameCombatLevel(
                        Runtime.Root.Position,
                        enemy.Root.Position
                    )

                local d =
                    horizontalDistance(
                        Runtime.Root.Position,
                        enemy.Root.Position
                    )

                if sameLevel
                    and d <= range
                    and d <= CFG.OPPORTUNISTIC_NEARBY_MAX
                then
                    local physicalEnemy =
                        isPhysicalEnemyModel(
                            enemy.Model
                        )

                    local name =
                        enemy.Model.Name or ""

                    local mage =
                        Runtime.IsRangedPressureName(
                            name
                        )
                        or string.find(
                            string.lower(name),
                            "mage",
                            1,
                            true
                        ) ~= nil

                    local relevant =
                        enemyRelevantForEncounter(
                            enemy
                        )

                    if Runtime.ActiveBossName then
                        -- During a live boss, keep the boss as the route/primary
                        -- target. Only a genuinely local add may receive a free
                        -- skill, and never more often than the boss cooldown.
                        relevant =
                            enemy.Model
                                ~= Runtime.ActiveBossModel
                            and enemy.Model.Name
                                ~= "Azrallik's Heart"
                            and d
                                <= CFG.OPPORTUNISTIC_BOSS_ADD_RANGE

                        if relevant
                            and now
                                - Runtime.LastBossOpportunityAt
                                < CFG.OPPORTUNISTIC_BOSS_COOLDOWN
                        then
                            relevant = false
                        end
                    end

                    if relevant then
                        local score =
                            -d * 20

                        if physicalUrgent then
                            if physicalEnemy then
                                score += 6000
                            else
                                score -= 6000
                            end
                        elseif mage
                            and (
                                not physical
                                or physicalDistance
                                    > CFG.OPPORTUNISTIC_MAGE_PHYSICAL_GUARD
                            )
                        then
                            -- Exactly the cheap opportunity the user observed:
                            -- a mage is stationary and only projecting red
                            -- geometry, so hit it while our movement dodges.
                            score += 4200
                        elseif physicalEnemy then
                            score += 900
                        else
                            score += 1800
                        end

                        if enemy.Humanoid.MaxHealth > 0 then
                            score +=
                                (
                                    1
                                    - enemy.Humanoid.Health
                                        / enemy.Humanoid.MaxHealth
                                ) * 600
                        end

                        if score > bestScore then
                            bestScore = score
                            best = enemy
                        end
                    end
                end
            end
        end

        return best
    end

    for _, slot in ipairs({
        "e",
        "q",
    }) do
        local tool =
            abilityTool(slot)

        if tool then
            local range =
                CFG.ABILITY_RANGE_HINTS[
                    tool.Name
                ]
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
                        return
                            tool:GetAttribute(
                                attributeName
                            )
                    end)

                if ok
                    and type(value) == "number"
                    and value > 0
                then
                    range = value
                    break
                end
            end

            local enemy =
                bestForRange(range)

            if enemy
                and Runtime.CastAbilityOnEnemy(
                    slot,
                    enemy,
                    allowGeometryDanger
                )
            then
                if Runtime.ActiveBossName then
                    Runtime.LastBossOpportunityAt =
                        now
                end

                if now
                    - Runtime.LastOpportunityAttackLog
                    >= CFG.OPPORTUNISTIC_LOG_COOLDOWN
                then
                    Runtime.LastOpportunityAttackLog =
                        now

                    logKV("OPPORTUNISTIC_ATTACK", {
                        slot = slot,
                        target =
                            enemy.Model.Name,
                        distance =
                            string.format(
                                "%.1f",
                                horizontalDistance(
                                    Runtime.Root.Position,
                                    enemy.Root.Position
                                )
                            ),
                        primary =
                            Runtime.Target
                            and Runtime.Target.Name
                            or "none",
                        dodge =
                            tostring(
                                Runtime.DodgeActive
                            ),
                    })
                end

                return true
            end
        end
    end

    return false
end

function basicSwing(
    allowGeometryDanger
)
    local magePressure =
        Runtime.MageFreePressureActive
        and Runtime.MageFreePressureActive()

    if not CFG.AUTO_ATTACK
        or (
            Runtime.DodgeActive
            and not (
                allowGeometryDanger
                and magePressure
            )
        )
        or busyCasting()
        or not Runtime.TargetRoot
        or not Runtime.Root
    then
        return false
    end

    local now = os.clock()

    if now-Runtime.LastSwing
        < CFG.BASIC_SWING_COOLDOWN
    then
        return false
    end

    if not sameCombatLevel(
        Runtime.TargetRoot.Position,
        Runtime.Root.Position
    ) then
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.TargetRoot.Position,
            Runtime.Root.Position
        )

    if distance > Profile.BasicRange then
        return false
    end

    -- Survival-first melee guard:
    -- do not commit to a basic swing while a physical mob can immediately
    -- counter. Skills remain usable from range.
    if CFG.PROACTIVE_MELEE_AVOIDANCE then
        local nearestPhysical, nearestPhysicalDist =
            nearestPhysicalEnemy(Runtime.Root.Position)

        if nearestPhysical
            and nearestPhysicalDist <= CFG.MELEE_BASIC_SWING_GUARD_RADIUS
        then
            return false
        end

        if Runtime.Target and isPhysicalEnemyModel(Runtime.Target) then
            return false
        end
    end

    if activeThreatCount() > 0
        and not (
            allowGeometryDanger
            and magePressure
        )
    then
        return false
    end

    local weaponEvent =
        equippedWeaponEvent()

    if not weaponEvent then
        return false
    end

    faceTarget()

    pcall(function()
        weaponEvent:FireServer()
    end)

    local weaponUsed =
        ReplicatedStorage
        :FindFirstChild("remotes")

    weaponUsed =
        weaponUsed
        and weaponUsed:FindFirstChild(
            "weaponUsed"
        )

    if weaponUsed
        and weaponUsed:IsA("RemoteEvent")
    then
        pcall(function()
            weaponUsed:FireServer()
        end)
    end

    Runtime.LastSwing = now

    return true
end

function attackThink(
    allowGeometryDanger
)
    if not Runtime.Root then
        return
    end

    local magePressure =
        Runtime.MageFreePressureActive
        and Runtime.MageFreePressureActive()

    if Runtime.TargetRoot
        and Runtime.TargetHumanoid
        and Runtime.TargetHumanoid.Health > 0
    then
        -- Primary target ALWAYS gets first access to both skills.
        if castAbility(
            "e",
            allowGeometryDanger
        ) then
            if magePressure
                and allowGeometryDanger
            then
                logKV("MAGE_PRESSURE_CAST", {
                    slot = "e",
                    target =
                        Runtime.Target.Name,
                    distance =
                        string.format(
                            "%.1f",
                            horizontalDistance(
                                Runtime.Root.Position,
                                Runtime.TargetRoot.Position
                            )
                        ),
                })
            end

            return
        end

        if castAbility(
            "q",
            allowGeometryDanger
        ) then
            if magePressure
                and allowGeometryDanger
            then
                logKV("MAGE_PRESSURE_CAST", {
                    slot = "q",
                    target =
                        Runtime.Target.Name,
                    distance =
                        string.format(
                            "%.1f",
                            horizontalDistance(
                                Runtime.Root.Position,
                                Runtime.TargetRoot.Position
                            )
                        ),
                })
            end

            return
        end
    end

    -- Mage-only mode is EXCLUSIVE offense:
    -- do not throw a ready skill into another enemy just because the red-line
    -- dodge temporarily placed the mage outside skill range.
    -- Keep closing/side-stepping the mage and use weapon basics when close.
    if magePressure then
        if basicSwing(
            allowGeometryDanger
        ) then
            logKV("MAGE_PRESSURE_BASIC", {
                target =
                    Runtime.Target
                    and Runtime.Target.Name
                    or "none",
                distance =
                    Runtime.TargetRoot
                    and string.format(
                        "%.1f",
                        horizontalDistance(
                            Runtime.Root.Position,
                            Runtime.TargetRoot.Position
                        )
                    )
                    or "inf",
            })
        end

        return
    end

    if Runtime.TryOpportunisticAttack(
        allowGeometryDanger
    ) then
        return
    end

    basicSwing(
        allowGeometryDanger
    )
end

function wallEscapeThink()
    if not Runtime.Root
        or not Runtime.Humanoid
        or not Runtime.WallEscapePosition
    then
        return false
    end

    local now = os.clock()

    if now > Runtime.WallEscapeUntil then
        Runtime.WallEscapePosition = nil
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            Runtime.WallEscapePosition
        )

    if distance <= 2.5 then
        Runtime.WallEscapePosition = nil
        Runtime.WallEscapeAttempts = 0
        Runtime.WallEscapeStarted = nil

        log("WALL_ESCAPE_CLEAR", "reached_open_space")

        return false
    end

    moveTo(
        Runtime.WallEscapePosition,
        "WALL_ESCAPE"
    )

    return true
end

function safeIdleThink()
    if not Runtime.Root
        or not Runtime.Humanoid
    then
        return false
    end

    local physical, dist =
        nearestPhysicalEnemy(
            Runtime.Root.Position
        )

    -- Never stand still with a physical enemy already approaching.
    if physical and physical.Root and dist <= 42 then
        local away =
            unitHorizontal(
                Runtime.Root.Position
                - physical.Root.Position
            )

        local open =
            chooseOpenSpacePoint(
                Runtime.Root.Position,
                away
            )

        if open then
            moveTo(
                open.Position,
                "SAFE_IDLE_ESCAPE"
            )

            return true
        end
    end

    -- Even with no enemy visible, do not idle while pressed directly against
    -- a wall; step into open arena space.
    local wallClearance, openCount =
        localWallClearance(
            Runtime.Root.Position
        )

    if wallClearance < 3.5
        or openCount <= 2
    then
        local open =
            chooseOpenSpacePoint(
                Runtime.Root.Position,
                unitHorizontal(
                    Runtime.Root.CFrame.LookVector
                )
            )

        if open then
            moveTo(
                open.Position,
                "SAFE_IDLE_OPEN_SPACE"
            )

            return true
        end
    end

    return false
end


