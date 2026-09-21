-- DQR universal macro combat-recovery controller.
-- Only runs when a recorded fight checkpoint still has living enemies.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer
local Context = DQR_MACRO_CONTEXT

local Combat = {}

local SCAN_CACHE = 0.12
local CHECKPOINT_RADIUS = 150.0
local FALLBACK_TIMEOUT = 120.0

local DESIRED_RANGE = 24.0
local APPROACH_RANGE = 31.0
local RETREAT_RANGE = 11.5
local BASIC_RANGE = 20.0
local ORBIT_STEP = 9.0

local ATTACK_INTERVAL = 0.34
local ABILITY_CHAIN_GAP = 0.20
local MOVEMENT_INTERVAL = 0.09

local scanCache = {
    At = -math.huge,
    Enemies = {},
}

local function character(timeout)
    local deadline = os.clock() + (timeout or 0)

    repeat
        local model = LP.Character
        local humanoid =
            model
            and model:FindFirstChildOfClass("Humanoid")
        local root =
            model
            and model:FindFirstChild("HumanoidRootPart")

        if model and humanoid
            and humanoid.Health > 0
            and root
        then
            return model, humanoid, root
        end

        task.wait(0.05)
    until os.clock() >= deadline

    return nil, nil, nil
end

local function modelRoot(model)
    return
        model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end

local function addEnemy(result, seen, humanoid)
    if not humanoid
        or not humanoid:IsA("Humanoid")
        or humanoid.Health <= 0
    then
        return
    end

    local model = humanoid.Parent

    if not model
        or not model:IsA("Model")
        or seen[model]
        or Players:GetPlayerFromCharacter(model)
    then
        return
    end

    local root = modelRoot(model)

    if not root then
        return
    end

    seen[model] = true

    result[#result + 1] = {
        Model = model,
        Humanoid = humanoid,
        Root = root,
        Room =
            Context
            and Context.RoomOfInstance(model)
            or nil,
    }
end

function Combat.Scan(force)
    local now = os.clock()

    if not force
        and now - scanCache.At < SCAN_CACHE
    then
        return scanCache.Enemies
    end

    local result = {}
    local seen = {}

    local dungeon =
        workspace:FindFirstChild("dungeon")

    if dungeon then
        for _, instance in ipairs(
            dungeon:GetDescendants()
        ) do
            if instance:IsA("Humanoid") then
                addEnemy(
                    result,
                    seen,
                    instance
                )
            end
        end
    end

    -- Catch boss/add models spawned outside workspace.dungeon.
    for _, child in ipairs(workspace:GetChildren()) do
        if child ~= dungeon
            and child:IsA("Model")
        then
            local humanoid =
                child:FindFirstChildOfClass("Humanoid")

            if humanoid then
                addEnemy(
                    result,
                    seen,
                    humanoid
                )
            end
        end
    end

    scanCache.At = now
    scanCache.Enemies = result

    return result
end

local function checkpointPosition(checkpoint)
    if not checkpoint then
        return nil
    end

    if Context and checkpoint.context then
        return Context.Resolve(checkpoint.context)
    end

    return nil
end

local function snapshotNames(enemies)
    local counts = {}

    for _, enemy in ipairs(enemies) do
        local name = enemy.Model.Name
        counts[name] = (counts[name] or 0) + 1
    end

    local result = {}

    for name, count in pairs(counts) do
        result[#result + 1] = {
            name = name,
            count = count,
        }
    end

    table.sort(result, function(a, b)
        return a.name < b.name
    end)

    return result
end

