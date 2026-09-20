-- DQR modular runtime: core/CombatMovement.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Combat movement
-- ============================================================

function desiredCombatPoint()
    if not Runtime.Root
        or not Runtime.TargetRoot
    then
        return nil
    end

    local player = Runtime.Root.Position
    local target = Runtime.TargetRoot.Position

    -- Never orbit underneath/above a target on another map level.
    if not sameCombatLevel(player, target) then
        return nil
    end

    local radial =
        unitHorizontal(player-target)

    local desiredRange = desiredRangeForTarget()

    local desired =
        target
        + radial*desiredRange

    -- Tangential offset creates a moving flank/orbit rather than standing
    -- directly on the enemy's frontal attack line.
    local tangent =
        Vector3.new(
            -radial.Z,
            0,
            radial.X
        )

    if os.clock()-Runtime.LastOrbitSwitch
        >= CFG.ORBIT_SWITCH_SECONDS
    then
        Runtime.LastOrbitSwitch = os.clock()
        Runtime.OrbitSign *= -1
    end

    desired +=
        tangent
        * CFG.ORBIT_OFFSET
        * Runtime.OrbitSign

    return Vector3.new(
        desired.X,
        player.Y,
        desired.Z
    )
end

function clearApproachPath()
    Runtime.ApproachWaypoints = nil
    Runtime.ApproachIndex = 1
    Runtime.ApproachDestination = nil
    Runtime.ApproachTarget = nil
    Runtime.ApproachFallbackPosition = nil
    Runtime.ApproachFallbackUntil = -math.huge
    Runtime.ApproachLevelTransition = false
end

function approachGoalPosition()
    if not Runtime.Root
        or not Runtime.TargetRoot
        or not Runtime.TargetRoot.Parent
    then
        return nil
    end

    local origin = Runtime.Root.Position
    local target = Runtime.TargetRoot.Position
    local desiredRange = desiredRangeForTarget()

    local away =
        unitHorizontal(
            origin - target
        )

    local levelTransition =
        not sameCombatLevel(origin, target)

    local goalY =
        levelTransition
        and target.Y
        or origin.Y

    return Vector3.new(
        target.X + away.X * desiredRange,
        goalY,
        target.Z + away.Z * desiredRange
    )
end

function computeApproachPath(destination)
    if not Runtime.Root or not destination then
        return false
    end

    local levelTransition =
        not sameCombatLevel(
            Runtime.Root.Position,
            destination
        )

    local maxWaypointVerticalDelta =
        levelTransition
        and (
            CFG.LEVEL_ROUTE_MAX_WAYPOINT_VERTICAL_DELTA
            or CFG.SAFE_VERTICAL_DELTA
        )
        or CFG.SAFE_VERTICAL_DELTA

    local path =
        PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            AgentCanClimb = true,
            WaypointSpacing = 7,
        })

    local ok =
        pcall(
            path.ComputeAsync,
            path,
            Runtime.Root.Position,
            destination
        )

    if not ok
        or path.Status ~= Enum.PathStatus.Success
    then
        return false
    end

    local waypoints = path:GetWaypoints()

    if #waypoints < 2 then
        return false
    end

    local previous =
        Runtime.Root.Position

    for i = 2, #waypoints do
        local point =
            waypoints[i].Position

        if math.abs(point.Y - previous.Y)
            > maxWaypointVerticalDelta
        then
            logKV("APPROACH_PATH_REJECT", {
                index = i,
                reason = "vertical_delta",
                level_route = tostring(levelTransition),
                from = vec(previous),
                to = vec(point),
            })

            return false
        end

        previous = point
    end

    Runtime.ApproachWaypoints = waypoints
    Runtime.ApproachIndex = 2
    Runtime.ApproachDestination = destination
    Runtime.ApproachTarget = Runtime.Target
    Runtime.ApproachLevelTransition = levelTransition

    return true
end

