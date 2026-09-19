-- DQR modular runtime: core/RuntimeController.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Runtime ownership
-- ============================================================

ENV = getgenv and getgenv() or _G
RUNTIME_KEY = "__SERENITY_DQR_MODULAR_COMBAT_V1"

-- Stop any older Underworld prototype that may still own movement.
for _, oldKey in ipairs({
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V1",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V2",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V3",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V4",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V5",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V6",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V7",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V7_2",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V7_3",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V7_4",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V7_5",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V7_6",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V7_7",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V7_8",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V7_9",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V8_0",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V8_1",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V8_2",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V8_3",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V8_4",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V8_5",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V8_6",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V8_7",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V8_8",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V8_9",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V9_0",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V9_0_2",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V9_1",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V9_2",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V9_3",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V9_4",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V9_5",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V9_6",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V9_7",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V9_8",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V9_9",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V10_0",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V10_1",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V10_2",
    "__SERENITY_DQR_UNDERWORLD_COMBAT_V10_3",
    "__SERENITY_DQR_SAMURAI_PALACE_COMBAT_V1",
}) do
    local previous = ENV[oldKey]

    if previous and type(previous.Stop) == "function" then
        pcall(previous.Stop, "modular_dqr_takeover")
    end
end

-- Stop the passive recon owner if the user starts combat testing in the same
-- live dungeon. Recon has no movement owner, but removing duplicate listeners
-- keeps performance/logging clean.
if ENV.DQR_NEW_WORLD_RECON
    and type(ENV.DQR_NEW_WORLD_RECON.Stop) == "function"
then
    pcall(
        ENV.DQR_NEW_WORLD_RECON.Stop,
        "modular_dqr_combat_started"
    )
end

