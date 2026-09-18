# Dungeon Quest Reborn — Underworld Master Knowledge

Updated: 2026-09-19
Repository: MUshihara/dungeonquest
Branch: main
Status: Underworld research and combat controller are mature enough to use as the reference implementation for future DQR worlds.

## 1. Purpose

This document is the durable project memory for the Dungeon Quest Reborn automation work done for Serenity Hub.

The working philosophy is evidence-first:
- inspect the actual game state before assuming mechanics;
- use passive reconnaissance, legitimate replicated state, UI state, attributes, Workspace attack geometry, and validated remotes/modules;
- one runtime owner;
- one physical movement owner;
- explicit combat / room / boss state;
- attack while dodging when safe;
- avoid per-frame spam, repeated require, hot full-Workspace scans, duplicate listeners, and duplicate runtime owners;
- never invent remote signatures;
- never add anti-cheat bypass, identity spoofing, hidden/admin remotes, blind remote spam, anti-kick hooks, or network ownership bypass.

The user values speed and automation quality, but not at the cost of unstable movement or fake “smart” behavior that only dodges while DPS stops.

## 2. Game identity and topology

Root/lobby PlaceId:
77649408247578

UniverseId:
9931749389

Shared battle PlaceId used by old dungeons:
85776757589518

Known accessible dungeon progression during this work:
- Desert Temple
- Winter Outpost
- Pirate Island
- King’s Castle
- The Underworld

Lobby remotes validated:
createLobby:InvokeServer(dungeon, difficulty, levelReq, hardcore, private, waveDefence)
startDungeon:FireServer()

Authoritative completion source:
ReplicatedStorage.remotes.loadCompleteGui

GUI fallback phrases:
- DUNGEON COMPLETED
- DUNGEON COMPLETE

Do not infer completion merely from boss disappearance.

## 3. Canonical architecture

Preferred architecture:

DungeonController
  -> RoomController
  -> TargetController
  -> CombatController
  -> ThreatEngine
  -> DodgePlanner
  -> MovementController
  -> CompletionController
  -> DiagnosticLogger

Important rule:
There must be only one MovementController that owns physical movement decisions.

Movement priority model used conceptually:
- lethal emergency: 100
- boss-specific emergency: 90
- active AoE / geometry: 80
- tactical reposition: 60
- attack spacing: 40
- next enemy / room transit: 20

Boss modules should return movement / target intents rather than directly fighting each other for CFrame or MoveTo ownership.

## 4. Combat model

Combat loop:

SCAN
-> SELECT TARGET
-> APPROACH / KITE
-> ATTACK
-> READ OR PREDICT ATTACK
-> IF SAFE: KEEP ATTACKING
-> IF UNSAFE: BEST ESCAPE
-> WALK / STRAFE FIRST
-> BOUNDED SHIFT ONLY WHEN NECESSARY
-> REPOSITION
-> RE-ENGAGE

The central design lesson from the Underworld project:
Dodging and attacking must not be mutually exclusive.

Mage example:
- mage proximity is not inherently dangerous;
- the red line / beam geometry is dangerous;
- if no physical attacker is actually close, stay on the mage, attack, and sidestep the geometry;
- do not run away merely because a mage attack object exists.

Physical enemy example:
- proximity and closing speed matter;
- normal pressure should be handled by kiting / pressure movement;
- full emergency dodge should be reserved for true panic, actual attack virtual threat, or very short TTC.

## 5. Ability / weapon observations

Ability tools use:
- abilitySlot.Value == "q" or "e"
- localEvent:Fire()
- cooldown attributes
- busyCasting state

Basic weapon attack observed through:
- accessory RemoteEvent
- remotes.weaponUsed:FireServer()

Observed loadouts changed during testing. The most important lesson is to calibrate by evidence rather than assume every skill has the same range.

Strong range findings:
- Ground Slam: genuinely short; useful envelope around 9–13 studs, configured around 12.5–14 in later builds.
- Infernal Strike: reliable inside about 30 studs; 50–55 was a bad assumption and produced repeated zero-damage samples.
- Lava Lash appeared as Q in later runs and could cast around 55 studs; exact effective damage range should still be validated per world/loadout.

Ability result telemetry is suggestive, not perfectly causal. HP delta after 0.95 sec can include other damage sources.

## 6. Underworld rooms and bosses

Important room landmarks:
- rooms 1–3: ordinary combat
- room 4: Demonic Overgrowth
- room 8: Kolvumar
- bossRoom / room 999: Demon Lord Azrallik

Special adds:
- Blood Minion
- Azrallik’s Heart