function chooseProgressStep(goal)
    if not Runtime.Root or not goal then
        return nil
    end

    local origin = Runtime.Root.Position
    local forward =
        unitHorizontal(
            goal - origin
        )

    local baseAngle =
        math.atan2(
            forward.Z,
            forward.X
        )

    local currentDistance =
        horizontalDistance(
            origin,
            goal
        )

    local best
    local bestScore = math.huge

    for _, radius in ipairs(CFG.APPROACH_STEP_RADII) do
        for _, degrees in ipairs(CFG.APPROACH_ANGLES) do
            local angle =
                baseAngle + math.rad(degrees)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate =
                origin + dir * radius

            if not movementWallHit(origin, candidate)
                and hasGroundAt(candidate)
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                local route =
                    routeDanger(
                        origin,
                        candidate
                    )

                local candidateDistance =
                    horizontalDistance(
                        candidate,
                        goal
                    )

                local progress =
                    currentDistance - candidateDistance

                local score =
                    danger
                    + route * 0.35
                    + enemyPenalty(candidate) * 0.30
                    + radius * 0.8
                    - progress * 180

                if inside > 0 then
                    score += 70000
                end

                -- Prefer forward. If forward is unsafe, left/right naturally
                -- win. Backtracking is only accepted when everything else is
                -- genuinely dangerous/blocked.
                if progress < -CFG.APPROACH_MIN_PROGRESS then
                    score +=
                        math.abs(progress)
                        * 340
                elseif progress >= CFG.APPROACH_MIN_PROGRESS then
                    score -= 2200
                end

                if clearance ~= math.huge then
                    score -=
                        math.min(
                            math.max(clearance, 0),
                            12
                        ) * 18
                end

                if score < bestScore then
                    bestScore = score
                    best = {
                        Position = candidate,
                        Radius = radius,
                        Progress = progress,
                        Angle = degrees,
                        Score = score,
                    }
                end
            end
        end
    end

    return best
end

