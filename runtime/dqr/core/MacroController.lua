-- DQR universal semantic macro controller.
--
-- Records:
--   * character route (adaptive / low-overhead)
--   * jumps
--   * basic weapon attacks
--   * Q/E ability casts
--
-- It intentionally does NOT record the screen, camera, mouse coordinates,
-- raw keyboard input, or UI interaction.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G
local MACRO_KEY = "__SERENITY_DQR_MACRO_V4"

local ROOT_DIR = "SerenityDQR"
local MACRO_DIR = ROOT_DIR .. "/macros"
local INDEX_PATH = MACRO_DIR .. "/index.json"

-- ------------------------------------------------------------
-- Recording
-- ------------------------------------------------------------
-- Heartbeat only checks position at this interval. It writes nothing unless
-- distance, vertical movement, or a meaningful turn warrants a new waypoint.
local SAMPLE_CHECK_INTERVAL = 0.065
local SAMPLE_MIN_DISTANCE = 2.20
local SAMPLE_CORNER_MIN_DISTANCE = 0.70
local SAMPLE_CORNER_DOT = 0.90
local SAMPLE_VERTICAL_TRIGGER = 0.65

-- An action always forces one exact movement sample immediately beforehand.
local ACTION_DEDUPE_WINDOW = 0.10
local SKILL_ANIMATION_DEDUPE_WINDOW = 0.18

-- ------------------------------------------------------------
-- Playback
-- ------------------------------------------------------------
local WAYPOINT_REACH_RADIUS = 3.0
local WAYPOINT_VERTICAL_RADIUS = 5.0
local ROUTE_LOOKAHEAD_POINTS = 2
local STUCK_CHECK_INTERVAL = 0.12
local STUCK_WINDOW = 0.70
local STUCK_PROGRESS_EPSILON = 0.45
local WAYPOINT_TIMEOUT_MIN = 0.55
local WAYPOINT_TIMEOUT_MAX = 4.0
local AUTO_LOOP_DELAY = 0.75
local SKILL_READY_GRACE = 0.55

local canRead = type(readfile) == "function"
local canWrite = type(writefile) == "function"
local canDelete = type(delfile) == "function"
local canFolder = type(makefolder) == "function"
local canIsFolder = type(isfolder) == "function"
local canIsFile = type(isfile) == "function"
local persistentStorage = canRead and canWrite

local MacroController = {}

local state = {
    Alive = true,

    Macros = {},
    Selected = nil,

    Recording = false,
    Playing = false,
    Auto = false,

    Status = "Idle",
    Storage = persistentStorage and "Persistent" or "Session only",
    LastError = nil,
    LastAction = "None",

    RecordingStartedAt = 0,
    RecordConnections = {},
    RecordAccumulator = 0,

    LastSamplePosition = nil,
    PreviousSamplePosition = nil,
    LastSampleAt = -math.huge,

    LastSkillRecordedAt = -math.huge,
    LastAttackRecordedAt = -math.huge,

    WatchedAbilityTools = {},

    PlayToken = 0,

    FarmBridge = nil,
    FarmWasEnabled = nil,
}

local listeners = {}

local old =
    ENV[MACRO_KEY]
    or ENV.__SERENITY_DQR_MACRO_V3
    or ENV.__SERENITY_DQR_MACRO_V2
    or ENV.__SERENITY_DQR_MACRO_V1

if old and type(old.Destroy) == "function" then
    pcall(old.Destroy, "reexecute")
elseif old and type(old.StopAll) == "function" then
    pcall(old.StopAll, "reexecute")
end

-- ------------------------------------------------------------
-- Common
-- ------------------------------------------------------------

local function emit()
    local snapshot = MacroController.Status()

    for _, callback in ipairs(listeners) do
        pcall(callback, snapshot)
    end
end

local function setStatus(value, err)
    state.Status = tostring(value or "Idle")
    state.LastError = err and tostring(err) or nil
    emit()
end

