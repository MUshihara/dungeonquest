-- DQR modular runtime: core/MovementController.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Movement
-- ============================================================

function encounterStillActive()
    if Runtime.ActiveBossName then
        return true
    end

    return
        Runtime.TargetHumanoid
        and Runtime.TargetHumanoid.Parent
        and Runtime.TargetHumanoid.Health > 0
end

function isThreatSolverMove(reason)
    reason = tostring(reason or "")

    return
        reason == "DODGE"
        or reason == "POST_SHIFT_CONTINUE"
        or reason == "BOSS_WAVE"
        or reason == "MAGE_WAVE"
        or reason == "AZRALLIK_SWEEP_GAP"
        or reason == "KOLVUMAR_SPIT_ESCAPE"
        or reason == "KOLVUMAR_SPIT_HOLD"
        or reason == "KOLVUMAR_SPIT_SLIDE"
        or reason == "KOLVUMAR_SPIT_COOLDOWN_SLIDE"
        or reason == "AZRALLIK_BEAM_POCKET"
        or reason == "AZRALLIK_BEAM_EARLY"
        or reason == "AZRALLIK_FINGER"
        or reason == "AZRALLIK_FINGER_PREMOVE"
        or reason == "AZRALLIK_POCKET_ADVANCE"
        or reason == "AZRALLIK_LANE_SLIDE"
        or reason == "AZRALLIK_SAFE_PRESSURE"
        or reason == "OVERGROWTH_EDGE"
        or reason == "OVERGROWTH_LONGLINE_POCKET"
        or reason == "STALL_BREAK_PROGRESS"
        or reason == "OVERGROWTH_FORWARD"
        or reason == "WALL_ESCAPE"
end

function strictRedSafeDestination(desired, reason)
    if not Runtime.Root
        or not desired
        or not encounterStillActive()
        or activeThreatCount() <= 0
        or isThreatSolverMove(reason)
    then
        return desired, true
    end

    local origin =
        Runtime.Root.Position

    local _, inside =
        pointDanger(desired)

    local route =
        routeDanger(
            origin,
            desired
        )

    if inside == 0
        and route <= CFG.STRICT_RED_ROUTE_LIMIT
    then
        return desired, true
    end

    local preferred =
        unitHorizontal(
            desired - origin
        )

    local open =
        chooseOpenSpacePoint(
            origin,
            preferred
        )

    if open then
        local _, openInside =
            pointDanger(open.Position)

        local openRoute =
            routeDanger(
                origin,
                open.Position
            )

        if openInside == 0
            and openRoute <= CFG.STRICT_RED_ROUTE_LIMIT
        then
            if os.clock() - Runtime.LastStrictRedLog
                >= CFG.STRICT_RED_LOG_COOLDOWN
            then
                Runtime.LastStrictRedLog =
                    os.clock()

                logKV("RED_ROUTE_BLOCK", {
                    reason = tostring(reason),
                    inside = inside,
                    route = string.format("%.0f", route),
                    requested = vec(desired),
                    resolved = vec(open.Position),
                })
            end

            return open.Position, true
        end
    end

    if os.clock() - Runtime.LastStrictRedLog
        >= CFG.STRICT_RED_LOG_COOLDOWN
    then
        Runtime.LastStrictRedLog =
            os.clock()

        logKV("RED_ROUTE_HOLD", {
            reason = tostring(reason),
            inside = inside,
            route = string.format("%.0f", route),
            requested = vec(desired),
        })
    end

    return nil, false
end


function logMoveReject(reason, reject, requested)
    local now = os.clock()
    local key =
        tostring(reason)
        .. "|"
        .. tostring(reject)

    if key ~= Runtime.LastMoveRejectKey
        or now - Runtime.LastMoveRejectLog
            >= CFG.MOVE_REJECT_LOG_COOLDOWN
    then
        Runtime.LastMoveRejectKey = key
        Runtime.LastMoveRejectLog = now

        logKV("MOVE_REJECT", {
            reason = tostring(reason),
            reject = tostring(reject),
            requested = vec(requested),
            current =
                Runtime.Root
                and vec(Runtime.Root.Position)
                or "nil",
        })
    end
end


