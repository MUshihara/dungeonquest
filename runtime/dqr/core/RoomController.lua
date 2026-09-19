-- DQR modular runtime: core/RoomController.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Room navigation
-- ============================================================

function spawnCentroid(room)
    if not room then return nil end

    local folder =
        room:FindFirstChild("enemyFolder")

    if not folder then return nil end

    local positions = {}

    for _,inst in ipairs(folder:GetChildren()) do
        if inst.Name == "spawn"
            and inst:IsA("BasePart")
        then
            positions[#positions+1] = inst.Position
        end
    end

    if #positions == 0 then
        return nil
    end

    local sum = Vector3.zero

    for _,p in ipairs(positions) do
        sum += p
    end

    return sum/#positions
end

function nextRoomWaypoint()
    local dungeon = workspace:FindFirstChild("dungeon")
    if not dungeon then return nil end

    local nextIndex =
        math.max(Runtime.CurrentRoomIndex,0) + 1

    local room =
        dungeon:FindFirstChild(
            "room" .. tostring(nextIndex)
        )

    if room then
        local c = spawnCentroid(room)
        if c then return c,nextIndex end
    end

    -- Underworld recorded room1...room9 then bossRoom.
    if Runtime.CurrentRoomIndex >= 9 then
        local boss =
            dungeon:FindFirstChild("bossRoom")

        if boss then
            local c = spawnCentroid(boss)

            if c then
                return c,999
            end

            local p =
                boss.PrimaryPart
                or boss:FindFirstChildWhichIsA(
                    "BasePart",
                    true
                )

            if p then
                return p.Position,999
            end
        end
    end

    return nil
end

function computePath(destination)
    if not Runtime.Root then
        return false
    end

    local path =
        PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            AgentCanClimb = true,
            WaypointSpacing = 6,
        })

    local ok =
        pcall(
            path.ComputeAsync,
            path,
            Runtime.Root.Position,
            destination
        )

    if not ok
        or path.Status
            ~= Enum.PathStatus.Success
    then
        return false
    end

    Runtime.PathWaypoints =
        path:GetWaypoints()

    Runtime.PathIndex = 2
    Runtime.PathDestination = destination

    return #Runtime.PathWaypoints >= 2
end

stopTransitTween = function(reason)
    local hadTransit =
        Runtime.TransitTween ~= nil
        or Runtime.TransitTweenTarget ~= nil
        or Runtime.TransitTweenDone == false

    if Runtime.TransitTweenConn then
        pcall(function()
            Runtime.TransitTweenConn:Disconnect()
        end)
        Runtime.TransitTweenConn = nil
    end

    if Runtime.TransitTween then
        pcall(function()
            Runtime.TransitTween:Cancel()
        end)
        Runtime.TransitTween = nil
    end

    if Runtime.Humanoid
        and Runtime.TransitAutoRotate ~= nil
    then
        pcall(function()
            Runtime.Humanoid.AutoRotate =
                Runtime.TransitAutoRotate
        end)
    end

    Runtime.TransitAutoRotate = nil
    Runtime.TransitTweenTarget = nil
    Runtime.TransitTweenDone = true

    if Runtime.MovementOwner == "TRANSIT"
        or Runtime.MovementOwner == "TRANSIT_SETTLE"
    then
        Runtime.MovementOwner = "NONE"
    end

    if reason and hadTransit then
        log("TRANSIT_TWEEN_STOP", tostring(reason))
    end
end

