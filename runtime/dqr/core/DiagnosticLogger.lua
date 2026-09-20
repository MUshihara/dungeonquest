-- DQR modular runtime: core/DiagnosticLogger.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Logging
-- ============================================================

BASE = "DQR_" .. tostring(DQR_WORLD and DQR_WORLD.LogSlug or "Unknown") .. "_Modular_V1"
LOG_PATH = BASE .. "/" .. tostring(DQR_WORLD and DQR_WORLD.LogSlug or "Unknown") .. "_Combat_Modular_V1_" .. tostring(os.time()) .. ".txt"

if type(makefolder) == "function" then
    pcall(function()
        if type(isfolder) ~= "function" or not isfolder(BASE) then
            makefolder(BASE)
        end
    end)
end

logBuffer = {}
bootClock = os.clock()

function flush()
    if #logBuffer == 0 then return end

    local block = table.concat(logBuffer, "\n") .. "\n"
    table.clear(logBuffer)

    if type(appendfile) == "function" then
        pcall(appendfile, LOG_PATH, block)
    elseif type(writefile) == "function" and type(readfile) == "function" then
        local old = ""
        pcall(function()
            old = readfile(LOG_PATH)
        end)
        pcall(writefile, LOG_PATH, old .. block)
    else
        print(block)
    end
end

