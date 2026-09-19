-- DQR modular runtime: core/Utils.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Helpers
-- ============================================================

function fullName(inst)
    if not inst then return "nil" end

    local ok, result = pcall(function()
        return inst:GetFullName()
    end)

    return ok and result or tostring(inst)
end

function horizontal(v)
    return Vector3.new(v.X, 0, v.Z)
end

function horizontalDistance(a, b)
    return horizontal(a - b).Magnitude
end

function unitHorizontal(v)
    local h = horizontal(v)

    if h.Magnitude < 1e-5 then
        return Vector3.new(1, 0, 0)
    end

    return h.Unit
end

function vec(v)
    return string.format("(%.2f,%.2f,%.2f)", v.X, v.Y, v.Z)
end

function getCharacter()
    local char = LP.Character
    if not char then return nil,nil,nil end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")

    return char,hum,root
end

activeThreatCount = function()
    return 0
end

function bindCharacter(char)
    Runtime.Character = char
    Runtime.Humanoid =
        char:FindFirstChildOfClass("Humanoid")
        or char:WaitForChild("Humanoid", 8)

    Runtime.Root =
        char:FindFirstChild("HumanoidRootPart")
        or char:WaitForChild("HumanoidRootPart", 8)

    Runtime.LastPosition =
        Runtime.Root and Runtime.Root.Position or nil

    Runtime.LastPositionChange = os.clock()

    if Runtime.TransitTween then
        pcall(function()
            Runtime.TransitTween:Cancel()
        end)
    end
    Runtime.TransitTween = nil
    Runtime.TransitTweenConn = nil
    Runtime.TransitTweenTarget = nil
    Runtime.TransitTweenDone = true
    Runtime.MovementOwner = "NONE"
    Runtime.TransitGeneration += 1
    Runtime.TransitStartPosition = nil
    Runtime.TransitExpectedPosition = nil
    Runtime.TransitSettleUntil = -math.huge

    Runtime.LastSafePosition =
        Runtime.Root and Runtime.Root.Position or nil
    Runtime.LastSafeCFrame =
        Runtime.Root and Runtime.Root.CFrame or nil
    Runtime.LastSafeAnchorAt = -math.huge

    Runtime.ApproachWaypoints = nil
    Runtime.ApproachFallbackPosition = nil
    Runtime.ApproachTarget = nil

    Runtime.DodgeActive = false
    Runtime.DodgePlan = nil
    Runtime.PathWaypoints = nil
    Runtime.PathDestination = nil
    Runtime.EnemyCacheAt = -math.huge
    Runtime.BossAliveCacheAt = -math.huge
    table.clear(Runtime.BossAliveCache)

    Runtime.FragileMode =
        CFG.ADAPTIVE_SURVIVAL
        and Runtime.Humanoid ~= nil
        and Runtime.Humanoid.MaxHealth
            <= CFG.FRAGILE_MAX_HEALTH

    logKV("CHARACTER", {
        health = Runtime.Humanoid and Runtime.Humanoid.Health or "nil",
        max_health =
            Runtime.Humanoid
            and Runtime.Humanoid.MaxHealth
            or "nil",
        fragile = tostring(Runtime.FragileMode),
        position = Runtime.Root and vec(Runtime.Root.Position) or "nil",
    })

    if Runtime.Humanoid then
        connect(Runtime.Humanoid.Died, function()
            log("PLAYER_DIED", "true")
            flush()
        end)

        local lastHp = Runtime.Humanoid.Health

        connect(Runtime.Humanoid.HealthChanged, function(hp)
            if hp < lastHp then
                logKV("DAMAGE", {
                    amount = string.format("%.1f", lastHp - hp),
                    hp = string.format("%.1f", hp),
                    dodge = Runtime.DodgeActive,
                    threats = tostring(activeThreatCount()),
                })
            end

            lastHp = hp
        end)
    end
end

bindCharacter(LP.Character or LP.CharacterAdded:Wait())

connect(LP.CharacterAdded, function(char)
    task.wait(0.12)
    bindCharacter(char)
end)

bindCompletionSignals()


