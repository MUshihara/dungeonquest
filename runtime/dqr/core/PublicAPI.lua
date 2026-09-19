-- DQR modular runtime: core/PublicAPI.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Stop / public API
-- ============================================================

Runtime.Stop = function(reason)
    if not Runtime.Alive then return end

    Runtime.Alive = false

    if stopTransitTween then
        stopTransitTween("runtime_stop")
    end

    if Runtime.Humanoid then
        pcall(function()
            Runtime.Humanoid:Move(
                Vector3.zero,
                false
            )

            if Runtime.AimPreviousAutoRotate ~= nil then
                Runtime.Humanoid.AutoRotate =
                    Runtime.AimPreviousAutoRotate
            else
                Runtime.Humanoid.AutoRotate = true
            end
        end)
    end

    logKV("SUMMARY", {
        reason = reason or "manual",
        style = CFG.STYLE,
        dodges = Runtime.DodgeCount,
        micro_dodges = Runtime.MicroCount,
        runtime = string.format(
            "%.1f",
            os.clock()-bootClock
        ),
    })

    flush()
    disconnectAll()

    if ENV[RUNTIME_KEY] == Runtime then
        ENV[RUNTIME_KEY] = nil
    end
end

ENV.DQR = {
    Version = "Modular-V1",

    Status = function()
        return {
            Style = CFG.STYLE,
            Dungeon = DQR_WORLD and DQR_WORLD.Name or "Unknown",
            Room = Runtime.CurrentRoomIndex,

            Boss = Runtime.ActiveBossName,
            Target =
                Runtime.Target
                and Runtime.Target.Name
                or nil,

            HP =
                Runtime.Humanoid
                and Runtime.Humanoid.Health
                or nil,

            MaxHP =
                Runtime.Humanoid
                and Runtime.Humanoid.MaxHealth
                or nil,

            MovementOwner =
                Runtime.MovementOwner,

            DodgeActive =
                Runtime.DodgeActive,

            DodgeCount =
                Runtime.DodgeCount,

            TeleportTotal =
                Runtime.TeleportTotal,

            LastTeleportTag =
                Runtime.LastTeleportTag,

            LastTeleportStuds =
                Runtime.LastTeleportStuds,

            CompletionConfirmed =
                Runtime.CompletionConfirmed,

            CompletionSource =
                Runtime.CompletionSource,

            GolemShatterTellAge =
                Runtime.GolemShatterTellAt
                    > -math.huge
                and (
                    os.clock()
                    - Runtime.GolemShatterTellAt
                )
                or nil,

            MiyamotoPhase =
                Runtime.MiyamotoPhase,

            MiyamotoCycloneActive =
                Runtime.MiyamotoCycloneActive,

            Log = LOG_PATH,
        }
    end,

    SetStyle = function(style)
        if STYLES[style] then
            CFG.STYLE = style
            Profile = STYLES[style]

            log(
                "STYLE",
                style
            )

            return true
        end

        return false
    end,

    Stop = function()
        Runtime.Stop(
            "user"
        )
    end,
}

logKV("START", {
    version = "Modular_V1",
    dungeon = DQR_WORLD and DQR_WORLD.Name or "Unknown",
    style = CFG.STYLE,
    place_id = game.PlaceId,
    universe_id = game.GameId,

    one_runtime_owner = true,
    one_movement_owner = true,
    tween_disabled = true,
    attack_while_dodging = CFG.DODGE_CAST_ENABLED,

    strongest_first_floor_targeting = true,
    sticky_target_lock = CFG.TARGET_LOCK_ENABLED,
    local_finish = CFG.LOCAL_FINISH_ENABLED,
    boss_hard_priority = true,
    boss_add_burst = CFG.BOSS_ADD_INTERCEPT_ENABLED,

    shuriken_ranged_pressure = true,
    physical_pressure_handoff =
        CFG.PHYSICAL_DODGE_HANDOFF_ENABLED,

    sanada_cross_local_gap = true,
    golem_shatter_prediction = true,
    golem_shatter_tell =
        CFG.GOLEM_SHATTER_TELL_ANIM,
    golem_local_gap = true,
    miyamoto_client_event_observer = true,
    miyamoto_doublebeam_local_gap = true,

    direct_shift_governor = true,
    direct_shift_cooldown =
        CFG.TELEPORT_GLOBAL_COOLDOWN,

    authoritative_completion = true,
    ability_result_diagnostic =
        CFG.ABILITY_RESULT_DIAGNOSTIC,
})

do
    local names = {}
    if DQR_WORLD and type(DQR_WORLD.Attacks) == "table" then
        for rootName in pairs(DQR_WORLD.Attacks) do
            names[#names + 1] = rootName
        end
        table.sort(names)
    end
    log("WORLD_KNOWN_ATTACKS", table.concat(names, ","))
end

flush()


if DQR_WORLD then
    if DQR_WORLD.Slug == "samurai_palace" then
        ENV.DQRSamuraiPalace = ENV.DQR
    elseif DQR_WORLD.Slug == "underworld" then
        ENV.DQRUnderworld = ENV.DQR
    end
end
