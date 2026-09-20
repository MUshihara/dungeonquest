-- DQR modular runtime: core/DodgePlanner.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Collision / candidate scoring
-- ============================================================

function isTransientMovementPart(inst)
    if not inst or not inst:IsA("BasePart") then
        return false
    end

    if not inst.CanCollide then
        return true
    end

    local top = topWorkspaceChild(inst)

    if top then
        if PLAYER_ATTACK_ROOTS[top.Name]
            or KNOWN_THREAT_ROOTS[top.Name]
        then
            return true
        end
    end

    local lower = string.lower(inst.Name)

    if lower == "hitbox"
        or lower == "precast"
        or lower == "glowpart"
    then
        return true
    end

    -- Living NPC/character body parts are not map walls.
    local cur = inst
    for _ = 1, 5 do
        if not cur then break end

        if cur:IsA("Model")
            and cur:FindFirstChildOfClass("Humanoid")
        then
            return true
        end

        cur = cur.Parent
    end

    return false
end

function staticObstacleRay(a, b, maxDistance)
    if not Runtime.Character then
        return nil
    end

    local delta = b - a
    local horizontalLength = horizontal(delta).Magnitude

    if horizontalLength < 0.5 then
        return nil
    end

    local ignore = {
        Runtime.Character,
    }

    -- Skip transient combat geometry and keep looking behind it for a real
    -- collidable map wall.
    for _ = 1, 10 do
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = ignore

        pcall(function()
            params.RespectCanCollide = true
        end)

        local origin = a + Vector3.new(0, 2.6, 0)
        local result = workspace:Raycast(origin, delta, params)

        if not result then
            return nil
        end

        if result.Normal.Y > 0.62 then
            return nil
        end

        if isTransientMovementPart(result.Instance) then
            ignore[#ignore + 1] = result.Instance
        else
            if maxDistance
                and result.Distance > maxDistance
            then
                -- A wall hundreds of studs away should not make the character
                -- sidestep now. Keep progressing until it is locally relevant.
                return nil
            end

            return result
        end
    end

    return nil
end


function groundBelow(point, depth)
    if not Runtime.Character then
        return nil
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        Runtime.Character,
    }

    return workspace:Raycast(
        point + Vector3.new(0, 4, 0),
        Vector3.new(
            0,
            -(depth or CFG.SAFE_GROUND_DEPTH),
            0
        ),
        params
    )
end

function safeMovementDestination(point, origin, allowLevelChange)
    if not point then
        return false, "nil"
    end

    origin =
        origin
        or (Runtime.Root and Runtime.Root.Position)

    local maxVerticalDelta =
        allowLevelChange
        and (
            CFG.LEVEL_ROUTE_MAX_WAYPOINT_VERTICAL_DELTA
            or CFG.SAFE_VERTICAL_DELTA
        )
        or CFG.SAFE_VERTICAL_DELTA

    if origin
        and math.abs(point.Y - origin.Y)
            > maxVerticalDelta
    then
        return false, "vertical_delta"
    end

    if Runtime.LastSafePosition
        and point.Y
            < Runtime.LastSafePosition.Y
                - CFG.VOID_DROP_TRIGGER
    then
        return false, "below_safe_anchor"
    end

    local ground =
        groundBelow(
            point,
            CFG.SAFE_GROUND_DEPTH
        )

    if not ground then
        return false, "no_ground"
    end

    local gap =
        point.Y - ground.Position.Y

    if gap > CFG.SAFE_GROUND_MAX_GAP
        or gap < -3
    then
        return false, "ground_gap"
    end

    return true, "ok"
end

function updateSafeAnchor()
    if not Runtime.Root
        or not Runtime.Humanoid
        or Runtime.Humanoid.Health <= 0
    then
        return false
    end

    local now = os.clock()

    if now - Runtime.LastSafeAnchorAt
        >= CFG.SAFE_ANCHOR_REFRESH
    then
        Runtime.LastSafeAnchorAt = now

        local pos =
            Runtime.Root.Position

        local ground =
            groundBelow(
                pos,
                CFG.SAFE_GROUND_DEPTH
            )

        if ground then
            local gap =
                pos.Y - ground.Position.Y

            if gap >= 0
                and gap <= CFG.SAFE_GROUND_MAX_GAP
            then
                Runtime.LastSafePosition = pos
                Runtime.LastSafeCFrame =
                    Runtime.Root.CFrame
            end
        end
    end

    local pos =
        Runtime.Root.Position

    if Runtime.LastSafePosition
        and pos.Y
            < Runtime.LastSafePosition.Y
                - CFG.VOID_DROP_TRIGGER
        and now - Runtime.LastVoidRecovery
            >= CFG.VOID_RECOVERY_COOLDOWN
    then
        Runtime.LastVoidRecovery = now

        if stopTransitTween then
            stopTransitTween("void_recovery")
        end

        if Runtime.LastSafeCFrame then
            pcall(function()
                Runtime.Root.AssemblyLinearVelocity =
                    Vector3.zero
                Runtime.Root.AssemblyAngularVelocity =
                    Vector3.zero
                Runtime.Root.CFrame =
                    Runtime.LastSafeCFrame

                Runtime.Humanoid:MoveTo(
                    Runtime.Root.Position
                )
                Runtime.Humanoid:Move(
                    Vector3.zero,
                    false
                )
            end)

            Runtime.ApproachWaypoints = nil
            Runtime.PathWaypoints = nil
            Runtime.WallEscapePosition = nil
            Runtime.MovementOwner = "NONE"

            logKV("VOID_RECOVERY", {
                from_y =
                    string.format("%.1f", pos.Y),
                safe_y =
                    string.format(
                        "%.1f",
                        Runtime.LastSafePosition.Y
                    ),
            })

            return true
        end
    end

    return false
end

function wallBlocked(a, b)
    local delta = b - a

    if horizontal(delta).Magnitude < 1 then
        return false
    end

    local result = staticObstacleRay(a, b, nil)

    if not result then
        return false
    end

    return
        result.Distance
        < horizontal(delta).Magnitude * 0.90
end

function enemyPenalty(point)
    local penalty = 0

    for _, enemy in ipairs(livingEnemies()) do
        local dist =
            horizontalDistance(
                point,
                enemy.Root.Position
            )

        if enemy.Model ~= Runtime.Target
            and dist < Profile.EnemyBuffer
        then
            penalty +=
                (Profile.EnemyBuffer - dist) * 350
        end
    end

    return penalty
end

function targetPositionScore(point)
    if not Runtime.TargetRoot
        or not Runtime.TargetRoot.Parent
    then
        return 0
    end

    local d =
        horizontalDistance(
            point,
            Runtime.TargetRoot.Position
        )

    local error =
        math.abs(d - desiredRangeForTarget())

    return error * 5
end

function wavePhysicalPenalty(point)
    local penalty = 0

    for _, enemy in ipairs(livingEnemies()) do
        if enemy.Model
            and enemy.Root
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and isPhysicalEnemyModel(enemy.Model)
            and physicalThreatRelevantForMovement(
                enemy,
                point
            )
        then
            local dist =
                horizontalDistance(
                    point,
                    enemy.Root.Position
                )

            if enemy.Model.Name == "Blood Minion" then
                local predictedEnemy =
                    enemy.Root.Position
                    + horizontal(
                        enemy.Root.AssemblyLinearVelocity
                    )
                    * CFG.BLOOD_MINION_WAVE_PREDICT_TIME

                dist =
                    math.min(
                        dist,
                        horizontalDistance(
                            point,
                            predictedEnemy
                        )
                    )
            end

            local hard = CFG.WAVE_PHYSICAL_HARD_RADIUS
            local soft = CFG.WAVE_PHYSICAL_SOFT_RADIUS

            if enemy.Model.Name == "Samurai Swordsman"
                or enemy.Model.Name == "Elite Swordsman"
                or enemy.Model.Name == "Ultimate Swordsman"
            then
                hard =
                    math.max(
                        hard,
                        CFG.SAMURAI_WAVE_PHYSICAL_HARD_RADIUS
                    )
                soft =
                    math.max(
                        soft,
                        CFG.SAMURAI_WAVE_PHYSICAL_SOFT_RADIUS
                    )
            end

            if enemy.Model.Name == "Blood Minion" then
                hard = math.max(hard, CFG.BLOOD_MINION_CRITICAL_RADIUS + 3)
                soft = math.max(soft, CFG.BLOOD_MINION_SOFT_RADIUS + 2)
            end

            if dist <= hard then
                penalty +=
                    CFG.WAVE_PHYSICAL_HARD_PENALTY
                    + (hard - dist) * 7000
            elseif dist < soft then
                penalty +=
                    (soft - dist)
                    * CFG.WAVE_PHYSICAL_SOFT_PENALTY
            end
        end
    end

    return penalty
end

function bossThreatHas(rootName, threats)
    for _, meta in ipairs(threats or {}) do
        if meta.RootName == rootName then
            return true
        end
    end

    return false
