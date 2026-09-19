-- DQR modular runtime: core/Geometry.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Geometry
-- ============================================================

function horizontalAxesForPart(part)
    local axes = {
        {
            Vec = part.CFrame.RightVector,
            Half = part.Size.X * 0.5,
            LocalIndex = 1,
        },
        {
            Vec = part.CFrame.UpVector,
            Half = part.Size.Y * 0.5,
            LocalIndex = 2,
        },
        {
            Vec = part.CFrame.LookVector,
            Half = part.Size.Z * 0.5,
            LocalIndex = 3,
        },
    }

    -- Ignore whichever local axis points most vertically.
    table.sort(axes, function(a, b)
        return math.abs(a.Vec.Y) < math.abs(b.Vec.Y)
    end)

    return axes[1], axes[2]
end

function componentByIndex(v, idx)
    if idx == 1 then return v.X end
    if idx == 2 then return v.Y end
    return v.Z
end

CIRCLE_ATTACKS = {
    kolvumarSpit = true,
    azrallikPunch = true,
    fingerBlastHit = true,
    bigMageBeam = true,
}

function threatGeometry(meta)
    local part = meta.Part
    if not part or not part.Parent then return nil end

    if CIRCLE_ATTACKS[meta.RootName] then
        local a,b = horizontalAxesForPart(part)

        local radius =
            math.max(
                a.Half,
                b.Half
            )

        local extra =
            meta.RootName == "kolvumarSpit"
            and CFG.KOLVUMAR_SPIT_SAFETY_EXTRA
            or 0

        return {
            Type = "Circle",
            Center = part.Position,
            Radius = radius + CFG.SAFETY_MARGIN + extra,
            Source = meta.RootName,
        }
    end

    return {
        Type = "Box",
        Part = part,
        Source = meta.RootName,
    }
end

function pointInsideProjectedBox(part, point, margin)
    margin = margin or 0

    local localPoint =
        part.CFrame:PointToObjectSpace(point)

    local axisA, axisB =
        horizontalAxesForPart(part)

    local coordA =
        math.abs(
            componentByIndex(
                localPoint,
                axisA.LocalIndex
            )
        )

    local coordB =
        math.abs(
            componentByIndex(
                localPoint,
                axisB.LocalIndex
            )
        )

    return
        coordA <= axisA.Half + margin
        and coordB <= axisB.Half + margin
end

function boxClearance(part, point)
    local localPoint =
        part.CFrame:PointToObjectSpace(point)

    local axisA, axisB =
        horizontalAxesForPart(part)

    local coordA =
        math.abs(
            componentByIndex(
                localPoint,
                axisA.LocalIndex
            )
        )

    local coordB =
        math.abs(
            componentByIndex(
                localPoint,
                axisB.LocalIndex
            )
        )

    local dx = coordA - axisA.Half
    local dz = coordB - axisB.Half

    if dx <= 0 and dz <= 0 then
        return -math.min(-dx, -dz)
    end

    return math.sqrt(
        math.max(dx,0)^2
        + math.max(dz,0)^2
    )
end

function pointInsideThreat(meta, point)
    local g = threatGeometry(meta)
    if not g then return false end

    if g.Type == "Circle" then
        return
            horizontalDistance(
                point,
                g.Center
            ) <= g.Radius
    end

    return pointInsideProjectedBox(
        g.Part,
        point,
        CFG.SAFETY_MARGIN
    )
end

function threatClearance(meta, point)
    local g = threatGeometry(meta)
    if not g then return math.huge end

    if g.Type == "Circle" then
        return
            horizontalDistance(
                point,
                g.Center
            )
            - g.Radius
    end

    return boxClearance(g.Part, point)
        - CFG.SAFETY_MARGIN
end

function cleanupVirtualThreats()
    local now = os.clock()

    for id, t in pairs(Runtime.VirtualThreats) do
        if now >= t.Expires then
            Runtime.VirtualThreats[id] = nil
        end
    end
end