Runtime = {
    Alive = true,
    Connections = {},

    Character = nil,
    Humanoid = nil,
    Root = nil,

    -- Strong tables are intentional. Weak Instance keys caused the executor to
    -- lose dedupe state and reconnect AnimationPlayed repeatedly.
    Threats = {},
    VirtualThreats = {},

    WatchedAnimators = {},
    LastAnimationEvent = {},
    LastMeleeAttackAt = {},

    EnemyCache = {},
    EnemyCacheAt = -math.huge,
    BossAliveCache = {},
    BossAliveCacheAt = -math.huge,

    DodgePlan = nil,
    LastDodgePlanAt = -math.huge,

    LastAbilityCast = {},
    LastAnyAbilityCast = -math.huge,
    LastAbilityRangeSkipLog = {},
    LastOpportunityAttackLog = -math.huge,
    LastBossOpportunityAt = -math.huge,
    LastMageFreePressureLog = -math.huge,
    LastMageSafeWindowLog = -math.huge,
    LastMagePressureCastLog = -math.huge,
    LastPhysicalLeashLog = -math.huge,
    LastPhysicalHandoffLog = -math.huge,
    LastLocalFinishLog = -math.huge,
    LastShortSkillStageLog = -math.huge,
    LastShortSkillToolProbe = -math.huge,
    ShortSkillTool = nil,
    AimTarget = nil,
    AimLockUntil = -math.huge,
    AimPreviousAutoRotate = nil,

    LastFastShift = -math.huge,
    LastMeleeFastShift = -math.huge,
    LastTeleportAt = -math.huge,
    TeleportHistory = {},
    TeleportTotal = 0,
    LastTeleportTag = nil,
    LastTeleportFrom = nil,
    LastTeleportTo = nil,
    LastTeleportStuds = 0,
    LastTeleportBlockLog = -math.huge,
    LastPostShiftContinueLog = -math.huge,

    LastBossHeartbeat = -math.huge,
    LastMoveRejectLog = -math.huge,
    LastMoveRejectKey = nil,
    LastOvergrowthBacktrackLog = -math.huge,

    ActiveBossName = nil,
    ActiveBossModel = nil,
    ActiveBossRoot = nil,

    BossAddFocusModel = nil,
    BossAddFocusStartedAt = nil,
    BossAddFocusUntil = -math.huge,
    BossAddCooldownUntil = -math.huge,
    LastBossAddFocusLog = -math.huge,

    BossCleanupModels = {},
    BossCleanupBoss = nil,
    BossCleanupUntil = -math.huge,
    BossCleanupTarget = nil,
    LastBossCleanupLog = -math.huge,

    BossWave = nil,
    BossWaveCounter = 0,

    MageWave = nil,
    MageWaveCounter = 0,

    SawFinalBoss = false,
    FinalBossDefeated = false,
    FinalBossDefeatedAt = nil,

    CompletionConfirmed = false,
    CompletionSource = nil,
    CompletionWaitLogged = false,

    -- Set only after a real non-completion disconnect/kick signal. The
    -- controller then stops issuing movement/attack requests instead of
    -- producing misleading recovery spam after the client is already leaving.
    HaltForDisconnect = false,

    PhysicalKiting = false,
    PhysicalKiteEnemy = nil,
    LastPhysicalKiteLog = -math.huge,

    LastMoveTarget = nil,
    LastMoveResolved = nil,
    LastMoveReason = nil,

    WallEscapePosition = nil,
    WallEscapeUntil = -math.huge,
    WallEscapeStarted = nil,
    WallEscapeAttempts = 0,
    BossStallBreakCount = 0,
    LastBossStallLog = -math.huge,
    LastWallEscape = -math.huge,
    LastWallLog = -math.huge,

    ApproachWaypoints = nil,
    ApproachIndex = 1,
    ApproachDestination = nil,
    ApproachTarget = nil,
    LastApproachPathAt = -math.huge,
    ApproachFallbackPosition = nil,
    ApproachFallbackUntil = -math.huge,
    LastApproachLog = -math.huge,

    HorizontalBeamHistory = {},
    LastHorizontalBeamSpawn = -math.huge,
    OvergrowthSpikeHistory = {},
    LastAzrallikPocketLog = -math.huge,
    LastAzrallikEarlyBeamLog = -math.huge,
    LastAzrallikAdvanceLog = -math.huge,
    LastAzrallikLaneSlideLog = -math.huge,
    LastAzrallikPressureLog = -math.huge,
    LastAzrallikHeartLog = -math.huge,
    LastAzrallikFingerLog = -math.huge,
    LastAzrallikBeamReleaseLog = -math.huge,
    LastAzrallikShiftSuppressLog = -math.huge,
    LastAzrallikFingerTellLog = -math.huge,
    AzrallikFingerTellAt = -math.huge,
    AzrallikFingerTellOrigin = nil,
    AzrallikFingerTellMoved = false,

    LastAzrallikSpreadTellLog = -math.huge,
    LastAzrallikSpreadMoveLog = -math.huge,
    LastAzrallikCombinedLog = -math.huge,
    AzrallikSpreadTellAt = -math.huge,
    AzrallikSpreadTellOrigin = nil,
    AzrallikSpreadOrbitSign = 1,

    LastKolvumarSpitRescueAt = -math.huge,
    LastKolvumarRecoveryLog = -math.huge,
    KolvumarRecoveryPosition = nil,
    KolvumarRecoveryUntil = -math.huge,
    LastKolvumarWalkOnlyLog = -math.huge,
    FragileMode = false,
    AzrallikHeartPhaseActive = false,
    AzrallikHeartModel = nil,
    AzrallikHeartStartedAt = nil,
    LastOvergrowthDirectionLog = -math.huge,
    LastOvergrowthLongLineLog = -math.huge,
    LastOvergrowthEdgeLog = -math.huge,
    LastOvergrowthEdgeFollowLog = -math.huge,
    LastStrictRedLog = -math.huge,

    TransitTween = nil,
    TransitTweenConn = nil,
    TransitTweenTarget = nil,
    TransitTweenDone = true,
    TransitAutoRotate = nil,
    LastGateLog = -math.huge,

    MovementOwner = "NONE",
    TransitGeneration = 0,
    TransitStartPosition = nil,
    TransitExpectedPosition = nil,
    TransitSettleUntil = -math.huge,
    TransitBackoffUntil = -math.huge,
    TransitSnapbackCount = 0,
    TransitSnapbackRoom = nil,
    TransitDisabledRoom = nil,

    LastSafeCFrame = nil,
    LastSafePosition = nil,
    LastSafeAnchorAt = -math.huge,
    LastVoidRecovery = -math.huge,

    Target = nil,
    TargetHumanoid = nil,
    TargetRoot = nil,
    TargetSince = -math.huge,
    LastTargetLockLog = -math.huge,

    AbilityStats = {},

    LastTargetScan = 0,
    LastMove = 0,
    LastThink = 0,
    LastFlush = 0,
    LastSwing = -math.huge,
    LastMicro = -math.huge,
    LastRepath = -math.huge,

    DodgeActive = false,
    DodgeStarted = 0,
    DodgeCount = 0,
    MicroCount = 0,
    DodgeMoveWatch = nil,
    LastDodgeMoveWatchLog = -math.huge,
    LastDodgeMoveLabel = nil,
    LastDodgeMoveTarget = nil,

    OrbitSign = 1,
    LastOrbitSwitch = os.clock(),

    LastPosition = nil,
    LastPositionChange = os.clock(),

    PathWaypoints = nil,
    PathIndex = 1,
    PathDestination = nil,
    PathComputeBusy = false,
    NextPathComputeAt = -math.huge,

    CurrentRoomIndex = 0,

    -- Samurai Palace world-local state.
    GolemShatterTellAt = -math.huge,
    GolemShatterTellOrigin = nil,
    GolemShatterPlan = nil,
    LastGolemShatterLog = -math.huge,
    GolemRockTellAt = -math.huge,

    MiyamotoPhase = "idle",
    MiyamotoBeamTellAt = -math.huge,
    MiyamotoCycloneActive = false,
    LastMiyamotoEventLog = -math.huge,
}

ENV[RUNTIME_KEY] = Runtime


-- Samurai Palace classifications. Runtime methods avoid adding more top-level
-- local function declarations to the already-large V10.x monolith.
Runtime.IsRangedPressureName = function(name)
    return DQR_WORLD and DQR_WORLD.RangedPressureNames
        and DQR_WORLD.RangedPressureNames[tostring(name or "")] == true
end

Runtime.IsSamuraiBossAddName = function(name)
    return DQR_WORLD and DQR_WORLD.BossAddNames
        and DQR_WORLD.BossAddNames[tostring(name or "")] == true
end

Runtime.IsSamuraiBossName = function(name)
    return DQR_WORLD and DQR_WORLD.BossNames
        and DQR_WORLD.BossNames[tostring(name or "")] == true
end


function connect(signal, fn)
    local c = signal:Connect(fn)
    Runtime.Connections[#Runtime.Connections + 1] = c
    return c
end

function disconnectAll()
    for _, c in ipairs(Runtime.Connections) do
        pcall(function()
            c:Disconnect()
        end)
    end
    table.clear(Runtime.Connections)
end


