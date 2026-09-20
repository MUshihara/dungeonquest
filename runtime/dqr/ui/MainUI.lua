-- DQR UI bridge using the official Serenity universal V3.2 renderer.

local ENV = (type(getgenv) == "function" and getgenv()) or _G

local Macro = DQR_MACRO or ENV.DQRMacro
if not Macro then
    warn("[DQR UI] Macro controller unavailable")
    return
end

local UI_KEY = "__SERENITY_DQR_UI_V2"
local previous = ENV[UI_KEY]

if previous and type(previous.Destroy) == "function" then
    pcall(previous.Destroy)
end

local BASE =
    "https://raw.githubusercontent.com/MUshihara/Serenity-hub/main/"

local UI = {
    Alive = true,
    App = nil,
    Generation = 0,
    RebuildQueued = false,
    DraftName = "",
}

local function notify(title, text)
    local app = UI.App
    local window = app and app.Window

    if window and type(window.Notify) == "function" then
        pcall(window.Notify, window, title, text)
    end
end

local function loadSerenity()
    local ok, source = pcall(
        game.HttpGet,
        game,
        BASE .. "dist/ui/serenity-v3.lua?dqr=" .. tostring(os.time()),
        true
    )

    if not ok or type(source) ~= "string" or source == "" then
        error(
            "[DQR UI] failed to download official Serenity UI: "
            .. tostring(source)
        )
    end

    local chunk, compileError =
        loadstring(
            source,
            "@SerenityDQR/serenity-v3.lua"
        )

    if not chunk then
        error(
            "[DQR UI] official Serenity UI compile failed: "
            .. tostring(compileError)
        )
    end

    local runOk, Serenity = pcall(chunk)

    if not runOk
        or type(Serenity) ~= "table"
        or type(Serenity.Build) ~= "function"
    then
        error(
            "[DQR UI] official Serenity UI initialization failed: "
            .. tostring(Serenity)
        )
    end

    return Serenity
end

local Serenity = loadSerenity()

local function macroOptions()
    local list = Macro.List()

    if #list == 0 then
        return {"(No saved macros)"}
    end

    return list
end

local function selectedOption(options)
    local status = Macro.Status()

    if status.Selected then
        for _, name in ipairs(options) do
            if name == status.Selected then
                return name
            end
        end
    end

    return options[1]
end

local function currentDungeon()
    local name = tostring(DQR_DUNGEON_NAME or "")
    if name == "" then
        return "Unknown / no dungeonName"
    end
    return name
end

local function farmStatusText()
    if DQR_FARM_SUPPORTED then
        return "Supported profile • " .. currentDungeon()
    end

    return "Macro-only mode • " .. currentDungeon()
end

local function actionResult(ok, value, successText)
    if ok then
        notify("Macro", successText or tostring(value or "Done"))
        return true
    end

    notify("Macro", tostring(value or "Action failed"))
    return false
end

