-- DQR modular runtime: core/DodgeController.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Dodge controller
-- ============================================================

-- V7.1 HOTFIX: these helpers must be declared before dodgeThink.
function safeCombatDestination(desired)
    if not Runtime.Root or not desired then
        return desired
    end

    local origin = Runtime.Root.Position
    local dangerAtDestination, insideAtDestination =
        pointDanger(desired)

    local crossingDanger =
        routeDanger(origin, desired)

    if insideAtDestination == 0
        and dangerAtDestination < 1200
        and crossingDanger < 2500
    then
        return desired
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
        logKV("COMBAT_HAZARD_ROUTE", {
            requested = vec(desired),
            resolved = vec(open.Position),
            inside = insideAtDestination,
            route = string.format("%.0f", crossingDanger),
        })

        return open.Position
    end

    return desired
end


-- Samurai Palace: proactive normal-movement setup before the Golem's 9-line
-- rockshatter appears. This never teleports. It selects a short lateral/orbit
-- point that is ground/wall/route safe using the shared V10.x geometry engine.
Runtime.GolemShatterPremovementCandidate = function()
    if Runtime.ActiveBossName
            ~= "Ancient Golem Guardian"
        or not Runtime.ActiveBossRoot
        or not Runtime.Root
        or Runtime.GolemShatterTellAt
            == -math.huge
    then
        return nil
    end

    local now = os.clock()
    local elapsed =
        now - Runtime.GolemShatterTellAt

    if elapsed < 0
        or elapsed
            > CFG.GOLEM_SHATTER_PREMOVE_END
    then
        return nil
    end

    if Runtime.GolemShatterPlan then
        local _, inside =
            pointDanger(
                Runtime.GolemShatterPlan.Position
            )

        if inside == 0 then
            return Runtime.GolemShatterPlan
        end

        Runtime.GolemShatterPlan = nil
    end

    local origin =
        Runtime.Root.Position
    local bossPos =
        Runtime.ActiveBossRoot.Position

    local radial =
        unitHorizontal(
            origin - bossPos
        )

    if radial.Magnitude < 0.01 then
        radial =
            Vector3.new(
                1,
                0,
                0
            )
    end

    local tangent =
        Vector3.new(
            -radial.Z,
            0,
            radial.X
        ) * (
            Runtime.OrbitSign ~= 0
            and Runtime.OrbitSign
            or 1
        )

    local best
    local bestScore =
        math.huge

    for _, step in ipairs(
        CFG.GOLEM_SHATTER_PREMOVE_STEPS
    ) do
        for _, sign in ipairs({
            1,
            -1,
        }) do
            local candidate =
                origin
                + tangent
                    * step
                    * sign
                + radial * 1.5

            local grounded =
                hasGroundAt(
                    candidate
                )

            if grounded
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside, clearance =
                    pointDanger(
                        candidate
                    )

                local route =
                    routeDanger(
                        origin,
                        candidate
                    )

                if inside == 0
                    and route
                        < CFG.STRICT_RED_ROUTE_LIMIT
                then
                    local bossDistance =
                        horizontalDistance(
                            candidate,
                            bossPos
                        )

                    local score =
                        danger
                        + route * 0.70
                        + math.abs(
                            bossDistance
                            - (
                                CFG.BOSS_DESIRED_RANGE[
                                    "Ancient Golem Guardian"
                                ]
                                or 28
                            )
                        ) * 28
                        + step * 2

                    if score < bestScore then
                        bestScore = score
                        best = {
                            Position = candidate,
                            Radius = step,
                            Clearance =
                                clearance
                                or 0,
                            Inside = inside,
                            Label =
                                "golem_shatter_premove",
                        }
                    end
                end
            end
        end
    end

    Runtime.GolemShatterPlan =
        best

    return best
end


function physicalPressureSettings(enemy)
    if not enemy or not enemy.Model then
        return CFG.MELEE_SOFT_RADIUS, CFG.MELEE_RELEASE_RADIUS, CFG.MELEE_CRITICAL_RADIUS
    end

    if enemy.Model.Name == "Blood Minion" then
        return
            CFG.BLOOD_MINION_SOFT_RADIUS,
            CFG.BLOOD_MINION_RELEASE_RADIUS,
            CFG.BLOOD_MINION_CRITICAL_RADIUS
    end

    return
        CFG.MELEE_SOFT_RADIUS,
        CFG.MELEE_RELEASE_RADIUS,
        CFG.MELEE_CRITICAL_RADIUS
end

function physicalEmergencyState()
    if not Runtime.Root then
        return nil
    end

    local enemy, dist =
        nearestPhysicalEnemy(Runtime.Root.Position)

    if not enemy then
        return nil
    end

    local _, _, criticalRadius =
        physicalPressureSettings(enemy)

    local _, closing, timeToContact =
        physicalClosingInfo(enemy, Runtime.Root.Position)

    local imminent =
        dist <= criticalRadius
        or (
            closing >= CFG.PHYSICAL_FAST_EMERGENCY_CLOSING
            and (
                dist <= CFG.PHYSICAL_FAST_EMERGENCY_RADIUS
                or timeToContact <= CFG.PHYSICAL_FAST_EMERGENCY_TTC
            )
        )

    if not imminent then
        return nil
    end

    return {
        Enemy = enemy,
        Distance = dist,
        Closing = closing,
        TimeToContact = timeToContact,
        CriticalRadius = criticalRadius,
    }
end

function physicalEmergencyCandidate(state)
    if not state
        or not state.Enemy
        or not state.Enemy.Root
        or not Runtime.Root
    then
        return nil
    end

    local origin = Runtime.Root.Position
    local away =
        unitHorizontal(
            origin - state.Enemy.Root.Position
        )

    local tangent =
        Vector3.new(
            -away.Z,
            0,
            away.X
        ) * Runtime.OrbitSign

    local dir =
        unitHorizontal(
            away * 1.0
            + tangent * 0.35
        )

    local distance =
        math.min(
            CFG.MELEE_FAST_SHIFT_MAX,
            math.max(
                3.5,
                state.CriticalRadius - state.Distance + 4.0
            )
        )

    local destination =
        origin + dir * distance

    if wallBlocked(origin, destination) then
        destination =
            origin + away * distance
    end

    local _, inside, clearance = pointDanger(destination)

    return {
        Position = destination,
        Radius = distance,
        Label = "physical_emergency",
        Source = state.Enemy.Model.Name,
        Inside = inside,
        Clearance = clearance,
    }
end

function guardOvergrowthForwardPlan(plan, bossWave)
    if plan
        and plan.Label == "overgrowth_edge_follow"
    then
        return plan
    end

    if not plan
        or not bossWave
        or bossWave.Boss ~= "Demonic Overgrowth"
        or not bossWave.SequenceDir
        or not bossWave.SequenceOrigin
        or not Runtime.Root
    then
        return plan
    end

    local now =
        os.clock()

    local currentProjection =
        horizontal(
            Runtime.Root.Position
            - bossWave.SequenceOrigin
        ):Dot(bossWave.SequenceDir)

    bossWave.SequenceMaxProjection =
        math.max(
            bossWave.SequenceMaxProjection
                or -math.huge,
            currentProjection
        )

    local planProjection =
        horizontal(
            plan.Position
            - bossWave.SequenceOrigin
        ):Dot(bossWave.SequenceDir)

    local minimumProjection =
        (bossWave.SequenceMaxProjection
            or currentProjection)
        - CFG.OVERGROWTH_BACKTRACK_TOLERANCE

    if planProjection < minimumProjection then
        if now - Runtime.LastOvergrowthBacktrackLog
            >= CFG.OVERGROWTH_BACKTRACK_LOG_COOLDOWN
        then
            Runtime.LastOvergrowthBacktrackLog = now

            logKV("OVERGROWTH_BACKTRACK_BLOCK", {
                wave = bossWave.Id,
                current_projection =
                    string.format(
                        "%.2f",
                        currentProjection
                    ),
                max_projection =
                    string.format(
                        "%.2f",
                        bossWave.SequenceMaxProjection
                    ),
                requested_projection =
                    string.format(
                        "%.2f",
                        planProjection
                    ),
                planner = tostring(plan.Label),
            })
        end

        -- Hold the current forward-most position rather than walk back toward
        -- an earlier strip. Dodge geometry may still replace this on the next
        -- replan if a genuinely safer forward/lateral point exists.
        local _, inside, clearance =
            pointDanger(Runtime.Root.Position)

        return {
            Position = Runtime.Root.Position,
            Radius = 0,
            Score = plan.Score or 0,
            Inside = inside,
            Clearance = clearance,
            Label = "overgrowth_forward_hold",
            Source = "OvergrowthForwardGuard",
            TimeToContact = plan.TimeToContact,
        }
    end

    return plan
end


