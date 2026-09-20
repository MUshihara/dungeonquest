-- DQR modular runtime: core/Config.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Config
-- ============================================================

CFG = {
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

    -- Samurai Swordsman's confirmed attack animation arrives essentially at
    -- impact in V1.1, so animation prediction cannot be the primary defense.
    -- Keep extra ordinary-walking space from Samurai physical enemies instead.
    SAMURAI_MELEE_SOFT_RADIUS = 22.0,
    SAMURAI_MELEE_RELEASE_RADIUS = 28.0,
    SAMURAI_MELEE_CRITICAL_RADIUS = 14.0,
    SAMURAI_WAVE_PHYSICAL_HARD_RADIUS = 24.0,
    SAMURAI_WAVE_PHYSICAL_SOFT_RADIUS = 34.0,
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

    -- Multi-level encounter navigation.
    -- Ordinary combat remains flat. A target on a different floor is not
    -- considered attack-reachable until a PathfindingService route climbs to
    -- approximately the same Y level.
    TARGET_LEVEL_VERTICAL_TOLERANCE = 14.0,
    LEVEL_ROUTE_MAX_WAYPOINT_VERTICAL_DELTA = 22.0,
    LEVEL_ROUTE_LOG_COOLDOWN = 0.80,

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
        -- Samurai Palace V1: use the calibrated Physical damage envelope from
        -- V10.x, but keep every boss-specific distance world-local.
        ["Sanada Yukimura"] = 26.0,
        ["Ancient Golem Guardian"] = 28.0,
        ["Miyamoto Musashi"] = 28.0,

        -- Dormant reference entries retained so the shared helper code remains
        -- structurally compatible with the V10.x source.
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
        -- Conservative first-pass walking deadlines. Golem rockshatter gets
        -- its own predictive premove from the measured animation tell.
        ["Sanada Yukimura"] = 0.72,
        ["Ancient Golem Guardian"] = 0.85,
        ["Miyamoto Musashi"] = 0.72,

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

        -- These were the observed Samurai Palace test loadout. Keep the V10.x
        -- Physical fallback if the user swaps skills later.
        ["Lava Lash"] = 55.0,
        ["Rending Slice"] = 55.0,
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
        -- Only stage a short skill when the boss is already local and there is
        -- no active geometry. Miyamoto stays ranged-first in V1.
        ["Sanada Yukimura"] = true,
        ["Ancient Golem Guardian"] = true,
        ["Miyamoto Musashi"] = false,

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

    -- Samurai Palace predictive tells measured from the full recon.
    GOLEM_SHATTER_TELL_ANIM = "rbxassetid://94282152705851",
    GOLEM_SHATTER_EXPECTED_MIN = 1.25,
    GOLEM_SHATTER_EXPECTED_MAX = 1.61,
    GOLEM_SHATTER_PREMOVE_END = 1.12,
    GOLEM_SHATTER_PREMOVE_STEPS = {8, 10, 12, 14, 16},
    GOLEM_SHATTER_LOG_COOLDOWN = 0.55,

    GOLEM_ROCK_TELL_ANIM = "rbxassetid://119729303097590",

    -- Small thrown rocks disappear roughly when their delayed explosion is
    -- about to occur. Keep the landing zones live slightly beyond the rock.
    GOLEM_SMALL_LANDING_RADIUS = 15.5,
    GOLEM_SMALL_LANDING_LIFETIME = 1.70,

    -- Main thrown rock explodes about 1.85s after the tell/landing marker.
    -- Keep its landing footprint dangerous before the explosion VFX appears.
    GOLEM_MAIN_LANDING_RADIUS = 19.0,
    GOLEM_MAIN_LANDING_LIFETIME = 2.35,

    SAMURAI_LOCAL_GAP_RADII = {4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24},
    SAMURAI_LOCAL_GAP_HOLD_CLEARANCE = 6.0,
    SAMURAI_LOCAL_GAP_ROUTE_MAX = 4200,

    -- Local-gap safety must include physical adds, not red geometry alone.
    -- This specifically prevents Sanada crossShuriken / Elite Swordsman and
    -- Miyamoto / Ultimate Swordsman overlap deaths seen in Modular V1.
    SAMURAI_LOCAL_GAP_PHYSICAL_WEIGHT = 1.0,

    -- V1.4: once a boss mechanic has a safe local pocket, commit to that
    -- pocket for the life of the same boss wave. Replan only if new geometry
    -- actually invalidates it or a physical add occupies it.
    SAMURAI_COMMITTED_GAP_MAX_RETURN = 30.0,
    SANADA_COMMITTED_GAP_MIN_CLEARANCE = 5.0,
    GOLEM_COMMITTED_GAP_MIN_CLEARANCE = 5.0,
    MIYAMOTO_COMMITTED_GAP_MIN_CLEARANCE = 7.0,

    -- V1.3: boss-wave movement must preserve DPS range. V1.2's old local-gap
    -- score penalized moving inward and could walk Sanada 100-150 studs away.
    SAMURAI_BOSS_GAP_MAX_HOLD_EXTRA = 10.0,
    SAMURAI_BOSS_GAP_RANGE_WEIGHT = 520.0,
    SAMURAI_BOSS_GAP_RETREAT_WEIGHT = 900.0,
    SAMURAI_BOSS_GAP_APPROACH_REWARD = 420.0,
    SAMURAI_BOSS_GAP_HARD_LEASH = 72.0,

    -- Threat geometry is 3D. Upstairs boss hazards must not control a player
    -- standing ~58 studs below them during a legitimate floor transition.
    THREAT_VERTICAL_MARGIN = 2.0,
    VIRTUAL_THREAT_VERTICAL_MAX = 24.0,

    -- Miyamoto can stack doubleFlameBeam with 39x39 flameShurikenHit circles
    -- and 150-stud flameBeam lines. During that dense overlap require a larger
    -- true clearance and permit a slightly wider route-safe local search.
    MIYAMOTO_DENSE_GAP_HOLD_CLEARANCE = 12.0,
    MIYAMOTO_DENSE_GAP_MIN_CLEARANCE = 6.0,
    MIYAMOTO_DENSE_GAP_RADII = {4, 6, 8, 10, 12, 14, 16, 18, 22, 26},

    -- The cyclone contains dozens of crescent parts but is one encounter
    -- hazard. Collapse it to one moving radial zone and keep dodge solutions
    -- inside the observed boss arena rather than drifting 130+ studs away.
    MIYAMOTO_CYCLONE_RADIUS = 30.0,
    MIYAMOTO_CYCLONE_LIFETIME = 3.80,
    MIYAMOTO_ARENA_LEASH = 82.0,
    MIYAMOTO_ARENA_LEASH_PENALTY = 9000.0,

    -- Server->client flameBeams warning repeatedly precedes real beam geometry.
    -- Use only walking to pre-move laterally; real geometry still owns the
    -- subsequent committed pocket.
    MIYAMOTO_BEAM_PREMOVE_WINDOW = 0.72,
    MIYAMOTO_BEAM_PREMOVE_STEPS = {6, 8, 10},
    MIYAMOTO_BEAM_PREMOVE_ROUTE_MAX = 4200,
    MIYAMOTO_BEAM_PREMOVE_RANGE_WEIGHT = 260.0,

    SHURIKEN_THROWER_ATTACK_ANIM = "rbxassetid://115248681546243",

    -- Full Modular V1 runs confirmed this as the actual close melee swing.
    -- 110763320481519 was an earlier unconfirmed/spawn-like observation.
    SAMURAI_SWORDSMAN_ATTACK_ANIM = "rbxassetid://107260711747781",

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



-- Active world may override shared knobs without duplicating the controller.
if DQR_WORLD and type(DQR_WORLD.Config) == "table" then
    for key, value in pairs(DQR_WORLD.Config) do
        CFG[key] = value
    end
end