Room 999 must be scoped carefully so future-room enemies do not steal targets before the encounter is actually active.

## 7. Known Underworld attacks / geometry

Known attack names:
- npcMageSpikes
- bigMageBeam
- spikePrecast
- overgrowthLongLineSpikes
- kolvumarSpit
- horizontalBeam
- azrallikPunch
- azrallikPunchSpread
- fingerBlastHit

Useful approximate geometry:
- npcMageSpikes active: about 60.4 x 52.55 x 6
- overgrowthLongLineSpikes: about 250.95 studs long
- horizontalBeam precast: about 250.95 x 1.13 x 16.31
- horizontalBeam active: about 170 x 87.99 x 16.31
- spikePrecast: about 13.77 x 5.21 x 160
- bigMageBeam: about 25 x 25 x 25
- azrallikPunchSpread active: about 270 x 33.97 x 8
- Kolvumar spit: about 35 x 35 x 35
- azrallikPunch: about 35 x 35 x 35
- fingerBlastHit: about 15 x 15 x 15

Do not use vertical float / jump-dodge as the main answer. Several hitboxes are tall enough that vertical tricks are not reliable.

## 8. Important animation tells

Demon Warrior attack:
rbxassetid://107260711747781

Kolvumar direct action:
rbxassetid://89702140030707

Kolvumar spit tell:
rbxassetid://140162831578310

Azrallik Finger Blast tell:
rbxassetid://106525745261065

Finger timing found repeatedly:
about 1.03–1.04 seconds before fingerBlastHit appears.

Azrallik punch / spread tell:
rbxassetid://130043568559097

Critical V10.2 discovery:
the animation repeatedly preceded azrallikPunchSpread by about 2.51–2.52 seconds.

This is why later builds begin lateral/orbit preparation before the spread instead of waiting for eight large radial lines to already exist.

## 9. Targeting rules that worked best

Normal floors:
- prefer the strongest meaningful enemy using MaxHP + enemy priority + current floor + remaining HP;
- distance is a tiebreaker, not the dominant factor;
- keep sticky target lock;
- finish a local almost-dead enemy before crossing the room to another target;
- physical enemies can override only when they are truly dangerous, not just vaguely nearby.

Boss fights:
- mandatory boss mechanic first, such as Azrallik’s Heart;
- boss is the main offensive target;
- adds may receive only a short emergency / ready-skill burst if truly local;
- do not spend the majority of the fight chasing Blood Minions or small adds;
- movement can avoid adds while offense stays on the boss.

Post-boss:
- clean up meaningful local leftovers before committing to the next room.

## 10. Mage behavior

One of the biggest project corrections:

A mage standing next to the player does NOT behave like a Demon Warrior.

Later behavior:
- if no physical enemy is within the true pressure region, aggressively keep the mage as the target;
- stay close enough to use skills and basic weapon;
- red line appears -> sidestep the actual geometry only;
- do not enter full dodge simply because a mage-wave object exists;
- if current_inside = 0 and predicted_inside = 0, release dodge ownership and keep attacking;
- basic attacks may continue while sidestepping mage geometry.

Mage pressure guard was reduced from 28 to about 20 studs so a distant physical enemy does not unnecessarily disable mage aggression.

## 11. Physical pressure behavior

V10.x direction:
- ordinary physical pressure belongs to PhysicalPressureMove, not the full dodge state;
- true panic is much narrower.

V10.1-style thresholds:
- hard panic radius about 6.5 studs;
- near radius about 9 studs only if closing speed is meaningful;
- near-panic minimum closing around 4 studs/sec;
- extremely short TTC remains a reason to emergency-dodge;
- actual replicated/virtual attack threat still takes precedence.

Important lesson:
distance alone is not enough. An enemy at 8–9 studs but moving away should not repeatedly start and clear a full dodge.

## 12. Demonic Overgrowth

Overgrowth became fast in the good V10 runs, but early-wave deaths remained the main variance source by V10.2.

Successful later fight times were often around the high-20s to low-30s seconds.

Known behavior:
- first-strip proactive movement;
- forward-only sequence;
- direction lock;
- exact long-line gap logic;
- larger single escape when needed;
- no generic narrow teleport spam;
- one bounded shift per wave;
- physical-aware long-line solving.

V10.2 regression:
every tested run had at least one Overgrowth death.

V10.3 current direction:
- larger first edge margin, around 6.5;
- after first proactive edge movement, continue outward briefly, about 0.9s, before converting fully into the forward sequence;
- heavily penalize low-clearance forward plans;
- preserve the proven forward sequence logic rather than redesigning the boss.