local function buildManifest()
    local options = macroOptions()
    local selected = selectedOption(options)

    return {
        SerenityAPIVersion = 3,
        ConfigVersion = 1,
        RuntimeKey = "__SERENITY_DQR_OFFICIAL_UI_V2",
        ConfigPath = "SerenityDQR/ui-v2.json",
        GameName = "Dungeon Quest Reborn",

        Pages = {
            {
                Id = "AutoFarm",
                Title = "Auto Farm",
                Icon = "bot",
                Description =
                    "Dungeon farming profiles are enabled only on validated maps.",
                Features = {
                    {
                        Id = "Availability",
                        Title = "Auto Farm",
                        Description =
                            "Current support and validated dungeon profiles.",
                        Accent = "cyan",
                        Expanded = true,
                        Controls = {
                            {
                                Id = "CurrentMode",
                                Type = "Live",
                                Title = "Current Mode",
                                Value = farmStatusText(),
                            },
                            {
                                Id = "CurrentPlace",
                                Type = "Live",
                                Title = "Place ID",
                                Value = tostring(game.PlaceId),
                            },
                            {
                                Type = "Paragraph",
                                Title = "Supported Maps",
                                Text =
                                    "Samurai Palace\n"
                                    .. "The Underworld",
                            },
                            {
                                Type = "Paragraph",
                                Title = "Auto Farm controls",
                                Text =
                                    "The proven farm engine is preserved. "
                                    .. "No new Auto Farm switch is exposed in this UI yet.",
                            },
                        },
                    },
                },
            },

            {
                Id = "Macro",
                Title = "Macro",
                Icon = "route",
                Description =
                    "Record your route, jumps, basic attacks, and Q/E skills in any Dungeon Quest place.",
                Features = {
                    {
                        Id = "Library",
                        Title = "Macro Library",
                        Description =
                            "Create, select, refresh, and delete named macros.",
                        Accent = "purple",
                        Expanded = true,
                        Controls = {
                            {
                                Id = "MacroName",
                                Type = "Input",
                                Title = "Macro Name",
                                Description =
                                    "Name for a new macro.",
                                Default = "",
                                Placeholder = "Example: Canals Route 1",
                                Changed = function(value)
                                    UI.DraftName = tostring(value or "")
                                end,
                            },
                            {
                                Id = "Create",
                                Type = "Action",
                                Title = "Create Macro",
                                Description =
                                    "Create an empty named macro and select it.",
                                ButtonText = "CREATE",
                                Callback = function()
                                    local ok, result =
                                        Macro.Create(UI.DraftName)

                                    if actionResult(
                                        ok,
                                        result,
                                        "Macro created"
                                    ) then
                                        UI:ScheduleRebuild()
                                    end
                                end,
                            },
                            {
                                Id = "SelectedMacro",
                                Type = "Select",
                                Title = "Selected Macro",
                                Description =
                                    "Choose which saved macro to record or play.",
                                Options = options,
                                Default = selected,
                                Changed = function(value)
                                    if value ~= "(No saved macros)" then
                                        Macro.Select(value)
                                    end
                                end,
                            },
                            {
                                Id = "Refresh",
                                Type = "Action",
                                Title = "Refresh Macro List",
                                Description =
                                    "Reload saved macro names from storage.",
                                ButtonText = "REFRESH",
                                Callback = function()
                                    Macro.Refresh()
                                    notify("Macro", "Macro list refreshed")
                                    UI:ScheduleRebuild()
                                end,
                            },
                            {
                                Id = "Delete",
                                Type = "Action",
                                Title = "Delete Selected Macro",
                                Description =
                                    "Delete the currently selected saved macro.",
                                Danger = true,
                                Confirm = true,
                                ConfirmText = "Delete this macro?",
                                ButtonText = "DELETE",
                                Callback = function()
                                    local ok, err = Macro.Delete()

                                    if actionResult(
                                        ok,
                                        err,
                                        "Macro deleted"
                                    ) then
                                        UI:ScheduleRebuild()
                                    end
                                end,
                            },
                        },
                    },

                    {
                        Id = "Recorder",
                        Title = "Recorder",
                        Description =
                            "Capture character movement plus semantic basic attacks and Q/E skills. No screen/camera recording.",
                        Accent = "mint",
                        Expanded = true,
                        Controls = {
                            {
                                Id = "StartRecording",
                                Type = "Action",
                                Title = "Start Recording",
                                Description =
                                    "Record the route and combat actions from your current position.",
                                ButtonText = "RECORD",
                                Callback = function()
                                    local ok, err =
                                        Macro.StartRecording()
                                    actionResult(
                                        ok,
                                        err,
                                        "Recording started"
                                    )
                                end,
                            },
                            {
                                Id = "StopSave",
                                Type = "Action",
                                Title = "Stop & Save",
                                Description =
                                    "Stop recording and save the captured macro.",
                                ButtonText = "SAVE",
                                Callback = function()
                                    local ok, err =
                                        Macro.StopRecording(true)
                                    actionResult(
                                        ok,
                                        err,
                                        "Recording saved"
                                    )
                                end,
                            },
                            {
                                Id = "PlayOnce",
                                Type = "Action",
                                Title = "Play Once",
                                Description =
                                    "Replay the recorded route, attacks, and skills one time.",
                                ButtonText = "PLAY",
                                Callback = function()
                                    local ok, err =
                                        Macro.PlayOnce()
                                    actionResult(
                                        ok,
                                        err,
                                        "Playback started"
                                    )
                                end,
                            },
                            {
                                Id = "StopPlayback",
                                Type = "Action",
                                Title = "Stop Playback",
                                Description =
                                    "Stop a running one-shot or automatic macro.",
                                ButtonText = "STOP",
                                Callback = function()
                                    local ok = Macro.StopPlayback()

                                    if ok then
                                        notify(
                                            "Macro",
                                            "Playback stopped"
                                        )
                                    else
                                        notify(
                                            "Macro",
                                            "No macro playback is active"
                                        )
                                    end
                                end,
                            },
                        },
                    },

                    {
                        Id = "Automation",
                        Title = "Auto Macro",
                        Description =
                            "Continuously repeat the selected route and recorded combat actions.",
                        Accent = "cyan",
                        Expanded = true,
                        Controls = {
                            {
                                Id = "Auto",
                                Type = "Switch",
                                Title = "Auto Macro",
                                Description =
                                    "Loop the selected macro until disabled.",
                                Default = false,
                                Changed = function(value, window, adapter)
                                    local ok, err =
                                        Macro.SetAuto(value == true)

                                    if not ok then
                                        notify(
                                            "Macro",
                                            tostring(err or "Unable to start Auto Macro")
                                        )

                                        local control =
                                            adapter
                                            and adapter.Controls
                                            and adapter.Controls[
                                                "Macro.Automation.Auto"
                                            ]

                                        if control
                                            and type(control.Set) == "function"
                                        then
                                            pcall(
                                                control.Set,
                                                control,
                                                false,
                                                true
                                            )
                                        end
                                    end
                                end,
                            },
                        },
                    },

                    {
                        Id = "Status",
                        Title = "Status",
                        Description =
                            "Live macro state and executor capability.",
                        Accent = "purple",
                        Expanded = true,
                        Controls = {
                            {
                                Id = "State",
                                Type = "Live",
                                Title = "Status",
                                Value = "Idle",
                            },
                            {
                                Id = "Selected",
                                Type = "Live",
                                Title = "Selected",
                                Value = "None",
                            },
                            {
                                Id = "Duration",
                                Type = "Live",
                                Title = "Duration",
                                Value = "0.0s",
                            },
                            {
                                Id = "Events",
                                Type = "Live",
                                Title = "Recorded Events",
                                Value = "0",
                            },
                            {
                                Id = "Moves",
                                Type = "Live",
                                Title = "Move Points",
                                Value = "0",
                            },
                            {
                                Id = "Attacks",
                                Type = "Live",
                                Title = "Basic Attacks",
                                Value = "0",
                            },
                            {
                                Id = "Skills",
                                Type = "Live",
                                Title = "Q/E Skills",
                                Value = "0",
                            },
                            {
                                Id = "Jumps",
                                Type = "Live",
                                Title = "Jumps",
                                Value = "0",
                            },
                            {
                                Id = "LastAction",
                                Type = "Live",
                                Title = "Last Action",
                                Value = "None",
                            },
                            {
                                Id = "Saved",
                                Type = "Live",
                                Title = "Saved Macros",
                                Value = "0",
                            },
                            {
                                Id = "Storage",
                                Type = "Live",
                                Title = "Storage",
                                Value = "Checking...",
                            },
                            {
                                Id = "RecordedPlace",
                                Type = "Live",
                                Title = "Current Place",
                                Value = tostring(game.PlaceId),
                            },
                        },
                    },
                },
            },
        },
    }
