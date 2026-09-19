--[[
    SERENITY HUB — DUNGEON QUEST REBORN
    UNDERWORLD INTELLIGENT COMBAT V10.3 — OVERGROWTH HARD CLEAR + KOLVUMAR ROLLBACK + AZRALLIK COMBO
    ------------------------------------------------------------
    Development target:
      The Underworld — Nightmare
      Gameplay PlaceId observed in recordings: 85776757589518

    This prototype uses the combat structure learned from the user's logs:
      • workspace.dungeon.roomN.enemyFolder
      • normal enemies: Demon Warrior / Dark Mage / Elder Dark Mage
      • bosses: Demonic Overgrowth / Kolvumar / Demon Lord Azrallik
      • dynamic warning objects:
          npcMageSpikes
          bigMageBeam
          spikePrecast
          overgrowthLongLineSpikes
          kolvumarSpit
          horizontalBeam
          azrallikPunch
          azrallikPunchSpread
          fingerBlastHit

    Priorities:
      1. Walk/strafe first; teleport only when movement is unlikely to clear in time.
      2. Group BOTH boss telegraphs and overlapping mage lines into attack waves.
      3. Use boss-specific fighting distance so ranged skills do the work safely.
      4. Preserve Kolvumar floor hazards without letting old zones freeze the boss state.
      5. Predict fast physical/add pressure before the attack animation is useful.
      6. Stop navigation cleanly once Demon Lord Azrallik is defeated.

    IMPORTANT:
      • This is a TEST BUILD, not the final Serenity production controller.
      • No anti-cheat bypasses.
      • No lobby automation.
      • No purchases.
      • No admin/dev remotes.
      • Emergency reposition is bounded, globally rate-limited, and normally once per boss wave.
      • Vertical/floating dodge is intentionally NOT used: recorded hitboxes are tall.

    Runtime logs:
      DQR_Underworld_Test_V8_4/
        Underworld_Combat_V8_4_<timestamp>.txt
]]

-- ============================================================
-- Services
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")

local LP = Players.LocalPlayer

-- ============================================================
-- Config
-- ============================================================

local CFG = {
    ENABLED = true,

    -- Current user profile.
    -- Supported planner profiles:
    --   "Physical"
    --   "Tank"
    --   "Spell"
    STYLE = "Physical",

    AUTO_NAVIGATION = true,
    AUTO_ATTACK = true,
    AUTO_ABILITIES = true,
    AUTO_DODGE = true,

    -- Small general emergency translation fallback.
    MICRO_TELEPORT = true,
    MICRO_TELEPORT_MAX = 5.5,
    MICRO_TELEPORT_COOLDOWN = 1.15,
    MICRO_TELEPORT_MIN_THREAT_AGE = 0.08,

    -- V5: every CFrame displacement shares one global budget. The game log
    -- showed chained teleports were useful but far too frequent around bosses.
    TELEPORT_GLOBAL_COOLDOWN = 3.00,
    TELEPORT_WINDOW_SECONDS = 12.0,
    TELEPORT_WINDOW_MAX = 4,

    -- A partial CFrame rescue can leave the Humanoid standing at the new point
    -- while the already-validated dodge plan still has distance remaining.
    POST_SHIFT_CONTINUE_ENABLED = true,
    POST_SHIFT_CONTINUE_MIN_DISTANCE = 1.75,

    -- V9.0: V8.9 correctly re-armed movement after a partial shift, but it
    -- sometimes chased the OLD dodge point for another 20-28 studs. That is
    -- what looked like "teleport too far, then correct/go back". Continue only
    -- one small validated local step; the normal planner may re-evaluate after.
    POST_SHIFT_CONTINUE_MAX_STEP = 7.0,
    POST_SHIFT_CONTINUE_LOG_COOLDOWN = 0.45,
    TELEPORT_BOSS_WAVE_MAX = 10.0,
    TELEPORT_BOSS_WAVE_ONCE = true,

    -- Long/thin red lines can activate before normal walking clears their
    -- width. V5 can immediately shift across the SHORT axis only.
    LARGE_LINE_FAST_SHIFT = true,
    LARGE_LINE_ASPECT_RATIO = 2.8,
    LARGE_LINE_FAST_SHIFT_MAX = 11.5,
    LARGE_LINE_FAST_SHIFT_COOLDOWN = 1.10,
    LARGE_LINE_EXTRA_MARGIN = 1.75,

    -- MELEE-FIRST / SPEED-AWARE:
    -- The logs proved Demon Warrior can hit within ~0.00-0.20 s of the
    -- client animation, and can close the gap faster than ordinary walking.
    -- Use distance + relative closing speed instead of waiting for animation.
    PROACTIVE_MELEE_AVOIDANCE = true,

    -- V7: NORMAL physical proximity is no longer a "dodge threat".
    -- It is handled as combat pressure/kiting so Q/E can keep firing and the
    -- controller does not bounce DODGE_START/DODGE_CLEAR every 0.05-0.10 sec.
    MELEE_SOFT_RADIUS = 18.0,
    MELEE_RELEASE_RADIUS = 23.0,
    MELEE_CRITICAL_RADIUS = 10.0,
    MELEE_PANIC_RADIUS = 7.0,
    MELEE_DYNAMIC_HORIZON = 0.18,
    MELEE_DYNAMIC_MAX_BONUS = 5.0,
    MELEE_DIRECT_ESCAPE_EXTRA = 4.5,
    MELEE_REACTION_WINDOW = 0.24,
    MELEE_FAST_SHIFT_MAX = 7.5,
    MELEE_FAST_SHIFT_COOLDOWN = 1.15,

    PHYSICAL_KITE_STEP = 8.0,
    PHYSICAL_KITE_TANGENT = 4.0,
    PHYSICAL_KITE_START_CLOSING = 6.0,
    PHYSICAL_KITE_LOG_COOLDOWN = 0.75,
    PHYSICAL_KITE_MIN_CLOSING = 2.5,
    PHYSICAL_HARD_KITE_RADIUS = 13.0,

    -- Do not let a Blood Minion / Warrior kite us hundreds of studs away from
    -- the real objective. Physical avoidance chooses a safe LOCAL point that
    -- also preserves progress toward the current mage/boss/Heart.
    PHYSICAL_TARGET_LEASH_ENABLED = true,
    PHYSICAL_TARGET_LEASH_SAMPLES = 8,
    PHYSICAL_TARGET_LEASH_EXTRA_STEP = 4.0,
    PHYSICAL_TARGET_LEASH_HEART_MAX = 36.0,
    PHYSICAL_TARGET_LEASH_BOSS_MAX = 42.0,
    PHYSICAL_TARGET_LEASH_MAGE_MAX = 38.0,
    PHYSICAL_TARGET_LEASH_LOG_COOLDOWN = 0.70,

    -- V7.2 wall awareness. Every movement request gets a short forward wall
    -- check. If blocked, the controller slides along the wall or selects an
    -- open-space candidate instead of repeatedly MoveTo'ing into the obstacle.
    WALL_LOOKAHEAD = 8.0,
    WALL_BODY_MARGIN = 2.5,
    WALL_ESCAPE_RADII = {6, 10, 14, 18, 24},
    WALL_ESCAPE_DIRECTIONS = 16,
    WALL_ESCAPE_HOLD = 0.95,
    WALL_ESCAPE_COOLDOWN = 0.35,
    WALL_STUCK_TRIGGER = 1.05,
    WALL_HARD_STUCK_SECONDS = 2.8,
    WALL_NUDGE_MAX = 4.5,
    WALL_LOG_COOLDOWN = 0.45,
    WALL_GROUND_CHECK = 12.0,
    WALL_LOCAL_INTERCEPT = 22.0,

    -- V7.3 long-range progress controller. When a target/boss is far away,
    -- stop trying one giant MoveTo through the whole arena. Follow a path when
    -- possible; otherwise keep taking forward/left/right progress steps until
    -- attack range is reached.
    APPROACH_TRIGGER_EXTRA = 34.0,
    APPROACH_REPATH_INTERVAL = 1.15,
    APPROACH_WAYPOINT_REACHED = 5.0,
    APPROACH_STEP_RADII = {14, 22, 32},
    APPROACH_ANGLES = {0, 30, -30, 60, -60, 90, -90, 120, -120, 180},
    APPROACH_HOLD = 0.70,
    APPROACH_MIN_PROGRESS = 2.0,
    APPROACH_LOG_COOLDOWN = 0.80,

    -- V8.4 threat-free boss-stall recovery. Humanoid movement only.
    -- One V8.3 run repeated the same ~6-stud wall escape for ~25 seconds while
    -- Overgrowth stayed ~147 studs away. Recovery now widens 12→18→24 studs
    -- and prefers progress toward the boss when there is no active threat.
    BOSS_STALL_RECOVERY_MIN_RADIUS = 12.0,
    BOSS_STALL_RECOVERY_MAX_RADIUS = 24.0,
    BOSS_STALL_LOG_COOLDOWN = 0.70,

    -- Boss-wave movement should preserve forward progress whenever a safe
    -- forward/lateral gap exists instead of slowly drifting backward.
    BOSS_PROGRESS_REWARD = 340.0,
    BOSS_BACKTRACK_PENALTY = 520.0,
    BOSS_PROGRESS_ACTIVE_EXTRA = 8.0,

    -- Kolvumar has a visible spit plus a non-red follow-up sequence. Keep a
    -- conservative range during that animation window and never route back
    -- through an old spit puddle.
    KOLVUMAR_SPIT_SAFETY_EXTRA = 7.0,

    -- Keep this explicit because the Kolvumar pocket/slide controller needs a
    -- stable boss-range target even when Runtime.Target temporarily switches
    -- to a nearby add.
    KOLVUMAR_DESIRED_RANGE = 26.0,

    KOLVUMAR_DIRECT_SAFE_RADIUS = 74.0,
    KOLVUMAR_DIRECT_THREAT_LIFETIME = 4.6,

    -- V8.8: each new spit can spawn directly under the player and hit about
    -- 0.17-0.25 sec later. A boss-wave "once" teleport is not enough because
    -- Kolvumar can place several puddles in one continuous wave.
    -- V9.0: V8.9's repeated 22.5-stud spit rescues were the main regression.
    -- The character escaped, then ordinary boss pressure walked it back into
    -- the same puddle while the 3-sec teleport governor was still cooling down.
    -- Build a local pocket outside the UNION of all active spit hitboxes,
    -- briefly hold it, then slide toward Kolvumar only through spit-safe space.
    KOLVUMAR_SPIT_RESCUE_MAX = 18.5,
    KOLVUMAR_SPIT_ESCAPE_MARGIN = 3.0,
    KOLVUMAR_SPIT_SEARCH_RADII = {
        10, 12, 14, 16, 18, 20, 22, 24, 28
    },
    KOLVUMAR_SPIT_SEARCH_ANGLES = {
        0, 22.5, -22.5, 45, -45, 67.5, -67.5,
        90, -90, 112.5, -112.5, 135, -135, 157.5, -157.5, 180
    },
    KOLVUMAR_SPIT_POST_ESCAPE_HOLD = 0.20,
    KOLVUMAR_POST_RESCUE_MOTION_TIME = 3.15,

    -- A stall-recovery MoveTo must be allowed to actually run. V10.1 could
    -- compute a valid recovery point and then immediately overwrite it on the
    -- next planner tick with the old puddle escape destination.
    -- V10.2 experiment: committing watchdog recovery ownership caused the
    -- strict-red route gate to repeatedly hold the player at speed 0. Restore
    -- V10.1's faster replanning behavior, but KEEP V10.2's live overlap recount.
    KOLVUMAR_STALL_RECOVERY_COMMIT_ENABLED = false,
    KOLVUMAR_STALL_RECOVERY_COMMIT = 0.62,
    KOLVUMAR_STALL_RECOVERY_LOG_COOLDOWN = 0.55,

    KOLVUMAR_SPIT_HOLD_DISTANCE = 1.35,
    KOLVUMAR_SPIT_SAFE_SLIDE_STEP = 10.0,
    KOLVUMAR_SPIT_SAFE_SLIDE_MIN = 3.0,
    KOLVUMAR_SPIT_ROUTE_SAMPLE_STEP = 2.5,
    KOLVUMAR_SPIT_LOG_COOLDOWN = 0.55,
    KOLVUMAR_SPIT_SHIFT_HP_RATIO = 0.58,
    KOLVUMAR_SPIT_SHIFT_MIN_STACK = 2,
    KOLVUMAR_GENERIC_WAVE_SHIFT = false,

    -- V7.4: wave planners must also respect fast physical pressure without
    -- turning normal proximity back into constant dodge mode.
    WAVE_PHYSICAL_HARD_RADIUS = 20.0,
    WAVE_PHYSICAL_SOFT_RADIUS = 30.0,
    WAVE_PHYSICAL_HARD_PENALTY = 150000,
    WAVE_PHYSICAL_SOFT_PENALTY = 4200,

    -- Overgrowth repeatedly killed the run after a 10-stud shift that still
    -- left us inside the wave. One larger primary shift is safer than chaining
    -- lots of tiny teleports.
    OVERGROWTH_WAVE_TELEPORT_MAX = 14.0,
    OVERGROWTH_MIN_CLEARANCE = 14.0,

    -- Azrallik spread + sweep.
    AZRALLIK_WAVE_TELEPORT_MAX = 16.0,
    AZRALLIK_SPREAD_MIN_CLEARANCE = 18.0,

    -- V10.2: every observed Azrallik punch animation
    -- rbxassetid://130043568559097 was followed by PunchSpread roughly
    -- 2.51-2.52 seconds later. Use that replicated animation as a prediction
    -- window: approach for the first ~1.05s, then orbit laterally instead of
    -- continuing straight toward the boss until the spread appears.
    AZRALLIK_SPREAD_TELL_ANIM = "rbxassetid://130043568559097",
    AZRALLIK_SPREAD_EXPECTED_DELAY = 2.52,
    AZRALLIK_SPREAD_PREMOVE_START = 1.05,
    AZRALLIK_SPREAD_TELL_WINDOW = 2.78,
    AZRALLIK_SPREAD_PREMOVE_MAX_BOSS_DISTANCE = 120.0,
    AZRALLIK_SPREAD_PREMOVE_STEPS = {8, 10, 12, 14},
    AZRALLIK_SPREAD_LOCAL_RADII = {4, 6, 8, 10, 12, 14, 16, 18},
    AZRALLIK_SPREAD_HOLD_CLEARANCE = 7.0,
    AZRALLIK_SPREAD_ROUTE_DANGER_MAX = 4200,
    AZRALLIK_SPREAD_LOG_COOLDOWN = 0.60,
    AZRALLIK_COMBINED_FINGER_SPREAD_ENABLED = true,
    AZRALLIK_COMBINED_LOG_COOLDOWN = 0.55,

    AZRALLIK_INVALID_DEST_MIN_RADIUS = 18.0,
    AZRALLIK_SWEEP_HISTORY = 8,
    AZRALLIK_SWEEP_HISTORY_AGE = 1.25,
    AZRALLIK_SWEEP_ESCAPE_MARGIN = 5.0,
    AZRALLIK_SWEEP_TELEPORT_MAX = 12.5,
    AZRALLIK_SWEEP_IMPACT_WINDOW = 1.00,
    AZRALLIK_SWEEP_MIN_ESCAPE = 10.5,
    AZRALLIK_SWEEP_GAP_MIN_CLEARANCE = 2.0,

    -- V8.0 Azrallik horizontal-beam handling.
    -- Parallel strips leave a narrow straight safe lane between them.
    -- Find one nearby lane, walk into it, and HOLD instead of chasing
    -- the moving front backward across the arena.
    AZRALLIK_BEAM_POCKET_ENABLED = true,
    -- The observed beam lattice is ~26 studs center-to-center with a
    -- ~16-stud strip width, leaving a ~9-10 stud safe lane. The exact spacing
    -- is learned every wave; these values only bound the local search.
    AZRALLIK_BEAM_AURA_STEP = 2.5,
    AZRALLIK_BEAM_AURA_RADIUS = 25.0,
    AZRALLIK_BEAM_AURA_LATERAL = {0, 5, -5, 10, -10},
    AZRALLIK_BEAM_MIN_GAP_WIDTH = 4.0,
    AZRALLIK_BEAM_MIN_CLEARANCE = 2.0,
    AZRALLIK_BEAM_HOLD_DISTANCE = 1.35,
    AZRALLIK_BEAM_MAX_POCKET_TRAVEL = 18.0,
    AZRALLIK_BEAM_RESCAN_INTERVAL = 0.10,
    AZRALLIK_BEAM_LOCK_LOG_COOLDOWN = 0.70,
    AZRALLIK_BEAM_NO_TELEPORT = true,

    -- Before two strips exist there is not enough information to build the
    -- ~26-stud lattice. Never fall back to a generic boss-wave destination.
    -- Either leave the first strip by its nearest edge or briefly hold the
    -- current already-safe point until the second strip reveals the lattice.
    AZRALLIK_BEAM_EARLY_MARGIN = 3.0,
    AZRALLIK_BEAM_EARLY_MAX_TRAVEL = 14.0,
    AZRALLIK_BEAM_EARLY_LOG_COOLDOWN = 0.65,

    -- After the last new beam strip has spawned, old strips remain in
    -- Workspace for several seconds. Do not wait for every object to vanish.
    -- Instead, advance toward the boss in short NORMAL MoveTo steps whenever
    -- the next step and its route are already safe.
    AZRALLIK_BEAM_SPAWN_QUIET = 0.38,

    -- V8.4 empirical release window.
    -- In the six V8.3 runs, the latest horizontal-beam damage happened about
    -- 1.15 sec after the final strip spawned, while the old hitbox objects
    -- stayed around roughly 3.5 sec. 1.45 sec keeps a safety margin but removes
    -- the ~2 sec "red is already gone but I'm still waiting" delay.
    AZRALLIK_BEAM_POST_SPAWN_DANGER = 1.45,

    AZRALLIK_BEAM_ADVANCE_STEP = 10.0,
    AZRALLIK_BEAM_ADVANCE_MIN_STEP = 3.0,
    AZRALLIK_BEAM_ADVANCE_INTERVAL = 0.25,
    AZRALLIK_BEAM_ADVANCE_LOG_COOLDOWN = 0.65,

    -- While horizontal beams are STILL active, move only ALONG the already
    -- safe lane (parallel to the beam's long axis). This cannot cross into the
    -- neighboring red strip, and it lets us approach the boss without waiting
    -- several seconds for old beam objects to disappear.
    AZRALLIK_BEAM_LANE_SLIDE_STEP = 10.0,
    AZRALLIK_BEAM_LANE_SLIDE_MIN = 2.5,
    AZRALLIK_BEAM_LANE_SLIDE_INTERVAL = 0.22,
    AZRALLIK_BEAM_LANE_SLIDE_LOG_COOLDOWN = 0.60,

    -- Final boss target discipline. Never chase a room-999 add across the map
    -- while Azrallik is alive. Blood Minion only overrides when it is already
    -- in its real physical-pressure envelope.
    AZRALLIK_BLOOD_MINION_EMERGENCY_RANGE = 36.0,
    AZRALLIK_HEART_LOCAL_RANGE = 42.0, -- compatibility only
    AZRALLIK_HEART_PHASE_LOCK = true,
    AZRALLIK_HEART_ATTACK_RANGE = 26.0,
    AZRALLIK_HEART_LOG_COOLDOWN = 0.75,

    -- V8.7 Finger Blast.
    -- V8.6 was hit ~1.7 sec after spawn in all three runs even after escaping.
    -- Hold away from the original marker through that delayed damage window.
    AZRALLIK_FINGER_MIN_DISTANCE = 30.0,
    AZRALLIK_FINGER_CANDIDATE_RADII = {28, 32, 36},
    AZRALLIK_FINGER_ANGLES = {0, 25, -25, 50, -50, 75, -75},
    AZRALLIK_FINGER_HOLD_TIME = 2.35,
    AZRALLIK_FINGER_LOG_COOLDOWN = 0.65,
    AZRALLIK_FINGER_TELL_ANIM = "rbxassetid://106525745261065",
    AZRALLIK_FINGER_TELL_WINDOW = 1.28,
    AZRALLIK_FINGER_PREMOVE_MIN_RADIUS = 14.0,
    AZRALLIK_FINGER_PREHOLD_CLEARANCE = 11.0,
    AZRALLIK_FINGER_TELL_LOG_COOLDOWN = 0.70,

    -- Keep consuming safe ground toward Azrallik/Heart during persistent
    -- non-horizontal boss waves instead of waiting for every threat object.
    AZRALLIK_SAFE_PRESSURE_ENABLED = true,
    AZRALLIK_SAFE_PRESSURE_RANGE = 52.0,
    AZRALLIK_SAFE_PRESSURE_STEP = 10.0,
    AZRALLIK_SAFE_PRESSURE_INTERVAL = 0.18,
    AZRALLIK_SAFE_PRESSURE_MIN_CLEARANCE = 6.0,
    AZRALLIK_SAFE_PRESSURE_CLEARANCE_KEEP = 0.65,
    AZRALLIK_SAFE_PRESSURE_MAX_REQUIRED_CLEARANCE = 14.0,
    AZRALLIK_SAFE_PRESSURE_LOG_COOLDOWN = 0.70,

    -- Exact lane sampling checks actual overlap, not proximity penalties.
    SAFE_ROUTE_SAMPLE_STEP = 2.5,

    -- Smooth inter-room transit only. This never owns movement during combat.
    -- The tween is deliberately moderate/longer rather than an instant CFrame.
    TRANSIT_TWEEN_ENABLED = false,
    TRANSIT_TWEEN_SPEED = 18.0,
    TRANSIT_TWEEN_MIN_DURATION = 0.38,
    TRANSIT_TWEEN_MAX_DURATION = 2.10,
    TRANSIT_TWEEN_WAYPOINT_SPACING = 11.0,
    TRANSIT_TWEEN_STOP_DISTANCE = 9.0,

    -- V7.5: keep smooth travel active toward distant enemies. Stop only near
    -- real combat or when a live threat appears.
    TRANSIT_COMBAT_STOP_DISTANCE = 68.0,
    TRANSIT_COMBAT_START_DISTANCE = 88.0,
    TRANSIT_SEGMENT_MAX = 32.0,
    TRANSIT_SEGMENT_MIN = 14.0,
    TRANSIT_GATE_RETRY = 0.45,
    TRANSIT_GATE_LOG_COOLDOWN = 1.0,

    -- V7.6 transit stability.
    TRANSIT_TWEEN_SAFE_CAP = 30.0,
    TRANSIT_SETTLE_TIME = 0.22,
    TRANSIT_SNAPBACK_DISTANCE = 8.0,
    TRANSIT_SNAPBACK_BACKOFF = 6.0,
    TRANSIT_SNAPBACK_ROOM_LIMIT = 2,

    -- Never follow a path/tween waypoint into a large vertical drop or a point
    -- with no floor beneath it.
    SAFE_VERTICAL_DELTA = 14.0,
    SAFE_GROUND_DEPTH = 20.0,
    SAFE_GROUND_MAX_GAP = 8.5,
    VOID_DROP_TRIGGER = 24.0,
    VOID_RECOVERY_COOLDOWN = 2.0,
    SAFE_ANCHOR_REFRESH = 0.18,

    -- Overgrowth is treated as a moving spike sequence.
    OVERGROWTH_SEQUENCE_HISTORY = 10,
    OVERGROWTH_SEQUENCE_AGE = 1.65,
    OVERGROWTH_SEQUENCE_MIN_STEP = 3.0,
    OVERGROWTH_SEQUENCE_RADII = {16, 24, 32, 40, 48},
    OVERGROWTH_SEQUENCE_ANGLES = {0, 22, -22, 45, -45, 70, -70},
    OVERGROWTH_SEQUENCE_ESCAPE_MARGIN = 4.0,
    OVERGROWTH_SEQUENCE_IMPACT_WINDOW = 0.58,
    OVERGROWTH_SEQUENCE_MAX_TELEPORTS = 1,
    OVERGROWTH_SEQUENCE_TELEPORT_GAP = 5.00,
    OVERGROWTH_FIRST_COMMIT_DELAY = 0.58,

    -- V7.8 narrow-spike sweep. Direction is learned from the first two
    -- distinct spikePrecast strips and then LOCKED for that boss wave. All
    -- subsequent escape candidates must continue forward or sideways; they
    -- are never allowed to reverse back into an earlier strip.
    OVERGROWTH_FORWARD_MIN_MOVE = 7.0,
    OVERGROWTH_FORWARD_EXTRA = 2.5,
    OVERGROWTH_FORWARD_MAX_REQUIRED = 22.0,
    OVERGROWTH_FORWARD_ANGLES = {0, 18, -18, 35, -35, 55, -55, 72, -72},
    OVERGROWTH_FORWARD_RADII = {8, 10, 12, 14, 16, 18, 22},
    OVERGROWTH_FORWARD_MIN_DOT = 0.18,
    OVERGROWTH_DIRECTION_LOG_COOLDOWN = 0.65,

    -- Once a narrow-spike sequence has committed a positional shift, preserve
    -- that forward progress. The same wave is never allowed to walk/shift back
    -- toward an earlier strip.
    OVERGROWTH_POST_SHIFT_HOLD = 1.60,
    OVERGROWTH_BACKTRACK_TOLERANCE = 1.25,
    OVERGROWTH_BACKTRACK_LOG_COOLDOWN = 0.70,

    -- V8.2 Overgrowth refinements.
    -- First narrow strip: leave by the SHORTEST edge immediately with normal
    -- walking instead of asking the generic boss planner for a 30-46 stud
    -- destination.
    -- V8.5: the V8.4 direct Humanoid:Move edge sprint could receive the
    -- correct ~10-stud plan but still fail to produce physical displacement.
    -- Return to wall-aware MoveTo and add a measured progress watchdog.
    -- V10.3: the visible/precast strip edge was too tight. V10.1/V10.2
    -- often escaped the first precast but still took one ~25k hit when the
    -- active strip arrived. Give the first escape materially more clearance,
    -- then keep walking outward for ~0.9s instead of immediately cutting back
    -- into the moving sequence.
    OVERGROWTH_FIRST_EDGE_MARGIN = 6.5,
    OVERGROWTH_FIRST_EDGE_MAX_TRAVEL = 18.0,
    OVERGROWTH_EDGE_FOLLOW_ENABLED = true,
    OVERGROWTH_EDGE_FOLLOW_TIME = 0.90,
    OVERGROWTH_EDGE_FOLLOW_STEPS = {9, 7, 5, 3},
    OVERGROWTH_EDGE_FOLLOW_LOG_COOLDOWN = 0.55,
    OVERGROWTH_FORWARD_MIN_CLEARANCE = 8.0,
    OVERGROWTH_EDGE_LOG_COOLDOWN = 0.55,
    OVERGROWTH_EDGE_PROGRESS_TIMEOUT = 0.10,
    OVERGROWTH_EDGE_PROGRESS_MIN = 0.70,
    OVERGROWTH_EDGE_RESCUE_MAX = 14.0,
    OVERGROWTH_EDGE_RESCUE_ONCE = true,
    OVERGROWTH_EDGE_PROACTIVE_SHIFT = true,
    OVERGROWTH_EDGE_PROACTIVE_MAX = 14.0,

    -- Simultaneous long-line batches normally use the exact local gap and
    -- ordinary walking. Only if the player is ACTUALLY inside a live strip may
    -- one bounded rescue shift be used.
    OVERGROWTH_LONGLINE_RESCUE_MAX = 11.5,
    OVERGROWTH_LONGLINE_HOLD_CLEARANCE = 7.0,

    -- Universal dodge movement watchdog. It does not add extra generic
    -- teleports; it only detects a dodge request that is not physically moving
    -- the character and re-resolves to a nearby open safe point.
    DODGE_MOVE_WATCH_TIMEOUT = 0.22,
    DODGE_MOVE_WATCH_MIN_PROGRESS = 0.70,
    DODGE_MOVE_WATCH_TARGET_EPS = 4.0,
    DODGE_MOVE_WATCH_LOG_COOLDOWN = 0.60,

    -- Long-line batch: centers are regularly spaced parallel strips. Solve the
    -- exact gap between adjacent strips and lock that local pocket for the
    -- wave. No map coordinates are hardcoded.
    OVERGROWTH_LONGLINE_MAX_POCKET_TRAVEL = 18.0,
    OVERGROWTH_LONGLINE_MIN_GAP = 5.0,
    OVERGROWTH_LONGLINE_MIN_CLEARANCE = 5.0,
    OVERGROWTH_LONGLINE_LOCK_LOG_COOLDOWN = 0.70,
    OVERGROWTH_LONGLINE_WALK_ONLY_DISTANCE = 14.0,

    -- Diagnostics for abrupt disconnect/kick analysis.
    TELEPORT_BLOCK_LOG_COOLDOWN = 0.70,
    BOSS_HEARTBEAT_INTERVAL = 1.50,
    MOVE_REJECT_LOG_COOLDOWN = 0.80,

    -- Normal combat/approach movement is not allowed to cross live red
    -- geometry while an encounter is still active. Dodge controllers remain
    -- the only systems allowed to solve movement from inside a threat.
    STRICT_RED_ROUTE_LIMIT = 1200,
    STRICT_RED_LOG_COOLDOWN = 0.50,

    -- V8.7 adaptive survival.
    -- Weaker/newer characters get more normal-room spacing while retaining
    -- the same ranged Q/E damage cycle.
    ADAPTIVE_SURVIVAL = true,
    FRAGILE_MAX_HEALTH = 45000,
    LOW_HEALTH_RATIO = 0.42,
    FRAGILE_RANGE_BONUS = 8.0,
    LOW_HEALTH_RANGE_BONUS = 6.0,
    FRAGILE_PHYSICAL_RADIUS_BONUS = 4.0,
    BLOOD_MINION_GLOBAL_PRESSURE_RADIUS = 42.0,

    -- V8.9 boss-add arbitration.
    -- A room-999 Blood Minion may exist while another boss is active. Never
    -- chase it from far away, but if it physically reaches us, temporarily
    -- kill the nearest one instead of tunneling the boss while it free-hits.
    BOSS_ADD_INTERCEPT_ENABLED = true,

    -- Generic local add control. Physical adds get an earlier intercept, but
    -- any hostile spawned inside the active boss encounter can be selected if
    -- it reaches the player. Never chase a distant add away from the boss.
    -- V9.5 boss-majority targeting.
    -- V9.4 spent ~27% of the Overgrowth fight on a Blood Minion even though
    -- the boss was still alive. Adds are now short emergency BURSTS only.
    BOSS_ADD_INTERCEPT_RANGE = 8.5,
    BOSS_ADD_PHYSICAL_INTERCEPT_RANGE = 10.5,
    BOSS_ADD_INTERCEPT_FRAGILE_RANGE = 16.0,
    BOSS_ADD_INTERCEPT_RELEASE_RANGE = 16.0,

    -- One short add burst, then force boss focus for several seconds.
    -- This keeps the boss as the clear majority target while still deleting
    -- an add that is physically on top of the player.
    BOSS_ADD_BURST_MAX = 0.50,
    BOSS_ADD_BURST_COOLDOWN = 5.00,
    BOSS_ADD_CRITICAL_RANGE = 7.5,
    BOSS_ADD_FINISH_HP_RATIO = 0.25,
    BOSS_ADD_INTERCEPT_LOG_COOLDOWN = 0.70,

    -- When a boss dies, finish nearby encounter leftovers before allowing the
    -- next-room target to steal focus. This is deliberately local/bounded so a
    -- preloaded room-999 entity hundreds of studs away is never chased.
    BOSS_POST_CLEANUP_ENABLED = true,
    BOSS_POST_CLEANUP_RADIUS = 78.0,
    BOSS_POST_CLEANUP_RELEASE_RADIUS = 96.0,
    BOSS_POST_CLEANUP_TIMEOUT = 15.0,
    BOSS_POST_CLEANUP_PHYSICAL_BONUS = 900,
    BOSS_POST_CLEANUP_STRENGTH_WEIGHT = 3.0,
    BOSS_POST_CLEANUP_LOG_COOLDOWN = 0.70,

    -- Sticky target hysteresis for ordinary rooms. The old scorer could rotate
    -- between multiple mages/warriors every 0.3 sec and waste approach time.
    TARGET_LOCK_ENABLED = true,
    -- V9.5 strongest-first floor targeting. Once a meaningful target is
    -- chosen, finish it instead of rotating for tiny score differences.
    TARGET_LOCK_MIN_SECONDS = 6.00,
    TARGET_LOCK_RELEASE_DISTANCE = 118.0,
    TARGET_LOCK_FINISH_HP_RATIO = 0.90,
    TARGET_LOCK_SWITCH_MARGIN = 500.0,

    -- A physical enemy may interrupt only when it is actually dangerous,
    -- rather than merely being somewhere within 25 studs.
    TARGET_LOCK_PHYSICAL_OVERRIDE_RANGE = 10.5,
    TARGET_LOCK_PHYSICAL_HOLD_RANGE = 30.0,
    TARGET_LOCK_LOCAL_HOLD_DISTANCE = 96.0,
    TARGET_LOCK_CHALLENGER_DISTANCE_GAIN = 40.0,

    -- Strongest-in-floor weighting. MaxHP is primary evidence of enemy
    -- strength; the existing per-enemy Priority table breaks near-ties.
    TARGET_STRENGTH_MAXHP_WEIGHT = 4.0,
    TARGET_STRENGTH_PRIORITY_WEIGHT = 2.2,
    TARGET_DISTANCE_WEIGHT = 0.55,

    -- Finish an almost-dead CURRENT-FLOOR enemy before committing to a long
    -- move toward the next strongest target. This is intentionally narrow so
    -- strongest-first remains the default behavior.
    LOCAL_FINISH_ENABLED = true,
    LOCAL_FINISH_RANGE = 32.0,
    LOCAL_FINISH_HP_RATIO = 0.18,
    LOCAL_FINISH_PHYSICAL_BONUS = 900.0,
    LOCAL_FINISH_LOG_COOLDOWN = 0.80,

    TARGET_LOCK_LOG_COOLDOWN = 0.80,

    -- Predict fast Blood Minion movement while scoring boss-wave safe points.
    BLOOD_MINION_WAVE_PREDICT_TIME = 0.38,

    -- Earlier reaction for genuinely fast physical closes.
    PHYSICAL_FAST_EMERGENCY_RADIUS = 15.0,
    PHYSICAL_FAST_EMERGENCY_CLOSING = 8.0,
    PHYSICAL_FAST_EMERGENCY_TTC = 0.42,

    -- Only confirmed Demon Warrior attack windows get an actual virtual
    -- damage circle. Previous V6 used a 22-stud virtual threat and overreacted.
    DEMON_WARRIOR_ATTACK_RADIUS = 13.5,
    DEMON_WARRIOR_ATTACK_LIFETIME = 0.62,

    -- Blood Minions behaved unlike an ordinary close-only melee NPC. The log
    -- showed repeated damage from ~23 studs, so V5 gives them a larger safety
    -- envelope and makes them the priority add during Overgrowth.
    BLOOD_MINION_SOFT_RADIUS = 28.0,
    BLOOD_MINION_RELEASE_RADIUS = 34.0,
    BLOOD_MINION_CRITICAL_RADIUS = 16.0,
    BLOOD_MINION_ANIM_THREAT_RADIUS = 27.0,
    BLOOD_MINION_ADD_PRIORITY_RANGE = 80.0,

    -- Boss-wave controller. Collect the near-simultaneous red strips, choose
    -- one lane, then HOLD the decision instead of reacting to every part.
    BOSS_WAVE_COLLECT_WINDOW = 0.14,
    BOSS_WAVE_END_GRACE = 0.30,
    BOSS_WAVE_REPLAN_INTERVAL = 0.20,
    BOSS_WAVE_SAFE_HOLD = 0.24,
    BOSS_WAVE_DIRECTIONS = 24,
    BOSS_WAVE_RADII = {6, 10, 14, 18, 24, 30, 38, 46},
    BOSS_ARENA_CONTROL_DISTANCE = 105.0,

    -- V9.4 range calibration.
    -- V9.3 proved that Infernal Strike is reliable inside ~30 studs and
    -- repeatedly does zero damage at 50-55. Keep bosses in the real damage
    -- envelope instead of orbiting at an assumed long range.
    BOSS_DESIRED_RANGE = {
        ["Demonic Overgrowth"] = 26.0,
        ["Kolvumar"] = 26.0,
        ["Demon Lord Azrallik"] = 28.0,
    },

    -- Normal mage mini-wave controller. Multiple npcMageSpikes arriving
    -- together are solved as ONE geometry problem instead of dodge-flipping
    -- between individual red lines.
    MAGE_WAVE_COLLECT_WINDOW = 0.13,
    MAGE_WAVE_END_GRACE = 0.20,
    MAGE_WAVE_REPLAN_INTERVAL = 0.18,
    MAGE_WAVE_DIRECTIONS = 20,
    MAGE_WAVE_RADII = {4, 7, 10, 14, 18, 23, 29, 34},
    MAGE_WAVE_TELEPORT_MAX = 9.0,

    -- Walking-first teleport policy.
    LINE_WALK_GRACE = 0.20,
    MAGE_WAVE_WALK_GRACE = 0.18,
    BOSS_WAVE_WALK_GRACE = 0.16,
    WALK_ETA_SAFETY = 0.10,

    -- Boss attack timing estimates used only to decide whether the emergency
    -- teleport is actually needed. Normal movement still owns the character.
    BOSS_ATTACK_ETA = {
        ["Demonic Overgrowth"] = 0.75,
        ["Kolvumar"] = 1.45,
        ["Demon Lord Azrallik"] = 0.78,
    },
    MAGE_ATTACK_ETA = 0.78,

    -- Kolvumar spit remains a real floor hazard for a long time, but only a
    -- recently-created spit belongs to the CURRENT boss wave.
    KOLVUMAR_NEW_WAVE_AGE = 3.0,

    -- Skills have long enough reach that Physical does not need to sit inside
    -- the Demon Warrior's attack envelope.
    MELEE_BASIC_SWING_GUARD_RADIUS = 24.0,
    MELEE_TARGET_SKILL_RANGE = 20.0,

    -- Ability scheduler / target lock.
    ABILITY_AIM_LOCK_TIME = 0.32,
    ABILITY_AIM_LEAD_TIME = 0.07,
    ABILITY_SAFE_PREDICT_TIME = 0.18,
    ABILITY_ALLOW_WHILE_DODGING_IF_SAFE = true,

    -- Skill-agnostic result telemetry. The user is intentionally testing
    -- different Q/E skills, so record whether the current target lost HP after
    -- each cast instead of assuming every ability has Lava Lash/Rending Slice
    -- range behavior. This is diagnostic only; it never invents a new remote.
    ABILITY_RESULT_DIAGNOSTIC = true,

    -- V9.1 used one 55-stud range for every Q/E skill. That is wrong for a
    -- mixed loadout. Current test evidence supports Ground Slam as the
    -- short-range skill; Infernal Strike remains the long-range test skill.
    -- Unknown skills still fall back to the active style profile.
    ABILITY_RANGE_HINTS = {
        ["Ground Slam"] = 12.5,
        ["Infernal Strike"] = 30.0,
    },
    ABILITY_RANGE_SKIP_LOG_COOLDOWN = 4.00,

    -- Offense must continue while movement is already handling red-line
    -- geometry. These guards block only genuine close physical danger / very
    -- low health, not a mage line that the movement controller is escaping.
    DODGE_CAST_ENABLED = true,
    DODGE_CAST_MIN_HP_RATIO = 0.30,
    DODGE_CAST_FRAGILE_MIN_HP_RATIO = 0.52,
    DODGE_CAST_PHYSICAL_GUARD = 9.5,
    DODGE_CAST_TTC_GUARD = 0.18,

    -- V10: ordinary physical spacing belongs to PhysicalPressureMove, not the
    -- full dodge state. V9.9 showed many very short physical_emergency
    -- start/clear cycles. Preserve the emergency dodge only for true panic.
    PHYSICAL_DODGE_HANDOFF_ENABLED = true,
    PHYSICAL_DODGE_PANIC_RADIUS = 6.5,
    PHYSICAL_DODGE_PANIC_NEAR_RADIUS = 9.0,
    PHYSICAL_DODGE_PANIC_MIN_CLOSING = 4.0,
    PHYSICAL_DODGE_PANIC_TTC = 0.12,
    PHYSICAL_DODGE_HANDOFF_LOG_COOLDOWN = 0.90,

    -- Keep the strongest/boss as the MOVEMENT target, but spend a ready skill
    -- on a free nearby enemy without repathing or changing the primary lock.
    OPPORTUNISTIC_ATTACK_ENABLED = true,
    OPPORTUNISTIC_NEARBY_MAX = 30.0,
    OPPORTUNISTIC_MAGE_PHYSICAL_GUARD = 18.0,
    OPPORTUNISTIC_PHYSICAL_PRIORITY_RANGE = 14.0,
    OPPORTUNISTIC_BOSS_ADD_RANGE = 10.5,
    OPPORTUNISTIC_BOSS_COOLDOWN = 5.0,
    OPPORTUNISTIC_LOG_COOLDOWN = 0.65,

    -- Mages are geometry threats, NOT proximity/melee threats. When no real
    -- physical attacker is close, keep pressure on the mage while dodging its
    -- red line instead of retreating out of useful skill range.
    MAGE_FREE_PRESSURE_ENABLED = true,
    MAGE_FREE_PRESSURE_ACQUIRE_RANGE = 34.0,
    MAGE_FREE_PRESSURE_PHYSICAL_GUARD = 20.0,
    MAGE_FREE_PRESSURE_DESIRED_RANGE = 10.5,
    MAGE_FREE_PRESSURE_WAVE_TARGET_WEIGHT = 3.40,

    -- V9.9 core rule:
    -- a mage-wave existing is NOT automatically a reason to dodge.
    -- If our current point and near-future point are outside the red geometry,
    -- keep attacking/closing the mage.
    MAGE_SAFE_WINDOW_ATTACK = true,
    MAGE_SAFE_WINDOW_MAX_PREDICTED_INSIDE = 0,
    MAGE_SAFE_WINDOW_LOG_COOLDOWN = 0.90,

    -- When an actual red line forces movement, prefer the smallest safe local
    -- sidestep that keeps us in/near skill range. Fall back to the full solver
    -- only if no such local point exists.
    MAGE_PRESSURE_LOCAL_DODGE_MAX_RADIUS = 18.0,
    MAGE_PRESSURE_MAX_DPS_DISTANCE = 30.0,
    MAGE_PRESSURE_BACKTRACK_TOLERANCE = 2.5,
    MAGE_FREE_PRESSURE_LOG_COOLDOWN = 0.80,

    SHORT_SKILL_STAGING_ENABLED = true,
    SHORT_SKILL_STAGING_SLOT = "q",
    SHORT_SKILL_MAX_RANGE = 20.0,
    SHORT_SKILL_STAGE_BUFFER = 1.5,
    SHORT_SKILL_NORMAL_START_DISTANCE = 22.0,
    SHORT_SKILL_BOSS_START_DISTANCE = 18.0,
    SHORT_SKILL_NORMAL_MIN_HP_RATIO = 0.45,
    SHORT_SKILL_BOSS_MIN_HP_RATIO = 0.70,
    SHORT_SKILL_PHYSICAL_GUARD_RADIUS = 26.0,
    SHORT_SKILL_STAGE_LOG_COOLDOWN = 1.50,
    SHORT_SKILL_TOOL_REFRESH = 0.50,
    SHORT_SKILL_BOSS_ALLOW = {
        -- V9.3 chased bosses from far away for the short skill and lost time.
        -- V10 only stages it when the boss is ALREADY local (<=18 studs) and
        -- ShortSkillOpportunity has confirmed there is no active geometry.
        ["Demonic Overgrowth"] = true,
        ["Kolvumar"] = true,
        ["Demon Lord Azrallik"] = false,
    },

    -- The old 0.42-sec HP sample was too early for these skills and reported
    -- almost everything as zero. Use a later observational sample. This is
    -- telemetry only, not proof that every HP change came from that cast.
    ABILITY_RESULT_DELAY = 0.95,

    -- Avoid firing Q/E on the exact same controller instant. This improves
    -- cast ownership and makes range/result diagnostics less ambiguous without
    -- materially changing normal cooldown DPS.
    ABILITY_CAST_CHAIN_GAP = 0.16,

    -- Threat lifecycle. Boss hazards can visually remain after the boss dies.
    -- They stop controlling movement once their source room/boss is finished.
    ROOM_TRANSITION_HAZARD_GRACE = 0.20,
    BOSS_DEAD_HAZARD_GRACE = 0.12,
    FINAL_BOSS_POST_DEATH_HAZARD_GRACE = 1.20,

    -- Main loop.
    THINK_INTERVAL = 0.045,
    MOVE_REFRESH = 0.07,
    TARGET_REFRESH = 0.30,

    -- Threat planning.
    SAFETY_MARGIN = 2.0,
    CANDIDATE_DIRECTIONS = 16,
    CANDIDATE_RADII = {4, 7, 11, 16, 24, 32},
    PATH_SAMPLES = 2,

    -- Performance: don't rebuild a full escape search every heartbeat.
    DODGE_REPLAN_INTERVAL = 0.12,
    ENEMY_CACHE_INTERVAL = 0.28,
    ANIMATION_DEDUPE_WINDOW = 0.12,
    DIRECT_ESCAPE_EXTRA = 1.35,

    -- Enemy spacing.
    PHYSICAL_RANGE = 20.0,
    TANK_RANGE = 8.5,
    SPELL_RANGE = 34.0,

    PHYSICAL_ABILITY_RANGE = 55,
    TANK_ABILITY_RANGE = 45,
    SPELL_ABILITY_RANGE = 70,

    BASIC_SWING_RANGE_PHYSICAL = 11,
    BASIC_SWING_RANGE_TANK = 10,
    BASIC_SWING_RANGE_SPELL = 45,

    BASIC_SWING_COOLDOWN = 0.38,

    -- Passive orbiting makes targeted line attacks harder to land.
    ORBIT_OFFSET = 5.5,
    ORBIT_SWITCH_SECONDS = 3.2,

    -- Close-range animation prediction.
    MELEE_PREDICT_RADIUS = 12.0,
    MELEE_PREDICT_LIFETIME = 0.80,

    -- Navigation.
    REPATH_INTERVAL = 1.1,
    WAYPOINT_REACHED = 5.0,
    STUCK_SECONDS = 1.05,
    STALL_BREAK_AFTER_ATTEMPTS = 4,

    -- File/log.
    FLUSH_INTERVAL = 0.50,
}

-- ============================================================
-- Style profiles
-- ============================================================

local STYLES = {
    Physical = {
        DesiredRange = CFG.PHYSICAL_RANGE,
        AbilityRange = CFG.PHYSICAL_ABILITY_RANGE,
        BasicRange = CFG.BASIC_SWING_RANGE_PHYSICAL,

        -- Physical should still dodge aggressively.
        EnemyBuffer = 7.0,

        -- Dangerous ranged mobs first.
        Priority = {
            ["Elder Dark Mage"] = 140,
            ["Dark Mage"] = 130,
            ["Demon Warrior"] = 170,
            ["Blood Minion"] = 460,

            ["Demonic Overgrowth"] = 300,
            ["Kolvumar"] = 300,
            ["Demon Lord Azrallik"] = 350,
            ["Azrallik's Heart"] = 360,
        },
    },

    Tank = {
        DesiredRange = CFG.TANK_RANGE,
        AbilityRange = CFG.TANK_ABILITY_RANGE,
        BasicRange = CFG.BASIC_SWING_RANGE_TANK,
        EnemyBuffer = 5.5,

        Priority = {
            ["Elder Dark Mage"] = 135,
            ["Dark Mage"] = 125,
            ["Demon Warrior"] = 170,
            ["Blood Minion"] = 460,

            ["Demonic Overgrowth"] = 300,
            ["Kolvumar"] = 300,
            ["Demon Lord Azrallik"] = 350,
            ["Azrallik's Heart"] = 360,
        },
    },

    Spell = {
        DesiredRange = CFG.SPELL_RANGE,
        AbilityRange = CFG.SPELL_ABILITY_RANGE,
        BasicRange = CFG.BASIC_SWING_RANGE_SPELL,
        EnemyBuffer = 10.0,

        Priority = {
            ["Elder Dark Mage"] = 145,
            ["Dark Mage"] = 135,
            ["Demon Warrior"] = 150,
            ["Blood Minion"] = 450,

            ["Demonic Overgrowth"] = 300,
            ["Kolvumar"] = 300,
            ["Demon Lord Azrallik"] = 350,
            ["Azrallik's Heart"] = 360,
        },
    },
}

local Profile = STYLES[CFG.STYLE] or STYLES.Physical

-- ============================================================
-- Runtime ownership
-- ============================================================

local ENV = getgenv and getgenv() or _G
local RUNTIME_KEY = "__SERENITY_DQR_UNDERWORLD_COMBAT_V10_3"

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
}) do
    local previous = ENV[oldKey]

    if previous and type(previous.Stop) == "function" then
        pcall(previous.Stop, "upgrade_to_v10_3")
    end
end

local Runtime = {
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
}

ENV[RUNTIME_KEY] = Runtime

local function connect(signal, fn)
    local c = signal:Connect(fn)
    Runtime.Connections[#Runtime.Connections + 1] = c
    return c
end

local function disconnectAll()
    for _, c in ipairs(Runtime.Connections) do
        pcall(function()
            c:Disconnect()
        end)
    end
    table.clear(Runtime.Connections)
end

-- ============================================================
-- Logging
-- ============================================================

local BASE = "DQR_Underworld_Test_V10_3"
local LOG_PATH =
    BASE .. "/Underworld_Combat_V10_3_" .. tostring(os.time()) .. ".txt"

if type(makefolder) == "function" then
    pcall(function()
        if type(isfolder) ~= "function" or not isfolder(BASE) then
            makefolder(BASE)
        end
    end)
end

local logBuffer = {}
local bootClock = os.clock()

local function flush()
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

local function log(tag, text)
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

local function logKV(tag, data)
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


local function markCompletion(source)
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

local function completionTextMatch(inst)
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

local function bindCompletionSignals()
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

-- ============================================================
-- Helpers
-- ============================================================

local function fullName(inst)
    if not inst then return "nil" end

    local ok, result = pcall(function()
        return inst:GetFullName()
    end)

    return ok and result or tostring(inst)
end

local function horizontal(v)
    return Vector3.new(v.X, 0, v.Z)
end

local function horizontalDistance(a, b)
    return horizontal(a - b).Magnitude
end

local function unitHorizontal(v)
    local h = horizontal(v)

    if h.Magnitude < 1e-5 then
        return Vector3.new(1, 0, 0)
    end

    return h.Unit
end

local function vec(v)
    return string.format("(%.2f,%.2f,%.2f)", v.X, v.Y, v.Z)
end

local function getCharacter()
    local char = LP.Character
    if not char then return nil,nil,nil end

    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")

    return char,hum,root
end

local activeThreatCount = function()
    return 0
end

local function bindCharacter(char)
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

-- ============================================================
-- Enemy discovery
-- ============================================================

local function modelRoot(model)
    if not model then return nil end

    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end

local function modelHumanoid(model)
    return model and model:FindFirstChildOfClass("Humanoid")
end

local function roomIndexFor(inst)
    local cur = inst

    while cur and cur ~= workspace do
        local n = cur.Name

        local idx = n:match("^room(%d+)$")
        if idx then
            return tonumber(idx)
        end

        if n == "bossRoom" then
            return 999
        end

        cur = cur.Parent
    end

    return 0
end

local function rebuildEnemyCache()
    local dungeon = workspace:FindFirstChild("dungeon")
    local result = {}

    if dungeon then
        for _, inst in ipairs(dungeon:GetDescendants()) do
            if inst:IsA("Humanoid") and inst.Health > 0 then
                local model = inst.Parent

                if model
                    and model:IsA("Model")
                    and Players:GetPlayerFromCharacter(model) == nil
                then
                    local root = modelRoot(model)

                    if root then
                        result[#result + 1] = {
                            Model = model,
                            Humanoid = inst,
                            Root = root,
                            RoomIndex = roomIndexFor(model),
                        }
                    end
                end
            end
        end
    end

    -- Boss adds that may be parented outside workspace.dungeon.
    for _, inst in ipairs(workspace:GetChildren()) do
        if inst:IsA("Model")
            and inst ~= Runtime.Character
            and Players:GetPlayerFromCharacter(inst) == nil
            and (inst.Name == "Blood Minion" or inst.Name == "Azrallik's Heart")
        then
            local hum = modelHumanoid(inst)
            local root = modelRoot(inst)

            if hum and root and hum.Health > 0 then
                result[#result + 1] = {
                    Model = inst,
                    Humanoid = hum,
                    Root = root,
                    RoomIndex = 999,
                }
            end
        end
    end

    Runtime.EnemyCache = result
    Runtime.EnemyCacheAt = os.clock()

    return result
end

local function livingEnemies(force)
    local now = os.clock()

    if force
        or now - Runtime.EnemyCacheAt >= CFG.ENEMY_CACHE_INTERVAL
    then
        return rebuildEnemyCache()
    end

    return Runtime.EnemyCache
end

-- V7.7 strict encounter scoping.
--
-- Important discovery:
-- workspace-root Blood Minions are labeled room 999. They may already exist
-- while an earlier boss (especially Demonic Overgrowth) is active. V7.6
-- allowed room 999 in every selectTarget pass, so it abandoned Overgrowth,
-- tried to path toward an inaccessible future Blood Minion, and became stuck.
local function enemyRelevantForEncounter(enemy)
    if not enemy
        or not enemy.Model
        or not enemy.Humanoid
        or enemy.Humanoid.Health <= 0
        or not enemy.Root
        or not enemy.Root.Parent
    then
        return false
    end

    -- The active boss itself is always relevant.
    if Runtime.ActiveBossModel
        and enemy.Model == Runtime.ActiveBossModel
    then
        return true
    end

    local room =
        enemy.RoomIndex or 0

    -- Normal/current encounter.
    if Runtime.CurrentRoomIndex > 0
        and room == Runtime.CurrentRoomIndex
    then
        return true
    end

    -- room 999 entities are ONLY legal during the final encounter / cleanup.
    if room == 999 then
        return
            Runtime.CurrentRoomIndex == 999
            or Runtime.ActiveBossName == "Demon Lord Azrallik"
            or Runtime.FinalBossDefeated
    end

    -- Startup only: selectTarget will immediately infer the lowest live room.
    return Runtime.CurrentRoomIndex == 0
end


-- ============================================================
-- Proactive physical/melee classification
-- ============================================================

local PHYSICAL_ENEMY_NAMES = {
    ["Demon Warrior"] = true,
    ["Blood Minion"] = true,
}

local BOSS_ENEMY_NAMES = {
    ["Demonic Overgrowth"] = true,
    ["Kolvumar"] = true,
    ["Demon Lord Azrallik"] = true,
}

local KOLVUMAR_DIRECT_ATTACK_ANIMS = {
    ["rbxassetid://89702140030707"] = true,
}

local DEMON_WARRIOR_ATTACK_ANIMS = {
    ["rbxassetid://107260711747781"] = true,
}

local function isPhysicalEnemyModel(model)
    return model ~= nil and PHYSICAL_ENEMY_NAMES[model.Name] == true
end

local function physicalThreatRelevantForMovement(
    enemy,
    point
)
    if enemyRelevantForEncounter(enemy) then
        return true
    end

    -- A future room-999 Blood Minion must never steal the target before the
    -- final encounter, but if it is already close enough to physically hit the
    -- player it must still affect movement.
    if enemy
        and enemy.Model
        and enemy.Model.Name == "Blood Minion"
        and enemy.Root
        and point
    then
        return
            horizontalDistance(
                point,
                enemy.Root.Position
            )
            <= CFG.BLOOD_MINION_GLOBAL_PRESSURE_RADIUS
    end

    return false
end


local function physicalClosingInfo(enemy, point)
    if not enemy or not enemy.Root or not Runtime.Root then
        return CFG.MELEE_SOFT_RADIUS, 0, math.huge
    end

    local enemyPos = enemy.Root.Position
    local dist = horizontalDistance(point, enemyPos)
    local away = unitHorizontal(point - enemyPos)

    local enemyVel = horizontal(enemy.Root.AssemblyLinearVelocity)
    local playerVel = horizontal(Runtime.Root.AssemblyLinearVelocity)

    -- Positive = enemy is closing the distance.
    local closing = (enemyVel - playerVel):Dot(away)

    local bonus =
        math.clamp(
            math.max(closing, 0) * CFG.MELEE_DYNAMIC_HORIZON,
            0,
            CFG.MELEE_DYNAMIC_MAX_BONUS
        )

    local baseRadius = CFG.MELEE_SOFT_RADIUS
    local panicRadius = CFG.MELEE_PANIC_RADIUS

    if enemy.Model and enemy.Model.Name == "Blood Minion" then
        baseRadius = CFG.BLOOD_MINION_SOFT_RADIUS
        panicRadius = CFG.BLOOD_MINION_CRITICAL_RADIUS
    end

    local survivalBonus = 0

    if CFG.ADAPTIVE_SURVIVAL
        and Runtime.Humanoid
    then
        local hpRatio =
            Runtime.Humanoid.MaxHealth > 0
            and (
                Runtime.Humanoid.Health
                / Runtime.Humanoid.MaxHealth
            )
            or 1

        if Runtime.FragileMode
            or hpRatio <= CFG.LOW_HEALTH_RATIO
        then
            survivalBonus =
                CFG.FRAGILE_PHYSICAL_RADIUS_BONUS
        end
    end

    local radius =
        baseRadius
        + bonus
        + survivalBonus

    local timeToContact = math.huge
    if closing > 0.5 then
        timeToContact =
            math.max(0, dist - panicRadius) / closing
    end

    return radius, closing, timeToContact
end

local function nearestPhysicalEnemy(point)
    local best, bestDist

    for _, enemy in ipairs(livingEnemies()) do
        if enemy.Root
            and enemy.Root.Parent
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and isPhysicalEnemyModel(enemy.Model)
            and physicalThreatRelevantForMovement(
                enemy,
                point
            )
        then
            local d = horizontalDistance(point, enemy.Root.Position)

            if not bestDist or d < bestDist then
                best = enemy
                bestDist = d
            end
        end
    end

    return best, bestDist or math.huge
end

local function physicalEnemiesNear(point, radius)
    local out = {}

    for _, enemy in ipairs(livingEnemies()) do
        if enemy.Root
            and enemy.Root.Parent
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and isPhysicalEnemyModel(enemy.Model)
            and physicalThreatRelevantForMovement(
                enemy,
                point
            )
        then
            local d = horizontalDistance(point, enemy.Root.Position)

            if d <= radius then
                out[#out + 1] = {
                    Enemy = enemy,
                    Distance = d,
                }
            end
        end
    end

    return out
end

Runtime.ShortSkillOpportunity = function()
    if not CFG.SHORT_SKILL_STAGING_ENABLED
        or not Runtime.Root
        or not Runtime.Target
        or not Runtime.TargetRoot
        or not Runtime.TargetHumanoid
        or Runtime.TargetHumanoid.Health <= 0
        or Runtime.DodgeActive
        or Runtime.BossWave
        or activeThreatCount() > 0
    then
        return nil
    end

    if isPhysicalEnemyModel(Runtime.Target) then
        return nil
    end

    local char = Runtime.Character
    if not char then
        return nil
    end

    local busy = char:FindFirstChild("busyCasting")
    if busy and busy.Value == true then
        return nil
    end

    local now = os.clock()
    local tool = Runtime.ShortSkillTool

    if not tool
        or not tool.Parent
        or now - Runtime.LastShortSkillToolProbe
            >= CFG.SHORT_SKILL_TOOL_REFRESH
    then
        Runtime.LastShortSkillToolProbe = now
        tool = nil

        local backpack =
            LP:FindFirstChild("Backpack")

        for _, container in ipairs({
            backpack,
            char,
        }) do
            if container then
                for _, candidate in ipairs(
                    container:GetChildren()
                ) do
                    if candidate:IsA("Tool") then
                        local slotValue =
                            candidate:FindFirstChild(
                                "abilitySlot"
                            )

                        if slotValue
                            and tostring(slotValue.Value)
                                == CFG.SHORT_SKILL_STAGING_SLOT
                        then
                            tool = candidate
                            break
                        end
                    end
                end
            end

            if tool then
                break
            end
        end

        Runtime.ShortSkillTool = tool
    end

    if not tool
        or not tool:FindFirstChild("localEvent")
    then
        return nil
    end

    local readyAt =
        Runtime.LastAbilityCast[CFG.SHORT_SKILL_STAGING_SLOT]
        or -math.huge

    if now < readyAt then
        return nil
    end

    local cooldown = tool:FindFirstChild("cooldown")

    if cooldown
        and tonumber(cooldown.Value)
        and cooldown.Value > 0
    then
        return nil
    end

    local abilityRange =
        CFG.ABILITY_RANGE_HINTS[tool.Name]
        or Profile.AbilityRange

    for _, attributeName in ipairs({
        "Range",
        "range",
        "CastRange",
        "castRange",
        "AbilityRange",
        "abilityRange",
    }) do
        local ok, value =
            pcall(function()
                return tool:GetAttribute(attributeName)
            end)

        if ok
            and type(value) == "number"
            and value > 0
        then
            abilityRange = value
            break
        end
    end

    if abilityRange > CFG.SHORT_SKILL_MAX_RANGE then
        return nil
    end

    local hpRatio =
        Runtime.Humanoid
        and Runtime.Humanoid.MaxHealth > 0
        and (
            Runtime.Humanoid.Health
            / Runtime.Humanoid.MaxHealth
        )
        or 1

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            Runtime.TargetRoot.Position
        )

    if Runtime.ActiveBossName then
        if not CFG.SHORT_SKILL_BOSS_ALLOW[Runtime.ActiveBossName] then
            return nil
        end

        if Runtime.FragileMode
            or hpRatio < CFG.SHORT_SKILL_BOSS_MIN_HP_RATIO
            or distance > CFG.SHORT_SKILL_BOSS_START_DISTANCE
        then
            return nil
        end
    else
        if hpRatio < CFG.SHORT_SKILL_NORMAL_MIN_HP_RATIO
            or distance > CFG.SHORT_SKILL_NORMAL_START_DISTANCE
        then
            return nil
        end

        local physical, physicalDistance =
            nearestPhysicalEnemy(Runtime.Root.Position)

        if physical
            and physical.Model ~= Runtime.Target
            and physicalDistance
                <= CFG.SHORT_SKILL_PHYSICAL_GUARD_RADIUS
        then
            return nil
        end
    end

    local stageRange =
        math.max(
            6.0,
            abilityRange - CFG.SHORT_SKILL_STAGE_BUFFER
        )

    if now - Runtime.LastShortSkillStageLog
        >= CFG.SHORT_SKILL_STAGE_LOG_COOLDOWN
    then
        Runtime.LastShortSkillStageLog = now

        logKV("SHORT_SKILL_STAGE", {
            skill = tool.Name,
            distance = string.format("%.1f", distance),
            stage_range = string.format("%.1f", stageRange),
            boss = tostring(Runtime.ActiveBossName or "none"),
        })
    end

    return stageRange
end


Runtime.MageFreePressureActive = function()
    if not CFG.MAGE_FREE_PRESSURE_ENABLED
        or Runtime.ActiveBossName
        or not Runtime.Root
        or not Runtime.Target
        or not Runtime.TargetRoot
        or not Runtime.TargetHumanoid
        or Runtime.TargetHumanoid.Health <= 0
    then
        return false
    end

    local targetName =
        string.lower(
            tostring(
                Runtime.Target.Name
            )
        )

    if not string.find(
        targetName,
        "mage",
        1,
        true
    ) then
        return false
    end

    local physical, physicalDistance =
        nearestPhysicalEnemy(
            Runtime.Root.Position
        )

    if physical
        and physicalDistance
            <= CFG.MAGE_FREE_PRESSURE_PHYSICAL_GUARD
    then
        return false
    end

    return true
end


local function desiredRangeForTarget()
    if Runtime.MageFreePressureActive
        and Runtime.MageFreePressureActive()
    then
        return CFG.MAGE_FREE_PRESSURE_DESIRED_RANGE
    end

    local shortSkillRange =
        Runtime.ShortSkillOpportunity
        and Runtime.ShortSkillOpportunity()

    if shortSkillRange then
        return shortSkillRange
    end

    if Runtime.Target
        and Runtime.Target.Name == "Azrallik's Heart"
    then
        return CFG.AZRALLIK_HEART_ATTACK_RANGE
    end

    if Runtime.Target and CFG.BOSS_DESIRED_RANGE[Runtime.Target.Name] then
        return math.max(
            Profile.DesiredRange,
            CFG.BOSS_DESIRED_RANGE[Runtime.Target.Name]
        )
    end

    if CFG.PROACTIVE_MELEE_AVOIDANCE and Runtime.Target then
        if isPhysicalEnemyModel(Runtime.Target) then
            return math.max(Profile.DesiredRange, CFG.MELEE_TARGET_SKILL_RANGE)
        end

        -- If a physical mob is sharing the room, avoid diving to point-blank
        -- range on a mage just to basic-swing it.
        if Runtime.Root then
            local _, d = nearestPhysicalEnemy(Runtime.Root.Position)
            if d <= CFG.MELEE_SOFT_RADIUS + 8 then
                return math.max(Profile.DesiredRange, CFG.MELEE_TARGET_SKILL_RANGE)
            end
        end
    end

    local desired =
        Profile.DesiredRange

    if CFG.ADAPTIVE_SURVIVAL
        and Runtime.Humanoid
    then
        local hpRatio =
            Runtime.Humanoid.MaxHealth > 0
            and (
                Runtime.Humanoid.Health
                / Runtime.Humanoid.MaxHealth
            )
            or 1

        if Runtime.FragileMode then
            desired +=
                CFG.FRAGILE_RANGE_BONUS
        end

        if hpRatio <= CFG.LOW_HEALTH_RATIO then
            desired +=
                CFG.LOW_HEALTH_RANGE_BONUS
        end
    end

    return desired
end

local function targetScore(enemy)
    if not Runtime.Root
        or not enemyRelevantForEncounter(enemy)
    then
        return -math.huge
    end

    local name = enemy.Model.Name
    local pri = Profile.Priority[name] or 80

    local dist =
        horizontalDistance(
            enemy.Root.Position,
            Runtime.Root.Position
        )

    -- V6: stacked mages were the largest remaining normal-room damage source.
    -- If multiple mages share the active room, prioritize deleting that red-line
    -- pressure instead of letting several synchronized casts build up.
    if name == "Dark Mage" or name == "Elder Dark Mage" then
        local mageCount = 0

        for _, other in ipairs(livingEnemies()) do
            if other.RoomIndex == enemy.RoomIndex
                and other.Model
                and (
                    other.Model.Name == "Dark Mage"
                    or other.Model.Name == "Elder Dark Mage"
                )
            then
                mageCount += 1
            end
        end

        if mageCount >= 2 then
            pri += 70 + (mageCount - 2) * 20
        end
    end

    -- V7.2: if a normal physical enemy is already close enough to pin the
    -- player, kill it instead of endlessly kiting it while aiming at a distant
    -- mage. This is especially important near walls.
    if name == "Demon Warrior" then
        if dist <= 14 then
            pri += 1100
        elseif dist <= 20 then
            pri += 700
        elseif dist <= 26 then
            pri += 320
        end
    end

    -- V6 boss add rule: Blood Minions become the immediate target when they
    -- are close enough to pressure the player. Do not tunnel the boss while
    -- an add is already in its dangerous/lunge range.
    if Runtime.ActiveBossName == "Demon Lord Azrallik"
        and name == "Blood Minion"
        and enemy.RoomIndex == 999
        and dist <= CFG.BLOOD_MINION_ADD_PRIORITY_RANGE
    then
        pri += 1000
    end

    -- Higher room means progression, but never skip living current-room mobs.
    local roomBonus =
        enemy.RoomIndex == Runtime.CurrentRoomIndex
        and 35
        or 0

    local lowHpBonus =
        enemy.Humanoid.MaxHealth > 0
        and (1 - enemy.Humanoid.Health / enemy.Humanoid.MaxHealth) * 15
        or 0

    local maxHealthMillions =
        enemy.Humanoid.MaxHealth > 0
        and (
            enemy.Humanoid.MaxHealth
            / 1000000
        )
        or 0

    local strengthBonus =
        maxHealthMillions
            * CFG.TARGET_STRENGTH_MAXHP_WEIGHT
        + pri
            * CFG.TARGET_STRENGTH_PRIORITY_WEIGHT

    -- Distance is intentionally a weak tiebreaker now. The strongest relevant
    -- enemy in the active floor should not lose focus merely because another
    -- weaker enemy happens to be a few studs closer.
    return
        strengthBonus
        + roomBonus
        + lowHpBonus
        - dist * CFG.TARGET_DISTANCE_WEIGHT
end

local function bossAddInterceptRange()
    if Runtime.FragileMode then
        return
            CFG.BOSS_ADD_INTERCEPT_FRAGILE_RANGE
    end

    return
        CFG.BOSS_ADD_INTERCEPT_RANGE
end

local function clearBossAddFocus(reason)
    if Runtime.BossAddFocusModel then
        local now = os.clock()

        if now - Runtime.LastBossAddFocusLog
            >= CFG.BOSS_ADD_INTERCEPT_LOG_COOLDOWN
        then
            Runtime.LastBossAddFocusLog = now

            logKV("BOSS_ADD_FOCUS_END", {
                add =
                    Runtime.BossAddFocusModel.Name,
                reason = tostring(reason),
            })
        end
    end

    Runtime.BossAddFocusModel = nil
    Runtime.BossAddFocusStartedAt = nil
end

local function chooseBossAddIntercept(enemies)
    if not CFG.BOSS_ADD_INTERCEPT_ENABLED
        or not Runtime.Root
        or not Runtime.ActiveBossName
        or Runtime.AzrallikHeartPhaseActive
    then
        clearBossAddFocus("disabled_or_phase")
        return nil
    end

    local now = os.clock()

    -- Continue only the CURRENT short burst.
    if Runtime.BossAddFocusModel
        and Runtime.BossAddFocusModel.Parent
        and now <= (
            Runtime.BossAddFocusUntil
            or -math.huge
        )
    then
        for _, enemy in ipairs(enemies) do
            if enemy.Model
                == Runtime.BossAddFocusModel
                and enemy.Humanoid
                and enemy.Humanoid.Health > 0
                and enemy.Root
            then
                local d =
                    horizontalDistance(
                        enemy.Root.Position,
                        Runtime.Root.Position
                    )

                if d
                    <= CFG.BOSS_ADD_INTERCEPT_RELEASE_RANGE
                then
                    return enemy
                end

                break
            end
        end
    end

    -- Burst ended: force boss focus for a real cooldown window.
    if Runtime.BossAddFocusModel then
        Runtime.BossAddCooldownUntil =
            math.max(
                Runtime.BossAddCooldownUntil
                    or -math.huge,
                now
                    + CFG.BOSS_ADD_BURST_COOLDOWN
            )

        clearBossAddFocus("burst_complete")
    end

    local best
    local bestScore = -math.huge
    local criticalCandidate = false

    for _, enemy in ipairs(enemies) do
        if enemy.Model
            and enemy.Model ~= Runtime.ActiveBossModel
            and enemy.Model.Name ~= "Azrallik's Heart"
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and enemy.Root
        then
            local d =
                horizontalDistance(
                    enemy.Root.Position,
                    Runtime.Root.Position
                )

            local physical =
                isPhysicalEnemyModel(
                    enemy.Model
                )

            local range =
                Runtime.FragileMode
                and CFG.BOSS_ADD_INTERCEPT_FRAGILE_RANGE
                or (
                    physical
                    and CFG.BOSS_ADD_PHYSICAL_INTERCEPT_RANGE
                    or CFG.BOSS_ADD_INTERCEPT_RANGE
                )

            local room =
                enemy.RoomIndex or 0

            local localEncounterAdd =
                room == Runtime.CurrentRoomIndex
                or room == 999
                or d <= 12

            if localEncounterAdd
                and d <= range
            then
                local eReady =
                    now >= (
                        Runtime.LastAbilityCast["e"]
                        or -math.huge
                    )

                local qReady =
                    now >= (
                        Runtime.LastAbilityCast["q"]
                        or -math.huge
                    )

                local immediateShot =
                    (
                        eReady
                        and d <= (
                            CFG.ABILITY_RANGE_HINTS["Infernal Strike"]
                            or 30
                        )
                    )
                    or (
                        qReady
                        and d <= (
                            CFG.ABILITY_RANGE_HINTS["Ground Slam"]
                            or 14
                        )
                    )

                -- If no damage skill is immediately available, keep offense on
                -- the boss. The movement/threat engine still dodges this add.
                if not immediateShot then
                    continue
                end

                local hpRatio =
                    enemy.Humanoid.MaxHealth > 0
                    and (
                        enemy.Humanoid.Health
                        / enemy.Humanoid.MaxHealth
                    )
                    or 1

                local critical =
                    d <= CFG.BOSS_ADD_CRITICAL_RANGE

                local finishable =
                    hpRatio
                        <= CFG.BOSS_ADD_FINISH_HP_RATIO

                -- During the forced boss-focus cooldown, only an enemy that is
                -- literally in critical melee range may interrupt again.
                if now >= (
                    Runtime.BossAddCooldownUntil
                    or -math.huge
                )
                    or critical
                then
                    local maxHealthMillions =
                        enemy.Humanoid.MaxHealth
                        / 1000000

                    local profilePri =
                        Profile.Priority[
                            enemy.Model.Name
                        ]
                        or 80

                    local score =
                        (critical and 5000 or 0)
                        + (physical and 1500 or 400)
                        + (finishable and 500 or 0)
                        + maxHealthMillions * 24
                        + profilePri * 2
                        - d * 22

                    if score > bestScore then
                        bestScore = score
                        best = enemy
                        criticalCandidate = critical
                    end
                end
            end
        end
    end

    if not best then
        return nil
    end

    Runtime.BossAddFocusModel =
        best.Model
    Runtime.BossAddFocusStartedAt =
        now
    Runtime.BossAddFocusUntil =
        now + CFG.BOSS_ADD_BURST_MAX

    if now - Runtime.LastBossAddFocusLog
        >= CFG.BOSS_ADD_INTERCEPT_LOG_COOLDOWN
    then
        Runtime.LastBossAddFocusLog = now

        logKV("BOSS_ADD_BURST_START", {
            boss =
                tostring(
                    Runtime.ActiveBossName
                ),
            add =
                best.Model.Name,
            distance =
                string.format(
                    "%.1f",
                    horizontalDistance(
                        best.Root.Position,
                        Runtime.Root.Position
                    )
                ),
            hp =
                math.floor(
                    best.Humanoid.Health
                ),
            critical =
                tostring(
                    criticalCandidate
                ),
            burst =
                string.format(
                    "%.2f",
                    CFG.BOSS_ADD_BURST_MAX
                ),
        })
    end

    return best
end

-- ------------------------------------------------------------
-- Generic post-boss cleanup.
-- Runtime table methods avoid consuming more top-level local registers.
-- ------------------------------------------------------------

Runtime.BeginBossCleanup = function(oldBossName)
    if not CFG.BOSS_POST_CLEANUP_ENABLED
        or not Runtime.Root
        or not oldBossName
    then
        return
    end

    Runtime.BossCleanupModels = {}
    Runtime.BossCleanupBoss = oldBossName
    Runtime.BossCleanupUntil =
        os.clock()
        + CFG.BOSS_POST_CLEANUP_TIMEOUT
    Runtime.BossCleanupTarget = nil

    local captured = 0

    for _, enemy in ipairs(
        livingEnemies()
    ) do
        if enemy.Model
            and enemy.Model.Name ~= oldBossName
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and enemy.Root
        then
            local d =
                horizontalDistance(
                    enemy.Root.Position,
                    Runtime.Root.Position
                )

            local room =
                enemy.RoomIndex or 0

            local sameEncounter =
                room == Runtime.CurrentRoomIndex
                or room == 999
                or room == 0

            if sameEncounter
                and d <= CFG.BOSS_POST_CLEANUP_RADIUS
            then
                Runtime.BossCleanupModels[
                    enemy.Model
                ] = true

                captured += 1
            end
        end
    end

    -- The active boss-add focus is always part of cleanup if still alive,
    -- even if its room metadata is unusual.
    if Runtime.BossAddFocusModel
        and Runtime.BossAddFocusModel.Parent
    then
        Runtime.BossCleanupModels[
            Runtime.BossAddFocusModel
        ] = true
    end

    if captured > 0
        or Runtime.BossAddFocusModel
    then
        logKV("BOSS_CLEANUP_START", {
            boss = tostring(oldBossName),
            captured = captured,
            timeout =
                string.format(
                    "%.1f",
                    CFG.BOSS_POST_CLEANUP_TIMEOUT
                ),
        })
    end
end

Runtime.ChooseBossCleanupTarget = function(enemies)
    if not Runtime.Root
        or not Runtime.BossCleanupBoss
    then
        return nil
    end

    local now = os.clock()

    if now > Runtime.BossCleanupUntil then
        if now - Runtime.LastBossCleanupLog
            >= CFG.BOSS_POST_CLEANUP_LOG_COOLDOWN
        then
            Runtime.LastBossCleanupLog = now

            logKV("BOSS_CLEANUP_END", {
                boss =
                    tostring(
                        Runtime.BossCleanupBoss
                    ),
                reason = "timeout",
            })
        end

        Runtime.BossCleanupModels = {}
        Runtime.BossCleanupBoss = nil
        Runtime.BossCleanupTarget = nil
        return nil
    end

    local aliveByModel = {}

    for _, enemy in ipairs(enemies) do
        aliveByModel[enemy.Model] = enemy
    end

    -- Keep finishing the current cleanup target if it is still local.
    if Runtime.BossCleanupTarget then
        local focused =
            aliveByModel[
                Runtime.BossCleanupTarget
            ]

        if focused
            and focused.Humanoid
            and focused.Humanoid.Health > 0
            and focused.Root
        then
            local d =
                horizontalDistance(
                    focused.Root.Position,
                    Runtime.Root.Position
                )

            if d
                <= CFG.BOSS_POST_CLEANUP_RELEASE_RADIUS
            then
                return focused
            end
        end

        Runtime.BossCleanupModels[
            Runtime.BossCleanupTarget
        ] = nil

        Runtime.BossCleanupTarget = nil
    end

    local best
    local bestScore = -math.huge
    local remaining = 0

    for model in pairs(
        Runtime.BossCleanupModels
    ) do
        local enemy =
            aliveByModel[model]

        if enemy
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and enemy.Root
        then
            local d =
                horizontalDistance(
                    enemy.Root.Position,
                    Runtime.Root.Position
                )

            if d
                <= CFG.BOSS_POST_CLEANUP_RELEASE_RADIUS
            then
                remaining += 1

                local physical =
                    isPhysicalEnemyModel(
                        enemy.Model
                    )

                local hpRatio =
                    enemy.Humanoid.MaxHealth > 0
                    and (
                        enemy.Humanoid.Health
                        / enemy.Humanoid.MaxHealth
                    )
                    or 1

                local maxHealthMillions =
                    enemy.Humanoid.MaxHealth
                    / 1000000

                local profilePri =
                    Profile.Priority[
                        enemy.Model.Name
                    ]
                    or 80

                local score =
                    maxHealthMillions
                        * CFG.BOSS_POST_CLEANUP_STRENGTH_WEIGHT
                    + profilePri * 2.0
                    + (
                        physical
                        and CFG.BOSS_POST_CLEANUP_PHYSICAL_BONUS
                        or 0
                    )
                    - d * 7
                    + (1 - hpRatio) * 650

                if score > bestScore then
                    bestScore = score
                    best = enemy
                end
            else
                Runtime.BossCleanupModels[
                    model
                ] = nil
            end
        else
            Runtime.BossCleanupModels[
                model
            ] = nil
        end
    end

    if best then
        Runtime.BossCleanupTarget =
            best.Model

        if now - Runtime.LastBossCleanupLog
            >= CFG.BOSS_POST_CLEANUP_LOG_COOLDOWN
        then
            Runtime.LastBossCleanupLog = now

            logKV("BOSS_CLEANUP_TARGET", {
                boss =
                    tostring(
                        Runtime.BossCleanupBoss
                    ),
                target =
                    best.Model.Name,
                physical =
                    tostring(
                        isPhysicalEnemyModel(
                            best.Model
                        )
                    ),
                distance =
                    string.format(
                        "%.1f",
                        horizontalDistance(
                            best.Root.Position,
                            Runtime.Root.Position
                        )
                    ),
                remaining = remaining,
            })
        end

        return best
    end

    if now - Runtime.LastBossCleanupLog
        >= CFG.BOSS_POST_CLEANUP_LOG_COOLDOWN
    then
        Runtime.LastBossCleanupLog = now

        logKV("BOSS_CLEANUP_END", {
            boss =
                tostring(
                    Runtime.BossCleanupBoss
                ),
            reason = "clear",
        })
    end

    Runtime.BossCleanupModels = {}
    Runtime.BossCleanupBoss = nil
    Runtime.BossCleanupTarget = nil

    return nil
end

Runtime.ChooseLocalFinisher = function(enemies)
    if not CFG.LOCAL_FINISH_ENABLED
        or Runtime.ActiveBossName
        or Runtime.BossCleanupBoss
        or not Runtime.Root
    then
        return nil
    end

    local best
    local bestScore = -math.huge

    for _, enemy in ipairs(enemies) do
        if enemy
            and enemy.Model
            and enemy.Root
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and enemyRelevantForEncounter(enemy)
            and enemy.RoomIndex
                == Runtime.CurrentRoomIndex
        then
            local maxHp =
                enemy.Humanoid.MaxHealth

            local hpRatio =
                maxHp > 0
                and (
                    enemy.Humanoid.Health
                    / maxHp
                )
                or 1

            local distance =
                horizontalDistance(
                    Runtime.Root.Position,
                    enemy.Root.Position
                )

            if hpRatio
                    <= CFG.LOCAL_FINISH_HP_RATIO
                and distance
                    <= CFG.LOCAL_FINISH_RANGE
            then
                local score =
                    (1 - hpRatio) * 2400
                    - distance * 18
                    + (
                        isPhysicalEnemyModel(
                            enemy.Model
                        )
                        and CFG.LOCAL_FINISH_PHYSICAL_BONUS
                        or 0
                    )

                if score > bestScore then
                    bestScore = score
                    best = enemy
                end
            end
        end
    end

    if best then
        local now = os.clock()

        if now - Runtime.LastLocalFinishLog
            >= CFG.LOCAL_FINISH_LOG_COOLDOWN
        then
            Runtime.LastLocalFinishLog = now

            logKV("LOCAL_FINISH", {
                target = best.Model.Name,
                hp =
                    math.floor(
                        best.Humanoid.Health
                    ),
                ratio =
                    string.format(
                        "%.2f",
                        best.Humanoid.MaxHealth > 0
                        and (
                            best.Humanoid.Health
                            / best.Humanoid.MaxHealth
                        )
                        or 1
                    ),
                distance =
                    string.format(
                        "%.1f",
                        horizontalDistance(
                            Runtime.Root.Position,
                            best.Root.Position
                        )
                    ),
            })
        end
    end

    return best
end


Runtime.StabilizeNormalTarget = function(
    enemies,
    candidate,
    candidateScore
)
    if not CFG.TARGET_LOCK_ENABLED
        or Runtime.ActiveBossName
        or Runtime.BossCleanupBoss
        or not Runtime.Root
    then
        return candidate, candidateScore
    end

    local current

    if Runtime.Target then
        for _, enemy in ipairs(enemies) do
            if enemy.Model == Runtime.Target
                and enemy.Humanoid
                and enemy.Humanoid.Health > 0
                and enemy.Root
                and enemyRelevantForEncounter(enemy)
            then
                current = enemy
                break
            end
        end
    end

    if not current then
        return candidate, candidateScore
    end

    local now = os.clock()
    local currentDistance =
        horizontalDistance(
            current.Root.Position,
            Runtime.Root.Position
        )

    if currentDistance
        > CFG.TARGET_LOCK_RELEASE_DISTANCE
    then
        return candidate, candidateScore
    end

    -- If the current target is already a physical threat, keep it latched
    -- while it remains local. This prevents mage -> warrior -> mage ping-pong
    -- that wastes rotations and leaves the warrior alive beside the player.
    if isPhysicalEnemyModel(current.Model)
        and currentDistance
            <= CFG.TARGET_LOCK_PHYSICAL_HOLD_RANGE
    then
        return
            current,
            targetScore(current)
    end

    -- A close physical mob is the only immediate override to a sticky ranged
    -- target. This keeps safety without rapid mage-to-mage rotations.
    local physicalOverride
    local physicalDistance = math.huge

    for _, enemy in ipairs(enemies) do
        if enemy.Model ~= current.Model
            and enemy.Root
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and isPhysicalEnemyModel(
                enemy.Model
            )
            and enemyRelevantForEncounter(enemy)
        then
            local d =
                horizontalDistance(
                    enemy.Root.Position,
                    Runtime.Root.Position
                )

            if d
                <= CFG.TARGET_LOCK_PHYSICAL_OVERRIDE_RANGE
                and d < physicalDistance
            then
                physicalDistance = d
                physicalOverride = enemy
            end
        end
    end

    if physicalOverride then
        return
            physicalOverride,
            math.huge
    end

    if candidate
        and candidate.Model ~= current.Model
        and candidate.Root
        and currentDistance
            <= CFG.TARGET_LOCK_LOCAL_HOLD_DISTANCE
        and not isPhysicalEnemyModel(candidate.Model)
    then
        local challengerDistance =
            horizontalDistance(
                candidate.Root.Position,
                Runtime.Root.Position
            )

        if challengerDistance
            > currentDistance
                - CFG.TARGET_LOCK_CHALLENGER_DISTANCE_GAIN
        then
            return
                current,
                targetScore(current)
        end
    end

    local hpRatio =
        current.Humanoid.MaxHealth > 0
        and (
            current.Humanoid.Health
            / current.Humanoid.MaxHealth
        )
        or 1

    local age =
        now - (
            Runtime.TargetSince
            or -math.huge
        )

    local keep =
        age < CFG.TARGET_LOCK_MIN_SECONDS
        or hpRatio
            <= CFG.TARGET_LOCK_FINISH_HP_RATIO

    local currentScore =
        targetScore(current)

    if not keep
        and candidate
        and candidate.Model ~= current.Model
    then
        keep =
            candidateScore
            < currentScore
                + CFG.TARGET_LOCK_SWITCH_MARGIN
    end

    if keep then
        if now - Runtime.LastTargetLockLog
            >= CFG.TARGET_LOCK_LOG_COOLDOWN
            and candidate
            and candidate.Model ~= current.Model
        then
            Runtime.LastTargetLockLog = now

            logKV("TARGET_LOCK_HOLD", {
                target =
                    current.Model.Name,
                hp_ratio =
                    string.format(
                        "%.2f",
                        hpRatio
                    ),
                age =
                    string.format(
                        "%.2f",
                        age
                    ),
                challenger =
                    candidate.Model.Name,
                current_score =
                    string.format(
                        "%.1f",
                        currentScore
                    ),
                challenger_score =
                    string.format(
                        "%.1f",
                        candidateScore
                    ),
            })
        end

        return current, currentScore
    end

    return candidate, candidateScore
end


local function selectTarget()
    local enemies = livingEnemies()

    if #enemies == 0 then
        Runtime.Target = nil
        Runtime.TargetHumanoid = nil
        Runtime.TargetRoot = nil
        return
    end

    -- Infer active room from smallest room index that still has enemies.
    local minRoom = math.huge

    for _, e in ipairs(enemies) do
        local room =
            e.RoomIndex or 0

        local room999Allowed =
            Runtime.ActiveBossName == "Demon Lord Azrallik"
            or Runtime.FinalBossDefeated
            or Runtime.CurrentRoomIndex == 999

        -- A preloaded Blood Minion must not temporarily turn the run into
        -- room 999 between earlier rooms.
        if room > 0
            and room < minRoom
            and (
                room < 999
                or room999Allowed
            )
        then
            minRoom = room
        end
    end

    if minRoom < math.huge then
        local previousRoom =
            Runtime.CurrentRoomIndex

        Runtime.CurrentRoomIndex =
            minRoom

        if previousRoom ~= minRoom then
            Runtime.TransitSnapbackCount = 0
            Runtime.TransitSnapbackRoom = minRoom
            Runtime.TransitDisabledRoom = nil
            Runtime.TransitBackoffUntil = -math.huge
        end
    end

    local best
    local bestScore = -math.huge

    local cleanupTarget =
        Runtime.ChooseBossCleanupTarget(
            enemies
        )

    if cleanupTarget then
        best = cleanupTarget
        bestScore = math.huge
    end

    if not best
        and not Runtime.ActiveBossName
    then
        local localFinisher =
            Runtime.ChooseLocalFinisher(
                enemies
            )

        if localFinisher then
            best = localFinisher
            bestScore = math.huge
        end
    end

    -- Boss is the PRIMARY target. A nearby add may steal only a short,
    -- duty-cycled emergency burst; movement avoidance still protects against
    -- adds even while offense returns to the boss.
    if not best
        and Runtime.ActiveBossModel
        and (
            Runtime.ActiveBossName == "Demonic Overgrowth"
            or Runtime.ActiveBossName == "Kolvumar"
        )
    then
        -- Primary movement/offense lock remains the boss. Nearby adds are
        -- handled by attack-only opportunism so they never steal our route.
        for _, enemy in ipairs(enemies) do
            if enemy.Model == Runtime.ActiveBossModel
                and enemyRelevantForEncounter(enemy)
            then
                best = enemy
                bestScore = math.huge
                break
            end
        end
    end

    -- V8.3 final-boss target discipline.
    -- "Azrallik's Heart" is a mandatory phase objective.
    if not best
        and Runtime.ActiveBossName == "Demon Lord Azrallik"
        and Runtime.ActiveBossModel
    then
        local bossEnemy
        local heartEnemy
        local emergencyAdd
        local emergencyScore = -math.huge

        for _, enemy in ipairs(enemies) do
            if enemyRelevantForEncounter(enemy) then
                if enemy.Model == Runtime.ActiveBossModel then
                    bossEnemy = enemy

                elseif enemy.Model
                    and enemy.Model.Name == "Azrallik's Heart"
                then
                    heartEnemy = enemy

                elseif enemy.Model
                    and enemy.Model.Name == "Blood Minion"
                then
                    local d =
                        horizontalDistance(
                            enemy.Root.Position,
                            Runtime.Root.Position
                        )

                    if d <= CFG.AZRALLIK_BLOOD_MINION_EMERGENCY_RANGE then
                        local score = 10000 - d

                        if score > emergencyScore then
                            emergencyScore = score
                            emergencyAdd = enemy
                        end
                    end
                end
            end
        end

        if CFG.AZRALLIK_HEART_PHASE_LOCK
            and heartEnemy
        then
            best = heartEnemy
            bestScore = math.huge

            if not Runtime.AzrallikHeartPhaseActive
                or Runtime.AzrallikHeartModel ~= heartEnemy.Model
            then
                Runtime.AzrallikHeartPhaseActive = true
                Runtime.AzrallikHeartModel = heartEnemy.Model
                Runtime.AzrallikHeartStartedAt = os.clock()

                logKV("AZRALLIK_HEART_PHASE_START", {
                    hp = math.floor(heartEnemy.Humanoid.Health),
                    distance = string.format(
                        "%.1f",
                        horizontalDistance(
                            heartEnemy.Root.Position,
                            Runtime.Root.Position
                        )
                    ),
                })
            end
        else
            if Runtime.AzrallikHeartPhaseActive then
                local elapsed =
                    Runtime.AzrallikHeartStartedAt
                    and (os.clock() - Runtime.AzrallikHeartStartedAt)
                    or 0

                logKV("AZRALLIK_HEART_PHASE_END", {
                    elapsed = string.format("%.2f", elapsed),
                })

                Runtime.AzrallikHeartPhaseActive = false
                Runtime.AzrallikHeartModel = nil
                Runtime.AzrallikHeartStartedAt = nil
            end

            best = bossEnemy

            bestScore =
                best and math.huge
                or -math.huge
        end
    end

    if not best
        and not Runtime.ActiveBossName
        and Runtime.Root
        and CFG.MAGE_FREE_PRESSURE_ENABLED
    then
        local physical, physicalDistance =
            nearestPhysicalEnemy(
                Runtime.Root.Position
            )

        if not physical
            or physicalDistance
                > CFG.MAGE_FREE_PRESSURE_PHYSICAL_GUARD
        then
            local mageBest
            local mageScore = -math.huge

            for _, enemy in ipairs(enemies) do
                if enemyRelevantForEncounter(enemy)
                    and enemy.Model
                    and enemy.Root
                    and enemy.Humanoid
                    and enemy.Humanoid.Health > 0
                then
                    local name =
                        string.lower(
                            tostring(
                                enemy.Model.Name
                            )
                        )

                    if string.find(
                        name,
                        "mage",
                        1,
                        true
                    ) then
                        local d =
                            horizontalDistance(
                                Runtime.Root.Position,
                                enemy.Root.Position
                            )

                        if d
                            <= CFG.MAGE_FREE_PRESSURE_ACQUIRE_RANGE
                        then
                            local maxHpMillions =
                                enemy.Humanoid.MaxHealth
                                / 1000000

                            local hpRatio =
                                enemy.Humanoid.MaxHealth > 0
                                and (
                                    enemy.Humanoid.Health
                                    / enemy.Humanoid.MaxHealth
                                )
                                or 1

                            local score =
                                maxHpMillions * 120
                                + (1 - hpRatio) * 700
                                - d * 8

                            if score > mageScore then
                                mageScore = score
                                mageBest = enemy
                            end
                        end
                    end
                end
            end

            if mageBest then
                best = mageBest
                bestScore = math.huge

                local now = os.clock()

                if now - Runtime.LastMageFreePressureLog
                    >= CFG.MAGE_FREE_PRESSURE_LOG_COOLDOWN
                then
                    Runtime.LastMageFreePressureLog = now

                    logKV("MAGE_FREE_FOCUS", {
                        target = mageBest.Model.Name,
                        distance =
                            string.format(
                                "%.1f",
                                horizontalDistance(
                                    Runtime.Root.Position,
                                    mageBest.Root.Position
                                )
                            ),
                        physical =
                            physical
                            and string.format(
                                "%.1f",
                                physicalDistance
                            )
                            or "none",
                    })
                end
            end
        end
    end

    if not best then
        for _, enemy in ipairs(enemies) do
            if enemyRelevantForEncounter(enemy) then
                local score = targetScore(enemy)

                if score > bestScore then
                    bestScore = score
                    best = enemy
                end
            end
        end

        best, bestScore =
            Runtime.StabilizeNormalTarget(
                enemies,
                best,
                bestScore
            )
    end

    if not best then
        Runtime.Target = nil
        Runtime.TargetHumanoid = nil
        Runtime.TargetRoot = nil
        Runtime.TargetSince = -math.huge
        Runtime.ApproachWaypoints = nil
        Runtime.ApproachFallbackPosition = nil
        Runtime.ApproachTarget = nil
        return
    end

    if best and Runtime.Target ~= best.Model then
        Runtime.ApproachWaypoints = nil
        Runtime.ApproachFallbackPosition = nil
        Runtime.ApproachTarget = nil

        Runtime.Target = best.Model
        Runtime.TargetHumanoid = best.Humanoid
        Runtime.TargetRoot = best.Root
        Runtime.TargetSince = os.clock()

        logKV("TARGET", {
            name = best.Model.Name,
            room = best.RoomIndex,
            hp = math.floor(best.Humanoid.Health),
            distance = string.format(
                "%.1f",
                horizontalDistance(
                    best.Root.Position,
                    Runtime.Root.Position
                )
            ),
        })
    elseif best then
        Runtime.Target = best.Model
        Runtime.TargetHumanoid = best.Humanoid
        Runtime.TargetRoot = best.Root
    end
end

-- ============================================================
-- Enemy animation prediction
-- ============================================================

local function addVirtualThreat(id, center, radius, lifetime, source)
    -- The same enemy can emit AnimationPlayed more than once in an executor.
    -- Reuse one hazard per enemy/id instead of creating dozens of circles.
    local old = Runtime.VirtualThreats[id]
    local isNew = old == nil

    Runtime.VirtualThreats[id] = {
        Center = center,
        Radius = radius,
        Created = old and old.Created or os.clock(),
        Expires = os.clock() + lifetime,
        Source = source,
    }

    if isNew then
        logKV("VIRTUAL_THREAT", {
            source = source,
            radius = radius,
            center = vec(center),
        })
    end
end

local function watchEnemyAnimator(model)
    if not model or Players:GetPlayerFromCharacter(model) then return end

    local hum = modelHumanoid(model)
    if not hum then return end

    local animator =
        hum:FindFirstChildOfClass("Animator")
        or hum:FindFirstChild("Animator")

    if not animator or Runtime.WatchedAnimators[animator] then
        return
    end

    -- Strong-key dedupe. We clean the entry when the Animator leaves.
    Runtime.WatchedAnimators[animator] = true

    connect(animator.AncestryChanged, function(_, parent)
        if parent == nil then
            Runtime.WatchedAnimators[animator] = nil
            Runtime.LastAnimationEvent[model] = nil
        end
    end)

    connect(animator.AnimationPlayed, function(track)
        if not Runtime.Alive then return end

        local priority = track.Priority

        if priority ~= Enum.AnimationPriority.Action
            and priority ~= Enum.AnimationPriority.Action2
            and priority ~= Enum.AnimationPriority.Action3
            and priority ~= Enum.AnimationPriority.Action4
        then
            return
        end

        local root = modelRoot(model)
        if not root or not Runtime.Root then return end

        local animId = "unknown"

        pcall(function()
            if track.Animation then
                animId = track.Animation.AnimationId
            end
        end)

        -- Some executors/replicated NPCs surfaced the exact same animation
        -- callback many times in the same frame. One event is enough.
        local now = os.clock()
        local previousAnim = Runtime.LastAnimationEvent[model]

        if previousAnim
            and previousAnim.Id == animId
            and now - previousAnim.At <= CFG.ANIMATION_DEDUPE_WINDOW
        then
            return
        end

        Runtime.LastAnimationEvent[model] = {
            Id = animId,
            At = now,
        }

        local dist =
            horizontalDistance(
                root.Position,
                Runtime.Root.Position
            )

        logKV("ENEMY_ACTION_ANIM", {
            enemy = model.Name,
            animation = animId,
            distance = string.format("%.1f", dist),
        })

        if model.Name == "Demon Lord Azrallik"
            and animId == CFG.AZRALLIK_SPREAD_TELL_ANIM
        then
            Runtime.AzrallikSpreadTellAt = now
            Runtime.AzrallikSpreadTellOrigin =
                Runtime.Root.Position
            Runtime.AzrallikSpreadOrbitSign =
                Runtime.OrbitSign ~= 0
                and Runtime.OrbitSign
                or 1

            if now - Runtime.LastAzrallikSpreadTellLog
                >= CFG.AZRALLIK_SPREAD_LOG_COOLDOWN
            then
                Runtime.LastAzrallikSpreadTellLog = now

                logKV("AZRALLIK_SPREAD_TELL", {
                    distance =
                        string.format("%.1f", dist),
                    eta =
                        string.format(
                            "%.2f",
                            CFG.AZRALLIK_SPREAD_EXPECTED_DELAY
                        ),
                    origin =
                        vec(Runtime.Root.Position),
                })
            end
        end

        if model.Name == "Demon Lord Azrallik"
            and animId == CFG.AZRALLIK_FINGER_TELL_ANIM
        then
            Runtime.AzrallikFingerTellAt = now
            Runtime.AzrallikFingerTellOrigin = Runtime.Root.Position
            Runtime.AzrallikFingerTellMoved = false

            if now - Runtime.LastAzrallikFingerTellLog
                >= CFG.AZRALLIK_FINGER_TELL_LOG_COOLDOWN
            then
                Runtime.LastAzrallikFingerTellLog = now

                logKV("AZRALLIK_FINGER_TELL", {
                    distance = string.format("%.1f", dist),
                    origin = vec(Runtime.Root.Position),
                })
            end
        end

        -- One virtual close-range hazard PER enemy. Repeated callbacks only
        -- refresh it rather than multiplying the threat count.
        if model.Name == "Demon Warrior"
            and dist <= 24
            and DEMON_WARRIOR_ATTACK_ANIMS[animId]
        then
            Runtime.LastMeleeAttackAt[model] = now

            addVirtualThreat(
                model,
                root.Position,
                CFG.DEMON_WARRIOR_ATTACK_RADIUS,
                CFG.DEMON_WARRIOR_ATTACK_LIFETIME,
                "Demon Warrior Attack"
            )

        elseif model.Name == "Blood Minion"
            and dist <= CFG.BLOOD_MINION_ANIM_THREAT_RADIUS + 8
        then
            addVirtualThreat(
                model,
                root.Position,
                CFG.BLOOD_MINION_ANIM_THREAT_RADIUS,
                0.95,
                "Blood Minion Action"
            )

        elseif model.Name == "Kolvumar"
            and KOLVUMAR_DIRECT_ATTACK_ANIMS[animId]
        then
            addVirtualThreat(
                "KolvumarDirect:" .. tostring(model),
                root.Position,
                CFG.KOLVUMAR_DIRECT_SAFE_RADIUS,
                CFG.KOLVUMAR_DIRECT_THREAT_LIFETIME,
                "Kolvumar NonRed Sequence"
            )
        end
    end)
end

local function refreshAnimators()
    for _, e in ipairs(livingEnemies()) do
        watchEnemyAnimator(e.Model)
    end
end

local function refreshBossState()
    local found

    for _, enemy in ipairs(livingEnemies()) do
        if enemy.Model
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and BOSS_ENEMY_NAMES[enemy.Model.Name]
        then
            found = enemy
            break
        end
    end

    local newName = found and found.Model.Name or nil

    if newName ~= Runtime.ActiveBossName then
        local oldName = Runtime.ActiveBossName

        logKV("BOSS_STATE", {
            old = tostring(oldName),
            new = tostring(newName),
        })

        if newName == "Demon Lord Azrallik" then
            Runtime.SawFinalBoss = true
        end

        if oldName == "Demon Lord Azrallik"
            and newName == nil
            and Runtime.SawFinalBoss
            and Runtime.CurrentRoomIndex == 999
        then
            Runtime.AzrallikHeartPhaseActive = false
            Runtime.AzrallikHeartModel = nil
            Runtime.AzrallikHeartStartedAt = nil
            Runtime.AzrallikSpreadTellAt = -math.huge
            Runtime.AzrallikSpreadTellOrigin = nil
            Runtime.FinalBossDefeated = true
            Runtime.FinalBossDefeatedAt = os.clock()
            Runtime.BossWave = nil
            Runtime.MageWave = nil
            Runtime.PathWaypoints = nil
            Runtime.PathDestination = nil

            -- Do NOT clear the target here. V6 could stop while a Blood Minion
            -- was still alive, preventing the authoritative completion state.
            log("FINAL_BOSS_GONE", "cleanup_remaining_hostiles")
        end

        if oldName
            and newName == nil
        then
            Runtime.BeginBossCleanup(
                oldName
            )
        end

        Runtime.ActiveBossName = newName
        Runtime.ActiveBossModel = found and found.Model or nil

        if newName == nil then
            clearBossAddFocus("boss_ended")
        end
        Runtime.ActiveBossRoot = found and found.Root or nil
        Runtime.BossWave = nil

        if newName then
            -- Do not let a leftover room path keep owning movement once the
            -- boss encounter is close enough to control directly.
            Runtime.PathWaypoints = nil
            Runtime.PathDestination = nil
        end
    elseif found then
        Runtime.ActiveBossModel = found.Model
        Runtime.ActiveBossRoot = found.Root
    end
end

-- ============================================================
-- Threat discovery
-- ============================================================

local KNOWN_THREAT_ROOTS = {
    npcMageSpikes = true,
    bigMageBeam = true,

    spikePrecast = true,
    overgrowthLongLineSpikes = true,
    overgrowthSpikes = true,

    kolvumarSpit = true,

    horizontalBeam = true,
    azrallikPunch = true,
    azrallikPunchSpread = true,
    fingerBlastHit = true,
}

local PLAYER_ATTACK_ROOTS = {
    ["Rending Slice"] = true,
    ["Lava Lash"] = true,
    ["lavaLashHitbox"] = true,
}

local function topWorkspaceChild(inst)
    local cur = inst

    while cur and cur.Parent ~= workspace do
        cur = cur.Parent
    end

    return cur
end

local function classifyThreatPart(part)
    if not part:IsA("BasePart") then
        return nil
    end

    local top = topWorkspaceChild(part)
    if not top then return nil end

    if PLAYER_ATTACK_ROOTS[top.Name] then
        return nil
    end

    if KNOWN_THREAT_ROOTS[top.Name] then
        -- Prefer visible warning / precast.
        if part.Name == "precast" then
            return "Precast"
        end

        if top.Name == "spikePrecast"
            and part.Name == "Part"
        then
            return "Precast"
        end

        -- overgrowthSpikes itself is the damaging followup; we normally
        -- already moved from spikePrecast, but retaining it as danger
        -- prevents re-entering.
        if top.Name == "overgrowthSpikes"
            and part.Name == "hitBox"
        then
            return "ActiveHitbox"
        end

        -- Invisible hitboxes are secondary threat evidence.
        if part.Name == "hitBox" then
            return "ActiveHitbox"
        end
    end

    local lowerTop = string.lower(top.Name)
    local lowerName = string.lower(part.Name)

    if lowerName == "precast"
        or lowerTop:find("precast", 1, true)
    then
        return "Precast"
    end

    return nil
end

local function registerThreat(part)
    if Runtime.Threats[part] then return end

    local kind = classifyThreatPart(part)
    if not kind then return end

    local top = topWorkspaceChild(part)

    local createdNow = os.clock()

    Runtime.Threats[part] = {
        Part = part,
        Kind = kind,
        RootName = top and top.Name or "Unknown",
        Created = createdNow,
        SpawnRoom = Runtime.CurrentRoomIndex,
        InvalidLogged = false,
    }

    if top
        and top.Name == "spikePrecast"
        and kind == "Precast"
        and math.max(part.Size.X, part.Size.Z) >= 40
    then
        Runtime.OvergrowthSpikeHistory[
            #Runtime.OvergrowthSpikeHistory + 1
        ] = {
            Position = part.Position,
            Time = createdNow,
            Part = part,
        }

        local kept = {}

        for _, item in ipairs(Runtime.OvergrowthSpikeHistory) do
            if createdNow - item.Time <= CFG.OVERGROWTH_SEQUENCE_AGE then
                kept[#kept + 1] = item
            end
        end

        while #kept > CFG.OVERGROWTH_SEQUENCE_HISTORY do
            table.remove(kept, 1)
        end

        Runtime.OvergrowthSpikeHistory = kept
    end

    if top
        and top.Name == "horizontalBeam"
        and kind == "Precast"
    then
        Runtime.LastHorizontalBeamSpawn = createdNow

        Runtime.HorizontalBeamHistory[#Runtime.HorizontalBeamHistory + 1] = {
            Position = part.Position,
            Time = createdNow,
            Part = part,
        }

        local kept = {}
        for _, item in ipairs(Runtime.HorizontalBeamHistory) do
            if createdNow - item.Time <= CFG.AZRALLIK_SWEEP_HISTORY_AGE then
                kept[#kept + 1] = item
            end
        end

        while #kept > CFG.AZRALLIK_SWEEP_HISTORY do
            table.remove(kept, 1)
        end

        Runtime.HorizontalBeamHistory = kept
    end

    logKV("THREAT_START", {
        attack = top and top.Name or "Unknown",
        kind = kind,
        size = vec(part.Size),
        position = vec(part.Position),
        orientation = vec(part.Orientation),
    })

    connect(part.AncestryChanged, function(_, parent)
        if parent == nil then
            local meta = Runtime.Threats[part]
            local created = meta and meta.Created or os.clock()
            Runtime.Threats[part] = nil

            logKV("THREAT_END", {
                attack = top and top.Name or "Unknown",
                lifetime = string.format("%.3f", os.clock() - created),
            })
        end
    end)
end

for _, inst in ipairs(workspace:GetDescendants()) do
    if inst:IsA("BasePart") then
        registerThreat(inst)
    end
end

connect(workspace.DescendantAdded, function(inst)
    if inst:IsA("BasePart") then
        task.defer(registerThreat, inst)
    elseif inst:IsA("Animator") then
        local model = inst.Parent and inst.Parent.Parent
        if model and model:IsA("Model") then
            task.defer(watchEnemyAnimator, model)
        end
    end
end)

-- ============================================================
-- Geometry
-- ============================================================

local function horizontalAxesForPart(part)
    local axes = {
        {
            Vec = part.CFrame.RightVector,
            Half = part.Size.X * 0.5,
            LocalIndex = 1,
        },
        {
            Vec = part.CFrame.UpVector,
            Half = part.Size.Y * 0.5,
            LocalIndex = 2,
        },
        {
            Vec = part.CFrame.LookVector,
            Half = part.Size.Z * 0.5,
            LocalIndex = 3,
        },
    }

    -- Ignore whichever local axis points most vertically.
    table.sort(axes, function(a, b)
        return math.abs(a.Vec.Y) < math.abs(b.Vec.Y)
    end)

    return axes[1], axes[2]
end

local function componentByIndex(v, idx)
    if idx == 1 then return v.X end
    if idx == 2 then return v.Y end
    return v.Z
end

local CIRCLE_ATTACKS = {
    kolvumarSpit = true,
    azrallikPunch = true,
    fingerBlastHit = true,
    bigMageBeam = true,
}

local function threatGeometry(meta)
    local part = meta.Part
    if not part or not part.Parent then return nil end

    if CIRCLE_ATTACKS[meta.RootName] then
        local a,b = horizontalAxesForPart(part)

        local radius =
            math.max(
                a.Half,
                b.Half
            )

        local extra =
            meta.RootName == "kolvumarSpit"
            and CFG.KOLVUMAR_SPIT_SAFETY_EXTRA
            or 0

        return {
            Type = "Circle",
            Center = part.Position,
            Radius = radius + CFG.SAFETY_MARGIN + extra,
            Source = meta.RootName,
        }
    end

    return {
        Type = "Box",
        Part = part,
        Source = meta.RootName,
    }
end

local function pointInsideProjectedBox(part, point, margin)
    margin = margin or 0

    local localPoint =
        part.CFrame:PointToObjectSpace(point)

    local axisA, axisB =
        horizontalAxesForPart(part)

    local coordA =
        math.abs(
            componentByIndex(
                localPoint,
                axisA.LocalIndex
            )
        )

    local coordB =
        math.abs(
            componentByIndex(
                localPoint,
                axisB.LocalIndex
            )
        )

    return
        coordA <= axisA.Half + margin
        and coordB <= axisB.Half + margin
end

local function boxClearance(part, point)
    local localPoint =
        part.CFrame:PointToObjectSpace(point)

    local axisA, axisB =
        horizontalAxesForPart(part)

    local coordA =
        math.abs(
            componentByIndex(
                localPoint,
                axisA.LocalIndex
            )
        )

    local coordB =
        math.abs(
            componentByIndex(
                localPoint,
                axisB.LocalIndex
            )
        )

    local dx = coordA - axisA.Half
    local dz = coordB - axisB.Half

    if dx <= 0 and dz <= 0 then
        return -math.min(-dx, -dz)
    end

    return math.sqrt(
        math.max(dx,0)^2
        + math.max(dz,0)^2
    )
end

local function pointInsideThreat(meta, point)
    local g = threatGeometry(meta)
    if not g then return false end

    if g.Type == "Circle" then
        return
            horizontalDistance(
                point,
                g.Center
            ) <= g.Radius
    end

    return pointInsideProjectedBox(
        g.Part,
        point,
        CFG.SAFETY_MARGIN
    )
end

local function threatClearance(meta, point)
    local g = threatGeometry(meta)
    if not g then return math.huge end

    if g.Type == "Circle" then
        return
            horizontalDistance(
                point,
                g.Center
            )
            - g.Radius
    end

    return boxClearance(g.Part, point)
        - CFG.SAFETY_MARGIN
end

local function cleanupVirtualThreats()
    local now = os.clock()

    for id, t in pairs(Runtime.VirtualThreats) do
        if now >= t.Expires then
            Runtime.VirtualThreats[id] = nil
        end
    end
end

local function pointInsideVirtual(point, t)
    return horizontalDistance(point, t.Center) <= t.Radius
end

local BOSS_HAZARD_OWNER = {
    spikePrecast = "Demonic Overgrowth",
    overgrowthLongLineSpikes = "Demonic Overgrowth",
    overgrowthSpikes = "Demonic Overgrowth",

    kolvumarSpit = "Kolvumar",

    horizontalBeam = "Demon Lord Azrallik",
    azrallikPunch = "Demon Lord Azrallik",
    azrallikPunchSpread = "Demon Lord Azrallik",
    fingerBlastHit = "Demon Lord Azrallik",
}

local THREAT_MAX_RELEVANT_AGE = {
    npcMageSpikes = 3.6,
    bigMageBeam = 5.8,
    spikePrecast = 1.8,
    overgrowthSpikes = 1.4,
    overgrowthLongLineSpikes = 3.8,
    horizontalBeam = 5.0,
    azrallikPunch = 4.0,
    azrallikPunchSpread = 4.0,
    fingerBlastHit = 2.45,
    -- kolvumarSpit is intentionally NOT age-capped while Kolvumar is alive;
    -- the object can persist as a real boss-floor hazard.
}

local function refreshBossAliveCache()
    local now = os.clock()

    if now - Runtime.BossAliveCacheAt < 0.15 then
        return
    end

    Runtime.BossAliveCacheAt = now
    table.clear(Runtime.BossAliveCache)

    for _, enemy in ipairs(livingEnemies()) do
        if enemy.Model
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
        then
            Runtime.BossAliveCache[enemy.Model.Name] = true
        end
    end
end

local function livingEnemyNamed(name)
    refreshBossAliveCache()
    return Runtime.BossAliveCache[name] == true
end

local function threatRelevant(meta)
    if not meta or not meta.Part or not meta.Part.Parent then
        return false, "gone"
    end

    local now = os.clock()
    local age = now - meta.Created

    -- A hazard created in a completed room is visual history, not a reason
    -- to keep the next-room character trapped forever.
    if meta.SpawnRoom
        and meta.SpawnRoom > 0
        and Runtime.CurrentRoomIndex > meta.SpawnRoom
        and age >= CFG.ROOM_TRANSITION_HAZARD_GRACE
    then
        return false, "room_finished"
    end

    local owner = BOSS_HAZARD_OWNER[meta.RootName]

    local bossDeadGrace =
        CFG.BOSS_DEAD_HAZARD_GRACE

    if owner == "Demon Lord Azrallik"
        and (
            meta.RootName == "horizontalBeam"
            or meta.RootName == "azrallikPunch"
            or meta.RootName == "azrallikPunchSpread"
            or meta.RootName == "fingerBlastHit"
        )
    then
        bossDeadGrace =
            math.max(
                bossDeadGrace,
                CFG.FINAL_BOSS_POST_DEATH_HAZARD_GRACE
            )
    end

    if owner
        and not livingEnemyNamed(owner)
        and age >= bossDeadGrace
    then
        return false, "boss_dead"
    end

    if meta.RootName == "horizontalBeam"
        and Runtime.LastHorizontalBeamSpawn > -math.huge
        and now - Runtime.LastHorizontalBeamSpawn
            >= CFG.AZRALLIK_BEAM_POST_SPAWN_DANGER
    then
        return false, "beam_sweep_finished"
    end

    local maxAge = THREAT_MAX_RELEVANT_AGE[meta.RootName]

    if maxAge and age > maxAge then
        return false, "expired_window"
    end

    return true, nil
end

local function maybeLogIgnoredThreat(meta, reason)
    if meta and not meta.InvalidLogged and reason ~= "gone" then
        meta.InvalidLogged = true

        if reason == "beam_sweep_finished" then
            local now = os.clock()

            if now - Runtime.LastAzrallikBeamReleaseLog >= 0.70 then
                Runtime.LastAzrallikBeamReleaseLog = now

                logKV("AZRALLIK_BEAM_RELEASE", {
                    since_last_spawn =
                        string.format(
                            "%.2f",
                            now
                            - Runtime.LastHorizontalBeamSpawn
                        ),
                    configured =
                        CFG.AZRALLIK_BEAM_POST_SPAWN_DANGER,
                })
            end

            return
        end

        logKV("THREAT_IGNORE", {
            attack = meta.RootName,
            reason = reason,
            age = string.format("%.2f", os.clock() - meta.Created),
            spawn_room = tostring(meta.SpawnRoom),
            current_room = tostring(Runtime.CurrentRoomIndex),
        })
    end
end

local function activeThreats()
    cleanupVirtualThreats()

    local result = {}
    local hasPrimary = {}

    for part,meta in pairs(Runtime.Threats) do
        local relevant, reason = threatRelevant(meta)

        if relevant and meta.Kind == "Precast" then
            result[#result + 1] = meta
            hasPrimary[meta.RootName] = true
        elseif not relevant then
            maybeLogIgnoredThreat(meta, reason)
        end
    end

    -- Invisible hitboxes matter only when their warning is gone AND the
    -- source is still relevant.
    for part,meta in pairs(Runtime.Threats) do
        local relevant, reason = threatRelevant(meta)

        if relevant
            and meta.Kind == "ActiveHitbox"
            and not hasPrimary[meta.RootName]
        then
            result[#result + 1] = meta
        elseif not relevant then
            maybeLogIgnoredThreat(meta, reason)
        end
    end

    return result
end

activeThreatCount = function()
    local n = #activeThreats()

    for _ in pairs(Runtime.VirtualThreats) do
        n += 1
    end

    return n
end

local function bossThreatsFrom(threats)
    local out = {}
    local bossName = Runtime.ActiveBossName

    if not bossName then
        return out
    end

    local now = os.clock()

    for _, meta in ipairs(threats) do
        if BOSS_HAZARD_OWNER[meta.RootName] == bossName then
            -- Kolvumar's spit can remain on the floor for ~35 seconds. Keep
            -- it in pointDanger(), but do NOT let an old puddle count as the
            -- current attack wave.
            if bossName == "Kolvumar"
                and meta.RootName == "kolvumarSpit"
                and now - meta.Created > CFG.KOLVUMAR_NEW_WAVE_AGE
            then
                -- persistent floor zone only
            else
                out[#out + 1] = meta
            end
        end
    end

    return out
end

local function kolvumarDirectVirtualActive(now)
    now = now or os.clock()

    for _, vt in pairs(Runtime.VirtualThreats) do
        if vt
            and vt.Source == "Kolvumar NonRed Sequence"
            and (vt.Expires or -math.huge) > now
        then
            return true
        end
    end

    return false
end

local function updateBossWave(threats)
    local now = os.clock()
    local bossThreats = bossThreatsFrom(threats)

    if not Runtime.ActiveBossName then
        Runtime.BossWave = nil
        return nil, bossThreats
    end

    local kolvumarVirtual =
        Runtime.ActiveBossName == "Kolvumar"
        and kolvumarDirectVirtualActive(now)

    local hasBossActivity =
        #bossThreats > 0
        or kolvumarVirtual

    if hasBossActivity then
        if not Runtime.BossWave then
            Runtime.BossWaveCounter += 1
            Runtime.BossWave = {
                Id = Runtime.BossWaveCounter,
                Boss = Runtime.ActiveBossName,
                Started = now,
                CollectUntil = now + CFG.BOSS_WAVE_COLLECT_WINDOW,
                LastThreatAt = now,
                LastPlanAt = -math.huge,
                Plan = nil,
                Teleported = false,
                TeleportCount = 0,
                LastWaveTeleportAt = -math.huge,

                -- Overgrowth narrow-spike sequence state.
                SequenceDir = nil,
                SequenceStep = nil,
                SequenceOrigin = nil,
                SequenceLockedAt = nil,
                SequenceCommitted = false,
                SequenceCommitPosition = nil,
                SequenceCommitUntil = -math.huge,
                SequenceMaxProjection = -math.huge,

                -- Overgrowth simultaneous long-line pocket state.
                LongLinePocket = nil,
                LongLinePocketLocked = false,
                LongLinePocketClearance = nil,
                LongLinePocketGapWidth = nil,

                -- V8.5 measured edge-commit state.
                EdgeCommitStartedAt = nil,
                EdgeCommitOrigin = nil,
                EdgeCommitTarget = nil,
                EdgeRescueUsed = false,

                -- Azrallik horizontal-beam safe-pocket state.
                BeamPocket = nil,
                BeamPocketAxis = nil,
                BeamPocketLocked = false,
                BeamPocketReached = false,
                BeamPocketLastPlanAt = -math.huge,
                BeamPocketLastAdvanceAt = -math.huge,
                BeamPocketLastSlideAt = -math.huge,
                BeamPocketClearance = nil,
                BeamPocketGapWidth = nil,
                BeamLatticeSpacing = nil,
                LastSafePressureAt = -math.huge,
                BeamLatticeHalfWidth = nil,

                FingerBlastStartedAt = nil,
                FingerBlastCenter = nil,

                -- V9.0 Kolvumar local spit-pocket state.
                KolvumarPocket = nil,
                KolvumarPocketUntil = -math.huge,
                KolvumarPocketReached = false,
                KolvumarPocketLastPlanAt = -math.huge,

                Finalized = false,
                SafeSince = nil,
                MaxThreatCount = math.max(#bossThreats, kolvumarVirtual and 1 or 0),
            }

            logKV("BOSS_WAVE_START", {
                id = Runtime.BossWave.Id,
                boss = Runtime.ActiveBossName,
                threats = math.max(#bossThreats, kolvumarVirtual and 1 or 0),
            })
        else
            Runtime.BossWave.LastThreatAt = now
            Runtime.BossWave.MaxThreatCount =
                math.max(
                    Runtime.BossWave.MaxThreatCount or 0,
                    math.max(
                        #bossThreats,
                        kolvumarVirtual and 1 or 0
                    )
                )
        end
    elseif Runtime.BossWave
        and now - Runtime.BossWave.LastThreatAt >= CFG.BOSS_WAVE_END_GRACE
    then
        logKV("BOSS_WAVE_END", {
            id = Runtime.BossWave.Id,
            boss = Runtime.BossWave.Boss,
            max_threats = Runtime.BossWave.MaxThreatCount or 0,
            teleported = Runtime.BossWave.Teleported,
            elapsed = string.format("%.3f", now - Runtime.BossWave.Started),
        })

        Runtime.BossWave = nil
    end

    return Runtime.BossWave, bossThreats
end

local function mageThreatsFrom(threats)
    local out = {}

    for _, meta in ipairs(threats) do
        if meta.RootName == "npcMageSpikes"
            or meta.RootName == "bigMageBeam"
        then
            out[#out + 1] = meta
        end
    end

    return out
end

local function updateMageWave(threats)
    local now = os.clock()

    if Runtime.ActiveBossName or Runtime.CompletionConfirmed then
        Runtime.MageWave = nil
        return nil, {}
    end

    local mageThreats = mageThreatsFrom(threats)

    -- Group only true overlap. A single line stays on the cheaper normal path.
    if #mageThreats >= 2 then
        if not Runtime.MageWave then
            Runtime.MageWaveCounter += 1

            Runtime.MageWave = {
                Id = Runtime.MageWaveCounter,
                Started = now,
                CollectUntil = now + CFG.MAGE_WAVE_COLLECT_WINDOW,
                LastThreatAt = now,
                LastPlanAt = -math.huge,
                Plan = nil,
                Finalized = false,
                Teleported = false,
                MaxThreatCount = #mageThreats,
            }

            logKV("MAGE_WAVE_START", {
                id = Runtime.MageWave.Id,
                threats = #mageThreats,
            })
        else
            Runtime.MageWave.LastThreatAt = now
            Runtime.MageWave.MaxThreatCount =
                math.max(Runtime.MageWave.MaxThreatCount or 0, #mageThreats)
        end
    elseif Runtime.MageWave
        and now - Runtime.MageWave.LastThreatAt >= CFG.MAGE_WAVE_END_GRACE
    then
        logKV("MAGE_WAVE_END", {
            id = Runtime.MageWave.Id,
            max_threats = Runtime.MageWave.MaxThreatCount or 0,
            teleported = Runtime.MageWave.Teleported,
            elapsed = string.format("%.3f", now - Runtime.MageWave.Started),
        })

        Runtime.MageWave = nil
    end

    return Runtime.MageWave, mageThreats
end

local function pointDanger(point)
    local penalty = 0
    local insideCount = 0
    local nearest = math.huge

    for _, meta in ipairs(activeThreats()) do
        local clearance =
            threatClearance(meta, point)

        nearest = math.min(nearest, clearance)

        if clearance <= 0 then
            insideCount += 1
            penalty += 100000
                + math.abs(clearance) * 800
        elseif clearance < 5 then
            penalty += (5 - clearance) * 400
        elseif clearance < 10 then
            penalty += (10 - clearance) * 35
        end
    end

    for _, vt in pairs(Runtime.VirtualThreats) do
        local clearance =
            horizontalDistance(point, vt.Center)
            - vt.Radius

        nearest = math.min(nearest, clearance)

        if clearance <= 0 then
            insideCount += 1
            penalty += 80000
                + math.abs(clearance) * 600
        elseif clearance < 4 then
            penalty += (4 - clearance) * 300
        end
    end

    return penalty, insideCount, nearest
end

local function routeDanger(a, b)
    local total = 0

    for i = 1, CFG.PATH_SAMPLES do
        local alpha = i / CFG.PATH_SAMPLES
        local p = a:Lerp(b, alpha)

        local penalty, inside =
            pointDanger(p)

        if inside > 0 then
            total += 40000
        end

        total += penalty * 0.08
    end

    return total
end

-- ============================================================
-- Collision / candidate scoring
-- ============================================================

local function isTransientMovementPart(inst)
    if not inst or not inst:IsA("BasePart") then
        return false
    end

    if not inst.CanCollide then
        return true
    end

    local top = topWorkspaceChild(inst)

    if top then
        if PLAYER_ATTACK_ROOTS[top.Name]
            or KNOWN_THREAT_ROOTS[top.Name]
        then
            return true
        end
    end

    local lower = string.lower(inst.Name)

    if lower == "hitbox"
        or lower == "precast"
        or lower == "glowpart"
    then
        return true
    end

    -- Living NPC/character body parts are not map walls.
    local cur = inst
    for _ = 1, 5 do
        if not cur then break end

        if cur:IsA("Model")
            and cur:FindFirstChildOfClass("Humanoid")
        then
            return true
        end

        cur = cur.Parent
    end

    return false
end

local function staticObstacleRay(a, b, maxDistance)
    if not Runtime.Character then
        return nil
    end

    local delta = b - a
    local horizontalLength = horizontal(delta).Magnitude

    if horizontalLength < 0.5 then
        return nil
    end

    local ignore = {
        Runtime.Character,
    }

    -- Skip transient combat geometry and keep looking behind it for a real
    -- collidable map wall.
    for _ = 1, 10 do
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = ignore

        pcall(function()
            params.RespectCanCollide = true
        end)

        local origin = a + Vector3.new(0, 2.6, 0)
        local result = workspace:Raycast(origin, delta, params)

        if not result then
            return nil
        end

        if result.Normal.Y > 0.62 then
            return nil
        end

        if isTransientMovementPart(result.Instance) then
            ignore[#ignore + 1] = result.Instance
        else
            if maxDistance
                and result.Distance > maxDistance
            then
                -- A wall hundreds of studs away should not make the character
                -- sidestep now. Keep progressing until it is locally relevant.
                return nil
            end

            return result
        end
    end

    return nil
end


local function groundBelow(point, depth)
    if not Runtime.Character then
        return nil
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        Runtime.Character,
    }

    return workspace:Raycast(
        point + Vector3.new(0, 4, 0),
        Vector3.new(
            0,
            -(depth or CFG.SAFE_GROUND_DEPTH),
            0
        ),
        params
    )
end

local function safeMovementDestination(point, origin)
    if not point then
        return false, "nil"
    end

    origin =
        origin
        or (Runtime.Root and Runtime.Root.Position)

    if origin
        and math.abs(point.Y - origin.Y)
            > CFG.SAFE_VERTICAL_DELTA
    then
        return false, "vertical_delta"
    end

    if Runtime.LastSafePosition
        and point.Y
            < Runtime.LastSafePosition.Y
                - CFG.VOID_DROP_TRIGGER
    then
        return false, "below_safe_anchor"
    end

    local ground =
        groundBelow(
            point,
            CFG.SAFE_GROUND_DEPTH
        )

    if not ground then
        return false, "no_ground"
    end

    local gap =
        point.Y - ground.Position.Y

    if gap > CFG.SAFE_GROUND_MAX_GAP
        or gap < -3
    then
        return false, "ground_gap"
    end

    return true, "ok"
end

local function updateSafeAnchor()
    if not Runtime.Root
        or not Runtime.Humanoid
        or Runtime.Humanoid.Health <= 0
    then
        return false
    end

    local now = os.clock()

    if now - Runtime.LastSafeAnchorAt
        >= CFG.SAFE_ANCHOR_REFRESH
    then
        Runtime.LastSafeAnchorAt = now

        local pos =
            Runtime.Root.Position

        local ground =
            groundBelow(
                pos,
                CFG.SAFE_GROUND_DEPTH
            )

        if ground then
            local gap =
                pos.Y - ground.Position.Y

            if gap >= 0
                and gap <= CFG.SAFE_GROUND_MAX_GAP
            then
                Runtime.LastSafePosition = pos
                Runtime.LastSafeCFrame =
                    Runtime.Root.CFrame
            end
        end
    end

    local pos =
        Runtime.Root.Position

    if Runtime.LastSafePosition
        and pos.Y
            < Runtime.LastSafePosition.Y
                - CFG.VOID_DROP_TRIGGER
        and now - Runtime.LastVoidRecovery
            >= CFG.VOID_RECOVERY_COOLDOWN
    then
        Runtime.LastVoidRecovery = now

        if stopTransitTween then
            stopTransitTween("void_recovery")
        end

        if Runtime.LastSafeCFrame then
            pcall(function()
                Runtime.Root.AssemblyLinearVelocity =
                    Vector3.zero
                Runtime.Root.AssemblyAngularVelocity =
                    Vector3.zero
                Runtime.Root.CFrame =
                    Runtime.LastSafeCFrame

                Runtime.Humanoid:MoveTo(
                    Runtime.Root.Position
                )
                Runtime.Humanoid:Move(
                    Vector3.zero,
                    false
                )
            end)

            Runtime.ApproachWaypoints = nil
            Runtime.PathWaypoints = nil
            Runtime.WallEscapePosition = nil
            Runtime.MovementOwner = "NONE"

            logKV("VOID_RECOVERY", {
                from_y =
                    string.format("%.1f", pos.Y),
                safe_y =
                    string.format(
                        "%.1f",
                        Runtime.LastSafePosition.Y
                    ),
            })

            return true
        end
    end

    return false
end

local function wallBlocked(a, b)
    local delta = b - a

    if horizontal(delta).Magnitude < 1 then
        return false
    end

    local result = staticObstacleRay(a, b, nil)

    if not result then
        return false
    end

    return
        result.Distance
        < horizontal(delta).Magnitude * 0.90
end

local function enemyPenalty(point)
    local penalty = 0

    for _, enemy in ipairs(livingEnemies()) do
        local dist =
            horizontalDistance(
                point,
                enemy.Root.Position
            )

        if enemy.Model ~= Runtime.Target
            and dist < Profile.EnemyBuffer
        then
            penalty +=
                (Profile.EnemyBuffer - dist) * 350
        end
    end

    return penalty
end

local function targetPositionScore(point)
    if not Runtime.TargetRoot
        or not Runtime.TargetRoot.Parent
    then
        return 0
    end

    local d =
        horizontalDistance(
            point,
            Runtime.TargetRoot.Position
        )

    local error =
        math.abs(d - desiredRangeForTarget())

    return error * 5
end

local function wavePhysicalPenalty(point)
    local penalty = 0

    for _, enemy in ipairs(livingEnemies()) do
        if enemy.Model
            and enemy.Root
            and enemy.Humanoid
            and enemy.Humanoid.Health > 0
            and isPhysicalEnemyModel(enemy.Model)
            and physicalThreatRelevantForMovement(
                enemy,
                point
            )
        then
            local dist =
                horizontalDistance(
                    point,
                    enemy.Root.Position
                )

            if enemy.Model.Name == "Blood Minion" then
                local predictedEnemy =
                    enemy.Root.Position
                    + horizontal(
                        enemy.Root.AssemblyLinearVelocity
                    )
                    * CFG.BLOOD_MINION_WAVE_PREDICT_TIME

                dist =
                    math.min(
                        dist,
                        horizontalDistance(
                            point,
                            predictedEnemy
                        )
                    )
            end

            local hard = CFG.WAVE_PHYSICAL_HARD_RADIUS
            local soft = CFG.WAVE_PHYSICAL_SOFT_RADIUS

            if enemy.Model.Name == "Blood Minion" then
                hard = math.max(hard, CFG.BLOOD_MINION_CRITICAL_RADIUS + 3)
                soft = math.max(soft, CFG.BLOOD_MINION_SOFT_RADIUS + 2)
            end

            if dist <= hard then
                penalty +=
                    CFG.WAVE_PHYSICAL_HARD_PENALTY
                    + (hard - dist) * 7000
            elseif dist < soft then
                penalty +=
                    (soft - dist)
                    * CFG.WAVE_PHYSICAL_SOFT_PENALTY
            end
        end
    end

    return penalty
end

local function bossThreatHas(rootName, threats)
    for _, meta in ipairs(threats or {}) do
        if meta.RootName == rootName then
            return true
        end
    end

    return false
end



local function pushCandidate(list, position, label)
    if not position then return end
    list[#list + 1] = {
        Position = position,
        Label = label or "candidate",
    }
end


local function humanoidAncestor(inst)
    local cur = inst

    for _ = 1, 5 do
        if not cur then break end

        if cur:IsA("Model")
            and cur:FindFirstChildOfClass("Humanoid")
        then
            return cur
        end

        cur = cur.Parent
    end

    return nil
end

local function movementWallHit(a, b)
    local delta = b - a

    if horizontal(delta).Magnitude < 0.5 then
        return nil
    end

    return staticObstacleRay(
        a,
        b,
        math.min(
            CFG.WALL_LOCAL_INTERCEPT,
            horizontal(delta).Magnitude * 0.92
        )
    )
end

local function hasGroundAt(point)
    if not Runtime.Character then
        return true
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {
        Runtime.Character,
    }

    local origin = point + Vector3.new(0, 4, 0)

    local result =
        workspace:Raycast(
            origin,
            Vector3.new(0, -CFG.WALL_GROUND_CHECK, 0),
            params
        )

    return result ~= nil
end

local function localWallClearance(point)
    local minClearance = 999
    local openCount = 0
    local rayLength = CFG.WALL_LOOKAHEAD

    for i = 0, 7 do
        local angle = (math.pi * 2) * (i / 8)
        local dir = Vector3.new(
            math.cos(angle),
            0,
            math.sin(angle)
        )

        local hit =
            movementWallHit(
                point,
                point + dir * rayLength
            )

        if hit then
            minClearance = math.min(minClearance, hit.Distance)
        else
            openCount += 1
        end
    end

    if minClearance == 999 then
        minClearance = rayLength
    end

    return minClearance, openCount
end

local function scoreOpenMovementCandidate(origin, candidate, preferredDir)
    if movementWallHit(origin, candidate) then
        return math.huge
    end

    if not hasGroundAt(candidate) then
        return math.huge
    end

    local danger, inside, threatClearance =
        pointDanger(candidate)

    if inside > 0 then
        danger += inside * 50000
    end

    local wallClearance, openCount =
        localWallClearance(candidate)

    local score =
        danger
        + routeDanger(origin, candidate) * 0.22
        + enemyPenalty(candidate) * 0.55
        + targetPositionScore(candidate) * 0.35
        + horizontalDistance(origin, candidate) * 1.4
        - wallClearance * 95
        - openCount * 120

    if preferredDir then
        local travel =
            unitHorizontal(candidate - origin)

        score -=
            math.max(
                preferredDir:Dot(travel),
                -1
            ) * 180
    end

    if threatClearance ~= math.huge then
        score -=
            math.min(
                math.max(threatClearance, 0),
                12
            ) * 18
    end

    return score
end

local function chooseOpenSpacePoint(
    origin,
    preferredDir,
    minRadius
)
    local baseAngle = 0

    if preferredDir and preferredDir.Magnitude > 0.01 then
        baseAngle =
            math.atan2(
                preferredDir.Z,
                preferredDir.X
            )
    end

    local best
    local bestScore = math.huge

    for _, radius in ipairs(CFG.WALL_ESCAPE_RADII) do
        if not minRadius
            or radius >= minRadius
        then
            for i = 0, CFG.WALL_ESCAPE_DIRECTIONS - 1 do
                local angle =
                    baseAngle
                    + (math.pi * 2)
                        * (i / CFG.WALL_ESCAPE_DIRECTIONS)

                local dir =
                    Vector3.new(
                        math.cos(angle),
                        0,
                        math.sin(angle)
                    )

                local candidate =
                    origin + dir * radius

                local score =
                    scoreOpenMovementCandidate(
                        origin,
                        candidate,
                        preferredDir
                    )

                if score < bestScore then
                    bestScore = score
                    best = {
                        Position = candidate,
                        Radius = radius,
                        Score = score,
                        Label = "open_space",
                    }
                end
            end
        end
    end

    return best
end

local function resolveWallAwareDestination(origin, desired, reason)
    if not origin or not desired then
        return desired, false
    end

    local horizontalDelta =
        horizontal(desired - origin)

    if horizontalDelta.Magnitude < 0.8 then
        return desired, false
    end

    local hit =
        movementWallHit(
            origin,
            desired
        )

    if not hit then
        return desired, false
    end

    local desiredDir =
        unitHorizontal(horizontalDelta)

    local wallNormal =
        unitHorizontal(
            Vector3.new(
                hit.Normal.X,
                0,
                hit.Normal.Z
            )
        )

    local tangent =
        Vector3.new(
            -wallNormal.Z,
            0,
            wallNormal.X
        )

    local distance =
        math.clamp(
            horizontalDelta.Magnitude,
            6,
            16
        )

    local dirs = {
        tangent,
        -tangent,
        unitHorizontal(tangent + wallNormal * 0.40),
        unitHorizontal(-tangent + wallNormal * 0.40),
        wallNormal,
        unitHorizontal(desiredDir + tangent * 0.80),
        unitHorizontal(desiredDir - tangent * 0.80),
    }

    local best
    local bestScore = math.huge

    for _, dir in ipairs(dirs) do
        local candidate =
            origin + dir * distance

        local score =
            scoreOpenMovementCandidate(
                origin,
                candidate,
                desiredDir
            )

        if score < bestScore then
            bestScore = score
            best = candidate
        end
    end

    if not best or bestScore == math.huge then
        local fallback =
            chooseOpenSpacePoint(
                origin,
                wallNormal
            )

        best =
            fallback
            and fallback.Position
            or desired
    end

    local now = os.clock()

    if now - Runtime.LastWallLog >= CFG.WALL_LOG_COOLDOWN then
        Runtime.LastWallLog = now

        logKV("WALL_AVOID", {
            reason = tostring(reason),
            hit = fullName(hit.Instance),
            hit_distance = string.format("%.1f", hit.Distance),
            requested = vec(desired),
            resolved = vec(best),
        })
    end

    return best, true
end

local function beginWallEscape(reason)
    if not Runtime.Root then
        return false
    end

    local now = os.clock()

    if now - Runtime.LastWallEscape < CFG.WALL_ESCAPE_COOLDOWN then
        return false
    end

    local origin = Runtime.Root.Position
    local preferred

    local physical, physicalDist =
        nearestPhysicalEnemy(origin)

    if physical and physical.Root and physicalDist < 45 then
        preferred =
            unitHorizontal(
                origin - physical.Root.Position
            )

    elseif Runtime.TargetRoot then
        if activeThreatCount() == 0 then
            preferred =
                unitHorizontal(
                    Runtime.TargetRoot.Position
                    - origin
                )
        else
            preferred =
                unitHorizontal(
                    origin - Runtime.TargetRoot.Position
                )
        end

    else
        preferred =
            unitHorizontal(
                Runtime.Root.CFrame.LookVector
            )
    end

    local minRadius

    if activeThreatCount() == 0
        and reason == "COMBAT_APPROACH_PATH"
    then
        minRadius =
            math.min(
                CFG.BOSS_STALL_RECOVERY_MAX_RADIUS,
                6
                + Runtime.WallEscapeAttempts * 6
            )
    end

    local candidate =
        chooseOpenSpacePoint(
            origin,
            preferred,
            minRadius
        )

    if not candidate then
        return false
    end

    Runtime.WallEscapePosition = candidate.Position
    Runtime.WallEscapeUntil = now + CFG.WALL_ESCAPE_HOLD
    Runtime.WallEscapeStarted =
        Runtime.WallEscapeStarted or now
    Runtime.WallEscapeAttempts += 1
    Runtime.LastWallEscape = now

    logKV("WALL_ESCAPE", {
        reason = tostring(reason),
        attempt = Runtime.WallEscapeAttempts,
        radius = string.format("%.1f", candidate.Radius),
        position = vec(candidate.Position),
    })

    return true
end

local function directEscapeCandidates(origin)
    local out = {}

    -- First solve the geometry directly. Thin lines usually need only a
    -- perpendicular edge exit, not a 360-degree search.
    for _, meta in ipairs(activeThreats()) do
        local g = threatGeometry(meta)

        if g then
            if g.Type == "Circle" then
                local delta = horizontal(origin - g.Center)
                local dist = delta.Magnitude
                local dir

                if dist > 0.05 then
                    dir = delta.Unit
                elseif Runtime.TargetRoot then
                    dir = unitHorizontal(origin - Runtime.TargetRoot.Position)
                else
                    dir = unitHorizontal(Runtime.Root.CFrame.RightVector)
                end

                local required =
                    math.max(
                        0,
                        g.Radius - dist
                    )
                    + CFG.DIRECT_ESCAPE_EXTRA

                if required > 0.05 then
                    pushCandidate(
                        out,
                        origin + dir * required,
                        "circle_edge"
                    )
                end
            else
                local part = g.Part
                local lp = part.CFrame:PointToObjectSpace(origin)
                local axisA, axisB = horizontalAxesForPart(part)

                local function addAxis(axis, coord, axisName)
                    local worldAxis = horizontal(axis.Vec)

                    if worldAxis.Magnitude < 0.05 then
                        return
                    end

                    worldAxis = worldAxis.Unit

                    local plusDistance =
                        axis.Half
                        + CFG.SAFETY_MARGIN
                        - coord
                        + CFG.DIRECT_ESCAPE_EXTRA

                    local minusDistance =
                        axis.Half
                        + CFG.SAFETY_MARGIN
                        + coord
                        + CFG.DIRECT_ESCAPE_EXTRA

                    if plusDistance > 0 then
                        pushCandidate(
                            out,
                            origin + worldAxis * plusDistance,
                            axisName .. "_plus"
                        )
                    end

                    if minusDistance > 0 then
                        pushCandidate(
                            out,
                            origin - worldAxis * minusDistance,
                            axisName .. "_minus"
                        )
                    end
                end

                addAxis(
                    axisA,
                    componentByIndex(lp, axisA.LocalIndex),
                    "boxA"
                )
                addAxis(
                    axisB,
                    componentByIndex(lp, axisB.LocalIndex),
                    "boxB"
                )
            end
        end
    end

    for _, vt in pairs(Runtime.VirtualThreats) do
        local delta = horizontal(origin - vt.Center)
        local dist = delta.Magnitude

        if dist <= vt.Radius + CFG.SAFETY_MARGIN then
            local dir =
                dist > 0.05
                and delta.Unit
                or unitHorizontal(Runtime.Root.CFrame.RightVector)

            local required =
                vt.Radius
                + CFG.SAFETY_MARGIN
                - dist
                + CFG.DIRECT_ESCAPE_EXTRA

            pushCandidate(
                out,
                origin + dir * required,
                "virtual_edge"
            )
        end
    end


    return out
end

local function scoreEscapeCandidate(origin, candidate)
    local danger, inside, clearance = pointDanger(candidate.Position)

    local score =
        danger
        + routeDanger(origin, candidate.Position)
        + enemyPenalty(candidate.Position)
        + targetPositionScore(candidate.Position)

    local travel =
        horizontalDistance(origin, candidate.Position)

    score += travel * 2.5

    if wallBlocked(origin, candidate.Position) then
        score += 50000
    end

    if clearance ~= math.huge then
        score -= math.min(math.max(clearance, 0), 10) * 12
    end

    return {
        Position = candidate.Position,
        Radius = travel,
        Score = score,
        Inside = inside,
        Clearance = clearance,
        Label = candidate.Label,
    }
end

local function chooseDodgePoint()
    if not Runtime.Root then return nil end

    local origin = Runtime.Root.Position

    -- 1) Geometry-first exits: usually 2-8 candidates total.
    local direct = directEscapeCandidates(origin)
    local best
    local bestScore = math.huge

    for _, candidate in ipairs(direct) do
        local scored = scoreEscapeCandidate(origin, candidate)

        if scored.Score < bestScore then
            bestScore = scored.Score
            best = scored
        end
    end

    -- If a direct edge exit is safe, take it. This is far cheaper and
    -- typically shorter than a 360-degree grid.
    if best and best.Inside == 0 and best.Score < 50000 then
        return best
    end

    -- 2) Overlap / blocked fallback: only 16 directions x 6 radii = 96
    -- points, and enemy data is cached. V1 used 400 points and performed
    -- repeated full dungeon scans from inside the candidate loop.
    local base =
        Runtime.TargetRoot
        and unitHorizontal(Runtime.TargetRoot.Position - origin)
        or unitHorizontal(Runtime.Root.CFrame.LookVector)

    local baseAngle = math.atan2(base.Z, base.X)

    for _, radius in ipairs(CFG.CANDIDATE_RADII) do
        for i = 0, CFG.CANDIDATE_DIRECTIONS - 1 do
            local angle =
                baseAngle
                + (math.pi * 2)
                * (i / CFG.CANDIDATE_DIRECTIONS)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local scored =
                scoreEscapeCandidate(
                    origin,
                    {
                        Position = origin + dir * radius,
                        Label = "fallback",
                    }
                )

            if scored.Score < bestScore then
                bestScore = scored.Score
                best = scored
            end
        end
    end

    return best
end

local function chooseMageWavePoint()
    if not Runtime.Root then
        return nil
    end

    local origin = Runtime.Root.Position
    local base =
        Runtime.TargetRoot
        and unitHorizontal(
            Runtime.TargetRoot.Position - origin
        )
        or unitHorizontal(
            Runtime.Root.CFrame.LookVector
        )

    local baseAngle =
        math.atan2(
            base.Z,
            base.X
        )

    local best
    local bestScore = math.huge

    local pressureBest
    local pressureBestScore = math.huge

    local pressureActive =
        Runtime.MageFreePressureActive
        and Runtime.MageFreePressureActive()

    local currentTargetDistance =
        pressureActive
        and Runtime.TargetRoot
        and horizontalDistance(
            origin,
            Runtime.TargetRoot.Position
        )
        or math.huge

    local targetWeight = 0.75

    if pressureActive then
        targetWeight =
            CFG.MAGE_FREE_PRESSURE_WAVE_TARGET_WEIGHT
    end

    for _, radius in ipairs(
        CFG.MAGE_WAVE_RADII
    ) do
        for i = 0,
            CFG.MAGE_WAVE_DIRECTIONS - 1
        do
            local angle =
                baseAngle
                + (math.pi * 2)
                    * (
                        i
                        / CFG.MAGE_WAVE_DIRECTIONS
                    )

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate =
                origin + dir * radius

            local danger,
                inside,
                clearance =
                pointDanger(candidate)

            local blocked =
                wallBlocked(
                    origin,
                    candidate
                )

            local score =
                danger
                + routeDanger(
                    origin,
                    candidate
                ) * 0.48
                + enemyPenalty(candidate)
                + wavePhysicalPenalty(candidate)
                + targetPositionScore(candidate)
                    * targetWeight
                + radius * 1.1

            if blocked then
                score += 50000
            end

            if inside == 0 then
                score -= 14000
            end

            if clearance ~= math.huge then
                score -=
                    math.min(
                        math.max(
                            clearance,
                            0
                        ),
                        12
                    ) * 26
            end

            -- Mage-only pressure:
            -- track a separate SMALL safe sidestep that does not throw us
            -- away from the mage. This wins over the generic "maximum gap"
            -- behavior whenever such a local point exists.
            if pressureActive
                and inside == 0
                and not blocked
                and radius
                    <= CFG.MAGE_PRESSURE_LOCAL_DODGE_MAX_RADIUS
            then
                local candidateTargetDistance =
                    Runtime.TargetRoot
                    and horizontalDistance(
                        candidate,
                        Runtime.TargetRoot.Position
                    )
                    or math.huge

                local keepsPressure =
                    candidateTargetDistance
                        <= CFG.MAGE_PRESSURE_MAX_DPS_DISTANCE
                    or candidateTargetDistance
                        <= currentTargetDistance
                            + CFG.MAGE_PRESSURE_BACKTRACK_TOLERANCE

                if keepsPressure then
                    local pressureScore =
                        score
                        + candidateTargetDistance
                            * 180
                        + radius * 65

                    if pressureScore
                        < pressureBestScore
                    then
                        pressureBestScore =
                            pressureScore

                        pressureBest = {
                            Position = candidate,
                            Radius = radius,
                            Score = pressureScore,
                            Inside = inside,
                            Clearance = clearance,
                            Label =
                                "mage_pressure_local_gap",
                            Source =
                                "MagePressure",
                        }
                    end
                end
            end

            if score < bestScore then
                bestScore = score

                best = {
                    Position = candidate,
                    Radius = radius,
                    Score = score,
                    Inside = inside,
                    Clearance = clearance,
                    Label = "mage_wave_gap",
                    Source = "MageWave",
                }
            end
        end
    end

    return pressureBest or best
end

local function chooseBossWavePoint()
    if not Runtime.Root then
        return nil
    end

    local origin = Runtime.Root.Position
    local base =
        Runtime.ActiveBossRoot
        and unitHorizontal(Runtime.ActiveBossRoot.Position - origin)
        or (
            Runtime.TargetRoot
            and unitHorizontal(Runtime.TargetRoot.Position - origin)
            or unitHorizontal(Runtime.Root.CFrame.LookVector)
        )

    local baseAngle = math.atan2(base.Z, base.X)
    local best
    local bestScore = math.huge

    for _, radius in ipairs(CFG.BOSS_WAVE_RADII) do
        for i = 0, CFG.BOSS_WAVE_DIRECTIONS - 1 do
            local angle =
                baseAngle
                + (math.pi * 2) * (i / CFG.BOSS_WAVE_DIRECTIONS)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate = origin + dir * radius
            local danger, inside, clearance = pointDanger(candidate)

            local score =
                danger
                + routeDanger(origin, candidate) * 0.55
                + enemyPenalty(candidate)
                + wavePhysicalPenalty(candidate)
                + targetPositionScore(candidate) * 1.20
                + radius * 1.25

            -- If we're still far from the boss, preserve FORWARD progress.
            -- When forward is unsafe, lateral gaps remain valid; moving away
            -- from the boss receives a penalty but is still possible if needed.
            if Runtime.ActiveBossRoot then
                local desiredRange =
                    desiredRangeForTarget()

                local currentBossDistance =
                    horizontalDistance(
                        origin,
                        Runtime.ActiveBossRoot.Position
                    )

                if currentBossDistance
                    > desiredRange + CFG.BOSS_PROGRESS_ACTIVE_EXTRA
                then
                    local candidateBossDistance =
                        horizontalDistance(
                            candidate,
                            Runtime.ActiveBossRoot.Position
                        )

                    local progress =
                        currentBossDistance
                        - candidateBossDistance

                    if progress >= 0 then
                        score -=
                            progress
                            * CFG.BOSS_PROGRESS_REWARD
                    else
                        score +=
                            math.abs(progress)
                            * CFG.BOSS_BACKTRACK_PENALTY
                    end
                end
            end

            if wallBlocked(origin, candidate) then
                score += 50000
            end

            -- Strongly prefer a genuine gap over a merely "less bad" strip.
            if inside == 0 then
                score -= 16000
            end

            if clearance ~= math.huge then
                score -= math.min(math.max(clearance, 0), 14) * 30

                if Runtime.ActiveBossName == "Demonic Overgrowth"
                    and clearance < CFG.OVERGROWTH_MIN_CLEARANCE
                then
                    score +=
                        (CFG.OVERGROWTH_MIN_CLEARANCE - clearance)
                        * 5500
                end

                if Runtime.ActiveBossName == "Demon Lord Azrallik"
                    and bossThreatHas("azrallikPunchSpread", activeThreats())
                    and clearance < CFG.AZRALLIK_SPREAD_MIN_CLEARANCE
                then
                    score +=
                        (CFG.AZRALLIK_SPREAD_MIN_CLEARANCE - clearance)
                        * 6500
                end
            end

            if score < bestScore then
                bestScore = score
                best = {
                    Position = candidate,
                    Radius = radius,
                    Score = score,
                    Inside = inside,
                    Clearance = clearance,
                    Label = "boss_wave_gap",
                    Source = Runtime.ActiveBossName,
                }
            end
        end
    end

    return best
end



local function narrowAxisForPart(part)
    if not part then
        return nil, nil
    end

    local axisA, axisB =
        horizontalAxesForPart(part)

    local narrow =
        axisA.Half <= axisB.Half
        and axisA
        or axisB

    local dir =
        unitHorizontal(narrow.Vec)

    if dir.Magnitude <= 0.1 then
        return nil, nil
    end

    return dir, narrow.Half
end

local function overgrowthFirstEdgeCandidate(
    bossWave,
    bossThreats
)
    if not Runtime.Root
        or not bossWave
        or bossWave.Boss ~= "Demonic Overgrowth"
    then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local best
    local bestScore = math.huge

    for _, meta in ipairs(bossThreats or {}) do
        if meta.RootName == "spikePrecast"
            and meta.Part
            and meta.Part.Parent
            and math.max(
                meta.Part.Size.X,
                meta.Part.Size.Z
            ) >= 40
        then
            local axisDir, half =
                narrowAxisForPart(
                    meta.Part
                )

            if axisDir and half then
                local signed =
                    horizontal(
                        origin - meta.Part.Position
                    ):Dot(axisDir)

                local edgeClearance =
                    math.abs(signed) - half

                if edgeClearance
                    <= CFG.OVERGROWTH_FIRST_EDGE_MARGIN
                then
                    for _, sign in ipairs({-1, 1}) do
                        local targetProjection =
                            sign
                            * (
                                half
                                + CFG.OVERGROWTH_FIRST_EDGE_MARGIN
                            )

                        local travel =
                            targetProjection - signed

                        local candidate =
                            origin
                            + axisDir * travel

                        local distance =
                            horizontalDistance(
                                origin,
                                candidate
                            )

                        if distance
                            <= CFG.OVERGROWTH_FIRST_EDGE_MAX_TRAVEL
                            and hasGroundAt(candidate)
                            and not movementWallHit(
                                origin,
                                candidate
                            )
                        then
                            local danger, inside, clearance =
                                pointDanger(candidate)

                            local route =
                                routeDanger(
                                    origin,
                                    candidate
                                )

                            local score =
                                danger
                                + route * 0.25
                                + distance * 90

                            if inside == 0 then
                                score -= 30000
                            else
                                score += 90000
                            end

                            if score < bestScore then
                                bestScore = score
                                best = {
                                    Position = candidate,
                                    Radius = distance,
                                    Score = score,
                                    Inside = inside,
                                    Clearance = clearance,
                                    Label = "overgrowth_first_edge",
                                    Source = "OvergrowthFirstStrip",
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end


Runtime.OvergrowthEdgeFollowCandidate = function(
    bossWave
)
    if not CFG.OVERGROWTH_EDGE_FOLLOW_ENABLED
        or not Runtime.Root
        or not bossWave
        or bossWave.Boss ~= "Demonic Overgrowth"
        or not bossWave.EdgeFollowDir
        or os.clock() >= (
            bossWave.EdgeFollowUntil
            or -math.huge
        )
    then
        return nil
    end

    local origin =
        Runtime.Root.Position

    for _, step in ipairs(
        CFG.OVERGROWTH_EDGE_FOLLOW_STEPS
    ) do
        local candidate =
            origin
            + bossWave.EdgeFollowDir * step

        if hasGroundAt(candidate)
            and not movementWallHit(
                origin,
                candidate
            )
        then
            local danger, inside, clearance =
                pointDanger(candidate)

            if inside == 0 then
                return {
                    Position = candidate,
                    Radius = step,
                    Score = danger,
                    Inside = 0,
                    Clearance = clearance,
                    Label =
                        "overgrowth_edge_follow",
                    Source =
                        "OvergrowthEdgeFollow",
                }
            end
        end
    end

    return nil
end


local function overgrowthLongLineThreatsFrom(bossThreats)
    local out = {}

    for _, meta in ipairs(bossThreats or {}) do
        if meta.RootName == "overgrowthLongLineSpikes"
            and meta.Part
            and meta.Part.Parent
        then
            out[#out + 1] = meta
        end
    end

    return out
end

local function overgrowthLongLinePocketCandidate(
    bossWave,
    bossThreats
)
    if not Runtime.Root
        or not bossWave
        or bossWave.Boss ~= "Demonic Overgrowth"
    then
        return nil
    end

    if bossWave.LongLinePocketLocked
        and bossWave.LongLinePocket
    then
        local _, inside, clearance =
            pointDanger(
                bossWave.LongLinePocket
            )

        local lockedPhysicalPenalty =
            wavePhysicalPenalty(
                bossWave.LongLinePocket
            )

        if inside == 0
            and hasGroundAt(
                bossWave.LongLinePocket
            )
            and lockedPhysicalPenalty
                < CFG.WAVE_PHYSICAL_HARD_PENALTY
        then
            return {
                Position = bossWave.LongLinePocket,
                Radius =
                    horizontalDistance(
                        Runtime.Root.Position,
                        bossWave.LongLinePocket
                    ),
                Score = 0,
                Inside = 0,
                Clearance = clearance,
                Label = "overgrowth_longline_pocket",
                Source = "OvergrowthLongLineLocked",
                GapWidth =
                    bossWave.LongLinePocketGapWidth,
            }
        end

        bossWave.LongLinePocketLocked = false
        bossWave.LongLinePocket = nil
    end

    local threats =
        overgrowthLongLineThreatsFrom(
            bossThreats
        )

    if #threats < 2 then
        return nil
    end

    local axisDir =
        narrowAxisForPart(
            threats[1].Part
        )

    if not axisDir then
        return nil
    end

    local bands = {}

    for _, meta in ipairs(threats) do
        local part =
            meta.Part

        local _, half =
            narrowAxisForPart(part)

        if half then
            local projection =
                horizontal(
                    part.Position
                ):Dot(axisDir)

            local duplicate = false

            for _, band in ipairs(bands) do
                if math.abs(
                    band.Projection - projection
                ) <= 1.0
                then
                    duplicate = true
                    band.Half =
                        math.max(
                            band.Half,
                            half
                        )
                    break
                end
            end

            if not duplicate then
                bands[#bands + 1] = {
                    Projection = projection,
                    Half = half,
                }
            end
        end
    end

    table.sort(bands, function(a, b)
        return a.Projection < b.Projection
    end)

    if #bands < 2 then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local playerProjection =
        horizontal(origin):Dot(axisDir)

    local best
    local bestScore = math.huge

    for i = 1, #bands - 1 do
        local left =
            bands[i]

        local right =
            bands[i + 1]

        local leftEdge =
            left.Projection + left.Half

        local rightEdge =
            right.Projection - right.Half

        local gapWidth =
            rightEdge - leftEdge

        if gapWidth
            >= CFG.OVERGROWTH_LONGLINE_MIN_GAP
        then
            local pocketProjection =
                (leftEdge + rightEdge) * 0.5

            local candidate =
                origin
                + axisDir
                * (
                    pocketProjection
                    - playerProjection
                )

            local travel =
                horizontalDistance(
                    origin,
                    candidate
                )

            if travel
                <= CFG.OVERGROWTH_LONGLINE_MAX_POCKET_TRAVEL
                and hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                local route =
                    routeDanger(
                        origin,
                        candidate
                    )

                if inside == 0
                    and (
                        clearance == math.huge
                        or clearance
                            >= CFG.OVERGROWTH_LONGLINE_MIN_CLEARANCE
                    )
                then
                    local score =
                        travel * 180
                        + route * 0.05
                        + wavePhysicalPenalty(candidate)
                        - gapWidth * 320

                    if score < bestScore then
                        bestScore = score
                        best = {
                            Position = candidate,
                            Radius = travel,
                            Score = score,
                            Inside = inside,
                            Clearance = clearance,
                            Label = "overgrowth_longline_pocket",
                            Source = "OvergrowthLongLineGap",
                            GapWidth = gapWidth,
                        }
                    end
                end
            end
        end
    end

    if best then
        bossWave.LongLinePocket =
            best.Position
        bossWave.LongLinePocketLocked =
            true
        bossWave.LongLinePocketClearance =
            best.Clearance
        bossWave.LongLinePocketGapWidth =
            best.GapWidth

        local now =
            os.clock()

        if now - Runtime.LastOvergrowthLongLineLog
            >= CFG.OVERGROWTH_LONGLINE_LOCK_LOG_COOLDOWN
        then
            Runtime.LastOvergrowthLongLineLog = now

            logKV("OVERGROWTH_LONGLINE_POCKET", {
                wave = bossWave.Id,
                position = vec(best.Position),
                distance =
                    string.format(
                        "%.2f",
                        best.Radius
                    ),
                gap =
                    string.format(
                        "%.2f",
                        best.GapWidth
                    ),
                clearance =
                    best.Clearance == math.huge
                    and "inf"
                    or string.format(
                        "%.2f",
                        best.Clearance or 0
                    ),
            })
        end
    end

    return best
end

local function overgrowthSequenceEscapeCandidate(bossWave)
    if not Runtime.Root
        or Runtime.ActiveBossName ~= "Demonic Overgrowth"
        or not bossWave
    then
        return nil
    end

    local now = os.clock()
    local hist = {}

    -- Only the narrow sequential spikePrecast strips are recorded here.
    -- Long-line arrays are deliberately handled by the generic boss-wave gap
    -- solver because they spawn as a simultaneous set, not a one-way sweep.
    for _, item in ipairs(Runtime.OvergrowthSpikeHistory) do
        if item.Time >= bossWave.Started - 0.05
            and now - item.Time <= CFG.OVERGROWTH_SEQUENCE_AGE
            and item.Part
            and item.Part.Parent
        then
            hist[#hist + 1] = item
        end
    end

    if #hist < 2 then
        return nil
    end

    table.sort(hist, function(a, b)
        return a.Time < b.Time
    end)

    -- Lock direction from the FIRST two genuinely different strips.
    -- Never recalculate from the newest pair; small strip jitter previously
    -- flipped the direction and caused first -> second -> first ping-pong.
    if not bossWave.SequenceDir then
        local first
        local second

        for i = 1, #hist - 1 do
            for j = i + 1, #hist do
                local delta =
                    horizontal(
                        hist[j].Position
                        - hist[i].Position
                    )

                if delta.Magnitude
                    >= CFG.OVERGROWTH_SEQUENCE_MIN_STEP
                then
                    first = hist[i]
                    second = hist[j]
                    break
                end
            end

            if first then break end
        end

        if not first or not second then
            return nil
        end

        local motion =
            horizontal(
                second.Position
                - first.Position
            )

        bossWave.SequenceDir = motion.Unit
        bossWave.SequenceStep = motion.Magnitude
        bossWave.SequenceOrigin = first.Position
        bossWave.SequenceLockedAt = now

        if now - Runtime.LastOvergrowthDirectionLog
            >= CFG.OVERGROWTH_DIRECTION_LOG_COOLDOWN
        then
            Runtime.LastOvergrowthDirectionLog = now

            logKV("OVERGROWTH_DIRECTION_LOCK", {
                wave = bossWave.Id,
                step = string.format(
                    "%.2f",
                    bossWave.SequenceStep
                ),
                direction = vec(bossWave.SequenceDir),
                first = vec(first.Position),
                second = vec(second.Position),
            })
        end
    end

    local sequenceDir =
        bossWave.SequenceDir

    local sequenceStep =
        bossWave.SequenceStep
        or CFG.OVERGROWTH_SEQUENCE_MIN_STEP

    if not sequenceDir then
        return nil
    end

    -- Latest strip that actually advanced in the LOCKED direction.
    local latest = hist[1]
    local latestProjection = -math.huge

    for _, item in ipairs(hist) do
        local projection =
            horizontal(
                item.Position
                - bossWave.SequenceOrigin
            ):Dot(sequenceDir)

        if projection > latestProjection then
            latestProjection = projection
            latest = item
        end
    end

    local origin =
        Runtime.Root.Position

    local relative =
        horizontal(
            origin - latest.Position
        )

    local playerAhead =
        relative:Dot(sequenceDir)

    local halfWidth = 7.0

    pcall(function()
        local axisA, axisB =
            horizontalAxesForPart(latest.Part)

        halfWidth =
            math.min(
                axisA.Half,
                axisB.Half
            )
    end)

    -- Predict the next strip and aim BEYOND it. This is the behavior the
    -- observed mechanic needs:
    --
    --     first -> second -> third
    --
    -- Once we move toward second/third, never reverse toward first.
    local nextCenter =
        latest.Position
        + sequenceDir * sequenceStep

    local targetForward =
        horizontal(
            nextCenter - origin
        ):Dot(sequenceDir)
        + halfWidth
        + CFG.OVERGROWTH_FORWARD_EXTRA

    targetForward =
        math.clamp(
            targetForward,
            CFG.OVERGROWTH_FORWARD_MIN_MOVE,
            CFG.OVERGROWTH_FORWARD_MAX_REQUIRED
        )

    local dt = 0.50

    if #hist >= 2 then
        local a = hist[#hist - 1]
        local b = hist[#hist]

        local delta =
            horizontal(
                b.Position - a.Position
            )

        if delta:Dot(sequenceDir) > 0 then
            dt =
                math.max(
                    b.Time - a.Time,
                    0.05
                )
        end
    end

    local sequenceSpeed =
        sequenceStep / math.max(dt, 0.05)

    local timeToContact = math.huge

    if playerAhead >= -halfWidth then
        timeToContact =
            math.max(
                0,
                playerAhead - halfWidth
            ) / math.max(sequenceSpeed, 1)
    end

    local baseAngle =
        math.atan2(
            sequenceDir.Z,
            sequenceDir.X
        )

    local best
    local bestScore = math.huge

    for _, radius in ipairs(CFG.OVERGROWTH_FORWARD_RADII) do
        for _, degrees in ipairs(CFG.OVERGROWTH_FORWARD_ANGLES) do
            local angle =
                baseAngle + math.rad(degrees)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local forwardDot =
                dir:Dot(sequenceDir)

            -- HARD RULE: no candidate is allowed to go backwards toward a
            -- previously fired strip.
            if forwardDot >= CFG.OVERGROWTH_FORWARD_MIN_DOT then
                local candidate =
                    origin + dir * radius

                local forwardMove =
                    horizontal(
                        candidate - origin
                    ):Dot(sequenceDir)

                if forwardMove
                    >= math.min(
                        targetForward * 0.72,
                        CFG.OVERGROWTH_FORWARD_MIN_MOVE
                    )
                    and not movementWallHit(origin, candidate)
                    and hasGroundAt(candidate)
                then
                    local danger, inside, clearance =
                        pointDanger(candidate)

                    local route =
                        routeDanger(
                            origin,
                            candidate
                        )

                    -- Predict the NEXT red strip even though it does not exist
                    -- in Workspace yet. Penalize candidates landing on it.
                    local candidateFromNext =
                        horizontal(
                            candidate - nextCenter
                        ):Dot(sequenceDir)

                    local predictedNextPenalty = 0

                    if math.abs(candidateFromNext)
                        <= halfWidth + CFG.OVERGROWTH_SEQUENCE_ESCAPE_MARGIN
                    then
                        predictedNextPenalty = 120000
                    end

                    local forwardError =
                        math.abs(
                            forwardMove
                            - targetForward
                        )

                    local score =
                        danger
                        + route * 0.38
                        + predictedNextPenalty
                        + wavePhysicalPenalty(candidate)
                        + enemyPenalty(candidate) * 0.20
                        + radius * 8
                        + forwardError * 180

                    if inside > 0 then
                        score += 100000
                    end

                    -- Prefer the first safe point beyond the predicted strip,
                    -- not the farthest point available.
                    if forwardMove >= targetForward then
                        score -= 3200
                    else
                        score +=
                            (targetForward - forwardMove)
                            * 420
                    end

                    if clearance ~= math.huge then
                        score -=
                            math.min(
                                math.max(clearance, 0),
                                24
                            ) * 70

                        if clearance
                            < CFG.OVERGROWTH_FORWARD_MIN_CLEARANCE
                        then
                            score +=
                                (
                                    CFG.OVERGROWTH_FORWARD_MIN_CLEARANCE
                                    - clearance
                                ) * 22000
                        end
                    end

                    if score < bestScore then
                        bestScore = score

                        best = {
                            Position = candidate,
                            Radius = radius,
                            Score = score,
                            Inside = inside,
                            Clearance = clearance,
                            Label = "overgrowth_sequence_forward",
                            Source = "OvergrowthSequence",
                            TimeToContact = timeToContact,
                            SequenceSpeed = sequenceSpeed,
                            ForwardMove = forwardMove,
                            Step = sequenceStep,
                        }
                    end
                end
            end
        end
    end

    if best
        and now - Runtime.LastOvergrowthDirectionLog
            >= CFG.OVERGROWTH_DIRECTION_LOG_COOLDOWN
    then
        Runtime.LastOvergrowthDirectionLog = now

        logKV("OVERGROWTH_FORWARD_PLAN", {
            wave = bossWave.Id,
            step = string.format("%.2f", sequenceStep),
            move = string.format("%.2f", best.ForwardMove or 0),
            radius = string.format("%.1f", best.Radius),
            clearance = string.format("%.1f", best.Clearance or 0),
        })
    end

    return best
end

local moveTo

local function azrallikBeamThreatsFrom(bossThreats)
    local out = {}

    for _, meta in ipairs(bossThreats or {}) do
        if meta
            and meta.RootName == "horizontalBeam"
            and meta.Part
            and meta.Part.Parent
        then
            out[#out + 1] = meta
        end
    end

    return out
end

local function beamNarrowAxis(part)
    if not part then
        return nil, nil
    end

    local axisA, axisB =
        horizontalAxesForPart(part)

    local narrow =
        axisA.Half <= axisB.Half
        and axisA
        or axisB

    local dir =
        unitHorizontal(narrow.Vec)

    if dir.Magnitude <= 0.1 then
        return nil, nil
    end

    return dir, narrow.Half
end

local function uniqueBeamBands(beamThreats, axisDir)
    local bands = {}

    for _, meta in ipairs(beamThreats) do
        local part = meta.Part

        if part and part.Parent then
            local narrowDir, half =
                beamNarrowAxis(part)

            if narrowDir then
                if narrowDir:Dot(axisDir) < 0 then
                    narrowDir = -narrowDir
                end

                local projection =
                    horizontal(part.Position):Dot(axisDir)

                local duplicate = false

                for _, band in ipairs(bands) do
                    if math.abs(
                        band.Projection - projection
                    ) <= 1.0
                    then
                        duplicate = true

                        if meta.Kind == "ActiveHitbox" then
                            band.Part = part
                            band.Half = math.max(
                                band.Half,
                                half or 0
                            )
                        end

                        break
                    end
                end

                if not duplicate then
                    bands[#bands + 1] = {
                        Projection = projection,
                        Half = half or 8.2,
                        Part = part,
                    }
                end
            end
        end
    end

    table.sort(bands, function(a, b)
        return a.Projection < b.Projection
    end)

    return bands
end

local function medianNumber(values)
    if #values == 0 then
        return nil
    end

    table.sort(values)

    local mid =
        math.floor((#values + 1) * 0.5)

    if #values % 2 == 1 then
        return values[mid]
    end

    return
        (values[mid] + values[mid + 1])
        * 0.5
end

local function beamLatticeMetrics(
    beamThreats,
    axisDir
)
    local bands =
        uniqueBeamBands(
            beamThreats,
            axisDir
        )

    if #bands < 2 then
        return nil
    end

    local steps = {}
    local halfWidths = {}

    for _, band in ipairs(bands) do
        halfWidths[#halfWidths + 1] =
            band.Half
    end

    for i = 1, #bands - 1 do
        local step =
            bands[i + 1].Projection
            - bands[i].Projection

        -- Reject duplicate/junk distances and very large unrelated gaps.
        if step >= 8 and step <= 60 then
            steps[#steps + 1] = step
        end
    end

    local spacing =
        medianNumber(steps)

    local halfWidth =
        medianNumber(halfWidths)

    if not spacing or not halfWidth then
        return nil
    end

    local gapWidth =
        spacing - halfWidth * 2

    if gapWidth
        < CFG.AZRALLIK_BEAM_MIN_GAP_WIDTH
    then
        return nil
    end

    return {
        Bands = bands,
        Axis = axisDir,
        Base = bands[1].Projection,
        Spacing = spacing,
        HalfWidth = halfWidth,
        GapWidth = gapWidth,
    }
end

local function azrallikLatticePocketCandidate(
    bossWave,
    beamThreats
)
    if not Runtime.Root
        or not bossWave
        or #beamThreats < 2
    then
        return nil
    end

    local axisDir =
        beamNarrowAxis(
            beamThreats[1].Part
        )

    if not axisDir then
        return nil
    end

    local lattice =
        beamLatticeMetrics(
            beamThreats,
            axisDir
        )

    if not lattice then
        return nil
    end

    bossWave.BeamLatticeSpacing =
        lattice.Spacing
    bossWave.BeamLatticeHalfWidth =
        lattice.HalfWidth

    local origin =
        Runtime.Root.Position

    local playerProjection =
        horizontal(origin):Dot(axisDir)

    -- Gaps repeat halfway between every pair of beam centers. Extend that
    -- measured lattice in BOTH directions, including strips not spawned yet.
    -- This means the nearest safe lane should normally be <= spacing/2 away
    -- (~13 studs in the observed ~26-stud pattern), never 100+ studs away.
    local rawIndex =
        (playerProjection - lattice.Base)
        / lattice.Spacing
        - 0.5

    local nearestIndex =
        math.floor(rawIndex + 0.5)

    local lateral =
        Vector3.new(
            -axisDir.Z,
            0,
            axisDir.X
        )

    local best
    local bestScore = math.huge

    for k = nearestIndex - 2, nearestIndex + 2 do
        local pocketProjection =
            lattice.Base
            + (k + 0.5)
            * lattice.Spacing

        local axisOffset =
            pocketProjection
            - playerProjection

        if math.abs(axisOffset)
            <= CFG.AZRALLIK_BEAM_MAX_POCKET_TRAVEL
        then
            for _, side in ipairs(
                CFG.AZRALLIK_BEAM_AURA_LATERAL
            ) do
                local candidate =
                    origin
                    + axisDir * axisOffset
                    + lateral * side

                if hasGroundAt(candidate)
                    and not movementWallHit(
                        origin,
                        candidate
                    )
                then
                    local danger, inside, clearance =
                        pointDanger(candidate)

                    if inside == 0
                        and (
                            clearance == math.huge
                            or clearance
                                >= CFG.AZRALLIK_BEAM_MIN_CLEARANCE
                        )
                    then
                        local travel =
                            horizontalDistance(
                                origin,
                                candidate
                            )

                        local route =
                            routeDanger(
                                origin,
                                candidate
                            )

                        local score =
                            travel * 180
                            + route * 0.05
                            + math.abs(side) * 35
                            - lattice.GapWidth * 300

                        if travel
                            <= CFG.AZRALLIK_BEAM_HOLD_DISTANCE
                        then
                            score -= 60000
                        end

                        if score < bestScore then
                            bestScore = score

                            best = {
                                Position = candidate,
                                Radius = travel,
                                Score = score,
                                Inside = inside,
                                Clearance = clearance,
                                Label = "azrallik_beam_pocket",
                                Source = "HorizontalBeamLattice",
                                PocketAxis = axisDir,
                                GapWidth = lattice.GapWidth,
                                PocketProjection = pocketProjection,
                                LatticeSpacing = lattice.Spacing,
                            }
                        end
                    end
                end
            end
        end
    end

    return best
end

local function azrallikAuraPocketCandidate(
    bossWave,
    beamThreats
)
    if not Runtime.Root
        or #beamThreats < 2
    then
        return nil
    end

    local axisDir =
        beamNarrowAxis(
            beamThreats[1].Part
        )

    if not axisDir then
        return nil
    end

    local lateral =
        Vector3.new(
            -axisDir.Z,
            0,
            axisDir.X
        )

    local origin =
        Runtime.Root.Position

    local best
    local bestScore = math.huge

    for offset =
        -CFG.AZRALLIK_BEAM_AURA_RADIUS,
        CFG.AZRALLIK_BEAM_AURA_RADIUS,
        CFG.AZRALLIK_BEAM_AURA_STEP
    do
        for _, side in ipairs(
            CFG.AZRALLIK_BEAM_AURA_LATERAL
        ) do
            local candidate =
                origin
                + axisDir * offset
                + lateral * side

            local travel =
                horizontalDistance(
                    origin,
                    candidate
                )

            if travel
                <= CFG.AZRALLIK_BEAM_MAX_POCKET_TRAVEL
                and hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                if inside == 0
                    and (
                        clearance == math.huge
                        or clearance
                            >= CFG.AZRALLIK_BEAM_MIN_CLEARANCE
                    )
                then
                    local route =
                        routeDanger(
                            origin,
                            candidate
                        )

                    local score =
                        travel * 190
                        + route * 0.08
                        + math.abs(side) * 35

                    if travel
                        <= CFG.AZRALLIK_BEAM_HOLD_DISTANCE
                    then
                        score -= 45000
                    end

                    if score < bestScore then
                        bestScore = score
                        best = {
                            Position = candidate,
                            Radius = travel,
                            Score = score,
                            Inside = inside,
                            Clearance = clearance,
                            Label = "azrallik_beam_pocket",
                            Source = "HorizontalBeamAuraLocal",
                            PocketAxis = axisDir,
                            GapWidth = nil,
                        }
                    end
                end
            end
        end
    end

    return best
end

local function azrallikEarlyBeamCandidate(
    bossWave,
    bossThreats
)
    if not Runtime.Root
        or not bossWave
    then
        return nil
    end

    local beamThreats =
        azrallikBeamThreatsFrom(
            bossThreats
        )

    if #beamThreats == 0 then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local nearest
    local nearestDistance = math.huge
    local nearestAxis
    local nearestHalf

    for _, meta in ipairs(beamThreats) do
        local part = meta.Part

        if part and part.Parent then
            local axisDir, half =
                beamNarrowAxis(part)

            if axisDir and half then
                local signed =
                    horizontal(
                        origin - part.Position
                    ):Dot(axisDir)

                local edgeDistance =
                    math.abs(
                        math.abs(signed) - half
                    )

                if edgeDistance < nearestDistance then
                    nearestDistance = edgeDistance
                    nearest = part
                    nearestAxis = axisDir
                    nearestHalf = half
                end
            end
        end
    end

    if not nearest
        or not nearestAxis
        or not nearestHalf
    then
        return nil
    end

    local signed =
        horizontal(
            origin - nearest.Position
        ):Dot(nearestAxis)

    local clearance =
        math.abs(signed) - nearestHalf

    -- Already outside the first strip with margin: HOLD this known-safe point
    -- for the few tenths of a second until strip #2 gives us lattice spacing.
    if clearance >= CFG.AZRALLIK_BEAM_EARLY_MARGIN then
        local _, inside, pointClearance =
            pointDanger(origin)

        return {
            Position = origin,
            Radius = 0,
            Score = 0,
            Inside = inside,
            Clearance = pointClearance,
            Label = "azrallik_beam_early_hold",
            Source = "AzrallikEarlyBeamHold",
            PocketAxis = nearestAxis,
        }
    end

    local sign =
        signed >= 0
        and 1
        or -1

    local targetProjection =
        sign
        * (
            nearestHalf
            + CFG.AZRALLIK_BEAM_EARLY_MARGIN
        )

    local travel =
        targetProjection - signed

    local candidate =
        origin
        + nearestAxis * travel

    local distance =
        horizontalDistance(
            origin,
            candidate
        )

    if distance
        <= CFG.AZRALLIK_BEAM_EARLY_MAX_TRAVEL
        and hasGroundAt(candidate)
        and not movementWallHit(
            origin,
            candidate
        )
    then
        local _, inside, pointClearance =
            pointDanger(candidate)

        if inside == 0 then
            local now = os.clock()

            if now - Runtime.LastAzrallikEarlyBeamLog
                >= CFG.AZRALLIK_BEAM_EARLY_LOG_COOLDOWN
            then
                Runtime.LastAzrallikEarlyBeamLog = now

                logKV("AZRALLIK_EARLY_BEAM_EDGE", {
                    wave = bossWave.Id,
                    distance =
                        string.format(
                            "%.2f",
                            distance
                        ),
                    clearance =
                        pointClearance == math.huge
                        and "inf"
                        or string.format(
                            "%.2f",
                            pointClearance
                        ),
                })
            end

            return {
                Position = candidate,
                Radius = distance,
                Score = 0,
                Inside = 0,
                Clearance = pointClearance,
                Label = "azrallik_beam_early_edge",
                Source = "AzrallikEarlyBeamEdge",
                PocketAxis = nearestAxis,
            }
        end
    end

    -- Last safe fallback: do not use the generic boss planner while the beam
    -- mechanic is active. Hold current position until the lattice resolves.
    local _, inside, pointClearance =
        pointDanger(origin)

    return {
        Position = origin,
        Radius = 0,
        Score = 0,
        Inside = inside,
        Clearance = pointClearance,
        Label = "azrallik_beam_early_hold",
        Source = "AzrallikEarlyBeamFallback",
        PocketAxis = nearestAxis,
    }
end


local function horizontalSweepEscapeCandidate(
    bossWave,
    bossThreats
)
    if not CFG.AZRALLIK_BEAM_POCKET_ENABLED
        or not Runtime.Root
        or not bossWave
    then
        return nil
    end

    local beamThreats =
        azrallikBeamThreatsFrom(
            bossThreats
        )

    if #beamThreats < 2 then
        return nil
    end

    local now = os.clock()

    -- Once a pocket is locked, keep it while it remains safe. The key V8.1
    -- difference is that the pocket comes from the repeating beam lattice,
    -- so it is local instead of a distant gap between already-spawned strips.
    if bossWave.BeamPocketLocked
        and bossWave.BeamPocket
    then
        local _, inside, clearance =
            pointDanger(
                bossWave.BeamPocket
            )

        if inside == 0
            and (
                clearance == math.huge
                or clearance
                    >= CFG.AZRALLIK_BEAM_MIN_CLEARANCE
            )
            and hasGroundAt(
                bossWave.BeamPocket
            )
        then
            return {
                Position = bossWave.BeamPocket,
                Radius =
                    horizontalDistance(
                        Runtime.Root.Position,
                        bossWave.BeamPocket
                    ),
                Score = 0,
                Inside = 0,
                Clearance = clearance,
                Label = "azrallik_beam_pocket",
                Source = "HorizontalBeamPocketLocked",
                PocketAxis = bossWave.BeamPocketAxis,
                GapWidth = bossWave.BeamPocketGapWidth,
                LatticeSpacing =
                    bossWave.BeamLatticeSpacing,
            }
        end

        bossWave.BeamPocketLocked = false
        bossWave.BeamPocketReached = false
        bossWave.BeamPocket = nil

        logKV("AZRALLIK_POCKET_RELEASE", {
            wave = bossWave.Id,
            reason = "pocket_became_dangerous",
            inside = inside,
            clearance =
                clearance == math.huge
                and "inf"
                or string.format("%.2f", clearance),
        })
    end

    if now - (bossWave.BeamPocketLastPlanAt or -math.huge)
        < CFG.AZRALLIK_BEAM_RESCAN_INTERVAL
    then
        return nil
    end

    bossWave.BeamPocketLastPlanAt = now

    local plan =
        azrallikLatticePocketCandidate(
            bossWave,
            beamThreats
        )

    if not plan then
        plan =
            azrallikAuraPocketCandidate(
                bossWave,
                beamThreats
            )
    end

    if plan then
        bossWave.BeamPocket =
            plan.Position
        bossWave.BeamPocketAxis =
            plan.PocketAxis
        bossWave.BeamPocketLocked = true
        bossWave.BeamPocketReached = false
        bossWave.BeamPocketClearance =
            plan.Clearance
        bossWave.BeamPocketGapWidth =
            plan.GapWidth

        if now - Runtime.LastAzrallikPocketLog
            >= CFG.AZRALLIK_BEAM_LOCK_LOG_COOLDOWN
        then
            Runtime.LastAzrallikPocketLog = now

            logKV("AZRALLIK_POCKET_LOCK", {
                wave = bossWave.Id,
                position = vec(plan.Position),
                distance =
                    string.format(
                        "%.2f",
                        plan.Radius
                    ),
                clearance =
                    plan.Clearance == math.huge
                    and "inf"
                    or string.format(
                        "%.2f",
                        plan.Clearance or 0
                    ),
                gap =
                    plan.GapWidth
                    and string.format(
                        "%.2f",
                        plan.GapWidth
                    )
                    or "aura",
                spacing =
                    plan.LatticeSpacing
                    and string.format(
                        "%.2f",
                        plan.LatticeSpacing
                    )
                    or "n/a",
                source = plan.Source,
            })
        end
    end

    return plan
end

local function exactThreatRouteSafe(
    fromPosition,
    toPosition
)
    if not fromPosition or not toPosition then
        return false
    end

    local delta = toPosition - fromPosition
    local distance = horizontal(delta).Magnitude

    if distance <= 0.1 then
        local _, inside = pointDanger(toPosition)
        return inside == 0
    end

    local samples =
        math.max(
            1,
            math.ceil(
                distance
                / CFG.SAFE_ROUTE_SAMPLE_STEP
            )
        )

    for i = 1, samples do
        local point =
            fromPosition
            + delta * (i / samples)

        local _, inside =
            pointDanger(point)

        if inside > 0 then
            return false
        end
    end

    return true
end

local function azrallikPhaseTargetRoot()
    if Runtime.TargetRoot
        and Runtime.Target
        and Runtime.Target.Name == "Azrallik's Heart"
    then
        return Runtime.TargetRoot
    end

    if Runtime.ActiveBossModel then
        return modelRoot(
            Runtime.ActiveBossModel
        )
    end

    return Runtime.TargetRoot
end


local function trySlideAzrallikPocketLane(
    bossWave
)
    if not Runtime.Root
        or not Runtime.ActiveBossModel
        or not bossWave
        or not bossWave.BeamPocketAxis
    then
        return false
    end

    local now =
        os.clock()

    if now - (bossWave.BeamPocketLastSlideAt or -math.huge)
        < CFG.AZRALLIK_BEAM_LANE_SLIDE_INTERVAL
    then
        return false
    end

    local bossRoot =
        azrallikPhaseTargetRoot()

    if not bossRoot then
        return false
    end

    local narrowAxis =
        bossWave.BeamPocketAxis

    local laneAxis =
        Vector3.new(
            -narrowAxis.Z,
            0,
            narrowAxis.X
        )

    local origin =
        Runtime.Root.Position

    local towardBoss =
        horizontal(
            bossRoot.Position - origin
        )

    local along =
        towardBoss:Dot(laneAxis)

    if math.abs(along)
        < CFG.AZRALLIK_BEAM_LANE_SLIDE_MIN
    then
        return false
    end

    local direction =
        along >= 0
        and laneAxis
        or -laneAxis

    local step =
        math.min(
            math.abs(along),
            CFG.AZRALLIK_BEAM_LANE_SLIDE_STEP
        )

    if step
        < CFG.AZRALLIK_BEAM_LANE_SLIDE_MIN
    then
        return false
    end

    local candidate =
        origin + direction * step

    local safeDestination =
        safeMovementDestination(
            candidate,
            origin
        )

    if not safeDestination
        or movementWallHit(
            origin,
            candidate
        )
    then
        return false
    end

    local _, inside, clearance =
        pointDanger(candidate)

    local hardRouteSafe =
        exactThreatRouteSafe(
            origin,
            candidate
        )

    if inside > 0
        or not hardRouteSafe
        or (
            clearance ~= math.huge
            and clearance
                < CFG.AZRALLIK_BEAM_MIN_CLEARANCE
        )
    then
        return false
    end

    bossWave.BeamPocketLastSlideAt = now
    bossWave.BeamPocket = candidate
    bossWave.BeamPocketReached = false

    moveTo(
        candidate,
        "AZRALLIK_LANE_SLIDE"
    )

    if now - Runtime.LastAzrallikLaneSlideLog
        >= CFG.AZRALLIK_BEAM_LANE_SLIDE_LOG_COOLDOWN
    then
        Runtime.LastAzrallikLaneSlideLog = now

        logKV("AZRALLIK_LANE_SLIDE", {
            wave = bossWave.Id,
            step =
                string.format(
                    "%.1f",
                    step
                ),
            boss_distance =
                string.format(
                    "%.1f",
                    horizontalDistance(
                        origin,
                        bossRoot.Position
                    )
                ),
            clearance =
                clearance == math.huge
                and "inf"
                or string.format(
                    "%.2f",
                    clearance
                ),
        })
    end

    return true
end

local function tryAdvanceAzrallikPocket(
    bossWave
)
    if not Runtime.Root
        or not Runtime.ActiveBossModel
        or not bossWave
    then
        return false
    end

    local now = os.clock()

    if now - Runtime.LastHorizontalBeamSpawn
        < CFG.AZRALLIK_BEAM_SPAWN_QUIET
    then
        return false
    end

    if now - (bossWave.BeamPocketLastAdvanceAt or -math.huge)
        < CFG.AZRALLIK_BEAM_ADVANCE_INTERVAL
    then
        return false
    end

    local bossRoot =
        azrallikPhaseTargetRoot()

    if not bossRoot then
        return false
    end

    local origin =
        Runtime.Root.Position

    local toward =
        unitHorizontal(
            bossRoot.Position - origin
        )

    if toward.Magnitude <= 0.1 then
        return false
    end

    bossWave.BeamPocketLastAdvanceAt = now

    for _, step in ipairs({
        CFG.AZRALLIK_BEAM_ADVANCE_STEP,
        8.0,
        6.0,
        4.0,
        CFG.AZRALLIK_BEAM_ADVANCE_MIN_STEP,
    }) do
        local candidate =
            origin + toward * step

        local safeGround =
            safeMovementDestination(
                candidate,
                origin
            )

        if safeGround
            and not movementWallHit(
                origin,
                candidate
            )
        then
            local _, inside, clearance =
                pointDanger(candidate)

            local hardRouteSafe =
                exactThreatRouteSafe(
                    origin,
                    candidate
                )

            if inside == 0
                and hardRouteSafe
                and (
                    clearance == math.huge
                    or clearance
                        >= CFG.AZRALLIK_BEAM_MIN_CLEARANCE
                )
            then
                bossWave.BeamPocket =
                    candidate
                bossWave.BeamPocketLocked =
                    true
                bossWave.BeamPocketReached =
                    false

                moveTo(
                    candidate,
                    "AZRALLIK_POCKET_ADVANCE"
                )

                if now - Runtime.LastAzrallikAdvanceLog
                    >= CFG.AZRALLIK_BEAM_ADVANCE_LOG_COOLDOWN
                then
                    Runtime.LastAzrallikAdvanceLog = now

                    logKV("AZRALLIK_POCKET_ADVANCE", {
                        wave = bossWave.Id,
                        step =
                            string.format(
                                "%.1f",
                                step
                            ),
                        boss_distance =
                            string.format(
                                "%.1f",
                                horizontalDistance(
                                    origin,
                                    bossRoot.Position
                                )
                            ),
                        quiet =
                            string.format(
                                "%.2f",
                                now
                                - Runtime.LastHorizontalBeamSpawn
                            ),
                        clearance =
                            clearance == math.huge
                            and "inf"
                            or string.format(
                                "%.2f",
                                clearance
                            ),
                    })
                end

                return true
            end
        end
    end

    return false
end


local function holdAzrallikBeamPocket(
    bossWave,
    plan
)
    if not Runtime.Root
        or not Runtime.Humanoid
        or not bossWave
        or not plan
    then
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            plan.Position
        )

    if distance
        > CFG.AZRALLIK_BEAM_HOLD_DISTANCE
    then
        moveTo(
            plan.Position,
            "AZRALLIK_BEAM_POCKET"
        )

        return true
    end

    -- While beams are active, slide along the already-safe lane toward the
    -- boss. This preserves the safe narrow-axis pocket and never crosses the
    -- neighboring beam strip.
    if trySlideAzrallikPocketLane(
        bossWave
    ) then
        return true
    end

    -- Once strip generation has gone quiet, begin consuming the old-beam tail
    -- in short safe cross-lane MoveTo steps. If even a 3-stud route is unsafe,
    -- stay in the pocket.
    if tryAdvanceAzrallikPocket(
        bossWave
    ) then
        return true
    end

    pcall(function()
        Runtime.Humanoid:MoveTo(
            Runtime.Root.Position
        )
        Runtime.Humanoid:Move(
            Vector3.zero,
            false
        )
        Runtime.Root.AssemblyLinearVelocity =
            Vector3.zero
    end)

    Runtime.MovementOwner =
        "AZRALLIK_POCKET_HOLD"

    if not bossWave.BeamPocketReached then
        bossWave.BeamPocketReached = true

        logKV("AZRALLIK_POCKET_HOLD", {
            wave = bossWave.Id,
            position =
                vec(Runtime.Root.Position),
            clearance =
                plan.Clearance == math.huge
                and "inf"
                or string.format(
                    "%.2f",
                    plan.Clearance or 0
                ),
        })
    end

    return true
end

-- ============================================================
-- Movement
-- ============================================================

local function encounterStillActive()
    if Runtime.ActiveBossName then
        return true
    end

    return
        Runtime.TargetHumanoid
        and Runtime.TargetHumanoid.Parent
        and Runtime.TargetHumanoid.Health > 0
end

local function isThreatSolverMove(reason)
    reason = tostring(reason or "")

    return
        reason == "DODGE"
        or reason == "POST_SHIFT_CONTINUE"
        or reason == "BOSS_WAVE"
        or reason == "MAGE_WAVE"
        or reason == "AZRALLIK_SWEEP_GAP"
        or reason == "KOLVUMAR_SPIT_ESCAPE"
        or reason == "KOLVUMAR_SPIT_HOLD"
        or reason == "KOLVUMAR_SPIT_SLIDE"
        or reason == "KOLVUMAR_SPIT_COOLDOWN_SLIDE"
        or reason == "AZRALLIK_BEAM_POCKET"
        or reason == "AZRALLIK_BEAM_EARLY"
        or reason == "AZRALLIK_FINGER"
        or reason == "AZRALLIK_FINGER_PREMOVE"
        or reason == "AZRALLIK_POCKET_ADVANCE"
        or reason == "AZRALLIK_LANE_SLIDE"
        or reason == "AZRALLIK_SAFE_PRESSURE"
        or reason == "OVERGROWTH_EDGE"
        or reason == "OVERGROWTH_LONGLINE_POCKET"
        or reason == "STALL_BREAK_PROGRESS"
        or reason == "OVERGROWTH_FORWARD"
        or reason == "WALL_ESCAPE"
end

local function strictRedSafeDestination(desired, reason)
    if not Runtime.Root
        or not desired
        or not encounterStillActive()
        or activeThreatCount() <= 0
        or isThreatSolverMove(reason)
    then
        return desired, true
    end

    local origin =
        Runtime.Root.Position

    local _, inside =
        pointDanger(desired)

    local route =
        routeDanger(
            origin,
            desired
        )

    if inside == 0
        and route <= CFG.STRICT_RED_ROUTE_LIMIT
    then
        return desired, true
    end

    local preferred =
        unitHorizontal(
            desired - origin
        )

    local open =
        chooseOpenSpacePoint(
            origin,
            preferred
        )

    if open then
        local _, openInside =
            pointDanger(open.Position)

        local openRoute =
            routeDanger(
                origin,
                open.Position
            )

        if openInside == 0
            and openRoute <= CFG.STRICT_RED_ROUTE_LIMIT
        then
            if os.clock() - Runtime.LastStrictRedLog
                >= CFG.STRICT_RED_LOG_COOLDOWN
            then
                Runtime.LastStrictRedLog =
                    os.clock()

                logKV("RED_ROUTE_BLOCK", {
                    reason = tostring(reason),
                    inside = inside,
                    route = string.format("%.0f", route),
                    requested = vec(desired),
                    resolved = vec(open.Position),
                })
            end

            return open.Position, true
        end
    end

    if os.clock() - Runtime.LastStrictRedLog
        >= CFG.STRICT_RED_LOG_COOLDOWN
    then
        Runtime.LastStrictRedLog =
            os.clock()

        logKV("RED_ROUTE_HOLD", {
            reason = tostring(reason),
            inside = inside,
            route = string.format("%.0f", route),
            requested = vec(desired),
        })
    end

    return nil, false
end


local function logMoveReject(reason, reject, requested)
    local now = os.clock()
    local key =
        tostring(reason)
        .. "|"
        .. tostring(reject)

    if key ~= Runtime.LastMoveRejectKey
        or now - Runtime.LastMoveRejectLog
            >= CFG.MOVE_REJECT_LOG_COOLDOWN
    then
        Runtime.LastMoveRejectKey = key
        Runtime.LastMoveRejectLog = now

        logKV("MOVE_REJECT", {
            reason = tostring(reason),
            reject = tostring(reject),
            requested = vec(requested),
            current =
                Runtime.Root
                and vec(Runtime.Root.Position)
                or "nil",
        })
    end
end


local stopTransitTween

moveTo = function(position, reason)
    if not Runtime.Humanoid
        or not Runtime.Root
        or not Runtime.Humanoid.Parent
    then
        return
    end

    if Runtime.TransitTween then
        stopTransitTween("movement_override:" .. tostring(reason))
    end

    local now = os.clock()

    if now - Runtime.LastMove < CFG.MOVE_REFRESH then
        return
    end

    Runtime.LastMove = now

    local requested = position

    local safeRequested, rejectReason =
        safeMovementDestination(
            requested,
            Runtime.Root.Position
        )

    if not safeRequested
        and isThreatSolverMove(reason)
    then
        local preferred =
            unitHorizontal(
                requested
                - Runtime.Root.Position
            )

        local fallbackMinRadius

        if Runtime.ActiveBossName == "Demon Lord Azrallik"
            and reason == "BOSS_WAVE"
        then
            fallbackMinRadius =
                CFG.AZRALLIK_INVALID_DEST_MIN_RADIUS
        end

        local fallback =
            chooseOpenSpacePoint(
                Runtime.Root.Position,
                preferred,
                fallbackMinRadius
            )

        if fallback then
            local fallbackSafe =
                safeMovementDestination(
                    fallback.Position,
                    Runtime.Root.Position
                )

            if fallbackSafe then
                logKV("DODGE_DESTINATION_FALLBACK", {
                    reason = tostring(reason),
                    reject = tostring(rejectReason),
                    requested = vec(requested),
                    fallback = vec(fallback.Position),
                    radius =
                        string.format(
                            "%.1f",
                            fallback.Radius
                        ),
                })

                requested =
                    fallback.Position
                safeRequested = true
                rejectReason = "fallback"
            end
        end
    end

    if not safeRequested then
        logMoveReject(
            reason,
            rejectReason,
            requested
        )

        Runtime.ApproachWaypoints = nil
        Runtime.PathWaypoints = nil
        Runtime.ApproachFallbackPosition = nil

        return
    end

    local resolved =
        resolveWallAwareDestination(
            Runtime.Root.Position,
            requested,
            reason
        )

    local safeResolved, resolvedReject =
        safeMovementDestination(
            resolved,
            Runtime.Root.Position
        )

    if not safeResolved
        and isThreatSolverMove(reason)
    then
        local preferred =
            unitHorizontal(
                requested
                - Runtime.Root.Position
            )

        local fallbackMinRadius

        if Runtime.ActiveBossName == "Demon Lord Azrallik"
            and reason == "BOSS_WAVE"
        then
            fallbackMinRadius =
                CFG.AZRALLIK_INVALID_DEST_MIN_RADIUS
        end

        local fallback =
            chooseOpenSpacePoint(
                Runtime.Root.Position,
                preferred,
                fallbackMinRadius
            )

        if fallback then
            local fallbackSafe =
                safeMovementDestination(
                    fallback.Position,
                    Runtime.Root.Position
                )

            if fallbackSafe then
                logKV("DODGE_RESOLVED_FALLBACK", {
                    reason = tostring(reason),
                    reject = tostring(resolvedReject),
                    resolved = vec(resolved),
                    fallback = vec(fallback.Position),
                    radius =
                        string.format(
                            "%.1f",
                            fallback.Radius
                        ),
                })

                resolved =
                    fallback.Position
                safeResolved = true
                resolvedReject = "fallback"
            end
        end
    end

    if not safeResolved then
        logMoveReject(
            reason,
            resolvedReject,
            resolved
        )

        return
    end

    local strictResolved, strictOkay =
        strictRedSafeDestination(
            resolved,
            reason
        )

    if not strictOkay or not strictResolved then
        pcall(function()
            Runtime.Humanoid:Move(
                Vector3.zero,
                false
            )
        end)

        return
    end

    resolved = strictResolved

    Runtime.MovementOwner = "MOVE_TO"
    Runtime.LastMoveTarget = requested
    Runtime.LastMoveResolved = resolved
    Runtime.LastMoveReason = reason

    Runtime.Humanoid:MoveTo(resolved)
end

local function faceTarget(targetModel)
    if not Runtime.Root then
        return
    end

    local targetRoot = Runtime.TargetRoot

    if targetModel and targetModel:IsA("Model") then
        targetRoot = modelRoot(targetModel) or targetRoot
    end

    if not targetRoot or not targetRoot.Parent then
        return
    end

    local here = Runtime.Root.Position

    local target =
        targetRoot.Position
        + horizontal(targetRoot.AssemblyLinearVelocity)
            * CFG.ABILITY_AIM_LEAD_TIME

    local flatTarget =
        Vector3.new(
            target.X,
            here.Y,
            target.Z
        )

    if horizontalDistance(here, flatTarget) > 0.5 then
        pcall(function()
            Runtime.Root.CFrame =
                CFrame.lookAt(
                    here,
                    flatTarget
                )
        end)
    end
end

local function beginAimLock()
    Runtime.AimTarget = Runtime.Target
    Runtime.AimLockUntil =
        os.clock() + CFG.ABILITY_AIM_LOCK_TIME

    if Runtime.Humanoid then
        if Runtime.AimPreviousAutoRotate == nil then
            Runtime.AimPreviousAutoRotate =
                Runtime.Humanoid.AutoRotate
        end

        Runtime.Humanoid.AutoRotate = false
    end

    faceTarget(Runtime.AimTarget)
end

local function updateAimLock()
    if not Runtime.Humanoid then return end

    if Runtime.AimTarget
        and os.clock() <= Runtime.AimLockUntil
        and Runtime.AimTarget.Parent
    then
        Runtime.Humanoid.AutoRotate = false
        faceTarget(Runtime.AimTarget)
    else
        Runtime.AimTarget = nil

        if Runtime.AimPreviousAutoRotate ~= nil then
            Runtime.Humanoid.AutoRotate =
                Runtime.AimPreviousAutoRotate

            Runtime.AimPreviousAutoRotate = nil
        end
    end
end

local function abilityDangerImminent()
    if not Runtime.Root then
        return true
    end

    local predicted =
        Runtime.Root.Position
        + horizontal(Runtime.Root.AssemblyLinearVelocity)
            * CFG.ABILITY_SAFE_PREDICT_TIME

    -- Only real attack geometry blocks a cast. Proactive melee spacing by
    -- itself should not suppress skills while we are safely kiting.
    for _, meta in ipairs(activeThreats()) do
        if pointInsideThreat(meta, Runtime.Root.Position)
            or pointInsideThreat(meta, predicted)
        then
            return true
        end
    end

    for _, vt in pairs(Runtime.VirtualThreats) do
        if pointInsideVirtual(Runtime.Root.Position, vt)
            or pointInsideVirtual(predicted, vt)
        then
            return true
        end
    end

    local enemy, dist = nearestPhysicalEnemy(Runtime.Root.Position)

    if enemy then
        local dynamicRadius, closing, timeToContact =
            physicalClosingInfo(enemy, Runtime.Root.Position)

        if dist <= CFG.MELEE_CRITICAL_RADIUS then
            return true
        end

        if closing > 2.5
            and timeToContact <= 0.30
        then
            return true
        end
    end

    return false
end


Runtime.DodgeCastBlocked = function()
    if not Runtime.Root
        or not Runtime.Humanoid
        or Runtime.Humanoid.Health <= 0
    then
        return true
    end

    local hpRatio =
        Runtime.Humanoid.MaxHealth > 0
        and (
            Runtime.Humanoid.Health
            / Runtime.Humanoid.MaxHealth
        )
        or 1

    local minimumHp =
        Runtime.FragileMode
        and CFG.DODGE_CAST_FRAGILE_MIN_HP_RATIO
        or CFG.DODGE_CAST_MIN_HP_RATIO

    if hpRatio < minimumHp then
        return true
    end

    local enemy, dist =
        nearestPhysicalEnemy(
            Runtime.Root.Position
        )

    if enemy then
        local _, closing, timeToContact =
            physicalClosingInfo(
                enemy,
                Runtime.Root.Position
            )

        if dist <= CFG.DODGE_CAST_PHYSICAL_GUARD then
            return true
        end

        if closing > 2.5
            and timeToContact <= CFG.DODGE_CAST_TTC_GUARD
        then
            return true
        end
    end

    return false
end


local function lineEmergencyCandidate(origin, threats)
    local oldPenalty, oldInside = pointDanger(origin)
    local best
    local bestScore = math.huge

    for _, meta in ipairs(threats) do
        local g = threatGeometry(meta)

        if g and g.Type == "Box"
            and meta.Kind == "Precast"
            and pointInsideThreat(meta, origin)
        then
            local part = g.Part
            local lp = part.CFrame:PointToObjectSpace(origin)
            local axisA, axisB = horizontalAxesForPart(part)

            local shortAxis, longAxis = axisA, axisB
            if axisB.Half < axisA.Half then
                shortAxis, longAxis = axisB, axisA
            end

            local aspect =
                longAxis.Half / math.max(shortAxis.Half, 0.1)

            if aspect >= CFG.LARGE_LINE_ASPECT_RATIO then
                local worldAxis = horizontal(shortAxis.Vec)

                if worldAxis.Magnitude > 0.05 then
                    worldAxis = worldAxis.Unit

                    local coord =
                        componentByIndex(lp, shortAxis.LocalIndex)

                    local plus =
                        shortAxis.Half
                        + CFG.SAFETY_MARGIN
                        - coord
                        + CFG.LARGE_LINE_EXTRA_MARGIN

                    local minus =
                        shortAxis.Half
                        + CFG.SAFETY_MARGIN
                        + coord
                        + CFG.LARGE_LINE_EXTRA_MARGIN

                    for _, option in ipairs({
                        {Dir = worldAxis, Distance = plus, Label = "line_short_plus"},
                        {Dir = -worldAxis, Distance = minus, Label = "line_short_minus"},
                    }) do
                        if option.Distance > 0
                            and option.Distance <= CFG.LARGE_LINE_FAST_SHIFT_MAX
                        then
                            local pos = origin + option.Dir * option.Distance
                            local penalty, inside = pointDanger(pos)

                            if inside < oldInside then
                                local score =
                                    penalty
                                    + option.Distance * 5
                                    + enemyPenalty(pos)

                                if score < bestScore then
                                    bestScore = score
                                    best = {
                                        Position = pos,
                                        Radius = option.Distance,
                                        Label = option.Label,
                                        OldInside = oldInside,
                                        NewInside = inside,
                                        Source = meta.RootName,
                                        ThreatCreated = meta.Created,
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

local function walkingLikelyEnough(plan, estimatedImpactAt)
    if not plan
        or not Runtime.Root
        or not Runtime.Humanoid
    then
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            plan.Position
        )

    local walkSpeed = math.max(Runtime.Humanoid.WalkSpeed, 1)
    local walkEta = distance / walkSpeed

    local timeLeft =
        math.max(
            0,
            estimatedImpactAt - os.clock()
        )

    return walkEta + CFG.WALK_ETA_SAFETY <= timeLeft
end

local function teleportBudgetStatus(now)
    now = now or os.clock()

    local kept = {}

    for _, at in ipairs(Runtime.TeleportHistory) do
        if now - at <= CFG.TELEPORT_WINDOW_SECONDS then
            kept[#kept + 1] = at
        end
    end

    Runtime.TeleportHistory = kept

    local sinceLast =
        now - Runtime.LastTeleportAt

    if sinceLast < CFG.TELEPORT_GLOBAL_COOLDOWN then
        return
            false,
            "global_cooldown",
            CFG.TELEPORT_GLOBAL_COOLDOWN - sinceLast
    end

    if #Runtime.TeleportHistory
        >= CFG.TELEPORT_WINDOW_MAX
    then
        local oldest =
            Runtime.TeleportHistory[1]

        return
            false,
            "window_budget",
            math.max(
                0,
                CFG.TELEPORT_WINDOW_SECONDS
                - (now - oldest)
            )
    end

    return true, "ok", 0
end

local function teleportBudgetAvailable(now)
    local okay =
        teleportBudgetStatus(now)

    return okay == true
end

local function logTeleportBlocked(source, now)
    now = now or os.clock()

    if now - Runtime.LastTeleportBlockLog
        < CFG.TELEPORT_BLOCK_LOG_COOLDOWN
    then
        return
    end

    local okay, reason, remaining =
        teleportBudgetStatus(now)

    if okay then
        return
    end

    Runtime.LastTeleportBlockLog = now

    logKV("TELEPORT_GOVERNOR_BLOCK", {
        source = tostring(source),
        reason = tostring(reason),
        remaining = string.format(
            "%.2f",
            remaining or 0
        ),
        since_last = string.format(
            "%.2f",
            now - Runtime.LastTeleportAt
        ),
        last_tag =
            tostring(
                Runtime.LastTeleportTag
                or "none"
            ),
        total = Runtime.TeleportTotal,
    })
end

local function recordTeleport(
    now,
    tag,
    fromPosition,
    toPosition,
    studs
)
    now = now or os.clock()

    Runtime.LastTeleportAt = now
    Runtime.TeleportHistory[
        #Runtime.TeleportHistory + 1
    ] = now

    Runtime.TeleportTotal += 1
    Runtime.LastTeleportTag =
        tag or "POSITION_SHIFT"
    Runtime.LastTeleportFrom =
        fromPosition
    Runtime.LastTeleportTo =
        toPosition
    Runtime.LastTeleportStuds =
        studs or 0
end


local function shiftPlanIsIntentionalHold(best)
    if not best then
        return false
    end

    return
        best.Label == "azrallik_finger_hold"
        or best.Label == "azrallik_beam_early_hold"
        or best.Label == "overgrowth_forward_hold"
        or best.Label == "kolvumar_spit_hold"
        or best.Label == "kolvumar_spit_emergency"
end

local function rearmMovementAfterShift(
    best,
    candidate,
    counterTag
)
    if not CFG.POST_SHIFT_CONTINUE_ENABLED
        or not best
        or not best.Position
        or not Runtime.Humanoid
        or not Runtime.Root
        or shiftPlanIsIntentionalHold(best)
    then
        return
    end

    local remaining =
        horizontalDistance(
            candidate,
            best.Position
        )

    if remaining
        < CFG.POST_SHIFT_CONTINUE_MIN_DISTANCE
    then
        return
    end

    local direction =
        unitHorizontal(
            best.Position - candidate
        )

    if direction.Magnitude <= 0.1 then
        return
    end

    local step =
        math.min(
            remaining,
            CFG.POST_SHIFT_CONTINUE_MAX_STEP
        )

    local localTarget =
        candidate
        + direction * step

    local destinationOkay =
        safeMovementDestination(
            localTarget,
            candidate
        )

    if not destinationOkay
        or movementWallHit(
            candidate,
            localTarget
        )
    then
        return
    end

    local _, localInside =
        pointDanger(localTarget)

    -- Never continue a positional correction into known active danger.
    if localInside > 0 then
        return
    end

    Runtime.LastMove = -math.huge
    Runtime.LastMoveTarget = nil
    Runtime.LastMoveResolved = nil
    Runtime.LastMoveReason = nil

    moveTo(
        localTarget,
        "POST_SHIFT_CONTINUE"
    )

    local now = os.clock()

    if now - Runtime.LastPostShiftContinueLog
        >= CFG.POST_SHIFT_CONTINUE_LOG_COOLDOWN
    then
        Runtime.LastPostShiftContinueLog = now

        logKV("POST_SHIFT_CONTINUE", {
            source =
                tostring(
                    counterTag
                    or best.Source
                ),
            planner =
                tostring(
                    best.Label
                ),
            remaining =
                string.format(
                    "%.2f",
                    remaining
                ),
            local_step =
                string.format(
                    "%.2f",
                    step
                ),
            target =
                vec(localTarget),
        })
    end
end


local function doFastShift(best, maxDistance, cooldown, counterTag, allowPartial)
    if not best or not Runtime.Root then
        return false
    end

    local now = os.clock()

    -- Reliability rule: no direct Root CFrame shift while Azrallik is active.
    -- Normal MoveTo/lane/pocket logic remains fully active. This is a stability
    -- fallback, not an attempt to suppress or bypass a kick.
    if Runtime.ActiveBossName == "Demon Lord Azrallik" then
        if now - Runtime.LastAzrallikShiftSuppressLog
            >= 0.85
        then
            Runtime.LastAzrallikShiftSuppressLog = now

            logKV("AZRALLIK_SHIFT_SUPPRESSED", {
                source =
                    tostring(
                        counterTag
                        or (
                            best
                            and best.Source
                        )
                        or "unknown"
                    ),
                planner =
                    tostring(
                        best.Label
                        or "unknown"
                    ),
            })
        end

        return false
    end

    if now - Runtime.LastFastShift < cooldown then
        return false
    end

    if not teleportBudgetAvailable(now) then
        return false
    end

    local delta = horizontal(best.Position - Runtime.Root.Position)

    if delta.Magnitude < 0.3 then
        return false
    end

    if not allowPartial
        and delta.Magnitude > maxDistance + 0.15
    then
        return false
    end

    local shift = math.min(delta.Magnitude, maxDistance)

    local candidate =
        Runtime.Root.Position
        + delta.Unit * shift

    local oldPenalty, oldInside = pointDanger(Runtime.Root.Position)
    local newPenalty, newInside = pointDanger(candidate)

    if newInside < oldInside
        or newPenalty < oldPenalty * 0.55
    then
        local rotation =
            Runtime.Root.CFrame
            - Runtime.Root.CFrame.Position

        local fromPosition =
            Runtime.Root.Position

        local sinceLast =
            now - Runtime.LastTeleportAt

        Runtime.Root.CFrame =
            CFrame.new(candidate) * rotation

        Runtime.LastFastShift = now

        recordTeleport(
            now,
            counterTag or "FAST_SHIFT",
            fromPosition,
            candidate,
            shift
        )

        logKV(counterTag or "FAST_SHIFT", {
            studs = string.format("%.2f", shift),
            requested = string.format("%.2f", delta.Magnitude),
            old_inside = oldInside,
            new_inside = newInside,
            planner = tostring(best.Label),
            source = tostring(best.Source),
            from = vec(fromPosition),
            to = vec(candidate),
            since_last =
                sinceLast == math.huge
                and "inf"
                or string.format("%.2f", sinceLast),
            total = Runtime.TeleportTotal,
        })

        rearmMovementAfterShift(
            best,
            candidate,
            counterTag
        )

        return true, newInside
    end

    return false, oldInside
end

local function doMicroTeleport(best)
    if not CFG.MICRO_TELEPORT
        or not best
        or not Runtime.Root
    then
        return false
    end

    local now = os.clock()

    if now-Runtime.LastMicro
        < CFG.MICRO_TELEPORT_COOLDOWN
        or not teleportBudgetAvailable(now)
    then
        return false
    end

    local delta =
        horizontal(
            best.Position
            - Runtime.Root.Position
        )

    if delta.Magnitude < 0.3 then
        return false
    end

    local shift =
        math.min(
            delta.Magnitude,
            CFG.MICRO_TELEPORT_MAX
        )

    local candidate =
        Runtime.Root.Position
        + delta.Unit*shift

    local oldPenalty,oldInside =
        pointDanger(Runtime.Root.Position)

    local newPenalty,newInside =
        pointDanger(candidate)

    if newInside < oldInside
        or newPenalty < oldPenalty*0.45
    then
        local rotation =
            Runtime.Root.CFrame
            - Runtime.Root.CFrame.Position

        local fromPosition =
            Runtime.Root.Position

        local sinceLast =
            now - Runtime.LastTeleportAt

        Runtime.Root.CFrame =
            CFrame.new(candidate)
            * rotation

        Runtime.LastMicro = now

        recordTeleport(
            now,
            "MICRO_DODGE",
            fromPosition,
            candidate,
            shift
        )

        Runtime.MicroCount += 1

        logKV("MICRO_DODGE", {
            count = Runtime.MicroCount,
            studs = string.format("%.2f",shift),
            old_inside = oldInside,
            new_inside = newInside,
            from = vec(fromPosition),
            to = vec(candidate),
            since_last =
                string.format("%.2f", sinceLast),
            total = Runtime.TeleportTotal,
        })

        rearmMovementAfterShift(
            best,
            candidate,
            "MICRO_DODGE"
        )

        return true
    end

    return false
end

-- ============================================================
-- Dodge controller
-- ============================================================

-- V7.1 HOTFIX: these helpers must be declared before dodgeThink.
local function safeCombatDestination(desired)
    if not Runtime.Root or not desired then
        return desired
    end

    local origin = Runtime.Root.Position
    local dangerAtDestination, insideAtDestination =
        pointDanger(desired)

    local crossingDanger =
        routeDanger(origin, desired)

    if insideAtDestination == 0
        and dangerAtDestination < 1200
        and crossingDanger < 2500
    then
        return desired
    end

    local preferred =
        unitHorizontal(
            desired - origin
        )

    local open =
        chooseOpenSpacePoint(
            origin,
            preferred
        )

    if open then
        logKV("COMBAT_HAZARD_ROUTE", {
            requested = vec(desired),
            resolved = vec(open.Position),
            inside = insideAtDestination,
            route = string.format("%.0f", crossingDanger),
        })

        return open.Position
    end

    return desired
end

local function physicalPressureSettings(enemy)
    if not enemy or not enemy.Model then
        return CFG.MELEE_SOFT_RADIUS, CFG.MELEE_RELEASE_RADIUS, CFG.MELEE_CRITICAL_RADIUS
    end

    if enemy.Model.Name == "Blood Minion" then
        return
            CFG.BLOOD_MINION_SOFT_RADIUS,
            CFG.BLOOD_MINION_RELEASE_RADIUS,
            CFG.BLOOD_MINION_CRITICAL_RADIUS
    end

    return
        CFG.MELEE_SOFT_RADIUS,
        CFG.MELEE_RELEASE_RADIUS,
        CFG.MELEE_CRITICAL_RADIUS
end

local function physicalEmergencyState()
    if not Runtime.Root then
        return nil
    end

    local enemy, dist =
        nearestPhysicalEnemy(Runtime.Root.Position)

    if not enemy then
        return nil
    end

    local _, _, criticalRadius =
        physicalPressureSettings(enemy)

    local _, closing, timeToContact =
        physicalClosingInfo(enemy, Runtime.Root.Position)

    local imminent =
        dist <= criticalRadius
        or (
            closing >= CFG.PHYSICAL_FAST_EMERGENCY_CLOSING
            and (
                dist <= CFG.PHYSICAL_FAST_EMERGENCY_RADIUS
                or timeToContact <= CFG.PHYSICAL_FAST_EMERGENCY_TTC
            )
        )

    if not imminent then
        return nil
    end

    return {
        Enemy = enemy,
        Distance = dist,
        Closing = closing,
        TimeToContact = timeToContact,
        CriticalRadius = criticalRadius,
    }
end

local function physicalEmergencyCandidate(state)
    if not state
        or not state.Enemy
        or not state.Enemy.Root
        or not Runtime.Root
    then
        return nil
    end

    local origin = Runtime.Root.Position
    local away =
        unitHorizontal(
            origin - state.Enemy.Root.Position
        )

    local tangent =
        Vector3.new(
            -away.Z,
            0,
            away.X
        ) * Runtime.OrbitSign

    local dir =
        unitHorizontal(
            away * 1.0
            + tangent * 0.35
        )

    local distance =
        math.min(
            CFG.MELEE_FAST_SHIFT_MAX,
            math.max(
                3.5,
                state.CriticalRadius - state.Distance + 4.0
            )
        )

    local destination =
        origin + dir * distance

    if wallBlocked(origin, destination) then
        destination =
            origin + away * distance
    end

    local _, inside, clearance = pointDanger(destination)

    return {
        Position = destination,
        Radius = distance,
        Label = "physical_emergency",
        Source = state.Enemy.Model.Name,
        Inside = inside,
        Clearance = clearance,
    }
end

local function guardOvergrowthForwardPlan(plan, bossWave)
    if plan
        and plan.Label == "overgrowth_edge_follow"
    then
        return plan
    end

    if not plan
        or not bossWave
        or bossWave.Boss ~= "Demonic Overgrowth"
        or not bossWave.SequenceDir
        or not bossWave.SequenceOrigin
        or not Runtime.Root
    then
        return plan
    end

    local now =
        os.clock()

    local currentProjection =
        horizontal(
            Runtime.Root.Position
            - bossWave.SequenceOrigin
        ):Dot(bossWave.SequenceDir)

    bossWave.SequenceMaxProjection =
        math.max(
            bossWave.SequenceMaxProjection
                or -math.huge,
            currentProjection
        )

    local planProjection =
        horizontal(
            plan.Position
            - bossWave.SequenceOrigin
        ):Dot(bossWave.SequenceDir)

    local minimumProjection =
        (bossWave.SequenceMaxProjection
            or currentProjection)
        - CFG.OVERGROWTH_BACKTRACK_TOLERANCE

    if planProjection < minimumProjection then
        if now - Runtime.LastOvergrowthBacktrackLog
            >= CFG.OVERGROWTH_BACKTRACK_LOG_COOLDOWN
        then
            Runtime.LastOvergrowthBacktrackLog = now

            logKV("OVERGROWTH_BACKTRACK_BLOCK", {
                wave = bossWave.Id,
                current_projection =
                    string.format(
                        "%.2f",
                        currentProjection
                    ),
                max_projection =
                    string.format(
                        "%.2f",
                        bossWave.SequenceMaxProjection
                    ),
                requested_projection =
                    string.format(
                        "%.2f",
                        planProjection
                    ),
                planner = tostring(plan.Label),
            })
        end

        -- Hold the current forward-most position rather than walk back toward
        -- an earlier strip. Dodge geometry may still replace this on the next
        -- replan if a genuinely safer forward/lateral point exists.
        local _, inside, clearance =
            pointDanger(Runtime.Root.Position)

        return {
            Position = Runtime.Root.Position,
            Radius = 0,
            Score = plan.Score or 0,
            Inside = inside,
            Clearance = clearance,
            Label = "overgrowth_forward_hold",
            Source = "OvergrowthForwardGuard",
            TimeToContact = plan.TimeToContact,
        }
    end

    return plan
end


local function kolvumarSpitThreats(
    bossThreats
)
    local out = {}
    local seen = {}

    for _, meta in ipairs(
        bossThreats or {}
    ) do
        if meta.RootName == "kolvumarSpit"
            and meta.Part
            and meta.Part.Parent
        then
            local key =
                string.format(
                    "%.1f:%.1f:%.1f",
                    meta.Part.Position.X,
                    meta.Part.Position.Y,
                    meta.Part.Position.Z
                )

            -- Active hitbox and precast often share the same center. One
            -- representative is enough for union tests.
            if not seen[key]
                or meta.Kind == "ActiveHitbox"
            then
                seen[key] = meta
            end
        end
    end

    for _, meta in pairs(seen) do
        out[#out + 1] = meta
    end

    return out
end

local function kolvumarSpitInsideCount(
    point,
    spitThreats
)
    local count = 0

    for _, meta in ipairs(
        spitThreats or {}
    ) do
        if pointInsideThreat(meta, point) then
            count += 1
        end
    end

    return count
end

local function kolvumarSpitRouteSafe(
    fromPosition,
    toPosition,
    spitThreats
)
    local delta =
        toPosition - fromPosition

    local distance =
        horizontal(delta).Magnitude

    if distance <= 0.1 then
        return
            kolvumarSpitInsideCount(
                toPosition,
                spitThreats
            ) == 0
    end

    local samples =
        math.max(
            1,
            math.ceil(
                distance
                / CFG.KOLVUMAR_SPIT_ROUTE_SAMPLE_STEP
            )
        )

    for i = 1, samples do
        local point =
            fromPosition
            + delta * (i / samples)

        if kolvumarSpitInsideCount(
            point,
            spitThreats
        ) > 0
        then
            return false
        end
    end

    return true
end

local function kolvumarLocalEscapeCandidate(
    bossWave,
    spitThreats,
    currentInside
)
    if not Runtime.Root then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local bossRoot =
        Runtime.ActiveBossModel
        and modelRoot(
            Runtime.ActiveBossModel
        )

    local towardBoss =
        bossRoot
        and unitHorizontal(
            bossRoot.Position - origin
        )
        or unitHorizontal(
            Runtime.Root.CFrame.LookVector
        )

    local away =
        -towardBoss

    -- If the player is inside a particular puddle, bias the first search
    -- directly away from the newest containing center.
    local newestContaining

    for _, meta in ipairs(spitThreats) do
        if pointInsideThreat(
            meta,
            origin
        ) then
            if not newestContaining
                or meta.Created
                    > newestContaining.Created
            then
                newestContaining = meta
            end
        end
    end

    if newestContaining then
        local fromPuddle =
            unitHorizontal(
                origin
                - newestContaining.Part.Position
            )

        if fromPuddle.Magnitude > 0.1 then
            away = fromPuddle
        end
    end

    if away.Magnitude <= 0.1 then
        away = Vector3.new(1, 0, 0)
    end

    local baseAngle =
        math.atan2(
            away.Z,
            away.X
        )

    local best
    local bestScore = math.huge

    for _, radius in ipairs(
        CFG.KOLVUMAR_SPIT_SEARCH_RADII
    ) do
        for _, degrees in ipairs(
            CFG.KOLVUMAR_SPIT_SEARCH_ANGLES
        ) do
            local angle =
                baseAngle
                + math.rad(degrees)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate =
                origin + dir * radius

            if hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
                and kolvumarSpitInsideCount(
                    candidate,
                    spitThreats
                ) == 0
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                local bossDistance =
                    bossRoot
                    and horizontalDistance(
                        candidate,
                        bossRoot.Position
                    )
                    or CFG.KOLVUMAR_DESIRED_RANGE

                local rangeError =
                    math.abs(
                        bossDistance
                        - CFG.KOLVUMAR_DESIRED_RANGE
                    )

                local score =
                    radius * 115
                    + rangeError * 22
                    + wavePhysicalPenalty(candidate)
                    + danger * 0.05
                    + inside * 6000

                if clearance ~= math.huge then
                    score -=
                        math.min(
                            math.max(clearance, 0),
                            24
                        ) * 65
                end

                if score < bestScore then
                    bestScore = score

                    best = {
                        Position = candidate,
                        Radius = radius,
                        Score = score,
                        Inside = inside,
                        Clearance = clearance,
                        Label = "kolvumar_spit_emergency",
                        Source = "KolvumarSpitUnion",
                        InsideSpits = currentInside,
                    }
                end
            end
        end
    end

    return best
end

local function kolvumarSafeSlideCandidate(
    bossWave,
    spitThreats
)
    if not Runtime.Root
        or not Runtime.ActiveBossModel
    then
        return nil
    end

    local bossRoot =
        modelRoot(
            Runtime.ActiveBossModel
        )

    if not bossRoot then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local toward =
        unitHorizontal(
            bossRoot.Position - origin
        )

    if toward.Magnitude <= 0.1 then
        return nil
    end

    local baseAngle =
        math.atan2(
            toward.Z,
            toward.X
        )

    local best
    local bestScore = math.huge

    for _, step in ipairs({
        12.0,
        CFG.KOLVUMAR_SPIT_SAFE_SLIDE_STEP,
        8.0,
        6.0,
        4.0,
        CFG.KOLVUMAR_SPIT_SAFE_SLIDE_MIN,
    }) do
        for _, degrees in ipairs({
            0, 25, -25, 50, -50, 75, -75,
            90, -90, 115, -115, 150, -150
        }) do
            local angle =
                baseAngle
                + math.rad(degrees)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate =
                origin + dir * step

            if hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
                and kolvumarSpitInsideCount(
                    candidate,
                    spitThreats
                ) == 0
                and kolvumarSpitRouteSafe(
                    origin,
                    candidate,
                    spitThreats
                )
            then
                local _, inside, clearance =
                    pointDanger(candidate)

                local bossDistance =
                    horizontalDistance(
                        candidate,
                        bossRoot.Position
                    )

                local score =
                    math.abs(
                        bossDistance
                        - CFG.KOLVUMAR_DESIRED_RANGE
                    ) * 35
                    + wavePhysicalPenalty(candidate)
                    + step * 12
                    + inside * 3500

                if score < bestScore then
                    bestScore = score

                    best = {
                        Position = candidate,
                        Radius = step,
                        Score = score,
                        Inside = inside,
                        Clearance = clearance,
                        Label = "kolvumar_spit_slide",
                        Source = "KolvumarSpitSafeSlide",
                    }
                end
            end
        end
    end

    return best
end

local function kolvumarSpitEmergencyCandidate(
    bossWave,
    bossThreats
)
    if not Runtime.Root
        or not bossWave
    then
        return nil
    end

    local spitThreats =
        kolvumarSpitThreats(
            bossThreats
        )

    if #spitThreats == 0 then
        bossWave.KolvumarPocket = nil
        bossWave.KolvumarPocketUntil = -math.huge
        bossWave.KolvumarPocketReached = false
        Runtime.KolvumarRecoveryPosition = nil
        Runtime.KolvumarRecoveryUntil = -math.huge
        return nil
    end

    local now = os.clock()

    local currentInside =
        kolvumarSpitInsideCount(
            Runtime.Root.Position,
            spitThreats
        )

    -- Highest priority: get out of the union of active puddles.
    if CFG.KOLVUMAR_STALL_RECOVERY_COMMIT_ENABLED
        and currentInside > 0
        and Runtime.KolvumarRecoveryPosition
        and now < (
            Runtime.KolvumarRecoveryUntil
            or -math.huge
        )
    then
        local recoveryInside =
            kolvumarSpitInsideCount(
                Runtime.KolvumarRecoveryPosition,
                spitThreats
            )

        if recoveryInside == 0
            and hasGroundAt(
                Runtime.KolvumarRecoveryPosition
            )
        then
            local _, inside, clearance =
                pointDanger(
                    Runtime.KolvumarRecoveryPosition
                )

            return {
                Position =
                    Runtime.KolvumarRecoveryPosition,
                Radius =
                    horizontalDistance(
                        Runtime.Root.Position,
                        Runtime.KolvumarRecoveryPosition
                    ),
                Score = 0,
                Inside = inside,
                Clearance = clearance,
                Label =
                    "kolvumar_spit_recovery_commit",
                Source =
                    "KolvumarStallRecovery",
                InsideSpits = currentInside,
            }
        end

        Runtime.KolvumarRecoveryPosition = nil
        Runtime.KolvumarRecoveryUntil = -math.huge
    end

    if currentInside > 0 then
        local escape =
            kolvumarLocalEscapeCandidate(
                bossWave,
                spitThreats,
                currentInside
            )

        if escape then
            bossWave.KolvumarPocket =
                escape.Position
            bossWave.KolvumarPocketUntil =
                now
                + CFG.KOLVUMAR_SPIT_POST_ESCAPE_HOLD
            bossWave.KolvumarPocketReached =
                false

            if now - Runtime.LastKolvumarSpitRescueAt
                >= CFG.KOLVUMAR_SPIT_LOG_COOLDOWN
            then
                Runtime.LastKolvumarSpitRescueAt = now

                logKV("KOLVUMAR_SPIT_EMERGENCY", {
                    inside = currentInside,
                    distance =
                        string.format(
                            "%.2f",
                            escape.Radius
                        ),
                    clearance =
                        escape.Clearance == math.huge
                        and "inf"
                        or string.format(
                            "%.2f",
                            escape.Clearance or 0
                        ),
                    source =
                        tostring(
                            escape.Source
                        ),
                })
            end
        end

        return escape
    end

    -- After an escape, do not immediately walk back toward Kolvumar through
    -- the same puddle. Hold the saved pocket briefly unless a new spit covers it.
    if bossWave.KolvumarPocket
        and now < (
            bossWave.KolvumarPocketUntil
            or -math.huge
        )
    then
        local pocketInside =
            kolvumarSpitInsideCount(
                bossWave.KolvumarPocket,
                spitThreats
            )

        if pocketInside == 0 then
            local distance =
                horizontalDistance(
                    Runtime.Root.Position,
                    bossWave.KolvumarPocket
                )

            local _, inside, clearance =
                pointDanger(
                    bossWave.KolvumarPocket
                )

            return {
                Position =
                    bossWave.KolvumarPocket,
                Radius = distance,
                Score = 0,
                Inside = inside,
                Clearance = clearance,
                Label = "kolvumar_spit_hold",
                Source = "KolvumarSpitHold",
            }
        end

        bossWave.KolvumarPocket = nil
        bossWave.KolvumarPocketUntil = -math.huge
        bossWave.KolvumarPocketReached = false
    end

    -- After a direct rescue, keep MOVING through route-safe local points for
    -- the whole global teleport cooldown. V10.0 deaths repeatedly happened
    -- when another spit landed while the 3-second governor was still cooling.
    if now < (
        bossWave.KolvumarPostRescueUntil
        or -math.huge
    ) then
        local cooldownSlide =
            kolvumarSafeSlideCandidate(
                bossWave,
                spitThreats
            )

        if cooldownSlide then
            cooldownSlide.Label =
                "kolvumar_spit_cooldown_slide"
            cooldownSlide.Source =
                "KolvumarPostRescueMotion"

            return cooldownSlide
        end
    end

    -- Puddles still exist, but the character is safe. Move only through a
    -- puddle-safe local route toward boss range rather than using a distant
    -- generic 30-46 stud boss-wave destination.
    local slide =
        kolvumarSafeSlideCandidate(
            bossWave,
            spitThreats
        )

    if slide then
        bossWave.KolvumarPocket =
            slide.Position

        return slide
    end

    local _, inside, clearance =
        pointDanger(
            Runtime.Root.Position
        )

    return {
        Position = Runtime.Root.Position,
        Radius = 0,
        Score = 0,
        Inside = inside,
        Clearance = clearance,
        Label = "kolvumar_spit_hold",
        Source = "KolvumarSpitNoRouteHold",
    }
end

local function holdKolvumarSpitPocket(
    bossWave,
    plan
)
    if not Runtime.Root
        or not Runtime.Humanoid
        or not bossWave
        or not plan
    then
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            plan.Position
        )

    if distance
        > CFG.KOLVUMAR_SPIT_HOLD_DISTANCE
    then
        moveTo(
            plan.Position,
            "KOLVUMAR_SPIT_HOLD"
        )

        return true
    end

    pcall(function()
        Runtime.Humanoid:MoveTo(
            Runtime.Root.Position
        )

        Runtime.Humanoid:Move(
            Vector3.zero,
            false
        )
    end)

    Runtime.MovementOwner =
        "KOLVUMAR_SPIT_HOLD"

    if not bossWave.KolvumarPocketReached then
        bossWave.KolvumarPocketReached = true

        logKV("KOLVUMAR_SPIT_HOLD", {
            wave = bossWave.Id,
            position =
                vec(Runtime.Root.Position),
        })
    end

    return true
end


local function azrallikFingerBlastCandidate(
    bossWave,
    bossThreats
)
    if not Runtime.Root
        or not bossWave
    then
        return nil
    end

    local fingerPart

    for _, meta in ipairs(
        bossThreats or {}
    ) do
        if meta.RootName == "fingerBlastHit"
            and meta.Part
            and meta.Part.Parent
        then
            fingerPart = meta.Part
            break
        end
    end

    if not fingerPart then
        bossWave.FingerBlastStartedAt = nil
        bossWave.FingerBlastCenter = nil
        return nil
    end

    local now = os.clock()

    if not bossWave.FingerBlastStartedAt then
        bossWave.FingerBlastStartedAt = now
        bossWave.FingerBlastCenter =
            fingerPart.Position
    end

    local center =
        bossWave.FingerBlastCenter
        or fingerPart.Position

    local origin =
        Runtime.Root.Position

    local away =
        unitHorizontal(
            origin - center
        )

    if away.Magnitude <= 0.1 then
        local bossRoot =
            Runtime.ActiveBossModel
            and modelRoot(
                Runtime.ActiveBossModel
            )

        away =
            bossRoot
            and unitHorizontal(
                origin - bossRoot.Position
            )
            or unitHorizontal(
                Runtime.Root.CFrame.LookVector
            )
    end

    local elapsed =
        now
        - bossWave.FingerBlastStartedAt

    local distanceFromCenter =
        horizontalDistance(
            origin,
            center
        )

    local _, currentInside, currentClearance =
        pointDanger(origin)

    if elapsed <= CFG.AZRALLIK_FINGER_HOLD_TIME
        and distanceFromCenter
            >= CFG.AZRALLIK_FINGER_MIN_DISTANCE
        and currentInside == 0
    then
        return {
            Position = origin,
            Radius = 0,
            Score = 0,
            Inside = 0,
            Clearance = currentClearance,
            Label = "azrallik_finger_hold",
            Source = "AzrallikFingerHold",
        }
    end

    local baseAngle =
        math.atan2(
            away.Z,
            away.X
        )

    local best
    local bestScore = math.huge

    for _, radius in ipairs(
        CFG.AZRALLIK_FINGER_CANDIDATE_RADII
    ) do
        for _, degrees in ipairs(
            CFG.AZRALLIK_FINGER_ANGLES
        ) do
            local angle =
                baseAngle
                + math.rad(degrees)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate =
                Vector3.new(
                    center.X,
                    origin.Y,
                    center.Z
                )
                + dir * radius

            if hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                if inside == 0 then
                    local travel =
                        horizontalDistance(
                            origin,
                            candidate
                        )

                    local route =
                        routeDanger(
                            origin,
                            candidate
                        )

                    local score =
                        danger
                        + route * 0.20
                        + travel * 95
                        + wavePhysicalPenalty(candidate)

                    if clearance ~= math.huge then
                        score -=
                            math.min(
                                math.max(clearance, 0),
                                30
                            ) * 120
                    end

                    if score < bestScore then
                        bestScore = score
                        best = {
                            Position = candidate,
                            Radius = travel,
                            Score = score,
                            Inside = inside,
                            Clearance = clearance,
                            Label = "azrallik_finger_escape",
                            Source = "AzrallikFingerBlast",
                        }
                    end
                end
            end
        end
    end

    if best
        and now - Runtime.LastAzrallikFingerLog
            >= CFG.AZRALLIK_FINGER_LOG_COOLDOWN
    then
        Runtime.LastAzrallikFingerLog = now

        logKV("AZRALLIK_FINGER_ESCAPE", {
            wave = bossWave.Id,
            elapsed =
                string.format(
                    "%.2f",
                    elapsed
                ),
            travel =
                string.format(
                    "%.2f",
                    best.Radius
                ),
            from_center =
                string.format(
                    "%.2f",
                    distanceFromCenter
                ),
            clearance =
                best.Clearance == math.huge
                and "inf"
                or string.format(
                    "%.2f",
                    best.Clearance or 0
                ),
        })
    end

    return best
end


local function azrallikSafePressureCandidate(
    bossWave,
    bossThreats
)
    if not CFG.AZRALLIK_SAFE_PRESSURE_ENABLED
        or not Runtime.Root
        or not bossWave
        or bossWave.Boss ~= "Demon Lord Azrallik"
        or bossThreatHas(
            "horizontalBeam",
            bossThreats
        )
    then
        return nil
    end

    local now = os.clock()

    if now - (bossWave.LastSafePressureAt or -math.huge)
        < CFG.AZRALLIK_SAFE_PRESSURE_INTERVAL
    then
        return nil
    end

    local targetRoot =
        azrallikPhaseTargetRoot()

    if not targetRoot then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local currentDistance =
        horizontalDistance(
            origin,
            targetRoot.Position
        )

    if currentDistance
        <= CFG.AZRALLIK_SAFE_PRESSURE_RANGE
    then
        return nil
    end

    local _, currentInside, currentClearance =
        pointDanger(origin)

    if currentInside > 0 then
        return nil
    end

    local requiredClearance =
        CFG.AZRALLIK_SAFE_PRESSURE_MIN_CLEARANCE

    if currentClearance ~= math.huge then
        requiredClearance =
            math.max(
                requiredClearance,
                math.min(
                    CFG.AZRALLIK_SAFE_PRESSURE_MAX_REQUIRED_CLEARANCE,
                    currentClearance
                    * CFG.AZRALLIK_SAFE_PRESSURE_CLEARANCE_KEEP
                )
            )
    end

    local toward =
        unitHorizontal(
            targetRoot.Position - origin
        )

    if toward.Magnitude <= 0.1 then
        return nil
    end

    bossWave.LastSafePressureAt = now

    for _, step in ipairs({
        CFG.AZRALLIK_SAFE_PRESSURE_STEP,
        8.0,
        6.0,
        4.0,
        3.0,
    }) do
        local candidate =
            origin + toward * step

        local safeDestination =
            safeMovementDestination(
                candidate,
                origin
            )

        if safeDestination
            and not movementWallHit(
                origin,
                candidate
            )
            and exactThreatRouteSafe(
                origin,
                candidate
            )
        then
            local _, inside, clearance =
                pointDanger(candidate)

            if inside == 0
                and (
                    clearance == math.huge
                    or clearance
                        >= requiredClearance
                )
            then
                if now - Runtime.LastAzrallikPressureLog
                    >= CFG.AZRALLIK_SAFE_PRESSURE_LOG_COOLDOWN
                then
                    Runtime.LastAzrallikPressureLog = now

                    logKV("AZRALLIK_SAFE_PRESSURE", {
                        wave = bossWave.Id,
                        step = string.format("%.1f", step),
                        target =
                            Runtime.Target
                            and Runtime.Target.Name
                            or "Demon Lord Azrallik",
                        distance =
                            string.format(
                                "%.1f",
                                currentDistance
                            ),
                        clearance =
                            clearance == math.huge
                            and "inf"
                            or string.format(
                                "%.2f",
                                clearance
                            ),
                    })
                end

                return {
                    Position = candidate,
                    Radius = step,
                    Score = 0,
                    Inside = 0,
                    Clearance = clearance,
                    Label = "azrallik_safe_pressure",
                    Source = "AzrallikSafePressure",
                }
            end
        end
    end

    return nil
end


local function resetDodgeMoveWatch()
    Runtime.DodgeMoveWatch = nil
    Runtime.LastDodgeMoveLabel = nil
    Runtime.LastDodgeMoveTarget = nil
end

local function dodgeMoveProgressWatch(
    plan,
    reason,
    waveId,
    currentInside
)
    if not Runtime.Root
        or not plan
        or not plan.Position
    then
        return false
    end

    -- Intentional hold positions must never be interpreted as a movement stall.
    if reason == "AZRALLIK_BEAM_POCKET"
        or Runtime.MovementOwner == "AZRALLIK_POCKET_HOLD"
        or Runtime.MovementOwner == "AZRALLIK_FINGER_HOLD"
        or Runtime.MovementOwner == "AZRALLIK_FINGER_PREHOLD"
        or Runtime.MovementOwner == "AZRALLIK_SPREAD_HOLD"
        or Runtime.MovementOwner == "KOLVUMAR_SPIT_HOLD"
        or Runtime.MovementOwner == "KOLVUMAR_SPIT_COOLDOWN_SLIDE"
        or Runtime.MovementOwner == "KOLVUMAR_SPIT_RECOVERY"
    then
        resetDodgeMoveWatch()
        return false
    end

    local now = os.clock()
    local target = plan.Position
    local label =
        tostring(reason or "DODGE")
        .. ":"
        .. tostring(waveId or 0)

    local watch =
        Runtime.DodgeMoveWatch

    if not watch
        or watch.Label ~= label
        or horizontalDistance(
            watch.Target,
            target
        ) > CFG.DODGE_MOVE_WATCH_TARGET_EPS
    then
        Runtime.DodgeMoveWatch = {
            Label = label,
            StartedAt = now,
            Origin = Runtime.Root.Position,
            Target = target,
            StartDistance =
                horizontalDistance(
                    Runtime.Root.Position,
                    target
                ),
        }

        Runtime.LastDodgeMoveLabel = label
        Runtime.LastDodgeMoveTarget = target
        return false
    end

    local moved =
        horizontalDistance(
            Runtime.Root.Position,
            watch.Origin
        )

    local remaining =
        horizontalDistance(
            Runtime.Root.Position,
            target
        )

    if remaining <= 1.25
        or moved >= CFG.DODGE_MOVE_WATCH_MIN_PROGRESS
    then
        -- Movement is real. Re-arm from the new position so a later physical
        -- stall in the same wave can still be detected.
        watch.StartedAt = now
        watch.Origin = Runtime.Root.Position
        watch.Target = target
        watch.StartDistance = remaining
        return false
    end

    if now - watch.StartedAt
        < CFG.DODGE_MOVE_WATCH_TIMEOUT
    then
        return false
    end

    if currentInside <= 0 then
        -- Safe and stationary is allowed; only escalate a stalled dodge while
        -- the player is still in actual dangerous geometry.
        watch.StartedAt = now
        watch.Origin = Runtime.Root.Position
        return false
    end

    if now - Runtime.LastDodgeMoveWatchLog
        >= CFG.DODGE_MOVE_WATCH_LOG_COOLDOWN
    then
        Runtime.LastDodgeMoveWatchLog = now

        logKV("DODGE_MOVE_STALL", {
            label = label,
            owner = tostring(Runtime.MovementOwner),
            moved = string.format("%.2f", moved),
            remaining = string.format("%.2f", remaining),
            inside = currentInside,
            velocity = string.format(
                "%.2f",
                horizontal(
                    Runtime.Root.AssemblyLinearVelocity
                ).Magnitude
            ),
        })
    end

    local preferred =
        unitHorizontal(
            target - Runtime.Root.Position
        )

    local fallback =
        chooseOpenSpacePoint(
            Runtime.Root.Position,
            preferred,
            6
        )

    if fallback then
        local _, oldInside =
            pointDanger(
                Runtime.Root.Position
            )

        local _, newInside =
            pointDanger(
                fallback.Position
            )

        if newInside < oldInside
            or newInside == 0
        then
            moveTo(
                fallback.Position,
                "DODGE_STALL_RECOVERY"
            )

            if CFG.KOLVUMAR_STALL_RECOVERY_COMMIT_ENABLED
                and Runtime.ActiveBossName == "Kolvumar"
                and (
                    reason == "KOLVUMAR_SPIT_ESCAPE"
                    or reason == "KOLVUMAR_SPIT_COOLDOWN_SLIDE"
                )
            then
                Runtime.KolvumarRecoveryPosition =
                    fallback.Position
                Runtime.KolvumarRecoveryUntil =
                    now
                    + CFG.KOLVUMAR_STALL_RECOVERY_COMMIT

                if now - Runtime.LastKolvumarRecoveryLog
                    >= CFG.KOLVUMAR_STALL_RECOVERY_LOG_COOLDOWN
                then
                    Runtime.LastKolvumarRecoveryLog = now

                    logKV("KOLVUMAR_RECOVERY_COMMIT", {
                        reason = tostring(reason),
                        position = vec(fallback.Position),
                        hold =
                            string.format(
                                "%.2f",
                                CFG.KOLVUMAR_STALL_RECOVERY_COMMIT
                            ),
                    })
                end
            end

            logKV("DODGE_STALL_RECOVERY", {
                label = label,
                radius = string.format(
                    "%.1f",
                    fallback.Radius
                ),
                old_inside = oldInside,
                new_inside = newInside,
                position = vec(fallback.Position),
            })
        end
    end

    watch.StartedAt = now
    watch.Origin = Runtime.Root.Position
    watch.Target = target

    return true
end

local function commitOvergrowthFirstEdge(
    bossWave,
    plan,
    currentInside
)
    if not Runtime.Root
        or not Runtime.Humanoid
        or not bossWave
        or not plan
    then
        return false
    end

    local now = os.clock()

    local firstEdgeDirection =
        unitHorizontal(
            plan.Position
            - Runtime.Root.Position
        )

    if firstEdgeDirection.Magnitude > 0.1 then
        bossWave.EdgeFollowDir =
            firstEdgeDirection
        bossWave.EdgeFollowUntil =
            now
            + CFG.OVERGROWTH_EDGE_FOLLOW_TIME
    end

    -- Always issue a real wall-aware MoveTo.
    moveTo(
        plan.Position,
        "OVERGROWTH_EDGE"
    )

    -- V8.7 still ate the first narrow strip in most runs because walking
    -- ~9-10 studs is too close to the ~0.7 sec activation window. If we are
    -- ACTUALLY inside that first strip and the global 3-sec governor permits,
    -- commit one short shift immediately. This consumes the wave teleport so
    -- the later sequence cannot chain another CFrame move.
    if CFG.OVERGROWTH_EDGE_PROACTIVE_SHIFT
        and currentInside > 0
        and not bossWave.Teleported
        and teleportBudgetAvailable(now)
    then
        local shifted, afterInside =
            doFastShift(
                plan,
                CFG.OVERGROWTH_EDGE_PROACTIVE_MAX,
                0,
                "OVERGROWTH_EDGE_PROACTIVE",
                false
            )

        if shifted then
            bossWave.EdgeRescueUsed = true
            bossWave.Teleported = true
            bossWave.TeleportCount =
                (bossWave.TeleportCount or 0) + 1
            bossWave.LastWaveTeleportAt = now
            bossWave.AfterTeleportInside = afterInside

            logKV("OVERGROWTH_EDGE_PROACTIVE_COMMIT", {
                wave = bossWave.Id,
                after_inside = afterInside,
                distance =
                    string.format(
                        "%.2f",
                        horizontalDistance(
                            Runtime.Root.Position,
                            plan.Position
                        )
                    ),
            })

            bossWave.EdgeCommitStartedAt = now
            bossWave.EdgeCommitOrigin = Runtime.Root.Position
            bossWave.EdgeCommitTarget = plan.Position

            return true
        end
    end

    if not bossWave.EdgeCommitStartedAt
        or not bossWave.EdgeCommitOrigin
        or not bossWave.EdgeCommitTarget
        or horizontalDistance(
            bossWave.EdgeCommitTarget,
            plan.Position
        ) > 2.0
    then
        bossWave.EdgeCommitStartedAt = now
        bossWave.EdgeCommitOrigin = Runtime.Root.Position
        bossWave.EdgeCommitTarget = plan.Position

        logKV("OVERGROWTH_EDGE_COMMIT", {
            wave = bossWave.Id,
            distance = string.format(
                "%.2f",
                horizontalDistance(
                    Runtime.Root.Position,
                    plan.Position
                )
            ),
            inside = currentInside,
        })

        return true
    end

    local moved =
        horizontalDistance(
            Runtime.Root.Position,
            bossWave.EdgeCommitOrigin
        )

    local remaining =
        horizontalDistance(
            Runtime.Root.Position,
            plan.Position
        )

    if remaining <= 1.25
        or currentInside <= 0
    then
        bossWave.EdgeCommitStartedAt = now
        bossWave.EdgeCommitOrigin = Runtime.Root.Position
        bossWave.EdgeCommitTarget = plan.Position
        return true
    end

    if moved >= CFG.OVERGROWTH_EDGE_PROGRESS_MIN then
        bossWave.EdgeCommitStartedAt = now
        bossWave.EdgeCommitOrigin = Runtime.Root.Position
        bossWave.EdgeCommitTarget = plan.Position
        return true
    end

    if now - bossWave.EdgeCommitStartedAt
        < CFG.OVERGROWTH_EDGE_PROGRESS_TIMEOUT
    then
        return true
    end

    -- The requested escape exists but the character physically did not move.
    -- One short globally-governed shift is allowed as a rescue. Marking the
    -- wave Teleported also prevents a second sequence teleport in this attack.
    if CFG.OVERGROWTH_EDGE_RESCUE_ONCE
        and not bossWave.EdgeRescueUsed
        and not bossWave.Teleported
        and teleportBudgetAvailable(now)
    then
        local shifted, afterInside =
            doFastShift(
                plan,
                CFG.OVERGROWTH_EDGE_RESCUE_MAX,
                0,
                "OVERGROWTH_EDGE_RESCUE",
                false
            )

        if shifted then
            bossWave.EdgeRescueUsed = true
            bossWave.Teleported = true
            bossWave.TeleportCount =
                (bossWave.TeleportCount or 0) + 1
            bossWave.LastWaveTeleportAt = now
            bossWave.AfterTeleportInside = afterInside

            logKV("OVERGROWTH_EDGE_RESCUE_COMMIT", {
                wave = bossWave.Id,
                moved_before =
                    string.format("%.2f", moved),
                remaining_before =
                    string.format("%.2f", remaining),
                after_inside = afterInside,
            })

            bossWave.EdgeCommitStartedAt = now
            bossWave.EdgeCommitOrigin = Runtime.Root.Position
            bossWave.EdgeCommitTarget = plan.Position
            return true
        end
    end

    -- No shift available: immediately ask the general watchdog for a local
    -- open-space recovery instead of standing in the strip.
    dodgeMoveProgressWatch(
        plan,
        "OVERGROWTH_EDGE",
        bossWave.Id,
        currentInside
    )

    bossWave.EdgeCommitStartedAt = now
    bossWave.EdgeCommitOrigin = Runtime.Root.Position
    bossWave.EdgeCommitTarget = plan.Position

    return true
end

local function rescueOvergrowthLongLineIfInside(
    bossWave,
    plan,
    currentInside
)
    if not Runtime.Root
        or not bossWave
        or not plan
        or bossWave.Teleported
        or not teleportBudgetAvailable(os.clock())
    then
        return false
    end

    local _, actualInside, actualClearance =
        pointDanger(
            Runtime.Root.Position
        )

    local urgent =
        actualInside > 0
        or (
            actualClearance ~= math.huge
            and actualClearance
                < CFG.OVERGROWTH_LONGLINE_HOLD_CLEARANCE
        )

    if not urgent then
        return false
    end

    local shifted, afterInside =
        doFastShift(
            plan,
            CFG.OVERGROWTH_LONGLINE_RESCUE_MAX,
            0,
            "OVERGROWTH_LONGLINE_RESCUE",
            true
        )

    if shifted then
        local now = os.clock()

        bossWave.Teleported = true
        bossWave.TeleportCount =
            (bossWave.TeleportCount or 0) + 1
        bossWave.LastWaveTeleportAt = now
        bossWave.AfterTeleportInside = afterInside

        logKV("OVERGROWTH_LONGLINE_RESCUE_COMMIT", {
            wave = bossWave.Id,
            after_inside = afterInside,
            target_distance =
                string.format(
                    "%.2f",
                    horizontalDistance(
                        Runtime.Root.Position,
                        plan.Position
                    )
                ),
        })

        return true
    end

    return false
end


local function currentPositionThreatened()
    if not Runtime.Root then
        return false,0
    end

    local _,inside =
        pointDanger(Runtime.Root.Position)

    return inside > 0,inside
end

local function clearDodge(reason)
    if Runtime.DodgeActive then
        Runtime.DodgeActive = false
        Runtime.DodgePlan = nil
        Runtime.DodgeMoveWatch = nil
        Runtime.LastDodgeMoveLabel = nil
        Runtime.LastDodgeMoveTarget = nil

        logKV("DODGE_CLEAR", {
            elapsed = string.format(
                "%.3f",
                os.clock() - Runtime.DodgeStarted
            ),
            reason = reason or "safe",
        })
    end
end

local function dodgeThink()
    if not CFG.AUTO_DODGE
        or not Runtime.Root
        or Runtime.CompletionConfirmed
    then
        return false
    end

    local threats = activeThreats()
    local bossWave, bossThreats = updateBossWave(threats)
    local mageWave, mageThreats = updateMageWave(threats)

    local virtualCount = 0
    for _ in pairs(Runtime.VirtualThreats) do
        virtualCount += 1
    end

    local nearestPhysical, nearestPhysicalDist =
        nearestPhysicalEnemy(Runtime.Root.Position)

    local dynamicMeleeRadius = CFG.MELEE_SOFT_RADIUS
    local physicalClosing = 0
    local meleeTimeToContact = math.huge

    if nearestPhysical then
        dynamicMeleeRadius, physicalClosing, meleeTimeToContact =
            physicalClosingInfo(nearestPhysical, Runtime.Root.Position)
    end

    local physicalEmergency =
        physicalEmergencyState()

    local predicted =
        Runtime.Root.Position
        + horizontal(Runtime.Root.AssemblyLinearVelocity)
            * CFG.ABILITY_SAFE_PREDICT_TIME

    local currentPenalty, currentInside =
        pointDanger(Runtime.Root.Position)

    local predictedPenalty, predictedInside =
        pointDanger(predicted)

    -- ========================================================
    -- BOSS WAVE MODE
    -- ========================================================
    if bossWave then
        local now = os.clock()

        local shouldPlan = bossWave.Plan == nil
        local finalizePlan = false

        if bossWave.Plan then
            local _, planInside = pointDanger(bossWave.Plan.Position)

            if now < bossWave.CollectUntil then
                if now - bossWave.LastPlanAt >= CFG.BOSS_WAVE_REPLAN_INTERVAL then
                    shouldPlan = true
                end
            elseif not bossWave.Finalized then
                shouldPlan = true
                finalizePlan = true
            elseif planInside > 0
                and now - bossWave.LastPlanAt >= CFG.BOSS_WAVE_REPLAN_INTERVAL
            then
                shouldPlan = true
            end
        end

        if shouldPlan then
            bossWave.Plan = chooseBossWavePoint()
            bossWave.LastPlanAt = now

            if finalizePlan or now >= bossWave.CollectUntil then
                bossWave.Finalized = true
            end

            if bossWave.Plan then
                logKV("BOSS_WAVE_PLAN", {
                    id = bossWave.Id,
                    boss = bossWave.Boss,
                    radius = string.format("%.1f", bossWave.Plan.Radius),
                    clearance = string.format("%.1f", bossWave.Plan.Clearance),
                    inside = bossWave.Plan.Inside,
                    threats = #bossThreats,
                    finalized = tostring(bossWave.Finalized == true),
                })
            end
        end

        local plan = bossWave.Plan

        if bossWave.Boss == "Demonic Overgrowth" then
            if bossThreatHas(
                "overgrowthLongLineSpikes",
                bossThreats
            ) then
                local longLinePlan =
                    overgrowthLongLinePocketCandidate(
                        bossWave,
                        bossThreats
                    )

                if longLinePlan then
                    plan = longLinePlan
                    bossWave.Plan = longLinePlan
                    bossWave.Finalized = true
                end
            else
                local edgeFollowPlan =
                    Runtime.OvergrowthEdgeFollowCandidate
                    and Runtime.OvergrowthEdgeFollowCandidate(
                        bossWave
                    )

                local sequencePlan

                if not edgeFollowPlan then
                    sequencePlan =
                        overgrowthSequenceEscapeCandidate(
                            bossWave
                        )
                end

                if edgeFollowPlan then
                    plan = edgeFollowPlan
                    bossWave.Plan = edgeFollowPlan

                    if now - Runtime.LastOvergrowthEdgeFollowLog
                        >= CFG.OVERGROWTH_EDGE_FOLLOW_LOG_COOLDOWN
                    then
                        Runtime.LastOvergrowthEdgeFollowLog = now

                        logKV("OVERGROWTH_EDGE_FOLLOW", {
                            wave = bossWave.Id,
                            step =
                                string.format(
                                    "%.1f",
                                    edgeFollowPlan.Radius
                                ),
                            remaining =
                                string.format(
                                    "%.2f",
                                    math.max(
                                        0,
                                        (
                                            bossWave.EdgeFollowUntil
                                            or now
                                        ) - now
                                    )
                                ),
                        })
                    end

                elseif sequencePlan then
                    plan = sequencePlan
                    bossWave.Plan = sequencePlan
                    bossWave.Finalized = true
                elseif bossThreatHas(
                    "spikePrecast",
                    bossThreats
                ) then
                    local edgePlan =
                        overgrowthFirstEdgeCandidate(
                            bossWave,
                            bossThreats
                        )

                    if edgePlan then
                        plan = edgePlan
                        bossWave.Plan = edgePlan

                        if now - Runtime.LastOvergrowthEdgeLog
                            >= CFG.OVERGROWTH_EDGE_LOG_COOLDOWN
                        then
                            Runtime.LastOvergrowthEdgeLog = now

                            logKV("OVERGROWTH_EDGE_PLAN", {
                                wave = bossWave.Id,
                                distance =
                                    string.format(
                                        "%.2f",
                                        edgePlan.Radius
                                    ),
                                clearance =
                                    edgePlan.Clearance == math.huge
                                    and "inf"
                                    or string.format(
                                        "%.2f",
                                        edgePlan.Clearance or 0
                                    ),
                            })
                        end
                    end
                end
            end
        end

        if bossWave.Boss == "Kolvumar" then
            local spitPlan =
                kolvumarSpitEmergencyCandidate(
                    bossWave,
                    bossThreats
                )

            if spitPlan then
                plan = spitPlan
                bossWave.Plan = spitPlan
                bossWave.Finalized = true
            end
        end

        local azrallikHorizontalBeamActive =
            bossWave.Boss == "Demon Lord Azrallik"
            and bossThreatHas(
                "horizontalBeam",
                bossThreats
            )

        local azrallikFingerActive =
            bossWave.Boss == "Demon Lord Azrallik"
            and bossThreatHas(
                "fingerBlastHit",
                bossThreats
            )

        local azrallikFingerTellActive =
            bossWave.Boss == "Demon Lord Azrallik"
            and Runtime.AzrallikFingerTellOrigin ~= nil
            and os.clock() - Runtime.AzrallikFingerTellAt
                <= CFG.AZRALLIK_FINGER_TELL_WINDOW

        local azrallikSpreadActive =
            bossWave.Boss == "Demon Lord Azrallik"
            and bossThreatHas(
                "azrallikPunchSpread",
                bossThreats
            )

        local azrallikSpreadTellActive =
            bossWave.Boss == "Demon Lord Azrallik"
            and Runtime.AzrallikSpreadTellOrigin ~= nil
            and os.clock() - Runtime.AzrallikSpreadTellAt
                <= CFG.AZRALLIK_SPREAD_TELL_WINDOW
            and os.clock() - Runtime.AzrallikSpreadTellAt
                >= CFG.AZRALLIK_SPREAD_PREMOVE_START

        if azrallikFingerActive
            and azrallikSpreadActive
            and CFG.AZRALLIK_COMBINED_FINGER_SPREAD_ENABLED
        then
            -- Finger can spawn while the 8-way PunchSpread is still live.
            -- The old finger escape was endpoint-safe but could WALK THROUGH a
            -- spread lane. Reuse the local spread solver first because its
            -- point/route checks include the finger geometry too.
            local combinedPlan =
                Runtime.AzrallikSpreadActiveCandidate
                and Runtime.AzrallikSpreadActiveCandidate(
                    bossWave,
                    bossThreats
                )

            if combinedPlan then
                plan = combinedPlan
                bossWave.Plan = combinedPlan
                bossWave.Finalized = true

                local combinedNow = os.clock()

                if combinedNow - Runtime.LastAzrallikCombinedLog
                    >= CFG.AZRALLIK_COMBINED_LOG_COOLDOWN
                then
                    Runtime.LastAzrallikCombinedLog =
                        combinedNow

                    logKV("AZRALLIK_COMBINED_ESCAPE", {
                        planner =
                            tostring(
                                combinedPlan.Label
                            ),
                        radius =
                            string.format(
                                "%.1f",
                                combinedPlan.Radius or 0
                            ),
                        clearance =
                            combinedPlan.Clearance == math.huge
                            and "inf"
                            or string.format(
                                "%.1f",
                                combinedPlan.Clearance or 0
                            ),
                    })
                end
            end

        elseif azrallikFingerActive then
            local fingerPlan =
                azrallikFingerBlastCandidate(
                    bossWave,
                    bossThreats
                )

            if fingerPlan then
                plan = fingerPlan
                bossWave.Plan = fingerPlan
                bossWave.Finalized = true
            end

        elseif azrallikHorizontalBeamActive then
            local sweepPlan =
                horizontalSweepEscapeCandidate(
                    bossWave,
                    bossThreats
                )

            if not sweepPlan then
                sweepPlan =
                    azrallikEarlyBeamCandidate(
                        bossWave,
                        bossThreats
                    )
            end

            if sweepPlan then
                plan = sweepPlan
                bossWave.Plan = sweepPlan
                bossWave.Finalized = true
            end

        elseif azrallikSpreadActive then
            local spreadPlan =
                Runtime.AzrallikSpreadActiveCandidate
                and Runtime.AzrallikSpreadActiveCandidate(
                    bossWave,
                    bossThreats
                )

            if spreadPlan then
                plan = spreadPlan
                bossWave.Plan = spreadPlan
                bossWave.Finalized = true
            end

        elseif azrallikFingerTellActive then
            local prePlan =
                Runtime.AzrallikFingerTellCandidate
                and Runtime.AzrallikFingerTellCandidate()

            if prePlan then
                plan = prePlan
                bossWave.Plan = prePlan
                bossWave.Finalized = true
            end

        elseif azrallikSpreadTellActive then
            local spreadPrePlan =
                Runtime.AzrallikSpreadTellCandidate
                and Runtime.AzrallikSpreadTellCandidate(
                    bossWave,
                    bossThreats
                )

            if spreadPrePlan then
                plan = spreadPrePlan
                bossWave.Plan = spreadPrePlan

                local now = os.clock()

                if now - Runtime.LastAzrallikSpreadMoveLog
                    >= CFG.AZRALLIK_SPREAD_LOG_COOLDOWN
                then
                    Runtime.LastAzrallikSpreadMoveLog = now

                    logKV("AZRALLIK_SPREAD_PREMOVE", {
                        elapsed =
                            string.format(
                                "%.2f",
                                now - Runtime.AzrallikSpreadTellAt
                            ),
                        distance =
                            string.format(
                                "%.1f",
                                horizontalDistance(
                                    Runtime.Root.Position,
                                    Runtime.ActiveBossRoot.Position
                                )
                            ),
                        step =
                            string.format(
                                "%.1f",
                                spreadPrePlan.Radius or 0
                            ),
                    })
                end
            end

        elseif bossWave.Boss == "Demon Lord Azrallik" then
            local pressurePlan =
                azrallikSafePressureCandidate(
                    bossWave,
                    bossThreats
                )

            if pressurePlan then
                plan = pressurePlan
                bossWave.Plan = pressurePlan
            end
        end

        if bossWave.Boss == "Demonic Overgrowth" then
            plan =
                guardOvergrowthForwardPlan(
                    plan,
                    bossWave
                )

            bossWave.Plan = plan
        end

        if plan then
            Runtime.WallEscapePosition = nil

            if not Runtime.DodgeActive then
                Runtime.DodgeActive = true
                Runtime.DodgeStarted = now
                Runtime.DodgeCount += 1

                logKV("DODGE_START", {
                    count = Runtime.DodgeCount,
                    current_inside = currentInside,
                    predicted_inside = predictedInside,
                    target_radius = string.format("%.1f", plan.Radius),
                    clearance = string.format("%.1f", plan.Clearance or 0),
                    planner = "boss_wave_gap",
                    wave = bossWave.Id,
                    boss = bossWave.Boss,
                })
            end

            local bossMoveReason = "BOSS_WAVE"

            if plan.Label == "kolvumar_spit_emergency" then
                bossMoveReason = "KOLVUMAR_SPIT_ESCAPE"

            elseif plan.Label == "kolvumar_spit_hold" then
                bossMoveReason = "KOLVUMAR_SPIT_HOLD"

            elseif plan.Label == "kolvumar_spit_slide" then
                bossMoveReason = "KOLVUMAR_SPIT_SLIDE"

            elseif plan.Label == "kolvumar_spit_cooldown_slide" then
                bossMoveReason = "KOLVUMAR_SPIT_COOLDOWN_SLIDE"

            elseif plan.Label == "kolvumar_spit_recovery_commit" then
                bossMoveReason = "KOLVUMAR_SPIT_RECOVERY"

            elseif plan.Label == "azrallik_finger_escape"
                or plan.Label == "azrallik_finger_hold"
            then
                bossMoveReason = "AZRALLIK_FINGER"

            elseif plan.Label == "azrallik_finger_premove"
                or plan.Label == "azrallik_finger_premove_hold"
            then
                bossMoveReason = "AZRALLIK_FINGER_PREMOVE"

            elseif plan.Label == "azrallik_beam_pocket" then
                bossMoveReason = "AZRALLIK_BEAM_POCKET"
            elseif plan.Label == "azrallik_beam_early_edge"
                or plan.Label == "azrallik_beam_early_hold"
            then
                bossMoveReason = "AZRALLIK_BEAM_EARLY"
            elseif plan.Label == "azrallik_safe_pressure" then
                bossMoveReason = "AZRALLIK_SAFE_PRESSURE"

            elseif plan.Label == "azrallik_spread_premove" then
                bossMoveReason = "AZRALLIK_SPREAD_PREMOVE"

            elseif plan.Label == "azrallik_spread_hold" then
                bossMoveReason = "AZRALLIK_SPREAD_HOLD"

            elseif plan.Label == "azrallik_spread_local_gap" then
                bossMoveReason = "AZRALLIK_SPREAD_LOCAL_GAP"
            elseif plan.Label == "azrallik_sweep_gap" then
                bossMoveReason = "AZRALLIK_SWEEP_GAP"
            elseif plan.Label == "overgrowth_sequence_forward" then
                bossMoveReason = "OVERGROWTH_FORWARD"
            elseif plan.Label == "overgrowth_edge_follow" then
                bossMoveReason = "OVERGROWTH_EDGE_FOLLOW"
            elseif plan.Label == "overgrowth_first_edge" then
                bossMoveReason = "OVERGROWTH_EDGE"
            elseif plan.Label == "overgrowth_longline_pocket" then
                bossMoveReason = "OVERGROWTH_LONGLINE_POCKET"
            end

            if plan.Label == "kolvumar_spit_hold" then
                holdKolvumarSpitPocket(
                    bossWave,
                    plan
                )

            elseif plan.Label == "azrallik_finger_premove_hold" then
                pcall(function()
                    Runtime.Humanoid:MoveTo(
                        Runtime.Root.Position
                    )
                end)

                Runtime.MovementOwner =
                    "AZRALLIK_FINGER_PREHOLD"

            elseif plan.Label == "azrallik_finger_hold" then
                pcall(function()
                    Runtime.Humanoid:MoveTo(
                        Runtime.Root.Position
                    )
                    Runtime.Humanoid:Move(
                        Vector3.zero,
                        false
                    )
                end)

                Runtime.MovementOwner =
                    "AZRALLIK_FINGER_HOLD"

            elseif plan.Label == "azrallik_beam_pocket" then
                holdAzrallikBeamPocket(
                    bossWave,
                    plan
                )

            elseif plan.Label == "overgrowth_first_edge" then
                commitOvergrowthFirstEdge(
                    bossWave,
                    plan,
                    currentInside
                )

            else
                moveTo(
                    plan.Position,
                    bossMoveReason
                )

                if plan.Label == "overgrowth_longline_pocket" then
                    rescueOvergrowthLongLineIfInside(
                        bossWave,
                        plan,
                        currentInside
                    )
                end

                dodgeMoveProgressWatch(
                    plan,
                    bossMoveReason,
                    bossWave.Id,
                    currentInside
                )
            end

            local eta =
                CFG.BOSS_ATTACK_ETA[bossWave.Boss]
                or 0.80

            local impactAt = bossWave.Started + eta
            local walkEnough = walkingLikelyEnough(plan, impactAt)

            local teleportMax = CFG.TELEPORT_BOSS_WAVE_MAX

            if bossWave.Boss == "Demonic Overgrowth" then
                teleportMax = CFG.OVERGROWTH_WAVE_TELEPORT_MAX
            elseif bossWave.Boss == "Demon Lord Azrallik" then
                teleportMax = CFG.AZRALLIK_WAVE_TELEPORT_MAX
            end

            local sweepEmergency =
                plan.Label == "azrallik_sweep_gap"
                and plan.TimeToContact <= CFG.AZRALLIK_SWEEP_IMPACT_WINDOW

            local overgrowthSequenceEmergency =
                plan.Label == "overgrowth_sequence_forward"
                and plan.TimeToContact <= CFG.OVERGROWTH_SEQUENCE_IMPACT_WINDOW

            local kolvumarSpitEmergency =
                plan.Label == "kolvumar_spit_emergency"

            local kolvumarHpRatio =
                Runtime.Humanoid
                and Runtime.Humanoid.MaxHealth > 0
                and (
                    Runtime.Humanoid.Health
                    / Runtime.Humanoid.MaxHealth
                )
                or 1

            -- Recount spit overlap RIGHT NOW. The escape plan can be a few
            -- frames old; V10.1 proved a second puddle may appear after the
            -- plan was created, producing current_inside=2 but stacked=1.
            local kolvumarLiveInside =
                plan.InsideSpits
                or 0

            if kolvumarSpitEmergency
                and Runtime.Root
            then
                local liveSpitThreats =
                    kolvumarSpitThreats(
                        bossThreats
                    )

                kolvumarLiveInside =
                    kolvumarSpitInsideCount(
                        Runtime.Root.Position,
                        liveSpitThreats
                    )

                plan.InsideSpits =
                    kolvumarLiveInside
            end

            local kolvumarSpitShiftEmergency =
                kolvumarSpitEmergency
                and (
                    Runtime.FragileMode
                    or kolvumarHpRatio
                        <= CFG.KOLVUMAR_SPIT_SHIFT_HP_RATIO
                    or kolvumarLiveInside
                        >= CFG.KOLVUMAR_SPIT_SHIFT_MIN_STACK
                )

            local overgrowthNarrowSpikeActive =
                bossWave.Boss == "Demonic Overgrowth"
                and bossThreatHas(
                    "spikePrecast",
                    bossThreats
                )
                and not bossThreatHas(
                    "overgrowthLongLineSpikes",
                    bossThreats
                )

            -- Moving-front teleports are proactive. Generic boss teleports
            -- remain reactive.
            local shouldTeleport =
                (
                    currentInside > 0
                    and predictedInside > 0
                    and now >= bossWave.Started + CFG.BOSS_WAVE_WALK_GRACE
                    and not walkEnough
                )
                or sweepEmergency
                or overgrowthSequenceEmergency
                or kolvumarSpitShiftEmergency

            if bossWave.Boss == "Demonic Overgrowth"
                and plan.Label
                    ~= "overgrowth_sequence_forward"
                and now - bossWave.Started
                    < CFG.OVERGROWTH_FIRST_COMMIT_DELAY
            then
                shouldTeleport = false
            end

            -- Stronger V7.9 rule:
            -- During the narrow moving spike sequence, NEVER use the generic
            -- boss-wave teleport. Wait for direction lock, then allow at most
            -- one forward-sequence shift for the whole wave.
            if overgrowthNarrowSpikeActive
                and plan.Label
                    ~= "overgrowth_sequence_forward"
            then
                shouldTeleport = false
            end

            if CFG.AZRALLIK_BEAM_NO_TELEPORT
                and azrallikHorizontalBeamActive
            then
                shouldTeleport = false
            end

            if bossWave.Boss == "Kolvumar" then
                if plan.Label ~= "kolvumar_spit_emergency" then
                    shouldTeleport = CFG.KOLVUMAR_GENERIC_WAVE_SHIFT
                elseif not kolvumarSpitShiftEmergency then
                    shouldTeleport = false

                    if now - Runtime.LastKolvumarWalkOnlyLog
                        >= CFG.KOLVUMAR_SPIT_LOG_COOLDOWN
                    then
                        Runtime.LastKolvumarWalkOnlyLog = now

                        logKV("KOLVUMAR_SPIT_WALK_ESCAPE", {
                            hp_ratio =
                                string.format("%.2f", kolvumarHpRatio),
                            stacked =
                                tostring(kolvumarLiveInside),
                            distance =
                                string.format("%.1f", plan.Radius or 0),
                        })
                    end
                end
            end

            if plan.Label == "azrallik_safe_pressure"
                or plan.Label == "azrallik_spread_premove"
                or plan.Label == "azrallik_spread_hold"
                or plan.Label == "azrallik_spread_local_gap"
                or plan.Label == "azrallik_finger_hold"
                or plan.Label == "azrallik_finger_premove"
                or plan.Label == "azrallik_finger_premove_hold"
                or plan.Label == "kolvumar_spit_hold"
                or plan.Label == "kolvumar_spit_slide"
                or plan.Label == "kolvumar_spit_cooldown_slide"
                or plan.Label == "kolvumar_spit_recovery_commit"
                or plan.Label == "overgrowth_edge_follow"
            then
                shouldTeleport = false
            end

            if plan.Label == "overgrowth_longline_pocket"
                and plan.Radius
                    <= CFG.OVERGROWTH_LONGLINE_WALK_ONLY_DISTANCE
            then
                shouldTeleport = false
            end

            local teleportAllowed =
                (not CFG.TELEPORT_BOSS_WAVE_ONCE or not bossWave.Teleported)

            if plan.Label == "kolvumar_spit_emergency" then
                -- Per-spit exception to boss-wave-once. The GLOBAL 3-second
                -- governor still applies and prevents chaining.
                teleportAllowed = true

            elseif plan.Label == "overgrowth_sequence_forward" then
                teleportAllowed =
                    not bossWave.Teleported
                    and not bossWave.SequenceCommitted
                    and (bossWave.TeleportCount or 0)
                        < CFG.OVERGROWTH_SEQUENCE_MAX_TELEPORTS
                    and now - (bossWave.LastWaveTeleportAt or -math.huge)
                        >= CFG.OVERGROWTH_SEQUENCE_TELEPORT_GAP
            end

            local teleportBudgetOkay =
                teleportBudgetAvailable(now)

            if shouldTeleport
                and teleportAllowed
                and not teleportBudgetOkay
            then
                logTeleportBlocked(
                    plan.Label
                        or bossWave.Boss,
                    now
                )
            end

            if shouldTeleport
                and teleportAllowed
                and teleportBudgetOkay
            then
                local tag = "BOSS_WAVE_TELEPORT"
                local maxShift = teleportMax

                if plan.Label == "kolvumar_spit_emergency" then
                    tag = "KOLVUMAR_SPIT_RESCUE"
                    maxShift = CFG.KOLVUMAR_SPIT_RESCUE_MAX

                elseif plan.Label == "azrallik_sweep_gap" then
                    tag = "AZRALLIK_SWEEP_TELEPORT"
                    maxShift = CFG.AZRALLIK_SWEEP_TELEPORT_MAX
                elseif plan.Label == "overgrowth_sequence_forward" then
                    tag = "OVERGROWTH_SEQUENCE_TELEPORT"
                    maxShift = CFG.OVERGROWTH_WAVE_TELEPORT_MAX
                end

                local didShift, afterInside =
                    doFastShift(
                        plan,
                        maxShift,
                        CFG.TELEPORT_GLOBAL_COOLDOWN,
                        tag,
                        true
                    )

                if didShift then
                    if plan.Label == "kolvumar_spit_emergency" then
                        bossWave.KolvumarPocket =
                            Runtime.Root.Position
                        bossWave.KolvumarPocketUntil =
                            now
                            + CFG.KOLVUMAR_SPIT_POST_ESCAPE_HOLD
                        bossWave.KolvumarPostRescueUntil =
                            now
                            + CFG.KOLVUMAR_POST_RESCUE_MOTION_TIME
                        bossWave.KolvumarPocketReached =
                            false
                    end

                    bossWave.Teleported = true
                    bossWave.TeleportCount =
                        (bossWave.TeleportCount or 0) + 1
                    bossWave.LastWaveTeleportAt = now
                    bossWave.AfterTeleportInside = afterInside

                    if plan.Label
                        == "overgrowth_sequence_forward"
                    then
                        bossWave.SequenceCommitted = true
                        bossWave.SequenceCommitPosition =
                            Runtime.Root.Position
                        bossWave.SequenceCommitUntil =
                            now
                            + CFG.OVERGROWTH_POST_SHIFT_HOLD

                        local projection =
                            horizontal(
                                Runtime.Root.Position
                                - bossWave.SequenceOrigin
                            ):Dot(
                                bossWave.SequenceDir
                            )

                        bossWave.SequenceMaxProjection =
                            math.max(
                                bossWave.SequenceMaxProjection
                                    or -math.huge,
                                projection
                            )

                        logKV("OVERGROWTH_COMMIT", {
                            wave = bossWave.Id,
                            position =
                                vec(Runtime.Root.Position),
                            projection =
                                string.format(
                                    "%.2f",
                                    projection
                                ),
                            hold =
                                string.format(
                                    "%.2f",
                                    CFG.OVERGROWTH_POST_SHIFT_HOLD
                                ),
                        })
                    end
                end
            end

            return true
        end
    end

    -- ========================================================
    -- NORMAL MAGE MINI-WAVE MODE
    -- ========================================================
    if mageWave then
        local now = os.clock()

        local magePressureActive =
            Runtime.MageFreePressureActive
            and Runtime.MageFreePressureActive()

        -- V9.9:
        -- mage-wave objects can exist while we are already perfectly safe.
        -- Do NOT enter dodge mode in that case. Release movement back to
        -- ordinary combat so the mage keeps getting attacked.
        if CFG.MAGE_SAFE_WINDOW_ATTACK
            and magePressureActive
            and currentInside == 0
            and predictedInside
                <= CFG.MAGE_SAFE_WINDOW_MAX_PREDICTED_INSIDE
        then
            if Runtime.DodgeActive then
                clearDodge(
                    "mage_safe_attack_window"
                )
            end

            if now - Runtime.LastMageSafeWindowLog
                >= CFG.MAGE_SAFE_WINDOW_LOG_COOLDOWN
            then
                Runtime.LastMageSafeWindowLog =
                    now

                logKV("MAGE_ATTACK_WINDOW", {
                    target =
                        Runtime.Target
                        and Runtime.Target.Name
                        or "none",
                    distance =
                        Runtime.TargetRoot
                        and string.format(
                            "%.1f",
                            horizontalDistance(
                                Runtime.Root.Position,
                                Runtime.TargetRoot.Position
                            )
                        )
                        or "inf",
                    threats = #mageThreats,
                })
            end

            return false
        end

        local shouldPlan = mageWave.Plan == nil
        local finalizePlan = false

        if mageWave.Plan then
            local _, planInside = pointDanger(mageWave.Plan.Position)

            if now < mageWave.CollectUntil then
                if now - mageWave.LastPlanAt >= CFG.MAGE_WAVE_REPLAN_INTERVAL then
                    shouldPlan = true
                end
            elseif not mageWave.Finalized then
                shouldPlan = true
                finalizePlan = true
            elseif planInside > 0
                and now - mageWave.LastPlanAt >= CFG.MAGE_WAVE_REPLAN_INTERVAL
            then
                shouldPlan = true
            end
        end

        if shouldPlan then
            mageWave.Plan = chooseMageWavePoint()
            mageWave.LastPlanAt = now

            if finalizePlan or now >= mageWave.CollectUntil then
                mageWave.Finalized = true
            end

            if mageWave.Plan then
                logKV("MAGE_WAVE_PLAN", {
                    id = mageWave.Id,
                    radius = string.format("%.1f", mageWave.Plan.Radius),
                    clearance = string.format("%.1f", mageWave.Plan.Clearance),
                    inside = mageWave.Plan.Inside,
                    threats = #mageThreats,
                    finalized = tostring(mageWave.Finalized == true),
                })
            end
        end

        local plan = mageWave.Plan

        local closePhysical, closePhysicalDist =
            nearestPhysicalEnemy(Runtime.Root.Position)

        if closePhysical
            and closePhysicalDist <= CFG.WAVE_PHYSICAL_HARD_RADIUS
            and now - mageWave.LastPlanAt >= 0.10
        then
            local merged = chooseMageWavePoint()

            if merged then
                plan = merged
                mageWave.Plan = merged
                mageWave.LastPlanAt = now
            end
        end

        if plan then
            Runtime.WallEscapePosition = nil

            if not Runtime.DodgeActive then
                Runtime.DodgeActive = true
                Runtime.DodgeStarted = now
                Runtime.DodgeCount += 1

                logKV("DODGE_START", {
                    count = Runtime.DodgeCount,
                    current_inside = currentInside,
                    predicted_inside = predictedInside,
                    target_radius = string.format("%.1f", plan.Radius),
                    clearance = string.format("%.1f", plan.Clearance or 0),
                    planner = "mage_wave_gap",
                    wave = mageWave.Id,
                })
            end

            moveTo(plan.Position, "MAGE_WAVE")

            dodgeMoveProgressWatch(
                plan,
                "MAGE_WAVE",
                mageWave.Id,
                currentInside
            )

            local impactAt =
                mageWave.Started + CFG.MAGE_ATTACK_ETA

            local walkEnough =
                walkingLikelyEnough(plan, impactAt)

            if currentInside > 0
                and predictedInside > 0
                and now >= mageWave.Started + CFG.MAGE_WAVE_WALK_GRACE
                and not mageWave.Teleported
                and not walkEnough
                and teleportBudgetAvailable(now)
            then
                local shifted =
                    doFastShift(
                        plan,
                        CFG.MAGE_WAVE_TELEPORT_MAX,
                        CFG.TELEPORT_GLOBAL_COOLDOWN,
                        "MAGE_WAVE_TELEPORT",
                        true
                    )

                if shifted then
                    mageWave.Teleported = true
                end
            end

            return true
        end
    end

    -- ========================================================
    -- ORDINARY COMBAT MODE
    -- ========================================================

    -- Ordinary fast physical pressure does not need to seize the full dodge
    -- state. Hand it back to PhysicalPressureMove unless contact is truly
    -- imminent; this keeps attack/combat movement running continuously.
    if CFG.PHYSICAL_DODGE_HANDOFF_ENABLED
        and physicalEmergency
        and #threats == 0
        and virtualCount == 0
    then
        local truePanic =
            physicalEmergency.Distance
                <= CFG.PHYSICAL_DODGE_PANIC_RADIUS
            or (
                physicalEmergency.Distance
                    <= CFG.PHYSICAL_DODGE_PANIC_NEAR_RADIUS
                and physicalEmergency.Closing
                    >= CFG.PHYSICAL_DODGE_PANIC_MIN_CLOSING
            )
            or (
                physicalEmergency.Closing > 0
                and physicalEmergency.TimeToContact
                    <= CFG.PHYSICAL_DODGE_PANIC_TTC
            )

        if not truePanic then
            clearDodge(
                "physical_pressure_handoff"
            )

            local now = os.clock()

            if now - Runtime.LastPhysicalHandoffLog
                >= CFG.PHYSICAL_DODGE_HANDOFF_LOG_COOLDOWN
            then
                Runtime.LastPhysicalHandoffLog =
                    now

                logKV("PHYSICAL_HANDOFF", {
                    enemy =
                        physicalEmergency.Enemy.Model.Name,
                    distance =
                        string.format(
                            "%.1f",
                            physicalEmergency.Distance
                        ),
                    closing =
                        string.format(
                            "%.1f",
                            physicalEmergency.Closing
                        ),
                    ttc =
                        physicalEmergency.TimeToContact
                            < math.huge
                        and string.format(
                            "%.2f",
                            physicalEmergency.TimeToContact
                        )
                        or "inf",
                })
            end

            return false
        end
    end

    if #threats == 0
        and virtualCount == 0
        and not physicalEmergency
    then
        clearDodge("no_threat")
        return false
    end

    local needsDodge =
        currentInside > 0
        or predictedInside > 0
        or predictedPenalty > 1500
        or physicalEmergency ~= nil

    if not needsDodge then
        clearDodge("outside_geometry")
        return false
    end

    -- Single thin line: start walking immediately. Teleport only if we are
    -- STILL inside after a brief walk grace and the global budget allows it.
    if CFG.LARGE_LINE_FAST_SHIFT
        and currentInside > 0
        and teleportBudgetAvailable(os.clock())
    then
        local linePlan =
            lineEmergencyCandidate(
                Runtime.Root.Position,
                threats
            )

        if linePlan then
            local age =
                linePlan.ThreatCreated
                and (os.clock() - linePlan.ThreatCreated)
                or math.huge

            if age >= CFG.LINE_WALK_GRACE then
                local impactAt =
                    (linePlan.ThreatCreated or os.clock())
                    + CFG.MAGE_ATTACK_ETA

                if not walkingLikelyEnough(linePlan, impactAt) then
                    if doFastShift(
                        linePlan,
                        CFG.LARGE_LINE_FAST_SHIFT_MAX,
                        CFG.LARGE_LINE_FAST_SHIFT_COOLDOWN,
                        "LINE_FAST_SHIFT",
                        false
                    ) then
                        Runtime.DodgePlan = nil
                        Runtime.LastDodgePlanAt = -math.huge
                    end
                end
            end
        end
    end

    local now = os.clock()
    local plan = Runtime.DodgePlan

    if physicalEmergency
        and #threats == 0
        and virtualCount == 0
    then
        plan = physicalEmergencyCandidate(physicalEmergency)
        Runtime.DodgePlan = plan
        Runtime.LastDodgePlanAt = now
    end

    local planUnsafe = false

    if plan then
        local _, insideAtPlan = pointDanger(plan.Position)
        planUnsafe = insideAtPlan > 0
    end

    if (not plan
        or planUnsafe
        or now - Runtime.LastDodgePlanAt >= CFG.DODGE_REPLAN_INTERVAL)
        and not (
            physicalEmergency
            and #threats == 0
            and virtualCount == 0
        )
    then
        plan = chooseDodgePoint()
        Runtime.DodgePlan = plan
        Runtime.LastDodgePlanAt = now
    end

    if not plan then
        return false
    end

    if not Runtime.DodgeActive then
        Runtime.DodgeActive = true
        Runtime.DodgeStarted = now
        Runtime.DodgeCount += 1

        logKV("DODGE_START", {
            count = Runtime.DodgeCount,
            current_inside = currentInside,
            predicted_inside = predictedInside,
            target_radius = string.format("%.1f", plan.Radius),
            clearance = string.format("%.1f", plan.Clearance or 0),
            planner = tostring(plan.Label),
            melee_dist = nearestPhysical
                and string.format("%.1f", nearestPhysicalDist)
                or "none",
            melee_closing = nearestPhysical
                and string.format("%.1f", physicalClosing)
                or "0",
        })
    end

    moveTo(plan.Position, "DODGE")

    -- V7: emergency translation is ONLY for true critical contact.
    -- Normal physical proximity is handled by PHYSICAL_PRESSURE movement.
    if physicalEmergency
        and teleportBudgetAvailable(now)
    then
        local emergencyPlan =
            physicalEmergencyCandidate(physicalEmergency)

        if emergencyPlan then
            local didShift =
                doFastShift(
                    emergencyPlan,
                    CFG.MELEE_FAST_SHIFT_MAX,
                    CFG.MELEE_FAST_SHIFT_COOLDOWN,
                    "MELEE_FAST_SHIFT",
                    false
                )

            if didShift then
                Runtime.LastMeleeFastShift = now

                logKV("MELEE_EMERGENCY", {
                    enemy = physicalEmergency.Enemy.Model.Name,
                    distance = string.format("%.2f", physicalEmergency.Distance),
                    closing = string.format("%.2f", physicalEmergency.Closing),
                    time_to_contact = physicalEmergency.TimeToContact < math.huge
                        and string.format("%.3f", physicalEmergency.TimeToContact)
                        or "inf",
                    planner = "physical_emergency",
                })
            end
        end
    end

    -- General micro teleport remains the last fallback.
    if currentInside > 0
        and teleportBudgetAvailable(now)
    then
        local oldestAge = 0

        for _, meta in ipairs(threats) do
            if pointInsideThreat(meta, Runtime.Root.Position) then
                oldestAge =
                    math.max(
                        oldestAge,
                        os.clock() - meta.Created
                    )
            end
        end

        if oldestAge >= CFG.MICRO_TELEPORT_MIN_THREAT_AGE
            and plan.Radius <= CFG.MICRO_TELEPORT_MAX + 1.0
        then
            doMicroTeleport(plan)
        end
    end

    return true
end



Runtime.PhysicalLeashDestination = function(
    enemy,
    startRadius,
    needed
)
    if not CFG.PHYSICAL_TARGET_LEASH_ENABLED
        or not Runtime.Root
        or not Runtime.Target
        or not Runtime.TargetRoot
        or Runtime.Target == enemy.Model
        or isPhysicalEnemyModel(
            Runtime.Target
        )
    then
        return nil
    end

    local targetName =
        Runtime.Target.Name or ""

    local isHeart =
        targetName == "Azrallik's Heart"

    local isBoss =
        Runtime.ActiveBossModel
        and Runtime.Target
            == Runtime.ActiveBossModel

    local isMage =
        string.find(
            string.lower(targetName),
            "mage",
            1,
            true
        ) ~= nil

    if not isHeart
        and not isBoss
        and not isMage
    then
        return nil
    end

    local maxLeash =
        isHeart
        and CFG.PHYSICAL_TARGET_LEASH_HEART_MAX
        or (
            isBoss
            and CFG.PHYSICAL_TARGET_LEASH_BOSS_MAX
            or CFG.PHYSICAL_TARGET_LEASH_MAGE_MAX
        )

    local origin =
        Runtime.Root.Position

    local targetPos =
        Runtime.TargetRoot.Position

    local currentTargetDistance =
        horizontalDistance(
            origin,
            targetPos
        )

    local desiredRange =
        desiredRangeForTarget()

    local away =
        unitHorizontal(
            origin - enemy.Root.Position
        )

    local toward =
        unitHorizontal(
            targetPos - origin
        )

    local baseAngle =
        math.atan2(
            away.Z,
            away.X
        )

    local best
    local bestScore =
        math.huge

    for _, radius in ipairs({
        needed,
        needed
            + CFG.PHYSICAL_TARGET_LEASH_EXTRA_STEP,
    }) do
        for i = 0,
            CFG.PHYSICAL_TARGET_LEASH_SAMPLES - 1
        do
            local angle =
                baseAngle
                + math.pi * 2
                    * (
                        i
                        / CFG.PHYSICAL_TARGET_LEASH_SAMPLES
                    )

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate =
                origin + dir * radius

            if hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside =
                    pointDanger(candidate)

                if inside == 0 then
                    local physicalDistance =
                        horizontalDistance(
                            candidate,
                            enemy.Root.Position
                        )

                    local targetDistance =
                        horizontalDistance(
                            candidate,
                            targetPos
                        )

                    local separationPenalty =
                        math.max(
                            startRadius + 2
                                - physicalDistance,
                            0
                        ) * 1800

                    local targetPenalty =
                        math.abs(
                            targetDistance
                            - desiredRange
                        ) * (
                            isHeart
                            and 260
                            or (
                                isBoss
                                and 190
                                or 120
                            )
                        )

                    local progressPenalty = 0

                    -- If pressure has already pushed us beyond the offensive
                    -- leash, reject any local dodge that keeps running farther
                    -- away from the objective.
                    if currentTargetDistance
                        > maxLeash
                        and targetDistance
                            >= currentTargetDistance - 0.5
                    then
                        progressPenalty += 24000
                    end

                    if targetDistance > maxLeash then
                        progressPenalty +=
                            (
                                targetDistance
                                - maxLeash
                            ) * 350
                    end

                    local progress =
                        toward:Dot(
                            unitHorizontal(
                                candidate - origin
                            )
                        )

                    local score =
                        danger
                        + separationPenalty
                        + targetPenalty
                        + progressPenalty
                        - progress * (
                            currentTargetDistance
                                > maxLeash
                                and 1800
                                or 250
                        )

                    if score < bestScore then
                        bestScore = score
                        best = candidate
                    end
                end
            end
        end
    end

    return best
end


local function physicalPressureMove()
    if not CFG.PROACTIVE_MELEE_AVOIDANCE
        or not Runtime.Root
        or not Runtime.Humanoid
    then
        Runtime.PhysicalKiting = false
        Runtime.PhysicalKiteEnemy = nil
        return false
    end

    local enemy, dist =
        nearestPhysicalEnemy(Runtime.Root.Position)

    if not enemy or not enemy.Root or not enemy.Root.Parent then
        Runtime.PhysicalKiting = false
        Runtime.PhysicalKiteEnemy = nil
        return false
    end

    local softRadius, releaseRadius =
        physicalPressureSettings(enemy)

    local _, closing, timeToContact =
        physicalClosingInfo(enemy, Runtime.Root.Position)

    -- A fast chaser gets a SMALL early-start bonus, but unlike V6 this never
    -- turns into a 30-36 stud "danger bubble".
    local earlyBonus =
        math.clamp(
            math.max(closing - CFG.PHYSICAL_KITE_START_CLOSING, 0) * 0.12,
            0,
            4.0
        )

    local startRadius = softRadius + earlyBonus

    local shouldKite =
        dist <= CFG.PHYSICAL_HARD_KITE_RADIUS
        or (
            dist <= startRadius
            and closing >= CFG.PHYSICAL_KITE_MIN_CLOSING
        )
        or (
            Runtime.PhysicalKiting
            and Runtime.PhysicalKiteEnemy == enemy.Model
            and dist < releaseRadius
            and closing > 0.8
        )

    if not shouldKite then
        if Runtime.PhysicalKiting
            and Runtime.PhysicalKiteEnemy == enemy.Model
            and os.clock() - Runtime.LastPhysicalKiteLog >= CFG.PHYSICAL_KITE_LOG_COOLDOWN
        then
            Runtime.LastPhysicalKiteLog = os.clock()
            logKV("PHYSICAL_PRESSURE_CLEAR", {
                enemy = enemy.Model.Name,
                distance = string.format("%.1f", dist),
            })
        end

        Runtime.PhysicalKiting = false
        Runtime.PhysicalKiteEnemy = nil
        return false
    end

    Runtime.PhysicalKiting = true
    Runtime.PhysicalKiteEnemy = enemy.Model

    local origin = Runtime.Root.Position
    local away = unitHorizontal(origin - enemy.Root.Position)

    local tangent =
        Vector3.new(
            -away.Z,
            0,
            away.X
        ) * Runtime.OrbitSign

    -- Diagonal retreat: creates space without endlessly running straight away.
    local dir =
        unitHorizontal(
            away * 1.0
            + tangent * 0.52
        )

    local needed =
        math.max(
            CFG.PHYSICAL_KITE_STEP,
            startRadius - dist + 4.0
        )

    local destination =
        origin + dir * needed

    local leashedDestination =
        Runtime.PhysicalLeashDestination(
            enemy,
            startRadius,
            needed
        )

    if leashedDestination then
        destination =
            leashedDestination

        if os.clock()
            - Runtime.LastPhysicalLeashLog
            >= CFG.PHYSICAL_TARGET_LEASH_LOG_COOLDOWN
        then
            Runtime.LastPhysicalLeashLog =
                os.clock()

            logKV("PHYSICAL_PRESSURE_LEASH", {
                enemy =
                    enemy.Model.Name,
                target =
                    Runtime.Target
                    and Runtime.Target.Name
                    or "none",
                target_distance =
                    Runtime.TargetRoot
                    and string.format(
                        "%.1f",
                        horizontalDistance(
                            destination,
                            Runtime.TargetRoot.Position
                        )
                    )
                    or "none",
            })
        end
    end

    -- If the first pressure lane faces a wall, select an actually open lane.
    if movementWallHit(origin, destination) then
        local open =
            chooseOpenSpacePoint(
                origin,
                away
            )

        if open then
            destination = open.Position
        else
            dir =
                unitHorizontal(
                    away * 1.0
                    - tangent * 0.52
                )

            destination =
                origin + dir * needed
        end
    end

    moveTo(destination, "PHYSICAL_PRESSURE")

    if os.clock() - Runtime.LastPhysicalKiteLog >= CFG.PHYSICAL_KITE_LOG_COOLDOWN then
        Runtime.LastPhysicalKiteLog = os.clock()

        logKV("PHYSICAL_PRESSURE", {
            enemy = enemy.Model.Name,
            distance = string.format("%.1f", dist),
            closing = string.format("%.1f", closing),
            ttc = timeToContact < math.huge
                and string.format("%.2f", timeToContact)
                or "inf",
            start = string.format("%.1f", startRadius),
        })
    end

    return true
end



-- ============================================================
-- Combat movement
-- ============================================================

local function desiredCombatPoint()
    if not Runtime.Root
        or not Runtime.TargetRoot
    then
        return nil
    end

    local player = Runtime.Root.Position
    local target = Runtime.TargetRoot.Position

    local radial =
        unitHorizontal(player-target)

    local desiredRange = desiredRangeForTarget()

    local desired =
        target
        + radial*desiredRange

    -- Tangential offset creates a moving flank/orbit rather than standing
    -- directly on the enemy's frontal attack line.
    local tangent =
        Vector3.new(
            -radial.Z,
            0,
            radial.X
        )

    if os.clock()-Runtime.LastOrbitSwitch
        >= CFG.ORBIT_SWITCH_SECONDS
    then
        Runtime.LastOrbitSwitch = os.clock()
        Runtime.OrbitSign *= -1
    end

    desired +=
        tangent
        * CFG.ORBIT_OFFSET
        * Runtime.OrbitSign

    return Vector3.new(
        desired.X,
        player.Y,
        desired.Z
    )
end

local function clearApproachPath()
    Runtime.ApproachWaypoints = nil
    Runtime.ApproachIndex = 1
    Runtime.ApproachDestination = nil
    Runtime.ApproachTarget = nil
    Runtime.ApproachFallbackPosition = nil
    Runtime.ApproachFallbackUntil = -math.huge
end

local function approachGoalPosition()
    if not Runtime.Root
        or not Runtime.TargetRoot
        or not Runtime.TargetRoot.Parent
    then
        return nil
    end

    local origin = Runtime.Root.Position
    local target = Runtime.TargetRoot.Position
    local desiredRange = desiredRangeForTarget()

    local away =
        unitHorizontal(
            origin - target
        )

    return Vector3.new(
        target.X + away.X * desiredRange,
        origin.Y,
        target.Z + away.Z * desiredRange
    )
end

local function computeApproachPath(destination)
    if not Runtime.Root or not destination then
        return false
    end

    local path =
        PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            AgentCanClimb = true,
            WaypointSpacing = 7,
        })

    local ok =
        pcall(
            path.ComputeAsync,
            path,
            Runtime.Root.Position,
            destination
        )

    if not ok
        or path.Status ~= Enum.PathStatus.Success
    then
        return false
    end

    local waypoints = path:GetWaypoints()

    if #waypoints < 2 then
        return false
    end

    local previous =
        Runtime.Root.Position

    for i = 2, #waypoints do
        local point =
            waypoints[i].Position

        if math.abs(point.Y - previous.Y)
            > CFG.SAFE_VERTICAL_DELTA
        then
            logKV("APPROACH_PATH_REJECT", {
                index = i,
                reason = "vertical_delta",
                from = vec(previous),
                to = vec(point),
            })

            return false
        end

        previous = point
    end

    Runtime.ApproachWaypoints = waypoints
    Runtime.ApproachIndex = 2
    Runtime.ApproachDestination = destination
    Runtime.ApproachTarget = Runtime.Target

    return true
end

local function chooseProgressStep(goal)
    if not Runtime.Root or not goal then
        return nil
    end

    local origin = Runtime.Root.Position
    local forward =
        unitHorizontal(
            goal - origin
        )

    local baseAngle =
        math.atan2(
            forward.Z,
            forward.X
        )

    local currentDistance =
        horizontalDistance(
            origin,
            goal
        )

    local best
    local bestScore = math.huge

    for _, radius in ipairs(CFG.APPROACH_STEP_RADII) do
        for _, degrees in ipairs(CFG.APPROACH_ANGLES) do
            local angle =
                baseAngle + math.rad(degrees)

            local dir =
                Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                )

            local candidate =
                origin + dir * radius

            if not movementWallHit(origin, candidate)
                and hasGroundAt(candidate)
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                local route =
                    routeDanger(
                        origin,
                        candidate
                    )

                local candidateDistance =
                    horizontalDistance(
                        candidate,
                        goal
                    )

                local progress =
                    currentDistance - candidateDistance

                local score =
                    danger
                    + route * 0.35
                    + enemyPenalty(candidate) * 0.30
                    + radius * 0.8
                    - progress * 180

                if inside > 0 then
                    score += 70000
                end

                -- Prefer forward. If forward is unsafe, left/right naturally
                -- win. Backtracking is only accepted when everything else is
                -- genuinely dangerous/blocked.
                if progress < -CFG.APPROACH_MIN_PROGRESS then
                    score +=
                        math.abs(progress)
                        * 340
                elseif progress >= CFG.APPROACH_MIN_PROGRESS then
                    score -= 2200
                end

                if clearance ~= math.huge then
                    score -=
                        math.min(
                            math.max(clearance, 0),
                            12
                        ) * 18
                end

                if score < bestScore then
                    bestScore = score
                    best = {
                        Position = candidate,
                        Radius = radius,
                        Progress = progress,
                        Angle = degrees,
                        Score = score,
                    }
                end
            end
        end
    end

    return best
end

local function longRangeApproachThink()
    if not Runtime.Root
        or not Runtime.TargetRoot
        or not Runtime.TargetRoot.Parent
        or not Runtime.TargetHumanoid
        or Runtime.TargetHumanoid.Health <= 0
    then
        clearApproachPath()
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            Runtime.TargetRoot.Position
        )

    local desiredRange =
        desiredRangeForTarget()

    if distance <= desiredRange + CFG.APPROACH_TRIGGER_EXTRA then
        clearApproachPath()
        return false
    end

    local goal =
        approachGoalPosition()

    if not goal then
        return false
    end

    local now = os.clock()

    local targetChanged =
        Runtime.ApproachTarget ~= Runtime.Target

    local destinationChanged =
        not Runtime.ApproachDestination
        or horizontalDistance(
            Runtime.ApproachDestination,
            goal
        ) > 18

    local needsPath =
        targetChanged
        or destinationChanged
        or not Runtime.ApproachWaypoints
        or now - Runtime.LastApproachPathAt >= CFG.APPROACH_REPATH_INTERVAL

    if needsPath then
        Runtime.LastApproachPathAt = now

        if computeApproachPath(goal) then
            if now - Runtime.LastApproachLog >= CFG.APPROACH_LOG_COOLDOWN then
                Runtime.LastApproachLog = now

                logKV("APPROACH_PATH", {
                    target = Runtime.Target.Name,
                    distance = string.format("%.1f", distance),
                    waypoints = #Runtime.ApproachWaypoints,
                })
            end
        else
            Runtime.ApproachWaypoints = nil
        end
    end

    local waypoint =
        Runtime.ApproachWaypoints
        and Runtime.ApproachWaypoints[
            Runtime.ApproachIndex
        ]

    if waypoint then
        if horizontalDistance(
            Runtime.Root.Position,
            waypoint.Position
        ) <= CFG.APPROACH_WAYPOINT_REACHED
        then
            Runtime.ApproachIndex += 1
            waypoint =
                Runtime.ApproachWaypoints[
                    Runtime.ApproachIndex
                ]
        end

        if waypoint then
            if waypoint.Action
                == Enum.PathWaypointAction.Jump
            then
                Runtime.Humanoid.Jump = true
            end

            moveTo(
                waypoint.Position,
                "COMBAT_APPROACH_PATH"
            )

            return true
        end
    end

    -- Pathfinding may fail in a scripted boss corridor. Keep making progress
    -- instead of stopping: forward first, then diagonals/left/right, backward
    -- only when no safe progress lane exists.
    if Runtime.ApproachFallbackPosition
        and now < Runtime.ApproachFallbackUntil
        and horizontalDistance(
            Runtime.Root.Position,
            Runtime.ApproachFallbackPosition
        ) > 3
    then
        moveTo(
            Runtime.ApproachFallbackPosition,
            "COMBAT_APPROACH_STEP"
        )

        return true
    end

    local step =
        chooseProgressStep(goal)

    if step then
        Runtime.ApproachFallbackPosition = step.Position
        Runtime.ApproachFallbackUntil = now + CFG.APPROACH_HOLD

        if now - Runtime.LastApproachLog >= CFG.APPROACH_LOG_COOLDOWN then
            Runtime.LastApproachLog = now

            logKV("APPROACH_STEP", {
                target = Runtime.Target.Name,
                distance = string.format("%.1f", distance),
                progress = string.format("%.1f", step.Progress),
                angle = step.Angle,
                radius = step.Radius,
            })
        end

        moveTo(
            step.Position,
            "COMBAT_APPROACH_STEP"
        )

        return true
    end

    return false
end

Runtime.AzrallikSpreadTellCandidate = function(
    bossWave,
    bossThreats
)
    if Runtime.ActiveBossName
            ~= "Demon Lord Azrallik"
        or not Runtime.Root
        or not Runtime.ActiveBossRoot
        or not Runtime.AzrallikSpreadTellOrigin
    then
        return nil
    end

    if bossThreatHas(
        "azrallikPunchSpread",
        bossThreats or {}
    ) then
        return nil
    end

    local now = os.clock()
    local elapsed =
        now
        - (
            Runtime.AzrallikSpreadTellAt
            or -math.huge
        )

    if elapsed < 0
        or elapsed
            > CFG.AZRALLIK_SPREAD_TELL_WINDOW
    then
        Runtime.AzrallikSpreadTellOrigin = nil
        return nil
    end

    if elapsed
        < CFG.AZRALLIK_SPREAD_PREMOVE_START
    then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local bossPosition =
        Runtime.ActiveBossRoot.Position

    local bossDistance =
        horizontalDistance(
            origin,
            bossPosition
        )

    -- If we are still extremely far after a respawn, keep approaching. The
    -- dangerous deaths were consistently in the ~60-90 stud region.
    if bossDistance
        > CFG.AZRALLIK_SPREAD_PREMOVE_MAX_BOSS_DISTANCE
    then
        return nil
    end

    local radial =
        unitHorizontal(
            origin - bossPosition
        )

    if radial.Magnitude <= 0.1 then
        radial =
            unitHorizontal(
                Runtime.Root.CFrame.LookVector
            )
    end

    local tangent =
        Vector3.new(
            -radial.Z,
            0,
            radial.X
        )

    local preferredSign =
        Runtime.AzrallikSpreadOrbitSign
        or 1

    local best
    local bestScore = math.huge

    for _, sign in ipairs({
        preferredSign,
        -preferredSign,
    }) do
        for _, step in ipairs(
            CFG.AZRALLIK_SPREAD_PREMOVE_STEPS
        ) do
            local direction =
                unitHorizontal(
                    tangent * sign
                    + radial * 0.10
                )

            local candidate =
                origin
                + direction * step

            if hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                local crossing =
                    routeDanger(
                        origin,
                        candidate
                    )

                local candidateBossDistance =
                    horizontalDistance(
                        candidate,
                        bossPosition
                    )

                -- Do not use the prediction phase to keep charging inward.
                local inward =
                    math.max(
                        0,
                        bossDistance
                        - candidateBossDistance
                    )

                if inside == 0
                    and crossing
                        <= CFG.AZRALLIK_SPREAD_ROUTE_DANGER_MAX
                then
                    local score =
                        step * 20
                        + crossing * 0.05
                        + inward * 900
                        + (
                            sign == preferredSign
                            and 0
                            or 350
                        )

                    if clearance ~= math.huge then
                        score -=
                            math.min(
                                math.max(clearance, 0),
                                20
                            ) * 35
                    end

                    if score < bestScore then
                        bestScore = score

                        best = {
                            Position = candidate,
                            Radius = step,
                            Score = score,
                            Inside = inside,
                            Clearance = clearance,
                            Label =
                                "azrallik_spread_premove",
                            Source =
                                "AzrallikSpreadTell",
                        }
                    end
                end
            end
        end
    end

    return best
end


Runtime.AzrallikSpreadActiveCandidate = function(
    bossWave,
    bossThreats
)
    if Runtime.ActiveBossName
            ~= "Demon Lord Azrallik"
        or not Runtime.Root
        or not Runtime.ActiveBossRoot
        or not bossThreatHas(
            "azrallikPunchSpread",
            bossThreats or {}
        )
    then
        return nil
    end

    local origin =
        Runtime.Root.Position

    local _, currentInside, currentClearance =
        pointDanger(origin)

    -- The old generic solver could choose a 38-46 stud destination even when
    -- the current point was already in a safe radial gap. Walking toward that
    -- distant point crossed the active fan and caused the observed deaths.
    if currentInside == 0
        and (
            currentClearance == math.huge
            or currentClearance
                >= CFG.AZRALLIK_SPREAD_HOLD_CLEARANCE
        )
    then
        return {
            Position = origin,
            Radius = 0,
            Score = 0,
            Inside = 0,
            Clearance = currentClearance,
            Label = "azrallik_spread_hold",
            Source = "AzrallikSpreadSafeGap",
        }
    end

    local bossPosition =
        Runtime.ActiveBossRoot.Position

    local currentBossDistance =
        horizontalDistance(
            origin,
            bossPosition
        )

    local best
    local bestScore = math.huge

    for _, radius in ipairs(
        CFG.AZRALLIK_SPREAD_LOCAL_RADII
    ) do
        for i = 0,
            CFG.BOSS_WAVE_DIRECTIONS - 1
        do
            local angle =
                (math.pi * 2)
                * (
                    i
                    / CFG.BOSS_WAVE_DIRECTIONS
                )

            local candidate =
                origin
                + Vector3.new(
                    math.cos(angle),
                    0,
                    math.sin(angle)
                ) * radius

            if hasGroundAt(candidate)
                and not movementWallHit(
                    origin,
                    candidate
                )
            then
                local danger, inside, clearance =
                    pointDanger(candidate)

                local candidateBossDistance =
                    horizontalDistance(
                        candidate,
                        bossPosition
                    )

                local crossing =
                    routeDanger(
                        origin,
                        candidate
                    )

                local inward =
                    math.max(
                        0,
                        currentBossDistance
                        - candidateBossDistance
                    )

                local score =
                    inside * 100000
                    + danger * 0.05
                    + radius * 160
                    + crossing * 0.04
                    + inward * 500

                if clearance ~= math.huge then
                    score -=
                        math.min(
                            math.max(clearance, 0),
                            20
                        ) * 90
                end

                if score < bestScore then
                    bestScore = score

                    best = {
                        Position = candidate,
                        Radius = radius,
                        Score = score,
                        Inside = inside,
                        Clearance = clearance,
                        Label =
                            "azrallik_spread_local_gap",
                        Source =
                            "AzrallikSpreadExact",
                    }
                end
            end
        end
    end

    return best
end


Runtime.AzrallikFingerTellCandidate = function()
    if Runtime.ActiveBossName ~= "Demon Lord Azrallik"
        or not Runtime.Root
        or not Runtime.Humanoid
        or not Runtime.AzrallikFingerTellOrigin
    then
        return nil
    end

    local now = os.clock()
    local elapsed =
        now - (Runtime.AzrallikFingerTellAt or -math.huge)

    if elapsed < 0
        or elapsed > CFG.AZRALLIK_FINGER_TELL_WINDOW
    then
        Runtime.AzrallikFingerTellOrigin = nil
        Runtime.AzrallikFingerTellMoved = false
        return nil
    end

    local origin =
        Runtime.AzrallikFingerTellOrigin

    local escaped =
        horizontalDistance(
            Runtime.Root.Position,
            origin
        )

    if escaped >= CFG.AZRALLIK_FINGER_PREHOLD_CLEARANCE then
        local _, inside, clearance =
            pointDanger(Runtime.Root.Position)

        return {
            Position = Runtime.Root.Position,
            Radius = 0,
            Score = 0,
            Inside = inside,
            Clearance = clearance,
            Label = "azrallik_finger_premove_hold",
            Source = "AzrallikFingerTellHold",
        }
    end

    local bossRoot =
        Runtime.ActiveBossModel
        and modelRoot(Runtime.ActiveBossModel)

    local preferred =
        bossRoot
        and unitHorizontal(
            Runtime.Root.Position - bossRoot.Position
        )
        or unitHorizontal(Runtime.Root.CFrame.RightVector)

    local escape =
        chooseOpenSpacePoint(
            Runtime.Root.Position,
            preferred,
            CFG.AZRALLIK_FINGER_PREMOVE_MIN_RADIUS
        )

    if not escape then
        return nil
    end

    local _, inside, clearance =
        pointDanger(escape.Position)

    if inside > 0 then
        return nil
    end

    escape.Inside = inside
    escape.Clearance = clearance
    escape.Label = "azrallik_finger_premove"
    escape.Source = "AzrallikFingerTell"

    return escape
end

Runtime.AzrallikFingerTellMove = function()
    if activeThreatCount() > 0
        or Runtime.BossWave
        or Runtime.DodgeActive
    then
        return false
    end

    local plan =
        Runtime.AzrallikFingerTellCandidate
        and Runtime.AzrallikFingerTellCandidate()

    if not plan then
        return false
    end

    if plan.Label == "azrallik_finger_premove_hold" then
        pcall(function()
            Runtime.Humanoid:MoveTo(Runtime.Root.Position)
        end)

        Runtime.MovementOwner = "AZRALLIK_FINGER_PREHOLD"
        return true
    end

    moveTo(
        plan.Position,
        "AZRALLIK_FINGER_PREMOVE"
    )

    if not Runtime.AzrallikFingerTellMoved then
        Runtime.AzrallikFingerTellMoved = true

        logKV("AZRALLIK_FINGER_PREMOVE", {
            elapsed =
                string.format(
                    "%.2f",
                    os.clock() - Runtime.AzrallikFingerTellAt
                ),
            radius = string.format("%.1f", plan.Radius),
            target = vec(plan.Position),
        })
    end

    return true
end

local function combatMovement()
    if Runtime.AzrallikFingerTellMove
        and Runtime.AzrallikFingerTellMove()
    then
        return true
    end

    if physicalPressureMove() then
        return true
    end

    if longRangeApproachThink() then
        return true
    end

    if not Runtime.TargetRoot
        or not Runtime.TargetRoot.Parent
        or not Runtime.Root
    then
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            Runtime.TargetRoot.Position
        )

    local desired = desiredCombatPoint()
    if not desired then return false end

    -- Move only when range is meaningfully off or maintain lateral orbit.
    local desiredRange = desiredRangeForTarget()

    if distance > desiredRange + 3
        or distance < desiredRange - 2
    then
        moveTo(safeCombatDestination(desired),"COMBAT_RANGE")
    else
        -- Small lateral reposition keeps mage lines from repeatedly targeting
        -- a stationary character.
        moveTo(safeCombatDestination(desired),"COMBAT_ORBIT")
    end

    return true
end

-- ============================================================
-- Room navigation
-- ============================================================

local function spawnCentroid(room)
    if not room then return nil end

    local folder =
        room:FindFirstChild("enemyFolder")

    if not folder then return nil end

    local positions = {}

    for _,inst in ipairs(folder:GetChildren()) do
        if inst.Name == "spawn"
            and inst:IsA("BasePart")
        then
            positions[#positions+1] = inst.Position
        end
    end

    if #positions == 0 then
        return nil
    end

    local sum = Vector3.zero

    for _,p in ipairs(positions) do
        sum += p
    end

    return sum/#positions
end

local function nextRoomWaypoint()
    local dungeon = workspace:FindFirstChild("dungeon")
    if not dungeon then return nil end

    local nextIndex =
        math.max(Runtime.CurrentRoomIndex,0) + 1

    local room =
        dungeon:FindFirstChild(
            "room" .. tostring(nextIndex)
        )

    if room then
        local c = spawnCentroid(room)
        if c then return c,nextIndex end
    end

    -- Underworld recorded room1...room9 then bossRoom.
    if Runtime.CurrentRoomIndex >= 9 then
        local boss =
            dungeon:FindFirstChild("bossRoom")

        if boss then
            local c = spawnCentroid(boss)

            if c then
                return c,999
            end

            local p =
                boss.PrimaryPart
                or boss:FindFirstChildWhichIsA(
                    "BasePart",
                    true
                )

            if p then
                return p.Position,999
            end
        end
    end

    return nil
end

local function computePath(destination)
    if not Runtime.Root then
        return false
    end

    local path =
        PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            AgentCanClimb = true,
            WaypointSpacing = 6,
        })

    local ok =
        pcall(
            path.ComputeAsync,
            path,
            Runtime.Root.Position,
            destination
        )

    if not ok
        or path.Status
            ~= Enum.PathStatus.Success
    then
        return false
    end

    Runtime.PathWaypoints =
        path:GetWaypoints()

    Runtime.PathIndex = 2
    Runtime.PathDestination = destination

    return #Runtime.PathWaypoints >= 2
end

stopTransitTween = function(reason)
    local hadTransit =
        Runtime.TransitTween ~= nil
        or Runtime.TransitTweenTarget ~= nil
        or Runtime.TransitTweenDone == false

    if Runtime.TransitTweenConn then
        pcall(function()
            Runtime.TransitTweenConn:Disconnect()
        end)
        Runtime.TransitTweenConn = nil
    end

    if Runtime.TransitTween then
        pcall(function()
            Runtime.TransitTween:Cancel()
        end)
        Runtime.TransitTween = nil
    end

    if Runtime.Humanoid
        and Runtime.TransitAutoRotate ~= nil
    then
        pcall(function()
            Runtime.Humanoid.AutoRotate =
                Runtime.TransitAutoRotate
        end)
    end

    Runtime.TransitAutoRotate = nil
    Runtime.TransitTweenTarget = nil
    Runtime.TransitTweenDone = true

    if Runtime.MovementOwner == "TRANSIT"
        or Runtime.MovementOwner == "TRANSIT_SETTLE"
    then
        Runtime.MovementOwner = "NONE"
    end

    if reason and hadTransit then
        log("TRANSIT_TWEEN_STOP", tostring(reason))
    end
end

local function startTransitTween(position)
    if not CFG.TRANSIT_TWEEN_ENABLED
        or not Runtime.Root
        or not Runtime.Humanoid
        or not position
    then
        return false
    end

    local now =
        os.clock()

    if now < Runtime.TransitBackoffUntil then
        return false
    end

    if Runtime.TransitDisabledRoom ~= nil
        and Runtime.TransitDisabledRoom
            == Runtime.CurrentRoomIndex
    then
        return false
    end

    local safe, rejectReason =
        safeMovementDestination(
            position,
            Runtime.Root.Position
        )

    if not safe then
        logKV("TRANSIT_REJECT", {
            reject = tostring(rejectReason),
            requested = vec(position),
            current = vec(Runtime.Root.Position),
        })

        Runtime.ApproachWaypoints = nil
        Runtime.PathWaypoints = nil
        return false
    end

    stopTransitTween(nil)

    local here =
        Runtime.Root.Position

    local distance =
        horizontalDistance(
            here,
            position
        )

    if distance <= 1.0 then
        Runtime.TransitTweenDone = true
        return true
    end

    local actualSpeed =
        math.min(
            CFG.TRANSIT_TWEEN_SPEED,
            CFG.TRANSIT_TWEEN_SAFE_CAP
        )

    if CFG.TRANSIT_TWEEN_SPEED
        > CFG.TRANSIT_TWEEN_SAFE_CAP
    then
        logKV("TRANSIT_SPEED_CLAMP", {
            requested = CFG.TRANSIT_TWEEN_SPEED,
            actual = actualSpeed,
        })
    end

    local duration =
        math.clamp(
            distance / actualSpeed,
            CFG.TRANSIT_TWEEN_MIN_DURATION,
            CFG.TRANSIT_TWEEN_MAX_DURATION
        )

    local flatTarget =
        Vector3.new(
            position.X,
            here.Y,
            position.Z
        )

    local rotation =
        Runtime.Root.CFrame
        - Runtime.Root.CFrame.Position

    if horizontalDistance(
        here,
        flatTarget
    ) > 0.5 then
        rotation =
            CFrame.lookAt(
                Vector3.zero,
                unitHorizontal(
                    flatTarget - here
                )
            )
    end

    local goal =
        CFrame.new(position)
        * rotation.Rotation

    -- Clear stale Humanoid MoveTo before transit owns movement.
    pcall(function()
        Runtime.Humanoid:MoveTo(
            Runtime.Root.Position
        )
        Runtime.Humanoid:Move(
            Vector3.zero,
            false
        )
        Runtime.Root.AssemblyLinearVelocity =
            Vector3.zero
    end)

    Runtime.TransitAutoRotate =
        Runtime.Humanoid.AutoRotate
    Runtime.Humanoid.AutoRotate = false

    Runtime.TransitGeneration += 1

    local generation =
        Runtime.TransitGeneration

    Runtime.TransitStartPosition = here
    Runtime.TransitExpectedPosition = position
    Runtime.TransitTweenDone = false
    Runtime.TransitTweenTarget = position
    Runtime.MovementOwner = "TRANSIT"

    local tween =
        TweenService:Create(
            Runtime.Root,
            TweenInfo.new(
                duration,
                Enum.EasingStyle.Linear,
                Enum.EasingDirection.Out
            ),
            {
                CFrame = goal,
            }
        )

    Runtime.TransitTween = tween

    Runtime.TransitTweenConn =
        tween.Completed:Connect(function(state)
            if generation
                ~= Runtime.TransitGeneration
            then
                return
            end

            Runtime.TransitTween = nil
            Runtime.TransitTweenTarget = nil

            if state
                ~= Enum.PlaybackState.Completed
            then
                Runtime.TransitTweenDone = true
                Runtime.MovementOwner = "NONE"
                return
            end

            Runtime.TransitTweenDone = true
            Runtime.MovementOwner =
                "TRANSIT_SETTLE"
            Runtime.TransitSettleUntil =
                os.clock()
                + CFG.TRANSIT_SETTLE_TIME

            if Runtime.Humanoid
                and Runtime.TransitAutoRotate
                    ~= nil
            then
                Runtime.Humanoid.AutoRotate =
                    Runtime.TransitAutoRotate
            end

            Runtime.TransitAutoRotate = nil

            -- Clear stale MoveTo again at the completed point.
            pcall(function()
                Runtime.Root.AssemblyLinearVelocity =
                    Vector3.zero
                Runtime.Humanoid:MoveTo(
                    Runtime.Root.Position
                )
                Runtime.Humanoid:Move(
                    Vector3.zero,
                    false
                )
            end)

            local expected =
                Runtime.TransitExpectedPosition
            local started =
                Runtime.TransitStartPosition

            logKV("TRANSIT_COMPLETE", {
                expected =
                    expected and vec(expected) or "nil",
                actual =
                    vec(Runtime.Root.Position),
            })

            task.delay(
                CFG.TRANSIT_SETTLE_TIME,
                function()
                    if not Runtime.Alive
                        or generation
                            ~= Runtime.TransitGeneration
                        or not Runtime.Root
                    then
                        return
                    end

                    local actual =
                        Runtime.Root.Position

                    local drift =
                        expected
                        and horizontalDistance(
                            actual,
                            expected
                        )
                        or 0

                    local towardStart = false

                    if expected and started then
                        towardStart =
                            horizontalDistance(
                                actual,
                                started
                            )
                            < horizontalDistance(
                                expected,
                                started
                            ) - 2
                    end

                    if drift
                        >= CFG.TRANSIT_SNAPBACK_DISTANCE
                        and towardStart
                    then
                        local room =
                            Runtime.CurrentRoomIndex

                        if Runtime.TransitSnapbackRoom
                            ~= room
                        then
                            Runtime.TransitSnapbackRoom = room
                            Runtime.TransitSnapbackCount = 0
                        end

                        Runtime.TransitSnapbackCount += 1
                        Runtime.TransitBackoffUntil =
                            os.clock()
                            + CFG.TRANSIT_SNAPBACK_BACKOFF

                        if Runtime.TransitSnapbackCount
                            >= CFG.TRANSIT_SNAPBACK_ROOM_LIMIT
                        then
                            Runtime.TransitDisabledRoom =
                                room
                        end

                        Runtime.ApproachWaypoints = nil
                        Runtime.PathWaypoints = nil

                        logKV("TRANSIT_SNAPBACK", {
                            drift =
                                string.format("%.1f", drift),
                            room = tostring(room),
                            count =
                                Runtime.TransitSnapbackCount,
                            disabled_room =
                                tostring(
                                    Runtime.TransitDisabledRoom
                                ),
                        })
                    else
                        logKV("TRANSIT_STABLE", {
                            drift =
                                string.format("%.1f", drift),
                        })
                    end

                    if Runtime.MovementOwner
                        == "TRANSIT_SETTLE"
                    then
                        Runtime.MovementOwner = "NONE"
                    end
                end
            )
        end)

    logKV("TRANSIT_TWEEN", {
        studs = string.format("%.1f", distance),
        duration = string.format("%.2f", duration),
        speed = string.format("%.1f", actualSpeed),
    })

    tween:Play()

    return true
end


local function isDungeonGatePart(inst)
    if not inst then
        return false
    end

    local cur = inst

    for _ = 1, 5 do
        if not cur then break end

        local lower =
            string.lower(cur.Name)

        if lower == "door"
            or lower:find("barrier", 1, true)
        then
            return true
        end

        cur = cur.Parent
    end

    return false
end

local function gateInDirection(destination)
    if not Runtime.Root or not destination then
        return nil
    end

    local hit =
        staticObstacleRay(
            Runtime.Root.Position,
            destination,
            28
        )

    if hit and isDungeonGatePart(hit.Instance) then
        return hit
    end

    return nil
end

local function selectTransitWaypoint(waypoints, startIndex, maxDistance)
    if not Runtime.Root or not waypoints then
        return nil, nil
    end

    local origin = Runtime.Root.Position
    local best
    local bestIndex

    for i = startIndex, #waypoints do
        local waypoint = waypoints[i]

        if waypoint.Action == Enum.PathWaypointAction.Jump then
            break
        end

        local distance =
            horizontalDistance(
                origin,
                waypoint.Position
            )

        if distance > maxDistance then
            break
        end

        local safeWaypoint =
            safeMovementDestination(
                waypoint.Position,
                origin
            )

        if distance >= 2
            and safeWaypoint
            and not movementWallHit(
                origin,
                waypoint.Position
            )
        then
            best = waypoint
            bestIndex = i
        else
            break
        end
    end

    return best, bestIndex
end

local function transitCombatShouldStop()
    if activeThreatCount() > 0 then
        return true
    end

    if Runtime.TargetRoot
        and Runtime.TargetHumanoid
        and Runtime.TargetHumanoid.Health > 0
        and Runtime.Root
    then
        local distance =
            horizontalDistance(
                Runtime.Root.Position,
                Runtime.TargetRoot.Position
            )

        if distance <= CFG.TRANSIT_COMBAT_STOP_DISTANCE then
            return true
        end

        local physical, physicalDist =
            nearestPhysicalEnemy(
                Runtime.Root.Position
            )

        if physical and physicalDist <= 30 then
            return true
        end
    end

    return false
end


local function combatTransitTweenThink()
    if Runtime.MovementOwner == "TRANSIT_SETTLE"
        and os.clock() < Runtime.TransitSettleUntil
    then
        return true
    end

    if os.clock() < Runtime.TransitBackoffUntil then
        return false
    end

    if Runtime.TransitDisabledRoom ~= nil
        and Runtime.TransitDisabledRoom
            == Runtime.CurrentRoomIndex
    then
        return false
    end

    if not CFG.TRANSIT_TWEEN_ENABLED
        or not Runtime.Root
        or not Runtime.TargetRoot
        or not Runtime.TargetRoot.Parent
        or not Runtime.TargetHumanoid
        or Runtime.TargetHumanoid.Health <= 0
    then
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            Runtime.TargetRoot.Position
        )

    if distance <= CFG.TRANSIT_COMBAT_STOP_DISTANCE
        or activeThreatCount() > 0
    then
        stopTransitTween("combat_range_or_threat")
        return false
    end

    local physical, physicalDist =
        nearestPhysicalEnemy(
            Runtime.Root.Position
        )

    if physical and physicalDist <= 30 then
        stopTransitTween("physical_near")
        return false
    end

    if distance < CFG.TRANSIT_COMBAT_START_DISTANCE
        and not Runtime.TransitTween
    then
        return false
    end

    if Runtime.TransitTween
        and not Runtime.TransitTweenDone
    then
        return true
    end

    local goal =
        approachGoalPosition()

    if not goal then
        return false
    end

    local now = os.clock()

    local needsPath =
        Runtime.ApproachTarget ~= Runtime.Target
        or not Runtime.ApproachWaypoints
        or not Runtime.ApproachDestination
        or horizontalDistance(
            Runtime.ApproachDestination,
            goal
        ) > 16
        or now - Runtime.LastApproachPathAt
            >= CFG.APPROACH_REPATH_INTERVAL

    if needsPath then
        Runtime.LastApproachPathAt = now

        if not computeApproachPath(goal) then
            return false
        end
    end

    local waypoint, index =
        selectTransitWaypoint(
            Runtime.ApproachWaypoints,
            Runtime.ApproachIndex,
            CFG.TRANSIT_SEGMENT_MAX
        )

    if not waypoint then
        return false
    end

    local segmentDistance =
        horizontalDistance(
            Runtime.Root.Position,
            waypoint.Position
        )

    if segmentDistance < CFG.TRANSIT_SEGMENT_MIN then
        return false
    end

    Runtime.ApproachIndex = index + 1

    logKV("COMBAT_TRANSIT", {
        target = Runtime.Target.Name,
        target_distance = string.format("%.1f", distance),
        segment = string.format("%.1f", segmentDistance),
    })

    return startTransitTween(
        waypoint.Position
    )
end

local function navigationThink()
    if Runtime.FinalBossDefeated then
        stopTransitTween("final_boss")
        return false
    end

    if not CFG.AUTO_NAVIGATION
        or not Runtime.Root
    then
        return false
    end

    if Runtime.TargetRoot
        and Runtime.TargetHumanoid
        and Runtime.TargetHumanoid.Health > 0
    then
        return false
    end

    if transitCombatShouldStop() then
        stopTransitTween("combat_or_threat")
        return false
    end

    local destination,nextIndex =
        nextRoomWaypoint()

    if not destination then
        stopTransitTween("no_destination")
        return false
    end

    local now = os.clock()

    local needsPath =
        not Runtime.PathWaypoints
        or not Runtime.PathDestination
        or horizontalDistance(
            Runtime.PathDestination,
            destination
        ) > 12
        or now - Runtime.LastRepath >= CFG.REPATH_INTERVAL

    if needsPath
        and not Runtime.PathComputeBusy
        and now >= Runtime.NextPathComputeAt
    then
        stopTransitTween(nil)

        Runtime.PathComputeBusy = true
        Runtime.LastRepath = now
        Runtime.NextPathComputeAt = now + 0.75

        local ok = computePath(destination)

        Runtime.PathComputeBusy = false

        if not ok then
            local gate =
                gateInDirection(destination)

            if gate then
                Runtime.Humanoid:Move(Vector3.zero, false)
                Runtime.NextPathComputeAt =
                    now + CFG.TRANSIT_GATE_RETRY

                if now - Runtime.LastGateLog
                    >= CFG.TRANSIT_GATE_LOG_COOLDOWN
                then
                    Runtime.LastGateLog = now

                    logKV("TRANSIT_GATE_WAIT", {
                        gate = fullName(gate.Instance),
                        distance = string.format("%.1f", gate.Distance),
                    })
                end

                return true
            end

            moveTo(destination,"NEXT_ROOM_DIRECT")
            return true
        end

        logKV("PATH", {
            next_room = nextIndex,
            waypoints = #Runtime.PathWaypoints,
            transit_tween = CFG.TRANSIT_TWEEN_ENABLED,
        })
    end

    local waypoint =
        Runtime.PathWaypoints
        and Runtime.PathWaypoints[
            Runtime.PathIndex
        ]

    if not waypoint then
        stopTransitTween(nil)
        Runtime.PathWaypoints = nil

        if horizontalDistance(
            Runtime.Root.Position,
            destination
        ) > CFG.TRANSIT_TWEEN_STOP_DISTANCE
        then
            local gate =
                gateInDirection(destination)

            if gate then
                Runtime.Humanoid:Move(Vector3.zero, false)

                if os.clock() - Runtime.LastGateLog
                    >= CFG.TRANSIT_GATE_LOG_COOLDOWN
                then
                    Runtime.LastGateLog = os.clock()

                    logKV("TRANSIT_GATE_WAIT", {
                        gate = fullName(gate.Instance),
                        distance = string.format("%.1f", gate.Distance),
                    })
                end

                return true
            end

            moveTo(destination,"NEXT_ROOM_FINISH")
        else
            Runtime.Humanoid:Move(Vector3.zero, false)
        end

        return true
    end

    if horizontalDistance(
        Runtime.Root.Position,
        waypoint.Position
    ) <= CFG.WAYPOINT_REACHED
    then
        Runtime.PathIndex += 1
        waypoint =
            Runtime.PathWaypoints[
                Runtime.PathIndex
            ]
    end

    if not waypoint then
        return true
    end

    if waypoint.Action == Enum.PathWaypointAction.Jump then
        -- Jump segments are safer with normal Humanoid movement.
        stopTransitTween(nil)
        Runtime.Humanoid.Jump = true
        moveTo(
            waypoint.Position,
            "NEXT_ROOM_PATH_JUMP"
        )
        return true
    end

    if CFG.TRANSIT_TWEEN_ENABLED then
        if Runtime.TransitTween
            and not Runtime.TransitTweenDone
        then
            return true
        end

        local farWaypoint, farIndex =
            selectTransitWaypoint(
                Runtime.PathWaypoints,
                Runtime.PathIndex,
                CFG.TRANSIT_SEGMENT_MAX
            )

        if farWaypoint then
            Runtime.PathIndex = farIndex + 1

            startTransitTween(
                farWaypoint.Position
            )

            return true
        end

        startTransitTween(waypoint.Position)
        return true
    end

    moveTo(
        waypoint.Position,
        "NEXT_ROOM_PATH"
    )

    return true
end

-- ============================================================
-- Attacks / abilities
-- ============================================================

local function busyCasting()
    local char = Runtime.Character

    if not char then return true end

    local busy =
        char:FindFirstChild("busyCasting")

    if not busy then
        return false
    end

    return busy.Value == true
end

local function abilityTool(slot)
    local backpack =
        LP:FindFirstChild("Backpack")

    local function scan(container)
        if not container then return nil end

        for _,tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") then
                local abilitySlot =
                    tool:FindFirstChild(
                        "abilitySlot"
                    )

                if abilitySlot
                    and tostring(
                        abilitySlot.Value
                    ) == slot
                then
                    return tool
                end
            end
        end

        return nil
    end

    return scan(backpack)
        or scan(Runtime.Character)
end

local function castAbility(slot, allowGeometryDanger)
    if not CFG.AUTO_ABILITIES
        or busyCasting()
    then
        return false
    end

    -- V3 blocked skills for the entire lifetime of any warning object.
    -- V6 only blocks a cast when danger is actually imminent at our position.
    if allowGeometryDanger then
        if not CFG.DODGE_CAST_ENABLED
            or Runtime.DodgeCastBlocked()
        then
            return false
        end
    elseif abilityDangerImminent() then
        return false
    end

    local tool = abilityTool(slot)
    if not tool then return false end

    local now = os.clock()
    local localReadyAt = Runtime.LastAbilityCast[slot] or -math.huge

    if now < localReadyAt then
        return false
    end

    local cooldown =
        tool:FindFirstChild("cooldown")

    if cooldown
        and tonumber(cooldown.Value)
        and cooldown.Value > 0
    then
        return false
    end

    local localEvent =
        tool:FindFirstChild("localEvent")

    if not localEvent then
        return false
    end

    local distance = math.huge

    if Runtime.TargetRoot
        and Runtime.Root
    then
        distance =
            horizontalDistance(
                Runtime.TargetRoot.Position,
                Runtime.Root.Position
            )
    end

    local abilityRange =
        CFG.ABILITY_RANGE_HINTS[tool.Name]
        or Profile.AbilityRange

    -- Prefer a legitimate numeric range exposed by the equipped Tool itself
    -- when the game provides one. Do not invent or call any extra remote.
    for _, attributeName in ipairs({
        "Range",
        "range",
        "CastRange",
        "castRange",
        "AbilityRange",
        "abilityRange",
    }) do
        local ok, value =
            pcall(function()
                return
                    tool:GetAttribute(
                        attributeName
                    )
            end)

        if ok
            and type(value) == "number"
            and value > 0
        then
            abilityRange = value
            break
        end
    end

    if distance > abilityRange then
        local lastLog =
            Runtime.LastAbilityRangeSkipLog[
                tool.Name
            ]
            or -math.huge

        if now - lastLog
            >= CFG.ABILITY_RANGE_SKIP_LOG_COOLDOWN
        then
            Runtime.LastAbilityRangeSkipLog[
                tool.Name
            ] = now

            logKV("ABILITY_RANGE_SKIP", {
                slot = slot,
                name = tool.Name,
                distance =
                    string.format(
                        "%.1f",
                        distance
                    ),
                range =
                    string.format(
                        "%.1f",
                        abilityRange
                    ),
            })
        end

        return false
    end

    if now - Runtime.LastAnyAbilityCast
        < CFG.ABILITY_CAST_CHAIN_GAP
    then
        return false
    end

    -- A distant/stale warning no longer suppresses skills. Lock facing onto
    -- the selected enemy immediately before the client fires the ability.
    beginAimLock()

    local cooldownLength =
        tool:FindFirstChild("cooldownLength")

    local localCooldown =
        cooldownLength
        and tonumber(cooldownLength.Value)
        or 0.8

    -- Set the lock BEFORE firing so a delayed replicated cooldown value cannot
    -- allow duplicate casts on consecutive controller ticks.
    Runtime.LastAbilityCast[slot] =
        now + math.max(localCooldown * 0.96, 0.45)

    Runtime.LastAnyAbilityCast = now

    pcall(function()
        localEvent:Fire()
    end)

    local abilityUsed =
        ReplicatedStorage
        :FindFirstChild("remotes")

    abilityUsed =
        abilityUsed
        and abilityUsed:FindFirstChild(
            "abilityUsed"
        )

    if abilityUsed
        and abilityUsed:IsA("RemoteEvent")
    then
        pcall(function()
            abilityUsed:FireServer(
                slot,
                tool
            )
        end)
    end

    logKV("ABILITY", {
        slot = slot,
        name = tool.Name,
        distance = string.format("%.1f",distance),
        range =
            string.format(
                "%.1f",
                abilityRange
            ),
    })

    if CFG.ABILITY_RESULT_DIAGNOSTIC
        and Runtime.TargetHumanoid
        and Runtime.Target
    then
        local probeHumanoid =
            Runtime.TargetHumanoid
        local probeModel =
            Runtime.Target
        local probeHp =
            probeHumanoid.Health
        local probeDistance =
            distance
        local probeName =
            tool.Name
        local probeSlot =
            slot

        task.delay(
            CFG.ABILITY_RESULT_DELAY,
            function()
                if not Runtime.Alive
                    or not probeHumanoid
                    or not probeHumanoid.Parent
                then
                    return
                end

                local hpDelta =
                    math.max(
                        0,
                        probeHp
                        - probeHumanoid.Health
                    )

                local stats =
                    Runtime.AbilityStats[
                        probeName
                    ]

                if not stats then
                    stats = {
                        Casts = 0,
                        Positive = 0,
                        MaxPositiveDistance = 0,
                    }

                    Runtime.AbilityStats[
                        probeName
                    ] = stats
                end

                stats.Casts += 1

                if hpDelta > 0 then
                    stats.Positive += 1
                    stats.MaxPositiveDistance =
                        math.max(
                            stats.MaxPositiveDistance,
                            probeDistance
                        )
                end

                logKV("ABILITY_RESULT", {
                    slot = probeSlot,
                    name = probeName,
                    sample_delay =
                        string.format(
                            "%.2f",
                            CFG.ABILITY_RESULT_DELAY
                        ),
                    cast_distance =
                        string.format(
                            "%.1f",
                            probeDistance
                        ),
                    hp_delta =
                        string.format(
                            "%.0f",
                            hpDelta
                        ),
                    same_target =
                        tostring(
                            Runtime.Target
                            == probeModel
                        ),
                    positive =
                        tostring(
                            hpDelta > 0
                        ),
                })
            end
        )
    end

    return true
end

local function equippedWeaponEvent()
    local char = Runtime.Character
    if not char then return nil end

    for _,inst in ipairs(char:GetChildren()) do
        if inst:IsA("Accessory")
            and inst:FindFirstChild("Weapon")
        then
            return
                inst:FindFirstChildOfClass(
                    "RemoteEvent"
                )
        end
    end

    return nil
end


Runtime.CastAbilityOnEnemy = function(
    slot,
    enemy,
    allowGeometryDanger
)
    if not enemy
        or not enemy.Model
        or not enemy.Root
        or not enemy.Humanoid
        or enemy.Humanoid.Health <= 0
        or not enemy.Model.Parent
    then
        return false
    end

    local savedTarget =
        Runtime.Target
    local savedHumanoid =
        Runtime.TargetHumanoid
    local savedRoot =
        Runtime.TargetRoot

    Runtime.Target =
        enemy.Model
    Runtime.TargetHumanoid =
        enemy.Humanoid
    Runtime.TargetRoot =
        enemy.Root

    local used =
        castAbility(
            slot,
            allowGeometryDanger
        )

    Runtime.Target =
        savedTarget
    Runtime.TargetHumanoid =
        savedHumanoid
    Runtime.TargetRoot =
        savedRoot

    return used
end


Runtime.TryOpportunisticAttack = function(
    allowGeometryDanger
)
    if not CFG.OPPORTUNISTIC_ATTACK_ENABLED
        or not Runtime.Root
    then
        return false
    end

    -- If the current primary is a lone mage, save every ready cast for that
    -- mage. V9.8 was incorrectly spending Infernal Strike on a distant Demon
    -- Warrior while the mage was still the primary target.
    if Runtime.MageFreePressureActive
        and Runtime.MageFreePressureActive()
    then
        return false
    end

    local now = os.clock()
    local physical, physicalDistance =
        nearestPhysicalEnemy(
            Runtime.Root.Position
        )

    local physicalUrgent =
        physical
        and physicalDistance
            <= CFG.OPPORTUNISTIC_PHYSICAL_PRIORITY_RANGE

    local function bestForRange(range)
        local best
        local bestScore = -math.huge

        for _, enemy in ipairs(livingEnemies()) do
            if enemy.Model
                and enemy.Model ~= Runtime.Target
                and enemy.Root
                and enemy.Humanoid
                and enemy.Humanoid.Health > 0
            then
                local d =
                    horizontalDistance(
                        Runtime.Root.Position,
                        enemy.Root.Position
                    )

                if d <= range
                    and d <= CFG.OPPORTUNISTIC_NEARBY_MAX
                then
                    local physicalEnemy =
                        isPhysicalEnemyModel(
                            enemy.Model
                        )

                    local name =
                        enemy.Model.Name or ""

                    local mage =
                        string.find(
                            string.lower(name),
                            "mage",
                            1,
                            true
                        ) ~= nil

                    local relevant =
                        enemyRelevantForEncounter(
                            enemy
                        )

                    if Runtime.ActiveBossName then
                        -- During a live boss, keep the boss as the route/primary
                        -- target. Only a genuinely local add may receive a free
                        -- skill, and never more often than the boss cooldown.
                        relevant =
                            enemy.Model
                                ~= Runtime.ActiveBossModel
                            and enemy.Model.Name
                                ~= "Azrallik's Heart"
                            and d
                                <= CFG.OPPORTUNISTIC_BOSS_ADD_RANGE

                        if relevant
                            and now
                                - Runtime.LastBossOpportunityAt
                                < CFG.OPPORTUNISTIC_BOSS_COOLDOWN
                        then
                            relevant = false
                        end
                    end

                    if relevant then
                        local score =
                            -d * 20

                        if physicalUrgent then
                            if physicalEnemy then
                                score += 6000
                            else
                                score -= 6000
                            end
                        elseif mage
                            and (
                                not physical
                                or physicalDistance
                                    > CFG.OPPORTUNISTIC_MAGE_PHYSICAL_GUARD
                            )
                        then
                            -- Exactly the cheap opportunity the user observed:
                            -- a mage is stationary and only projecting red
                            -- geometry, so hit it while our movement dodges.
                            score += 4200
                        elseif physicalEnemy then
                            score += 900
                        else
                            score += 1800
                        end

                        if enemy.Humanoid.MaxHealth > 0 then
                            score +=
                                (
                                    1
                                    - enemy.Humanoid.Health
                                        / enemy.Humanoid.MaxHealth
                                ) * 600
                        end

                        if score > bestScore then
                            bestScore = score
                            best = enemy
                        end
                    end
                end
            end
        end

        return best
    end

    for _, slot in ipairs({
        "e",
        "q",
    }) do
        local tool =
            abilityTool(slot)

        if tool then
            local range =
                CFG.ABILITY_RANGE_HINTS[
                    tool.Name
                ]
                or Profile.AbilityRange

            for _, attributeName in ipairs({
                "Range",
                "range",
                "CastRange",
                "castRange",
                "AbilityRange",
                "abilityRange",
            }) do
                local ok, value =
                    pcall(function()
                        return
                            tool:GetAttribute(
                                attributeName
                            )
                    end)

                if ok
                    and type(value) == "number"
                    and value > 0
                then
                    range = value
                    break
                end
            end

            local enemy =
                bestForRange(range)

            if enemy
                and Runtime.CastAbilityOnEnemy(
                    slot,
                    enemy,
                    allowGeometryDanger
                )
            then
                if Runtime.ActiveBossName then
                    Runtime.LastBossOpportunityAt =
                        now
                end

                if now
                    - Runtime.LastOpportunityAttackLog
                    >= CFG.OPPORTUNISTIC_LOG_COOLDOWN
                then
                    Runtime.LastOpportunityAttackLog =
                        now

                    logKV("OPPORTUNISTIC_ATTACK", {
                        slot = slot,
                        target =
                            enemy.Model.Name,
                        distance =
                            string.format(
                                "%.1f",
                                horizontalDistance(
                                    Runtime.Root.Position,
                                    enemy.Root.Position
                                )
                            ),
                        primary =
                            Runtime.Target
                            and Runtime.Target.Name
                            or "none",
                        dodge =
                            tostring(
                                Runtime.DodgeActive
                            ),
                    })
                end

                return true
            end
        end
    end

    return false
end

local function basicSwing(
    allowGeometryDanger
)
    local magePressure =
        Runtime.MageFreePressureActive
        and Runtime.MageFreePressureActive()

    if not CFG.AUTO_ATTACK
        or (
            Runtime.DodgeActive
            and not (
                allowGeometryDanger
                and magePressure
            )
        )
        or busyCasting()
        or not Runtime.TargetRoot
        or not Runtime.Root
    then
        return false
    end

    local now = os.clock()

    if now-Runtime.LastSwing
        < CFG.BASIC_SWING_COOLDOWN
    then
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.TargetRoot.Position,
            Runtime.Root.Position
        )

    if distance > Profile.BasicRange then
        return false
    end

    -- Survival-first melee guard:
    -- do not commit to a basic swing while a physical mob can immediately
    -- counter. Skills remain usable from range.
    if CFG.PROACTIVE_MELEE_AVOIDANCE then
        local nearestPhysical, nearestPhysicalDist =
            nearestPhysicalEnemy(Runtime.Root.Position)

        if nearestPhysical
            and nearestPhysicalDist <= CFG.MELEE_BASIC_SWING_GUARD_RADIUS
        then
            return false
        end

        if Runtime.Target and isPhysicalEnemyModel(Runtime.Target) then
            return false
        end
    end

    if activeThreatCount() > 0
        and not (
            allowGeometryDanger
            and magePressure
        )
    then
        return false
    end

    local weaponEvent =
        equippedWeaponEvent()

    if not weaponEvent then
        return false
    end

    faceTarget()

    pcall(function()
        weaponEvent:FireServer()
    end)

    local weaponUsed =
        ReplicatedStorage
        :FindFirstChild("remotes")

    weaponUsed =
        weaponUsed
        and weaponUsed:FindFirstChild(
            "weaponUsed"
        )

    if weaponUsed
        and weaponUsed:IsA("RemoteEvent")
    then
        pcall(function()
            weaponUsed:FireServer()
        end)
    end

    Runtime.LastSwing = now

    return true
end

local function attackThink(
    allowGeometryDanger
)
    if not Runtime.Root then
        return
    end

    local magePressure =
        Runtime.MageFreePressureActive
        and Runtime.MageFreePressureActive()

    if Runtime.TargetRoot
        and Runtime.TargetHumanoid
        and Runtime.TargetHumanoid.Health > 0
    then
        -- Primary target ALWAYS gets first access to both skills.
        if castAbility(
            "e",
            allowGeometryDanger
        ) then
            if magePressure
                and allowGeometryDanger
            then
                logKV("MAGE_PRESSURE_CAST", {
                    slot = "e",
                    target =
                        Runtime.Target.Name,
                    distance =
                        string.format(
                            "%.1f",
                            horizontalDistance(
                                Runtime.Root.Position,
                                Runtime.TargetRoot.Position
                            )
                        ),
                })
            end

            return
        end

        if castAbility(
            "q",
            allowGeometryDanger
        ) then
            if magePressure
                and allowGeometryDanger
            then
                logKV("MAGE_PRESSURE_CAST", {
                    slot = "q",
                    target =
                        Runtime.Target.Name,
                    distance =
                        string.format(
                            "%.1f",
                            horizontalDistance(
                                Runtime.Root.Position,
                                Runtime.TargetRoot.Position
                            )
                        ),
                })
            end

            return
        end
    end

    -- Mage-only mode is EXCLUSIVE offense:
    -- do not throw a ready skill into another enemy just because the red-line
    -- dodge temporarily placed the mage outside skill range.
    -- Keep closing/side-stepping the mage and use weapon basics when close.
    if magePressure then
        if basicSwing(
            allowGeometryDanger
        ) then
            logKV("MAGE_PRESSURE_BASIC", {
                target =
                    Runtime.Target
                    and Runtime.Target.Name
                    or "none",
                distance =
                    Runtime.TargetRoot
                    and string.format(
                        "%.1f",
                        horizontalDistance(
                            Runtime.Root.Position,
                            Runtime.TargetRoot.Position
                        )
                    )
                    or "inf",
            })
        end

        return
    end

    if Runtime.TryOpportunisticAttack(
        allowGeometryDanger
    ) then
        return
    end

    basicSwing(
        allowGeometryDanger
    )
end

local function wallEscapeThink()
    if not Runtime.Root
        or not Runtime.Humanoid
        or not Runtime.WallEscapePosition
    then
        return false
    end

    local now = os.clock()

    if now > Runtime.WallEscapeUntil then
        Runtime.WallEscapePosition = nil
        return false
    end

    local distance =
        horizontalDistance(
            Runtime.Root.Position,
            Runtime.WallEscapePosition
        )

    if distance <= 2.5 then
        Runtime.WallEscapePosition = nil
        Runtime.WallEscapeAttempts = 0
        Runtime.WallEscapeStarted = nil

        log("WALL_ESCAPE_CLEAR", "reached_open_space")

        return false
    end

    moveTo(
        Runtime.WallEscapePosition,
        "WALL_ESCAPE"
    )

    return true
end

local function safeIdleThink()
    if not Runtime.Root
        or not Runtime.Humanoid
    then
        return false
    end

    local physical, dist =
        nearestPhysicalEnemy(
            Runtime.Root.Position
        )

    -- Never stand still with a physical enemy already approaching.
    if physical and physical.Root and dist <= 42 then
        local away =
            unitHorizontal(
                Runtime.Root.Position
                - physical.Root.Position
            )

        local open =
            chooseOpenSpacePoint(
                Runtime.Root.Position,
                away
            )

        if open then
            moveTo(
                open.Position,
                "SAFE_IDLE_ESCAPE"
            )

            return true
        end
    end

    -- Even with no enemy visible, do not idle while pressed directly against
    -- a wall; step into open arena space.
    local wallClearance, openCount =
        localWallClearance(
            Runtime.Root.Position
        )

    if wallClearance < 3.5
        or openCount <= 2
    then
        local open =
            chooseOpenSpacePoint(
                Runtime.Root.Position,
                unitHorizontal(
                    Runtime.Root.CFrame.LookVector
                )
            )

        if open then
            moveTo(
                open.Position,
                "SAFE_IDLE_OPEN_SPACE"
            )

            return true
        end
    end

    return false
end

-- ============================================================
-- Stuck detection
-- ============================================================

local function stuckThink()
    if not Runtime.Root or Runtime.CompletionConfirmed then
        return
    end

    if Runtime.BossWave
        or Runtime.MageWave
        or Runtime.MovementOwner == "TRANSIT"
        or Runtime.MovementOwner == "TRANSIT_SETTLE"
        or Runtime.MovementOwner == "AZRALLIK_POCKET_HOLD"
        or Runtime.MovementOwner == "AZRALLIK_FINGER_HOLD"
        or Runtime.MovementOwner == "AZRALLIK_FINGER_PREHOLD"
        or Runtime.MovementOwner == "KOLVUMAR_SPIT_HOLD"
    then
        Runtime.LastPosition =
            Runtime.Root.Position
        Runtime.LastPositionChange =
            os.clock()
        return
    end

    local now = os.clock()
    local pos = Runtime.Root.Position

    if not Runtime.LastPosition then
        Runtime.LastPosition = pos
        Runtime.LastPositionChange = now
        return
    end

    local moved =
        horizontalDistance(
            pos,
            Runtime.LastPosition
        )

    if moved >= 1.2 then
        Runtime.LastPosition = pos
        Runtime.LastPositionChange = now

        -- Real movement means the escape worked. Reset the escalation state.
        if moved >= 2.0 then
            Runtime.WallEscapeAttempts = 0
            Runtime.WallEscapeStarted = nil
            Runtime.BossStallBreakCount = 0
        end

        return
    end

    local stuckFor =
        now - Runtime.LastPositionChange

    if stuckFor < CFG.WALL_STUCK_TRIGGER then
        return
    end

    -- Combat movement needs an actual local escape, not just a path reset.
    local reason =
        Runtime.LastMoveReason
        or "unknown"

    if Runtime.WallEscapeAttempts
        >= CFG.STALL_BREAK_AFTER_ATTEMPTS
    then
        Runtime.WallEscapeAttempts = 0
        Runtime.WallEscapeStarted = nil
        Runtime.WallEscapePosition = nil
        Runtime.PathWaypoints = nil
        Runtime.PathDestination = nil
        Runtime.ApproachWaypoints = nil
        Runtime.ApproachFallbackPosition = nil
        Runtime.LastRepath = -math.huge
        Runtime.OrbitSign *= -1

        local preferred

        if Runtime.TargetRoot then
            local toward =
                unitHorizontal(
                    Runtime.TargetRoot.Position
                    - Runtime.Root.Position
                )

            preferred =
                Vector3.new(
                    -toward.Z,
                    0,
                    toward.X
                ) * Runtime.OrbitSign
        else
            preferred =
                unitHorizontal(
                    Runtime.Root.CFrame.RightVector
                ) * Runtime.OrbitSign
        end

        Runtime.BossStallBreakCount += 1

        if Runtime.TargetRoot
            and activeThreatCount() == 0
        then
            preferred =
                unitHorizontal(
                    Runtime.TargetRoot.Position
                    - Runtime.Root.Position
                )
        end

        local minRadius =
            math.min(
                CFG.BOSS_STALL_RECOVERY_MAX_RADIUS,
                CFG.BOSS_STALL_RECOVERY_MIN_RADIUS
                + (
                    Runtime.BossStallBreakCount - 1
                ) * 6
            )

        local open =
            chooseOpenSpacePoint(
                Runtime.Root.Position,
                preferred,
                minRadius
            )

        if open then
            moveTo(
                open.Position,
                "STALL_BREAK_PROGRESS"
            )
        end

        Runtime.LastPositionChange = now

        if now - Runtime.LastBossStallLog
            >= CFG.BOSS_STALL_LOG_COOLDOWN
        then
            Runtime.LastBossStallLog = now

            logKV("BOSS_PROGRESS_RECOVERY", {
                reason = tostring(reason),
                target = Runtime.Target
                    and Runtime.Target.Name
                    or "nil",
                room = Runtime.CurrentRoomIndex,
                attempt =
                    Runtime.BossStallBreakCount,
                radius =
                    open
                    and string.format(
                        "%.1f",
                        open.Radius
                    )
                    or "none",
                position =
                    open
                    and vec(open.Position)
                    or "none",
            })
        end

        return
    end

    if beginWallEscape(reason) then
        Runtime.LastPositionChange = now
        Runtime.PathWaypoints = nil
        Runtime.LastRepath = -math.huge

        return
    end

    -- Extremely rare final fallback: if we're physically wedged for several
    -- seconds AND danger is present, use a tiny bounded nudge into the already
    -- selected open-space point. This shares the global teleport budget.
    local escapeAge =
        Runtime.WallEscapeStarted
        and (now - Runtime.WallEscapeStarted)
        or 0

    if escapeAge >= CFG.WALL_HARD_STUCK_SECONDS
        and Runtime.WallEscapePosition
        and teleportBudgetAvailable(now)
    then
        local penalty, inside =
            pointDanger(Runtime.Root.Position)

        local physical, physicalDist =
            nearestPhysicalEnemy(Runtime.Root.Position)

        local immediateDanger =
            inside > 0
            or (
                physical
                and physicalDist <= CFG.MELEE_CRITICAL_RADIUS + 2
            )

        if immediateDanger then
            local plan = {
                Position = Runtime.WallEscapePosition,
                Radius = horizontalDistance(
                    Runtime.Root.Position,
                    Runtime.WallEscapePosition
                ),
                Label = "wall_nudge",
                Source = "wall_stuck",
                Clearance = 0,
            }

            if doFastShift(
                plan,
                CFG.WALL_NUDGE_MAX,
                CFG.TELEPORT_GLOBAL_COOLDOWN,
                "WALL_NUDGE",
                true
            ) then
                Runtime.LastPositionChange = now
                Runtime.WallEscapeStarted = nil
                Runtime.WallEscapeAttempts = 0
            end
        end
    end
end

-- ============================================================
-- Main controller
-- ============================================================

local function controllerStep()
    if not CFG.ENABLED then
        return
    end

    local char,hum,root = getCharacter()

    if not char
        or not hum
        or hum.Health <= 0
        or not root
    then
        return
    end

    Runtime.Character = char
    Runtime.Humanoid = hum
    Runtime.Root = root

    if updateSafeAnchor() then
        return
    end

    updateAimLock()

    local now = os.clock()

    if now-Runtime.LastTargetScan
        >= CFG.TARGET_REFRESH
    then
        Runtime.LastTargetScan = now
        rebuildEnemyCache()
        refreshBossState()

        selectTarget()
        refreshAnimators()
    end

    -- Authoritative completion is the only point where V7 fully stops combat.
    if Runtime.CompletionConfirmed then
        if not Runtime.CompletionWaitLogged then
            Runtime.CompletionWaitLogged = true
            logKV("COMPLETION_WAIT", {
                source = tostring(Runtime.CompletionSource),
            })
        end

        clearDodge("completion_confirmed")
        Runtime.PathWaypoints = nil
        Runtime.PathDestination = nil
        Runtime.Target = nil
        Runtime.TargetHumanoid = nil
        Runtime.TargetRoot = nil

        pcall(function()
            Runtime.Humanoid:Move(Vector3.zero, false)
        end)

        return
    end

    -- Final boss is gone but completion has NOT been confirmed yet.
    -- Keep killing any remaining encounter adds (especially Blood Minions).
    -- If nothing remains, simply hold; never path back to room999.
    if Runtime.FinalBossDefeated
        and (
            not Runtime.TargetRoot
            or not Runtime.TargetHumanoid
            or Runtime.TargetHumanoid.Health <= 0
        )
    then
        if not Runtime.CompletionWaitLogged then
            Runtime.CompletionWaitLogged = true
            log("POST_BOSS_CLEANUP", "waiting_for_adds_or_completion_signal")
        end

        clearDodge("post_boss_no_target")
        Runtime.PathWaypoints = nil
        Runtime.PathDestination = nil

        if safeIdleThink() then
            stuckThink()
            return
        end

        -- No immediate enemy and already in open space: hold normally while
        -- waiting for the authoritative completion signal.
        pcall(function()
            Runtime.Humanoid:Move(Vector3.zero, false)
        end)

        return
    end

    if Runtime.FinalBossDefeated
        and Runtime.TargetRoot
        and Runtime.TargetHumanoid
        and Runtime.TargetHumanoid.Health > 0
    then
        Runtime.CompletionWaitLogged = false
    end

    if Runtime.TransitTween
        and transitCombatShouldStop()
    then
        stopTransitTween("combat_started")
    end

    -- 1. Highest priority: survival movement.
    -- V6 may still fire a ready skill while kiting if the current position is
    -- outside real attack geometry and contact is not imminent.
    if dodgeThink() then
        if CFG.AUTO_ABILITIES then
            -- Movement already owns the escape path. Keep firing instant skills
            -- through mage/boss red-line movement when there is no immediate
            -- physical collision risk.
            attackThink(true)
        end

        if not Runtime.BossWave
            and not Runtime.MageWave
        then
            stuckThink()
        end

        return
    end

    -- 2. If movement got pinned against geometry, commit briefly to the
    -- selected open-space escape. Attacks can still fire while moving.
    if wallEscapeThink() then
        attackThink()
        stuckThink()
        return
    end

    -- 3. Fight current enemy using ordinary Humanoid/path movement.
    -- V7.7 intentionally does not use forward CFrame tween transit.
    if Runtime.TargetRoot
        and Runtime.TargetHumanoid
        and Runtime.TargetHumanoid.Health > 0
    then
        combatMovement()
        attackThink()
        stuckThink()
        return
    end

    -- 4. Move to next room.
    if navigationThink() then
        if Runtime.MovementOwner ~= "TRANSIT"
            and Runtime.MovementOwner ~= "TRANSIT_SETTLE"
        then
            stuckThink()
        end

        return
    end

    -- 5. Nothing to navigate to yet: do not freeze beside a wall or a
    -- non-telegraphed physical enemy while waiting for the next state.
    safeIdleThink()
    stuckThink()
end

Runtime.BossHeartbeatThink = function(now)
    if not Runtime.ActiveBossName
        or not Runtime.Root
        or not Runtime.Humanoid
    then
        return
    end

    if now - Runtime.LastBossHeartbeat
        < CFG.BOSS_HEARTBEAT_INTERVAL
    then
        return
    end

    Runtime.LastBossHeartbeat = now

    local bossHp = "nil"

    if Runtime.ActiveBossModel then
        local hum =
            Runtime.ActiveBossModel:FindFirstChildOfClass(
                "Humanoid"
            )

        if hum then
            bossHp =
                string.format(
                    "%.0f",
                    hum.Health
                )
        end
    end

    local lastShiftAge =
        Runtime.LastTeleportAt == -math.huge
        and "inf"
        or string.format(
            "%.2f",
            now - Runtime.LastTeleportAt
        )

    logKV("BOSS_HEARTBEAT", {
        boss = Runtime.ActiveBossName,
        boss_hp = bossHp,
        player_hp = string.format(
            "%.0f",
            Runtime.Humanoid.Health
        ),
        position = vec(Runtime.Root.Position),
        room = Runtime.CurrentRoomIndex,
        wave =
            Runtime.BossWave
            and Runtime.BossWave.Id
            or "none",
        shift_age = lastShiftAge,
        shift_total = Runtime.TeleportTotal,
        last_shift =
            tostring(
                Runtime.LastTeleportTag
                or "none"
            ),
        threats = activeThreatCount(),
        movement_owner =
            tostring(
                Runtime.MovementOwner
                or "NONE"
            ),
        dodge_label =
            Runtime.LastDodgeMoveLabel
            or "none",
        dodge_remaining =
            Runtime.LastDodgeMoveTarget
            and string.format(
                "%.2f",
                horizontalDistance(
                    Runtime.Root.Position,
                    Runtime.LastDodgeMoveTarget
                )
            )
            or "none",
        speed =
            string.format(
                "%.2f",
                horizontal(
                    Runtime.Root.AssemblyLinearVelocity
                ).Magnitude
            ),
    })
end


connect(
    RunService.Heartbeat,
    function()
        if not Runtime.Alive
            or Runtime.HaltForDisconnect
        then
            return
        end

        local now = os.clock()

        Runtime.BossHeartbeatThink(now)

        if now-Runtime.LastThink
            >= CFG.THINK_INTERVAL
        then
            Runtime.LastThink = now

            local ok,err =
                pcall(controllerStep)

            if not ok then
                log("ERROR",tostring(err))
            end
        end

        if now-Runtime.LastFlush
            >= CFG.FLUSH_INTERVAL
        then
            Runtime.LastFlush = now
            flush()
        end
    end
)

-- ============================================================
-- Stop / public API
-- ============================================================

Runtime.Stop = function(reason)
    if not Runtime.Alive then return end

    Runtime.Alive = false

    if stopTransitTween then
        stopTransitTween("runtime_stop")
    end

    if Runtime.Humanoid then
        pcall(function()
            Runtime.Humanoid:Move(
                Vector3.zero,
                false
            )

            if Runtime.AimPreviousAutoRotate ~= nil then
                Runtime.Humanoid.AutoRotate =
                    Runtime.AimPreviousAutoRotate
            else
                Runtime.Humanoid.AutoRotate = true
            end
        end)
    end

    logKV("SUMMARY", {
        reason = reason or "manual",
        style = CFG.STYLE,
        dodges = Runtime.DodgeCount,
        micro_dodges = Runtime.MicroCount,
        runtime = string.format(
            "%.1f",
            os.clock()-bootClock
        ),
    })

    flush()
    disconnectAll()

    if ENV[RUNTIME_KEY] == Runtime then
        ENV[RUNTIME_KEY] = nil
    end
end

ENV.DQRUnderworld = {
    Version = "V10.3-Overgrowth-HardClear-Kolvumar-Rollback-Azrallik-Combo",
    Status = function()
        return {
            Style = CFG.STYLE,
            Target =
                Runtime.Target
                and Runtime.Target.Name
                or nil,
            CurrentRoom = Runtime.CurrentRoomIndex,
            Threats = activeThreatCount(),
            Dodges = Runtime.DodgeCount,
            MicroDodges = Runtime.MicroCount,
            Boss = Runtime.ActiveBossName,
            BossWave = Runtime.BossWave and Runtime.BossWave.Id or nil,
            MageWave = Runtime.MageWave and Runtime.MageWave.Id or nil,
            FinalBossDefeated = Runtime.FinalBossDefeated,
            CompletionConfirmed = Runtime.CompletionConfirmed,
            CompletionSource = Runtime.CompletionSource,
            PhysicalKiting = Runtime.PhysicalKiting,
            WallEscapeActive = Runtime.WallEscapePosition ~= nil,
            ApproachActive =
                Runtime.ApproachWaypoints ~= nil
                or Runtime.ApproachFallbackPosition ~= nil,
            TransitTweenActive =
                Runtime.TransitTween ~= nil
                and not Runtime.TransitTweenDone,
            OvergrowthHistory = #Runtime.OvergrowthSpikeHistory,
            MovementOwner = Runtime.MovementOwner,
            TransitSnapbacks = Runtime.TransitSnapbackCount,
            TransitDisabledRoom = Runtime.TransitDisabledRoom,
            TeleportTotal = Runtime.TeleportTotal,
            LastTeleportTag = Runtime.LastTeleportTag,
            LastTeleportAge =
                Runtime.LastTeleportAt == -math.huge
                and math.huge
                or os.clock() - Runtime.LastTeleportAt,
            LastSafePosition =
                Runtime.LastSafePosition
                and vec(Runtime.LastSafePosition)
                or nil,
            AzrallikPocket =
                Runtime.BossWave
                and Runtime.BossWave.BeamPocket
                and vec(Runtime.BossWave.BeamPocket)
                or nil,
            AzrallikPocketLocked =
                Runtime.BossWave
                and Runtime.BossWave.BeamPocketLocked
                or false,
            AzrallikHeartPhase =
                Runtime.AzrallikHeartPhaseActive,
            AzrallikHeartTarget =
                Runtime.AzrallikHeartModel
                and Runtime.AzrallikHeartModel.Name
                or nil,
            LastMoveReason = Runtime.LastMoveReason,
            TeleportsInWindow = #Runtime.TeleportHistory,
            Log = LOG_PATH,
        }
    end,

    SetStyle = function(style)
        if STYLES[style] then
            CFG.STYLE = style
            Profile = STYLES[style]

            log("STYLE",style)

            return true
        end

        return false
    end,

    Stop = function()
        Runtime.Stop("user")
    end,
}

logKV("START", {
    style = CFG.STYLE,
    place = game.PlaceId,
    expected_gameplay_place = 85776757589518,
    auto_dodge = CFG.AUTO_DODGE,
    auto_attack = CFG.AUTO_ATTACK,
    auto_abilities = CFG.AUTO_ABILITIES,
    auto_navigation = CFG.AUTO_NAVIGATION,
    optimized_planner = true,
    predictive_melee = CFG.PROACTIVE_MELEE_AVOIDANCE,
    melee_soft_radius = CFG.MELEE_SOFT_RADIUS,
    line_fast_shift = CFG.LARGE_LINE_FAST_SHIFT,
    aim_lock = CFG.ABILITY_AIM_LOCK_TIME,
    melee_critical_radius = CFG.MELEE_CRITICAL_RADIUS,
    candidate_directions = CFG.CANDIDATE_DIRECTIONS,
    candidate_radii = #CFG.CANDIDATE_RADII,
    mage_wave_grouping = true,
    boss_specific_range = true,
    final_boss_completion_state = true,
    physical_pressure_mode = true,
    proximity_is_not_dodge = true,
    authoritative_completion = true,
    wall_aware_movement = true,
    open_space_recovery = true,
    close_physical_target_override = true,
    progressive_boss_approach = true,
    dynamic_effects_not_walls = true,
    hazard_aware_combat_route = true,
    kolvumar_nonred_guard = true,
    wave_physical_merge = true,
    azrallik_sweep_prediction = true,
    room_transit_tween = false,
    overgrowth_larger_single_escape = true,
    overgrowth_sequence_prediction = true,
    azrallik_early_sweep_escape = true,
    long_combat_transit_tween = false,
    gate_waiting = true,
    earlier_fast_physical_escape = true,
    safe_waypoint_validation = true,
    void_recovery = true,
    snapback_detection = true,
    stale_moveto_cancel = true,
    boss_wave_movement_ownership = true,
    azrallik_future_gap_solver = true,
    strict_encounter_targeting = true,
    future_room999_rejected = true,
    boss_target_lock = true,
    tween_disabled = true,
    bounded_stall_recovery = true,
    overgrowth_direction_lock = true,
    overgrowth_forward_only = true,
    longline_sequence_separated = true,
    strict_red_route_gate = true,
    teleport_global_cooldown = CFG.TELEPORT_GLOBAL_COOLDOWN,
    teleport_governor = true,
    overgrowth_one_shift_per_wave = true,
    overgrowth_generic_narrow_shift_disabled = true,
    overgrowth_backtrack_guard = true,
    boss_heartbeat = true,
    azrallik_safe_pocket = true,
    azrallik_aura_scan = true,
    azrallik_pocket_hold = true,
    azrallik_beam_teleport_disabled = CFG.AZRALLIK_BEAM_NO_TELEPORT,
    azrallik_dynamic_lattice = true,
    azrallik_local_pocket_cap = CFG.AZRALLIK_BEAM_MAX_POCKET_TRAVEL,
    azrallik_safe_tail_advance = true,
    azrallik_boss_target_lock = true,
    azrallik_blood_minion_emergency_range = CFG.AZRALLIK_BLOOD_MINION_EMERGENCY_RANGE,
    overgrowth_first_edge_escape = true,
    overgrowth_longline_exact_gap = true,
    kolvumar_virtual_wave_hold = true,
    azrallik_lane_slide = true,
    azrallik_heart_phase_lock = CFG.AZRALLIK_HEART_PHASE_LOCK,
    azrallik_safe_pressure = CFG.AZRALLIK_SAFE_PRESSURE_ENABLED,
    exact_safe_lane_sampling = true,
    beam_spawn_quiet = CFG.AZRALLIK_BEAM_SPAWN_QUIET,
    beam_post_spawn_danger = CFG.AZRALLIK_BEAM_POST_SPAWN_DANGER,
    safe_pressure_clearance_retention = true,
    overgrowth_edge_direct_drive = false,
    overgrowth_edge_wall_aware_commit = true,
    overgrowth_edge_stall_rescue = true,
    overgrowth_longline_inside_rescue = true,
    dodge_move_watchdog = true,
    teleport_3s_governor = true,
    azrallik_horizontal_generic_teleport_disabled = true,
    azrallik_early_beam_guard = true,
    azrallik_spread_larger_single_escape = true,
    demon_warrior_final_tuning = true,
    adaptive_survival = CFG.ADAPTIVE_SURVIVAL,
    fragile_max_health = CFG.FRAGILE_MAX_HEALTH,
    nearby_blood_minion_pressure = true,
    overgrowth_short_forward_commit = true,
    overgrowth_sequence_shift_max = CFG.OVERGROWTH_WAVE_TELEPORT_MAX,
    azrallik_finger_hold = true,
    overgrowth_first_strip_proactive = true,
    overgrowth_longline_physical_aware = true,
    kolvumar_per_spit_rescue = true,
    physical_emergency_shift_geometry_independent = true,
    azrallik_large_invalid_destination_fallback = true,
    final_boss_post_death_hazard_grace = CFG.FINAL_BOSS_POST_DEATH_HAZARD_GRACE,
    boss_add_intercept = CFG.BOSS_ADD_INTERCEPT_ENABLED,
    boss_majority_focus = true,
    boss_hard_priority = true,
    boss_add_requires_ready_skill = true,
    heart_range_fixed = CFG.AZRALLIK_HEART_ATTACK_RANGE,
    kolvumar_pressure_range_fixed = CFG.KOLVUMAR_DESIRED_RANGE,
    strongest_efficient_floor_sweep = true,
    boss_dps_range_retention = true,
    attack_while_dodging = CFG.DODGE_CAST_ENABLED,
    opportunistic_attack_only = CFG.OPPORTUNISTIC_ATTACK_ENABLED,
    mage_free_shot_enabled = true,
    mage_free_pressure = CFG.MAGE_FREE_PRESSURE_ENABLED,
    mage_safe_window_attack = CFG.MAGE_SAFE_WINDOW_ATTACK,
    mage_minimal_dodge = true,
    physical_pressure_handoff = CFG.PHYSICAL_DODGE_HANDOFF_ENABLED,
    physical_handoff_panic_radius = CFG.PHYSICAL_DODGE_PANIC_RADIUS,
    physical_handoff_near_radius = CFG.PHYSICAL_DODGE_PANIC_NEAR_RADIUS,
    physical_handoff_min_closing = CFG.PHYSICAL_DODGE_PANIC_MIN_CLOSING,
    kolvumar_stack_count_fixed = true,
    kolvumar_live_stack_recount = true,
    kolvumar_stall_recovery_commit =
        CFG.KOLVUMAR_STALL_RECOVERY_COMMIT_ENABLED,
    kolvumar_v101_replan_restored = true,
    kolvumar_post_rescue_motion = CFG.KOLVUMAR_POST_RESCUE_MOTION_TIME,
    azrallik_spread_prediction = true,
    azrallik_spread_tell_anim = CFG.AZRALLIK_SPREAD_TELL_ANIM,
    azrallik_spread_expected_delay = CFG.AZRALLIK_SPREAD_EXPECTED_DELAY,
    azrallik_spread_local_gap = true,
    azrallik_combined_finger_spread = CFG.AZRALLIK_COMBINED_FINGER_SPREAD_ENABLED,
    overgrowth_edge_margin = CFG.OVERGROWTH_FIRST_EDGE_MARGIN,
    overgrowth_edge_follow = CFG.OVERGROWTH_EDGE_FOLLOW_ENABLED,
    overgrowth_edge_follow_time = CFG.OVERGROWTH_EDGE_FOLLOW_TIME,
    local_finish = CFG.LOCAL_FINISH_ENABLED,
    local_finish_ratio = CFG.LOCAL_FINISH_HP_RATIO,
    safe_local_boss_short_skill = true,
    mage_primary_cast_exclusive = true,
    mage_basic_while_dodging = true,
    mage_free_pressure_range = CFG.MAGE_FREE_PRESSURE_DESIRED_RANGE,
    mage_free_pressure_guard = CFG.MAGE_FREE_PRESSURE_PHYSICAL_GUARD,
    mage_wave_dps_retention = CFG.MAGE_FREE_PRESSURE_WAVE_TARGET_WEIGHT,
    primary_target_never_repathed_for_opportunity = true,
    physical_objective_leash = CFG.PHYSICAL_TARGET_LEASH_ENABLED,
    ground_slam_range_calibrated = CFG.ABILITY_RANGE_HINTS["Ground Slam"],
    boss_add_burst_max = CFG.BOSS_ADD_BURST_MAX,
    boss_add_burst_cooldown = CFG.BOSS_ADD_BURST_COOLDOWN,
    strongest_first_floor_targeting = true,
    boss_add_intercept_range = CFG.BOSS_ADD_INTERCEPT_RANGE,
    blood_minion_wave_prediction = CFG.BLOOD_MINION_WAVE_PREDICT_TIME,
    post_shift_continuation = CFG.POST_SHIFT_CONTINUE_ENABLED,
    overgrowth_local_sequence_steps = true,
    kolvumar_inside_spit_rescue = true,
    room999_transition_guard = true,
    post_shift_local_step = CFG.POST_SHIFT_CONTINUE_MAX_STEP,
    kolvumar_union_safe_pocket = true,
    kolvumar_desired_range = CFG.KOLVUMAR_DESIRED_RANGE,
    kolvumar_range_bug_fixed = true,
    generic_boss_add_intercept = true,
    boss_post_cleanup = CFG.BOSS_POST_CLEANUP_ENABLED,
    sticky_target_lock = CFG.TARGET_LOCK_ENABLED,
    target_lock_min_seconds = CFG.TARGET_LOCK_MIN_SECONDS,
    ability_result_diagnostic = CFG.ABILITY_RESULT_DIAGNOSTIC,
    mixed_skill_ranges = true,
    empirically_calibrated_skill_ranges = true,
    boss_short_skill_chase = false,
    boss_range_overgrowth = CFG.BOSS_DESIRED_RANGE["Demonic Overgrowth"],
    boss_range_kolvumar = CFG.BOSS_DESIRED_RANGE["Kolvumar"],
    boss_range_azrallik = CFG.BOSS_DESIRED_RANGE["Demon Lord Azrallik"],
    tactical_short_skill_staging = CFG.SHORT_SKILL_STAGING_ENABLED,
    short_skill_stage_slot = CFG.SHORT_SKILL_STAGING_SLOT,
    ground_slam_range_hint = CFG.ABILITY_RANGE_HINTS["Ground Slam"],
    infernal_strike_range_hint = CFG.ABILITY_RANGE_HINTS["Infernal Strike"],
    ability_result_delay = CFG.ABILITY_RESULT_DELAY,
    physical_target_latch = CFG.TARGET_LOCK_PHYSICAL_HOLD_RANGE,
    azrallik_direct_shift_disabled = true,
    halt_after_disconnect_signal = true,
    azrallik_finger_animation_premove = true,
    kolvumar_shift_hp_ratio = CFG.KOLVUMAR_SPIT_SHIFT_HP_RATIO,
    kolvumar_shift_min_stack = CFG.KOLVUMAR_SPIT_SHIFT_MIN_STACK,
    kolvumar_generic_wave_shift = CFG.KOLVUMAR_GENERIC_WAVE_SHIFT,
    target_lock_local_hold = CFG.TARGET_LOCK_LOCAL_HOLD_DISTANCE,
    kolvumar_static_hold_removed = true,
    kolvumar_post_escape_hold = CFG.KOLVUMAR_SPIT_POST_ESCAPE_HOLD,
    azrallik_shift_cap = CFG.AZRALLIK_WAVE_TELEPORT_MAX,
    progressive_boss_stall_recovery = true,
    disconnect_telemetry = true,
    invalid_dodge_destination_fallback = true,
})

log(
    "UNDERWORLD_KNOWN_ATTACKS",
    "npcMageSpikes,bigMageBeam,spikePrecast,overgrowthLongLineSpikes,kolvumarSpit,horizontalBeam,azrallikPunch,azrallikPunchSpread,fingerBlastHit"
)

flush()