function startTransitTween(position)
    if not CFG.TRANSIT_TWEEN_ENABLED
        or not Runtime.Root
        or not Runtime.Humanoid
        or not position
    then
        return false
    end

    local now =
        os.clock()

    if now < Runtime.TransitBackoffUntil then
        return false
    end

    if Runtime.TransitDisabledRoom ~= nil
        and Runtime.TransitDisabledRoom
            == Runtime.CurrentRoomIndex
    then
        return false
    end

    local safe, rejectReason =
        safeMovementDestination(
            position,
            Runtime.Root.Position
        )

    if not safe then
        logKV("TRANSIT_REJECT", {
            reject = tostring(rejectReason),
            requested = vec(position),
            current = vec(Runtime.Root.Position),
        })

        Runtime.ApproachWaypoints = nil
        Runtime.PathWaypoints = nil
        return false
    end

    stopTransitTween(nil)

    local here =
        Runtime.Root.Position

    local distance =
        horizontalDistance(
            here,
            position
        )

    if distance <= 1.0 then
        Runtime.TransitTweenDone = true
        return true
    end

    local actualSpeed =
        math.min(
            CFG.TRANSIT_TWEEN_SPEED,
            CFG.TRANSIT_TWEEN_SAFE_CAP
        )

    if CFG.TRANSIT_TWEEN_SPEED
        > CFG.TRANSIT_TWEEN_SAFE_CAP
    then
        logKV("TRANSIT_SPEED_CLAMP", {
            requested = CFG.TRANSIT_TWEEN_SPEED,
            actual = actualSpeed,
        })
    end

    local duration =
        math.clamp(
            distance / actualSpeed,
            CFG.TRANSIT_TWEEN_MIN_DURATION,
            CFG.TRANSIT_TWEEN_MAX_DURATION
        )

    local flatTarget =
        Vector3.new(
            position.X,
            here.Y,
            position.Z
        )

    local rotation =
        Runtime.Root.CFrame
        - Runtime.Root.CFrame.Position

    if horizontalDistance(
        here,
        flatTarget
    ) > 0.5 then
        rotation =
            CFrame.lookAt(
                Vector3.zero,
                unitHorizontal(
                    flatTarget - here
                )
            )
    end

    local goal =
        CFrame.new(position)
        * rotation.Rotation

    -- Clear stale Humanoid MoveTo before transit owns movement.
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

    Runtime.TransitAutoRotate =
        Runtime.Humanoid.AutoRotate
    Runtime.Humanoid.AutoRotate = false

    Runtime.TransitGeneration += 1

    local generation =
        Runtime.TransitGeneration

    Runtime.TransitStartPosition = here
    Runtime.TransitExpectedPosition = position
    Runtime.TransitTweenDone = false
    Runtime.TransitTweenTarget = position
    Runtime.MovementOwner = "TRANSIT"

    local tween =
        TweenService:Create(
            Runtime.Root,
            TweenInfo.new(
                duration,
                Enum.EasingStyle.Linear,
                Enum.EasingDirection.Out
            ),
            {
                CFrame = goal,
            }
        )

    Runtime.TransitTween = tween

    Runtime.TransitTweenConn =
        tween.Completed:Connect(function(state)
            if generation
                ~= Runtime.TransitGeneration
            then
                return
            end

            Runtime.TransitTween = nil
            Runtime.TransitTweenTarget = nil

            if state
                ~= Enum.PlaybackState.Completed
            then
                Runtime.TransitTweenDone = true
                Runtime.MovementOwner = "NONE"
                return
            end

            Runtime.TransitTweenDone = true
            Runtime.MovementOwner =
                "TRANSIT_SETTLE"
            Runtime.TransitSettleUntil =
                os.clock()
                + CFG.TRANSIT_SETTLE_TIME

            if Runtime.Humanoid
                and Runtime.TransitAutoRotate
                    ~= nil
            then
                Runtime.Humanoid.AutoRotate =
                    Runtime.TransitAutoRotate
            end

            Runtime.TransitAutoRotate = nil

            -- Clear stale MoveTo again at the completed point.
            pcall(function()
                Runtime.Root.AssemblyLinearVelocity =
                    Vector3.zero
                Runtime.Humanoid:MoveTo(
                    Runtime.Root.Position
                )
                Runtime.Humanoid:Move(
                    Vector3.zero,
                    false
                )
            end)

            local expected =
                Runtime.TransitExpectedPosition
            local started =
                Runtime.TransitStartPosition

            logKV("TRANSIT_COMPLETE", {
                expected =
                    expected and vec(expected) or "nil",
                actual =
                    vec(Runtime.Root.Position),
            })

            task.delay(
                CFG.TRANSIT_SETTLE_TIME,
                function()
                    if not Runtime.Alive
                        or generation
                            ~= Runtime.TransitGeneration
                        or not Runtime.Root
                    then
                        return
                    end

                    local actual =
                        Runtime.Root.Position

                    local drift =
                        expected
                        and horizontalDistance(
                            actual,
                            expected
                        )
                        or 0

                    local towardStart = false

                    if expected and started then
                        towardStart =
                            horizontalDistance(
                                actual,
                                started
                            )
                            < horizontalDistance(
                                expected,
                                started
                            ) - 2
                    end

                    if drift
                        >= CFG.TRANSIT_SNAPBACK_DISTANCE
                        and towardStart
                    then
                        local room =
                            Runtime.CurrentRoomIndex

                        if Runtime.TransitSnapbackRoom
                            ~= room
                        then
                            Runtime.TransitSnapbackRoom = room
                            Runtime.TransitSnapbackCount = 0
                        end

                        Runtime.TransitSnapbackCount += 1
                        Runtime.TransitBackoffUntil =
                            os.clock()
                            + CFG.TRANSIT_SNAPBACK_BACKOFF

                        if Runtime.TransitSnapbackCount
                            >= CFG.TRANSIT_SNAPBACK_ROOM_LIMIT
                        then
                            Runtime.TransitDisabledRoom =
                                room
                        end

                        Runtime.ApproachWaypoints = nil
                        Runtime.PathWaypoints = nil

                        logKV("TRANSIT_SNAPBACK", {
                            drift =
                                string.format("%.1f", drift),
                            room = tostring(room),
                            count =
                                Runtime.TransitSnapbackCount,
                            disabled_room =
                                tostring(
                                    Runtime.TransitDisabledRoom
                                ),
                        })
                    else
                        logKV("TRANSIT_STABLE", {
                            drift =
                                string.format("%.1f", drift),
                        })
                    end

                    if Runtime.MovementOwner
                        == "TRANSIT_SETTLE"
                    then
                        Runtime.MovementOwner = "NONE"
                    end
                end
            )
        end)

    logKV("TRANSIT_TWEEN", {
        studs = string.format("%.1f", distance),
        duration = string.format("%.2f", duration),
        speed = string.format("%.1f", actualSpeed),
    })

    tween:Play()

    return true