function kolvumarSpitThreats(
    bossThreats
)
    local out = {}
    local seen = {}

    for _, meta in ipairs(
        bossThreats or {}
    ) do
        if meta.RootName == "kolvumarSpit"
            and meta.Part
            and meta.Part.Parent
        then
            local key =
                string.format(
                    "%.1f:%.1f:%.1f",
                    meta.Part.Position.X,
                    meta.Part.Position.Y,
                    meta.Part.Position.Z
                )

            -- Active hitbox and precast often share the same center. One
            -- representative is enough for union tests.
            if not seen[key]
                or meta.Kind == "ActiveHitbox"
            then
                seen[key] = meta
            end
        end
    end

    for _, meta in pairs(seen) do
        out[#out + 1] = meta
    end

    return out
end

function kolvumarSpitInsideCount(
    point,
    spitThreats
)
    local count = 0

    for _, meta in ipairs(
        spitThreats or {}
    ) do
        if pointInsideThreat(meta, point) then
            count += 1
        end
    end

    return count
end

function kolvumarSpitRouteSafe(
    fromPosition,
    toPosition,
    spitThreats
)
    local delta =
        toPosition - fromPosition

    local distance =
        horizontal(delta).Magnitude

    if distance <= 0.1 then
        return
            kolvumarSpitInsideCount(
                toPosition,
                spitThreats
            ) == 0
    end

    local samples =
        math.max(
            1,
            math.ceil(
                distance
                / CFG.KOLVUMAR_SPIT_ROUTE_SAMPLE_STEP
            )
        )

    for i = 1, samples do
        local point =
            fromPosition
            + delta * (i / samples)

        if kolvumarSpitInsideCount(
            point,
            spitThreats
        ) > 0
        then
            return false
        end
    end

    return true
end

function kolvumarLocalEscapeCandidate(
    bossWave,
    spitThreats,
    currentInside
)
    if not Runtime.Root then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local bossRoot =
        Runtime.ActiveBossModel
        and modelRoot(
            Runtime.ActiveBossModel
        )

    local towardBoss =
        bossRoot
        and unitHorizontal(
            bossRoot.Position - origin
        )
        or unitHorizontal(
            Runtime.Root.CFrame.LookVector
        )

    local away =
        -towardBoss

    -- If the player is inside a particular puddle, bias the first search
    -- directly away from the newest containing center.
    local newestContaining

    for _, meta in ipairs(spitThreats) do
        if pointInsideThreat(
            meta,
            origin
        ) then
            if not newestContaining
                or meta.Created
                    > newestContaining.Created
            then
                newestContaining = meta
            end
        end
    end

    if newestContaining then
        local fromPuddle =
            unitHorizontal(
                origin
                - newestContaining.Part.Position
            )

        if fromPuddle.Magnitude > 0.1 then
            away = fromPuddle
        end
    end

    if away.Magnitude <= 0.1 then
        away = Vector3.new(1, 0, 0)
    end

    local baseAngle =
        math.atan2(
            away.Z,
            away.X
        )

    local best
    local bestScore = math.huge

    for _, radius in ipairs(
        CFG.KOLVUMAR_SPIT_SEARCH_RADII
    ) do
        for _, degrees in ipairs(
            CFG.KOLVUMAR_SPIT_SEARCH_ANGLES
        ) do
            local angle =
                baseAngle
                + math.rad(degrees)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate =
                origin + dir * radius

            if hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
                and kolvumarSpitInsideCount(
                    candidate,
                    spitThreats
                ) == 0
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                local bossDistance =
                    bossRoot
                    and horizontalDistance(
                        candidate,
                        bossRoot.Position
                    )
                    or CFG.KOLVUMAR_DESIRED_RANGE

                local rangeError =
                    math.abs(
                        bossDistance
                        - CFG.KOLVUMAR_DESIRED_RANGE
                    )

                local score =
                    radius * 115
                    + rangeError * 22
                    + wavePhysicalPenalty(candidate)
                    + danger * 0.05
                    + inside * 6000

                if clearance ~= math.huge then
                    score -=
                        math.min(
                            math.max(clearance, 0),
                            24
                        ) * 65
                end

                if score < bestScore then
                    bestScore = score

                    best = {
                        Position = candidate,
                        Radius = radius,
                        Score = score,
                        Inside = inside,
                        Clearance = clearance,
                        Label = "kolvumar_spit_emergency",
                        Source = "KolvumarSpitUnion",
                        InsideSpits = currentInside,
                    }
                end
            end
        end
    end

    return best
end

function kolvumarSafeSlideCandidate(
    bossWave,
    spitThreats
)
    if not Runtime.Root
        or not Runtime.ActiveBossModel
    then
        return nil
    end

    local bossRoot =
        modelRoot(
            Runtime.ActiveBossModel
        )

    if not bossRoot then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local toward =
        unitHorizontal(
            bossRoot.Position - origin
        )

    if toward.Magnitude <= 0.1 then
        return nil
    end

    local baseAngle =
        math.atan2(
            toward.Z,
            toward.X
        )

    local best
    local bestScore = math.huge

    for _, step in ipairs({
        12.0,
        CFG.KOLVUMAR_SPIT_SAFE_SLIDE_STEP,
        8.0,
        6.0,
        4.0,
        CFG.KOLVUMAR_SPIT_SAFE_SLIDE_MIN,
    }) do
        for _, degrees in ipairs({
            0, 25, -25, 50, -50, 75, -75,
            90, -90, 115, -115, 150, -150
        }) do
            local angle =
                baseAngle
                + math.rad(degrees)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate =
                origin + dir * step

            if hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
                and kolvumarSpitInsideCount(
                    candidate,
                    spitThreats
                ) == 0
                and kolvumarSpitRouteSafe(
                    origin,
                    candidate,
                    spitThreats
                )
            then
                local _, inside, clearance =
                    pointDanger(candidate)

                local bossDistance =
                    horizontalDistance(
                        candidate,
                        bossRoot.Position
                    )

                local score =
                    math.abs(
                        bossDistance
                        - CFG.KOLVUMAR_DESIRED_RANGE
                    ) * 35
                    + wavePhysicalPenalty(candidate)
                    + step * 12
                    + inside * 3500

                if score < bestScore then
                    bestScore = score

                    best = {
                        Position = candidate,
                        Radius = step,
                        Score = score,
                        Inside = inside,
                        Clearance = clearance,
                        Label = "kolvumar_spit_slide",
                        Source = "KolvumarSpitSafeSlide",
                    }
                end
            end
        end
    end

    return best
end

function kolvumarSpitEmergencyCandidate(
    bossWave,
    bossThreats
)
    if not Runtime.Root
        or not bossWave
    then
        return nil
    end

    local spitThreats =
        kolvumarSpitThreats(
            bossThreats
        )

    if #spitThreats == 0 then
        bossWave.KolvumarPocket = nil
        bossWave.KolvumarPocketUntil = -math.huge
        bossWave.KolvumarPocketReached = false
        Runtime.KolvumarRecoveryPosition = nil
        Runtime.KolvumarRecoveryUntil = -math.huge
        return nil
    end

    local now = os.clock()

    local currentInside =
        kolvumarSpitInsideCount(
            Runtime.Root.Position,
            spitThreats
        )

    -- Highest priority: get out of the union of active puddles.
    if CFG.KOLVUMAR_STALL_RECOVERY_COMMIT_ENABLED
        and currentInside > 0
        and Runtime.KolvumarRecoveryPosition
        and now < (
            Runtime.KolvumarRecoveryUntil
            or -math.huge
        )
    then
        local recoveryInside =
            kolvumarSpitInsideCount(
                Runtime.KolvumarRecoveryPosition,
                spitThreats
            )

        if recoveryInside == 0
            and hasGroundAt(
                Runtime.KolvumarRecoveryPosition
            )
        then
            local _, inside, clearance =
                pointDanger(
                    Runtime.KolvumarRecoveryPosition
                )

            return {
                Position =
                    Runtime.KolvumarRecoveryPosition,
                Radius =
                    horizontalDistance(
                        Runtime.Root.Position,
                        Runtime.KolvumarRecoveryPosition
                    ),
                Score = 0,
                Inside = inside,
                Clearance = clearance,
                Label =
                    "kolvumar_spit_recovery_commit",
                Source =
                    "KolvumarStallRecovery",
                InsideSpits = currentInside,
            }
        end

        Runtime.KolvumarRecoveryPosition = nil
        Runtime.KolvumarRecoveryUntil = -math.huge
    end

    if currentInside > 0 then
        local escape =
            kolvumarLocalEscapeCandidate(
                bossWave,
                spitThreats,
                currentInside
            )

        if escape then
            bossWave.KolvumarPocket =
                escape.Position
            bossWave.KolvumarPocketUntil =
                now
                + CFG.KOLVUMAR_SPIT_POST_ESCAPE_HOLD
            bossWave.KolvumarPocketReached =
                false

            if now - Runtime.LastKolvumarSpitRescueAt
                >= CFG.KOLVUMAR_SPIT_LOG_COOLDOWN
            then
                Runtime.LastKolvumarSpitRescueAt = now

                logKV("KOLVUMAR_SPIT_EMERGENCY", {
                    inside = currentInside,
                    distance =
                        string.format(
                            "%.2f",
                            escape.Radius
                        ),
                    clearance =
                        escape.Clearance == math.huge
                        and "inf"
                        or string.format(
                            "%.2f",
                            escape.Clearance or 0
                        ),
                    source =
                        tostring(
                            escape.Source
                        ),
                })
            end
        end

        return escape
    end

    -- After an escape, do not immediately walk back toward Kolvumar through
    -- the same puddle. Hold the saved pocket briefly unless a new spit covers it.
    if bossWave.KolvumarPocket
        and now < (
            bossWave.KolvumarPocketUntil
            or -math.huge
        )
    then
        local pocketInside =
            kolvumarSpitInsideCount(
                bossWave.KolvumarPocket,
                spitThreats
            )

        if pocketInside == 0 then
            local distance =
                horizontalDistance(
                    Runtime.Root.Position,
                    bossWave.KolvumarPocket
                )

            local _, inside, clearance =
                pointDanger(
                    bossWave.KolvumarPocket
                )

            return {
                Position =
                    bossWave.KolvumarPocket,
                Radius = distance,
                Score = 0,
                Inside = inside,
                Clearance = clearance,
                Label = "kolvumar_spit_hold",
                Source = "KolvumarSpitHold",
            }
        end

        bossWave.KolvumarPocket = nil
        bossWave.KolvumarPocketUntil = -math.huge
        bossWave.KolvumarPocketReached = false
    end

    -- After a direct rescue, keep MOVING through route-safe local points for
    -- the whole global teleport cooldown. V10.0 deaths repeatedly happened
    -- when another spit landed while the 3-second governor was still cooling.
    if now < (
        bossWave.KolvumarPostRescueUntil
        or -math.huge
    ) then
        local cooldownSlide =
            kolvumarSafeSlideCandidate(
                bossWave,
                spitThreats
            )

        if cooldownSlide then
            cooldownSlide.Label =
                "kolvumar_spit_cooldown_slide"
            cooldownSlide.Source =
                "KolvumarPostRescueMotion"

            return cooldownSlide
        end
    end

    -- Puddles still exist, but the character is safe. Move only through a
    -- puddle-safe local route toward boss range rather than using a distant
    -- generic 30-46 stud boss-wave destination.
    local slide =
        kolvumarSafeSlideCandidate(
            bossWave,
            spitThreats
        )

    if slide then
        bossWave.KolvumarPocket =
            slide.Position

        return slide
    end

    local _, inside, clearance =
        pointDanger(
            Runtime.Root.Position
        )

    return {
        Position = Runtime.Root.Position,
        Radius = 0,
        Score = 0,
        Inside = inside,
        Clearance = clearance,
        Label = "kolvumar_spit_hold",
        Source = "KolvumarSpitNoRouteHold",
    }
end

function holdKolvumarSpitPocket(
    bossWave,
    plan
)
    if not Runtime.Root
        or not Runtime.Humanoid
        or not bossWave
        or not plan
    then
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            plan.Position
        )

    if distance
        > CFG.KOLVUMAR_SPIT_HOLD_DISTANCE
    then
        moveTo(
            plan.Position,
            "KOLVUMAR_SPIT_HOLD"
        )

        return true
    end

    pcall(function()
        Runtime.Humanoid:MoveTo(
            Runtime.Root.Position
        )

        Runtime.Humanoid:Move(
            Vector3.zero,
            false
        )
    end)

    Runtime.MovementOwner =
        "KOLVUMAR_SPIT_HOLD"

    if not bossWave.KolvumarPocketReached then
        bossWave.KolvumarPocketReached = true

        logKV("KOLVUMAR_SPIT_HOLD", {
            wave = bossWave.Id,
            position =
                vec(Runtime.Root.Position),
        })
    end

    return true
end