function longRangeApproachThink()
    if not Runtime.Root
        or not Runtime.TargetRoot
        or not Runtime.TargetRoot.Parent
        or not Runtime.TargetHumanoid
        or Runtime.TargetHumanoid.Health <= 0
    then
        clearApproachPath()
        return false
    end

    local origin =
        Runtime.Root.Position

    local targetPosition =
        Runtime.TargetRoot.Position

    local distance =
        horizontalDistance(
            origin,
            targetPosition
        )

    local verticalGap =
        verticalDistance(
            origin,
            targetPosition
        )

    local levelTransition =
        verticalGap
            > CFG.TARGET_LEVEL_VERTICAL_TOLERANCE

    local desiredRange =
        desiredRangeForTarget()

    if not levelTransition
        and distance
            <= desiredRange + CFG.APPROACH_TRIGGER_EXTRA
    then
        clearApproachPath()
        return false
    end

    local goal =
        approachGoalPosition()

    if not goal then
        return false
    end

    local now = os.clock()

    local targetChanged =
        Runtime.ApproachTarget ~= Runtime.Target

    local destinationChanged =
        not Runtime.ApproachDestination
        or (
            Runtime.ApproachDestination
            - goal
        ).Magnitude > 18

    local needsPath =
        targetChanged
        or destinationChanged
        or not Runtime.ApproachWaypoints
        or now - Runtime.LastApproachPathAt >= CFG.APPROACH_REPATH_INTERVAL

    if needsPath then
        Runtime.LastApproachPathAt = now

        if computeApproachPath(goal) then
            if now - Runtime.LastApproachLog >= CFG.APPROACH_LOG_COOLDOWN then
                Runtime.LastApproachLog = now

                logKV(
                    levelTransition
                        and "LEVEL_APPROACH_PATH"
                        or "APPROACH_PATH",
                    {
                        target = Runtime.Target.Name,
                        distance = string.format("%.1f", distance),
                        vertical_gap = string.format("%.1f", verticalGap),
                        waypoints = #Runtime.ApproachWaypoints,
                    }
                )
            end
        else
            Runtime.ApproachWaypoints = nil
        end
    end

    local waypoint =
        Runtime.ApproachWaypoints
        and Runtime.ApproachWaypoints[
            Runtime.ApproachIndex
        ]

    if waypoint then
        local waypointDistance =
            Runtime.ApproachLevelTransition
            and (
                Runtime.Root.Position
                - waypoint.Position
            ).Magnitude
            or horizontalDistance(
                Runtime.Root.Position,
                waypoint.Position
            )

        if waypointDistance
            <= CFG.APPROACH_WAYPOINT_REACHED
        then
            Runtime.ApproachIndex += 1
            waypoint =
                Runtime.ApproachWaypoints[
                    Runtime.ApproachIndex
                ]
        end

        if waypoint then
            if waypoint.Action
                == Enum.PathWaypointAction.Jump
            then
                Runtime.Humanoid.Jump = true
            end

            moveTo(
                waypoint.Position,
                Runtime.ApproachLevelTransition
                    and "COMBAT_APPROACH_LEVEL"
                    or "COMBAT_APPROACH_PATH"
            )

            return true
        end
    end

    -- Never fall back to flat orbit/progress while the target is on another
    -- floor. Repath until PathfindingService gives us the legitimate route.
    if levelTransition then
        if now - Runtime.LastApproachLog
            >= CFG.LEVEL_ROUTE_LOG_COOLDOWN
        then
            Runtime.LastApproachLog = now

            logKV("LEVEL_ROUTE_WAIT", {
                target = Runtime.Target.Name,
                horizontal = string.format("%.1f", distance),
                vertical_gap = string.format("%.1f", verticalGap),
            })
        end

        return true
    end

    -- Pathfinding may fail in a scripted boss corridor. Keep making progress
    -- instead of stopping: forward first, then diagonals/left/right, backward
    -- only when no safe progress lane exists.
    if Runtime.ApproachFallbackPosition
        and now < Runtime.ApproachFallbackUntil
        and horizontalDistance(
            Runtime.Root.Position,
            Runtime.ApproachFallbackPosition
        ) > 3
    then
        moveTo(
            Runtime.ApproachFallbackPosition,
            "COMBAT_APPROACH_STEP"
        )

        return true
    end

    local step =
        chooseProgressStep(goal)

    if step then
        Runtime.ApproachFallbackPosition = step.Position
        Runtime.ApproachFallbackUntil = now + CFG.APPROACH_HOLD

        if now - Runtime.LastApproachLog >= CFG.APPROACH_LOG_COOLDOWN then
            Runtime.LastApproachLog = now

            logKV("APPROACH_STEP", {
                target = Runtime.Target.Name,
                distance = string.format("%.1f", distance),
                progress = string.format("%.1f", step.Progress),
                angle = step.Angle,
                radius = step.Radius,
            })
        end

        moveTo(
            step.Position,
            "COMBAT_APPROACH_STEP"
        )

        return true
    end

    return false
end