end


function isDungeonGatePart(inst)
    if not inst then
        return false
    end

    local cur = inst

    for _ = 1, 5 do
        if not cur then break end

        local lower =
            string.lower(cur.Name)

        if lower == "door"
            or lower:find("barrier", 1, true)
        then
            return true
        end

        cur = cur.Parent
    end

    return false
end

function gateInDirection(destination)
    if not Runtime.Root or not destination then
        return nil
    end

    local hit =
        staticObstacleRay(
            Runtime.Root.Position,
            destination,
            28
        )

    if hit and isDungeonGatePart(hit.Instance) then
        return hit
    end

    return nil
end

function selectTransitWaypoint(waypoints, startIndex, maxDistance)
    if not Runtime.Root or not waypoints then
        return nil, nil
    end

    local origin = Runtime.Root.Position
    local best
    local bestIndex

    for i = startIndex, #waypoints do
        local waypoint = waypoints[i]

        if waypoint.Action == Enum.PathWaypointAction.Jump then
            break
        end

        local distance =
            horizontalDistance(
                origin,
                waypoint.Position
            )

        if distance > maxDistance then
            break
        end

        local safeWaypoint =
            safeMovementDestination(
                waypoint.Position,
                origin
            )

        if distance >= 2
            and safeWaypoint
            and not movementWallHit(
                origin,
                waypoint.Position
            )
        then
            best = waypoint
            bestIndex = i
        else
            break
        end
    end

    return best, bestIndex
end