end



function pushCandidate(list, position, label)
    if not position then return end
    list[#list + 1] = {
        Position = position,
        Label = label or "candidate",
    }
end


function humanoidAncestor(inst)
    local cur = inst

    for _ = 1, 5 do
        if not cur then break end

        if cur:IsA("Model")
            and cur:FindFirstChildOfClass("Humanoid")
        then
            return cur
        end

        cur = cur.Parent
    end

    return nil
end

function movementWallHit(a, b)
    local delta = b - a

    if horizontal(delta).Magnitude < 0.5 then
        return nil
    end

    return staticObstacleRay(
        a,
        b,
        math.min(
            CFG.WALL_LOCAL_INTERCEPT,
            horizontal(delta).Magnitude * 0.92
        )
    )
end

function hasGroundAt(point)
    if not Runtime.Character then
        return true
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        Runtime.Character,
    }

    local origin = point + Vector3.new(0, 4, 0)

    local result =
        workspace:Raycast(
            origin,
            Vector3.new(0, -CFG.WALL_GROUND_CHECK, 0),
            params
        )

    return result ~= nil
end

function localWallClearance(point)
    local minClearance = 999
    local openCount = 0
    local rayLength = CFG.WALL_LOOKAHEAD

    for i = 0, 7 do
        local angle = (math.pi * 2) * (i / 8)
        local dir = Vector3.new(
            math.cos(angle),
            0,
            math.sin(angle)
        )

        local hit =
            movementWallHit(
                point,
                point + dir * rayLength
            )

        if hit then
            minClearance = math.min(minClearance, hit.Distance)
        else
            openCount += 1
        end
    end

    if minClearance == 999 then
        minClearance = rayLength
    end

    return minClearance, openCount
end

function scoreOpenMovementCandidate(origin, candidate, preferredDir)
    if movementWallHit(origin, candidate) then
        return math.huge
    end

    if not hasGroundAt(candidate) then
        return math.huge
    end

    local danger, inside, threatClearance =
        pointDanger(candidate)

    if inside > 0 then
        danger += inside * 50000
    end

    local wallClearance, openCount =
        localWallClearance(candidate)

    local score =
        danger
        + routeDanger(origin, candidate) * 0.22
        + enemyPenalty(candidate) * 0.55
        + targetPositionScore(candidate) * 0.35
        + horizontalDistance(origin, candidate) * 1.4
        - wallClearance * 95
        - openCount * 120

    if preferredDir then
        local travel =
            unitHorizontal(candidate - origin)

        score -=
            math.max(
                preferredDir:Dot(travel),
                -1
            ) * 180
    end

    if threatClearance ~= math.huge then
        score -=
            math.min(
                math.max(threatClearance, 0),
                12
            ) * 18
    end

    return score
end

function chooseOpenSpacePoint(
    origin,
    preferredDir,
    minRadius
)
    local baseAngle = 0

    if preferredDir and preferredDir.Magnitude > 0.01 then
        baseAngle =
            math.atan2(
                preferredDir.Z,
                preferredDir.X
            )
    end

    local best
    local bestScore = math.huge

    for _, radius in ipairs(CFG.WALL_ESCAPE_RADII) do
        if not minRadius
            or radius >= minRadius
        then
            for i = 0, CFG.WALL_ESCAPE_DIRECTIONS - 1 do
                local angle =
                    baseAngle
                    + (math.pi * 2)
                        * (i / CFG.WALL_ESCAPE_DIRECTIONS)

                local dir =
                    Vector3.new(
                        math.cos(angle),
                        0,
                        math.sin(angle)
                    )

                local candidate =
                    origin + dir * radius

                local score =
                    scoreOpenMovementCandidate(
                        origin,
                        candidate,
                        preferredDir
                    )

                if score < bestScore then
                    bestScore = score
                    best = {
                        Position = candidate,
                        Radius = radius,
                        Score = score,
                        Label = "open_space",
                    }
                end
            end
        end
    end

    return best
end

function resolveWallAwareDestination(origin, desired, reason)
    if not origin or not desired then
        return desired, false
    end

    local horizontalDelta =
        horizontal(desired - origin)

    if horizontalDelta.Magnitude < 0.8 then
        return desired, false
    end

    local hit =
        movementWallHit(
            origin,
            desired
        )

    if not hit then
        return desired, false
    end

    local desiredDir =
        unitHorizontal(horizontalDelta)

    local wallNormal =
        unitHorizontal(
            Vector3.new(
                hit.Normal.X,
                0,
                hit.Normal.Z
            )
        )

    local tangent =
        Vector3.new(
            -wallNormal.Z,
            0,
            wallNormal.X
        )

    local distance =
        math.clamp(
            horizontalDelta.Magnitude,
            6,
            16
        )

    local dirs = {
        tangent,
        -tangent,
        unitHorizontal(tangent + wallNormal * 0.40),
        unitHorizontal(-tangent + wallNormal * 0.40),
        wallNormal,
        unitHorizontal(desiredDir + tangent * 0.80),
        unitHorizontal(desiredDir - tangent * 0.80),
    }

    local best
    local bestScore = math.huge

    for _, dir in ipairs(dirs) do
        local candidate =
            origin + dir * distance

        local score =
            scoreOpenMovementCandidate(
                origin,
                candidate,
                desiredDir
            )

        if score < bestScore then
            bestScore = score
            best = candidate
        end
    end

    if not best or bestScore == math.huge then
        local fallback =
            chooseOpenSpacePoint(
                origin,
                wallNormal
            )

        best =
            fallback
            and fallback.Position
            or desired
    end

    local now = os.clock()

    if now - Runtime.LastWallLog >= CFG.WALL_LOG_COOLDOWN then
        Runtime.LastWallLog = now

        logKV("WALL_AVOID", {
            reason = tostring(reason),
            hit = fullName(hit.Instance),
            hit_distance = string.format("%.1f", hit.Distance),
            requested = vec(desired),
            resolved = vec(best),
        })
    end

    return best, true
end

function beginWallEscape(reason)
    if not Runtime.Root then
        return false
    end

    local now = os.clock()

    if now - Runtime.LastWallEscape < CFG.WALL_ESCAPE_COOLDOWN then
        return false
    end

    local origin = Runtime.Root.Position
    local preferred

    local physical, physicalDist =
        nearestPhysicalEnemy(origin)

    if physical and physical.Root and physicalDist < 45 then
        preferred =
            unitHorizontal(
                origin - physical.Root.Position
            )

    elseif Runtime.TargetRoot then
        if activeThreatCount() == 0 then
            preferred =
                unitHorizontal(
                    Runtime.TargetRoot.Position
                    - origin
                )
        else
            preferred =
                unitHorizontal(
                    origin - Runtime.TargetRoot.Position
                )
        end

    else
        preferred =
            unitHorizontal(
                Runtime.Root.CFrame.LookVector
            )
    end

    local minRadius

    if activeThreatCount() == 0
        and reason == "COMBAT_APPROACH_PATH"
    then
        minRadius =
            math.min(
                CFG.BOSS_STALL_RECOVERY_MAX_RADIUS,
                6
                + Runtime.WallEscapeAttempts * 6
            )
    end

    local candidate =
        chooseOpenSpacePoint(
            origin,
            preferred,
            minRadius
        )

    if not candidate then
        return false
    end

    Runtime.WallEscapePosition = candidate.Position
    Runtime.WallEscapeUntil = now + CFG.WALL_ESCAPE_HOLD
    Runtime.WallEscapeStarted =
        Runtime.WallEscapeStarted or now
    Runtime.WallEscapeAttempts += 1
    Runtime.LastWallEscape = now

    logKV("WALL_ESCAPE", {
        reason = tostring(reason),
        attempt = Runtime.WallEscapeAttempts,
        radius = string.format("%.1f", candidate.Radius),
        position = vec(candidate.Position),
    })

    return true
end