Runtime.AzrallikSpreadTellCandidate = function(
    bossWave,
    bossThreats
)
    if Runtime.ActiveBossName
            ~= "Demon Lord Azrallik"
        or not Runtime.Root
        or not Runtime.ActiveBossRoot
        or not Runtime.AzrallikSpreadTellOrigin
    then
        return nil
    end

    if bossThreatHas(
        "azrallikPunchSpread",
        bossThreats or {}
    ) then
        return nil
    end

    local now = os.clock()
    local elapsed =
        now
        - (
            Runtime.AzrallikSpreadTellAt
            or -math.huge
        )

    if elapsed < 0
        or elapsed
            > CFG.AZRALLIK_SPREAD_TELL_WINDOW
    then
        Runtime.AzrallikSpreadTellOrigin = nil
        return nil
    end

    if elapsed
        < CFG.AZRALLIK_SPREAD_PREMOVE_START
    then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local bossPosition =
        Runtime.ActiveBossRoot.Position

    local bossDistance =
        horizontalDistance(
            origin,
            bossPosition
        )

    -- If we are still extremely far after a respawn, keep approaching. The
    -- dangerous deaths were consistently in the ~60-90 stud region.
    if bossDistance
        > CFG.AZRALLIK_SPREAD_PREMOVE_MAX_BOSS_DISTANCE
    then
        return nil
    end

    local radial =
        unitHorizontal(
            origin - bossPosition
        )

    if radial.Magnitude <= 0.1 then
        radial =
            unitHorizontal(
                Runtime.Root.CFrame.LookVector
            )
    end

    local tangent =
        Vector3.new(
            -radial.Z,
            0,
            radial.X
        )

    local preferredSign =
        Runtime.AzrallikSpreadOrbitSign
        or 1

    local best
    local bestScore = math.huge

    for _, sign in ipairs({
        preferredSign,
        -preferredSign,
    }) do
        for _, step in ipairs(
            CFG.AZRALLIK_SPREAD_PREMOVE_STEPS
        ) do
            local direction =
                unitHorizontal(
                    tangent * sign
                    + radial * 0.10
                )

            local candidate =
                origin
                + direction * step

            if hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                local crossing =
                    routeDanger(
                        origin,
                        candidate
                    )

                local candidateBossDistance =
                    horizontalDistance(
                        candidate,
                        bossPosition
                    )

                -- Do not use the prediction phase to keep charging inward.
                local inward =
                    math.max(
                        0,
                        bossDistance
                        - candidateBossDistance
                    )

                if inside == 0
                    and crossing
                        <= CFG.AZRALLIK_SPREAD_ROUTE_DANGER_MAX
                then
                    local score =
                        step * 20
                        + crossing * 0.05
                        + inward * 900
                        + (
                            sign == preferredSign
                            and 0
                            or 350
                        )

                    if clearance ~= math.huge then
                        score -=
                            math.min(
                                math.max(clearance, 0),
                                20
                            ) * 35
                    end

                    if score < bestScore then
                        bestScore = score

                        best = {
                            Position = candidate,
                            Radius = step,
                            Score = score,
                            Inside = inside,
                            Clearance = clearance,
                            Label =
                                "azrallik_spread_premove",
                            Source =
                                "AzrallikSpreadTell",
                        }
                    end
                end
            end
        end
    end

    return best
end