function transitCombatShouldStop()
    if activeThreatCount() > 0 then
        return true
    end

    if Runtime.TargetRoot
        and Runtime.TargetHumanoid
        and Runtime.TargetHumanoid.Health > 0
        and Runtime.Root
    then
        local distance =
            horizontalDistance(
                Runtime.Root.Position,
                Runtime.TargetRoot.Position
            )

        if distance <= CFG.TRANSIT_COMBAT_STOP_DISTANCE then
            return true
        end

        local physical, physicalDist =
            nearestPhysicalEnemy(
                Runtime.Root.Position
            )

        if physical and physicalDist <= 30 then
            return true
        end
    end

    return false
end


function combatTransitTweenThink()
    if Runtime.MovementOwner == "TRANSIT_SETTLE"
        and os.clock() < Runtime.TransitSettleUntil
    then
        return true
    end

    if os.clock() < Runtime.TransitBackoffUntil then
        return false
    end

    if Runtime.TransitDisabledRoom ~= nil
        and Runtime.TransitDisabledRoom
            == Runtime.CurrentRoomIndex
    then
        return false
    end

    if not CFG.TRANSIT_TWEEN_ENABLED
        or not Runtime.Root
        or not Runtime.TargetRoot
        or not Runtime.TargetRoot.Parent
        or not Runtime.TargetHumanoid
        or Runtime.TargetHumanoid.Health <= 0
    then
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            Runtime.TargetRoot.Position
        )

    if distance <= CFG.TRANSIT_COMBAT_STOP_DISTANCE
        or activeThreatCount() > 0
    then
        stopTransitTween("combat_range_or_threat")
        return false
    end

    local physical, physicalDist =
        nearestPhysicalEnemy(
            Runtime.Root.Position
        )

    if physical and physicalDist <= 30 then
        stopTransitTween("physical_near")
        return false
    end

    if distance < CFG.TRANSIT_COMBAT_START_DISTANCE
        and not Runtime.TransitTween
    then
        return false
    end

    if Runtime.TransitTween
        and not Runtime.TransitTweenDone
    then
        return true
    end

    local goal =
        approachGoalPosition()

    if not goal then
        return false
    end

    local now = os.clock()

    local needsPath =
        Runtime.ApproachTarget ~= Runtime.Target
        or not Runtime.ApproachWaypoints
        or not Runtime.ApproachDestination
        or horizontalDistance(
            Runtime.ApproachDestination,
            goal
        ) > 16
        or now - Runtime.LastApproachPathAt
            >= CFG.APPROACH_REPATH_INTERVAL

    if needsPath then
        Runtime.LastApproachPathAt = now

        if not computeApproachPath(goal) then
            return false
        end
    end

    local waypoint, index =
        selectTransitWaypoint(
            Runtime.ApproachWaypoints,
            Runtime.ApproachIndex,
            CFG.TRANSIT_SEGMENT_MAX
        )

    if not waypoint then
        return false
    end

    local segmentDistance =
        horizontalDistance(
            Runtime.Root.Position,
            waypoint.Position
        )

    if segmentDistance < CFG.TRANSIT_SEGMENT_MIN then
        return false
    end

    Runtime.ApproachIndex = index + 1

    logKV("COMBAT_TRANSIT", {
        target = Runtime.Target.Name,
        target_distance = string.format("%.1f", distance),
        segment = string.format("%.1f", segmentDistance),
    })

    return startTransitTween(
        waypoint.Position
    )
end

