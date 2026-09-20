--[[
    Dungeon Quest Reborn — Modular Runtime Bootstrap V1
    Systems compile independently inside one isolated shared environment.
]]

local REPO_ROOT =
    "https://raw.githubusercontent.com/MUshihara/dungeonquest/main/runtime/dqr/"

local SUPPORTED = {
    ["Samurai Palace"] = "samurai_palace",
    ["The Underworld"] = "underworld",
    ["Underworld"] = "underworld",
}

local function fetch(path)
    local ok, body = pcall(game.HttpGet, game, REPO_ROOT .. path)
    if not ok then
        error("[DQR Modular] failed to fetch " .. tostring(path) .. ": " .. tostring(body))
    end
    return body
end

local function compile(path, body, env)
    if env and type(setfenv) ~= "function" then
        error("[DQR Modular] executor is missing setfenv; cannot isolate/share modular runtime state safely")
    end

    local fn, err = loadstring(body, "@dqr/" .. path)
    if not fn then
        error("[DQR Modular] compile failed in " .. tostring(path) .. ": " .. tostring(err))
    end

    if env then setfenv(fn, env) end
    return fn
end

local function loadTable(path)
    local fn = compile(path, fetch(path))
    local ok, value = pcall(fn)
    if not ok then
        error("[DQR Modular] world module failed " .. tostring(path) .. ": " .. tostring(value))
    end
    if type(value) ~= "table" then
        error("[DQR Modular] expected table from " .. tostring(path))
    end
    return value
end

local dungeonNameValue = workspace:FindFirstChild("dungeonName")
local dungeonName = dungeonNameValue and tostring(dungeonNameValue.Value) or ""
local slug = SUPPORTED[dungeonName]

if not slug then
    warn("[DQR Modular] unsupported/unknown dungeon: " .. tostring(dungeonName) .. ". Run recon first.")
    return
end

local worldRoot = "dungeons/" .. slug .. "/"
local world = loadTable(worldRoot .. "manifest.lua")
world.Attacks = loadTable(worldRoot .. "attacks.lua")
world.Rooms = loadTable(worldRoot .. "rooms.lua")
world.BossData = {}

for bossName, path in pairs(world.BossModules or {}) do
    world.BossData[bossName] = loadTable(path)
end

local parentEnv = (type(getgenv) == "function" and getgenv()) or _G
local Shared = setmetatable({
    DQR_WORLD = world,
    DQR_REPO_ROOT = REPO_ROOT,
}, { __index = parentEnv })
Shared._G = Shared

local MODULES = {
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
    "core/MacroController.lua",
    "ui/MainUI.lua",
}

for index, path in ipairs(MODULES) do
    local fn = compile(path, fetch(path), Shared)
    local ok, err = pcall(fn)

    if not ok then
        warn("[DQR Modular] module failed #" .. tostring(index) .. " " .. tostring(path) .. ": " .. tostring(err))
        if Shared.Runtime and type(Shared.Runtime.Stop) == "function" then
            pcall(Shared.Runtime.Stop, "module_load_error")
        end
        return
    end
end

print("[DQR Modular] loaded " .. tostring(world.Name) .. " with " .. tostring(#MODULES) .. " systems")