Runtime.SamuraiLocalGapCandidate = function(
    bossThreats,
    attackName,
    labelPrefix
)
    if not Runtime.Root
        or not Runtime.ActiveBossRoot
        or not attackName
        or not labelPrefix
        or not bossThreatHas(
            attackName,
            bossThreats or {}
        )
    then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local currentDanger,
        currentInside,
        currentClearance =
            pointDanger(
                origin
            )

    local currentPhysicalPenalty =
        wavePhysicalPenalty(origin)

    local bossPosition =
        Runtime.ActiveBossRoot.Position

    local currentBossDistance =
        horizontalDistance(
            origin,
            bossPosition
        )

    local desiredBossRange =
        CFG.BOSS_DESIRED_RANGE[
            Runtime.ActiveBossName
        ]
        or 28

    local denseMiyamoto =
        Runtime.ActiveBossName
            == "Miyamoto Musashi"
        and (
            Runtime.MiyamotoCycloneActive
            or bossThreatHas(
                "doubleFlameBeam",
                bossThreats
            )
            or (
                bossThreatHas(
                    "flameShurikenHit",
                    bossThreats
                )
                and bossThreatHas(
                    "flameBeam",
                    bossThreats
                )
            )
        )

    local holdClearance =
        denseMiyamoto
        and CFG.MIYAMOTO_DENSE_GAP_HOLD_CLEARANCE
        or CFG.SAMURAI_LOCAL_GAP_HOLD_CLEARANCE

    -- "Safe red geometry" is not actually safe if an Elite/Ultimate/physical
    -- enemy is occupying the same pocket. This was the main Sanada overlap
    -- failure in the two Modular V1 runs.
    if currentInside == 0
        and currentPhysicalPenalty <= 0
        and currentBossDistance
            <= desiredBossRange
                + CFG.SAMURAI_BOSS_GAP_MAX_HOLD_EXTRA
        and not (
            Runtime.ActiveBossName
                == "Miyamoto Musashi"
            and currentBossDistance
                > CFG.MIYAMOTO_ARENA_LEASH
        )
        and (
            currentClearance
                == math.huge
            or currentClearance
                >= holdClearance
        )
    then
        return {
            Position = origin,
            Radius = 0,
            Score = currentDanger,
            Inside = 0,
            Clearance =
                currentClearance,
            Label =
                labelPrefix
                .. "_hold",
            Source =
                denseMiyamoto
                and "SamuraiPalaceDenseExactGap"
                or "SamuraiPalaceExactGap",
        }
    end

    local radii =
        denseMiyamoto
        and CFG.MIYAMOTO_DENSE_GAP_RADII
        or CFG.SAMURAI_LOCAL_GAP_RADII

    local best
    local bestScore =
        math.huge

    for _, radius in ipairs(
        radii
    ) do
        for i = 0,
            CFG.BOSS_WAVE_DIRECTIONS - 1
        do
            local angle =
                math.pi * 2
                * (
                    i
                    / CFG.BOSS_WAVE_DIRECTIONS
                )

            local candidate =
                origin
                + Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                ) * radius

            local candidateSafe =
                safeMovementDestination(
                    candidate,
                    origin
                )

            if candidateSafe
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger,
                    inside,
                    clearance =
                        pointDanger(
                            candidate
                        )

                local crossing =
                    routeDanger(
                        origin,
                        candidate
                    )

                local physicalPenalty =
                    wavePhysicalPenalty(
                        candidate
                    )

                local requiredClearance =
                    Runtime.ActiveBossName == "Sanada Yukimura"
                    and CFG.SANADA_COMMITTED_GAP_MIN_CLEARANCE
                    or (
                        Runtime.ActiveBossName
                            == "Ancient Golem Guardian"
                        and CFG.GOLEM_COMMITTED_GAP_MIN_CLEARANCE
                        or (
                            Runtime.ActiveBossName
                                == "Miyamoto Musashi"
                            and math.max(
                                CFG.MIYAMOTO_COMMITTED_GAP_MIN_CLEARANCE,
                                denseMiyamoto
                                    and CFG.MIYAMOTO_DENSE_GAP_MIN_CLEARANCE
                                    or 0
                            )
                            or 0
                        )
                    )

                local clearanceOkay =
                    clearance == math.huge
                    or clearance >= requiredClearance

                if inside == 0
                    and clearanceOkay
                    and crossing
                        <= CFG.SAMURAI_LOCAL_GAP_ROUTE_MAX
                then
                    local candidateBossDistance =
                        horizontalDistance(
                            candidate,
                            bossPosition
                        )

                    local rangeError =
                        math.abs(
                            candidateBossDistance
                            - desiredBossRange
                        )

                    local retreat =
                        math.max(
                            0,
                            candidateBossDistance
                            - currentBossDistance
                        )

                    local approach =
                        math.max(
                            0,
                            currentBossDistance
                            - candidateBossDistance
                        )

                    local rangePenalty =
                        rangeError
                            * CFG.SAMURAI_BOSS_GAP_RANGE_WEIGHT
                        + retreat
                            * CFG.SAMURAI_BOSS_GAP_RETREAT_WEIGHT
                        - approach
                            * CFG.SAMURAI_BOSS_GAP_APPROACH_REWARD

                    local hardLeash =
                        Runtime.ActiveBossName
                            == "Miyamoto Musashi"
                        and CFG.MIYAMOTO_ARENA_LEASH
                        or CFG.SAMURAI_BOSS_GAP_HARD_LEASH

                    if candidateBossDistance
                        > hardLeash
                    then
                        rangePenalty +=
                            180000
                            + (
                                candidateBossDistance
                                - hardLeash
                            ) * 10000
                    end

                    local score =
                        danger * 0.05
                        + radius * 110
                        + crossing * 0.05
                        + rangePenalty
                        + physicalPenalty
                            * CFG.SAMURAI_LOCAL_GAP_PHYSICAL_WEIGHT

                    if clearance
                            ~= math.huge
                    then
                        score -=
                            math.min(
                                math.max(
                                    clearance,
                                    0
                                ),
                                20
                            ) * 80
                    end

                    if score < bestScore then
                        bestScore =
                            score

                        best = {
                            Position =
                                candidate,
                            Radius =
                                radius,
                            Score =
                                score,
                            Inside =
                                inside,
                            Clearance =
                                clearance,
                            Label =
                                labelPrefix
                                .. "_local_gap",
                            Source =
                                denseMiyamoto
                                and "SamuraiPalaceDenseExactGap"
                                or "SamuraiPalaceExactGap",
                        }
                    end
                end
            end
        end
    end

    return best