function pointInsideVirtual(point, t)
    return horizontalDistance(point, t.Center) <= t.Radius
end

BOSS_HAZARD_OWNER = {
    -- Samurai Palace.
    shurikenThrow = "Sanada Yukimura",
    crossShuriken = "Sanada Yukimura",

    golemRockThrow = "Ancient Golem Guardian",
    golemRockThrowSmall = "Ancient Golem Guardian",
    golemRockClap = "Ancient Golem Guardian",
    rockshatter = "Ancient Golem Guardian",
    rockExplosion = "Ancient Golem Guardian",
    rockExplosionSmall = "Ancient Golem Guardian",

    flameShurikenHit = "Miyamoto Musashi",
    flameBeam = "Miyamoto Musashi",
    doubleFlameBeam = "Miyamoto Musashi",
    ["Flame Cyclone"] = "Miyamoto Musashi",

    -- Dormant Underworld reference ownership.
    spikePrecast = "Demonic Overgrowth",
    overgrowthLongLineSpikes = "Demonic Overgrowth",
    overgrowthSpikes = "Demonic Overgrowth",
    kolvumarSpit = "Kolvumar",
    horizontalBeam = "Demon Lord Azrallik",
    azrallikPunch = "Demon Lord Azrallik",
    azrallikPunchSpread = "Demon Lord Azrallik",
    fingerBlastHit = "Demon Lord Azrallik",
}

THREAT_MAX_RELEVANT_AGE = {
    -- Samurai Palace measured object lifetimes / useful danger windows.
    npcShurikenThrow = 3.25,
    shurikenThrow = 2.25,
    crossShuriken = 1.85,
    eliteSwordsmanSpin = 3.25,

    -- golemRockThrow remains in Workspace ~10 sec, but the dangerous sequence
    -- transitions into the explosion/small-rock objects after a few seconds.
    golemRockThrow = 4.30,
    golemRockThrowSmall = 1.30,
    golemRockClap = 2.50,
    rockshatter = 4.20,
    rockExplosion = 0.45,
    rockExplosionSmall = 0.35,

    flameShurikenHit = 2.50,
    flameBeam = 1.25,
    doubleFlameBeam = 4.25,
    ["Flame Cyclone"] = 3.80,

    -- Dormant Underworld reference windows.
    npcMageSpikes = 3.6,
    bigMageBeam = 5.8,
    spikePrecast = 1.8,
    overgrowthSpikes = 1.4,
    overgrowthLongLineSpikes = 3.8,
    horizontalBeam = 5.0,
    azrallikPunch = 4.0,
    azrallikPunchSpread = 4.0,
    fingerBlastHit = 2.45,
}

function refreshBossAliveCache()
    local now = os.clock()

    if now - Runtime.BossAliveCacheAt < 0.15 then
        return
    end

    Runtime.BossAliveCacheAt = now
    table.clear(Runtime.BossAliveCache)

    for _, enemy in ipairs(livingEnemies()) do
        if enemy.Model
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
        then
            Runtime.BossAliveCache[enemy.Model.Name] = true
        end
    end
end

function livingEnemyNamed(name)
    refreshBossAliveCache()
    return Runtime.BossAliveCache[name] == true
end