Do not retune all Overgrowth geometry unless logs prove the current narrow fix fails.

## 13. Kolvumar

Kolvumar was the most difficult consistency problem before V10.

Spit facts:
- spit can spawn effectively under the player;
- damage can arrive quickly;
- staying far away does not prevent spit;
- overlapping puddles are the real danger;
- direct rescue is useful but should remain bounded by the global 3-second teleport governor.

Good V10.1 direction:
- shorter walking escape radii: 10, 12, 14, 16, 18, 20, 22, 24, 28;
- direct rescue max about 18.5 studs;
- route-safe motion during governor cooldown;
- live overlap count should decide whether stacked emergency is active;
- generic boss-wave direct shift stays disabled;
- direct rescue remains exceptional.

V10.1 had a major improvement:
Kolvumar fight average fell to roughly low-20-second range and deaths dropped significantly compared with V10.0.

V10.2 experiment:
a stall-recovery commit window was added. It improved some cases but could also create speed=0 / stale-owner behavior and made overall Kolvumar performance less consistent.

V10.3 current direction:
- restore V10.1-style rapid replanning;
- KEEP V10.2 live overlap recount at the exact rescue decision;
- do not keep the V10.2 recovery-commit behavior if it causes stalls;
- retain 3-second global shift governor;
- retain no-tween rule.

## 14. Demon Lord Azrallik

Main mechanics:
- Heart phase is mandatory and receives absolute target priority;
- horizontal beam / lattice logic;
- finger tell;
- punch;
- punch spread;
- Blood Minion pressure;
- safe-pressure movement;
- direct Azrallik CFrame shifting remains disabled in later stable builds.

Heart:
- attack around real skill range; older 52-stud spacing was a mistake when Infernal Strike was only reliable around 30.
- Heart lock is not a “small add”; it is the boss objective.

Finger:
- replicated action animation gives about 1.03 seconds of warning;
- proactive normal movement is preferred;
- do not wait for fingerBlastHit to exist.

PunchSpread:
- punch tell animation gives about 2.51–2.52 sec warning;
- later V10.2 logic approaches briefly, then begins lateral/orbit preparation;
- if already standing in a safe spread gap when spread appears, HOLD instead of crossing the fan;
- if actually inside a line, find a local safe gap around 4–18 studs;
- avoid 38–46 stud generic destinations that force the player to walk through radial lines.

V10.3 additional direction:
when Finger Blast overlaps active PunchSpread, use a combined local safe-gap solution first. Do not let the finger solver walk through the 8-way spread.

## 15. Movement / teleport rules

No tween.

Global direct-shift governor:
3.00 seconds minimum spacing.

Rolling teleport budget remained bounded in older builds; do not reintroduce shift spam.

Direct movement philosophy:
- walk first;
- local sidestep second;
- bounded direct shift only when geometry / timing proves walking cannot save the player;
- after a direct shift, re-evaluate rather than blindly chaining stale continuation.

Snapback detection exists and should remain.

Never solve an anti-cheat signal by adding bypass hooks. If a direct movement correlates with kicks, reduce or remove risky shifts.

## 16. Performance rules

Known healthy-ish controller cadence from earlier stable work:
- THINK_INTERVAL about 0.045
- MOVE_REFRESH about 0.07
- TARGET_REFRESH about 0.30
- DODGE_REPLAN_INTERVAL about 0.12
- ENEMY_CACHE_INTERVAL about 0.28
- ANIMATION_DEDUPE_WINDOW about 0.12
- repath about 1.1
- log flush about 0.50

Avoid:
- ordinary automation on RenderStepped;
- repeated require;
- full Workspace scans every tick;
- creating connections inside loops;
- per-poll log spam;
- duplicated AnimationPlayed listeners;
- duplicated virtual threats;
- same-frame duplicate event work;
- multiple runtime owners;
- remote bursts.

Ability diagnostics use bounded delayed samples only after legitimate casts.

## 17. Luau compiler constraint

Very important:
the large monolithic file hit Luau’s roughly 200 local-register limit.

V9.0 initially failed because too many top-level local function declarations accumulated.

Rule for this codebase:
do NOT casually add new top-level local functions.

Prefer:
Runtime.SomeHelper = function(...)
    ...
end

or modularize into separate files when moving into the final repo architecture.

## 18. Version history — important turning points

V7.x:
survival / movement foundation, no-tween direction, encounter locking.

V8.0–V8.2:
Azrallik safe pocket / lattice / exact gaps / lane slide.

V8.3–V8.6:
Heart lock, cleanup, stall recovery, Overgrowth commit, global 3-second teleport governor.