end


Runtime.AzrallikSpreadActiveCandidate = function(
    bossWave,
    bossThreats
)
    if Runtime.ActiveBossName
            ~= "Demon Lord Azrallik"
        or not Runtime.Root
        or not Runtime.ActiveBossRoot
        or not bossThreatHas(
            "azrallikPunchSpread",
            bossThreats or {}
        )
    then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local _, currentInside, currentClearance =
        pointDanger(origin)

    -- The old generic solver could choose a 38-46 stud destination even when
    -- the current point was already in a safe radial gap. Walking toward that
    -- distant point crossed the active fan and caused the observed deaths.
    if currentInside == 0
        and (
            currentClearance == math.huge
            or currentClearance
                >= CFG.AZRALLIK_SPREAD_HOLD_CLEARANCE
        )
    then
        return {
            Position = origin,
            Radius = 0,
            Score = 0,
            Inside = 0,
            Clearance = currentClearance,
            Label = "azrallik_spread_hold",
            Source = "AzrallikSpreadSafeGap",
        }
    end

    local bossPosition =
        Runtime.ActiveBossRoot.Position

    local currentBossDistance =
        horizontalDistance(
            origin,
            bossPosition
        )

    local best
    local bestScore = math.huge

    for _, radius in ipairs(
        CFG.AZRALLIK_SPREAD_LOCAL_RADII
    ) do
        for i = 0,
            CFG.BOSS_WAVE_DIRECTIONS - 1
        do
            local angle =
                (math.pi * 2)
                * (
                    i
                    / CFG.BOSS_WAVE_DIRECTIONS
                )

            local candidate =
                origin
                + Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                ) * radius

            if hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                local candidateBossDistance =
                    horizontalDistance(
                        candidate,
                        bossPosition
                    )

                local crossing =
                    routeDanger(
                        origin,
                        candidate
                    )

                local inward =
                    math.max(
                        0,
                        currentBossDistance
                        - candidateBossDistance
                    )

                local score =
                    inside * 100000
                    + danger * 0.05
                    + radius * 160
                    + crossing * 0.04
                    + inward * 500

                if clearance ~= math.huge then
                    score -=
                        math.min(
                            math.max(clearance, 0),
                            20
                        ) * 90
                end

                if score < bestScore then
                    bestScore = score

                    best = {
                        Position = candidate,
                        Radius = radius,
                        Score = score,
                        Inside = inside,
                        Clearance = clearance,
                        Label =
                            "azrallik_spread_local_gap",
                        Source =
                            "AzrallikSpreadExact",
                    }
                end
            end
        end
    end

    return best
end