function azrallikFingerBlastCandidate(
    bossWave,
    bossThreats
)
    if not Runtime.Root
        or not bossWave
    then
        return nil
    end

    local fingerPart

    for _, meta in ipairs(
        bossThreats or {}
    ) do
        if meta.RootName == "fingerBlastHit"
            and meta.Part
            and meta.Part.Parent
        then
            fingerPart = meta.Part
            break
        end
    end

    if not fingerPart then
        bossWave.FingerBlastStartedAt = nil
        bossWave.FingerBlastCenter = nil
        return nil
    end

    local now = os.clock()

    if not bossWave.FingerBlastStartedAt then
        bossWave.FingerBlastStartedAt = now
        bossWave.FingerBlastCenter =
            fingerPart.Position
    end

    local center =
        bossWave.FingerBlastCenter
        or fingerPart.Position

    local origin =
        Runtime.Root.Position

    local away =
        unitHorizontal(
            origin - center
        )

    if away.Magnitude <= 0.1 then
        local bossRoot =
            Runtime.ActiveBossModel
            and modelRoot(
                Runtime.ActiveBossModel
            )

        away =
            bossRoot
            and unitHorizontal(
                origin - bossRoot.Position
            )
            or unitHorizontal(
                Runtime.Root.CFrame.LookVector
            )
    end

    local elapsed =
        now
        - bossWave.FingerBlastStartedAt

    local distanceFromCenter =
        horizontalDistance(
            origin,
            center
        )

    local _, currentInside, currentClearance =
        pointDanger(origin)

    if elapsed <= CFG.AZRALLIK_FINGER_HOLD_TIME
        and distanceFromCenter
            >= CFG.AZRALLIK_FINGER_MIN_DISTANCE
        and currentInside == 0
    then
        return {
            Position = origin,
            Radius = 0,
            Score = 0,
            Inside = 0,
            Clearance = currentClearance,
            Label = "azrallik_finger_hold",
            Source = "AzrallikFingerHold",
        }
    end

    local baseAngle =
        math.atan2(
            away.Z,
            away.X
        )

    local best
    local bestScore = math.huge

    for _, radius in ipairs(
        CFG.AZRALLIK_FINGER_CANDIDATE_RADII
    ) do
        for _, degrees in ipairs(
            CFG.AZRALLIK_FINGER_ANGLES
        ) do
            local angle =
                baseAngle
                + math.rad(degrees)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate =
                Vector3.new(
                    center.X,
                    origin.Y,
                    center.Z
                )
                + dir * radius

            if hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                if inside == 0 then
                    local travel =
                        horizontalDistance(
                            origin,
                            candidate
                        )

                    local route =
                        routeDanger(
                            origin,
                            candidate
                        )

                    local score =
                        danger
                        + route * 0.20
                        + travel * 95
                        + wavePhysicalPenalty(candidate)

                    if clearance ~= math.huge then
                        score -=
                            math.min(
                                math.max(clearance, 0),
                                30
                            ) * 120
                    end

                    if score < bestScore then
                        bestScore = score
                        best = {
                            Position = candidate,
                            Radius = travel,
                            Score = score,
                            Inside = inside,
                            Clearance = clearance,
                            Label = "azrallik_finger_escape",
                            Source = "AzrallikFingerBlast",
                        }
                    end
                end
            end
        end
    end

    if best
        and now - Runtime.LastAzrallikFingerLog
            >= CFG.AZRALLIK_FINGER_LOG_COOLDOWN
    then
        Runtime.LastAzrallikFingerLog = now

        logKV("AZRALLIK_FINGER_ESCAPE", {
            wave = bossWave.Id,
            elapsed =
                string.format(
                    "%.2f",
                    elapsed
                ),
            travel =
                string.format(
                    "%.2f",
                    best.Radius
                ),
            from_center =
                string.format(
                    "%.2f",
                    distanceFromCenter
                ),
            clearance =
                best.Clearance == math.huge
                and "inf"
                or string.format(
                    "%.2f",
                    best.Clearance or 0
                ),
        })
    end

    return best
end


function azrallikSafePressureCandidate(
    bossWave,
    bossThreats
)
    if not CFG.AZRALLIK_SAFE_PRESSURE_ENABLED
        or not Runtime.Root
        or not bossWave
        or bossWave.Boss ~= "Demon Lord Azrallik"
        or bossThreatHas(
            "horizontalBeam",
            bossThreats
        )
    then
        return nil
    end

    local now = os.clock()

    if now - (bossWave.LastSafePressureAt or -math.huge)
        < CFG.AZRALLIK_SAFE_PRESSURE_INTERVAL
    then
        return nil
    end

    local targetRoot =
        azrallikPhaseTargetRoot()

    if not targetRoot then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local currentDistance =
        horizontalDistance(
            origin,
            targetRoot.Position
        )

    if currentDistance
        <= CFG.AZRALLIK_SAFE_PRESSURE_RANGE
    then
        return nil
    end

    local _, currentInside, currentClearance =
        pointDanger(origin)

    if currentInside > 0 then
        return nil
    end

    local requiredClearance =
        CFG.AZRALLIK_SAFE_PRESSURE_MIN_CLEARANCE

    if currentClearance ~= math.huge then
        requiredClearance =
            math.max(
                requiredClearance,
                math.min(
                    CFG.AZRALLIK_SAFE_PRESSURE_MAX_REQUIRED_CLEARANCE,
                    currentClearance
                    * CFG.AZRALLIK_SAFE_PRESSURE_CLEARANCE_KEEP
                )
            )
    end

    local toward =
        unitHorizontal(
            targetRoot.Position - origin
        )

    if toward.Magnitude <= 0.1 then
        return nil
    end

    bossWave.LastSafePressureAt = now

    for _, step in ipairs({
        CFG.AZRALLIK_SAFE_PRESSURE_STEP,
        8.0,
        6.0,
        4.0,
        3.0,
    }) do
        local candidate =
            origin + toward * step

        local safeDestination =
            safeMovementDestination(
                candidate,
                origin
            )

        if safeDestination
            and not movementWallHit(
                origin,
                candidate
            )
            and exactThreatRouteSafe(
                origin,
                candidate
            )
        then
            local _, inside, clearance =
                pointDanger(candidate)

            if inside == 0
                and (
                    clearance == math.huge
                    or clearance
                        >= requiredClearance
                )
            then
                if now - Runtime.LastAzrallikPressureLog
                    >= CFG.AZRALLIK_SAFE_PRESSURE_LOG_COOLDOWN
                then
                    Runtime.LastAzrallikPressureLog = now

                    logKV("AZRALLIK_SAFE_PRESSURE", {
                        wave = bossWave.Id,
                        step = string.format("%.1f", step),
                        target =
                            Runtime.Target
                            and Runtime.Target.Name
                            or "Demon Lord Azrallik",
                        distance =
                            string.format(
                                "%.1f",
                                currentDistance
                            ),
                        clearance =
                            clearance == math.huge
                            and "inf"
                            or string.format(
                                "%.2f",
                                clearance
                            ),
                    })
                end

                return {
                    Position = candidate,
                    Radius = step,
                    Score = 0,
                    Inside = 0,
                    Clearance = clearance,
                    Label = "azrallik_safe_pressure",
                    Source = "AzrallikSafePressure",
                }
            end
        end
    end

    return nil
end


function resetDodgeMoveWatch()
    Runtime.DodgeMoveWatch = nil
    Runtime.LastDodgeMoveLabel = nil
    Runtime.LastDodgeMoveTarget = nil
end

function dodgeMoveProgressWatch(
    plan,
    reason,
    waveId,
    currentInside
)
    if not Runtime.Root
        or not plan
        or not plan.Position
    then
        return false
    end

    -- Intentional hold positions must never be interpreted as a movement stall.
    if reason == "AZRALLIK_BEAM_POCKET"
        or Runtime.MovementOwner == "AZRALLIK_POCKET_HOLD"
        or Runtime.MovementOwner == "AZRALLIK_FINGER_HOLD"
        or Runtime.MovementOwner == "AZRALLIK_FINGER_PREHOLD"
        or Runtime.MovementOwner == "AZRALLIK_SPREAD_HOLD"
        or Runtime.MovementOwner == "KOLVUMAR_SPIT_HOLD"
        or Runtime.MovementOwner == "KOLVUMAR_SPIT_COOLDOWN_SLIDE"
        or Runtime.MovementOwner == "KOLVUMAR_SPIT_RECOVERY"
    then
        resetDodgeMoveWatch()
        return false
    end

    local now = os.clock()
    local target = plan.Position
    local label =
        tostring(reason or "DODGE")
        .. ":"
        .. tostring(waveId or 0)

    local watch =
        Runtime.DodgeMoveWatch

    if not watch
        or watch.Label ~= label
        or horizontalDistance(
            watch.Target,
            target
        ) > CFG.DODGE_MOVE_WATCH_TARGET_EPS
    then
        Runtime.DodgeMoveWatch = {
            Label = label,
            StartedAt = now,
            Origin = Runtime.Root.Position,
            Target = target,
            StartDistance =
                horizontalDistance(
                    Runtime.Root.Position,
                    target
                ),
        }

        Runtime.LastDodgeMoveLabel = label
        Runtime.LastDodgeMoveTarget = target
        return false
    end

    local moved =
        horizontalDistance(
            Runtime.Root.Position,
            watch.Origin
        )

    local remaining =
        horizontalDistance(
            Runtime.Root.Position,
            target
        )

    if remaining <= 1.25
        or moved >= CFG.DODGE_MOVE_WATCH_MIN_PROGRESS
    then
        -- Movement is real. Re-arm from the new position so a later physical
        -- stall in the same wave can still be detected.
        watch.StartedAt = now
        watch.Origin = Runtime.Root.Position
        watch.Target = target
        watch.StartDistance = remaining
        return false
    end

    if now - watch.StartedAt
        < CFG.DODGE_MOVE_WATCH_TIMEOUT
    then
        return false
    end

    if currentInside <= 0 then
        -- Safe and stationary is allowed; only escalate a stalled dodge while
        -- the player is still in actual dangerous geometry.
        watch.StartedAt = now
        watch.Origin = Runtime.Root.Position
        return false
    end

    if now - Runtime.LastDodgeMoveWatchLog
        >= CFG.DODGE_MOVE_WATCH_LOG_COOLDOWN
    then
        Runtime.LastDodgeMoveWatchLog = now

        logKV("DODGE_MOVE_STALL", {
            label = label,
            owner = tostring(Runtime.MovementOwner),
            moved = string.format("%.2f", moved),
            remaining = string.format("%.2f", remaining),
            inside = currentInside,
            velocity = string.format(
                "%.2f",
                horizontal(
                    Runtime.Root.AssemblyLinearVelocity
                ).Magnitude
            ),
        })
    end

    local preferred =
        unitHorizontal(
            target - Runtime.Root.Position
        )

    local fallback =
        chooseOpenSpacePoint(
            Runtime.Root.Position,
            preferred,
            6
        )

    if fallback then
        local _, oldInside =
            pointDanger(
                Runtime.Root.Position
            )

        local _, newInside =
            pointDanger(
                fallback.Position
            )

        if newInside < oldInside
            or newInside == 0
        then
            moveTo(
                fallback.Position,
                "DODGE_STALL_RECOVERY"
            )

            if CFG.KOLVUMAR_STALL_RECOVERY_COMMIT_ENABLED
                and Runtime.ActiveBossName == "Kolvumar"
                and (
                    reason == "KOLVUMAR_SPIT_ESCAPE"
                    or reason == "KOLVUMAR_SPIT_COOLDOWN_SLIDE"
                )
            then
                Runtime.KolvumarRecoveryPosition =
                    fallback.Position
                Runtime.KolvumarRecoveryUntil =
                    now
                    + CFG.KOLVUMAR_STALL_RECOVERY_COMMIT

                if now - Runtime.LastKolvumarRecoveryLog
                    >= CFG.KOLVUMAR_STALL_RECOVERY_LOG_COOLDOWN
                then
                    Runtime.LastKolvumarRecoveryLog = now

                    logKV("KOLVUMAR_RECOVERY_COMMIT", {
                        reason = tostring(reason),
                        position = vec(fallback.Position),
                        hold =
                            string.format(
                                "%.2f",
                                CFG.KOLVUMAR_STALL_RECOVERY_COMMIT
                            ),
                    })
                end
            end

            logKV("DODGE_STALL_RECOVERY", {
                label = label,
                radius = string.format(
                    "%.1f",
                    fallback.Radius
                ),
                old_inside = oldInside,
                new_inside = newInside,
                position = vec(fallback.Position),
            })
        end
    end

    watch.StartedAt = now
    watch.Origin = Runtime.Root.Position
    watch.Target = target

    return true
end