V8.7:
one of the best early survival baselines.

V8.8:
starter-safe improvements, proactive first strip, physical emergency fixes.

V8.9:
boss add and movement-continuity regression; too many deaths.

V9.0–V9.0.2:
Kolvumar local continuation and range bug fixes; compiler register issue discovered.

V9.1:
generic boss add intercept, post-boss cleanup, sticky targeting, ability diagnostics.

V9.2:
mixed-skill range work, stronger latching, Azrallik direct shifts suppressed; Ground Slam skip spam exposed wrong spacing.

V9.3:
tactical short-skill staging; too defensive / too slow.

V9.4:
range calibration rollback; fixed the false assumption that Infernal Strike worked at 55.

V9.5:
boss-majority + strongest-first targeting.

V9.6:
DPS recovery / hard boss priority; fixed Heart and Kolvumar spacing.

V9.7:
attack while dodging + opportunistic DPS.

V9.8:
mage free-pressure concept, but still over-avoided.

V9.9:
mage assault + minimal dodge; mage wave existence no longer automatically means dodge.

V10.0:
aggression continuity; all three reference runs completed around 392.9–436.0 sec, roughly 416.9 sec average.

V10.1:
Kolvumar stability + true physical panic. Kolvumar became much faster and more reliable; overall average stayed around low 420s due one slower run.

V10.2:
Azrallik spread prediction + live Kolvumar recount. Produced a best recent clear around 359.9 sec, but had Overgrowth and Kolvumar consistency regression.

V10.3:
current latest build direction. Combines:
- V10.0/V10.1 aggression and mage behavior;
- V10.1-style Kolvumar replanning;
- V10.2 live Kolvumar overlap recount;
- V10.2 Azrallik spread prediction;
- new Overgrowth first-edge hard-clear tuning;
- combined Finger + PunchSpread local-gap handling.

Latest local filename at handoff:
DQR_Underworld_Intelligent_Combat_V10_3_OvergrowthHardClear_KolvumarRollback_AzrallikCombo.lua

V10.3 had static QA only at handoff. It had not yet received the same full multi-run validation as earlier builds.

## 19. Reference run results

V10.0:
3/3 authoritative completions.
Approx completion times:
- 421.8 sec
- 436.0 sec
- 392.9 sec
Average about 416.9 sec.

Typical boss times in those runs:
- Overgrowth about 28.5 sec average
- Kolvumar about 34.9 sec average
- Azrallik about 78.6 sec average

V10.1:
3/3 authoritative completions.
Approx completion times:
- 403.8 sec
- 451.4 sec
- 406.6 sec
Average about 420.6 sec.
Median about 406.6 sec.

Kolvumar:
about 16.2 / 21.7 / 28.3 sec, around 22.1 sec average.

V10.2:
5/5 authoritative completions.
Approx completion times:
- 419.6 sec
- 552.8 sec
- 393.6 sec
- 414.9 sec
- 359.9 sec

Average about 428.2 sec.
Median about 414.9 sec.
Best recent clear: about 359.9 sec.

Interpretation:
the engine can already clear very fast, but consistency is the remaining problem.

## 20. Logging events worth preserving

Core:
- ERROR
- START
- CHARACTER
- TARGET
- TARGET_LOCK_HOLD
- ABILITY
- ABILITY_RESULT
- ABILITY_RANGE_SKIP
- DAMAGE
- PLAYER_DIED
- COMPLETION_CONFIRMED
- DISCONNECT_SIGNAL
- CONTROLLER_HALT

Movement:
- APPROACH_PATH
- MOVE_REJECT
- WALL_AVOID
- RED_ROUTE_BLOCK
- DODGE_START
- DODGE_CLEAR
- DODGE_MOVE_STALL
- DODGE_STALL_RECOVERY
- TELEPORT_GOVERNOR_BLOCK
- SNAPBACK

Mage:
- MAGE_FREE_FOCUS
- MAGE_ATTACK_WINDOW
- MAGE_PRESSURE_CAST
- MAGE_PRESSURE_BASIC
- MAGE_WAVE_START
- MAGE_WAVE_PLAN
- MAGE_WAVE_END

Physical:
- PHYSICAL_PRESSURE
- PHYSICAL_HANDOFF
- PHYSICAL_PRESSURE_LEASH
- MELEE_EMERGENCY

Overgrowth:
- OVERGROWTH_EDGE_PROACTIVE
- OVERGROWTH_DIRECTION_LOCK
- OVERGROWTH_FORWARD_PLAN
- OVERGROWTH_LONGLINE_POCKET