function Combat.Snapshot(position, radius)
    radius = radius or CHECKPOINT_RADIUS

    local room =
        Context
        and Context.RoomAt(position)
        or nil

    local enemies = {}

    for _, enemy in ipairs(
        Combat.Scan(true)
    ) do
        local distance =
            (enemy.Root.Position - position).Magnitude

        local sameRoom =
            room
            and enemy.Room == room

        if sameRoom
            or (
                not room
                and distance <= radius
            )
        then
            enemies[#enemies + 1] = enemy
        end
    end

    return {
        room = room,
        context =
            Context
            and Context.Capture(position)
            or {p = {position.X, position.Y, position.Z}},
        enemies = snapshotNames(enemies),
        radius = radius,
    }
end

local function recordedNameSet(checkpoint)
    local set = {}

    for _, entry in ipairs(
        checkpoint.enemies or {}
    ) do
        set[tostring(entry.name)] = true
    end

    return set
end

function Combat.Pending(checkpoint)
    if type(checkpoint) ~= "table" then
        return {}
    end

    local center =
        checkpointPosition(checkpoint)

    local names =
        recordedNameSet(checkpoint)

    local room =
        checkpoint.room

    local result = {}

    for _, enemy in ipairs(
        Combat.Scan(true)
    ) do
        local sameRoom =
            room ~= nil
            and enemy.Room == room

        local named =
            names[enemy.Model.Name] == true

        local close =
            center
            and (
                enemy.Root.Position - center
            ).Magnitude
                <= tonumber(
                    checkpoint.radius
                )
                    or CHECKPOINT_RADIUS

        -- Exact room is strongest evidence. Name + locality is the fallback
        -- for bosses/adds that spawn outside the room hierarchy.
        if sameRoom
            or (named and close)
        then
            result[#result + 1] = enemy
        end
    end

    return result
end

local function abilitySlot(tool)
    if not tool or not tool:IsA("Tool") then
        return nil
    end

    local value =
        tool:FindFirstChild("abilitySlot")

    if not value then
        return nil
    end

    local slot =
        string.lower(
            tostring(value.Value)
        )

    if slot == "q" or slot == "e" then
        return slot
    end

    return nil
end

local function abilityTool(slot)
    local characterModel = LP.Character
    local backpack = LP:FindFirstChild("Backpack")

    for _, container in ipairs({
        backpack,
        characterModel,
    }) do
        if container then
            for _, child in ipairs(
                container:GetChildren()
            ) do
                if abilitySlot(child) == slot then
                    return child
                end
            end
        end
    end

    return nil
end

local function abilityRange(tool)
    if not tool then
        return 34.0
    end

    for _, attribute in ipairs({
        "Range",
        "range",
        "CastRange",
        "castRange",
        "AbilityRange",
        "abilityRange",
    }) do
        local ok, value =
            pcall(
                tool.GetAttribute,
                tool,
                attribute
            )

        if ok
            and type(value) == "number"
            and value > 0
        then
            return value
        end
    end

    return 34.0
end

local function face(root, target)
    local delta =
        target.Root.Position - root.Position

    local flat =
        Vector3.new(
            delta.X,
            0,
            delta.Z
        )

    if flat.Magnitude < 0.01 then
        return
    end

    pcall(function()
        root.CFrame =
            CFrame.lookAt(
                root.Position,
                root.Position + flat.Unit
            )
    end)
end

local function castSkill(slot, target)
    local tool = abilityTool(slot)

    if not tool then
        return false
    end

    local cooldown =
        tool:FindFirstChild("cooldown")

    if cooldown
        and tonumber(cooldown.Value)
        and cooldown.Value > 0
    then
        return false
    end

    local _, _, root = character(0)

    if not root then
        return false
    end

    local distance =
        Vector3.new(
            target.Root.Position.X - root.Position.X,
            0,
            target.Root.Position.Z - root.Position.Z
        ).Magnitude

    if distance > abilityRange(tool) then
        return false
    end

    local localEvent =
        tool:FindFirstChild("localEvent")

    if not localEvent then
        return false
    end

    face(root, target)

    pcall(function()
        localEvent:Fire()
    end)

    local remotes =
        ReplicatedStorage:FindFirstChild("remotes")

    local abilityUsed =
        remotes
        and remotes:FindFirstChild("abilityUsed")

    if abilityUsed
        and abilityUsed:IsA("RemoteEvent")
    then
        pcall(function()
            abilityUsed:FireServer(
                slot,
                tool
            )
        end)
    end

    return true
end

local function weaponEvent()
    local model = LP.Character

    if not model then
        return nil
    end

    for _, instance in ipairs(
        model:GetChildren()
    ) do
        if instance:IsA("Accessory")
            and instance:FindFirstChild("Weapon")
        then
            local remote =
                instance:FindFirstChildOfClass("RemoteEvent")

            if remote then
                return remote
            end
        end
    end

    return nil
end

local function basicAttack(target)
    local _, _, root = character(0)

    if not root then
        return false
    end

    local distance =
        Vector3.new(
            target.Root.Position.X - root.Position.X,
            0,
            target.Root.Position.Z - root.Position.Z
        ).Magnitude

    if distance > BASIC_RANGE then
        return false
    end

    local event = weaponEvent()

    if not event then
        return false
    end

    face(root, target)

    pcall(function()
        event:FireServer()
    end)

    local remotes =
        ReplicatedStorage:FindFirstChild("remotes")

    local used =
        remotes
        and remotes:FindFirstChild("weaponUsed")

    if used
        and used:IsA("RemoteEvent")
    then
        pcall(function()
            used:FireServer()
        end)
    end

    return true
end

local function score(enemy, origin, sticky)
    if enemy == sticky then
        return math.huge
    end

    local distance =
        (enemy.Root.Position - origin).Magnitude

    local maxHealth =
        math.max(
            tonumber(enemy.Humanoid.MaxHealth) or 0,
            0
        )

    local hpRatio =
        maxHealth > 0
        and enemy.Humanoid.Health / maxHealth
        or 1

    -- Strongest first, then finish wounded/local enemies.
    return
        maxHealth * 0.0001
        + (1 - hpRatio) * 1800
        - distance * 5
end

local function chooseTarget(enemies, root, sticky)
    if sticky
        and sticky.Humanoid
        and sticky.Humanoid.Health > 0
        and sticky.Root
        and sticky.Root.Parent
    then
        return sticky
    end

    local best
    local bestScore = -math.huge

    for _, enemy in ipairs(enemies) do
        local value =
            score(
                enemy,
                root.Position,
                nil
            )

        if value > bestScore then
            bestScore = value
            best = enemy
        end
    end

    return best
end

local function combatMove(humanoid, root, target, orbitSign)
    local delta =
        target.Root.Position - root.Position

    local flat =
        Vector3.new(
            delta.X,
            0,
            delta.Z
        )

    local distance = flat.Magnitude

    if distance < 0.01 then
        return
    end

    local toward = flat.Unit
    local destination

    if distance > APPROACH_RANGE then
        destination =
            target.Root.Position
            - toward * DESIRED_RANGE

    elseif distance < RETREAT_RANGE then
        destination =
            root.Position
            - toward * (
                DESIRED_RANGE - distance
            )

    else
        local tangent =
            Vector3.new(
                -toward.Z,
                0,
                toward.X
            ) * orbitSign

        destination =
            root.Position
            + tangent * ORBIT_STEP
            + toward
                * math.clamp(
                    distance - DESIRED_RANGE,
                    -3,
                    3
                )
    end

    pcall(function()
        humanoid:MoveTo(destination)
    end)
end

function Combat.FightUntilClear(checkpoint, control)
    control = control or {}

    local started = os.clock()
    local sticky
    local lastAttack = -math.huge
    local lastAbility = -math.huge
    local lastMove = -math.huge
    local orbitSign = 1
    local nextOrbitFlip = os.clock() + 1.6

    print(
        "[DQR Macro] FALLBACK | START | room="
        .. tostring(checkpoint and checkpoint.room or "unknown")
    )

    while os.clock() - started < FALLBACK_TIMEOUT do
        if type(control.Cancelled) == "function"
            and control.Cancelled()
        then
            return false, "cancelled"
        end

        local pending =
            Combat.Pending(checkpoint)

        if #pending == 0 then
            print(
                "[DQR Macro] FALLBACK | CLEAR | seconds="
                .. string.format("%.2f", os.clock() - started)
            )

            return true
        end

        local _, humanoid, root =
            character(2)

        if not humanoid or not root then
            task.wait(0.10)
            continue
        end

        sticky =
            chooseTarget(
                pending,
                root,
                sticky
            )

        if not sticky then
            task.wait(0.08)
            continue
        end

        if os.clock() >= nextOrbitFlip then
            orbitSign *= -1
            nextOrbitFlip = os.clock() + 1.6
        end

        if os.clock() - lastMove >= MOVEMENT_INTERVAL then
            lastMove = os.clock()

            combatMove(
                humanoid,
                root,
                sticky,
                orbitSign
            )
        end

        if os.clock() - lastAbility >= ABILITY_CHAIN_GAP then
            if castSkill("e", sticky)
                or castSkill("q", sticky)
            then
                lastAbility = os.clock()
            end
        end

        if os.clock() - lastAttack >= ATTACK_INTERVAL then
            if basicAttack(sticky) then
                lastAttack = os.clock()
            end
        end

        task.wait(0.04)
    end

    print(
        "[DQR Macro] FALLBACK | TIMEOUT | room="
        .. tostring(checkpoint and checkpoint.room or "unknown")
    )

    return false, "fallback_timeout"
end

DQR_MACRO_COMBAT = Combat