Runtime.AzrallikFingerTellCandidate = function()
    if Runtime.ActiveBossName ~= "Demon Lord Azrallik"
        or not Runtime.Root
        or not Runtime.Humanoid
        or not Runtime.AzrallikFingerTellOrigin
    then
        return nil
    end

    local now = os.clock()
    local elapsed =
        now - (Runtime.AzrallikFingerTellAt or -math.huge)

    if elapsed < 0
        or elapsed > CFG.AZRALLIK_FINGER_TELL_WINDOW
    then
        Runtime.AzrallikFingerTellOrigin = nil
        Runtime.AzrallikFingerTellMoved = false
        return nil
    end

    local origin =
        Runtime.AzrallikFingerTellOrigin

    local escaped =
        horizontalDistance(
            Runtime.Root.Position,
            origin
        )

    if escaped >= CFG.AZRALLIK_FINGER_PREHOLD_CLEARANCE then
        local _, inside, clearance =
            pointDanger(Runtime.Root.Position)

        return {
            Position = Runtime.Root.Position,
            Radius = 0,
            Score = 0,
            Inside = inside,
            Clearance = clearance,
            Label = "azrallik_finger_premove_hold",
            Source = "AzrallikFingerTellHold",
        }
    end

    local bossRoot =
        Runtime.ActiveBossModel
        and modelRoot(Runtime.ActiveBossModel)

    local preferred =
        bossRoot
        and unitHorizontal(
            Runtime.Root.Position - bossRoot.Position
        )
        or unitHorizontal(Runtime.Root.CFrame.RightVector)

    local escape =
        chooseOpenSpacePoint(
            Runtime.Root.Position,
            preferred,
            CFG.AZRALLIK_FINGER_PREMOVE_MIN_RADIUS
        )

    if not escape then
        return nil
    end

    local _, inside, clearance =
        pointDanger(escape.Position)

    if inside > 0 then
        return nil
    end

    escape.Inside = inside
    escape.Clearance = clearance
    escape.Label = "azrallik_finger_premove"
    escape.Source = "AzrallikFingerTell"

    return escape
end

Runtime.AzrallikFingerTellMove = function()
    if activeThreatCount() > 0
        or Runtime.BossWave
        or Runtime.DodgeActive
    then
        return false
    end

    local plan =
        Runtime.AzrallikFingerTellCandidate
        and Runtime.AzrallikFingerTellCandidate()

    if not plan then
        return false
    end

    if plan.Label == "azrallik_finger_premove_hold" then
        pcall(function()
            Runtime.Humanoid:MoveTo(Runtime.Root.Position)
        end)

        Runtime.MovementOwner = "AZRALLIK_FINGER_PREHOLD"
        return true
    end

    moveTo(
        plan.Position,
        "AZRALLIK_FINGER_PREMOVE"
    )

    if not Runtime.AzrallikFingerTellMoved then
        Runtime.AzrallikFingerTellMoved = true

        logKV("AZRALLIK_FINGER_PREMOVE", {
            elapsed =
                string.format(
                    "%.2f",
                    os.clock() - Runtime.AzrallikFingerTellAt
                ),
            radius = string.format("%.1f", plan.Radius),
            target = vec(plan.Position),
        })
    end

    return true
end

function combatMovement()
    if Runtime.AzrallikFingerTellMove
        and Runtime.AzrallikFingerTellMove()
    then
        return true
    end

    if Runtime.Root
        and Runtime.TargetRoot
        and Runtime.TargetRoot.Parent
        and not sameCombatLevel(
            Runtime.Root.Position,
            Runtime.TargetRoot.Position
        )
    then
        return longRangeApproachThink()
    end

    if physicalPressureMove() then
        return true
    end

    if longRangeApproachThink() then
        return true
    end

    if not Runtime.TargetRoot
        or not Runtime.TargetRoot.Parent
        or not Runtime.Root
    then
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            Runtime.TargetRoot.Position
        )

    local desired = desiredCombatPoint()
    if not desired then return false end

    -- Move only when range is meaningfully off or maintain lateral orbit.
    local desiredRange = desiredRangeForTarget()

    if distance > desiredRange + 3
        or distance < desiredRange - 2
    then
        moveTo(safeCombatDestination(desired),"COMBAT_RANGE")
    else
        -- Small lateral reposition keeps mage lines from repeatedly targeting
        -- a stationary character.
        moveTo(safeCombatDestination(desired),"COMBAT_ORBIT")
    end

    return true
end