function commitOvergrowthFirstEdge(
    bossWave,
    plan,
    currentInside
)
    if not Runtime.Root
        or not Runtime.Humanoid
        or not bossWave
        or not plan
    then
        return false
    end

    local now = os.clock()

    local firstEdgeDirection =
        unitHorizontal(
            plan.Position
            - Runtime.Root.Position
        )

    if firstEdgeDirection.Magnitude > 0.1 then
        bossWave.EdgeFollowDir =
            firstEdgeDirection
        bossWave.EdgeFollowUntil =
            now
            + CFG.OVERGROWTH_EDGE_FOLLOW_TIME
    end

    -- Always issue a real wall-aware MoveTo.
    moveTo(
        plan.Position,
        "OVERGROWTH_EDGE"
    )

    -- V8.7 still ate the first narrow strip in most runs because walking
    -- ~9-10 studs is too close to the ~0.7 sec activation window. If we are
    -- ACTUALLY inside that first strip and the global 3-sec governor permits,
    -- commit one short shift immediately. This consumes the wave teleport so
    -- the later sequence cannot chain another CFrame move.
    if CFG.OVERGROWTH_EDGE_PROACTIVE_SHIFT
        and currentInside > 0
        and not bossWave.Teleported
        and teleportBudgetAvailable(now)
    then
        local shifted, afterInside =
            doFastShift(
                plan,
                CFG.OVERGROWTH_EDGE_PROACTIVE_MAX,
                0,
                "OVERGROWTH_EDGE_PROACTIVE",
                false
            )

        if shifted then
            bossWave.EdgeRescueUsed = true
            bossWave.Teleported = true
            bossWave.TeleportCount =
                (bossWave.TeleportCount or 0) + 1
            bossWave.LastWaveTeleportAt = now
            bossWave.AfterTeleportInside = afterInside

            logKV("OVERGROWTH_EDGE_PROACTIVE_COMMIT", {
                wave = bossWave.Id,
                after_inside = afterInside,
                distance =
                    string.format(
                        "%.2f",
                        horizontalDistance(
                            Runtime.Root.Position,
                            plan.Position
                        )
                    ),
            })

            bossWave.EdgeCommitStartedAt = now
            bossWave.EdgeCommitOrigin = Runtime.Root.Position
            bossWave.EdgeCommitTarget = plan.Position

            return true
        end
    end

    if not bossWave.EdgeCommitStartedAt
        or not bossWave.EdgeCommitOrigin
        or not bossWave.EdgeCommitTarget
        or horizontalDistance(
            bossWave.EdgeCommitTarget,
            plan.Position
        ) > 2.0
    then
        bossWave.EdgeCommitStartedAt = now
        bossWave.EdgeCommitOrigin = Runtime.Root.Position
        bossWave.EdgeCommitTarget = plan.Position

        logKV("OVERGROWTH_EDGE_COMMIT", {
            wave = bossWave.Id,
            distance = string.format(
                "%.2f",
                horizontalDistance(
                    Runtime.Root.Position,
                    plan.Position
                )
            ),
            inside = currentInside,
        })

        return true
    end

    local moved =
        horizontalDistance(
            Runtime.Root.Position,
            bossWave.EdgeCommitOrigin
        )

    local remaining =
        horizontalDistance(
            Runtime.Root.Position,
            plan.Position
        )

    if remaining <= 1.25
        or currentInside <= 0
    then
        bossWave.EdgeCommitStartedAt = now
        bossWave.EdgeCommitOrigin = Runtime.Root.Position
        bossWave.EdgeCommitTarget = plan.Position
        return true
    end

    if moved >= CFG.OVERGROWTH_EDGE_PROGRESS_MIN then
        bossWave.EdgeCommitStartedAt = now
        bossWave.EdgeCommitOrigin = Runtime.Root.Position
        bossWave.EdgeCommitTarget = plan.Position
        return true
    end

    if now - bossWave.EdgeCommitStartedAt
        < CFG.OVERGROWTH_EDGE_PROGRESS_TIMEOUT
    then
        return true
    end

    -- The requested escape exists but the character physically did not move.
    -- One short globally-governed shift is allowed as a rescue. Marking the
    -- wave Teleported also prevents a second sequence teleport in this attack.
    if CFG.OVERGROWTH_EDGE_RESCUE_ONCE
        and not bossWave.EdgeRescueUsed
        and not bossWave.Teleported
        and teleportBudgetAvailable(now)
    then
        local shifted, afterInside =
            doFastShift(
                plan,
                CFG.OVERGROWTH_EDGE_RESCUE_MAX,
                0,
                "OVERGROWTH_EDGE_RESCUE",
                false
            )

        if shifted then
            bossWave.EdgeRescueUsed = true
            bossWave.Teleported = true
            bossWave.TeleportCount =
                (bossWave.TeleportCount or 0) + 1
            bossWave.LastWaveTeleportAt = now
            bossWave.AfterTeleportInside = afterInside

            logKV("OVERGROWTH_EDGE_RESCUE_COMMIT", {
                wave = bossWave.Id,
                moved_before =
                    string.format("%.2f", moved),
                remaining_before =
                    string.format("%.2f", remaining),
                after_inside = afterInside,
            })

            bossWave.EdgeCommitStartedAt = now
            bossWave.EdgeCommitOrigin = Runtime.Root.Position
            bossWave.EdgeCommitTarget = plan.Position
            return true
        end
    end

    -- No shift available: immediately ask the general watchdog for a local
    -- open-space recovery instead of standing in the strip.
    dodgeMoveProgressWatch(
        plan,
        "OVERGROWTH_EDGE",
        bossWave.Id,
        currentInside
    )

    bossWave.EdgeCommitStartedAt = now
    bossWave.EdgeCommitOrigin = Runtime.Root.Position
    bossWave.EdgeCommitTarget = plan.Position

    return true
end

function rescueOvergrowthLongLineIfInside(
    bossWave,
    plan,
    currentInside
)
    if not Runtime.Root
        or not bossWave
        or not plan
        or bossWave.Teleported
        or not teleportBudgetAvailable(os.clock())
    then
        return false
    end

    local _, actualInside, actualClearance =
        pointDanger(
            Runtime.Root.Position
        )

    local urgent =
        actualInside > 0
        or (
            actualClearance ~= math.huge
            and actualClearance
                < CFG.OVERGROWTH_LONGLINE_HOLD_CLEARANCE
        )

    if not urgent then
        return false
    end

    local shifted, afterInside =
        doFastShift(
            plan,
            CFG.OVERGROWTH_LONGLINE_RESCUE_MAX,
            0,
            "OVERGROWTH_LONGLINE_RESCUE",
            true
        )

    if shifted then
        local now = os.clock()

        bossWave.Teleported = true
        bossWave.TeleportCount =
            (bossWave.TeleportCount or 0) + 1
        bossWave.LastWaveTeleportAt = now
        bossWave.AfterTeleportInside = afterInside

        logKV("OVERGROWTH_LONGLINE_RESCUE_COMMIT", {
            wave = bossWave.Id,
            after_inside = afterInside,
            target_distance =
                string.format(
                    "%.2f",
                    horizontalDistance(
                        Runtime.Root.Position,
                        plan.Position
                    )
                ),
        })

        return true
    end

    return false
end


function currentPositionThreatened()
    if not Runtime.Root then
        return false,0
    end

    local _,inside =
        pointDanger(Runtime.Root.Position)

    return inside > 0,inside
end

function clearDodge(reason)
    if Runtime.DodgeActive then
        Runtime.DodgeActive = false
        Runtime.DodgePlan = nil
        Runtime.DodgeMoveWatch = nil
        Runtime.LastDodgeMoveLabel = nil
        Runtime.LastDodgeMoveTarget = nil

        logKV("DODGE_CLEAR", {
            elapsed = string.format(
                "%.3f",
                os.clock() - Runtime.DodgeStarted
            ),
            reason = reason or "safe",
        })
    end
end

