-- DQR universal character-movement macro controller.
-- Records and replays only character movement + jumps. No camera, mouse,
-- keyboard, screen/UI, or ability input is captured.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G
local MACRO_KEY = "__SERENITY_DQR_MACRO_V3"

local ROOT_DIR = "SerenityDQR"
local MACRO_DIR = ROOT_DIR .. "/macros"
local INDEX_PATH = MACRO_DIR .. "/index.json"

-- Recording is distance-driven so the route stays compact without losing
-- corners. A timed keepalive preserves pauses / slow sections.
local SAMPLE_CHECK_INTERVAL = 0.05
local SAMPLE_MIN_DISTANCE = 1.25
local SAMPLE_MAX_INTERVAL = 0.30
local SAMPLE_VERTICAL_TRIGGER = 0.70

-- Playback stays on ordinary Humanoid movement.
local WAYPOINT_REACH_RADIUS = 2.35
local WAYPOINT_VERTICAL_RADIUS = 4.50
local STUCK_CHECK_INTERVAL = 0.12
local STUCK_WINDOW = 0.65
local STUCK_PROGRESS_EPSILON = 0.35
local AUTO_LOOP_DELAY = 0.75

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

    RecordingStartedAt = 0,
    RecordConnections = {},
    RecordAccumulator = 0,
    LastSamplePosition = nil,
    LastSampleAt = -math.huge,

    PlayToken = 0,

    FarmBridge = nil,
    FarmWasEnabled = nil,
}

local listeners = {}

local old =
    ENV[MACRO_KEY]
    or ENV.__SERENITY_DQR_MACRO_V2
    or ENV.__SERENITY_DQR_MACRO_V1

if old and type(old.Destroy) == "function" then
    pcall(old.Destroy, "reexecute")
elseif old and type(old.StopAll) == "function" then
    pcall(old.StopAll, "reexecute")
end

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

local function sanitizeMacro(macro, fallbackName)
    if type(macro) ~= "table" then
        return nil
    end

    local sourceEvents =
        type(macro.Events) == "table"
        and macro.Events
        or {}

    local events = {}

    -- Older schema macros are accepted, but only movement/jump information is
    -- retained. Camera/input fields are intentionally discarded.
    for _, event in ipairs(sourceEvents) do
        if type(event) == "table"
            and event.type == "frame"
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
            and event.type == "move"
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
        end
    end

    table.sort(events, function(a, b)
        return (a.t or 0) < (b.t or 0)
    end)

    macro.Schema = 3
    macro.Mode = "CharacterMovementOnly"
    macro.Name = tostring(macro.Name or fallbackName or "Macro")
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
                Schema = 3,
                Names = names(),
            }
        )

    if ok then
        pcall(writefile, INDEX_PATH, encoded)
    end
end

local function saveMacro(macro)
    macro = sanitizeMacro(macro, macro and macro.Name)

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
            state.Macros[macro.Name] =
                macro
        end
    end
end

local function liveCharacter(timeout)
    local deadline =
        os.clock() + (timeout or 0)

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

        task.wait(0.05)
    until os.clock() >= deadline

    return nil, nil, nil
end

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

local function clearRecordConnections()
    for _, connection in ipairs(
        state.RecordConnections
    ) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(
        state.RecordConnections
    )
end

local function addEvent(macro, event)
    event.t =
        math.max(
            0,
            os.clock()
            - state.RecordingStartedAt
        )

    macro.Events[#macro.Events + 1] =
        event
end

local function recordMove(macro, force)
    local _, _, root =
        liveCharacter(0)

    if not root then
        return false
    end

    local now = os.clock()
    local position = root.Position
    local last = state.LastSamplePosition

    local distance =
        last
        and (position - last).Magnitude
        or math.huge

    local vertical =
        last
        and math.abs(position.Y - last.Y)
        or math.huge

    local elapsed =
        now - state.LastSampleAt

    if not force
        and distance < SAMPLE_MIN_DISTANCE
        and vertical < SAMPLE_VERTICAL_TRIGGER
        and elapsed < SAMPLE_MAX_INTERVAL
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

    state.LastSamplePosition = position
    state.LastSampleAt = now

    return true
end

local function connectRecord(signal, callback)
    local connection =
        signal:Connect(callback)

    state.RecordConnections[
        #state.RecordConnections + 1
    ] = connection

    return connection
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

    local function bindHumanoid()
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
                    -- Capture the current movement point immediately before
                    -- the jump marker so playback jumps at the same location.
                    recordMove(
                        macro,
                        true
                    )

                    addEvent(
                        macro,
                        {
                            type = "jump",
                        }
                    )
                end
            end
        )
    end

    bindHumanoid()

    connectRecord(
        LP.CharacterAdded,
        function()
            if state.Recording then
                task.delay(
                    0.25,
                    bindHumanoid
                )
            end
        end
    )
end

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
    local delta = root.Position - target

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