stopTransitTween = nil

moveTo = function(position, reason)
    if not Runtime.Humanoid
        or not Runtime.Root
        or not Runtime.Humanoid.Parent
    then
        return
    end

    if Runtime.TransitTween then
        stopTransitTween("movement_override:" .. tostring(reason))
    end

    local now = os.clock()

    if now - Runtime.LastMove < CFG.MOVE_REFRESH then
        return
    end

    Runtime.LastMove = now

    local requested = position

    local safeRequested, rejectReason =
        safeMovementDestination(
            requested,
            Runtime.Root.Position
        )

    if not safeRequested
        and isThreatSolverMove(reason)
    then
        local preferred =
            unitHorizontal(
                requested
                - Runtime.Root.Position
            )

        local fallbackMinRadius

        if Runtime.ActiveBossName == "Demon Lord Azrallik"
            and reason == "BOSS_WAVE"
        then
            fallbackMinRadius =
                CFG.AZRALLIK_INVALID_DEST_MIN_RADIUS
        end

        local fallback =
            chooseOpenSpacePoint(
                Runtime.Root.Position,
                preferred,
                fallbackMinRadius
            )

        if fallback then
            local fallbackSafe =
                safeMovementDestination(
                    fallback.Position,
                    Runtime.Root.Position
                )

            if fallbackSafe then
                logKV("DODGE_DESTINATION_FALLBACK", {
                    reason = tostring(reason),
                    reject = tostring(rejectReason),
                    requested = vec(requested),
                    fallback = vec(fallback.Position),
                    radius =
                        string.format(
                            "%.1f",
                            fallback.Radius
                        ),
                })

                requested =
                    fallback.Position
                safeRequested = true
                rejectReason = "fallback"
            end
        end
    end

    if not safeRequested then
        logMoveReject(
            reason,
            rejectReason,
            requested
        )

        Runtime.ApproachWaypoints = nil
        Runtime.PathWaypoints = nil
        Runtime.ApproachFallbackPosition = nil

        return
    end

    local resolved =
        resolveWallAwareDestination(
            Runtime.Root.Position,
            requested,
            reason
        )

    local safeResolved, resolvedReject =
        safeMovementDestination(
            resolved,
            Runtime.Root.Position
        )

    if not safeResolved
        and isThreatSolverMove(reason)
    then
        local preferred =
            unitHorizontal(
                requested
                - Runtime.Root.Position
            )

        local fallbackMinRadius

        if Runtime.ActiveBossName == "Demon Lord Azrallik"
            and reason == "BOSS_WAVE"
        then
            fallbackMinRadius =
                CFG.AZRALLIK_INVALID_DEST_MIN_RADIUS
        end

        local fallback =
            chooseOpenSpacePoint(
                Runtime.Root.Position,
                preferred,
                fallbackMinRadius
            )

        if fallback then
            local fallbackSafe =
                safeMovementDestination(
                    fallback.Position,
                    Runtime.Root.Position
                )

            if fallbackSafe then
                logKV("DODGE_RESOLVED_FALLBACK", {
                    reason = tostring(reason),
                    reject = tostring(resolvedReject),
                    resolved = vec(resolved),
                    fallback = vec(fallback.Position),
                    radius =
                        string.format(
                            "%.1f",
                            fallback.Radius
                        ),
                })

                resolved =
                    fallback.Position
                safeResolved = true
                resolvedReject = "fallback"
            end
        end
    end

    if not safeResolved then
        logMoveReject(
            reason,
            resolvedReject,
            resolved
        )

        return
    end

    local strictResolved, strictOkay =
        strictRedSafeDestination(
            resolved,
            reason
        )

    if not strictOkay or not strictResolved then
        pcall(function()
            Runtime.Humanoid:Move(
                Vector3.zero,
                false
            )
        end)

        return
    end

    resolved = strictResolved

    Runtime.MovementOwner = "MOVE_TO"
    Runtime.LastMoveTarget = requested
    Runtime.LastMoveResolved = resolved
    Runtime.LastMoveReason = reason

    Runtime.Humanoid:MoveTo(resolved)
end

