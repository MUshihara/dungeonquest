-- DQR modular runtime: core/StuckController.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Stuck detection
-- ============================================================

function stuckThink()
    if not Runtime.Root or Runtime.CompletionConfirmed then
        return
    end

    if Runtime.BossWave
        or Runtime.MageWave
        or Runtime.MovementOwner == "TRANSIT"
        or Runtime.MovementOwner == "TRANSIT_SETTLE"
        or Runtime.MovementOwner == "AZRALLIK_POCKET_HOLD"
        or Runtime.MovementOwner == "AZRALLIK_FINGER_HOLD"
        or Runtime.MovementOwner == "AZRALLIK_FINGER_PREHOLD"
        or Runtime.MovementOwner == "KOLVUMAR_SPIT_HOLD"
    then
        Runtime.LastPosition =
            Runtime.Root.Position
        Runtime.LastPositionChange =
            os.clock()
        return
    end

    local now = os.clock()
    local pos = Runtime.Root.Position

    if not Runtime.LastPosition then
        Runtime.LastPosition = pos
        Runtime.LastPositionChange = now
        return
    end

    local moved =
        horizontalDistance(
            pos,
            Runtime.LastPosition
        )

    if moved >= 1.2 then
        Runtime.LastPosition = pos
        Runtime.LastPositionChange = now

        -- Real movement means the escape worked. Reset the escalation state.
        if moved >= 2.0 then
            Runtime.WallEscapeAttempts = 0
            Runtime.WallEscapeStarted = nil
            Runtime.BossStallBreakCount = 0
        end

        return
    end

    local stuckFor =
        now - Runtime.LastPositionChange

    if stuckFor < CFG.WALL_STUCK_TRIGGER then
        return
    end

    -- Combat movement needs an actual local escape, not just a path reset.
    local reason =
        Runtime.LastMoveReason
        or "unknown"

    if Runtime.WallEscapeAttempts
        >= CFG.STALL_BREAK_AFTER_ATTEMPTS
    then
        Runtime.WallEscapeAttempts = 0
        Runtime.WallEscapeStarted = nil
        Runtime.WallEscapePosition = nil
        Runtime.PathWaypoints = nil
        Runtime.PathDestination = nil
        Runtime.ApproachWaypoints = nil
        Runtime.ApproachFallbackPosition = nil
        Runtime.LastRepath = -math.huge
        Runtime.OrbitSign *= -1

        local preferred

        if Runtime.TargetRoot then
            local toward =
                unitHorizontal(
                    Runtime.TargetRoot.Position
                    - Runtime.Root.Position
                )

            preferred =
                Vector3.new(
                    -toward.Z,
                    0,
                    toward.X
                ) * Runtime.OrbitSign
        else
            preferred =
                unitHorizontal(
                    Runtime.Root.CFrame.RightVector
                ) * Runtime.OrbitSign
        end

        Runtime.BossStallBreakCount += 1

        if Runtime.TargetRoot
            and activeThreatCount() == 0
        then
            preferred =
                unitHorizontal(
                    Runtime.TargetRoot.Position
                    - Runtime.Root.Position
                )
        end

        local minRadius =
            math.min(
                CFG.BOSS_STALL_RECOVERY_MAX_RADIUS,
                CFG.BOSS_STALL_RECOVERY_MIN_RADIUS
                + (
                    Runtime.BossStallBreakCount - 1
                ) * 6
            )

        local open =
            chooseOpenSpacePoint(
                Runtime.Root.Position,
                preferred,
                minRadius
            )

        if open then
            moveTo(
                open.Position,
                "STALL_BREAK_PROGRESS"
            )
        end

        Runtime.LastPositionChange = now

        if now - Runtime.LastBossStallLog
            >= CFG.BOSS_STALL_LOG_COOLDOWN
        then
            Runtime.LastBossStallLog = now

            logKV("BOSS_PROGRESS_RECOVERY", {
                reason = tostring(reason),
                target = Runtime.Target
                    and Runtime.Target.Name
                    or "nil",
                room = Runtime.CurrentRoomIndex,
                attempt =
                    Runtime.BossStallBreakCount,
                radius =
                    open
                    and string.format(
                        "%.1f",
                        open.Radius
                    )
                    or "none",
                position =
                    open
                    and vec(open.Position)
                    or "none",
            })
        end

        return
    end

    if beginWallEscape(reason) then
        Runtime.LastPositionChange = now
        Runtime.PathWaypoints = nil
        Runtime.LastRepath = -math.huge

        return
    end

    -- Extremely rare final fallback: if we're physically wedged for several
    -- seconds AND danger is present, use a tiny bounded nudge into the already
    -- selected open-space point. This shares the global teleport budget.
    local escapeAge =
        Runtime.WallEscapeStarted
        and (now - Runtime.WallEscapeStarted)
        or 0

    if escapeAge >= CFG.WALL_HARD_STUCK_SECONDS
        and Runtime.WallEscapePosition
        and teleportBudgetAvailable(now)
    then
        local penalty, inside =
            pointDanger(Runtime.Root.Position)

        local physical, physicalDist =
            nearestPhysicalEnemy(Runtime.Root.Position)

        local immediateDanger =
            inside > 0
            or (
                physical
                and physicalDist <= CFG.MELEE_CRITICAL_RADIUS + 2
            )

        if immediateDanger then
            local plan = {
                Position = Runtime.WallEscapePosition,
                Radius = horizontalDistance(
                    Runtime.Root.Position,
                    Runtime.WallEscapePosition
                ),
                Label = "wall_nudge",
                Source = "wall_stuck",
                Clearance = 0,
            }

            if doFastShift(
                plan,
                CFG.WALL_NUDGE_MAX,
                CFG.TELEPORT_GLOBAL_COOLDOWN,
                "WALL_NUDGE",
                true
            ) then
                Runtime.LastPositionChange = now
                Runtime.WallEscapeStarted = nil
                Runtime.WallEscapeAttempts = 0
            end
        end
    end
end