end

function UI:UpdateLive()
    local app = self.App
    local adapter = app and app.Adapter

    if not adapter or type(adapter.SetLive) ~= "function" then
        return
    end

    local status = Macro.Status()

    adapter:SetLive(
        "AutoFarm.Availability.CurrentMode",
        farmStatusText()
    )

    adapter:SetLive(
        "AutoFarm.Availability.CurrentPlace",
        tostring(game.PlaceId)
    )

    adapter:SetLive(
        "Macro.Status.State",
        status.Error
        and (
            tostring(status.Status)
            .. " • "
            .. tostring(status.Error)
        )
        or tostring(status.Status)
    )

    adapter:SetLive(
        "Macro.Status.Selected",
        tostring(status.Selected or "None")
    )

    adapter:SetLive(
        "Macro.Status.Duration",
        string.format(
            "%.1fs",
            tonumber(status.Duration) or 0
        )
    )

    adapter:SetLive(
        "Macro.Status.Events",
        tostring(status.Events or 0)
    )

    adapter:SetLive(
        "Macro.Status.Moves",
        tostring(status.Moves or 0)
    )

    adapter:SetLive(
        "Macro.Status.Attacks",
        tostring(status.Attacks or 0)
    )

    adapter:SetLive(
        "Macro.Status.Skills",
        tostring(status.Skills or 0)
    )

    adapter:SetLive(
        "Macro.Status.Jumps",
        tostring(status.Jumps or 0)
    )

    adapter:SetLive(
        "Macro.Status.LastAction",
        tostring(status.LastAction or "None")
    )

    adapter:SetLive(
        "Macro.Status.Saved",
        tostring(status.Count or 0)
    )

    adapter:SetLive(
        "Macro.Status.Storage",
        tostring(status.Storage)
        .. " • semantic combat recorder"
    )

    adapter:SetLive(
        "Macro.Status.RecordedPlace",
        tostring(game.PlaceId)
    )