function directEscapeCandidates(origin)
    local out = {}

    -- First solve the geometry directly. Thin lines usually need only a
    -- perpendicular edge exit, not a 360-degree search.
    for _, meta in ipairs(activeThreats()) do
        local g = threatGeometry(meta)

        if g then
            if g.Type == "Circle" then
                local delta = horizontal(origin - g.Center)
                local dist = delta.Magnitude
                local dir

                if dist > 0.05 then
                    dir = delta.Unit
                elseif Runtime.TargetRoot then
                    dir = unitHorizontal(origin - Runtime.TargetRoot.Position)
                else
                    dir = unitHorizontal(Runtime.Root.CFrame.RightVector)
                end

                local required =
                    math.max(
                        0,
                        g.Radius - dist
                    )
                    + CFG.DIRECT_ESCAPE_EXTRA

                if required > 0.05 then
                    pushCandidate(
                        out,
                        origin + dir * required,
                        "circle_edge"
                    )
                end
            else
                local part = g.Part
                local lp = part.CFrame:PointToObjectSpace(origin)
                local axisA, axisB = horizontalAxesForPart(part)

                local function addAxis(axis, coord, axisName)
                    local worldAxis = horizontal(axis.Vec)

                    if worldAxis.Magnitude < 0.05 then
                        return
                    end

                    worldAxis = worldAxis.Unit

                    local plusDistance =
                        axis.Half
                        + CFG.SAFETY_MARGIN
                        - coord
                        + CFG.DIRECT_ESCAPE_EXTRA

                    local minusDistance =
                        axis.Half
                        + CFG.SAFETY_MARGIN
                        + coord
                        + CFG.DIRECT_ESCAPE_EXTRA

                    if plusDistance > 0 then
                        pushCandidate(
                            out,
                            origin + worldAxis * plusDistance,
                            axisName .. "_plus"
                        )
                    end

                    if minusDistance > 0 then
                        pushCandidate(
                            out,
                            origin - worldAxis * minusDistance,
                            axisName .. "_minus"
                        )
                    end
                end

                local minHalf =
                    math.min(axisA.Half, axisB.Half)
                local maxHalf =
                    math.max(axisA.Half, axisB.Half)

                -- Long/thin line hazards must exit across their SHORT axis.
                -- V1.1 could select the 73-stud long edge and produce a
                -- 60-70 stud dodge for a 4-stud-wide Shuriken line.
                if minHalf > 0
                    and maxHalf / minHalf
                        >= CFG.LARGE_LINE_ASPECT_RATIO
                then
                    local narrow =
                        axisA.Half <= axisB.Half
                        and axisA
                        or axisB

                    addAxis(
                        narrow,
                        componentByIndex(
                            lp,
                            narrow.LocalIndex
                        ),
                        "line_short"
                    )
                else
                    addAxis(
                        axisA,
                        componentByIndex(lp, axisA.LocalIndex),
                        "boxA"
                    )
                    addAxis(
                        axisB,
                        componentByIndex(lp, axisB.LocalIndex),
                        "boxB"
                    )
                end
            end
        end
    end

    for _, vt in pairs(Runtime.VirtualThreats) do
        local delta = horizontal(origin - vt.Center)
        local dist = delta.Magnitude

        if dist <= vt.Radius + CFG.SAFETY_MARGIN then
            local dir =
                dist > 0.05
                and delta.Unit
                or unitHorizontal(Runtime.Root.CFrame.RightVector)

            local required =
                vt.Radius
                + CFG.SAFETY_MARGIN
                - dist
                + CFG.DIRECT_ESCAPE_EXTRA

            pushCandidate(
                out,
                origin + dir * required,
                "virtual_edge"
            )
        end
    end


    return out
end

function scoreEscapeCandidate(origin, candidate)
    local danger, inside, clearance = pointDanger(candidate.Position)

    local score =
        danger
        + routeDanger(origin, candidate.Position)
        + enemyPenalty(candidate.Position)
        + targetPositionScore(candidate.Position)

    local travel =
        horizontalDistance(origin, candidate.Position)

    score += travel * 2.5

    if wallBlocked(origin, candidate.Position) then
        score += 50000
    end

    if clearance ~= math.huge then
        score -= math.min(math.max(clearance, 0), 10) * 12
    end

    return {
        Position = candidate.Position,
        Radius = travel,
        Score = score,
        Inside = inside,
        Clearance = clearance,
        Label = candidate.Label,
    }
end

function chooseDodgePoint()
    if not Runtime.Root then return nil end

    local origin = Runtime.Root.Position

    -- 1) Geometry-first exits: usually 2-8 candidates total.
    local direct = directEscapeCandidates(origin)
    local best
    local bestScore = math.huge

    for _, candidate in ipairs(direct) do
        local scored = scoreEscapeCandidate(origin, candidate)

        if scored.Score < bestScore then
            bestScore = scored.Score
            best = scored
        end
    end

    -- If a direct edge exit is safe, take it. This is far cheaper and
    -- typically shorter than a 360-degree grid.
    if best and best.Inside == 0 and best.Score < 50000 then
        return best
    end

    -- 2) Overlap / blocked fallback: only 16 directions x 6 radii = 96
    -- points, and enemy data is cached. V1 used 400 points and performed
    -- repeated full dungeon scans from inside the candidate loop.
    local base =
        Runtime.TargetRoot
        and unitHorizontal(Runtime.TargetRoot.Position - origin)
        or unitHorizontal(Runtime.Root.CFrame.LookVector)

    local baseAngle = math.atan2(base.Z, base.X)

    for _, radius in ipairs(CFG.CANDIDATE_RADII) do
        for i = 0, CFG.CANDIDATE_DIRECTIONS - 1 do
            local angle =
                baseAngle
                + (math.pi * 2)
                * (i / CFG.CANDIDATE_DIRECTIONS)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local scored =
                scoreEscapeCandidate(
                    origin,
                    {
                        Position = origin + dir * radius,
                        Label = "fallback",
                    }
                )

            if scored.Score < bestScore then
                bestScore = scored.Score
                best = scored
            end
        end
    end

    return best
end

function chooseMageWavePoint()
    if not Runtime.Root then
        return nil
    end

    local origin = Runtime.Root.Position
    local base =
        Runtime.TargetRoot
        and unitHorizontal(
            Runtime.TargetRoot.Position - origin
        )
        or unitHorizontal(
            Runtime.Root.CFrame.LookVector
        )

    local baseAngle =
        math.atan2(
            base.Z,
            base.X
        )

    local best
    local bestScore = math.huge

    local pressureBest
    local pressureBestScore = math.huge

    local pressureActive =
        Runtime.MageFreePressureActive
        and Runtime.MageFreePressureActive()

    local currentTargetDistance =
        pressureActive
        and Runtime.TargetRoot
        and horizontalDistance(
            origin,
            Runtime.TargetRoot.Position
        )
        or math.huge

    local targetWeight = 0.75

    if pressureActive then
        targetWeight =
            CFG.MAGE_FREE_PRESSURE_WAVE_TARGET_WEIGHT
    end

    for _, radius in ipairs(
        CFG.MAGE_WAVE_RADII
    ) do
        for i = 0,
            CFG.MAGE_WAVE_DIRECTIONS - 1
        do
            local angle =
                baseAngle
                + (math.pi * 2)
                    * (
                        i
                        / CFG.MAGE_WAVE_DIRECTIONS
                    )

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate =
                origin + dir * radius

            local danger,
                inside,
                clearance =
                pointDanger(candidate)

            local blocked =
                wallBlocked(
                    origin,
                    candidate
                )

            local score =
                danger
                + routeDanger(
                    origin,
                    candidate
                ) * 0.48
                + enemyPenalty(candidate)
                + wavePhysicalPenalty(candidate)
                + targetPositionScore(candidate)
                    * targetWeight
                + radius * 1.1

            if blocked then
                score += 50000
            end

            if inside == 0 then
                score -= 14000
            end

            if clearance ~= math.huge then
                score -=
                    math.min(
                        math.max(
                            clearance,
                            0
                        ),
                        12
                    ) * 26
            end

            -- Mage-only pressure:
            -- track a separate SMALL safe sidestep that does not throw us
            -- away from the mage. This wins over the generic "maximum gap"
            -- behavior whenever such a local point exists.
            if pressureActive
                and inside == 0
                and not blocked
                and radius
                    <= CFG.MAGE_PRESSURE_LOCAL_DODGE_MAX_RADIUS
            then
                local candidateTargetDistance =
                    Runtime.TargetRoot
                    and horizontalDistance(
                        candidate,
                        Runtime.TargetRoot.Position
                    )
                    or math.huge

                local keepsPressure =
                    candidateTargetDistance
                        <= CFG.MAGE_PRESSURE_MAX_DPS_DISTANCE
                    or candidateTargetDistance
                        <= currentTargetDistance
                            + CFG.MAGE_PRESSURE_BACKTRACK_TOLERANCE

                if keepsPressure then
                    local pressureScore =
                        score
                        + candidateTargetDistance
                            * 180
                        + radius * 65

                    if pressureScore
                        < pressureBestScore
                    then
                        pressureBestScore =
                            pressureScore

                        pressureBest = {
                            Position = candidate,
                            Radius = radius,
                            Score = pressureScore,
                            Inside = inside,
                            Clearance = clearance,
                            Label =
                                "mage_pressure_local_gap",
                            Source =
                                "MagePressure",
                        }
                    end
                end
            end

            if score < bestScore then
                bestScore = score

                best = {
                    Position = candidate,
                    Radius = radius,
                    Score = score,
                    Inside = inside,
                    Clearance = clearance,
                    Label = "mage_wave_gap",
                    Source = "MageWave",
                }
            end
        end
    end

    return pressureBest or best
end

