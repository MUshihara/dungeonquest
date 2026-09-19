-- DQR modular runtime: core/MainController.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Main controller
-- ============================================================

function controllerStep()
    if not CFG.ENABLED then
        return
    end

    local char,hum,root = getCharacter()

    if not char
        or not hum
        or hum.Health <= 0
        or not root
    then
        return
    end

    Runtime.Character = char
    Runtime.Humanoid = hum
    Runtime.Root = root

    if updateSafeAnchor() then
        return
    end

    updateAimLock()

    local now = os.clock()

    if now-Runtime.LastTargetScan
        >= CFG.TARGET_REFRESH
    then
        Runtime.LastTargetScan = now
        rebuildEnemyCache()
        refreshBossState()

        selectTarget()
        refreshAnimators()
    end

    -- Authoritative completion is the only point where V7 fully stops combat.
    if Runtime.CompletionConfirmed then
        if not Runtime.CompletionWaitLogged then
            Runtime.CompletionWaitLogged = true
            logKV("COMPLETION_WAIT", {
                source = tostring(Runtime.CompletionSource),
            })
        end

        clearDodge("completion_confirmed")
        Runtime.PathWaypoints = nil
        Runtime.PathDestination = nil
        Runtime.Target = nil
        Runtime.TargetHumanoid = nil
        Runtime.TargetRoot = nil

        pcall(function()
            Runtime.Humanoid:Move(Vector3.zero, false)
        end)

        return
    end

    -- Final boss is gone but completion has NOT been confirmed yet.
    -- Keep killing any remaining encounter adds (especially Blood Minions).
    -- If nothing remains, simply hold; never path back to room999.
    if Runtime.FinalBossDefeated
        and (
            not Runtime.TargetRoot
            or not Runtime.TargetHumanoid
            or Runtime.TargetHumanoid.Health <= 0
        )
    then
        if not Runtime.CompletionWaitLogged then
            Runtime.CompletionWaitLogged = true
            log("POST_BOSS_CLEANUP", "waiting_for_adds_or_completion_signal")
        end

        clearDodge("post_boss_no_target")
        Runtime.PathWaypoints = nil
        Runtime.PathDestination = nil

        if safeIdleThink() then
            stuckThink()
            return
        end

        -- No immediate enemy and already in open space: hold normally while
        -- waiting for the authoritative completion signal.
        pcall(function()
            Runtime.Humanoid:Move(Vector3.zero, false)
        end)

        return
    end

    if Runtime.FinalBossDefeated
        and Runtime.TargetRoot
        and Runtime.TargetHumanoid
        and Runtime.TargetHumanoid.Health > 0
    then
        Runtime.CompletionWaitLogged = false
    end

    if Runtime.TransitTween
        and transitCombatShouldStop()
    then
        stopTransitTween("combat_started")
    end

    -- 1. Highest priority: survival movement.
    -- V6 may still fire a ready skill while kiting if the current position is
    -- outside real attack geometry and contact is not imminent.
    if dodgeThink() then
        if CFG.AUTO_ABILITIES then
            -- Movement already owns the escape path. Keep firing instant skills
            -- through mage/boss red-line movement when there is no immediate
            -- physical collision risk.
            attackThink(true)
        end

        if not Runtime.BossWave
            and not Runtime.MageWave
        then
            stuckThink()
        end

        return
    end

    -- 2. If movement got pinned against geometry, commit briefly to the
    -- selected open-space escape. Attacks can still fire while moving.
    if wallEscapeThink() then
        attackThink()
        stuckThink()
        return
    end

    -- 3. Fight current enemy using ordinary Humanoid/path movement.
    -- V7.7 intentionally does not use forward CFrame tween transit.
    if Runtime.TargetRoot
        and Runtime.TargetHumanoid
        and Runtime.TargetHumanoid.Health > 0
    then
        combatMovement()
        attackThink()
        stuckThink()
        return
    end

    -- 4. Move to next room.
    if navigationThink() then
        if Runtime.MovementOwner ~= "TRANSIT"
            and Runtime.MovementOwner ~= "TRANSIT_SETTLE"
        then
            stuckThink()
        end

        return
    end

    -- 5. Nothing to navigate to yet: do not freeze beside a wall or a
    -- non-telegraphed physical enemy while waiting for the next state.
    safeIdleThink()
    stuckThink()
end

Runtime.BossHeartbeatThink = function(now)
    if not Runtime.ActiveBossName
        or not Runtime.Root
        or not Runtime.Humanoid
    then
        return
    end

    if now - Runtime.LastBossHeartbeat
        < CFG.BOSS_HEARTBEAT_INTERVAL
    then
        return
    end

    Runtime.LastBossHeartbeat = now

    local bossHp = "nil"

    if Runtime.ActiveBossModel then
        local hum =
            Runtime.ActiveBossModel:FindFirstChildOfClass(
                "Humanoid"
            )

        if hum then
            bossHp =
                string.format(
                    "%.0f",
                    hum.Health
                )
        end
    end

    local lastShiftAge =
        Runtime.LastTeleportAt == -math.huge
        and "inf"
        or string.format(
            "%.2f",
            now - Runtime.LastTeleportAt
        )

    logKV("BOSS_HEARTBEAT", {
        boss = Runtime.ActiveBossName,
        boss_hp = bossHp,
        player_hp = string.format(
            "%.0f",
            Runtime.Humanoid.Health
        ),
        position = vec(Runtime.Root.Position),
        room = Runtime.CurrentRoomIndex,
        wave =
            Runtime.BossWave
            and Runtime.BossWave.Id
            or "none",
        shift_age = lastShiftAge,
        shift_total = Runtime.TeleportTotal,
        last_shift =
            tostring(
                Runtime.LastTeleportTag
                or "none"
            ),
        threats = activeThreatCount(),
        movement_owner =
            tostring(
                Runtime.MovementOwner
                or "NONE"
            ),
        dodge_label =
            Runtime.LastDodgeMoveLabel
            or "none",
        dodge_remaining =
            Runtime.LastDodgeMoveTarget
            and string.format(
                "%.2f",
                horizontalDistance(
                    Runtime.Root.Position,
                    Runtime.LastDodgeMoveTarget
                )
            )
            or "none",
        speed =
            string.format(
                "%.2f",
                horizontal(
                    Runtime.Root.AssemblyLinearVelocity
                ).Magnitude
            ),
    })
end


connect(
    RunService.Heartbeat,
    function()
        if not Runtime.Alive
            or Runtime.HaltForDisconnect
        then
            return
        end

        local now = os.clock()

        Runtime.BossHeartbeatThink(now)

        if now-Runtime.LastThink
            >= CFG.THINK_INTERVAL
        then
            Runtime.LastThink = now

            local ok,err =
                pcall(controllerStep)

            if not ok then
                log("ERROR",tostring(err))
            end
        end

        if now-Runtime.LastFlush
            >= CFG.FLUSH_INTERVAL
        then
            Runtime.LastFlush = now
            flush()
        end
    end
)