Kolvumar:
- KOLVUMAR_SPIT_EMERGENCY
- KOLVUMAR_SPIT_WALK_ESCAPE
- KOLVUMAR_SPIT_RESCUE
- KOLVUMAR_SPIT_HOLD
- KOLVUMAR_SPIT_SLIDE
- KOLVUMAR_SPIT_COOLDOWN_SLIDE

Azrallik:
- AZRALLIK_HEART_PHASE_START
- AZRALLIK_HEART_PHASE_END
- AZRALLIK_FINGER_TELL
- AZRALLIK_FINGER_PREMOVE
- AZRALLIK_SPREAD_TELL
- AZRALLIK_SPREAD_PREMOVE
- AZRALLIK_SPREAD_HOLD
- AZRALLIK_SPREAD_LOCAL_GAP
- AZRALLIK_SAFE_PRESSURE
- AZRALLIK_SHIFT_SUPPRESSED
- BOSS_HEARTBEAT

## 21. What to validate first on any future Underworld run

1. Zero ERROR lines.
2. START flags match intended version.
3. Authoritative COMPLETION_CONFIRMED.
4. Total runtime and death count.
5. Boss start/end timestamps.
6. No direct-shift spacing below 3 seconds.
7. No snapback.
8. No repeated target thrash.
9. Skills are actually landing in their effective ranges.
10. Mage waves are not forcing unnecessary retreat.
11. Physical pressure is not repeatedly creating 0.05-second fake dodge cycles.
12. Kolvumar is not stalling at zero speed inside puddles.
13. Azrallik spread tell appears before spread and produces lateral/local-gap behavior.
14. Overgrowth first wave is no longer the dominant death source.

## 22. Future repository architecture

Do not keep the final product as a single 16k-line file forever.

Recommended DQR structure:

runtime/dqr/
  core/
    RuntimeController.lua
    MovementController.lua
    ThreatEngine.lua
    DodgePlanner.lua
    CombatController.lua
    TargetController.lua
    AbilityController.lua
    CompletionController.lua
    DiagnosticLogger.lua
  profiles/
    Physical.lua
  dungeons/
    underworld/
      manifest.lua
      attacks.lua
      rooms.lua
      bosses/
        DemonicOvergrowth.lua
        Kolvumar.lua
        DemonLordAzrallik.lua

Reusable core systems from Underworld:
- one-owner MovementController;
- sticky TargetController with strongest-first scoring;
- physical pressure handoff;
- mage free-pressure aggression;
- AbilityTelemetry / skill effective-range profile;
- boss-add arbitration;
- post-boss cleanup;
- AnimationTellPredictor;
- local safe-gap planner;
- bounded direct-shift governor;
- authoritative completion controller.

Do not move a new world’s boss-specific geometry into universal core until it has been validated independently.

## 23. Moving to another world

Underworld should now be treated as the reference implementation, not copied blindly.

For a new world:
1. identify actual PlaceId / room topology;
2. inventory enemies and bosses;
3. passively record Workspace attack geometry and animation tells;
4. inspect relevant replicated modules, attributes, UI and legitimate callsites;
5. validate entry / room progression / completion source;
6. build a world manifest and attack registry;
7. reuse universal movement/target/ability systems;
8. add only world-specific hazard adapters;
9. test one room at a time;
10. then run full dungeon batches.

Never assume another world uses Underworld timings, hitbox dimensions, room numbers, or boss state.

## 24. Working style / continuation expectations

The user wants:
- practical evidence, not guesses;
- diagnostic/decompile/recon first when a game/world is unknown;
- fastest stable automation, not “safe-looking” automation that stops DPS;
- minimal needless clarification when the evidence can answer the question;
- downloadable Lua builds when code is produced;
- comparisons across multiple test logs;
- concise conclusions with the actual root cause;
- preserve working systems and make narrow changes after a strong baseline.

When a new build gets worse:
do not keep layering features. Identify the regression and roll back only the failing subsystem while keeping proven improvements.

## 25. Current handoff status

Current stable knowledge stack:
- V10.0 aggression continuity is a strong general baseline.
- V10.1 Kolvumar behavior is the best proven Kolvumar baseline.
- V10.2 Azrallik spread predictor is worth keeping.
- V10.3 combines those with a targeted Overgrowth first-edge fix and combined Azrallik Finger+Spread handling.

Next Underworld action if returning later:
run V10.3 in a small batch, compare against V10.1/V10.2, and keep only changes that improve both completion time and death consistency.

Next project action now:
begin the next DQR world using the new-chat handoff document in this folder.