function faceTarget(targetModel)
    if not Runtime.Root then
        return
    end

    local targetRoot = Runtime.TargetRoot

    if targetModel and targetModel:IsA("Model") then
        targetRoot = modelRoot(targetModel) or targetRoot
    end

    if not targetRoot or not targetRoot.Parent then
        return
    end

    local here = Runtime.Root.Position

    local target =
        targetRoot.Position
        + horizontal(targetRoot.AssemblyLinearVelocity)
            * CFG.ABILITY_AIM_LEAD_TIME

    local flatTarget =
        Vector3.new(
            target.X,
            here.Y,
            target.Z
        )

    if horizontalDistance(here, flatTarget) > 0.5 then
        pcall(function()
            Runtime.Root.CFrame =
                CFrame.lookAt(
                    here,
                    flatTarget
                )
        end)
    end
end

function beginAimLock()
    Runtime.AimTarget = Runtime.Target
    Runtime.AimLockUntil =
        os.clock() + CFG.ABILITY_AIM_LOCK_TIME

    if Runtime.Humanoid then
        if Runtime.AimPreviousAutoRotate == nil then
            Runtime.AimPreviousAutoRotate =
                Runtime.Humanoid.AutoRotate
        end

        Runtime.Humanoid.AutoRotate = false
    end

    faceTarget(Runtime.AimTarget)
end

function updateAimLock()
    if not Runtime.Humanoid then return end

    if Runtime.AimTarget
        and os.clock() <= Runtime.AimLockUntil
        and Runtime.AimTarget.Parent
    then
        Runtime.Humanoid.AutoRotate = false
        faceTarget(Runtime.AimTarget)
    else
        Runtime.AimTarget = nil

        if Runtime.AimPreviousAutoRotate ~= nil then
            Runtime.Humanoid.AutoRotate =
                Runtime.AimPreviousAutoRotate

            Runtime.AimPreviousAutoRotate = nil
        end
    end
end

function abilityDangerImminent()
    if not Runtime.Root then
        return true
    end

    local predicted =
        Runtime.Root.Position
        + horizontal(Runtime.Root.AssemblyLinearVelocity)
            * CFG.ABILITY_SAFE_PREDICT_TIME

    -- Only real attack geometry blocks a cast. Proactive melee spacing by
    -- itself should not suppress skills while we are safely kiting.
    for _, meta in ipairs(activeThreats()) do
        if pointInsideThreat(meta, Runtime.Root.Position)
            or pointInsideThreat(meta, predicted)
        then
            return true
        end
    end

    for _, vt in pairs(Runtime.VirtualThreats) do
        if pointInsideVirtual(Runtime.Root.Position, vt)
            or pointInsideVirtual(predicted, vt)
        then
            return true
        end
    end

    local enemy, dist = nearestPhysicalEnemy(Runtime.Root.Position)

    if enemy then
        local dynamicRadius, closing, timeToContact =
            physicalClosingInfo(enemy, Runtime.Root.Position)

        if dist <= CFG.MELEE_CRITICAL_RADIUS then
            return true
        end

        if closing > 2.5
            and timeToContact <= 0.30
        then
            return true
        end
    end

    return false
end


Runtime.DodgeCastBlocked = function()
    if not Runtime.Root
        or not Runtime.Humanoid
        or Runtime.Humanoid.Health <= 0
    then
        return true
    end

    local hpRatio =
        Runtime.Humanoid.MaxHealth > 0
        and (
            Runtime.Humanoid.Health
            / Runtime.Humanoid.MaxHealth
        )
        or 1

    local minimumHp =
        Runtime.FragileMode
        and CFG.DODGE_CAST_FRAGILE_MIN_HP_RATIO
        or CFG.DODGE_CAST_MIN_HP_RATIO

    if hpRatio < minimumHp then
        return true
    end

    local enemy, dist =
        nearestPhysicalEnemy(
            Runtime.Root.Position
        )

    if enemy then
        local _, closing, timeToContact =
            physicalClosingInfo(
                enemy,
                Runtime.Root.Position
            )

        if dist <= CFG.DODGE_CAST_PHYSICAL_GUARD then
            return true
        end

        if closing > 2.5
            and timeToContact <= CFG.DODGE_CAST_TTC_GUARD
        then
            return true
        end
    end

    return false
