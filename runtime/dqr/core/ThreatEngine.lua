-- DQR modular runtime: core/ThreatEngine.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Threat discovery
-- ============================================================

KNOWN_THREAT_ROOTS = {
    -- Samurai Palace normal/ranged attacks.
    npcShurikenThrow = true,

    -- Sanada Yukimura.
    shurikenThrow = true,
    crossShuriken = true,
    eliteSwordsmanSpin = true,

    -- Ancient Golem Guardian.
    golemRockThrow = true,
    golemRockThrowSmall = true,
    golemRockClap = true,
    rockshatter = true,
    rockExplosion = true,
    rockExplosionSmall = true,

    -- Miyamoto Musashi.
    flameShurikenHit = true,
    flameBeam = true,
    doubleFlameBeam = true,
    ["Flame Cyclone"] = true,

    -- Dormant Underworld reference hazards.
    npcMageSpikes = true,
    bigMageBeam = true,
    spikePrecast = true,
    overgrowthLongLineSpikes = true,
    overgrowthSpikes = true,
    kolvumarSpit = true,
    horizontalBeam = true,
    azrallikPunch = true,
    azrallikPunchSpread = true,
    fingerBlastHit = true,
}

PLAYER_ATTACK_ROOTS = {
    ["Rending Slice"] = true,
    ["Lava Lash"] = true,
    ["lavaLashHitbox"] = true,
}

function topWorkspaceChild(inst)
    local cur = inst

    while cur and cur.Parent ~= workspace do
        cur = cur.Parent
    end

    return cur
end

function classifyThreatPart(part)
    if not part:IsA("BasePart") then
        return nil
    end

    local top = topWorkspaceChild(part)
    if not top then return nil end

    if PLAYER_ATTACK_ROOTS[top.Name] then
        return nil
    end

    if KNOWN_THREAT_ROOTS[top.Name] then
        -- Prefer visible warning / precast.
        if part.Name == "precast" then
            return "Precast"
        end

        if top.Name == "spikePrecast"
            and part.Name == "Part"
        then
            return "Precast"
        end

        -- overgrowthSpikes itself is the damaging followup; we normally
        -- already moved from spikePrecast, but retaining it as danger
        -- prevents re-entering.
        if top.Name == "overgrowthSpikes"
            and part.Name == "hitBox"
        then
            return "ActiveHitbox"
        end

        -- Invisible hitboxes are secondary threat evidence.
        if part.Name == "hitBox" then
            return "ActiveHitbox"
        end
    end

    -- Samurai Palace explosion/cyclone objects do not expose the same
    -- precast/hitBox naming as the line attacks. Their visible/touchable
    -- pieces are still legitimate live geometry observed in the recon.
    if top.Name == "Flame Cyclone"
        and part.Name == "crescent"
    then
        return "ActiveHitbox"
    end

    local lowerTop = string.lower(top.Name)
    local lowerName = string.lower(part.Name)

    if lowerName == "precast"
        or lowerTop:find("precast", 1, true)
    then
        return "Precast"
    end

    return nil
end

function registerThreat(part)
    if Runtime.Threats[part] then return end

    local top = topWorkspaceChild(part)

    -- Golem explosion effects contain many flame MeshParts (up to dozens per
    -- explosion). Treat each explosion root as ONE short-lived radial virtual
    -- hazard instead of multiplying pointDanger/routeDanger work by every VFX
    -- fragment. Radius follows the observed ~34/26-stud attack footprints.
    if top
        and part.Name == "PrimaryPart"
        and (
            top.Name == "rockExplosion"
            or top.Name == "rockExplosionSmall"
        )
    then
        local radius =
            top.Name == "rockExplosion"
            and 18.0
            or 14.0

        local lifetime =
            top.Name == "rockExplosion"
            and 0.45
            or 0.35

        addVirtualThreat(
            top,
            part.Position,
            radius,
            lifetime,
            top.Name
        )

        return
    end

    local kind = classifyThreatPart(part)
    if not kind then return end

    local createdNow = os.clock()

    Runtime.Threats[part] = {
        Part = part,
        Kind = kind,
        RootName = top and top.Name or "Unknown",
        Created = createdNow,
        SpawnRoom = Runtime.CurrentRoomIndex,
        InvalidLogged = false,
    }

    if top
        and top.Name == "spikePrecast"
        and kind == "Precast"
        and math.max(part.Size.X, part.Size.Z) >= 40
    then
        Runtime.OvergrowthSpikeHistory[
            #Runtime.OvergrowthSpikeHistory + 1
        ] = {
            Position = part.Position,
            Time = createdNow,
            Part = part,
        }

        local kept = {}

        for _, item in ipairs(Runtime.OvergrowthSpikeHistory) do
            if createdNow - item.Time <= CFG.OVERGROWTH_SEQUENCE_AGE then
                kept[#kept + 1] = item
            end
        end

        while #kept > CFG.OVERGROWTH_SEQUENCE_HISTORY do
            table.remove(kept, 1)
        end

        Runtime.OvergrowthSpikeHistory = kept
    end

    if top
        and top.Name == "horizontalBeam"
        and kind == "Precast"
    then
        Runtime.LastHorizontalBeamSpawn = createdNow

        Runtime.HorizontalBeamHistory[#Runtime.HorizontalBeamHistory + 1] = {
            Position = part.Position,
            Time = createdNow,
            Part = part,
        }

        local kept = {}
        for _, item in ipairs(Runtime.HorizontalBeamHistory) do
            if createdNow - item.Time <= CFG.AZRALLIK_SWEEP_HISTORY_AGE then
                kept[#kept + 1] = item
            end
        end

        while #kept > CFG.AZRALLIK_SWEEP_HISTORY do
            table.remove(kept, 1)
        end

        Runtime.HorizontalBeamHistory = kept
    end

    logKV("THREAT_START", {
        attack = top and top.Name or "Unknown",
        kind = kind,
        size = vec(part.Size),
        position = vec(part.Position),
        orientation = vec(part.Orientation),
    })

    connect(part.AncestryChanged, function(_, parent)
        if parent == nil then
            local meta = Runtime.Threats[part]
            local created = meta and meta.Created or os.clock()
            Runtime.Threats[part] = nil

            logKV("THREAT_END", {
                attack = top and top.Name or "Unknown",
                lifetime = string.format("%.3f", os.clock() - created),
            })
        end
    end)
end

for _, inst in ipairs(workspace:GetDescendants()) do
    if inst:IsA("BasePart") then
        registerThreat(inst)
    end
end

connect(workspace.DescendantAdded, function(inst)
    if inst:IsA("BasePart") then
        task.defer(registerThreat, inst)
    elseif inst:IsA("Animator") then
        local model = inst.Parent and inst.Parent.Parent
        if model and model:IsA("Model") then
            task.defer(watchEnemyAnimator, model)
        end
    end
end)



if DQR_WORLD and type(DQR_WORLD.Attacks) == "table" then
    table.clear(KNOWN_THREAT_ROOTS)
    for rootName in pairs(DQR_WORLD.Attacks) do
        KNOWN_THREAT_ROOTS[rootName] = true
    end
end
