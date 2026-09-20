--[[
    Dungeon Quest Reborn — universal Macro + conditional Auto Farm bootstrap.

    Macro/UI load in every place.
    Auto Farm combat modules load only for validated dungeon profiles.
]]

local REPO_ROOT =
    "https://raw.githubusercontent.com/MUshihara/dungeonquest/main/runtime/dqr/"

local SUPPORTED = {
    ["Samurai Palace"] = "samurai_palace",
    ["The Underworld"] = "underworld",
    ["Underworld"] = "underworld",
}

local function fetch(path)
    local ok, body =
        pcall(
            game.HttpGet,
            game,
            REPO_ROOT .. path
        )

    if not ok then
        error(
            "[DQR] failed to fetch "
            .. tostring(path)
            .. ": "
            .. tostring(body)
        )
    end

    return body
end

local function compile(path, body, env)
    if env and type(setfenv) ~= "function" then
        error(
            "[DQR] executor is missing setfenv; "
            .. "cannot share the modular environment safely"
        )
    end

    local fn, err =
        loadstring(
            body,
            "@dqr/" .. path
        )

    if not fn then
        error(
            "[DQR] compile failed in "
            .. tostring(path)
            .. ": "
            .. tostring(err)
        )
    end

    if env then
        setfenv(fn, env)
    end

    return fn
end

local function loadTable(path)
    local fn = compile(path, fetch(path))
    local ok, value = pcall(fn)

    if not ok then
        error(
            "[DQR] world module failed "
            .. tostring(path)
            .. ": "
            .. tostring(value)
        )
    end

    if type(value) ~= "table" then
        error(
            "[DQR] expected table from "
            .. tostring(path)
        )
    end

    return value
end

local dungeonNameValue =
    workspace:FindFirstChild("dungeonName")

local dungeonName =
    dungeonNameValue
    and tostring(dungeonNameValue.Value)
    or ""

local slug = SUPPORTED[dungeonName]
local world

if slug then
    local worldRoot =
        "dungeons/" .. slug .. "/"

    world = loadTable(
        worldRoot .. "manifest.lua"
    )

    world.Attacks =
        loadTable(
            worldRoot .. "attacks.lua"
        )

    world.Rooms =
        loadTable(
            worldRoot .. "rooms.lua"
        )

    world.BossData = {}

    for bossName, path in pairs(
        world.BossModules or {}
    ) do
        world.BossData[bossName] =
            loadTable(path)
    end
end

local parentEnv =
    (
        type(getgenv) == "function"
        and getgenv()
    )
    or _G

local Shared =
    setmetatable(
        {
            DQR_WORLD = world,
            DQR_REPO_ROOT = REPO_ROOT,
            DQR_DUNGEON_NAME = dungeonName,
            DQR_FARM_SUPPORTED = slug ~= nil,
            DQR_FARM_SLUG = slug,
        },
        {
            __index = parentEnv,
        }
    )

Shared._G = Shared

local function runShared(path)
    local fn =
        compile(
            path,
            fetch(path),
            Shared
        )

    local ok, err = pcall(fn)

    if not ok then
        error(
            "[DQR] module failed "
            .. tostring(path)
            .. ": "
            .. tostring(err)
        )
    end
end

-- Macro is universal and never depends on a supported combat map.
runShared("core/MacroController.lua")

local COMBAT_MODULES = {
    "core/Services.lua",
    "core/Config.lua",
    "profiles/Profiles.lua",
    "core/RuntimeController.lua",
    "core/DiagnosticLogger.lua",
    "core/Utils.lua",
    "core/EnemyTracker.lua",
    "core/TargetController.lua",
    "core/AnimationController.lua",
    "core/ThreatEngine.lua",
    "core/Geometry.lua",
    "core/DodgePlanner.lua",
    "core/MovementController.lua",
    "core/DodgeController.lua",
    "core/CombatMovement.lua",
    "core/RoomController.lua",
    "core/AbilityController.lua",
    "core/StuckController.lua",
    "core/MainController.lua",
    "core/PublicAPI.lua",
}

if slug then
    for index, path in ipairs(
        COMBAT_MODULES
    ) do
        local fn =
            compile(
                path,
                fetch(path),
                Shared
            )

        local ok, err = pcall(fn)

        if not ok then
            warn(
                "[DQR Auto Farm] module failed #"
                .. tostring(index)
                .. " "
                .. tostring(path)
                .. ": "
                .. tostring(err)
            )

            if Shared.Runtime
                and type(Shared.Runtime.Stop)
                    == "function"
            then
                pcall(
                    Shared.Runtime.Stop,
                    "module_load_error"
                )
            end

            break
        end
    end

    if Shared.DQR_MACRO
        and Shared.CFG
        and Shared.Runtime
    then
        Shared.DQR_MACRO.AttachFarm({
            GetEnabled = function()
                return Shared.CFG.ENABLED
            end,

            SetEnabled = function(value)
                Shared.CFG.ENABLED =
                    value == true
            end,

            StopMovement = function()
                local runtime = Shared.Runtime

                if runtime.Humanoid then
                    pcall(function()
                        if runtime.Root then
                            runtime.Humanoid:MoveTo(
                                runtime.Root.Position
                            )
                        end

                        runtime.Humanoid:Move(
                            Vector3.zero,
                            false
                        )
                    end)
                end

                runtime.MovementOwner =
                    "MACRO"
            end,
        })

        Shared.Runtime.MacroController =
            Shared.DQR_MACRO

        if Shared.ENV
            and type(Shared.ENV.DQR)
                == "table"
        then
            Shared.ENV.DQR.Macro =
                Shared.DQR_MACRO
        end
    end
end

-- UI is also universal. It reports macro-only mode for unsupported maps.
runShared("ui/MainUI.lua")

if slug
    and Shared.Runtime
    and Shared.DQR_UI
then
    Shared.Runtime.DQRUI =
        Shared.DQR_UI
end

if slug then
    print(
        "[DQR] loaded Auto Farm + universal Macro | dungeon="
        .. tostring(dungeonName)
        .. " | place_id="
        .. tostring(game.PlaceId)
    )
else
    print(
        "[DQR] loaded universal Macro | macro-only mode | dungeon="
        .. (
            dungeonName ~= ""
            and tostring(dungeonName)
            or "unknown"
        )
        .. " | place_id="
        .. tostring(game.PlaceId)
    )
end