function navigationThink()
    if Runtime.FinalBossDefeated then
        stopTransitTween("final_boss")
        return false
    end

    if not CFG.AUTO_NAVIGATION
        or not Runtime.Root
    then
        return false
    end

    if Runtime.TargetRoot
        and Runtime.TargetHumanoid
        and Runtime.TargetHumanoid.Health > 0
    then
        return false
    end

    if transitCombatShouldStop() then
        stopTransitTween("combat_or_threat")
        return false
    end

    local destination,nextIndex =
        nextRoomWaypoint()

    if not destination then
        stopTransitTween("no_destination")
        return false
    end

    local now = os.clock()

    local needsPath =
        not Runtime.PathWaypoints
        or not Runtime.PathDestination
        or horizontalDistance(
            Runtime.PathDestination,
            destination
        ) > 12
        or now - Runtime.LastRepath >= CFG.REPATH_INTERVAL

    if needsPath
        and not Runtime.PathComputeBusy
        and now >= Runtime.NextPathComputeAt
    then
        stopTransitTween(nil)

        Runtime.PathComputeBusy = true
        Runtime.LastRepath = now
        Runtime.NextPathComputeAt = now + 0.75

        local ok = computePath(destination)

        Runtime.PathComputeBusy = false

        if not ok then
            local gate =
                gateInDirection(destination)

            if gate then
                Runtime.Humanoid:Move(Vector3.zero, false)
                Runtime.NextPathComputeAt =
                    now + CFG.TRANSIT_GATE_RETRY

                if now - Runtime.LastGateLog
                    >= CFG.TRANSIT_GATE_LOG_COOLDOWN
                then
                    Runtime.LastGateLog = now

                    logKV("TRANSIT_GATE_WAIT", {
                        gate = fullName(gate.Instance),
                        distance = string.format("%.1f", gate.Distance),
                    })
                end

                return true
            end

            moveTo(destination,"NEXT_ROOM_DIRECT")
            return true
        end

        logKV("PATH", {
            next_room = nextIndex,
            waypoints = #Runtime.PathWaypoints,
            transit_tween = CFG.TRANSIT_TWEEN_ENABLED,
        })
    end

    local waypoint =
        Runtime.PathWaypoints
        and Runtime.PathWaypoints[
            Runtime.PathIndex
        ]

    if not waypoint then
        stopTransitTween(nil)
        Runtime.PathWaypoints = nil

        if horizontalDistance(
            Runtime.Root.Position,
            destination
        ) > CFG.TRANSIT_TWEEN_STOP_DISTANCE
        then
            local gate =
                gateInDirection(destination)

            if gate then
                Runtime.Humanoid:Move(Vector3.zero, false)

                if os.clock() - Runtime.LastGateLog
                    >= CFG.TRANSIT_GATE_LOG_COOLDOWN
                then
                    Runtime.LastGateLog = os.clock()

                    logKV("TRANSIT_GATE_WAIT", {
                        gate = fullName(gate.Instance),
                        distance = string.format("%.1f", gate.Distance),
                    })
                end

                return true
            end

            moveTo(destination,"NEXT_ROOM_FINISH")
        else
            Runtime.Humanoid:Move(Vector3.zero, false)
        end

        return true
    end

    if horizontalDistance(
        Runtime.Root.Position,
        waypoint.Position
    ) <= CFG.WAYPOINT_REACHED
    then
        Runtime.PathIndex += 1
        waypoint =
            Runtime.PathWaypoints[
                Runtime.PathIndex
            ]
    end

    if not waypoint then
        return true
    end

    if waypoint.Action == Enum.PathWaypointAction.Jump then
        -- Jump segments are safer with normal Humanoid movement.
        stopTransitTween(nil)
        Runtime.Humanoid.Jump = true
        moveTo(
            waypoint.Position,
            "NEXT_ROOM_PATH_JUMP"
        )
        return true
    end

    if CFG.TRANSIT_TWEEN_ENABLED then
        if Runtime.TransitTween
            and not Runtime.TransitTweenDone
        then
            return true
        end

        local farWaypoint, farIndex =
            selectTransitWaypoint(
                Runtime.PathWaypoints,
                Runtime.PathIndex,
                CFG.TRANSIT_SEGMENT_MAX
            )

        if farWaypoint then
            Runtime.PathIndex = farIndex + 1

            startTransitTween(
                farWaypoint.Position
            )

            return true
        end

        startTransitTween(waypoint.Position)
        return true
    end

    moveTo(
        waypoint.Position,
        "NEXT_ROOM_PATH"
    )

    return true
end


