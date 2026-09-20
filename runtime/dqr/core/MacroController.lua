-- DQR universal macro controller.
-- Intentionally independent from dungeon combat profiles and PlaceId support.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local ENV = (type(getgenv) == "function" and getgenv()) or _G
local MACRO_KEY = "__SERENITY_DQR_MACRO_V2"

local VirtualInputManager
pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)

local ROOT_DIR = "SerenityDQR"
local MACRO_DIR = ROOT_DIR .. "/macros"
local INDEX_PATH = MACRO_DIR .. "/index.json"

local SAMPLE_INTERVAL = 0.10
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
    RecordingStartedAt = 0,
    RecordConnections = {},
    RecordAccumulator = 0,
    PlayToken = 0,
    LastError = nil,
    InputPlayback = VirtualInputManager ~= nil,
    FarmBridge = nil,
    FarmWasEnabled = nil,
}

local listeners = {}
local pressedKeys = {}

local old = ENV[MACRO_KEY] or ENV.__SERENITY_DQR_MACRO_V1
if old and type(old.Destroy) == "function" then
    pcall(old.Destroy, "reexecute")
elseif old and type(old.StopAll) == "function" then
    pcall(old.StopAll, "reexecute")
end

local function emit()
    local snapshot = MacroController.Status()
    for _, fn in ipairs(listeners) do
        pcall(fn, snapshot)
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
    return tostring(name):lower():gsub("%s+", "_")
end

local function macroPath(name)
    return MACRO_DIR .. "/" .. fileKey(name) .. ".json"
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

local function saveIndex()
    if not persistentStorage then
        return
    end

    ensureFolders()

    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, {
        Schema = 2,
        Names = names(),
    })

    if ok then
        pcall(writefile, INDEX_PATH, encoded)
    end
end

local function saveMacro(macro)
    if not macro or not macro.Name then
        return false, "Invalid macro"
    end

    state.Macros[macro.Name] = macro

    if persistentStorage then
        ensureFolders()

        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, macro)
        if not ok then
            return false, tostring(encoded)
        end

        local wrote, err = pcall(writefile, macroPath(macro.Name), encoded)
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

    local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
    if decodedOk
        and type(decoded) == "table"
        and type(decoded.Events) == "table"
    then
        decoded.Name = tostring(decoded.Name or name)
        return decoded
    end

    return nil
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

    local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
    if not decodedOk
        or type(decoded) ~= "table"
        or type(decoded.Names) ~= "table"
    then
        return
    end

    for _, name in ipairs(decoded.Names) do
        local macro = loadMacroFromDisk(tostring(name))
        if macro then
            state.Macros[macro.Name] = macro
        end
    end
end

local function packCFrame(cf)
    if not cf then
        return nil
    end
    return {cf:GetComponents()}
end

local function unpackCFrame(values)
    if type(values) ~= "table" or #values < 12 then
        return nil
    end
    return CFrame.new(table.unpack(values))
end

local function liveCharacter(timeout)
    local deadline = os.clock() + (timeout or 0)

    repeat
        local character = LP.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")

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
        and type(bridge.GetEnabled) == "function"
    then
        local ok, enabled = pcall(bridge.GetEnabled)
        if ok then
            state.FarmWasEnabled = enabled == true
        end
    end

    if type(bridge.SetEnabled) == "function" then
        pcall(bridge.SetEnabled, false)
    end

    if type(bridge.StopMovement) == "function" then
        pcall(bridge.StopMovement)
    end
end

local function restoreFarm()
    if state.Recording or state.Playing or state.Auto then
        return
    end

    local bridge = state.FarmBridge
    if bridge
        and state.FarmWasEnabled ~= nil
        and type(bridge.SetEnabled) == "function"
    then
        pcall(bridge.SetEnabled, state.FarmWasEnabled)
    end

    state.FarmWasEnabled = nil
end