function dodgeThink()
    if not CFG.AUTO_DODGE
        or not Runtime.Root
        or Runtime.CompletionConfirmed
    then
        return false
    end

    local threats = activeThreats()
    local bossWave, bossThreats = updateBossWave(threats)
    local mageWave, mageThreats = updateMageWave(threats)

    local virtualCount = 0
    for _ in pairs(Runtime.VirtualThreats) do
        virtualCount += 1
    end

    local nearestPhysical, nearestPhysicalDist =
        nearestPhysicalEnemy(Runtime.Root.Position)

    local dynamicMeleeRadius = CFG.MELEE_SOFT_RADIUS
    local physicalClosing = 0
    local meleeTimeToContact = math.huge

    if nearestPhysical then
        dynamicMeleeRadius, physicalClosing, meleeTimeToContact =
            physicalClosingInfo(nearestPhysical, Runtime.Root.Position)
    end

    local physicalEmergency =
        physicalEmergencyState()

    local predicted =
        Runtime.Root.Position
        + horizontal(Runtime.Root.AssemblyLinearVelocity)
            * CFG.ABILITY_SAFE_PREDICT_TIME

    local currentPenalty, currentInside =
        pointDanger(Runtime.Root.Position)

    local predictedPenalty, predictedInside =
        pointDanger(predicted)

    -- Ancient Golem Guardian predictive premove.
    -- The measured tell gives ~1.25-1.61 sec before the 9 rockshatter lines.
    -- Only use ordinary movement here; once real geometry appears the normal
    -- boss-wave solver takes ownership.
    if Runtime.ActiveBossName
            == "Ancient Golem Guardian"
        and Runtime.GolemShatterTellAt
            > -math.huge
        and os.clock()
            - Runtime.GolemShatterTellAt
            <= CFG.GOLEM_SHATTER_PREMOVE_END
        and currentInside == 0
        and predictedInside == 0
    then
        local golemPlan =
            Runtime.GolemShatterPremovementCandidate
            and Runtime.GolemShatterPremovementCandidate()

        if golemPlan then
            moveTo(
                golemPlan.Position,
                "GOLEM_SHATTER_PREMOVE"
            )

            local now =
                os.clock()

            if now - Runtime.LastGolemShatterLog
                >= CFG.GOLEM_SHATTER_LOG_COOLDOWN
            then
                Runtime.LastGolemShatterLog =
                    now

                logKV(
                    "GOLEM_SHATTER_PREMOVE",
                    {
                        elapsed =
                            string.format(
                                "%.2f",
                                now
                                - Runtime.GolemShatterTellAt
                            ),
                        step =
                            string.format(
                                "%.1f",
                                golemPlan.Radius
                                or 0
                            ),
                        clearance =
                            string.format(
                                "%.1f",
                                golemPlan.Clearance
                                or 0
                            ),
                    }
                )
            end

            return true
        end
    end

    -- ========================================================
    -- BOSS WAVE MODE
    -- ========================================================
    if bossWave then
        local now = os.clock()

        local shouldPlan = bossWave.Plan == nil
        local finalizePlan = false

        if bossWave.Plan then
            local _, planInside = pointDanger(bossWave.Plan.Position)

            if now < bossWave.CollectUntil then
                if now - bossWave.LastPlanAt >= CFG.BOSS_WAVE_REPLAN_INTERVAL then
                    shouldPlan = true
                end
            elseif not bossWave.Finalized then
                shouldPlan = true
                finalizePlan = true
            elseif planInside > 0
                and now - bossWave.LastPlanAt >= CFG.BOSS_WAVE_REPLAN_INTERVAL
            then
                shouldPlan = true
            end
        end

        if shouldPlan then
            bossWave.Plan = chooseBossWavePoint()
            bossWave.LastPlanAt = now

            if finalizePlan or now >= bossWave.CollectUntil then
                bossWave.Finalized = true
            end

            if bossWave.Plan then
                logKV("BOSS_WAVE_PLAN", {
                    id = bossWave.Id,
                    boss = bossWave.Boss,
                    radius = string.format("%.1f", bossWave.Plan.Radius),
                    clearance = string.format("%.1f", bossWave.Plan.Clearance),
                    inside = bossWave.Plan.Inside,
                    threats = #bossThreats,
                    finalized = tostring(bossWave.Finalized == true),
                })
            end
        end

        local plan = bossWave.Plan

        if bossWave.Boss == "Demonic Overgrowth" then
            if bossThreatHas(
                "overgrowthLongLineSpikes",
                bossThreats
            ) then
                local longLinePlan =
                    overgrowthLongLinePocketCandidate(
                        bossWave,
                        bossThreats
                    )

                if longLinePlan then
                    plan = longLinePlan
                    bossWave.Plan = longLinePlan
                    bossWave.Finalized = true
                end
            else
                local edgeFollowPlan =
                    Runtime.OvergrowthEdgeFollowCandidate
                    and Runtime.OvergrowthEdgeFollowCandidate(
                        bossWave
                    )

                local sequencePlan

                if not edgeFollowPlan then
                    sequencePlan =
                        overgrowthSequenceEscapeCandidate(
                            bossWave
                        )
                end

                if edgeFollowPlan then
                    plan = edgeFollowPlan
                    bossWave.Plan = edgeFollowPlan

                    if now - Runtime.LastOvergrowthEdgeFollowLog
                        >= CFG.OVERGROWTH_EDGE_FOLLOW_LOG_COOLDOWN
                    then
                        Runtime.LastOvergrowthEdgeFollowLog = now

                        logKV("OVERGROWTH_EDGE_FOLLOW", {
                            wave = bossWave.Id,
                            step =
                                string.format(
                                    "%.1f",
                                    edgeFollowPlan.Radius
                                ),
                            remaining =
                                string.format(
                                    "%.2f",
                                    math.max(
                                        0,
                                        (
                                            bossWave.EdgeFollowUntil
                                            or now
                                        ) - now
                                    )
                                ),
                        })
                    end

                elseif sequencePlan then
                    plan = sequencePlan
                    bossWave.Plan = sequencePlan
                    bossWave.Finalized = true
                elseif bossThreatHas(
                    "spikePrecast",
                    bossThreats
                ) then
                    local edgePlan =
                        overgrowthFirstEdgeCandidate(
                            bossWave,
                            bossThreats
                        )

                    if edgePlan then
                        plan = edgePlan
                        bossWave.Plan = edgePlan

                        if now - Runtime.LastOvergrowthEdgeLog
                            >= CFG.OVERGROWTH_EDGE_LOG_COOLDOWN
                        then
                            Runtime.LastOvergrowthEdgeLog = now

                            logKV("OVERGROWTH_EDGE_PLAN", {
                                wave = bossWave.Id,
                                distance =
                                    string.format(
                                        "%.2f",
                                        edgePlan.Radius
                                    ),
                                clearance =
                                    edgePlan.Clearance == math.huge
                                    and "inf"
                                    or string.format(
                                        "%.2f",
                                        edgePlan.Clearance or 0
                                    ),
                            })
                        end
                    end
                end
            end
        end

        if bossWave.Boss == "Kolvumar" then
            local spitPlan =
                kolvumarSpitEmergencyCandidate(
                    bossWave,
                    bossThreats
                )

            if spitPlan then
                plan = spitPlan
                bossWave.Plan = spitPlan
                bossWave.Finalized = true
            end
        end

        -- Samurai Palace exact local-gap handling for the long-line batches.
        -- If already safe, HOLD. If inside, move only to a nearby route-safe gap.
        -- This avoids the old failure mode where a generic 30-46 stud plan
        -- crosses several radial/parallel lines.
        local samuraiGapAttack
        local samuraiGapLabel

        if bossWave.Boss == "Sanada Yukimura"
            and bossThreatHas(
                "crossShuriken",
                bossThreats
            )
        then
            samuraiGapAttack =
                "crossShuriken"
            samuraiGapLabel =
                "sanada_cross"

        elseif bossWave.Boss
                == "Ancient Golem Guardian"
            and bossThreatHas(
                "rockshatter",
                bossThreats
            )
        then
            samuraiGapAttack =
                "rockshatter"
            samuraiGapLabel =
                "golem_shatter"

        elseif bossWave.Boss
                == "Miyamoto Musashi"
            and bossThreatHas(
                "doubleFlameBeam",
                bossThreats
            )
        then
            samuraiGapAttack =
                "doubleFlameBeam"
            samuraiGapLabel =
                "miyamoto_doublebeam"
        end

        if samuraiGapAttack
            and Runtime.SamuraiLocalGapCandidate
        then
            local localGapPlan =
                Runtime.SamuraiLocalGapCandidate(
                    bossThreats,
                    samuraiGapAttack,
                    samuraiGapLabel
                )

            if localGapPlan then
                plan = localGapPlan
                bossWave.Plan =
                    localGapPlan
                bossWave.Finalized =
                    true
            end
        end

        local azrallikHorizontalBeamActive =
            bossWave.Boss == "Demon Lord Azrallik"
            and bossThreatHas(
                "horizontalBeam",
                bossThreats
            )

        local azrallikFingerActive =
            bossWave.Boss == "Demon Lord Azrallik"
            and bossThreatHas(
                "fingerBlastHit",
                bossThreats
            )

        local azrallikFingerTellActive =
            bossWave.Boss == "Demon Lord Azrallik"
            and Runtime.AzrallikFingerTellOrigin ~= nil
            and os.clock() - Runtime.AzrallikFingerTellAt
                <= CFG.AZRALLIK_FINGER_TELL_WINDOW

        local azrallikSpreadActive =
            bossWave.Boss == "Demon Lord Azrallik"
            and bossThreatHas(
                "azrallikPunchSpread",
                bossThreats
            )

        local azrallikSpreadTellActive =
            bossWave.Boss == "Demon Lord Azrallik"
            and Runtime.AzrallikSpreadTellOrigin ~= nil
            and os.clock() - Runtime.AzrallikSpreadTellAt
                <= CFG.AZRALLIK_SPREAD_TELL_WINDOW
            and os.clock() - Runtime.AzrallikSpreadTellAt
                >= CFG.AZRALLIK_SPREAD_PREMOVE_START

        if azrallikFingerActive
            and azrallikSpreadActive
            and CFG.AZRALLIK_COMBINED_FINGER_SPREAD_ENABLED
        then
            -- Finger can spawn while the 8-way PunchSpread is still live.
            -- The old finger escape was endpoint-safe but could WALK THROUGH a
            -- spread lane. Reuse the local spread solver first because its
            -- point/route checks include the finger geometry too.
            local combinedPlan =
                Runtime.AzrallikSpreadActiveCandidate
                and Runtime.AzrallikSpreadActiveCandidate(
                    bossWave,
                    bossThreats
                )

            if combinedPlan then
                plan = combinedPlan
                bossWave.Plan = combinedPlan
                bossWave.Finalized = true

                local combinedNow = os.clock()

                if combinedNow - Runtime.LastAzrallikCombinedLog
                    >= CFG.AZRALLIK_COMBINED_LOG_COOLDOWN
                then
                    Runtime.LastAzrallikCombinedLog =
                        combinedNow

                    logKV("AZRALLIK_COMBINED_ESCAPE", {
                        planner =
                            tostring(
                                combinedPlan.Label
                            ),
                        radius =
                            string.format(
                                "%.1f",
                                combinedPlan.Radius or 0
                            ),
                        clearance =
                            combinedPlan.Clearance == math.huge
                            and "inf"
                            or string.format(
                                "%.1f",
                                combinedPlan.Clearance or 0
                            ),
                    })
                end
            end

        elseif azrallikFingerActive then
            local fingerPlan =
                azrallikFingerBlastCandidate(
                    bossWave,
                    bossThreats
                )

            if fingerPlan then
                plan = fingerPlan
                bossWave.Plan = fingerPlan
                bossWave.Finalized = true
            end

        elseif azrallikHorizontalBeamActive then
            local sweepPlan =
                horizontalSweepEscapeCandidate(
                    bossWave,
                    bossThreats
                )

            if not sweepPlan then
                sweepPlan =
                    azrallikEarlyBeamCandidate(
                        bossWave,
                        bossThreats
                    )
            end

            if sweepPlan then
                plan = sweepPlan
                bossWave.Plan = sweepPlan
                bossWave.Finalized = true
            end

        elseif azrallikSpreadActive then
            local spreadPlan =
                Runtime.AzrallikSpreadActiveCandidate
                and Runtime.AzrallikSpreadActiveCandidate(
                    bossWave,
                    bossThreats
                )

            if spreadPlan then
                plan = spreadPlan
                bossWave.Plan = spreadPlan
                bossWave.Finalized = true
            end

        elseif azrallikFingerTellActive then
            local prePlan =
                Runtime.AzrallikFingerTellCandidate
                and Runtime.AzrallikFingerTellCandidate()

            if prePlan then
                plan = prePlan
                bossWave.Plan = prePlan
                bossWave.Finalized = true
            end

        elseif azrallikSpreadTellActive then
            local spreadPrePlan =
                Runtime.AzrallikSpreadTellCandidate
                and Runtime.AzrallikSpreadTellCandidate(
                    bossWave,
                    bossThreats
                )

            if spreadPrePlan then
                plan = spreadPrePlan
                bossWave.Plan = spreadPrePlan

                local now = os.clock()

                if now - Runtime.LastAzrallikSpreadMoveLog
                    >= CFG.AZRALLIK_SPREAD_LOG_COOLDOWN
                then
                    Runtime.LastAzrallikSpreadMoveLog = now

                    logKV("AZRALLIK_SPREAD_PREMOVE", {
                        elapsed =
                            string.format(
                                "%.2f",
                                now - Runtime.AzrallikSpreadTellAt
                            ),
                        distance =
                            string.format(
                                "%.1f",
                                horizontalDistance(
                                    Runtime.Root.Position,
                                    Runtime.ActiveBossRoot.Position
                                )
                            ),
                        step =
                            string.format(
                                "%.1f",
                                spreadPrePlan.Radius or 0
                            ),
                    })
                end
            end

        elseif bossWave.Boss == "Demon Lord Azrallik" then
            local pressurePlan =
                azrallikSafePressureCandidate(
                    bossWave,
                    bossThreats
                )

            if pressurePlan then
                plan = pressurePlan
                bossWave.Plan = pressurePlan
            end
        end

        if bossWave.Boss == "Demonic Overgrowth" then
            plan =
                guardOvergrowthForwardPlan(
                    plan,
                    bossWave
                )

            bossWave.Plan = plan
        end

        if plan then
            Runtime.WallEscapePosition = nil

            if not Runtime.DodgeActive then
                Runtime.DodgeActive = true
                Runtime.DodgeStarted = now
                Runtime.DodgeCount += 1

                logKV("DODGE_START", {
                    count = Runtime.DodgeCount,
                    current_inside = currentInside,
                    predicted_inside = predictedInside,
                    target_radius = string.format("%.1f", plan.Radius),
                    clearance = string.format("%.1f", plan.Clearance or 0),
                    planner = "boss_wave_gap",
                    wave = bossWave.Id,
                    boss = bossWave.Boss,
                })
            end

            local bossMoveReason = "BOSS_WAVE"

            if plan.Label == "kolvumar_spit_emergency" then
                bossMoveReason = "KOLVUMAR_SPIT_ESCAPE"

            elseif plan.Label == "kolvumar_spit_hold" then
                bossMoveReason = "KOLVUMAR_SPIT_HOLD"

            elseif plan.Label == "kolvumar_spit_slide" then
                bossMoveReason = "KOLVUMAR_SPIT_SLIDE"

            elseif plan.Label == "kolvumar_spit_cooldown_slide" then
                bossMoveReason = "KOLVUMAR_SPIT_COOLDOWN_SLIDE"

            elseif plan.Label == "kolvumar_spit_recovery_commit" then
                bossMoveReason = "KOLVUMAR_SPIT_RECOVERY"

            elseif plan.Label == "sanada_cross_hold"
                or plan.Label == "sanada_cross_local_gap"
            then
                bossMoveReason =
                    "SANADA_CROSS_LOCAL_GAP"

            elseif plan.Label == "golem_shatter_hold"
                or plan.Label == "golem_shatter_local_gap"
            then
                bossMoveReason =
                    "GOLEM_SHATTER_LOCAL_GAP"

            elseif plan.Label == "miyamoto_doublebeam_hold"
                or plan.Label == "miyamoto_doublebeam_local_gap"
            then
                bossMoveReason =
                    "MIYAMOTO_DOUBLEBEAM_LOCAL_GAP"

            elseif plan.Label == "azrallik_finger_escape"
                or plan.Label == "azrallik_finger_hold"
            then
                bossMoveReason = "AZRALLIK_FINGER"

            elseif plan.Label == "azrallik_finger_premove"
                or plan.Label == "azrallik_finger_premove_hold"
            then
                bossMoveReason = "AZRALLIK_FINGER_PREMOVE"

            elseif plan.Label == "azrallik_beam_pocket" then
                bossMoveReason = "AZRALLIK_BEAM_POCKET"
            elseif plan.Label == "azrallik_beam_early_edge"
                or plan.Label == "azrallik_beam_early_hold"
            then
                bossMoveReason = "AZRALLIK_BEAM_EARLY"
            elseif plan.Label == "azrallik_safe_pressure" then
                bossMoveReason = "AZRALLIK_SAFE_PRESSURE"

            elseif plan.Label == "azrallik_spread_premove" then
                bossMoveReason = "AZRALLIK_SPREAD_PREMOVE"

            elseif plan.Label == "azrallik_spread_hold" then
                bossMoveReason = "AZRALLIK_SPREAD_HOLD"

            elseif plan.Label == "azrallik_spread_local_gap" then
                bossMoveReason = "AZRALLIK_SPREAD_LOCAL_GAP"
            elseif plan.Label == "azrallik_sweep_gap" then
                bossMoveReason = "AZRALLIK_SWEEP_GAP"
            elseif plan.Label == "overgrowth_sequence_forward" then
                bossMoveReason = "OVERGROWTH_FORWARD"
            elseif plan.Label == "overgrowth_edge_follow" then
                bossMoveReason = "OVERGROWTH_EDGE_FOLLOW"
            elseif plan.Label == "overgrowth_first_edge" then
                bossMoveReason = "OVERGROWTH_EDGE"
            elseif plan.Label == "overgrowth_longline_pocket" then
                bossMoveReason = "OVERGROWTH_LONGLINE_POCKET"
            end

            if plan.Label == "kolvumar_spit_hold" then
                holdKolvumarSpitPocket(
                    bossWave,
                    plan
                )

            elseif plan.Label == "azrallik_finger_premove_hold" then
                pcall(function()
                    Runtime.Humanoid:MoveTo(
                        Runtime.Root.Position
                    )
                end)

                Runtime.MovementOwner =
                    "AZRALLIK_FINGER_PREHOLD"

            elseif plan.Label == "azrallik_finger_hold" then
                pcall(function()
                    Runtime.Humanoid:MoveTo(
                        Runtime.Root.Position
                    )
                    Runtime.Humanoid:Move(
                        Vector3.zero,
                        false
                    )
                end)

                Runtime.MovementOwner =
                    "AZRALLIK_FINGER_HOLD"

            elseif plan.Label == "azrallik_beam_pocket" then
                holdAzrallikBeamPocket(
                    bossWave,
                    plan
                )

            elseif plan.Label == "overgrowth_first_edge" then
                commitOvergrowthFirstEdge(
                    bossWave,
                    plan,
                    currentInside
                )

            else
                moveTo(
                    plan.Position,
                    bossMoveReason
                )

                if plan.Label == "overgrowth_longline_pocket" then
                    rescueOvergrowthLongLineIfInside(
                        bossWave,
                        plan,
                        currentInside
                    )
                end

                dodgeMoveProgressWatch(
                    plan,
                    bossMoveReason,
                    bossWave.Id,
                    currentInside
                )
            end

            local eta =
                CFG.BOSS_ATTACK_ETA[bossWave.Boss]
                or 0.80

            local impactAt = bossWave.Started + eta
            local walkEnough = walkingLikelyEnough(plan, impactAt)

            local teleportMax = CFG.TELEPORT_BOSS_WAVE_MAX

            if bossWave.Boss == "Demonic Overgrowth" then
                teleportMax = CFG.OVERGROWTH_WAVE_TELEPORT_MAX
            elseif bossWave.Boss == "Demon Lord Azrallik" then
                teleportMax = CFG.AZRALLIK_WAVE_TELEPORT_MAX
            end

            local sweepEmergency =
                plan.Label == "azrallik_sweep_gap"
                and plan.TimeToContact <= CFG.AZRALLIK_SWEEP_IMPACT_WINDOW

            local overgrowthSequenceEmergency =
                plan.Label == "overgrowth_sequence_forward"
                and plan.TimeToContact <= CFG.OVERGROWTH_SEQUENCE_IMPACT_WINDOW

            local kolvumarSpitEmergency =
                plan.Label == "kolvumar_spit_emergency"

            local kolvumarHpRatio =
                Runtime.Humanoid
                and Runtime.Humanoid.MaxHealth > 0
                and (
                    Runtime.Humanoid.Health
                    / Runtime.Humanoid.MaxHealth
                )
                or 1

            -- Recount spit overlap RIGHT NOW. The escape plan can be a few
            -- frames old; V10.1 proved a second puddle may appear after the
            -- plan was created, producing current_inside=2 but stacked=1.
            local kolvumarLiveInside =
                plan.InsideSpits
                or 0

            if kolvumarSpitEmergency
                and Runtime.Root
            then
                local liveSpitThreats =
                    kolvumarSpitThreats(
                        bossThreats
                    )

                kolvumarLiveInside =
                    kolvumarSpitInsideCount(
                        Runtime.Root.Position,
                        liveSpitThreats
                    )

                plan.InsideSpits =
                    kolvumarLiveInside
            end

            local kolvumarSpitShiftEmergency =
                kolvumarSpitEmergency
                and (
                    Runtime.FragileMode
                    or kolvumarHpRatio
                        <= CFG.KOLVUMAR_SPIT_SHIFT_HP_RATIO
                    or kolvumarLiveInside
                        >= CFG.KOLVUMAR_SPIT_SHIFT_MIN_STACK
                )

            local overgrowthNarrowSpikeActive =
                bossWave.Boss == "Demonic Overgrowth"
                and bossThreatHas(
                    "spikePrecast",
                    bossThreats
                )
                and not bossThreatHas(
                    "overgrowthLongLineSpikes",
                    bossThreats
                )

            -- Moving-front teleports are proactive. Generic boss teleports
            -- remain reactive.
            local shouldTeleport =
                (
                    currentInside > 0
                    and predictedInside > 0
                    and now >= bossWave.Started + CFG.BOSS_WAVE_WALK_GRACE
                    and not walkEnough
                )
                or sweepEmergency
                or overgrowthSequenceEmergency
                or kolvumarSpitShiftEmergency

            if bossWave.Boss == "Demonic Overgrowth"
                and plan.Label
                    ~= "overgrowth_sequence_forward"
                and now - bossWave.Started
                    < CFG.OVERGROWTH_FIRST_COMMIT_DELAY
            then
                shouldTeleport = false
            end

            -- Stronger V7.9 rule:
            -- During the narrow moving spike sequence, NEVER use the generic
            -- boss-wave teleport. Wait for direction lock, then allow at most
            -- one forward-sequence shift for the whole wave.
            if overgrowthNarrowSpikeActive
                and plan.Label
                    ~= "overgrowth_sequence_forward"
            then
                shouldTeleport = false
            end

            if CFG.AZRALLIK_BEAM_NO_TELEPORT
                and azrallikHorizontalBeamActive
            then
                shouldTeleport = false
            end

            if bossWave.Boss == "Kolvumar" then
                if plan.Label ~= "kolvumar_spit_emergency" then
                    shouldTeleport = CFG.KOLVUMAR_GENERIC_WAVE_SHIFT
                elseif not kolvumarSpitShiftEmergency then
                    shouldTeleport = false

                    if now - Runtime.LastKolvumarWalkOnlyLog
                        >= CFG.KOLVUMAR_SPIT_LOG_COOLDOWN
                    then
                        Runtime.LastKolvumarWalkOnlyLog = now

                        logKV("KOLVUMAR_SPIT_WALK_ESCAPE", {
                            hp_ratio =
                                string.format("%.2f", kolvumarHpRatio),
                            stacked =
                                tostring(kolvumarLiveInside),
                            distance =
                                string.format("%.1f", plan.Radius or 0),
                        })
                    end
                end
            end

            if plan.Label == "sanada_cross_hold"
                or plan.Label == "sanada_cross_local_gap"
                or plan.Label == "golem_shatter_hold"
                or plan.Label == "golem_shatter_local_gap"
                or plan.Label == "miyamoto_doublebeam_hold"
                or plan.Label == "miyamoto_doublebeam_local_gap"
                or plan.Label == "azrallik_safe_pressure"
                or plan.Label == "azrallik_spread_premove"
                or plan.Label == "azrallik_spread_hold"
                or plan.Label == "azrallik_spread_local_gap"
                or plan.Label == "azrallik_finger_hold"
                or plan.Label == "azrallik_finger_premove"
                or plan.Label == "azrallik_finger_premove_hold"
                or plan.Label == "kolvumar_spit_hold"
                or plan.Label == "kolvumar_spit_slide"
                or plan.Label == "kolvumar_spit_cooldown_slide"
                or plan.Label == "kolvumar_spit_recovery_commit"
                or plan.Label == "overgrowth_edge_follow"
            then
                shouldTeleport = false
            end

            if plan.Label == "overgrowth_longline_pocket"
                and plan.Radius
                    <= CFG.OVERGROWTH_LONGLINE_WALK_ONLY_DISTANCE
            then
                shouldTeleport = false
            end

            local teleportAllowed =
                (not CFG.TELEPORT_BOSS_WAVE_ONCE or not bossWave.Teleported)

            if plan.Label == "kolvumar_spit_emergency" then
                -- Per-spit exception to boss-wave-once. The GLOBAL 3-second
                -- governor still applies and prevents chaining.
                teleportAllowed = true

            elseif plan.Label == "overgrowth_sequence_forward" then
                teleportAllowed =
                    not bossWave.Teleported
                    and not bossWave.SequenceCommitted
                    and (bossWave.TeleportCount or 0)
                        < CFG.OVERGROWTH_SEQUENCE_MAX_TELEPORTS
                    and now - (bossWave.LastWaveTeleportAt or -math.huge)
                        >= CFG.OVERGROWTH_SEQUENCE_TELEPORT_GAP
            end

            local teleportBudgetOkay =
                teleportBudgetAvailable(now)

            if shouldTeleport
                and teleportAllowed
                and not teleportBudgetOkay
            then
                logTeleportBlocked(
                    plan.Label
                        or bossWave.Boss,
                    now
                )
            end

            if shouldTeleport
                and teleportAllowed
                and teleportBudgetOkay
            then
                local tag = "BOSS_WAVE_TELEPORT"
                local maxShift = teleportMax

                if plan.Label == "kolvumar_spit_emergency" then
                    tag = "KOLVUMAR_SPIT_RESCUE"
                    maxShift = CFG.KOLVUMAR_SPIT_RESCUE_MAX

                elseif plan.Label == "azrallik_sweep_gap" then
                    tag = "AZRALLIK_SWEEP_TELEPORT"
                    maxShift = CFG.AZRALLIK_SWEEP_TELEPORT_MAX
                elseif plan.Label == "overgrowth_sequence_forward" then
                    tag = "OVERGROWTH_SEQUENCE_TELEPORT"
                    maxShift = CFG.OVERGROWTH_WAVE_TELEPORT_MAX
                end

                local didShift, afterInside =
                    doFastShift(
                        plan,
                        maxShift,
                        CFG.TELEPORT_GLOBAL_COOLDOWN,
                        tag,
                        true
                    )

                if didShift then
                    if plan.Label == "kolvumar_spit_emergency" then
                        bossWave.KolvumarPocket =
                            Runtime.Root.Position
                        bossWave.KolvumarPocketUntil =
                            now
                            + CFG.KOLVUMAR_SPIT_POST_ESCAPE_HOLD
                        bossWave.KolvumarPostRescueUntil =
                            now
                            + CFG.KOLVUMAR_POST_RESCUE_MOTION_TIME
                        bossWave.KolvumarPocketReached =
                            false
                    end

                    bossWave.Teleported = true
                    bossWave.TeleportCount =
                        (bossWave.TeleportCount or 0) + 1
                    bossWave.LastWaveTeleportAt = now
                    bossWave.AfterTeleportInside = afterInside

                    if plan.Label
                        == "overgrowth_sequence_forward"
                    then
                        bossWave.SequenceCommitted = true
                        bossWave.SequenceCommitPosition =
                            Runtime.Root.Position
                        bossWave.SequenceCommitUntil =
                            now
                            + CFG.OVERGROWTH_POST_SHIFT_HOLD

                        local projection =
                            horizontal(
                                Runtime.Root.Position
                                - bossWave.SequenceOrigin
                            ):Dot(
                                bossWave.SequenceDir
                            )

                        bossWave.SequenceMaxProjection =
                            math.max(
                                bossWave.SequenceMaxProjection
                                    or -math.huge,
                                projection
                            )

                        logKV("OVERGROWTH_COMMIT", {
                            wave = bossWave.Id,
                            position =
                                vec(Runtime.Root.Position),
                            projection =
                                string.format(
                                    "%.2f",
                                    projection
                                ),
                            hold =
                                string.format(
                                    "%.2f",
                                    CFG.OVERGROWTH_POST_SHIFT_HOLD
                                ),
                        })
                    end
                end
            end

            return true
        end
    end

    -- ========================================================
    -- NORMAL MAGE MINI-WAVE MODE
    -- ========================================================
    if mageWave then
        local now = os.clock()

        local magePressureActive =
            Runtime.MageFreePressureActive
            and Runtime.MageFreePressureActive()

        -- V9.9:
        -- mage-wave objects can exist while we are already perfectly safe.
        -- Do NOT enter dodge mode in that case. Release movement back to
        -- ordinary combat so the mage keeps getting attacked.
        if CFG.MAGE_SAFE_WINDOW_ATTACK
            and magePressureActive
            and currentInside == 0
            and predictedInside
                <= CFG.MAGE_SAFE_WINDOW_MAX_PREDICTED_INSIDE
        then
            if Runtime.DodgeActive then
                clearDodge(
                    "mage_safe_attack_window"
                )
            end

            if now - Runtime.LastMageSafeWindowLog
                >= CFG.MAGE_SAFE_WINDOW_LOG_COOLDOWN
            then
                Runtime.LastMageSafeWindowLog =
                    now

                logKV("MAGE_ATTACK_WINDOW", {
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
                    threats = #mageThreats,
                })
            end

            return false
        end

        local shouldPlan = mageWave.Plan == nil
        local finalizePlan = false

        if mageWave.Plan then
            local _, planInside = pointDanger(mageWave.Plan.Position)

            if now < mageWave.CollectUntil then
                if now - mageWave.LastPlanAt >= CFG.MAGE_WAVE_REPLAN_INTERVAL then
                    shouldPlan = true
                end
            elseif not mageWave.Finalized then
                shouldPlan = true
                finalizePlan = true
            elseif planInside > 0
                and now - mageWave.LastPlanAt >= CFG.MAGE_WAVE_REPLAN_INTERVAL
            then
                shouldPlan = true
            end
        end

        if shouldPlan then
            mageWave.Plan = chooseMageWavePoint()
            mageWave.LastPlanAt = now

            if finalizePlan or now >= mageWave.CollectUntil then
                mageWave.Finalized = true
            end

            if mageWave.Plan then
                logKV("MAGE_WAVE_PLAN", {
                    id = mageWave.Id,
                    radius = string.format("%.1f", mageWave.Plan.Radius),
                    clearance = string.format("%.1f", mageWave.Plan.Clearance),
                    inside = mageWave.Plan.Inside,
                    threats = #mageThreats,
                    finalized = tostring(mageWave.Finalized == true),
                })
            end
        end

        local plan = mageWave.Plan

        local closePhysical, closePhysicalDist =
            nearestPhysicalEnemy(Runtime.Root.Position)

        if closePhysical
            and closePhysicalDist <= CFG.WAVE_PHYSICAL_HARD_RADIUS
            and now - mageWave.LastPlanAt >= 0.10
        then
            local merged = chooseMageWavePoint()

            if merged then
                plan = merged
                mageWave.Plan = merged
                mageWave.LastPlanAt = now
            end
        end

        if plan then
            Runtime.WallEscapePosition = nil

            if not Runtime.DodgeActive then
                Runtime.DodgeActive = true
                Runtime.DodgeStarted = now
                Runtime.DodgeCount += 1

                logKV("DODGE_START", {
                    count = Runtime.DodgeCount,
                    current_inside = currentInside,
                    predicted_inside = predictedInside,
                    target_radius = string.format("%.1f", plan.Radius),
                    clearance = string.format("%.1f", plan.Clearance or 0),
                    planner = "mage_wave_gap",
                    wave = mageWave.Id,
                })
            end

            moveTo(plan.Position, "MAGE_WAVE")

            dodgeMoveProgressWatch(
                plan,
                "MAGE_WAVE",
                mageWave.Id,
                currentInside
            )

            local impactAt =
                mageWave.Started + CFG.MAGE_ATTACK_ETA

            local walkEnough =
                walkingLikelyEnough(plan, impactAt)

            if currentInside > 0
                and predictedInside > 0
                and now >= mageWave.Started + CFG.MAGE_WAVE_WALK_GRACE
                and not mageWave.Teleported
                and not walkEnough
                and teleportBudgetAvailable(now)
            then
                local shifted =
                    doFastShift(
                        plan,
                        CFG.MAGE_WAVE_TELEPORT_MAX,
                        CFG.TELEPORT_GLOBAL_COOLDOWN,
                        "MAGE_WAVE_TELEPORT",
                        true
                    )

                if shifted then
                    mageWave.Teleported = true
                end
            end

            return true
        end
    end

    -- ========================================================
    -- ORDINARY COMBAT MODE
    -- ========================================================

    -- Ordinary fast physical pressure does not need to seize the full dodge
    -- state. Hand it back to PhysicalPressureMove unless contact is truly
    -- imminent; this keeps attack/combat movement running continuously.
    if CFG.PHYSICAL_DODGE_HANDOFF_ENABLED
        and physicalEmergency
        and #threats == 0
        and virtualCount == 0
    then
        local truePanic =
            physicalEmergency.Distance
                <= CFG.PHYSICAL_DODGE_PANIC_RADIUS
            or (
                physicalEmergency.Distance
                    <= CFG.PHYSICAL_DODGE_PANIC_NEAR_RADIUS
                and physicalEmergency.Closing
                    >= CFG.PHYSICAL_DODGE_PANIC_MIN_CLOSING
            )
            or (
                physicalEmergency.Closing > 0
                and physicalEmergency.TimeToContact
                    <= CFG.PHYSICAL_DODGE_PANIC_TTC
            )

        if not truePanic then
            clearDodge(
                "physical_pressure_handoff"
            )

            local now = os.clock()

            if now - Runtime.LastPhysicalHandoffLog
                >= CFG.PHYSICAL_DODGE_HANDOFF_LOG_COOLDOWN
            then
                Runtime.LastPhysicalHandoffLog =
                    now

                logKV("PHYSICAL_HANDOFF", {
                    enemy =
                        physicalEmergency.Enemy.Model.Name,
                    distance =
                        string.format(
                            "%.1f",
                            physicalEmergency.Distance
                        ),
                    closing =
                        string.format(
                            "%.1f",
                            physicalEmergency.Closing
                        ),
                    ttc =
                        physicalEmergency.TimeToContact
                            < math.huge
                        and string.format(
                            "%.2f",
                            physicalEmergency.TimeToContact
                        )
                        or "inf",
                })
            end

            return false
        end
    end

    if #threats == 0
        and virtualCount == 0
        and not physicalEmergency
    then
        clearDodge("no_threat")
        return false
    end

    local needsDodge =
        currentInside > 0
        or predictedInside > 0
        or predictedPenalty > 1500
        or physicalEmergency ~= nil

    if not needsDodge then
        clearDodge("outside_geometry")
        return false
    end

    -- Single thin line: start walking immediately. Teleport only if we are
    -- STILL inside after a brief walk grace and the global budget allows it.
    if CFG.LARGE_LINE_FAST_SHIFT
        and currentInside > 0
        and teleportBudgetAvailable(os.clock())
    then
        local linePlan =
            lineEmergencyCandidate(
                Runtime.Root.Position,
                threats
            )

        if linePlan then
            local age =
                linePlan.ThreatCreated
                and (os.clock() - linePlan.ThreatCreated)
                or math.huge

            if age >= CFG.LINE_WALK_GRACE then
                local impactAt =
                    (linePlan.ThreatCreated or os.clock())
                    + CFG.MAGE_ATTACK_ETA

                if not walkingLikelyEnough(linePlan, impactAt) then
                    if doFastShift(
                        linePlan,
                        CFG.LARGE_LINE_FAST_SHIFT_MAX,
                        CFG.LARGE_LINE_FAST_SHIFT_COOLDOWN,
                        "LINE_FAST_SHIFT",
                        false
                    ) then
                        Runtime.DodgePlan = nil
                        Runtime.LastDodgePlanAt = -math.huge
                    end
                end
            end
        end
    end

    local now = os.clock()
    local plan = Runtime.DodgePlan

    if physicalEmergency
        and #threats == 0
        and virtualCount == 0
    then
        plan = physicalEmergencyCandidate(physicalEmergency)
        Runtime.DodgePlan = plan
        Runtime.LastDodgePlanAt = now
    end

    local planUnsafe = false

    if plan then
        local _, insideAtPlan = pointDanger(plan.Position)
        planUnsafe = insideAtPlan > 0
    end

    if (not plan
        or planUnsafe
        or now - Runtime.LastDodgePlanAt >= CFG.DODGE_REPLAN_INTERVAL)
        and not (
            physicalEmergency
            and #threats == 0
            and virtualCount == 0
        )
    then
        plan = chooseDodgePoint()
        Runtime.DodgePlan = plan
        Runtime.LastDodgePlanAt = now
    end

    if not plan then
        return false
    end

    if not Runtime.DodgeActive then
        Runtime.DodgeActive = true
        Runtime.DodgeStarted = now
        Runtime.DodgeCount += 1

        logKV("DODGE_START", {
            count = Runtime.DodgeCount,
            current_inside = currentInside,
            predicted_inside = predictedInside,
            target_radius = string.format("%.1f", plan.Radius),
            clearance = string.format("%.1f", plan.Clearance or 0),
            planner = tostring(plan.Label),
            melee_dist = nearestPhysical
                and string.format("%.1f", nearestPhysicalDist)
                or "none",
            melee_closing = nearestPhysical
                and string.format("%.1f", physicalClosing)
                or "0",
        })
    end

    moveTo(plan.Position, "DODGE")

    -- V7: emergency translation is ONLY for true critical contact.
    -- Normal physical proximity is handled by PHYSICAL_PRESSURE movement.
    if physicalEmergency
        and teleportBudgetAvailable(now)
    then
        local emergencyPlan =
            physicalEmergencyCandidate(physicalEmergency)

        if emergencyPlan then
            local didShift =
                doFastShift(
                    emergencyPlan,
                    CFG.MELEE_FAST_SHIFT_MAX,
                    CFG.MELEE_FAST_SHIFT_COOLDOWN,
                    "MELEE_FAST_SHIFT",
                    false
                )

            if didShift then
                Runtime.LastMeleeFastShift = now

                logKV("MELEE_EMERGENCY", {
                    enemy = physicalEmergency.Enemy.Model.Name,
                    distance = string.format("%.2f", physicalEmergency.Distance),
                    closing = string.format("%.2f", physicalEmergency.Closing),
                    time_to_contact = physicalEmergency.TimeToContact < math.huge
                        and string.format("%.3f", physicalEmergency.TimeToContact)
                        or "inf",
                    planner = "physical_emergency",
                })
            end
        end
    end

    -- General micro teleport remains the last fallback.
    if currentInside > 0
        and teleportBudgetAvailable(now)
    then
        local oldestAge = 0

        for _, meta in ipairs(threats) do
            if pointInsideThreat(meta, Runtime.Root.Position) then
                oldestAge =
                    math.max(
                        oldestAge,
                        os.clock() - meta.Created
                    )
            end
        end

        if oldestAge >= CFG.MICRO_TELEPORT_MIN_THREAT_AGE
            and plan.Radius <= CFG.MICRO_TELEPORT_MAX + 1.0
        then
            doMicroTeleport(plan)
        end
    end

    return true