function log(tag, text)
    local line = string.format(
        "[+%08.3f][%s] %s",
        os.clock() - bootClock,
        tostring(tag),
        tostring(text)
    )

    logBuffer[#logBuffer + 1] = line

    if #logBuffer >= 80 then
        flush()
    end
end

function logKV(tag, data)
    local keys = {}
    for k in pairs(data) do
        keys[#keys + 1] = k
    end
    table.sort(keys)

    local out = {}
    for _, k in ipairs(keys) do
        out[#out + 1] = tostring(k) .. "=" .. tostring(data[k])
    end

    log(tag, table.concat(out, " "))
end


-- Passive disconnect/teleport diagnostics only. This does not suppress,
-- intercept, or bypass a platform/game disconnect.
pcall(function()
    connect(
        GuiService.ErrorMessageChanged,
        function(eventMessage)
            local message =
                tostring(eventMessage or "")

            -- Some clients expose the text only through the GuiService
            -- property. Use it only as a fallback so the diagnostic remains
            -- compatible without depending on that property existing.
            if message == "" then
                pcall(function()
                    message =
                        tostring(
                            GuiService.ErrorMessage
                            or ""
                        )
                end)
            end

            if message ~= "" then
                logKV("DISCONNECT_SIGNAL", {
                    message =
                        string.gsub(
                            message,
                            "%s+",
                            "_"
                        ),
                    boss =
                        Runtime.ActiveBossName
                        or "none",
                    room =
                        Runtime.CurrentRoomIndex,
                    last_move =
                        tostring(
                            Runtime.LastMoveReason
                            or "none"
                        ),
                    last_shift =
                        tostring(
                            Runtime.LastTeleportTag
                            or "none"
                        ),
                    shift_age =
                        Runtime.LastTeleportAt == -math.huge
                        and "inf"
                        or string.format(
                            "%.2f",
                            os.clock()
                            - Runtime.LastTeleportAt
                        ),
                })

                if not Runtime.CompletionConfirmed then
                    Runtime.HaltForDisconnect = true

                    if Runtime.Humanoid then
                        pcall(function()
                            Runtime.Humanoid:Move(
                                Vector3.zero,
                                false
                            )

                            Runtime.Humanoid:MoveTo(
                                Runtime.Root
                                and Runtime.Root.Position
                                or Runtime.Humanoid.RootPart.Position
                            )
                        end)
                    end

                    logKV("CONTROLLER_HALT", {
                        reason = "disconnect_signal",
                    })
                end

                flush()
            end
        end
    )
end)

connect(
    Players.PlayerRemoving,
    function(player)
        if player == LP then
            logKV("LOCAL_PLAYER_REMOVING", {
                boss =
                    Runtime.ActiveBossName
                    or "none",
                room =
                    Runtime.CurrentRoomIndex,
                last_move =
                    tostring(
                        Runtime.LastMoveReason
                        or "none"
                    ),
            })

            flush()
        end
    end
)

pcall(function()
    connect(
        LP.OnTeleport,
        function(state, placeId)
            logKV("TELEPORT_STATE", {
                state = tostring(state),
                place = tostring(placeId),
                completion =
                    tostring(
                        Runtime.CompletionConfirmed
                    ),
            })

            flush()
        end
    )
end)


function markCompletion(source)
    if Runtime.CompletionConfirmed then
        return
    end

    Runtime.CompletionConfirmed = true
    Runtime.CompletionSource = source or "unknown"

    logKV("COMPLETION_CONFIRMED", {
        source = Runtime.CompletionSource,
        final_boss_gone = Runtime.FinalBossDefeated,
    })
end

function completionTextMatch(inst)
    if not inst then return false end

    local ok, text = pcall(function()
        if inst:IsA("TextLabel")
            or inst:IsA("TextButton")
            or inst:IsA("TextBox")
        then
            return tostring(inst.Text)
        end
        return ""
    end)

    if not ok or text == "" then
        return false
    end

    local upper = string.upper(text)

    return
        string.find(upper, "DUNGEON COMPLETED", 1, true) ~= nil
        or string.find(upper, "DUNGEON COMPLETE", 1, true) ~= nil
end

function bindCompletionSignals()


-- Miyamoto exposes legitimate server->client encounter state through this
-- RemoteEvent. Observe only; never FireServer it.
Runtime.BindSamuraiPalaceSignals = function()
    local remotes =
        ReplicatedStorage:FindFirstChild("remotes")

    local miyamoto =
        remotes
        and remotes:FindFirstChild(
            "miyamotoClientEvents"
        )

    if miyamoto
        and miyamoto:IsA("RemoteEvent")
    then
        connect(
            miyamoto.OnClientEvent,
            function(action, payload)
                if not Runtime.Alive then
                    return
                end

                action = tostring(action or "")

                if action == "flameBeams" then
                    Runtime.MiyamotoPhase =
                        "flame_beams"
                    Runtime.MiyamotoBeamTellAt =
                        os.clock()

                elseif action == "fireCyclone" then
                    Runtime.MiyamotoPhase =
                        "fire_cyclone"
                    Runtime.MiyamotoCycloneActive =
                        true
                    Runtime.MiyamotoCycloneSuppressed =
                        false

                elseif action == "endFireCyclone" then
                    Runtime.MiyamotoCycloneActive =
                        false
                    Runtime.MiyamotoCycloneSuppressed =
                        true
                    Runtime.MiyamotoPhase =
                        "post_cyclone"

                    for id, vt in pairs(
                        Runtime.VirtualThreats
                    ) do
                        if vt.Source == "Flame Cyclone" then
                            Runtime.VirtualThreats[id] = nil
                        end
                    end

                elseif action == "spinFlameShuriken" then
                    Runtime.MiyamotoPhase =
                        "flame_shuriken"

                elseif action == "hideFire" then
                    Runtime.MiyamotoPhase =
                        "idle"
                    Runtime.MiyamotoCycloneActive =
                        false
                    Runtime.MiyamotoCycloneSuppressed =
                        true

                    for id, vt in pairs(
                        Runtime.VirtualThreats
                    ) do
                        if vt.Source == "Flame Cyclone" then
                            Runtime.VirtualThreats[id] = nil
                        end
                    end
                end

                logKV(
                    "MIYAMOTO_CLIENT_EVENT",
                    {
                        action = action,
                        phase =
                            Runtime.MiyamotoPhase,
                    }
                )
            end
        )
    end
end

if DQR_WORLD and DQR_WORLD.Slug == "samurai_palace" then
    Runtime.BindSamuraiPalaceSignals()
end

    local remotes = ReplicatedStorage:FindFirstChild("remotes")

    if remotes then
        local completeRemote = remotes:FindFirstChild("loadCompleteGui")

        if completeRemote and completeRemote:IsA("RemoteEvent") then
            connect(completeRemote.OnClientEvent, function()
                markCompletion("loadCompleteGui")
            end)
        end
    end

    local playerGui = LP:FindFirstChild("PlayerGui")

    if playerGui then
        for _, inst in ipairs(playerGui:GetDescendants()) do
            if completionTextMatch(inst) then
                markCompletion("PlayerGui")
                break
            end
        end

        connect(playerGui.DescendantAdded, function(inst)
            task.defer(function()
                if completionTextMatch(inst) then
                    markCompletion("PlayerGui")
                end
            end)
        end)
    end
end