end


function lineEmergencyCandidate(origin, threats)
    local oldPenalty, oldInside = pointDanger(origin)
    local best
    local bestScore = math.huge

    for _, meta in ipairs(threats) do
        local g = threatGeometry(meta)

        if g and g.Type == "Box"
            and meta.Kind == "Precast"
            and pointInsideThreat(meta, origin)
        then
            local part = g.Part
            local lp = part.CFrame:PointToObjectSpace(origin)
            local axisA, axisB = horizontalAxesForPart(part)

            local shortAxis, longAxis = axisA, axisB
            if axisB.Half < axisA.Half then
                shortAxis, longAxis = axisB, axisA
            end

            local aspect =
                longAxis.Half / math.max(shortAxis.Half, 0.1)

            if aspect >= CFG.LARGE_LINE_ASPECT_RATIO then
                local worldAxis = horizontal(shortAxis.Vec)

                if worldAxis.Magnitude > 0.05 then
                    worldAxis = worldAxis.Unit

                    local coord =
                        componentByIndex(lp, shortAxis.LocalIndex)

                    local plus =
                        shortAxis.Half
                        + CFG.SAFETY_MARGIN
                        - coord
                        + CFG.LARGE_LINE_EXTRA_MARGIN

                    local minus =
                        shortAxis.Half
                        + CFG.SAFETY_MARGIN
                        + coord
                        + CFG.LARGE_LINE_EXTRA_MARGIN

                    for _, option in ipairs({
                        {Dir = worldAxis, Distance = plus, Label = "line_short_plus"},
                        {Dir = -worldAxis, Distance = minus, Label = "line_short_minus"},
                    }) do
                        if option.Distance > 0
                            and option.Distance <= CFG.LARGE_LINE_FAST_SHIFT_MAX
                        then
                            local pos = origin + option.Dir * option.Distance
                            local penalty, inside = pointDanger(pos)

                            if inside < oldInside then
                                local score =
                                    penalty
                                    + option.Distance * 5
                                    + enemyPenalty(pos)

                                if score < bestScore then
                                    bestScore = score
                                    best = {
                                        Position = pos,
                                        Radius = option.Distance,
                                        Label = option.Label,
                                        OldInside = oldInside,
                                        NewInside = inside,
                                        Source = meta.RootName,
                                        ThreatCreated = meta.Created,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

function walkingLikelyEnough(plan, estimatedImpactAt)
    if not plan
        or not Runtime.Root
        or not Runtime.Humanoid
    then
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            plan.Position
        )

    local walkSpeed = math.max(Runtime.Humanoid.WalkSpeed, 1)
    local walkEta = distance / walkSpeed

    local timeLeft =
        math.max(
            0,
            estimatedImpactAt - os.clock()
        )

    return walkEta + CFG.WALK_ETA_SAFETY <= timeLeft
end