local function clearRecordConnections()
    for _, connection in ipairs(state.RecordConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(state.RecordConnections)
end

local movementKeys = {
    W = true,
    A = true,
    S = true,
    D = true,
}

local function pointOverMacroUI(position)
    if type(MacroController.IsPointOverUI) ~= "function" then
        return false
    end

    local ok, result = pcall(MacroController.IsPointOverUI, position)
    return ok and result == true
end

local function addEvent(macro, event)
    event.t = math.max(0, os.clock() - state.RecordingStartedAt)
    macro.Events[#macro.Events + 1] = event
end

local function recordFrame(macro)
    local _, _, root = liveCharacter(0)
    if not root then
        return
    end

    local camera = workspace.CurrentCamera
    local p = root.Position

    addEvent(macro, {
        type = "frame",
        p = {p.X, p.Y, p.Z},
        camera = camera and packCFrame(camera.CFrame) or nil,
    })
end

local function connectRecord(signal, callback)
    local connection = signal:Connect(callback)
    state.RecordConnections[#state.RecordConnections + 1] = connection
    return connection
end

local function attachRecordListeners(macro)
    state.RecordAccumulator = 0

    connectRecord(RunService.Heartbeat, function(dt)
        if not state.Recording then
            return
        end

        state.RecordAccumulator += dt

        if state.RecordAccumulator >= SAMPLE_INTERVAL then
            state.RecordAccumulator =
                state.RecordAccumulator % SAMPLE_INTERVAL
            recordFrame(macro)
        end
    end)

    connectRecord(UserInputService.InputBegan, function(input)
        if not state.Recording or UserInputService:GetFocusedTextBox() then
            return
        end

        if input.UserInputType == Enum.UserInputType.Keyboard then
            local key = input.KeyCode.Name

            if key ~= "Unknown"
                and not movementKeys[key]
                and key ~= "Space"
            then
                addEvent(macro, {
                    type = "key",
                    key = key,
                    down = true,
                })
            end

        elseif input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2
        then
            local position = UserInputService:GetMouseLocation()

            if pointOverMacroUI(position) then
                return
            end

            local camera = workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize

            if viewport and viewport.X > 0 and viewport.Y > 0 then
                addEvent(macro, {
                    type = "mouse",
                    button =
                        input.UserInputType == Enum.UserInputType.MouseButton1
                        and 0
                        or 1,
                    down = true,
                    x = position.X / viewport.X,
                    y = position.Y / viewport.Y,
                })
            end
        end
    end)

    connectRecord(UserInputService.InputEnded, function(input)
        if not state.Recording or UserInputService:GetFocusedTextBox() then
            return
        end

        if input.UserInputType == Enum.UserInputType.Keyboard then
            local key = input.KeyCode.Name

            if key ~= "Unknown"
                and not movementKeys[key]
                and key ~= "Space"
            then
                addEvent(macro, {
                    type = "key",
                    key = key,
                    down = false,
                })
            end

        elseif input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2
        then
            local position = UserInputService:GetMouseLocation()

            if pointOverMacroUI(position) then
                return
            end

            local camera = workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize

            if viewport and viewport.X > 0 and viewport.Y > 0 then
                addEvent(macro, {
                    type = "mouse",
                    button =
                        input.UserInputType == Enum.UserInputType.MouseButton1
                        and 0
                        or 1,
                    down = false,
                    x = position.X / viewport.X,
                    y = position.Y / viewport.Y,
                })
            end
        end
    end)

    local function bindHumanoid()
        local _, humanoid = liveCharacter(1)
        if not humanoid then
            return
        end

        connectRecord(humanoid.StateChanged, function(_, newState)
            if state.Recording
                and newState == Enum.HumanoidStateType.Jumping
            then
                addEvent(macro, {type = "jump"})
            end
        end)
    end

    bindHumanoid()

    connectRecord(LP.CharacterAdded, function()
        if state.Recording then
            task.delay(0.25, bindHumanoid)
        end
    end)
end

local function sendKey(keyName, down)
    if not VirtualInputManager then
        return false
    end

    local keyCode = Enum.KeyCode[keyName]
    if not keyCode then
        return false
    end

    local ok = pcall(function()
        VirtualInputManager:SendKeyEvent(
            down == true,
            keyCode,
            false,
            game
        )
    end)

    if ok then
        if down then
            pressedKeys[keyName] = true
        else
            pressedKeys[keyName] = nil
        end
    end

    return ok
end

local function releasePressedKeys()
    for key in pairs(pressedKeys) do
        sendKey(key, false)
    end
    table.clear(pressedKeys)
end

local function applyEvent(event)
    if event.type == "frame" then
        local _, humanoid = liveCharacter(2)

        if humanoid
            and type(event.p) == "table"
            and #event.p >= 3
        then
            humanoid:MoveTo(
                Vector3.new(
                    event.p[1],
                    event.p[2],
                    event.p[3]
                )
            )
        end

        if event.camera then
            local cf = unpackCFrame(event.camera)
            local camera = workspace.CurrentCamera

            if cf and camera then
                pcall(function()
                    camera.CFrame = cf
                end)
            end
        end

    elseif event.type == "jump" then
        local _, humanoid = liveCharacter(1)
        if humanoid then
            pcall(function()
                humanoid.Jump = true
            end)
        end

    elseif event.type == "key" then
        sendKey(tostring(event.key or ""), event.down == true)

    elseif event.type == "mouse" and VirtualInputManager then
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize

        if viewport and viewport.X > 0 and viewport.Y > 0 then
            local x =
                math.floor(
                    math.clamp(tonumber(event.x) or 0, 0, 1)
                    * viewport.X
                )

            local y =
                math.floor(
                    math.clamp(tonumber(event.y) or 0, 0, 1)
                    * viewport.Y
                )

            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(
                    x,
                    y,
                    tonumber(event.button) or 0,
                    event.down == true,
                    game,
                    0
                )
            end)
        end
    end
end

local function playBlocking(macro, token, loopIndex)
    if not macro
        or type(macro.Events) ~= "table"
        or #macro.Events == 0
    then
        return false, "Macro has no recorded events"
    end

    state.Playing = true
    pauseFarm()

    setStatus(
        state.Auto
        and ("Auto Macro • Loop " .. tostring(loopIndex or 1))
        or "Playing Macro"
    )

    local started = os.clock()
    local index = 1

    while state.Alive and index <= #macro.Events do
        if token ~= state.PlayToken then
            break
        end

        local event = macro.Events[index]
        local targetTime = tonumber(event.t) or 0
        local remaining = targetTime - (os.clock() - started)

        if remaining > 0 then
            task.wait(math.min(remaining, 0.03))
        else
            applyEvent(event)
            index += 1
        end
    end

    releasePressedKeys()

    local _, humanoid, root = liveCharacter(0)
    if humanoid then
        pcall(function()
            if root then
                humanoid:MoveTo(root.Position)
            end
            humanoid:Move(Vector3.zero, false)
        end)
    end

    state.Playing = false

    if token ~= state.PlayToken or not state.Alive then
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
    if state.Recording or state.Playing then
        return false, "Stop the active macro first"
    end

    local valid, err = validName(name)
    if not valid then
        setStatus("Create failed", err)
        return false, err
    end

    if state.Macros[valid] then
        local message = "A macro with that name already exists"
        setStatus("Create failed", message)
        return false, message
    end

    local macro = {
        Schema = 2,
        Name = valid,
        CreatedAt = os.time(),
        UpdatedAt = os.time(),
        Duration = 0,
        SampleInterval = SAMPLE_INTERVAL,
        UniverseId = game.GameId,
        CreatedPlaceId = game.PlaceId,
        Events = {},
    }

    local ok, saveErr = saveMacro(macro)
    if not ok then
        setStatus("Create failed", saveErr)
        return false, saveErr
    end

    state.Selected = valid
    setStatus("Macro created")
    return true, valid
end

function MacroController.Delete(name)
    if state.Recording or state.Playing or state.Auto then
        return false, "Stop recording/playback first"
    end

    name = name or state.Selected

    if not name or not state.Macros[name] then
        return false, "Select a macro"
    end

    state.Macros[name] = nil

    if persistentStorage and canDelete then
        pcall(function()
            local path = macroPath(name)

            if not canIsFile or isfile(path) then
                delfile(path)
            end
        end)
    end

    saveIndex()

    if state.Selected == name then
        local list = names()
        state.Selected = list[1]
    end

    setStatus("Macro deleted")
    return true
end

function MacroController.Select(name)
    if name and state.Macros[name] then
        state.Selected = name
        setStatus("Macro selected")
        return true
    end

    return false, "Macro not found"
end

function MacroController.StartRecording(name)
    if state.Playing or state.Auto then
        return false, "Stop playback first"
    end

    name = name or state.Selected
    local macro = name and state.Macros[name]

    if not macro then
        return false, "Create or select a macro first"
    end

    if state.Recording then
        return false, "Already recording"
    end

    macro.Events = {}
    macro.Duration = 0
    macro.UpdatedAt = os.time()
    macro.RecordedUniverseId = game.GameId
    macro.RecordedPlaceId = game.PlaceId

    state.Selected = macro.Name
    state.Recording = true
    state.RecordingStartedAt = os.clock()

    pauseFarm()
    recordFrame(macro)
    attachRecordListeners(macro)

    setStatus("Recording • move/play normally")
    return true
end

function MacroController.StopRecording(save)
    if not state.Recording then
        return false, "Not recording"
    end

    local macro =
        state.Selected
        and state.Macros[state.Selected]

    if macro then
        recordFrame(macro)
        macro.Duration =
            math.max(
                0,
                os.clock() - state.RecordingStartedAt
            )
        macro.UpdatedAt = os.time()
    end

    state.Recording = false
    clearRecordConnections()

    local ok, err = true, nil

    if save ~= false and macro then
        ok, err = saveMacro(macro)
    end

    restoreFarm()

    if ok then
        setStatus("Recording saved")
    else
        setStatus("Save failed", err)
    end

    return ok, err
end

function MacroController.PlayOnce(name)
    if state.Recording or state.Playing or state.Auto then
        return false, "Another macro action is active"
    end

    name = name or state.Selected
    local macro = name and state.Macros[name]

    if not macro then
        return false, "Select a macro"
    end

    if #macro.Events == 0 then
        return false, "Macro is empty"
    end

    state.Selected = name
    state.PlayToken += 1

    local token = state.PlayToken

    task.spawn(function()
        local ok, err = playBlocking(macro, token, 1)

        restoreFarm()

        if ok then
            setStatus("Playback complete")
        elseif err and err ~= "Stopped" then
            setStatus("Playback failed", err)
        end
    end)

    return true
end

function MacroController.SetAuto(enabled)
    enabled = enabled == true

    if enabled then
        if state.Recording or state.Playing or state.Auto then
            return false, "Stop the active macro first"
        end

        local macro =
            state.Selected
            and state.Macros[state.Selected]

        if not macro or #macro.Events == 0 then
            return false, "Select a recorded macro"
        end

        state.Auto = true
        state.PlayToken += 1

        local token = state.PlayToken

        pauseFarm()

        task.spawn(function()
            local loopIndex = 1

            while state.Alive
                and state.Auto
                and token == state.PlayToken
            do
                local selected =
                    state.Selected
                    and state.Macros[state.Selected]

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
                    or token ~= state.PlayToken
                then
                    break
                end

                loopIndex += 1

                local untilTime =
                    os.clock() + AUTO_LOOP_DELAY

                while state.Alive
                    and state.Auto
                    and token == state.PlayToken
                    and os.clock() < untilTime
                do
                    task.wait(0.05)
                end
            end

            state.Auto = false
            state.Playing = false
            restoreFarm()

            if state.Alive
                and token == state.PlayToken
            then
                setStatus("Auto Macro stopped")
            end
        end)

        emit()
        return true
    end

    if state.Auto or state.Playing then
        state.Auto = false
        state.PlayToken += 1
        state.Playing = false

        releasePressedKeys()
        restoreFarm()
        setStatus("Auto Macro stopped")
    end

    return true
end

function MacroController.StopPlayback()
    if not state.Playing and not state.Auto then
        return false
    end

    state.Auto = false
    state.PlayToken += 1
    state.Playing = false

    releasePressedKeys()
    restoreFarm()

    setStatus("Playback stopped")
    return true
end

function MacroController.Refresh()
    if persistentStorage then
        state.Macros = {}
        loadIndex()
    end

    local list = names()

    if state.Selected
        and not state.Macros[state.Selected]
    then
        state.Selected = nil
    end

    if not state.Selected then
        state.Selected = list[1]
    end

    emit()
    return list
end

function MacroController.List()
    return names()
end

function MacroController.Get(name)
    return state.Macros[name or state.Selected]
end

function MacroController.Status()
    local selected =
        state.Selected
        and state.Macros[state.Selected]

    return {
        Selected = state.Selected,
        Recording = state.Recording,
        Playing = state.Playing,
        Auto = state.Auto,
        Status = state.Status,
        Storage = state.Storage,
        InputPlayback = state.InputPlayback,
        Duration =
            state.Recording
            and math.max(
                0,
                os.clock() - state.RecordingStartedAt
            )
            or (
                selected
                and tonumber(selected.Duration)
                or 0
            ),
        Events =
            selected
            and #selected.Events
            or 0,
        Count = #names(),
        Error = state.LastError,
        FarmAttached = state.FarmBridge ~= nil,
        UniverseId = game.GameId,
        PlaceId = game.PlaceId,
    }
end

function MacroController.OnChanged(callback)
    if type(callback) ~= "function" then
        return function() end
    end

    listeners[#listeners + 1] = callback
    local alive = true

    return function()
        if not alive then
            return
        end

        alive = false

        for i = #listeners, 1, -1 do
            if listeners[i] == callback then
                table.remove(listeners, i)
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
        pcall(MacroController.StopRecording, true)
    end

    state.Auto = false
    state.PlayToken += 1
    state.Playing = false

    clearRecordConnections()
    releasePressedKeys()
    restoreFarm()

    setStatus(
        reason
        and ("Stopped • " .. tostring(reason))
        or "Stopped"
    )
end

function MacroController.Destroy(reason)
    if not state.Alive then
        return
    end

    MacroController.StopAll(reason or "destroy")
    state.Alive = false
    listeners = {}

    if ENV[MACRO_KEY] == MacroController then
        ENV[MACRO_KEY] = nil
    end

    if ENV.DQRMacro == MacroController then
        ENV.DQRMacro = nil
    end
end

loadIndex()
MacroController.Refresh()

ENV[MACRO_KEY] = MacroController
ENV.DQRMacro = MacroController

-- Expose into the shared bootstrap environment too.
DQR_MACRO = MacroController