function chooseBossWavePoint()
    if not Runtime.Root then
        return nil
    end

    local origin = Runtime.Root.Position
    local base =
        Runtime.ActiveBossRoot
        and unitHorizontal(Runtime.ActiveBossRoot.Position - origin)
        or (
            Runtime.TargetRoot
            and unitHorizontal(Runtime.TargetRoot.Position - origin)
            or unitHorizontal(Runtime.Root.CFrame.LookVector)
        )

    local baseAngle = math.atan2(base.Z, base.X)
    local best
    local bestScore = math.huge

    for _, radius in ipairs(CFG.BOSS_WAVE_RADII) do
        for i = 0, CFG.BOSS_WAVE_DIRECTIONS - 1 do
            local angle =
                baseAngle
                + (math.pi * 2) * (i / CFG.BOSS_WAVE_DIRECTIONS)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate = origin + dir * radius
            local danger, inside, clearance = pointDanger(candidate)

            local score =
                danger
                + routeDanger(origin, candidate) * 0.55
                + enemyPenalty(candidate)
                + wavePhysicalPenalty(candidate)
                + targetPositionScore(candidate) * 1.20
                + radius * 1.25

            -- If we're still far from the boss, preserve FORWARD progress.
            -- When forward is unsafe, lateral gaps remain valid; moving away
            -- from the boss receives a penalty but is still possible if needed.
            if Runtime.ActiveBossRoot then
                local desiredRange =
                    desiredRangeForTarget()

                local currentBossDistance =
                    horizontalDistance(
                        origin,
                        Runtime.ActiveBossRoot.Position
                    )

                if currentBossDistance
                    > desiredRange + CFG.BOSS_PROGRESS_ACTIVE_EXTRA
                then
                    local candidateBossDistance =
                        horizontalDistance(
                            candidate,
                            Runtime.ActiveBossRoot.Position
                        )

                    local progress =
                        currentBossDistance
                        - candidateBossDistance

                    if progress >= 0 then
                        score -=
                            progress
                            * CFG.BOSS_PROGRESS_REWARD
                    else
                        score +=
                            math.abs(progress)
                            * CFG.BOSS_BACKTRACK_PENALTY
                    end
                end
            end

            if Runtime.ActiveBossName == "Miyamoto Musashi"
                and Runtime.ActiveBossRoot
            then
                local candidateBossDistance =
                    horizontalDistance(
                        candidate,
                        Runtime.ActiveBossRoot.Position
                    )

                if candidateBossDistance
                    > CFG.MIYAMOTO_ARENA_LEASH
                then
                    score +=
                        150000
                        + (
                            candidateBossDistance
                            - CFG.MIYAMOTO_ARENA_LEASH
                        )
                        * CFG.MIYAMOTO_ARENA_LEASH_PENALTY
                end
            end

            if wallBlocked(origin, candidate) then
                score += 50000
            end

            -- Strongly prefer a genuine gap over a merely "less bad" strip.
            if inside == 0 then
                score -= 16000
            end

            if clearance ~= math.huge then
                score -= math.min(math.max(clearance, 0), 14) * 30

                if Runtime.ActiveBossName == "Demonic Overgrowth"
                    and clearance < CFG.OVERGROWTH_MIN_CLEARANCE
                then
                    score +=
                        (CFG.OVERGROWTH_MIN_CLEARANCE - clearance)
                        * 5500
                end

                if Runtime.ActiveBossName == "Demon Lord Azrallik"
                    and bossThreatHas("azrallikPunchSpread", activeThreats())
                    and clearance < CFG.AZRALLIK_SPREAD_MIN_CLEARANCE
                then
                    score +=
                        (CFG.AZRALLIK_SPREAD_MIN_CLEARANCE - clearance)
                        * 6500
                end
            end

            if score < bestScore then
                bestScore = score
                best = {
                    Position = candidate,
                    Radius = radius,
                    Score = score,
                    Inside = inside,
                    Clearance = clearance,
                    Label = "boss_wave_gap",
                    Source = Runtime.ActiveBossName,
                }
            end
        end
    end

    return best
end



function narrowAxisForPart(part)
    if not part then
        return nil, nil
    end

    local axisA, axisB =
        horizontalAxesForPart(part)

    local narrow =
        axisA.Half <= axisB.Half
        and axisA
        or axisB

    local dir =
        unitHorizontal(narrow.Vec)

    if dir.Magnitude <= 0.1 then
        return nil, nil
    end

    return dir, narrow.Half
end