function threatRelevant(meta)
    if not meta or not meta.Part or not meta.Part.Parent then
        return false, "gone"
    end

    local now = os.clock()
    local age = now - meta.Created

    -- A hazard created in a completed room is visual history, not a reason
    -- to keep the next-room character trapped forever.
    if meta.SpawnRoom
        and meta.SpawnRoom > 0
        and Runtime.CurrentRoomIndex > meta.SpawnRoom
        and age >= CFG.ROOM_TRANSITION_HAZARD_GRACE
    then
        return false, "room_finished"
    end

    local owner = BOSS_HAZARD_OWNER[meta.RootName]

    local bossDeadGrace =
        CFG.BOSS_DEAD_HAZARD_GRACE

    if owner == "Demon Lord Azrallik"
        and (
            meta.RootName == "horizontalBeam"
            or meta.RootName == "azrallikPunch"
            or meta.RootName == "azrallikPunchSpread"
            or meta.RootName == "fingerBlastHit"
        )
    then
        bossDeadGrace =
            math.max(
                bossDeadGrace,
                CFG.FINAL_BOSS_POST_DEATH_HAZARD_GRACE
            )
    end

    if owner
        and not livingEnemyNamed(owner)
        and age >= bossDeadGrace
    then
        return false, "boss_dead"
    end

    if meta.RootName == "horizontalBeam"
        and Runtime.LastHorizontalBeamSpawn > -math.huge
        and now - Runtime.LastHorizontalBeamSpawn
            >= CFG.AZRALLIK_BEAM_POST_SPAWN_DANGER
    then
        return false, "beam_sweep_finished"
    end

    local maxAge = THREAT_MAX_RELEVANT_AGE[meta.RootName]

    if maxAge and age > maxAge then
        return false, "expired_window"
    end

    return true, nil
end

function maybeLogIgnoredThreat(meta, reason)
    if meta and not meta.InvalidLogged and reason ~= "gone" then
        meta.InvalidLogged = true

        if reason == "beam_sweep_finished" then
            local now = os.clock()

            if now - Runtime.LastAzrallikBeamReleaseLog >= 0.70 then
                Runtime.LastAzrallikBeamReleaseLog = now

                logKV("AZRALLIK_BEAM_RELEASE", {
                    since_last_spawn =
                        string.format(
                            "%.2f",
                            now
                            - Runtime.LastHorizontalBeamSpawn
                        ),
                    configured =
                        CFG.AZRALLIK_BEAM_POST_SPAWN_DANGER,
                })
            end

            return
        end

        logKV("THREAT_IGNORE", {
            attack = meta.RootName,
            reason = reason,
            age = string.format("%.2f", os.clock() - meta.Created),
            spawn_room = tostring(meta.SpawnRoom),
            current_room = tostring(Runtime.CurrentRoomIndex),
        })
    end
end

