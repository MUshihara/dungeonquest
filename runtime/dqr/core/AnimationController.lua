-- DQR modular runtime: core/AnimationController.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Enemy animation prediction
-- ============================================================

function addVirtualThreat(id, center, radius, lifetime, source)
    -- The same enemy can emit AnimationPlayed more than once in an executor.
    -- Reuse one hazard per enemy/id instead of creating dozens of circles.
    local old = Runtime.VirtualThreats[id]
    local isNew = old == nil

    Runtime.VirtualThreats[id] = {
        Center = center,
        Radius = radius,
        Created = old and old.Created or os.clock(),
        Expires = os.clock() + lifetime,
        Source = source,
    }

    if isNew then
        logKV("VIRTUAL_THREAT", {
            source = source,
            radius = radius,
            center = vec(center),
        })
    end
end

function watchEnemyAnimator(model)
    if not model or Players:GetPlayerFromCharacter(model) then return end

    local hum = modelHumanoid(model)
    if not hum then return end

    local animator =
        hum:FindFirstChildOfClass("Animator")
        or hum:FindFirstChild("Animator")

    if not animator or Runtime.WatchedAnimators[animator] then
        return
    end

    -- Strong-key dedupe. We clean the entry when the Animator leaves.
    Runtime.WatchedAnimators[animator] = true

    connect(animator.AncestryChanged, function(_, parent)
        if parent == nil then
            Runtime.WatchedAnimators[animator] = nil
            Runtime.LastAnimationEvent[model] = nil
        end
    end)

    connect(animator.AnimationPlayed, function(track)
        if not Runtime.Alive then return end

        local priority = track.Priority

        if priority ~= Enum.AnimationPriority.Action
            and priority ~= Enum.AnimationPriority.Action2
            and priority ~= Enum.AnimationPriority.Action3
            and priority ~= Enum.AnimationPriority.Action4
        then
            return
        end

        local root = modelRoot(model)
        if not root or not Runtime.Root then return end

        local animId = "unknown"

        pcall(function()
            if track.Animation then
                animId = track.Animation.AnimationId
            end
        end)

        -- Some executors/replicated NPCs surfaced the exact same animation
        -- callback many times in the same frame. One event is enough.
        local now = os.clock()
        local previousAnim = Runtime.LastAnimationEvent[model]

        if previousAnim
            and previousAnim.Id == animId
            and now - previousAnim.At <= CFG.ANIMATION_DEDUPE_WINDOW
        then
            return
        end

        Runtime.LastAnimationEvent[model] = {
            Id = animId,
            At = now,
        }

        local dist =
            horizontalDistance(
                root.Position,
                Runtime.Root.Position
            )

        logKV("ENEMY_ACTION_ANIM", {
            enemy = model.Name,
            animation = animId,
            distance = string.format("%.1f", dist),
        })


        -- Samurai Swordsman: Action tell was observed on the physical mob.
        -- Physical closing-speed logic remains primary; this short virtual
        -- circle only represents the confirmed attack window.
        if model.Name == "Samurai Swordsman"
            and animId
                == CFG.SAMURAI_SWORDSMAN_ATTACK_ANIM
            and dist <= 24
        then
            Runtime.LastMeleeAttackAt[
                model
            ] = now

            addVirtualThreat(
                model,
                root.Position,
                13.5,
                0.66,
                "Samurai Swordsman Attack"
            )
        end

        -- Ancient Golem Guardian rockshatter predictor:
        -- recon repeatedly measured this animation -> 9 rockshatter lines
        -- in ~1.25-1.61 sec. Start a normal lateral/orbit premove early.
        if model.Name
                == "Ancient Golem Guardian"
            and animId
                == CFG.GOLEM_SHATTER_TELL_ANIM
        then
            Runtime.GolemShatterTellAt =
                now
            Runtime.GolemShatterTellOrigin =
                Runtime.Root.Position
            Runtime.GolemShatterPlan =
                nil

            if now
                - Runtime.LastGolemShatterLog
                >= CFG.GOLEM_SHATTER_LOG_COOLDOWN
            then
                Runtime.LastGolemShatterLog =
                    now

                logKV(
                    "GOLEM_SHATTER_TELL",
                    {
                        distance =
                            string.format(
                                "%.1f",
                                dist
                            ),
                        eta_min =
                            string.format(
                                "%.2f",
                                CFG.GOLEM_SHATTER_EXPECTED_MIN
                            ),
                        eta_max =
                            string.format(
                                "%.2f",
                                CFG.GOLEM_SHATTER_EXPECTED_MAX
                            ),
                    }
                )
            end
        end

        if model.Name
                == "Ancient Golem Guardian"
            and animId
                == CFG.GOLEM_ROCK_TELL_ANIM
        then
            Runtime.GolemRockTellAt =
                now

            logKV(
                "GOLEM_ROCK_TELL",
                {
                    distance =
                        string.format(
                            "%.1f",
                            dist
                        ),
                }
            )
        end


        if model.Name == "Demon Lord Azrallik"
            and animId == CFG.AZRALLIK_SPREAD_TELL_ANIM
        then
            Runtime.AzrallikSpreadTellAt = now
            Runtime.AzrallikSpreadTellOrigin =
                Runtime.Root.Position
            Runtime.AzrallikSpreadOrbitSign =
                Runtime.OrbitSign ~= 0
                and Runtime.OrbitSign
                or 1

            if now - Runtime.LastAzrallikSpreadTellLog
                >= CFG.AZRALLIK_SPREAD_LOG_COOLDOWN
            then
                Runtime.LastAzrallikSpreadTellLog = now

                logKV("AZRALLIK_SPREAD_TELL", {
                    distance =
                        string.format("%.1f", dist),
                    eta =
                        string.format(
                            "%.2f",
                            CFG.AZRALLIK_SPREAD_EXPECTED_DELAY
                        ),
                    origin =
                        vec(Runtime.Root.Position),
                })
            end
        end

        if model.Name == "Demon Lord Azrallik"
            and animId == CFG.AZRALLIK_FINGER_TELL_ANIM
        then
            Runtime.AzrallikFingerTellAt = now
            Runtime.AzrallikFingerTellOrigin = Runtime.Root.Position
            Runtime.AzrallikFingerTellMoved = false

            if now - Runtime.LastAzrallikFingerTellLog
                >= CFG.AZRALLIK_FINGER_TELL_LOG_COOLDOWN
            then
                Runtime.LastAzrallikFingerTellLog = now

                logKV("AZRALLIK_FINGER_TELL", {
                    distance = string.format("%.1f", dist),
                    origin = vec(Runtime.Root.Position),
                })
            end
        end

        -- One virtual close-range hazard PER enemy. Repeated callbacks only
        -- refresh it rather than multiplying the threat count.
        if model.Name == "Demon Warrior"
            and dist <= 24
            and DEMON_WARRIOR_ATTACK_ANIMS[animId]
        then
            Runtime.LastMeleeAttackAt[model] = now

            addVirtualThreat(
                model,
                root.Position,
                CFG.DEMON_WARRIOR_ATTACK_RADIUS,
                CFG.DEMON_WARRIOR_ATTACK_LIFETIME,
                "Demon Warrior Attack"
            )

        elseif model.Name == "Blood Minion"
            and dist <= CFG.BLOOD_MINION_ANIM_THREAT_RADIUS + 8
        then
            addVirtualThreat(
                model,
                root.Position,
                CFG.BLOOD_MINION_ANIM_THREAT_RADIUS,
                0.95,
                "Blood Minion Action"
            )

        elseif model.Name == "Kolvumar"
            and KOLVUMAR_DIRECT_ATTACK_ANIMS[animId]
        then
            addVirtualThreat(
                "KolvumarDirect:" .. tostring(model),
                root.Position,
                CFG.KOLVUMAR_DIRECT_SAFE_RADIUS,
                CFG.KOLVUMAR_DIRECT_THREAT_LIFETIME,
                "Kolvumar NonRed Sequence"
            )
        end
    end)