end



Runtime.PhysicalLeashDestination = function(
    enemy,
    startRadius,
    needed
)
    if not CFG.PHYSICAL_TARGET_LEASH_ENABLED
        or not Runtime.Root
        or not Runtime.Target
        or not Runtime.TargetRoot
        or Runtime.Target == enemy.Model
        or isPhysicalEnemyModel(
            Runtime.Target
        )
    then
        return nil
    end

    local targetName =
        Runtime.Target.Name or ""

    local isHeart =
        targetName == "Azrallik's Heart"

    local isBoss =
        Runtime.ActiveBossModel
        and Runtime.Target
            == Runtime.ActiveBossModel

    local isMage =
        Runtime.IsRangedPressureName(
            targetName
        )
        or string.find(
            string.lower(targetName),
            "mage",
            1,
            true
        ) ~= nil

    if not isHeart
        and not isBoss
        and not isMage
    then
        return nil
    end

    local maxLeash =
        isHeart
        and CFG.PHYSICAL_TARGET_LEASH_HEART_MAX
        or (
            isBoss
            and CFG.PHYSICAL_TARGET_LEASH_BOSS_MAX
            or CFG.PHYSICAL_TARGET_LEASH_MAGE_MAX
        )

    local origin =
        Runtime.Root.Position

    local targetPos =
        Runtime.TargetRoot.Position

    local currentTargetDistance =
        horizontalDistance(
            origin,
            targetPos
        )

    local desiredRange =
        desiredRangeForTarget()

    local away =
        unitHorizontal(
            origin - enemy.Root.Position
        )

    local toward =
        unitHorizontal(
            targetPos - origin
        )

    local baseAngle =
        math.atan2(
            away.Z,
            away.X
        )

    local best
    local bestScore =
        math.huge

    for _, radius in ipairs({
        needed,
        needed
            + CFG.PHYSICAL_TARGET_LEASH_EXTRA_STEP,
    }) do
        for i = 0,
            CFG.PHYSICAL_TARGET_LEASH_SAMPLES - 1
        do
            local angle =
                baseAngle
                + math.pi * 2
                    * (
                        i
                        / CFG.PHYSICAL_TARGET_LEASH_SAMPLES
                    )

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate =
                origin + dir * radius

            if hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside =
                    pointDanger(candidate)

                if inside == 0 then
                    local physicalDistance =
                        horizontalDistance(
                            candidate,
                            enemy.Root.Position
                        )

                    local targetDistance =
                        horizontalDistance(
                            candidate,
                            targetPos
                        )

                    local separationPenalty =
                        math.max(
                            startRadius + 2
                                - physicalDistance,
                            0
                        ) * 1800

                    local targetPenalty =
                        math.abs(
                            targetDistance
                            - desiredRange
                        ) * (
                            isHeart
                            and 260
                            or (
                                isBoss
                                and 190
                                or 120
                            )
                        )

                    local progressPenalty = 0

                    -- If pressure has already pushed us beyond the offensive
                    -- leash, reject any local dodge that keeps running farther
                    -- away from the objective.
                    if currentTargetDistance
                        > maxLeash
                        and targetDistance
                            >= currentTargetDistance - 0.5
                    then
                        progressPenalty += 24000
                    end

                    if targetDistance > maxLeash then
                        progressPenalty +=
                            (
                                targetDistance
                                - maxLeash
                            ) * 350
                    end

                    local progress =
                        toward:Dot(
                            unitHorizontal(
                                candidate - origin
                            )
                        )

                    local score =
                        danger
                        + separationPenalty
                        + targetPenalty
                        + progressPenalty
                        - progress * (
                            currentTargetDistance
                                > maxLeash
                                and 1800
                                or 250
                        )

                    if score < bestScore then
                        bestScore = score
                        best = candidate
                    end
                end
            end
        end
    end

    return best
