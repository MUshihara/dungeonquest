-- DQR modular runtime: core/MacroController.lua
-- Local macro recorder/player. Keeps macro ownership separate from the farm engine.

local MacroController = {}
local MacroEnv = (type(getgenv) == "function" and getgenv()) or _G
local MACRO_KEY = "__SERENITY_DQR_MACRO_V1"
local UIS = game:GetService("UserInputService")
local MacroRunService = game:GetService("RunService")

local VIM
pcall(function()
    VIM = game:GetService("VirtualInputManager")
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

local state = {
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
    FarmWasEnabled = nil,
    LastError = nil,
    InputPlayback = VIM ~= nil,
}

local listeners = {}
local pressedKeys = {}

local old = MacroEnv[MACRO_KEY]
if old and type(old.StopAll) == "function" then
    pcall(old.StopAll, "reexecute")
end

local function emit()
    for _, fn in ipairs(listeners) do
        pcall(fn, MacroController.Status())
    end
end

local function setStatus(value, err)
    state.Status = value
    state.LastError = err
    emit()
end

local function trim(s)
    return tostring(s or ""):match("^%s*(.-)%s*$")
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

local function indexNames()
    local names = {}
    for name in pairs(state.Macros) do
        names[#names + 1] = name
    end
    table.sort(names, function(a, b)
        return string.lower(a) < string.lower(b)
    end)
    return names
end

local function saveIndex()
    if not persistentStorage then
        return
    end

    ensureFolders()
    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, {
        Schema = 1,
        Names = indexNames(),
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
    if decodedOk and type(decoded) == "table" and type(decoded.Events) == "table" then
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
    if not decodedOk or type(decoded) ~= "table" or type(decoded.Names) ~= "table" then
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
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if char and hum and hum.Health > 0 and root then
            return char, hum, root
        end
        task.wait(0.05)
    until os.clock() >= deadline
    return nil, nil, nil
end

local function pauseFarm()
    if state.FarmWasEnabled == nil then
        state.FarmWasEnabled = CFG.ENABLED
    end
    CFG.ENABLED = false

    if Runtime.Humanoid then
        pcall(function()
            if Runtime.Root then
                Runtime.Humanoid:MoveTo(Runtime.Root.Position)
            end
            Runtime.Humanoid:Move(Vector3.zero, false)
        end)
    end

    Runtime.MovementOwner = "MACRO"
end

local function restoreFarm()
    if state.Recording or state.Playing or state.Auto then
        return
    end

    if state.FarmWasEnabled ~= nil then
        CFG.ENABLED = state.FarmWasEnabled
        state.FarmWasEnabled = nil
    end

    if Runtime.MovementOwner == "MACRO" then
        Runtime.MovementOwner = "NONE"
    end
end

local function clearRecordConnections()
    for _, c in ipairs(state.RecordConnections) do
        pcall(function()
            c:Disconnect()
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

local function pointOverMacroUI(pos)
    if type(MacroController.IsPointOverUI) ~= "function" then
        return false
    end

    local ok, result = pcall(MacroController.IsPointOverUI, pos)
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

local function connectRecord(signal, fn)
    local c = signal:Connect(fn)
    state.RecordConnections[#state.RecordConnections + 1] = c
    return c
end

local function attachRecordListeners(macro)
    state.RecordAccumulator = 0

    connectRecord(MacroRunService.Heartbeat, function(dt)
        if not state.Recording then
            return
        end

        state.RecordAccumulator += dt
        if state.RecordAccumulator >= SAMPLE_INTERVAL then
            state.RecordAccumulator = state.RecordAccumulator % SAMPLE_INTERVAL
            recordFrame(macro)
        end
    end)

    connectRecord(UIS.InputBegan, function(input)
        if not state.Recording or UIS:GetFocusedTextBox() then
            return
        end

        if input.UserInputType == Enum.UserInputType.Keyboard then
            local key = input.KeyCode.Name
            if key ~= "Unknown" and not movementKeys[key] and key ~= "Space" then
                addEvent(macro, {
                    type = "key",
                    key = key,
                    down = true,
                })
            end
        elseif input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2
        then
            local pos = UIS:GetMouseLocation()
            if pointOverMacroUI(pos) then
                return
            end

            local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
            if viewport and viewport.X > 0 and viewport.Y > 0 then
                addEvent(macro, {
                    type = "mouse",
                    button = input.UserInputType == Enum.UserInputType.MouseButton1 and 0 or 1,
                    down = true,
                    x = pos.X / viewport.X,
                    y = pos.Y / viewport.Y,
                })
            end
        end
    end)

    connectRecord(UIS.InputEnded, function(input)
        if not state.Recording or UIS:GetFocusedTextBox() then
            return
        end

        if input.UserInputType == Enum.UserInputType.Keyboard then
            local key = input.KeyCode.Name
            if key ~= "Unknown" and not movementKeys[key] and key ~= "Space" then
                addEvent(macro, {
                    type = "key",
                    key = key,
                    down = false,
                })
            end
        elseif input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.MouseButton2
        then
            local pos = UIS:GetMouseLocation()
            if pointOverMacroUI(pos) then
                return
            end

            local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
            if viewport and viewport.X > 0 and viewport.Y > 0 then
                addEvent(macro, {
                    type = "mouse",
                    button = input.UserInputType == Enum.UserInputType.MouseButton1 and 0 or 1,
                    down = false,
                    x = pos.X / viewport.X,
                    y = pos.Y / viewport.Y,
                })
            end
        end
    end)

    local function bindHumanoid()
        local _, hum = liveCharacter(1)
        if not hum then
            return
        end

        connectRecord(hum.StateChanged, function(_, newState)
            if state.Recording and newState == Enum.HumanoidStateType.Jumping then
                addEvent(macro, {type = "jump"})
            end
        end)
    end

    bindHumanoid()

    connectRecord(LP.CharacterAdded, function()
        if not state.Recording then
            return
        end
        task.delay(0.25, bindHumanoid)
    end)
end

local function sendKey(keyName, down)
    if not VIM then
        return false
    end

    local keyCode = Enum.KeyCode[keyName]
    if not keyCode then
        return false
    end

    local ok = pcall(function()
        VIM:SendKeyEvent(down == true, keyCode, false, game)
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
        local _, hum = liveCharacter(2)
        if hum and type(event.p) == "table" and #event.p >= 3 then
            hum:MoveTo(Vector3.new(event.p[1], event.p[2], event.p[3]))
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
        local _, hum = liveCharacter(1)
        if hum then
            pcall(function()
                hum.Jump = true
            end)
        end

    elseif event.type == "key" then
        sendKey(tostring(event.key or ""), event.down == true)

    elseif event.type == "mouse" and VIM then
        local camera = workspace.CurrentCamera
        local viewport = camera and camera.ViewportSize
        if viewport and viewport.X > 0 and viewport.Y > 0 then
            local x = math.floor(math.clamp(tonumber(event.x) or 0, 0, 1) * viewport.X)
            local y = math.floor(math.clamp(tonumber(event.y) or 0, 0, 1) * viewport.Y)

            pcall(function()
                VIM:SendMouseButtonEvent(
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
    if not macro or type(macro.Events) ~= "table" or #macro.Events == 0 then
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

    while index <= #macro.Events do
        if token ~= state.PlayToken or not Runtime.Alive then
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

    local _, hum = liveCharacter(0)
    if hum then
        pcall(function()
            hum:Move(Vector3.zero, false)
        end)
    end

    state.Playing = false

    if token ~= state.PlayToken then
        setStatus(state.Auto and "Auto Macro stopped" or "Playback stopped")
        return false, "Stopped"
    end

    return true
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
        Schema = 1,
        Name = valid,
        CreatedAt = os.time(),
        UpdatedAt = os.time(),
        Duration = 0,
        SampleInterval = SAMPLE_INTERVAL,
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
        local names = indexNames()
        state.Selected = names[1]
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
    return false
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

    local macro = state.Selected and state.Macros[state.Selected]
    if macro then
        recordFrame(macro)
        macro.Duration = math.max(0, os.clock() - state.RecordingStartedAt)
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

        local macro = state.Selected and state.Macros[state.Selected]
        if not macro or #macro.Events == 0 then
            return false, "Select a recorded macro"
        end

        state.Auto = true
        state.PlayToken += 1
        local token = state.PlayToken
        pauseFarm()

        task.spawn(function()
            local loopIndex = 1

            while state.Auto
                and token == state.PlayToken
                and Runtime.Alive
            do
                local selected = state.Selected and state.Macros[state.Selected]
                if not selected or #selected.Events == 0 then
                    break
                end

                local ok = playBlocking(selected, token, loopIndex)
                if not ok or token ~= state.PlayToken then
                    break
                end

                loopIndex += 1

                local untilTime = os.clock() + AUTO_LOOP_DELAY
                while state.Auto
                    and token == state.PlayToken
                    and os.clock() < untilTime
                do
                    task.wait(0.05)
                end
            end

            state.Auto = false
            state.Playing = false
            restoreFarm()

            if token == state.PlayToken then
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

    local names = indexNames()
    if state.Selected and not state.Macros[state.Selected] then
        state.Selected = nil
    end
    if not state.Selected then
        state.Selected = names[1]
    end

    emit()
    return names
end

function MacroController.List()
    return indexNames()
end

function MacroController.Status()
    local selected = state.Selected and state.Macros[state.Selected]
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
            and math.max(0, os.clock() - state.RecordingStartedAt)
            or (selected and tonumber(selected.Duration) or 0),
        Events = selected and #selected.Events or 0,
        Count = #indexNames(),
        Error = state.LastError,
    }
end

function MacroController.OnChanged(fn)
    if type(fn) ~= "function" then
        return function() end
    end

    listeners[#listeners + 1] = fn
    local alive = true

    return function()
        if not alive then
            return
        end
        alive = false
        for i = #listeners, 1, -1 do
            if listeners[i] == fn then
                table.remove(listeners, i)
                break
            end
        end
    end
end

function MacroController.StopAll(reason)
    if state.Recording then
        pcall(MacroController.StopRecording, true)
    end

    state.Auto = false
    state.PlayToken += 1
    state.Playing = false
    clearRecordConnections()
    releasePressedKeys()
    restoreFarm()
    setStatus(reason and ("Stopped • " .. tostring(reason)) or "Stopped")
end

loadIndex()
MacroController.Refresh()

MacroEnv[MACRO_KEY] = MacroController
MacroEnv.DQRMacro = MacroController

if type(ENV.DQR) == "table" then
    ENV.DQR.Macro = MacroController
end

Runtime.MacroController = MacroController