end

function refreshAnimators()
    for _, e in ipairs(livingEnemies()) do
        watchEnemyAnimator(e.Model)
    end
end

function refreshBossState()
    local found

    for _, enemy in ipairs(livingEnemies()) do
        if enemy.Model
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and BOSS_ENEMY_NAMES[enemy.Model.Name]
        then
            found = enemy
            break
        end
    end

    local newName = found and found.Model.Name or nil

    if newName ~= Runtime.ActiveBossName then
        local oldName = Runtime.ActiveBossName

        logKV("BOSS_STATE", {
            old = tostring(oldName),
            new = tostring(newName),
        })

        if DQR_WORLD and newName == DQR_WORLD.FinalBossName then
            Runtime.SawFinalBoss = true
        end

        if DQR_WORLD
            and oldName == DQR_WORLD.FinalBossName
            and newName == nil
            and Runtime.SawFinalBoss
            and Runtime.CurrentRoomIndex == 999
        then
            Runtime.AzrallikHeartPhaseActive = false
            Runtime.AzrallikHeartModel = nil
            Runtime.AzrallikHeartStartedAt = nil
            Runtime.AzrallikSpreadTellAt = -math.huge
            Runtime.AzrallikSpreadTellOrigin = nil
            Runtime.FinalBossDefeated = true
            Runtime.FinalBossDefeatedAt = os.clock()
            Runtime.BossWave = nil
            Runtime.MageWave = nil
            Runtime.PathWaypoints = nil
            Runtime.PathDestination = nil

            -- Do NOT clear the target here. V6 could stop while a Blood Minion
            -- was still alive, preventing the authoritative completion state.
            log("FINAL_BOSS_GONE", "cleanup_remaining_hostiles")
        end

        if oldName
            and newName == nil
        then
            Runtime.BeginBossCleanup(
                oldName
            )
        end

        Runtime.ActiveBossName = newName
        Runtime.ActiveBossModel = found and found.Model or nil

        if newName == nil then
            clearBossAddFocus("boss_ended")
        end
        Runtime.ActiveBossRoot = found and found.Root or nil
        Runtime.BossWave = nil

        if newName then
            -- Do not let a leftover room path keep owning movement once the
            -- boss encounter is close enough to control directly.
            Runtime.PathWaypoints = nil
            Runtime.PathDestination = nil
        end
    elseif found then
        Runtime.ActiveBossModel = found.Model
        Runtime.ActiveBossRoot = found.Root
    end
end


