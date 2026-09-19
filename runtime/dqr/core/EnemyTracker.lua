-- DQR modular runtime: core/EnemyTracker.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Enemy discovery
-- ============================================================

function modelRoot(model)
    if not model then return nil end

    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end

function modelHumanoid(model)
    return model and model:FindFirstChildOfClass("Humanoid")
end

function roomIndexFor(inst)
    local cur = inst

    while cur and cur ~= workspace do
        local n = cur.Name

        local idx = n:match("^room(%d+)$")
        if idx then
            return tonumber(idx)
        end

        if n == "bossRoom" then
            return 999
        end

        cur = cur.Parent
    end

    return 0
end

function rebuildEnemyCache()
    local dungeon = workspace:FindFirstChild("dungeon")
    local result = {}

    if dungeon then
        for _, inst in ipairs(dungeon:GetDescendants()) do
            if inst:IsA("Humanoid") and inst.Health > 0 then
                local model = inst.Parent

                if model
                    and model:IsA("Model")
                    and Players:GetPlayerFromCharacter(model) == nil
                then
                    local root = modelRoot(model)

                    if root then
                        result[#result + 1] = {
                            Model = model,
                            Humanoid = inst,
                            Root = root,
                            RoomIndex = roomIndexFor(model),
                        }
                    end
                end
            end
        end
    end

    -- Samurai Palace boss adds are spawned under
    -- workspace.eliteSwordsman rather than workspace.dungeon.
    local addFolder =
        workspace:FindFirstChild(
            "eliteSwordsman"
        )

    if addFolder then
        for _, inst in ipairs(
            addFolder:GetDescendants()
        ) do
            if inst:IsA("Humanoid")
                and inst.Health > 0
            then
                local model =
                    inst.Parent

                if model
                    and model:IsA("Model")
                    and Players:GetPlayerFromCharacter(
                        model
                    ) == nil
                    and Runtime.IsSamuraiBossAddName(
                        model.Name
                    )
                then
                    local root =
                        modelRoot(model)

                    if root then
                        local addRoom =
                            Runtime.ActiveBossName
                                == "Miyamoto Musashi"
                            and 999
                            or (
                                Runtime.ActiveBossName
                                    == "Sanada Yukimura"
                                and 4
                                or Runtime.CurrentRoomIndex
                            )

                        result[#result + 1] = {
                            Model = model,
                            Humanoid = inst,
                            Root = root,
                            RoomIndex = addRoom,
                        }
                    end
                end
            end
        end
    end

    -- Dormant shared-engine support for Underworld-only workspace-root adds.
    for _, inst in ipairs(workspace:GetChildren()) do
        if inst:IsA("Model")
            and inst ~= Runtime.Character
            and Players:GetPlayerFromCharacter(inst) == nil
            and (inst.Name == "Blood Minion" or inst.Name == "Azrallik's Heart")
        then
            local hum = modelHumanoid(inst)
            local root = modelRoot(inst)

            if hum and root and hum.Health > 0 then
                result[#result + 1] = {
                    Model = inst,
                    Humanoid = hum,
                    Root = root,
                    RoomIndex = 999,
                }
            end
        end
    end

    Runtime.EnemyCache = result
    Runtime.EnemyCacheAt = os.clock()

    return result
end

function livingEnemies(force)
    local now = os.clock()

    if force
        or now - Runtime.EnemyCacheAt >= CFG.ENEMY_CACHE_INTERVAL
    then
        return rebuildEnemyCache()
    end

    return Runtime.EnemyCache
end

-- V7.7 strict encounter scoping.
--
-- Important discovery:
-- workspace-root Blood Minions are labeled room 999. They may already exist
-- while an earlier boss (especially Demonic Overgrowth) is active. V7.6
-- allowed room 999 in every selectTarget pass, so it abandoned Overgrowth,
-- tried to path toward an inaccessible future Blood Minion, and became stuck.
function enemyRelevantForEncounter(enemy)
    if not enemy
        or not enemy.Model
        or not enemy.Humanoid
        or enemy.Humanoid.Health <= 0
        or not enemy.Root
        or not enemy.Root.Parent
    then
        return false
    end

    -- The active boss itself is always relevant.
    if Runtime.ActiveBossModel
        and enemy.Model == Runtime.ActiveBossModel
    then
        return true
    end

    local room =
        enemy.RoomIndex or 0

    -- Normal/current encounter.
    if Runtime.CurrentRoomIndex > 0
        and room == Runtime.CurrentRoomIndex
    then
        return true
    end

    -- room 999 entities are ONLY legal during the final encounter / cleanup.
    if room == 999 then
        return
            Runtime.CurrentRoomIndex == 999
            or Runtime.ActiveBossName == "Demon Lord Azrallik"
            or Runtime.ActiveBossName == "Miyamoto Musashi"
            or Runtime.FinalBossDefeated
    end

    -- Startup only: selectTarget will immediately infer the lowest live room.
    return Runtime.CurrentRoomIndex == 0
end