end

function UI:Build()
    if not self.Alive then
        return
    end

    self.Generation += 1
    local generation = self.Generation

    if self.App and type(self.App.Destroy) == "function" then
        pcall(self.App.Destroy, self.App)
    end

    local manifest = buildManifest()

    local ok, appOrError = xpcall(
        function()
            return Serenity.Build(
                manifest,
                {
                    RuntimeKey =
                        "__SERENITY_DQR_OFFICIAL_UI_V2",
                    ConfigPath =
                        "SerenityDQR/ui-v2.json",
                }
            )
        end,
        debug.traceback
    )

    if not ok then
        warn(
            "[DQR UI] official Serenity build failed: "
            .. tostring(appOrError)
        )
        self.App = nil
        return
    end

    self.App = appOrError

    local controls =
        self.App.Adapter
        and self.App.Adapter.Controls

    local selectedControl =
        controls
        and controls[
            "Macro.Library.SelectedMacro"
        ]

    if selectedControl
        and type(selectedControl.Set) == "function"
    then
        pcall(
            selectedControl.Set,
            selectedControl,
            selectedOption(macroOptions()),
            true
        )
    end

    local autoControl =
        controls
        and controls[
            "Macro.Automation.Auto"
        ]

    -- Automations always start OFF even if an old UI config happened to save ON.
    if autoControl and type(autoControl.Set) == "function" then
        pcall(
            autoControl.Set,
            autoControl,
            false,
            false
        )
    end

    self:UpdateLive()

    task.spawn(function()
        while UI.Alive
            and UI.Generation == generation
            and UI.App == appOrError
        do
            UI:UpdateLive()
            task.wait(0.50)
        end
    end)
end

function UI:ScheduleRebuild()
    if self.RebuildQueued or not self.Alive then
        return
    end

    self.RebuildQueued = true

    task.defer(function()
        task.wait()

        if not UI.Alive then
            return
        end

        UI.RebuildQueued = false
        UI:Build()
    end)
end

function UI:Destroy()
    if not self.Alive then
        return
    end

    self.Alive = false
    self.Generation += 1

    if self.App and type(self.App.Destroy) == "function" then
        pcall(self.App.Destroy, self.App)
    end

    self.App = nil

    if ENV[UI_KEY] == self then
        ENV[UI_KEY] = nil
    end
end

UI:Build()

ENV[UI_KEY] = UI
DQR_UI = UI