end


function physicalPressureMove()
    if not CFG.PROACTIVE_MELEE_AVOIDANCE
        or not Runtime.Root
        or not Runtime.Humanoid
    then
        Runtime.PhysicalKiting = false
        Runtime.PhysicalKiteEnemy = nil
        return false
    end

    local enemy, dist =
        nearestPhysicalEnemy(Runtime.Root.Position)

    if not enemy or not enemy.Root or not enemy.Root.Parent then
        Runtime.PhysicalKiting = false
        Runtime.PhysicalKiteEnemy = nil
        return false
    end

    local softRadius, releaseRadius =
        physicalPressureSettings(enemy)

    local _, closing, timeToContact =
        physicalClosingInfo(enemy, Runtime.Root.Position)

    -- A fast chaser gets a SMALL early-start bonus, but unlike V6 this never
    -- turns into a 30-36 stud "danger bubble".
    local earlyBonus =
        math.clamp(
            math.max(closing - CFG.PHYSICAL_KITE_START_CLOSING, 0) * 0.12,
            0,
            4.0
        )

    local startRadius = softRadius + earlyBonus

    local shouldKite =
        dist <= CFG.PHYSICAL_HARD_KITE_RADIUS
        or (
            dist <= startRadius
            and closing >= CFG.PHYSICAL_KITE_MIN_CLOSING
        )
        or (
            Runtime.PhysicalKiting
            and Runtime.PhysicalKiteEnemy == enemy.Model
            and dist < releaseRadius
            and closing > 0.8
        )

    if not shouldKite then
        if Runtime.PhysicalKiting
            and Runtime.PhysicalKiteEnemy == enemy.Model
            and os.clock() - Runtime.LastPhysicalKiteLog >= CFG.PHYSICAL_KITE_LOG_COOLDOWN
        then
            Runtime.LastPhysicalKiteLog = os.clock()
            logKV("PHYSICAL_PRESSURE_CLEAR", {
                enemy = enemy.Model.Name,
                distance = string.format("%.1f", dist),
            })
        end

        Runtime.PhysicalKiting = false
        Runtime.PhysicalKiteEnemy = nil
        return false
    end

    Runtime.PhysicalKiting = true
    Runtime.PhysicalKiteEnemy = enemy.Model

    local origin = Runtime.Root.Position
    local away = unitHorizontal(origin - enemy.Root.Position)

    local tangent =
        Vector3.new(
            -away.Z,
            0,
            away.X
        ) * Runtime.OrbitSign

    -- Diagonal retreat: creates space without endlessly running straight away.
    local dir =
        unitHorizontal(
            away * 1.0
            + tangent * 0.52
        )

    local needed =
        math.max(
            CFG.PHYSICAL_KITE_STEP,
            startRadius - dist + 4.0
        )

    local destination =
        origin + dir * needed

    local leashedDestination =
        Runtime.PhysicalLeashDestination(
            enemy,
            startRadius,
            needed
        )

    if leashedDestination then
        destination =
            leashedDestination

        if os.clock()
            - Runtime.LastPhysicalLeashLog
            >= CFG.PHYSICAL_TARGET_LEASH_LOG_COOLDOWN
        then
            Runtime.LastPhysicalLeashLog =
                os.clock()

            logKV("PHYSICAL_PRESSURE_LEASH", {
                enemy =
                    enemy.Model.Name,
                target =
                    Runtime.Target
                    and Runtime.Target.Name
                    or "none",
                target_distance =
                    Runtime.TargetRoot
                    and string.format(
                        "%.1f",
                        horizontalDistance(
                            destination,
                            Runtime.TargetRoot.Position
                        )
                    )
                    or "none",
            })
        end
    end

    -- If the first pressure lane faces a wall, select an actually open lane.
    if movementWallHit(origin, destination) then
        local open =
            chooseOpenSpacePoint(
                origin,
                away
            )

        if open then
            destination = open.Position
        else
            dir =
                unitHorizontal(
                    away * 1.0
                    - tangent * 0.52
                )

            destination =
                origin + dir * needed
        end
    end

    moveTo(destination, "PHYSICAL_PRESSURE")

    if os.clock() - Runtime.LastPhysicalKiteLog >= CFG.PHYSICAL_KITE_LOG_COOLDOWN then
        Runtime.LastPhysicalKiteLog = os.clock()

        logKV("PHYSICAL_PRESSURE", {
            enemy = enemy.Model.Name,
            distance = string.format("%.1f", dist),
            closing = string.format("%.1f", closing),
            ttc = timeToContact < math.huge
                and string.format("%.2f", timeToContact)
                or "inf",
            start = string.format("%.1f", startRadius),
        })
    end

    return true
end