local function moveToWaypoint(target, token, maxTime)
    local _, humanoid, root =
        liveCharacter(2)

    if not humanoid or not root then
        return false, "Character unavailable"
    end

    local startDistance =
        (root.Position - target).Magnitude

    local walkSpeed =
        math.max(
            tonumber(humanoid.WalkSpeed) or 16,
            1
        )

    local timeout =
        maxTime
        or math.clamp(
            startDistance / walkSpeed * 2.6 + 0.85,
            0.65,
            7.0
        )

    local deadline =
        os.clock() + timeout

    local bestDistance = startDistance
    local lastProgressAt = os.clock()
    local lastCommandAt = -math.huge

    while state.Alive
        and token == state.PlayToken
        and os.clock() < deadline
    do
        local _, liveHumanoid, liveRoot =
            liveCharacter(0)

        if not liveHumanoid
            or not liveRoot
        then
            task.wait(0.05)
            continue
        end

        humanoid = liveHumanoid
        root = liveRoot

        if reached(root, target) then
            return true
        end

        local distance =
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
                humanoid:MoveTo(target)
            end)
        end

        if os.clock() - lastProgressAt
            >= STUCK_WINDOW
        then
            -- A small ordinary jump often clears stairs, lips and low props.
            -- No CFrame correction is used.
            pcall(function()
                humanoid.Jump = true
                humanoid:MoveTo(target)
            end)

            lastProgressAt = os.clock()
            bestDistance = distance
        end

        task.wait(0.03)
    end

    -- Do not freeze the entire macro on one missed sample. The next nearby
    -- recorded waypoint often recovers the route naturally.
    return false, "waypoint_timeout"
end

local function firstMoveEvent(events)
    for _, event in ipairs(events) do
        if event.type == "move" then
            return event
        end
    end

    return nil
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
        return false, "Macro has no movement"
    end

    local first =
        firstMoveEvent(
            macro.Events
        )

    if not first then
        return false, "Macro has no movement"
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

    -- Begin from the recorded start point. This also makes repeated macros
    -- deterministic when the previous loop ends slightly off-route.
    local firstTarget =
        vectorFromEvent(first)

    if firstTarget then
        moveToWaypoint(
            firstTarget,
            token,
            nil
        )
    end

    local playbackStarted =
        os.clock()

    local previousTime = 0

    for _, event in ipairs(
        macro.Events
    ) do
        if not state.Alive
            or token ~= state.PlayToken
        then
            break
        end

        local eventTime =
            math.max(
                0,
                tonumber(event.t) or 0
            )

        if event.type == "jump" then
            local waitUntil =
                playbackStarted
                + eventTime

            while state.Alive
                and token == state.PlayToken
                and os.clock() < waitUntil
            do
                task.wait(
                    math.min(
                        0.03,
                        waitUntil - os.clock()
                    )
                )
            end

            local _, humanoid =
                liveCharacter(0)

            if humanoid then
                pcall(function()
                    humanoid.Jump = true
                end)
            end

        elseif event.type == "move" then
            local target =
                vectorFromEvent(event)

            if target then
                local segmentRecordedTime =
                    math.max(
                        0.05,
                        eventTime - previousTime
                    )

                -- Allow extra real-world time for collisions/latency while
                -- preserving the recorded path order.
                local segmentBudget =
                    math.clamp(
                        segmentRecordedTime * 2.35 + 0.35,
                        0.55,
                        4.5
                    )

                moveToWaypoint(
                    target,
                    token,
                    segmentBudget
                )

                -- If we reached this point early, preserve intentional pauses
                -- from the recording instead of racing through the macro.
                local scheduled =
                    playbackStarted
                    + eventTime

                while state.Alive
                    and token == state.PlayToken
                    and os.clock() < scheduled
                do
                    task.wait(
                        math.min(
                            0.03,
                            scheduled - os.clock()
                        )
                    )
                end

                previousTime =
                    eventTime
            end
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
        Schema = 3,
        Mode = "CharacterMovementOnly",
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

    macro.Schema = 3
    macro.Mode = "CharacterMovementOnly"
    macro.Events = {}
    macro.Duration = 0
    macro.UpdatedAt = os.time()
    macro.RecordedUniverseId = game.GameId
    macro.RecordedPlaceId = game.PlaceId

    state.Selected = macro.Name
    state.Recording = true
    state.RecordingStartedAt =
        os.clock()

    state.LastSamplePosition = nil
    state.LastSampleAt = -math.huge

    pauseFarm()

    recordMove(
        macro,
        true
    )

    attachRecordListeners(
        macro
    )

    setStatus(
        "Recording character movement"
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
    state.LastSampleAt = -math.huge

    local ok, err = true, nil

    if save ~= false and macro then
        ok, err =
            saveMacro(macro)
    end

    restoreFarm()

    if ok then
        setStatus(
            "Movement recording saved"
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

function MacroController.Status()
    local selected =
        state.Selected
        and state.Macros[
            state.Selected
        ]

    return {
        Selected = state.Selected,
        Recording = state.Recording,
        Playing = state.Playing,
        Auto = state.Auto,

        Status = state.Status,
        Storage = state.Storage,
        MovementOnly = true,

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

        Events =
            selected
            and #selected.Events
            or 0,

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