function teleportBudgetStatus(now)
    now = now or os.clock()

    local kept = {}

    for _, at in ipairs(Runtime.TeleportHistory) do
        if now - at <= CFG.TELEPORT_WINDOW_SECONDS then
            kept[#kept + 1] = at
        end
    end

    Runtime.TeleportHistory = kept

    local sinceLast =
        now - Runtime.LastTeleportAt

    if sinceLast < CFG.TELEPORT_GLOBAL_COOLDOWN then
        return
            false,
            "global_cooldown",
            CFG.TELEPORT_GLOBAL_COOLDOWN - sinceLast
    end

    if #Runtime.TeleportHistory
        >= CFG.TELEPORT_WINDOW_MAX
    then
        local oldest =
            Runtime.TeleportHistory[1]

        return
            false,
            "window_budget",
            math.max(
                0,
                CFG.TELEPORT_WINDOW_SECONDS
                - (now - oldest)
            )
    end

    return true, "ok", 0
end

function teleportBudgetAvailable(now)
    local okay =
        teleportBudgetStatus(now)

    return okay == true
end

function logTeleportBlocked(source, now)
    now = now or os.clock()

    if now - Runtime.LastTeleportBlockLog
        < CFG.TELEPORT_BLOCK_LOG_COOLDOWN
    then
        return
    end

    local okay, reason, remaining =
        teleportBudgetStatus(now)

    if okay then
        return
    end

    Runtime.LastTeleportBlockLog = now

    logKV("TELEPORT_GOVERNOR_BLOCK", {
        source = tostring(source),
        reason = tostring(reason),
        remaining = string.format(
            "%.2f",
            remaining or 0
        ),
        since_last = string.format(
            "%.2f",
            now - Runtime.LastTeleportAt
        ),
        last_tag =
            tostring(
                Runtime.LastTeleportTag
                or "none"
            ),
        total = Runtime.TeleportTotal,
    })
end

function recordTeleport(
    now,
    tag,
    fromPosition,
    toPosition,
    studs
)
    now = now or os.clock()

    Runtime.LastTeleportAt = now
    Runtime.TeleportHistory[
        #Runtime.TeleportHistory + 1
    ] = now

    Runtime.TeleportTotal += 1
    Runtime.LastTeleportTag =
        tag or "POSITION_SHIFT"
    Runtime.LastTeleportFrom =
        fromPosition
    Runtime.LastTeleportTo =
        toPosition
    Runtime.LastTeleportStuds =
        studs or 0
end


function shiftPlanIsIntentionalHold(best)
    if not best then
        return false
    end

    return
        best.Label == "azrallik_finger_hold"
        or best.Label == "azrallik_beam_early_hold"
        or best.Label == "overgrowth_forward_hold"
        or best.Label == "kolvumar_spit_hold"
        or best.Label == "kolvumar_spit_emergency"
end

function rearmMovementAfterShift(
    best,
    candidate,
    counterTag
)
    if not CFG.POST_SHIFT_CONTINUE_ENABLED
        or not best
        or not best.Position
        or not Runtime.Humanoid
        or not Runtime.Root
        or shiftPlanIsIntentionalHold(best)
    then
        return
    end

    local remaining =
        horizontalDistance(
            candidate,
            best.Position
        )

    if remaining
        < CFG.POST_SHIFT_CONTINUE_MIN_DISTANCE
    then
        return
    end

    local direction =
        unitHorizontal(
            best.Position - candidate
        )

    if direction.Magnitude <= 0.1 then
        return
    end

    local step =
        math.min(
            remaining,
            CFG.POST_SHIFT_CONTINUE_MAX_STEP
        )

    local localTarget =
        candidate
        + direction * step

    local destinationOkay =
        safeMovementDestination(
            localTarget,
            candidate
        )

    if not destinationOkay
        or movementWallHit(
            candidate,
            localTarget
        )
    then
        return
    end

    local _, localInside =
        pointDanger(localTarget)

    -- Never continue a positional correction into known active danger.
    if localInside > 0 then
        return
    end

    Runtime.LastMove = -math.huge
    Runtime.LastMoveTarget = nil
    Runtime.LastMoveResolved = nil
    Runtime.LastMoveReason = nil

    moveTo(
        localTarget,
        "POST_SHIFT_CONTINUE"
    )

    local now = os.clock()

    if now - Runtime.LastPostShiftContinueLog
        >= CFG.POST_SHIFT_CONTINUE_LOG_COOLDOWN
    then
        Runtime.LastPostShiftContinueLog = now

        logKV("POST_SHIFT_CONTINUE", {
            source =
                tostring(
                    counterTag
                    or best.Source
                ),
            planner =
                tostring(
                    best.Label
                ),
            remaining =
                string.format(
                    "%.2f",
                    remaining
                ),
            local_step =
                string.format(
                    "%.2f",
                    step
                ),
            target =
                vec(localTarget),
        })
    end
end


function doFastShift(best, maxDistance, cooldown, counterTag, allowPartial)
    if not best or not Runtime.Root then
        return false
    end

    local now = os.clock()

    -- Reliability rule: no direct Root CFrame shift while Azrallik is active.
    -- Normal MoveTo/lane/pocket logic remains fully active. This is a stability
    -- fallback, not an attempt to suppress or bypass a kick.
    if Runtime.ActiveBossName == "Demon Lord Azrallik" then
        if now - Runtime.LastAzrallikShiftSuppressLog
            >= 0.85
        then
            Runtime.LastAzrallikShiftSuppressLog = now

            logKV("AZRALLIK_SHIFT_SUPPRESSED", {
                source =
                    tostring(
                        counterTag
                        or (
                            best
                            and best.Source
                        )
                        or "unknown"
                    ),
                planner =
                    tostring(
                        best.Label
                        or "unknown"
                    ),
            })
        end

        return false
    end

    if now - Runtime.LastFastShift < cooldown then
        return false
    end

    if not teleportBudgetAvailable(now) then
        return false
    end

    local delta = horizontal(best.Position - Runtime.Root.Position)

    if delta.Magnitude < 0.3 then
        return false
    end

    if not allowPartial
        and delta.Magnitude > maxDistance + 0.15
    then
        return false
    end

    local shift = math.min(delta.Magnitude, maxDistance)

    local candidate =
        Runtime.Root.Position
        + delta.Unit * shift

    local oldPenalty, oldInside = pointDanger(Runtime.Root.Position)
    local newPenalty, newInside = pointDanger(candidate)

    if newInside < oldInside
        or newPenalty < oldPenalty * 0.55
    then
        local rotation =
            Runtime.Root.CFrame
            - Runtime.Root.CFrame.Position

        local fromPosition =
            Runtime.Root.Position

        local sinceLast =
            now - Runtime.LastTeleportAt

        Runtime.Root.CFrame =
            CFrame.new(candidate) * rotation

        Runtime.LastFastShift = now

        recordTeleport(
            now,
            counterTag or "FAST_SHIFT",
            fromPosition,
            candidate,
            shift
        )

        logKV(counterTag or "FAST_SHIFT", {
            studs = string.format("%.2f", shift),
            requested = string.format("%.2f", delta.Magnitude),
            old_inside = oldInside,
            new_inside = newInside,
            planner = tostring(best.Label),
            source = tostring(best.Source),
            from = vec(fromPosition),
            to = vec(candidate),
            since_last =
                sinceLast == math.huge
                and "inf"
                or string.format("%.2f", sinceLast),
            total = Runtime.TeleportTotal,
        })

        rearmMovementAfterShift(
            best,
            candidate,
            counterTag
        )

        return true, newInside
    end

    return false, oldInside
end

function doMicroTeleport(best)
    if not CFG.MICRO_TELEPORT
        or not best
        or not Runtime.Root
    then
        return false
    end

    local now = os.clock()

    if now-Runtime.LastMicro
        < CFG.MICRO_TELEPORT_COOLDOWN
        or not teleportBudgetAvailable(now)
    then
        return false
    end

    local delta =
        horizontal(
            best.Position
            - Runtime.Root.Position
        )

    if delta.Magnitude < 0.3 then
        return false
    end

    local shift =
        math.min(
            delta.Magnitude,
            CFG.MICRO_TELEPORT_MAX
        )

    local candidate =
        Runtime.Root.Position
        + delta.Unit*shift

    local oldPenalty,oldInside =
        pointDanger(Runtime.Root.Position)

    local newPenalty,newInside =
        pointDanger(candidate)

    if newInside < oldInside
        or newPenalty < oldPenalty*0.45
    then
        local rotation =
            Runtime.Root.CFrame
            - Runtime.Root.CFrame.Position

        local fromPosition =
            Runtime.Root.Position

        local sinceLast =
            now - Runtime.LastTeleportAt

        Runtime.Root.CFrame =
            CFrame.new(candidate)
            * rotation

        Runtime.LastMicro = now

        recordTeleport(
            now,
            "MICRO_DODGE",
            fromPosition,
            candidate,
            shift
        )

        Runtime.MicroCount += 1

        logKV("MICRO_DODGE", {
            count = Runtime.MicroCount,
            studs = string.format("%.2f",shift),
            old_inside = oldInside,
            new_inside = newInside,
            from = vec(fromPosition),
            to = vec(candidate),
            since_last =
                string.format("%.2f", sinceLast),
            total = Runtime.TeleportTotal,
        })

        rearmMovementAfterShift(
            best,
            candidate,
            "MICRO_DODGE"
        )

        return true
    end

    return false
end