function overgrowthFirstEdgeCandidate(
    bossWave,
    bossThreats
)
    if not Runtime.Root
        or not bossWave
        or bossWave.Boss ~= "Demonic Overgrowth"
    then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local best
    local bestScore = math.huge

    for _, meta in ipairs(bossThreats or {}) do
        if meta.RootName == "spikePrecast"
            and meta.Part
            and meta.Part.Parent
            and math.max(
                meta.Part.Size.X,
                meta.Part.Size.Z
            ) >= 40
        then
            local axisDir, half =
                narrowAxisForPart(
                    meta.Part
                )

            if axisDir and half then
                local signed =
                    horizontal(
                        origin - meta.Part.Position
                    ):Dot(axisDir)

                local edgeClearance =
                    math.abs(signed) - half

                if edgeClearance
                    <= CFG.OVERGROWTH_FIRST_EDGE_MARGIN
                then
                    for _, sign in ipairs({-1, 1}) do
                        local targetProjection =
                            sign
                            * (
                                half
                                + CFG.OVERGROWTH_FIRST_EDGE_MARGIN
                            )

                        local travel =
                            targetProjection - signed

                        local candidate =
                            origin
                            + axisDir * travel

                        local distance =
                            horizontalDistance(
                                origin,
                                candidate
                            )

                        if distance
                            <= CFG.OVERGROWTH_FIRST_EDGE_MAX_TRAVEL
                            and hasGroundAt(candidate)
                            and not movementWallHit(
                                origin,
                                candidate
                            )
                        then
                            local danger, inside, clearance =
                                pointDanger(candidate)

                            local route =
                                routeDanger(
                                    origin,
                                    candidate
                                )

                            local score =
                                danger
                                + route * 0.25
                                + distance * 90

                            if inside == 0 then
                                score -= 30000
                            else
                                score += 90000
                            end

                            if score < bestScore then
                                bestScore = score
                                best = {
                                    Position = candidate,
                                    Radius = distance,
                                    Score = score,
                                    Inside = inside,
                                    Clearance = clearance,
                                    Label = "overgrowth_first_edge",
                                    Source = "OvergrowthFirstStrip",
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end


Runtime.OvergrowthEdgeFollowCandidate = function(
    bossWave
)
    if not CFG.OVERGROWTH_EDGE_FOLLOW_ENABLED
        or not Runtime.Root
        or not bossWave
        or bossWave.Boss ~= "Demonic Overgrowth"
        or not bossWave.EdgeFollowDir
        or os.clock() >= (
            bossWave.EdgeFollowUntil
            or -math.huge
        )
    then
        return nil
    end

    local origin =
        Runtime.Root.Position

    for _, step in ipairs(
        CFG.OVERGROWTH_EDGE_FOLLOW_STEPS
    ) do
        local candidate =
            origin
            + bossWave.EdgeFollowDir * step

        if hasGroundAt(candidate)
            and not movementWallHit(
                origin,
                candidate
            )
        then
            local danger, inside, clearance =
                pointDanger(candidate)

            if inside == 0 then
                return {
                    Position = candidate,
                    Radius = step,
                    Score = danger,
                    Inside = 0,
                    Clearance = clearance,
                    Label =
                        "overgrowth_edge_follow",
                    Source =
                        "OvergrowthEdgeFollow",
                }
            end
        end
    end

    return nil
end


function overgrowthLongLineThreatsFrom(bossThreats)
    local out = {}

    for _, meta in ipairs(bossThreats or {}) do
        if meta.RootName == "overgrowthLongLineSpikes"
            and meta.Part
            and meta.Part.Parent
        then
            out[#out + 1] = meta
        end
    end

    return out
end

function overgrowthLongLinePocketCandidate(
    bossWave,
    bossThreats
)
    if not Runtime.Root
        or not bossWave
        or bossWave.Boss ~= "Demonic Overgrowth"
    then
        return nil
    end

    if bossWave.LongLinePocketLocked
        and bossWave.LongLinePocket
    then
        local _, inside, clearance =
            pointDanger(
                bossWave.LongLinePocket
            )

        local lockedPhysicalPenalty =
            wavePhysicalPenalty(
                bossWave.LongLinePocket
            )

        if inside == 0
            and hasGroundAt(
                bossWave.LongLinePocket
            )
            and lockedPhysicalPenalty
                < CFG.WAVE_PHYSICAL_HARD_PENALTY
        then
            return {
                Position = bossWave.LongLinePocket,
                Radius =
                    horizontalDistance(
                        Runtime.Root.Position,
                        bossWave.LongLinePocket
                    ),
                Score = 0,
                Inside = 0,
                Clearance = clearance,
                Label = "overgrowth_longline_pocket",
                Source = "OvergrowthLongLineLocked",
                GapWidth =
                    bossWave.LongLinePocketGapWidth,
            }
        end

        bossWave.LongLinePocketLocked = false
        bossWave.LongLinePocket = nil
    end

    local threats =
        overgrowthLongLineThreatsFrom(
            bossThreats
        )

    if #threats < 2 then
        return nil
    end

    local axisDir =
        narrowAxisForPart(
            threats[1].Part
        )

    if not axisDir then
        return nil
    end

    local bands = {}

    for _, meta in ipairs(threats) do
        local part =
            meta.Part

        local _, half =
            narrowAxisForPart(part)

        if half then
            local projection =
                horizontal(
                    part.Position
                ):Dot(axisDir)

            local duplicate = false

            for _, band in ipairs(bands) do
                if math.abs(
                    band.Projection - projection
                ) <= 1.0
                then
                    duplicate = true
                    band.Half =
                        math.max(
                            band.Half,
                            half
                        )
                    break
                end
            end

            if not duplicate then
                bands[#bands + 1] = {
                    Projection = projection,
                    Half = half,
                }
            end
        end
    end

    table.sort(bands, function(a, b)
        return a.Projection < b.Projection
    end)

    if #bands < 2 then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local playerProjection =
        horizontal(origin):Dot(axisDir)

    local best
    local bestScore = math.huge

    for i = 1, #bands - 1 do
        local left =
            bands[i]

        local right =
            bands[i + 1]

        local leftEdge =
            left.Projection + left.Half

        local rightEdge =
            right.Projection - right.Half

        local gapWidth =
            rightEdge - leftEdge

        if gapWidth
            >= CFG.OVERGROWTH_LONGLINE_MIN_GAP
        then
            local pocketProjection =
                (leftEdge + rightEdge) * 0.5

            local candidate =
                origin
                + axisDir
                * (
                    pocketProjection
                    - playerProjection
                )

            local travel =
                horizontalDistance(
                    origin,
                    candidate
                )

            if travel
                <= CFG.OVERGROWTH_LONGLINE_MAX_POCKET_TRAVEL
                and hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                local route =
                    routeDanger(
                        origin,
                        candidate
                    )

                if inside == 0
                    and (
                        clearance == math.huge
                        or clearance
                            >= CFG.OVERGROWTH_LONGLINE_MIN_CLEARANCE
                    )
                then
                    local score =
                        travel * 180
                        + route * 0.05
                        + wavePhysicalPenalty(candidate)
                        - gapWidth * 320

                    if score < bestScore then
                        bestScore = score
                        best = {
                            Position = candidate,
                            Radius = travel,
                            Score = score,
                            Inside = inside,
                            Clearance = clearance,
                            Label = "overgrowth_longline_pocket",
                            Source = "OvergrowthLongLineGap",
                            GapWidth = gapWidth,
                        }
                    end
                end
            end
        end
    end

    if best then
        bossWave.LongLinePocket =
            best.Position
        bossWave.LongLinePocketLocked =
            true
        bossWave.LongLinePocketClearance =
            best.Clearance
        bossWave.LongLinePocketGapWidth =
            best.GapWidth

        local now =
            os.clock()

        if now - Runtime.LastOvergrowthLongLineLog
            >= CFG.OVERGROWTH_LONGLINE_LOCK_LOG_COOLDOWN
        then
            Runtime.LastOvergrowthLongLineLog = now

            logKV("OVERGROWTH_LONGLINE_POCKET", {
                wave = bossWave.Id,
                position = vec(best.Position),
                distance =
                    string.format(
                        "%.2f",
                        best.Radius
                    ),
                gap =
                    string.format(
                        "%.2f",
                        best.GapWidth
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
    end

    return best
end

function overgrowthSequenceEscapeCandidate(bossWave)
    if not Runtime.Root
        or Runtime.ActiveBossName ~= "Demonic Overgrowth"
        or not bossWave
    then
        return nil
    end

    local now = os.clock()
    local hist = {}

    -- Only the narrow sequential spikePrecast strips are recorded here.
    -- Long-line arrays are deliberately handled by the generic boss-wave gap
    -- solver because they spawn as a simultaneous set, not a one-way sweep.
    for _, item in ipairs(Runtime.OvergrowthSpikeHistory) do
        if item.Time >= bossWave.Started - 0.05
            and now - item.Time <= CFG.OVERGROWTH_SEQUENCE_AGE
            and item.Part
            and item.Part.Parent
        then
            hist[#hist + 1] = item
        end
    end

    if #hist < 2 then
        return nil
    end

    table.sort(hist, function(a, b)
        return a.Time < b.Time
    end)

    -- Lock direction from the FIRST two genuinely different strips.
    -- Never recalculate from the newest pair; small strip jitter previously
    -- flipped the direction and caused first -> second -> first ping-pong.
    if not bossWave.SequenceDir then
        local first
        local second

        for i = 1, #hist - 1 do
            for j = i + 1, #hist do
                local delta =
                    horizontal(
                        hist[j].Position
                        - hist[i].Position
                    )

                if delta.Magnitude
                    >= CFG.OVERGROWTH_SEQUENCE_MIN_STEP
                then
                    first = hist[i]
                    second = hist[j]
                    break
                end
            end

            if first then break end
        end

        if not first or not second then
            return nil
        end

        local motion =
            horizontal(
                second.Position
                - first.Position
            )

        bossWave.SequenceDir = motion.Unit
        bossWave.SequenceStep = motion.Magnitude
        bossWave.SequenceOrigin = first.Position
        bossWave.SequenceLockedAt = now

        if now - Runtime.LastOvergrowthDirectionLog
            >= CFG.OVERGROWTH_DIRECTION_LOG_COOLDOWN
        then
            Runtime.LastOvergrowthDirectionLog = now

            logKV("OVERGROWTH_DIRECTION_LOCK", {
                wave = bossWave.Id,
                step = string.format(
                    "%.2f",
                    bossWave.SequenceStep
                ),
                direction = vec(bossWave.SequenceDir),
                first = vec(first.Position),
                second = vec(second.Position),
            })
        end
    end

    local sequenceDir =
        bossWave.SequenceDir

    local sequenceStep =
        bossWave.SequenceStep
        or CFG.OVERGROWTH_SEQUENCE_MIN_STEP

    if not sequenceDir then
        return nil
    end

    -- Latest strip that actually advanced in the LOCKED direction.
    local latest = hist[1]
    local latestProjection = -math.huge

    for _, item in ipairs(hist) do
        local projection =
            horizontal(
                item.Position
                - bossWave.SequenceOrigin
            ):Dot(sequenceDir)

        if projection > latestProjection then
            latestProjection = projection
            latest = item
        end
    end

    local origin =
        Runtime.Root.Position

    local relative =
        horizontal(
            origin - latest.Position
        )

    local playerAhead =
        relative:Dot(sequenceDir)

    local halfWidth = 7.0

    pcall(function()
        local axisA, axisB =
            horizontalAxesForPart(latest.Part)

        halfWidth =
            math.min(
                axisA.Half,
                axisB.Half
            )
    end)

    -- Predict the next strip and aim BEYOND it. This is the behavior the
    -- observed mechanic needs:
    --
    --     first -> second -> third
    --
    -- Once we move toward second/third, never reverse toward first.
    local nextCenter =
        latest.Position
        + sequenceDir * sequenceStep

    local targetForward =
        horizontal(
            nextCenter - origin
        ):Dot(sequenceDir)
        + halfWidth
        + CFG.OVERGROWTH_FORWARD_EXTRA

    targetForward =
        math.clamp(
            targetForward,
            CFG.OVERGROWTH_FORWARD_MIN_MOVE,
            CFG.OVERGROWTH_FORWARD_MAX_REQUIRED
        )

    local dt = 0.50

    if #hist >= 2 then
        local a = hist[#hist - 1]
        local b = hist[#hist]

        local delta =
            horizontal(
                b.Position - a.Position
            )

        if delta:Dot(sequenceDir) > 0 then
            dt =
                math.max(
                    b.Time - a.Time,
                    0.05
                )
        end
    end

    local sequenceSpeed =
        sequenceStep / math.max(dt, 0.05)

    local timeToContact = math.huge

    if playerAhead >= -halfWidth then
        timeToContact =
            math.max(
                0,
                playerAhead - halfWidth
            ) / math.max(sequenceSpeed, 1)
    end

    local baseAngle =
        math.atan2(
            sequenceDir.Z,
            sequenceDir.X
        )

    local best
    local bestScore = math.huge

    for _, radius in ipairs(CFG.OVERGROWTH_FORWARD_RADII) do
        for _, degrees in ipairs(CFG.OVERGROWTH_FORWARD_ANGLES) do
            local angle =
                baseAngle + math.rad(degrees)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local forwardDot =
                dir:Dot(sequenceDir)

            -- HARD RULE: no candidate is allowed to go backwards toward a
            -- previously fired strip.
            if forwardDot >= CFG.OVERGROWTH_FORWARD_MIN_DOT then
                local candidate =
                    origin + dir * radius

                local forwardMove =
                    horizontal(
                        candidate - origin
                    ):Dot(sequenceDir)

                if forwardMove
                    >= math.min(
                        targetForward * 0.72,
                        CFG.OVERGROWTH_FORWARD_MIN_MOVE
                    )
                    and not movementWallHit(origin, candidate)
                    and hasGroundAt(candidate)
                then
                    local danger, inside, clearance =
                        pointDanger(candidate)

                    local route =
                        routeDanger(
                            origin,
                            candidate
                        )

                    -- Predict the NEXT red strip even though it does not exist
                    -- in Workspace yet. Penalize candidates landing on it.
                    local candidateFromNext =
                        horizontal(
                            candidate - nextCenter
                        ):Dot(sequenceDir)

                    local predictedNextPenalty = 0

                    if math.abs(candidateFromNext)
                        <= halfWidth + CFG.OVERGROWTH_SEQUENCE_ESCAPE_MARGIN
                    then
                        predictedNextPenalty = 120000
                    end

                    local forwardError =
                        math.abs(
                            forwardMove
                            - targetForward
                        )

                    local score =
                        danger
                        + route * 0.38
                        + predictedNextPenalty
                        + wavePhysicalPenalty(candidate)
                        + enemyPenalty(candidate) * 0.20
                        + radius * 8
                        + forwardError * 180

                    if inside > 0 then
                        score += 100000
                    end

                    -- Prefer the first safe point beyond the predicted strip,
                    -- not the farthest point available.
                    if forwardMove >= targetForward then
                        score -= 3200
                    else
                        score +=
                            (targetForward - forwardMove)
                            * 420
                    end

                    if clearance ~= math.huge then
                        score -=
                            math.min(
                                math.max(clearance, 0),
                                24
                            ) * 70

                        if clearance
                            < CFG.OVERGROWTH_FORWARD_MIN_CLEARANCE
                        then
                            score +=
                                (
                                    CFG.OVERGROWTH_FORWARD_MIN_CLEARANCE
                                    - clearance
                                ) * 22000
                        end
                    end

                    if score < bestScore then
                        bestScore = score

                        best = {
                            Position = candidate,
                            Radius = radius,
                            Score = score,
                            Inside = inside,
                            Clearance = clearance,
                            Label = "overgrowth_sequence_forward",
                            Source = "OvergrowthSequence",
                            TimeToContact = timeToContact,
                            SequenceSpeed = sequenceSpeed,
                            ForwardMove = forwardMove,
                            Step = sequenceStep,
                        }
                    end
                end
            end
        end
    end

    if best
        and now - Runtime.LastOvergrowthDirectionLog
            >= CFG.OVERGROWTH_DIRECTION_LOG_COOLDOWN
    then
        Runtime.LastOvergrowthDirectionLog = now

        logKV("OVERGROWTH_FORWARD_PLAN", {
            wave = bossWave.Id,
            step = string.format("%.2f", sequenceStep),
            move = string.format("%.2f", best.ForwardMove or 0),
            radius = string.format("%.1f", best.Radius),
            clearance = string.format("%.1f", best.Clearance or 0),
        })
    end

    return best
end

moveTo = nil

function azrallikBeamThreatsFrom(bossThreats)
    local out = {}

    for _, meta in ipairs(bossThreats or {}) do
        if meta
            and meta.RootName == "horizontalBeam"
            and meta.Part
            and meta.Part.Parent
        then
            out[#out + 1] = meta
        end
    end

    return out
end

function beamNarrowAxis(part)
    if not part then
        return nil, nil
    end

    local axisA, axisB =
        horizontalAxesForPart(part)

    local narrow =
        axisA.Half <= axisB.Half
        and axisA
        or axisB

    local dir =
        unitHorizontal(narrow.Vec)

    if dir.Magnitude <= 0.1 then
        return nil, nil
    end

    return dir, narrow.Half
end

function uniqueBeamBands(beamThreats, axisDir)
    local bands = {}

    for _, meta in ipairs(beamThreats) do
        local part = meta.Part

        if part and part.Parent then
            local narrowDir, half =
                beamNarrowAxis(part)

            if narrowDir then
                if narrowDir:Dot(axisDir) < 0 then
                    narrowDir = -narrowDir
                end

                local projection =
                    horizontal(part.Position):Dot(axisDir)

                local duplicate = false

                for _, band in ipairs(bands) do
                    if math.abs(
                        band.Projection - projection
                    ) <= 1.0
                    then
                        duplicate = true

                        if meta.Kind == "ActiveHitbox" then
                            band.Part = part
                            band.Half = math.max(
                                band.Half,
                                half or 0
                            )
                        end

                        break
                    end
                end

                if not duplicate then
                    bands[#bands + 1] = {
                        Projection = projection,
                        Half = half or 8.2,
                        Part = part,
                    }
                end
            end
        end
    end

    table.sort(bands, function(a, b)
        return a.Projection < b.Projection
    end)

    return bands
end

function medianNumber(values)
    if #values == 0 then
        return nil
    end

    table.sort(values)

    local mid =
        math.floor((#values + 1) * 0.5)

    if #values % 2 == 1 then
        return values[mid]
    end

    return
        (values[mid] + values[mid + 1])
        * 0.5
end

function beamLatticeMetrics(
    beamThreats,
    axisDir
)
    local bands =
        uniqueBeamBands(
            beamThreats,
            axisDir
        )

    if #bands < 2 then
        return nil
    end

    local steps = {}
    local halfWidths = {}

    for _, band in ipairs(bands) do
        halfWidths[#halfWidths + 1] =
            band.Half
    end

    for i = 1, #bands - 1 do
        local step =
            bands[i + 1].Projection
            - bands[i].Projection

        -- Reject duplicate/junk distances and very large unrelated gaps.
        if step >= 8 and step <= 60 then
            steps[#steps + 1] = step
        end
    end

    local spacing =
        medianNumber(steps)

    local halfWidth =
        medianNumber(halfWidths)

    if not spacing or not halfWidth then
        return nil
    end

    local gapWidth =
        spacing - halfWidth * 2

    if gapWidth
        < CFG.AZRALLIK_BEAM_MIN_GAP_WIDTH
    then
        return nil
    end

    return {
        Bands = bands,
        Axis = axisDir,
        Base = bands[1].Projection,
        Spacing = spacing,
        HalfWidth = halfWidth,
        GapWidth = gapWidth,
    }
end

function azrallikLatticePocketCandidate(
    bossWave,
    beamThreats
)
    if not Runtime.Root
        or not bossWave
        or #beamThreats < 2
    then
        return nil
    end

    local axisDir =
        beamNarrowAxis(
            beamThreats[1].Part
        )

    if not axisDir then
        return nil
    end

    local lattice =
        beamLatticeMetrics(
            beamThreats,
            axisDir
        )

    if not lattice then
        return nil
    end

    bossWave.BeamLatticeSpacing =
        lattice.Spacing
    bossWave.BeamLatticeHalfWidth =
        lattice.HalfWidth

    local origin =
        Runtime.Root.Position

    local playerProjection =
        horizontal(origin):Dot(axisDir)

    -- Gaps repeat halfway between every pair of beam centers. Extend that
    -- measured lattice in BOTH directions, including strips not spawned yet.
    -- This means the nearest safe lane should normally be <= spacing/2 away
    -- (~13 studs in the observed ~26-stud pattern), never 100+ studs away.
    local rawIndex =
        (playerProjection - lattice.Base)
        / lattice.Spacing
        - 0.5

    local nearestIndex =
        math.floor(rawIndex + 0.5)

    local lateral =
        Vector3.new(
            -axisDir.Z,
            0,
            axisDir.X
        )

    local best
    local bestScore = math.huge

    for k = nearestIndex - 2, nearestIndex + 2 do
        local pocketProjection =
            lattice.Base
            + (k + 0.5)
            * lattice.Spacing

        local axisOffset =
            pocketProjection
            - playerProjection

        if math.abs(axisOffset)
            <= CFG.AZRALLIK_BEAM_MAX_POCKET_TRAVEL
        then
            for _, side in ipairs(
                CFG.AZRALLIK_BEAM_AURA_LATERAL
            ) do
                local candidate =
                    origin
                    + axisDir * axisOffset
                    + lateral * side

                if hasGroundAt(candidate)
                    and not movementWallHit(
                        origin,
                        candidate
                    )
                then
                    local danger, inside, clearance =
                        pointDanger(candidate)

                    if inside == 0
                        and (
                            clearance == math.huge
                            or clearance
                                >= CFG.AZRALLIK_BEAM_MIN_CLEARANCE
                        )
                    then
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
                            travel * 180
                            + route * 0.05
                            + math.abs(side) * 35
                            - lattice.GapWidth * 300

                        if travel
                            <= CFG.AZRALLIK_BEAM_HOLD_DISTANCE
                        then
                            score -= 60000
                        end

                        if score < bestScore then
                            bestScore = score

                            best = {
                                Position = candidate,
                                Radius = travel,
                                Score = score,
                                Inside = inside,
                                Clearance = clearance,
                                Label = "azrallik_beam_pocket",
                                Source = "HorizontalBeamLattice",
                                PocketAxis = axisDir,
                                GapWidth = lattice.GapWidth,
                                PocketProjection = pocketProjection,
                                LatticeSpacing = lattice.Spacing,
                            }
                        end
                    end
                end
            end
        end
    end

    return best
end

function azrallikAuraPocketCandidate(
    bossWave,
    beamThreats
)
    if not Runtime.Root
        or #beamThreats < 2
    then
        return nil
    end

    local axisDir =
        beamNarrowAxis(
            beamThreats[1].Part
        )

    if not axisDir then
        return nil
    end

    local lateral =
        Vector3.new(
            -axisDir.Z,
            0,
            axisDir.X
        )

    local origin =
        Runtime.Root.Position

    local best
    local bestScore = math.huge

    for offset =
        -CFG.AZRALLIK_BEAM_AURA_RADIUS,
        CFG.AZRALLIK_BEAM_AURA_RADIUS,
        CFG.AZRALLIK_BEAM_AURA_STEP
    do
        for _, side in ipairs(
            CFG.AZRALLIK_BEAM_AURA_LATERAL
        ) do
            local candidate =
                origin
                + axisDir * offset
                + lateral * side

            local travel =
                horizontalDistance(
                    origin,
                    candidate
                )

            if travel
                <= CFG.AZRALLIK_BEAM_MAX_POCKET_TRAVEL
                and hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                if inside == 0
                    and (
                        clearance == math.huge
                        or clearance
                            >= CFG.AZRALLIK_BEAM_MIN_CLEARANCE
                    )
                then
                    local route =
                        routeDanger(
                            origin,
                            candidate
                        )

                    local score =
                        travel * 190
                        + route * 0.08
                        + math.abs(side) * 35

                    if travel
                        <= CFG.AZRALLIK_BEAM_HOLD_DISTANCE
                    then
                        score -= 45000
                    end

                    if score < bestScore then
                        bestScore = score
                        best = {
                            Position = candidate,
                            Radius = travel,
                            Score = score,
                            Inside = inside,
                            Clearance = clearance,
                            Label = "azrallik_beam_pocket",
                            Source = "HorizontalBeamAuraLocal",
                            PocketAxis = axisDir,
                            GapWidth = nil,
                        }
                    end
                end
            end
        end
    end

    return best
end

function azrallikEarlyBeamCandidate(
    bossWave,
    bossThreats
)
    if not Runtime.Root
        or not bossWave
    then
        return nil
    end

    local beamThreats =
        azrallikBeamThreatsFrom(
            bossThreats
        )

    if #beamThreats == 0 then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local nearest
    local nearestDistance = math.huge
    local nearestAxis
    local nearestHalf

    for _, meta in ipairs(beamThreats) do
        local part = meta.Part

        if part and part.Parent then
            local axisDir, half =
                beamNarrowAxis(part)

            if axisDir and half then
                local signed =
                    horizontal(
                        origin - part.Position
                    ):Dot(axisDir)

                local edgeDistance =
                    math.abs(
                        math.abs(signed) - half
                    )

                if edgeDistance < nearestDistance then
                    nearestDistance = edgeDistance
                    nearest = part
                    nearestAxis = axisDir
                    nearestHalf = half
                end
            end
        end
    end

    if not nearest
        or not nearestAxis
        or not nearestHalf
    then
        return nil
    end

    local signed =
        horizontal(
            origin - nearest.Position
        ):Dot(nearestAxis)

    local clearance =
        math.abs(signed) - nearestHalf

    -- Already outside the first strip with margin: HOLD this known-safe point
    -- for the few tenths of a second until strip #2 gives us lattice spacing.
    if clearance >= CFG.AZRALLIK_BEAM_EARLY_MARGIN then
        local _, inside, pointClearance =
            pointDanger(origin)

        return {
            Position = origin,
            Radius = 0,
            Score = 0,
            Inside = inside,
            Clearance = pointClearance,
            Label = "azrallik_beam_early_hold",
            Source = "AzrallikEarlyBeamHold",
            PocketAxis = nearestAxis,
        }
    end

    local sign =
        signed >= 0
        and 1
        or -1

    local targetProjection =
        sign
        * (
            nearestHalf
            + CFG.AZRALLIK_BEAM_EARLY_MARGIN
        )

    local travel =
        targetProjection - signed

    local candidate =
        origin
        + nearestAxis * travel

    local distance =
        horizontalDistance(
            origin,
            candidate
        )

    if distance
        <= CFG.AZRALLIK_BEAM_EARLY_MAX_TRAVEL
        and hasGroundAt(candidate)
        and not movementWallHit(
            origin,
            candidate
        )
    then
        local _, inside, pointClearance =
            pointDanger(candidate)

        if inside == 0 then
            local now = os.clock()

            if now - Runtime.LastAzrallikEarlyBeamLog
                >= CFG.AZRALLIK_BEAM_EARLY_LOG_COOLDOWN
            then
                Runtime.LastAzrallikEarlyBeamLog = now

                logKV("AZRALLIK_EARLY_BEAM_EDGE", {
                    wave = bossWave.Id,
                    distance =
                        string.format(
                            "%.2f",
                            distance
                        ),
                    clearance =
                        pointClearance == math.huge
                        and "inf"
                        or string.format(
                            "%.2f",
                            pointClearance
                        ),
                })
            end

            return {
                Position = candidate,
                Radius = distance,
                Score = 0,
                Inside = 0,
                Clearance = pointClearance,
                Label = "azrallik_beam_early_edge",
                Source = "AzrallikEarlyBeamEdge",
                PocketAxis = nearestAxis,
            }
        end
    end

    -- Last safe fallback: do not use the generic boss planner while the beam
    -- mechanic is active. Hold current position until the lattice resolves.
    local _, inside, pointClearance =
        pointDanger(origin)

    return {
        Position = origin,
        Radius = 0,
        Score = 0,
        Inside = inside,
        Clearance = pointClearance,
        Label = "azrallik_beam_early_hold",
        Source = "AzrallikEarlyBeamFallback",
        PocketAxis = nearestAxis,
    }
end


function horizontalSweepEscapeCandidate(
    bossWave,
    bossThreats
)
    if not CFG.AZRALLIK_BEAM_POCKET_ENABLED
        or not Runtime.Root
        or not bossWave
    then
        return nil
    end

    local beamThreats =
        azrallikBeamThreatsFrom(
            bossThreats
        )

    if #beamThreats < 2 then
        return nil
    end

    local now = os.clock()

    -- Once a pocket is locked, keep it while it remains safe. The key V8.1
    -- difference is that the pocket comes from the repeating beam lattice,
    -- so it is local instead of a distant gap between already-spawned strips.
    if bossWave.BeamPocketLocked
        and bossWave.BeamPocket
    then
        local _, inside, clearance =
            pointDanger(
                bossWave.BeamPocket
            )

        if inside == 0
            and (
                clearance == math.huge
                or clearance
                    >= CFG.AZRALLIK_BEAM_MIN_CLEARANCE
            )
            and hasGroundAt(
                bossWave.BeamPocket
            )
        then
            return {
                Position = bossWave.BeamPocket,
                Radius =
                    horizontalDistance(
                        Runtime.Root.Position,
                        bossWave.BeamPocket
                    ),
                Score = 0,
                Inside = 0,
                Clearance = clearance,
                Label = "azrallik_beam_pocket",
                Source = "HorizontalBeamPocketLocked",
                PocketAxis = bossWave.BeamPocketAxis,
                GapWidth = bossWave.BeamPocketGapWidth,
                LatticeSpacing =
                    bossWave.BeamLatticeSpacing,
            }
        end

        bossWave.BeamPocketLocked = false
        bossWave.BeamPocketReached = false
        bossWave.BeamPocket = nil

        logKV("AZRALLIK_POCKET_RELEASE", {
            wave = bossWave.Id,
            reason = "pocket_became_dangerous",
            inside = inside,
            clearance =
                clearance == math.huge
                and "inf"
                or string.format("%.2f", clearance),
        })
    end

    if now - (bossWave.BeamPocketLastPlanAt or -math.huge)
        < CFG.AZRALLIK_BEAM_RESCAN_INTERVAL
    then
        return nil
    end

    bossWave.BeamPocketLastPlanAt = now

    local plan =
        azrallikLatticePocketCandidate(
            bossWave,
            beamThreats
        )

    if not plan then
        plan =
            azrallikAuraPocketCandidate(
                bossWave,
                beamThreats
            )
    end

    if plan then
        bossWave.BeamPocket =
            plan.Position
        bossWave.BeamPocketAxis =
            plan.PocketAxis
        bossWave.BeamPocketLocked = true
        bossWave.BeamPocketReached = false
        bossWave.BeamPocketClearance =
            plan.Clearance
        bossWave.BeamPocketGapWidth =
            plan.GapWidth

        if now - Runtime.LastAzrallikPocketLog
            >= CFG.AZRALLIK_BEAM_LOCK_LOG_COOLDOWN
        then
            Runtime.LastAzrallikPocketLog = now

            logKV("AZRALLIK_POCKET_LOCK", {
                wave = bossWave.Id,
                position = vec(plan.Position),
                distance =
                    string.format(
                        "%.2f",
                        plan.Radius
                    ),
                clearance =
                    plan.Clearance == math.huge
                    and "inf"
                    or string.format(
                        "%.2f",
                        plan.Clearance or 0
                    ),
                gap =
                    plan.GapWidth
                    and string.format(
                        "%.2f",
                        plan.GapWidth
                    )
                    or "aura",
                spacing =
                    plan.LatticeSpacing
                    and string.format(
                        "%.2f",
                        plan.LatticeSpacing
                    )
                    or "n/a",
                source = plan.Source,
            })
        end
    end

    return plan
end

function exactThreatRouteSafe(
    fromPosition,
    toPosition
)
    if not fromPosition or not toPosition then
        return false
    end

    local delta = toPosition - fromPosition
    local distance = horizontal(delta).Magnitude

    if distance <= 0.1 then
        local _, inside = pointDanger(toPosition)
        return inside == 0
    end

    local samples =
        math.max(
            1,
            math.ceil(
                distance
                / CFG.SAFE_ROUTE_SAMPLE_STEP
            )
        )

    for i = 1, samples do
        local point =
            fromPosition
            + delta * (i / samples)

        local _, inside =
            pointDanger(point)

        if inside > 0 then
            return false
        end
    end

    return true
end

function azrallikPhaseTargetRoot()
    if Runtime.TargetRoot
        and Runtime.Target
        and Runtime.Target.Name == "Azrallik's Heart"
    then
        return Runtime.TargetRoot
    end

    if Runtime.ActiveBossModel then
        return modelRoot(
            Runtime.ActiveBossModel
        )
    end

    return Runtime.TargetRoot
end


function trySlideAzrallikPocketLane(
    bossWave
)
    if not Runtime.Root
        or not Runtime.ActiveBossModel
        or not bossWave
        or not bossWave.BeamPocketAxis
    then
        return false
    end

    local now =
        os.clock()

    if now - (bossWave.BeamPocketLastSlideAt or -math.huge)
        < CFG.AZRALLIK_BEAM_LANE_SLIDE_INTERVAL
    then
        return false
    end

    local bossRoot =
        azrallikPhaseTargetRoot()

    if not bossRoot then
        return false
    end

    local narrowAxis =
        bossWave.BeamPocketAxis

    local laneAxis =
        Vector3.new(
            -narrowAxis.Z,
            0,
            narrowAxis.X
        )

    local origin =
        Runtime.Root.Position

    local towardBoss =
        horizontal(
            bossRoot.Position - origin
        )

    local along =
        towardBoss:Dot(laneAxis)

    if math.abs(along)
        < CFG.AZRALLIK_BEAM_LANE_SLIDE_MIN
    then
        return false
    end

    local direction =
        along >= 0
        and laneAxis
        or -laneAxis

    local step =
        math.min(
            math.abs(along),
            CFG.AZRALLIK_BEAM_LANE_SLIDE_STEP
        )

    if step
        < CFG.AZRALLIK_BEAM_LANE_SLIDE_MIN
    then
        return false
    end

    local candidate =
        origin + direction * step

    local safeDestination =
        safeMovementDestination(
            candidate,
            origin
        )

    if not safeDestination
        or movementWallHit(
            origin,
            candidate
        )
    then
        return false
    end

    local _, inside, clearance =
        pointDanger(candidate)

    local hardRouteSafe =
        exactThreatRouteSafe(
            origin,
            candidate
        )

    if inside > 0
        or not hardRouteSafe
        or (
            clearance ~= math.huge
            and clearance
                < CFG.AZRALLIK_BEAM_MIN_CLEARANCE
        )
    then
        return false
    end

    bossWave.BeamPocketLastSlideAt = now
    bossWave.BeamPocket = candidate
    bossWave.BeamPocketReached = false

    moveTo(
        candidate,
        "AZRALLIK_LANE_SLIDE"
    )

    if now - Runtime.LastAzrallikLaneSlideLog
        >= CFG.AZRALLIK_BEAM_LANE_SLIDE_LOG_COOLDOWN
    then
        Runtime.LastAzrallikLaneSlideLog = now

        logKV("AZRALLIK_LANE_SLIDE", {
            wave = bossWave.Id,
            step =
                string.format(
                    "%.1f",
                    step
                ),
            boss_distance =
                string.format(
                    "%.1f",
                    horizontalDistance(
                        origin,
                        bossRoot.Position
                    )
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

    return true
end

function tryAdvanceAzrallikPocket(
    bossWave
)
    if not Runtime.Root
        or not Runtime.ActiveBossModel
        or not bossWave
    then
        return false
    end

    local now = os.clock()

    if now - Runtime.LastHorizontalBeamSpawn
        < CFG.AZRALLIK_BEAM_SPAWN_QUIET
    then
        return false
    end

    if now - (bossWave.BeamPocketLastAdvanceAt or -math.huge)
        < CFG.AZRALLIK_BEAM_ADVANCE_INTERVAL
    then
        return false
    end

    local bossRoot =
        azrallikPhaseTargetRoot()

    if not bossRoot then
        return false
    end

    local origin =
        Runtime.Root.Position

    local toward =
        unitHorizontal(
            bossRoot.Position - origin
        )

    if toward.Magnitude <= 0.1 then
        return false
    end

    bossWave.BeamPocketLastAdvanceAt = now

    for _, step in ipairs({
        CFG.AZRALLIK_BEAM_ADVANCE_STEP,
        8.0,
        6.0,
        4.0,
        CFG.AZRALLIK_BEAM_ADVANCE_MIN_STEP,
    }) do
        local candidate =
            origin + toward * step

        local safeGround =
            safeMovementDestination(
                candidate,
                origin
            )

        if safeGround
            and not movementWallHit(
                origin,
                candidate
            )
        then
            local _, inside, clearance =
                pointDanger(candidate)

            local hardRouteSafe =
                exactThreatRouteSafe(
                    origin,
                    candidate
                )

            if inside == 0
                and hardRouteSafe
                and (
                    clearance == math.huge
                    or clearance
                        >= CFG.AZRALLIK_BEAM_MIN_CLEARANCE
                )
            then
                bossWave.BeamPocket =
                    candidate
                bossWave.BeamPocketLocked =
                    true
                bossWave.BeamPocketReached =
                    false

                moveTo(
                    candidate,
                    "AZRALLIK_POCKET_ADVANCE"
                )

                if now - Runtime.LastAzrallikAdvanceLog
                    >= CFG.AZRALLIK_BEAM_ADVANCE_LOG_COOLDOWN
                then
                    Runtime.LastAzrallikAdvanceLog = now

                    logKV("AZRALLIK_POCKET_ADVANCE", {
                        wave = bossWave.Id,
                        step =
                            string.format(
                                "%.1f",
                                step
                            ),
                        boss_distance =
                            string.format(
                                "%.1f",
                                horizontalDistance(
                                    origin,
                                    bossRoot.Position
                                )
                            ),
                        quiet =
                            string.format(
                                "%.2f",
                                now
                                - Runtime.LastHorizontalBeamSpawn
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

                return true
            end
        end
    end

    return false
end


function holdAzrallikBeamPocket(
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
        > CFG.AZRALLIK_BEAM_HOLD_DISTANCE
    then
        moveTo(
            plan.Position,
            "AZRALLIK_BEAM_POCKET"
        )

        return true
    end

    -- While beams are active, slide along the already-safe lane toward the
    -- boss. This preserves the safe narrow-axis pocket and never crosses the
    -- neighboring beam strip.
    if trySlideAzrallikPocketLane(
        bossWave
    ) then
        return true
    end

    -- Once strip generation has gone quiet, begin consuming the old-beam tail
    -- in short safe cross-lane MoveTo steps. If even a 3-stud route is unsafe,
    -- stay in the pocket.
    if tryAdvanceAzrallikPocket(
        bossWave
    ) then
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
        Runtime.Root.AssemblyLinearVelocity =
            Vector3.zero
    end)

    Runtime.MovementOwner =
        "AZRALLIK_POCKET_HOLD"

    if not bossWave.BeamPocketReached then
        bossWave.BeamPocketReached = true

        logKV("AZRALLIK_POCKET_HOLD", {
            wave = bossWave.Id,
            position =
                vec(Runtime.Root.Position),
            clearance =
                plan.Clearance == math.huge
                and "inf"
                or string.format(
                    "%.2f",
                    plan.Clearance or 0
                ),
        })
    end

    return true
end