local function actionLog(phase, kind, fields)
    fields = fields or {}

    local chunks = {
        "[DQR Macro]",
        tostring(phase),
        tostring(kind),
    }

    for key, value in pairs(fields) do
        chunks[#chunks + 1] =
            tostring(key) .. "=" .. tostring(value)
    end

    print(table.concat(chunks, " | "))
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function validName(name)
    name = trim(name)

    if #name < 1 then
        return nil, "Enter a macro name"
    end

    if #name > 32 then
        return nil, "Macro name is limited to 32 characters"
    end

    if not name:match("^[%w _%-]+$") then
        return nil, "Use letters, numbers, spaces, _ or -"
    end

    return name
end

local function fileKey(name)
    return tostring(name)
        :lower()
        :gsub("%s+", "_")
end

local function macroPath(name)
    return
        MACRO_DIR
        .. "/"
        .. fileKey(name)
        .. ".json"
end

local function ensureFolders()
    if not persistentStorage or not canFolder then
        return
    end

    pcall(function()
        if not canIsFolder or not isfolder(ROOT_DIR) then
            makefolder(ROOT_DIR)
        end
    end)

    pcall(function()
        if not canIsFolder or not isfolder(MACRO_DIR) then
            makefolder(MACRO_DIR)
        end
    end)
end

local function names()
    local list = {}

    for name in pairs(state.Macros) do
        list[#list + 1] = name
    end

    table.sort(list, function(a, b)
        return string.lower(a) < string.lower(b)
    end)

    return list
end

local function liveCharacter(timeout)
    local deadline = os.clock() + (timeout or 0)

    repeat
        local character = LP.Character

        local humanoid =
            character
            and character:FindFirstChildOfClass(
                "Humanoid"
            )

        local root =
            character
            and character:FindFirstChild(
                "HumanoidRootPart"
            )

        if character
            and humanoid
            and humanoid.Health > 0
            and root
        then
            return character, humanoid, root
        end

        task.wait(0.04)
    until os.clock() >= deadline

    return nil, nil, nil
end

local function eventTime()
    return
        math.max(
            0,
            os.clock()
            - state.RecordingStartedAt
        )
end

local function addEvent(macro, event)
    event.t = eventTime()
    macro.Events[#macro.Events + 1] = event
end

local function captureLook()
    local _, _, root = liveCharacter(0)

    if not root then
        return nil
    end

    local look = root.CFrame.LookVector
    local flat =
        Vector3.new(
            look.X,
            0,
            look.Z
        )

    if flat.Magnitude < 0.001 then
        return nil
    end

    flat = flat.Unit

    return {
        flat.X,
        flat.Z,
    }
end

local function faceRecordedDirection(event)
    if not event
        or type(event.look) ~= "table"
        or #event.look < 2
    then
        return
    end

    local _, humanoid, root =
        liveCharacter(0)

    if not humanoid or not root then
        return
    end

    local direction =
        Vector3.new(
            tonumber(event.look[1]) or 0,
            0,
            tonumber(event.look[2]) or 0
        )

    if direction.Magnitude < 0.001 then
        return
    end

    direction = direction.Unit

    -- Rotation only. Position is preserved exactly.
    pcall(function()
        root.CFrame =
            CFrame.lookAt(
                root.Position,
                root.Position + direction
            )
    end)
end

-- ------------------------------------------------------------
-- Persistence + migration
-- ------------------------------------------------------------

local function sanitizeMacro(macro, fallbackName)
    if type(macro) ~= "table" then
        return nil
    end

    local source =
        type(macro.Events) == "table"
        and macro.Events
        or {}

    local events = {}

    for _, event in ipairs(source) do
        if type(event) == "table"
            and (
                event.type == "move"
                or event.type == "frame"
            )
            and type(event.p) == "table"
            and #event.p >= 3
        then
            events[#events + 1] = {
                type = "move",
                t = tonumber(event.t) or 0,
                p = {
                    tonumber(event.p[1]) or 0,
                    tonumber(event.p[2]) or 0,
                    tonumber(event.p[3]) or 0,
                },
            }

        elseif type(event) == "table"
            and event.type == "jump"
        then
            events[#events + 1] = {
                type = "jump",
                t = tonumber(event.t) or 0,
            }

        elseif type(event) == "table"
            and event.type == "attack"
        then
            events[#events + 1] = {
                type = "attack",
                t = tonumber(event.t) or 0,
                animation = event.animation,
                look = event.look,
            }

        elseif type(event) == "table"
            and event.type == "skill"
        then
            local slot =
                string.lower(
                    tostring(event.slot or "")
                )

            if slot == "q" or slot == "e" then
                events[#events + 1] = {
                    type = "skill",
                    t = tonumber(event.t) or 0,
                    slot = slot,
                    name = tostring(event.name or ""),
                    look = event.look,
                }
            end
        end
    end

    table.sort(events, function(a, b)
        return (a.t or 0) < (b.t or 0)
    end)

    macro.Schema = 4
    macro.Mode = "RouteCombatSemantic"
    macro.Name =
        tostring(
            macro.Name
            or fallbackName
            or "Macro"
        )

    macro.Events = events
    macro.SampleInterval = nil

    return macro
end

local function saveIndex()
    if not persistentStorage then
        return
    end

    ensureFolders()

    local ok, encoded =
        pcall(
            HttpService.JSONEncode,
            HttpService,
            {
                Schema = 4,
                Names = names(),
            }
        )

    if ok then
        pcall(writefile, INDEX_PATH, encoded)
    end
end

local function saveMacro(macro)
    macro =
        sanitizeMacro(
            macro,
            macro and macro.Name
        )

    if not macro or not macro.Name then
        return false, "Invalid macro"
    end

    state.Macros[macro.Name] = macro

    if persistentStorage then
        ensureFolders()

        local ok, encoded =
            pcall(
                HttpService.JSONEncode,
                HttpService,
                macro
            )

        if not ok then
            return false, tostring(encoded)
        end

        local wrote, err =
            pcall(
                writefile,
                macroPath(macro.Name),
                encoded
            )

        if not wrote then
            return false, tostring(err)
        end

        saveIndex()
    end

    return true
end

local function loadMacroFromDisk(name)
    if not persistentStorage then
        return nil
    end

    local path = macroPath(name)

    if canIsFile then
        local ok, exists = pcall(isfile, path)

        if not ok or not exists then
            return nil
        end
    end

    local ok, raw = pcall(readfile, path)

    if not ok then
        return nil
    end

    local decodedOk, decoded =
        pcall(
            HttpService.JSONDecode,
            HttpService,
            raw
        )

    if not decodedOk then
        return nil
    end

    return sanitizeMacro(decoded, name)
end

local function loadIndex()
    if not persistentStorage then
        return
    end

    ensureFolders()

    if canIsFile then
        local ok, exists = pcall(isfile, INDEX_PATH)

        if not ok or not exists then
            return
        end
    end

    local ok, raw = pcall(readfile, INDEX_PATH)

    if not ok then
        return
    end

    local decodedOk, decoded =
        pcall(
            HttpService.JSONDecode,
            HttpService,
            raw
        )

    if not decodedOk
        or type(decoded) ~= "table"
        or type(decoded.Names) ~= "table"
    then
        return
    end

    for _, name in ipairs(decoded.Names) do
        local macro =
            loadMacroFromDisk(
                tostring(name)
            )

        if macro then
            state.Macros[macro.Name] = macro
        end
    end
end

-- ------------------------------------------------------------
-- Auto Farm bridge
-- ------------------------------------------------------------

local function pauseFarm()
    local bridge = state.FarmBridge

    if not bridge then
        return
    end

    if state.FarmWasEnabled == nil
        and type(bridge.GetEnabled)
            == "function"
    then
        local ok, enabled =
            pcall(bridge.GetEnabled)

        if ok then
            state.FarmWasEnabled =
                enabled == true
        end
    end

    if type(bridge.SetEnabled) == "function" then
        pcall(
            bridge.SetEnabled,
            false
        )
    end

    if type(bridge.StopMovement) == "function" then
        pcall(bridge.StopMovement)
    end
end

local function restoreFarm()
    if state.Recording
        or state.Playing
        or state.Auto
    then
        return
    end

    local bridge = state.FarmBridge

    if bridge
        and state.FarmWasEnabled ~= nil
        and type(bridge.SetEnabled)
            == "function"
    then
        pcall(
            bridge.SetEnabled,
            state.FarmWasEnabled
        )
    end

    state.FarmWasEnabled = nil
end

-- ------------------------------------------------------------
-- Recording: movement
-- ------------------------------------------------------------

local function clearRecordConnections()
    for _, connection in ipairs(
        state.RecordConnections
    ) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(state.RecordConnections)
    state.WatchedAbilityTools = {}
end

local function connectRecord(signal, callback)
    local connection =
        signal:Connect(callback)

    state.RecordConnections[
        #state.RecordConnections + 1
    ] = connection

    return connection
end

local function shouldRecordMove(position, force)
    if force
        or not state.LastSamplePosition
    then
        return true
    end

    local delta =
        position
        - state.LastSamplePosition

    local distance = delta.Magnitude

    if math.abs(delta.Y)
        >= SAMPLE_VERTICAL_TRIGGER
    then
        return true
    end

    if distance >= SAMPLE_MIN_DISTANCE then
        return true
    end

    local previous =
        state.PreviousSamplePosition

    if previous
        and distance
            >= SAMPLE_CORNER_MIN_DISTANCE
    then
        local oldVector =
            state.LastSamplePosition
            - previous

        local newVector =
            position
            - state.LastSamplePosition

        local oldFlat =
            Vector3.new(
                oldVector.X,
                0,
                oldVector.Z
            )

        local newFlat =
            Vector3.new(
                newVector.X,
                0,
                newVector.Z
            )

        if oldFlat.Magnitude > 0.15
            and newFlat.Magnitude > 0.15
        then
            local dot =
                oldFlat.Unit:Dot(
                    newFlat.Unit
                )

            if dot <= SAMPLE_CORNER_DOT then
                return true
            end
        end
    end

    return false
end

local function recordMove(macro, force)
    local _, _, root =
        liveCharacter(0)

    if not root then
        return false
    end

    local position = root.Position

    if not shouldRecordMove(
        position,
        force
    ) then
        return false
    end

    -- Do not write duplicate forced samples at the exact same point.
    if state.LastSamplePosition
        and (
            position
            - state.LastSamplePosition
        ).Magnitude < 0.06
        and force
    then
        return false
    end

    addEvent(
        macro,
        {
            type = "move",
            p = {
                position.X,
                position.Y,
                position.Z,
            },
        }
    )

    state.PreviousSamplePosition =
        state.LastSamplePosition

    state.LastSamplePosition =
        position

    state.LastSampleAt =
        os.clock()

    return true
end

-- ------------------------------------------------------------
-- Recording: semantic combat
-- ------------------------------------------------------------

local function abilitySlotOf(tool)
    if not tool
        or not tool:IsA("Tool")
    then
        return nil
    end

    local slotValue =
        tool:FindFirstChild(
            "abilitySlot"
        )

    if not slotValue then
        return nil
    end

    local slot =
        string.lower(
            tostring(slotValue.Value)
        )

    if slot == "q"
        or slot == "e"
    then
        return slot
    end

    return nil
end

local function recordSkill(macro, slot, tool)
    local now = os.clock()

    if now - state.LastSkillRecordedAt
        < ACTION_DEDUPE_WINDOW
    then
        return
    end

    state.LastSkillRecordedAt = now

    recordMove(
        macro,
        true
    )

    local event = {
        type = "skill",
        slot = slot,
        name = tool and tool.Name or "",
        look = captureLook(),
    }

    addEvent(macro, event)

    state.LastAction =
        "Skill "
        .. string.upper(slot)
        .. (
            tool
            and (" • " .. tool.Name)
            or ""
        )

    actionLog(
        "REC",
        "SKILL",
        {
            slot = slot,
            name = tool and tool.Name or "unknown",
            t = string.format("%.3f", event.t),
        }
    )

    emit()
end

local function watchAbilityTool(macro, tool)
    if not tool
        or state.WatchedAbilityTools[tool]
    then
        return
    end

    local slot =
        abilitySlotOf(tool)

    if not slot then
        return
    end

    state.WatchedAbilityTools[tool] =
        true

    local cooldown =
        tool:FindFirstChild(
            "cooldown"
        )

    if not cooldown then
        return
    end

    local lastValue =
        tonumber(cooldown.Value)
        or 0

    connectRecord(
        cooldown:GetPropertyChangedSignal(
            "Value"
        ),
        function()
            if not state.Recording then
                return
            end

            local value =
                tonumber(cooldown.Value)
                or 0

            -- A cast starts when cooldown transitions from ready to positive,
            -- or sharply resets upward for games that never expose exact zero.
            local started =
                value > 0
                and (
                    lastValue <= 0
                    or value
                        > lastValue + 0.20
                )

            lastValue = value

            if started then
                recordSkill(
                    macro,
                    slot,
                    tool
                )
            end
        end
    )
end

local function scanAbilityTools(macro)
    local backpack =
        LP:FindFirstChild("Backpack")

    local character =
        LP.Character

    for _, container in ipairs({
        backpack,
        character,
    }) do
        if container then
            for _, child in ipairs(
                container:GetChildren()
            ) do
                watchAbilityTool(
                    macro,
                    child
                )
            end
        end
    end
end

local function hasWeaponAccessory()
    local character =
        LP.Character

    if not character then
        return false
    end

    for _, instance in ipairs(
        character:GetChildren()
    ) do
        if instance:IsA("Accessory")
            and instance:FindFirstChild(
                "Weapon"
            )
            and instance:FindFirstChildOfClass(
                "RemoteEvent"
            )
        then
            return true
        end
    end

    return false
end

local ACTION_PRIORITIES = {
    [Enum.AnimationPriority.Action] = true,
    [Enum.AnimationPriority.Action2] = true,
    [Enum.AnimationPriority.Action3] = true,
    [Enum.AnimationPriority.Action4] = true,
}

local function recordAttackFromAnimation(
    macro,
    track
)
    if not state.Recording
        or not hasWeaponAccessory()
    then
        return
    end

    if not ACTION_PRIORITIES[
        track.Priority
    ] then
        return
    end

    local startedAt = os.clock()
    local animationId = ""

    pcall(function()
        animationId =
            track.Animation
            and track.Animation.AnimationId
            or ""
    end)

    -- Ability animations also use Action priority. Delay classification very
    -- briefly so a Q/E cooldown transition can claim the same animation first.
    task.delay(
        0.07,
        function()
            if not state.Recording then
                return
            end

            if os.clock()
                - state.LastSkillRecordedAt
                <= SKILL_ANIMATION_DEDUPE_WINDOW
            then
                return
            end

            if startedAt
                <= state.LastAttackRecordedAt
                    + ACTION_DEDUPE_WINDOW
            then
                return
            end

            state.LastAttackRecordedAt =
                startedAt

            recordMove(
                macro,
                true
            )

            local event = {
                type = "attack",
                animation = animationId,
                look = captureLook(),
            }

            addEvent(macro, event)

            state.LastAction =
                animationId ~= ""
                and (
                    "Basic Attack • "
                    .. animationId
                )
                or "Basic Attack"

            actionLog(
                "REC",
                "ATTACK",
                {
                    animation =
                        animationId ~= ""
                        and animationId
                        or "unknown",
                    t =
                        string.format(
                            "%.3f",
                            event.t
                        ),
                }
            )

            emit()
        end
    )
end

local function bindCombatObservers(macro)
    local boundAnimator

    local function bindCharacter()
        local character, humanoid =
            liveCharacter(1)

        if not character
            or not humanoid
        then
            return
        end

        local animator =
            humanoid:FindFirstChildOfClass(
                "Animator"
            )

        if animator
            and animator ~= boundAnimator
        then
            boundAnimator = animator

            connectRecord(
                animator.AnimationPlayed,
                function(track)
                    recordAttackFromAnimation(
                        macro,
                        track
                    )
                end
            )
        end

        connectRecord(
            character.ChildAdded,
            function(child)
                if state.Recording then
                    watchAbilityTool(
                        macro,
                        child
                    )
                end
            end
        )
    end

    local backpack =
        LP:FindFirstChild("Backpack")

    if backpack then
        connectRecord(
            backpack.ChildAdded,
            function(child)
                if state.Recording then
                    watchAbilityTool(
                        macro,
                        child
                    )
                end
            end
        )
    end

    bindCharacter()
    scanAbilityTools(macro)

    connectRecord(
        LP.CharacterAdded,
        function()
            if state.Recording then
                task.delay(
                    0.20,
                    function()
                        if state.Recording then
                            bindCharacter()
                            scanAbilityTools(
                                macro
                            )
                        end
                    end
                )
            end
        end
    )
end

local function attachRecordListeners(macro)
    state.RecordAccumulator = 0

    connectRecord(
        RunService.Heartbeat,
        function(dt)
            if not state.Recording then
                return
            end

            state.RecordAccumulator += dt

            if state.RecordAccumulator
                >= SAMPLE_CHECK_INTERVAL
            then
                state.RecordAccumulator =
                    state.RecordAccumulator
                    % SAMPLE_CHECK_INTERVAL

                recordMove(
                    macro,
                    false
                )
            end
        end
    )

    local boundHumanoid

    local function bindJump()
        local _, humanoid =
            liveCharacter(1)

        if not humanoid
            or humanoid == boundHumanoid
        then
            return
        end

        boundHumanoid = humanoid

        connectRecord(
            humanoid.StateChanged,
            function(_, newState)
                if not state.Recording then
                    return
                end

                if newState
                    == Enum.HumanoidStateType.Jumping
                then
                    recordMove(
                        macro,
                        true
                    )

                    local event = {
                        type = "jump",
                    }

                    addEvent(
                        macro,
                        event
                    )

                    state.LastAction =
                        "Jump"
                end
            end
        )
    end

    bindJump()
    bindCombatObservers(macro)

    connectRecord(
        LP.CharacterAdded,
        function()
            if state.Recording then
                task.delay(
                    0.20,
                    bindJump
                )
            end
        end
    )
end

-- ------------------------------------------------------------
-- Playback helpers
-- ------------------------------------------------------------

local function vectorFromEvent(event)
    if not event
        or type(event.p) ~= "table"
        or #event.p < 3
    then
        return nil
    end

    return Vector3.new(
        tonumber(event.p[1]) or 0,
        tonumber(event.p[2]) or 0,
        tonumber(event.p[3]) or 0
    )
end

local function reached(root, target)
    local delta =
        root.Position - target

    local horizontal =
        Vector3.new(
            delta.X,
            0,
            delta.Z
        ).Magnitude

    return
        horizontal <= WAYPOINT_REACH_RADIUS
        and math.abs(delta.Y)
            <= WAYPOINT_VERTICAL_RADIUS
end

local function stopHumanoid()
    local _, humanoid, root =
        liveCharacter(0)

    if humanoid then
        pcall(function()
            if root then
                humanoid:MoveTo(
                    root.Position
                )
            end

            humanoid:Move(
                Vector3.zero,
                false
            )
        end)
    end
end

local function routeMoveTo(target, token)
    local _, humanoid, root =
        liveCharacter(2)

    if not humanoid or not root then
        return false, "Character unavailable"
    end

    local distance =
        (root.Position - target).Magnitude

    local walkSpeed =
        math.max(
            tonumber(humanoid.WalkSpeed)
            or 16,
            1
        )

    local timeout =
        math.clamp(
            distance / walkSpeed
                * 2.15
                + 0.45,
            WAYPOINT_TIMEOUT_MIN,
            WAYPOINT_TIMEOUT_MAX
        )

    local deadline =
        os.clock() + timeout

    local bestDistance =
        distance

    local lastProgressAt =
        os.clock()

    local lastCommandAt =
        -math.huge

    while state.Alive
        and token == state.PlayToken
        and os.clock() < deadline
    do
        local _, liveHumanoid, liveRoot =
            liveCharacter(0)

        if not liveHumanoid
            or not liveRoot
        then
            task.wait(0.035)
            continue
        end

        humanoid = liveHumanoid
        root = liveRoot

        if reached(root, target) then
            return true
        end

        distance =
            (root.Position - target).Magnitude

        if distance
            < bestDistance
                - STUCK_PROGRESS_EPSILON
        then
            bestDistance = distance
            lastProgressAt = os.clock()
        end

        if os.clock() - lastCommandAt
            >= STUCK_CHECK_INTERVAL
        then
            lastCommandAt = os.clock()

            pcall(function()
                humanoid:MoveTo(
                    target
                )
            end)
        end

        if os.clock() - lastProgressAt
            >= STUCK_WINDOW
        then
            -- Ordinary recovery only. No positional CFrame teleport.
            pcall(function()
                humanoid.Jump = true
                humanoid:MoveTo(
                    target
                )
            end)

            lastProgressAt =
                os.clock()

            bestDistance =
                distance
        end

        task.wait(0.03)
    end

    return false, "waypoint_timeout"
end

local function abilityTool(slot, preferredName)
    local backpack =
        LP:FindFirstChild("Backpack")

    local character =
        LP.Character

    local fallback

    for _, container in ipairs({
        backpack,
        character,
    }) do
        if container then
            for _, child in ipairs(
                container:GetChildren()
            ) do
                local childSlot =
                    abilitySlotOf(child)

                if childSlot == slot then
                    if preferredName
                        and preferredName ~= ""
                        and child.Name
                            == preferredName
                    then
                        return child
                    end

                    fallback =
                        fallback or child
                end
            end
        end
    end

    return fallback
end

local function replaySkill(event)
    local slot =
        string.lower(
            tostring(event.slot or "")
        )

    if slot ~= "q"
        and slot ~= "e"
    then
        return false, "invalid_slot"
    end

    local tool =
        abilityTool(
            slot,
            event.name
        )

    if not tool then
        actionLog(
            "PLAY",
            "SKILL_SKIP",
            {
                slot = slot,
                reason = "tool_missing",
            }
        )

        return false, "tool_missing"
    end

    local cooldown =
        tool:FindFirstChild(
            "cooldown"
        )

    local readyDeadline =
        os.clock()
        + SKILL_READY_GRACE

    while cooldown
        and tonumber(cooldown.Value)
        and cooldown.Value > 0
        and os.clock() < readyDeadline
    do
        task.wait(0.03)
    end

    if cooldown
        and tonumber(cooldown.Value)
        and cooldown.Value > 0
    then
        actionLog(
            "PLAY",
            "SKILL_SKIP",
            {
                slot = slot,
                name = tool.Name,
                reason = "cooldown",
            }
        )

        return false, "cooldown"
    end

    local localEvent =
        tool:FindFirstChild(
            "localEvent"
        )

    if not localEvent then
        return false, "localEvent_missing"
    end

    faceRecordedDirection(
        event
    )

    pcall(function()
        localEvent:Fire()
    end)

    local remotes =
        ReplicatedStorage
        :FindFirstChild("remotes")

    local abilityUsed =
        remotes
        and remotes:FindFirstChild(
            "abilityUsed"
        )

    if abilityUsed
        and abilityUsed:IsA(
            "RemoteEvent"
        )
    then
        pcall(function()
            abilityUsed:FireServer(
                slot,
                tool
            )
        end)
    end

    state.LastAction =
        "Skill "
        .. string.upper(slot)
        .. " • "
        .. tool.Name

    actionLog(
        "PLAY",
        "SKILL",
        {
            slot = slot,
            name = tool.Name,
        }
    )

    return true
end

local function equippedWeaponEvent()
    local character =
        LP.Character

    if not character then
        return nil
    end

    for _, instance in ipairs(
        character:GetChildren()
    ) do
        if instance:IsA("Accessory")
            and instance:FindFirstChild(
                "Weapon"
            )
        then
            local remote =
                instance:FindFirstChildOfClass(
                    "RemoteEvent"
                )

            if remote then
                return remote
            end
        end
    end

    return nil
end

local function replayAttack(event)
    local weaponEvent =
        equippedWeaponEvent()

    if not weaponEvent then
        actionLog(
            "PLAY",
            "ATTACK_SKIP",
            {
                reason = "weapon_remote_missing",
            }
        )

        return false, "weapon_remote_missing"
    end

    faceRecordedDirection(
        event
    )

    pcall(function()
        weaponEvent:FireServer()
    end)

    local remotes =
        ReplicatedStorage
        :FindFirstChild("remotes")

    local weaponUsed =
        remotes
        and remotes:FindFirstChild(
            "weaponUsed"
        )

    if weaponUsed
        and weaponUsed:IsA(
            "RemoteEvent"
        )
    then
        pcall(function()
            weaponUsed:FireServer()
        end)
    end

    state.LastAction =
        "Basic Attack"

    actionLog(
        "PLAY",
        "ATTACK",
        {
            animation =
                tostring(
                    event.animation
                    or "unknown"
                ),
        }
    )

    return true
end

-- ------------------------------------------------------------
-- Playback
-- ------------------------------------------------------------

local function straightEnoughForLookahead(events, fromIndex, toIndex)
    local a = vectorFromEvent(events[fromIndex])
    local b = vectorFromEvent(events[fromIndex + 1])
    local c = vectorFromEvent(events[toIndex])

    if not a or not b or not c then
        return false
    end

    local first =
        Vector3.new(
            b.X - a.X,
            0,
            b.Z - a.Z
        )

    local combined =
        Vector3.new(
            c.X - a.X,
            0,
            c.Z - a.Z
        )

    if first.Magnitude < 0.15
        or combined.Magnitude < 0.15
    then
        return true
    end

    return
        first.Unit:Dot(
            combined.Unit
        ) >= 0.94
end

local function playBlocking(macro, token, loopIndex)
    macro =
        sanitizeMacro(
            macro,
            macro and macro.Name
        )

    if not macro
        or type(macro.Events) ~= "table"
        or #macro.Events == 0
    then
        return false, "Macro has no events"
    end

    state.Playing = true
    pauseFarm()

    setStatus(
        state.Auto
        and (
            "Auto Macro • Loop "
            .. tostring(loopIndex or 1)
        )
        or "Playing Macro"
    )

    local events = macro.Events
    local index = 1

    while state.Alive
        and token == state.PlayToken
        and index <= #events
    do
        local event =
            events[index]

        if event.type == "move" then
            local targetIndex =
                index

            -- Small geometric lookahead keeps MoveTo from stopping at every
            -- dense recorded point. Never look through an action/jump event.
            for step = 1, ROUTE_LOOKAHEAD_POINTS do
                local candidateIndex =
                    targetIndex + 1

                local candidate =
                    events[candidateIndex]

                if not candidate
                    or candidate.type
                        ~= "move"
                    or not straightEnoughForLookahead(
                        events,
                        index,
                        candidateIndex
                    )
                then
                    break
                end

                targetIndex =
                    candidateIndex
            end

            local target =
                vectorFromEvent(
                    events[targetIndex]
                )

            if target then
                routeMoveTo(
                    target,
                    token
                )
            end

            index =
                targetIndex + 1

        elseif event.type == "jump" then
            local _, humanoid =
                liveCharacter(0)

            if humanoid then
                pcall(function()
                    humanoid.Jump = true
                end)
            end

            state.LastAction =
                "Jump"

            index += 1

        elseif event.type == "attack" then
            replayAttack(event)
            index += 1

        elseif event.type == "skill" then
            replaySkill(event)
            index += 1

        else
            index += 1
        end
    end

    stopHumanoid()
    state.Playing = false

    if token ~= state.PlayToken
        or not state.Alive
    then
        return false, "Stopped"
    end

    return true
end

-- ------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------

function MacroController.AttachFarm(bridge)
    state.FarmBridge =
        type(bridge) == "table"
        and bridge
        or nil

    emit()
end

function MacroController.Create(name)
    if state.Recording
        or state.Playing
    then
        return false, "Stop the active macro first"
    end

    local valid, err =
        validName(name)

    if not valid then
        setStatus(
            "Create failed",
            err
        )

        return false, err
    end

    if state.Macros[valid] then
        local message =
            "A macro with that name already exists"

        setStatus(
            "Create failed",
            message
        )

        return false, message
    end

    local macro = {
        Schema = 4,
        Mode = "RouteCombatSemantic",

        Name = valid,
        CreatedAt = os.time(),
        UpdatedAt = os.time(),
        Duration = 0,

        UniverseId = game.GameId,
        CreatedPlaceId = game.PlaceId,

        Events = {},
    }

    local ok, saveErr =
        saveMacro(macro)

    if not ok then
        setStatus(
            "Create failed",
            saveErr
        )

        return false, saveErr
    end

    state.Selected = valid
    setStatus("Macro created")

    return true, valid
end

function MacroController.Delete(name)
    if state.Recording
        or state.Playing
        or state.Auto
    then
        return false, "Stop recording/playback first"
    end

    name =
        name
        or state.Selected

    if not name
        or not state.Macros[name]
    then
        return false, "Select a macro"
    end

    state.Macros[name] = nil

    if persistentStorage
        and canDelete
    then
        pcall(function()
            local path =
                macroPath(name)

            if not canIsFile
                or isfile(path)
            then
                delfile(path)
            end
        end)
    end

    saveIndex()

    if state.Selected == name then
        state.Selected =
            names()[1]
    end

    setStatus("Macro deleted")

    return true
end

function MacroController.Select(name)
    if name
        and state.Macros[name]
    then
        state.Selected = name
        setStatus("Macro selected")
        return true
    end

    return false, "Macro not found"
end

function MacroController.StartRecording(name)
    if state.Playing
        or state.Auto
    then
        return false, "Stop playback first"
    end

    name =
        name
        or state.Selected

    local macro =
        name
        and state.Macros[name]

    if not macro then
        return false, "Create or select a macro first"
    end

    if state.Recording then
        return false, "Already recording"
    end

    macro.Schema = 4
    macro.Mode = "RouteCombatSemantic"
    macro.Events = {}
    macro.Duration = 0
    macro.UpdatedAt = os.time()
    macro.RecordedUniverseId = game.GameId
    macro.RecordedPlaceId = game.PlaceId

    state.Selected = macro.Name

    state.Recording = true
    state.RecordingStartedAt =
        os.clock()

    state.RecordAccumulator = 0

    state.LastSamplePosition = nil
    state.PreviousSamplePosition = nil
    state.LastSampleAt = -math.huge

    state.LastSkillRecordedAt =
        -math.huge

    state.LastAttackRecordedAt =
        -math.huge

    state.LastAction = "None"

    pauseFarm()

    recordMove(
        macro,
        true
    )

    attachRecordListeners(
        macro
    )

    actionLog(
        "REC",
        "START",
        {
            macro = macro.Name,
            place = game.PlaceId,
        }
    )

    setStatus(
        "Recording route + combat"
    )

    return true
end

function MacroController.StopRecording(save)
    if not state.Recording then
        return false, "Not recording"
    end

    local macro =
        state.Selected
        and state.Macros[
            state.Selected
        ]

    if macro then
        recordMove(
            macro,
            true
        )

        macro.Duration =
            math.max(
                0,
                os.clock()
                - state.RecordingStartedAt
            )

        macro.UpdatedAt =
            os.time()
    end

    state.Recording = false

    clearRecordConnections()

    state.LastSamplePosition = nil
    state.PreviousSamplePosition = nil

    local ok, err = true, nil

    if save ~= false and macro then
        ok, err =
            saveMacro(macro)
    end

    restoreFarm()

    local counts =
        MacroController.CountEvents(
            macro
        )

    actionLog(
        "REC",
        "STOP",
        {
            macro =
                macro
                and macro.Name
                or "none",
            moves = counts.Moves,
            jumps = counts.Jumps,
            attacks = counts.Attacks,
            skills = counts.Skills,
        }
    )

    if ok then
        setStatus(
            "Macro recording saved"
        )
    else
        setStatus(
            "Save failed",
            err
        )
    end

    return ok, err
end

function MacroController.PlayOnce(name)
    if state.Recording
        or state.Playing
        or state.Auto
    then
        return false, "Another macro action is active"
    end

    name =
        name
        or state.Selected

    local macro =
        name
        and state.Macros[name]

    if not macro then
        return false, "Select a macro"
    end

    if #macro.Events == 0 then
        return false, "Macro is empty"
    end

    state.Selected = name
    state.PlayToken += 1

    local token =
        state.PlayToken

    task.spawn(function()
        local ok, err =
            playBlocking(
                macro,
                token,
                1
            )

        restoreFarm()

        if ok then
            setStatus(
                "Playback complete"
            )
        elseif err
            and err ~= "Stopped"
        then
            setStatus(
                "Playback failed",
                err
            )
        end
    end)

    return true
end

function MacroController.SetAuto(enabled)
    enabled = enabled == true

    if enabled then
        if state.Recording
            or state.Playing
            or state.Auto
        then
            return false, "Stop the active macro first"
        end

        local macro =
            state.Selected
            and state.Macros[
                state.Selected
            ]

        if not macro
            or #macro.Events == 0
        then
            return false, "Select a recorded macro"
        end

        state.Auto = true
        state.PlayToken += 1

        local token =
            state.PlayToken

        pauseFarm()

        task.spawn(function()
            local loopIndex = 1

            while state.Alive
                and state.Auto
                and token
                    == state.PlayToken
            do
                local selected =
                    state.Selected
                    and state.Macros[
                        state.Selected
                    ]

                if not selected
                    or #selected.Events == 0
                then
                    break
                end

                local ok =
                    playBlocking(
                        selected,
                        token,
                        loopIndex
                    )

                if not ok
                    or token
                        ~= state.PlayToken
                then
                    break
                end

                loopIndex += 1

                local untilTime =
                    os.clock()
                    + AUTO_LOOP_DELAY

                while state.Alive
                    and state.Auto
                    and token
                        == state.PlayToken
                    and os.clock()
                        < untilTime
                do
                    task.wait(0.05)
                end
            end

            state.Auto = false
            state.Playing = false

            restoreFarm()

            if state.Alive
                and token
                    == state.PlayToken
            then
                setStatus(
                    "Auto Macro stopped"
                )
            end
        end)

        emit()
        return true
    end

    if state.Auto
        or state.Playing
    then
        state.Auto = false
        state.PlayToken += 1
        state.Playing = false

        stopHumanoid()
        restoreFarm()

        setStatus(
            "Auto Macro stopped"
        )
    end

    return true
end

function MacroController.StopPlayback()
    if not state.Playing
        and not state.Auto
    then
        return false
    end

    state.Auto = false
    state.PlayToken += 1
    state.Playing = false

    stopHumanoid()
    restoreFarm()

    setStatus(
        "Playback stopped"
    )

    return true
end

function MacroController.Refresh()
    if persistentStorage then
        state.Macros = {}
        loadIndex()
    end

    local list = names()

    if state.Selected
        and not state.Macros[
            state.Selected
        ]
    then
        state.Selected = nil
    end

    if not state.Selected then
        state.Selected =
            list[1]
    end

    emit()

    return list
end

function MacroController.List()
    return names()
end

function MacroController.Get(name)
    return state.Macros[
        name
        or state.Selected
    ]
end

function MacroController.CountEvents(macro)
    macro =
        macro
        or MacroController.Get()

    local counts = {
        Moves = 0,
        Jumps = 0,
        Attacks = 0,
        Skills = 0,
        Total = 0,
    }

    if not macro
        or type(macro.Events)
            ~= "table"
    then
        return counts
    end

    for _, event in ipairs(
        macro.Events
    ) do
        counts.Total += 1

        if event.type == "move" then
            counts.Moves += 1
        elseif event.type == "jump" then
            counts.Jumps += 1
        elseif event.type == "attack" then
            counts.Attacks += 1
        elseif event.type == "skill" then
            counts.Skills += 1
        end
    end

    return counts
end

function MacroController.Status()
    local selected =
        state.Selected
        and state.Macros[
            state.Selected
        ]

    local counts =
        MacroController.CountEvents(
            selected
        )

    return {
        Selected = state.Selected,

        Recording = state.Recording,
        Playing = state.Playing,
        Auto = state.Auto,

        Status = state.Status,
        Storage = state.Storage,
        Mode = "Route + attacks + Q/E skills",
        LastAction = state.LastAction,

        Duration =
            state.Recording
            and math.max(
                0,
                os.clock()
                - state.RecordingStartedAt
            )
            or (
                selected
                and tonumber(
                    selected.Duration
                )
                or 0
            ),

        Events = counts.Total,
        Moves = counts.Moves,
        Jumps = counts.Jumps,
        Attacks = counts.Attacks,
        Skills = counts.Skills,

        Count = #names(),
        Error = state.LastError,

        FarmAttached =
            state.FarmBridge ~= nil,

        UniverseId = game.GameId,
        PlaceId = game.PlaceId,
    }
end

function MacroController.OnChanged(callback)
    if type(callback)
        ~= "function"
    then
        return function() end
    end

    listeners[
        #listeners + 1
    ] = callback

    local alive = true

    return function()
        if not alive then
            return
        end

        alive = false

        for i = #listeners, 1, -1 do
            if listeners[i]
                == callback
            then
                table.remove(
                    listeners,
                    i
                )
                break
            end
        end
    end
end

function MacroController.StopAll(reason)
    if not state.Alive then
        return
    end

    if state.Recording then
        pcall(
            MacroController.StopRecording,
            true
        )
    end

    state.Auto = false
    state.PlayToken += 1
    state.Playing = false

    clearRecordConnections()
    stopHumanoid()
    restoreFarm()

    setStatus(
        reason
        and (
            "Stopped • "
            .. tostring(reason)
        )
        or "Stopped"
    )
end

function MacroController.Destroy(reason)
    if not state.Alive then
        return
    end

    MacroController.StopAll(
        reason or "destroy"
    )

    state.Alive = false
    listeners = {}

    if ENV[MACRO_KEY]
        == MacroController
    then
        ENV[MACRO_KEY] = nil
    end

    if ENV.DQRMacro
        == MacroController
    then
        ENV.DQRMacro = nil
    end
end

loadIndex()
MacroController.Refresh()

ENV[MACRO_KEY] =
    MacroController

ENV.DQRMacro =
    MacroController

DQR_MACRO =
    MacroController