function activeThreats()
    cleanupVirtualThreats()

    local result = {}
    local hasPrimary = {}

    for part,meta in pairs(Runtime.Threats) do
        local relevant, reason = threatRelevant(meta)

        if relevant and meta.Kind == "Precast" then
            result[#result + 1] = meta
            hasPrimary[meta.RootName] = true
        elseif not relevant then
            maybeLogIgnoredThreat(meta, reason)
        end
    end

    -- Invisible hitboxes matter only when their warning is gone AND the
    -- source is still relevant.
    for part,meta in pairs(Runtime.Threats) do
        local relevant, reason = threatRelevant(meta)

        if relevant
            and meta.Kind == "ActiveHitbox"
            and not hasPrimary[meta.RootName]
        then
            result[#result + 1] = meta
        elseif not relevant then
            maybeLogIgnoredThreat(meta, reason)
        end
    end

    return result
end

activeThreatCount = function()
    local n = #activeThreats()

    for _ in pairs(Runtime.VirtualThreats) do
        n += 1
    end

    return n
end

function bossThreatsFrom(threats)
    local out = {}
    local bossName = Runtime.ActiveBossName

    if not bossName then
        return out
    end

    local now = os.clock()

    for _, meta in ipairs(threats) do
        if BOSS_HAZARD_OWNER[meta.RootName] == bossName then
            -- Kolvumar's spit can remain on the floor for ~35 seconds. Keep
            -- it in pointDanger(), but do NOT let an old puddle count as the
            -- current attack wave.
            if bossName == "Kolvumar"
                and meta.RootName == "kolvumarSpit"
                and now - meta.Created > CFG.KOLVUMAR_NEW_WAVE_AGE
            then
                -- persistent floor zone only
            else
                out[#out + 1] = meta
            end
        end
    end

    return out
end

function kolvumarDirectVirtualActive(now)
    now = now or os.clock()

    for _, vt in pairs(Runtime.VirtualThreats) do
        if vt
            and vt.Source == "Kolvumar NonRed Sequence"
            and (vt.Expires or -math.huge) > now
        then
            return true
        end
    end

    return false
end

function updateBossWave(threats)
    local now = os.clock()
    local bossThreats = bossThreatsFrom(threats)

    if not Runtime.ActiveBossName then
        Runtime.BossWave = nil
        return nil, bossThreats
    end

    local kolvumarVirtual =
        Runtime.ActiveBossName == "Kolvumar"
        and kolvumarDirectVirtualActive(now)

    local hasBossActivity =
        #bossThreats > 0
        or kolvumarVirtual

    if hasBossActivity then
        if not Runtime.BossWave then
            Runtime.BossWaveCounter += 1
            Runtime.BossWave = {
                Id = Runtime.BossWaveCounter,
                Boss = Runtime.ActiveBossName,
                Started = now,
                CollectUntil = now + CFG.BOSS_WAVE_COLLECT_WINDOW,
                LastThreatAt = now,
                LastPlanAt = -math.huge,
                Plan = nil,
                Teleported = false,
                TeleportCount = 0,
                LastWaveTeleportAt = -math.huge,

                -- Overgrowth narrow-spike sequence state.
                SequenceDir = nil,
                SequenceStep = nil,
                SequenceOrigin = nil,
                SequenceLockedAt = nil,
                SequenceCommitted = false,
                SequenceCommitPosition = nil,
                SequenceCommitUntil = -math.huge,
                SequenceMaxProjection = -math.huge,

                -- Overgrowth simultaneous long-line pocket state.
                LongLinePocket = nil,
                LongLinePocketLocked = false,
                LongLinePocketClearance = nil,
                LongLinePocketGapWidth = nil,

                -- V8.5 measured edge-commit state.
                EdgeCommitStartedAt = nil,
                EdgeCommitOrigin = nil,
                EdgeCommitTarget = nil,
                EdgeRescueUsed = false,

                -- Azrallik horizontal-beam safe-pocket state.
                BeamPocket = nil,
                BeamPocketAxis = nil,
                BeamPocketLocked = false,
                BeamPocketReached = false,
                BeamPocketLastPlanAt = -math.huge,
                BeamPocketLastAdvanceAt = -math.huge,
                BeamPocketLastSlideAt = -math.huge,
                BeamPocketClearance = nil,
                BeamPocketGapWidth = nil,
                BeamLatticeSpacing = nil,
                LastSafePressureAt = -math.huge,
                BeamLatticeHalfWidth = nil,

                FingerBlastStartedAt = nil,
                FingerBlastCenter = nil,

                -- V9.0 Kolvumar local spit-pocket state.
                KolvumarPocket = nil,
                KolvumarPocketUntil = -math.huge,
                KolvumarPocketReached = false,
                KolvumarPocketLastPlanAt = -math.huge,

                Finalized = false,
                SafeSince = nil,
                MaxThreatCount = math.max(#bossThreats, kolvumarVirtual and 1 or 0),
            }

            logKV("BOSS_WAVE_START", {
                id = Runtime.BossWave.Id,
                boss = Runtime.ActiveBossName,
                threats = math.max(#bossThreats, kolvumarVirtual and 1 or 0),
            })
        else
            Runtime.BossWave.LastThreatAt = now
            Runtime.BossWave.MaxThreatCount =
                math.max(
                    Runtime.BossWave.MaxThreatCount or 0,
                    math.max(
                        #bossThreats,
                        kolvumarVirtual and 1 or 0
                    )
                )
        end
    elseif Runtime.BossWave
        and now - Runtime.BossWave.LastThreatAt >= CFG.BOSS_WAVE_END_GRACE
    then
        logKV("BOSS_WAVE_END", {
            id = Runtime.BossWave.Id,
            boss = Runtime.BossWave.Boss,
            max_threats = Runtime.BossWave.MaxThreatCount or 0,
            teleported = Runtime.BossWave.Teleported,
            elapsed = string.format("%.3f", now - Runtime.BossWave.Started),
        })

        Runtime.BossWave = nil
    end

    return Runtime.BossWave, bossThreats
end

function mageThreatsFrom(threats)
    local out = {}

    for _, meta in ipairs(threats) do
        if meta.RootName == "npcShurikenThrow"
            or meta.RootName == "npcMageSpikes"
            or meta.RootName == "bigMageBeam"
        then
            out[#out + 1] = meta
        end
    end

    return out
end

function updateMageWave(threats)
    local now = os.clock()

    if Runtime.ActiveBossName or Runtime.CompletionConfirmed then
        Runtime.MageWave = nil
        return nil, {}
    end

    local mageThreats = mageThreatsFrom(threats)

    -- Group only true overlap. A single line stays on the cheaper normal path.
    if #mageThreats >= 2 then
        if not Runtime.MageWave then
            Runtime.MageWaveCounter += 1

            Runtime.MageWave = {
                Id = Runtime.MageWaveCounter,
                Started = now,
                CollectUntil = now + CFG.MAGE_WAVE_COLLECT_WINDOW,
                LastThreatAt = now,
                LastPlanAt = -math.huge,
                Plan = nil,
                Finalized = false,
                Teleported = false,
                MaxThreatCount = #mageThreats,
            }

            logKV("MAGE_WAVE_START", {
                id = Runtime.MageWave.Id,
                threats = #mageThreats,
            })
        else
            Runtime.MageWave.LastThreatAt = now
            Runtime.MageWave.MaxThreatCount =
                math.max(Runtime.MageWave.MaxThreatCount or 0, #mageThreats)
        end
    elseif Runtime.MageWave
        and now - Runtime.MageWave.LastThreatAt >= CFG.MAGE_WAVE_END_GRACE
    then
        logKV("MAGE_WAVE_END", {
            id = Runtime.MageWave.Id,
            max_threats = Runtime.MageWave.MaxThreatCount or 0,
            teleported = Runtime.MageWave.Teleported,
            elapsed = string.format("%.3f", now - Runtime.MageWave.Started),
        })

        Runtime.MageWave = nil
    end

    return Runtime.MageWave, mageThreats
end

function pointDanger(point)
    local penalty = 0
    local insideCount = 0
    local nearest = math.huge

    for _, meta in ipairs(activeThreats()) do
        local clearance =
            threatClearance(meta, point)

        nearest = math.min(nearest, clearance)

        if clearance <= 0 then
            insideCount += 1
            penalty += 100000
                + math.abs(clearance) * 800
        elseif clearance < 5 then
            penalty += (5 - clearance) * 400
        elseif clearance < 10 then
            penalty += (10 - clearance) * 35
        end
    end

    for _, vt in pairs(Runtime.VirtualThreats) do
        local clearance =
            horizontalDistance(point, vt.Center)
            - vt.Radius

        nearest = math.min(nearest, clearance)

        if clearance <= 0 then
            insideCount += 1
            penalty += 80000
                + math.abs(clearance) * 600
        elseif clearance < 4 then
            penalty += (4 - clearance) * 300
        end
    end

    return penalty, insideCount, nearest
end

function routeDanger(a, b)
    local total = 0

    for i = 1, CFG.PATH_SAMPLES do
        local alpha = i / CFG.PATH_SAMPLES
        local p = a:Lerp(b, alpha)

        local penalty, inside =
            pointDanger(p)

        if inside > 0 then
            total += 40000
        end

        total += penalty * 0.08
    end

    return total
end



if DQR_WORLD and type(DQR_WORLD.Attacks) == "table" then
    table.clear(BOSS_HAZARD_OWNER)
    table.clear(THREAT_MAX_RELEVANT_AGE)
    for rootName, attack in pairs(DQR_WORLD.Attacks) do
        if type(attack) == "table" then
            if attack.Owner then BOSS_HAZARD_OWNER[rootName] = attack.Owner end
            if attack.MaxRelevantAge then THREAT_MAX_RELEVANT_AGE[rootName] = attack.MaxRelevantAge end
        end
    end
end
