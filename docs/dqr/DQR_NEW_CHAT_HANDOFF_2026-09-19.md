# DQR New Conversation Handoff — Read This First

Updated: 2026-09-19
Project: Dungeon Quest Reborn
Repository: MUshihara/dungeonquest
Branch: main

## What the next assistant must do first

Read:
1. docs/dqr/DQR_UNDERWORLD_MASTER_KNOWLEDGE_2026-09-19.md
2. this file

Do NOT ask the user to repeat the Underworld history.

The user is moving to another DQR world. Underworld is now the reference implementation for the shared engine.

## Current project state

The latest Underworld local build at handoff is:

DQR_Underworld_Intelligent_Combat_V10_3_OvergrowthHardClear_KolvumarRollback_AzrallikCombo.lua

It is based on the successful V10.x line.

V10.0:
- 3/3 authoritative clears;
- roughly 392.9–436.0 sec;
- strong aggression / mage behavior.

V10.1:
- 3/3 authoritative clears;
- roughly 403.8 / 451.4 / 406.6 sec;
- strongest proven Kolvumar behavior;
- true-physical-panic logic.

V10.2:
- 5/5 authoritative clears;
- best recent clear around 359.9 sec;
- valuable Azrallik PunchSpread prediction;
- inconsistent Overgrowth / Kolvumar deaths.

V10.3 combines:
- V10.0/V10.1 aggression;
- V10.1-style Kolvumar replanning;
- V10.2 live Kolvumar overlap recount;
- V10.2 Azrallik spread prediction;
- targeted Overgrowth first-edge hard-clear behavior;
- combined Finger + PunchSpread local-gap handling.

V10.3 needs gameplay validation before being called final.

## Non-negotiable engineering rules

- One runtime owner.
- One physical movement owner.
- No tween.
- Walk first, local sidestep second, bounded direct shift only when necessary.
- Global direct-shift cooldown remains 3 seconds.
- No per-frame ordinary automation.
- No hot full-Workspace scan.
- No repeated require.
- No duplicate listeners.
- No remote spam.
- No anti-cheat bypass.
- No anti-kick hooks.
- No identity spoofing.
- No hidden/admin remotes.
- No invented remote signatures.
- No network-ownership bypass.
- Do not solve anti-cheat by bypassing it; reduce risky behavior instead.
- Do not add lots of new top-level local functions to the monolith because the code already hit Luau’s local-register limit. Use Runtime.* helpers or modular files.

## Universal combat philosophy

The user wants FAST stable clears.

Do not confuse “dodging more” with “being better.”

Correct behavior:
- attack while moving when possible;
- dodge only actual or predicted danger;
- keep damage continuity;
- do not abandon the boss for small adds;
- do not run away from mages just because they are close;
- do not chase far targets when a nearly-dead local enemy should simply be finished;
- use actual effective skill range, not assumed range.

## Shared systems to reuse in the next world

Reuse conceptually:
- TargetController strongest-first scoring;
- sticky target lock;
- local-finisher rule;
- boss-majority / hard boss priority;
- mage free-pressure mode;
- physical-pressure handoff;
- AbilityTelemetry;
- one-owner MovementController;
- geometry-aware route checks;
- pointDanger / routeDanger style scoring;
- authoritative completion detection;
- bounded direct-shift governor;
- diagnostic logger.

Do NOT copy Underworld boss geometry/timings directly.

## First diagnostic procedure for the new world

When the user gives the next world / places the character there:

### Phase A — identity and topology
Record:
- PlaceId;
- UniverseId if useful;
- current room / floor markers;
- room folder names;
- boss names;
- enemy names;
- gate / progression state;
- death / respawn behavior;
- completion UI and remote state.

### Phase B — passive combat reconnaissance
Observe:
- Workspace hitbox / precast parts;
- names, sizes, orientation, lifetime;
- projectile objects;
- action animations;
- replicated attributes;
- enemy state;
- player state;
- room assignment.

Do not start by guessing attack names.

### Phase C — legitimate action mapping
Find:
- ability/tool state;
- weapon attack path;
- entry/start remotes only from legitimate callsites or observed modules/UI;
- progression remotes only when their signature is evidenced.

No blind remote firing.

### Phase D — diagnostic script
Build a bounded diagnostic that logs:
- enemy spawn/despawn;
- boss state;
- room transitions;
- animation tells;
- threat start/end;
- player damage/death;
- ability casts;
- movement ownership;
- completion state.

Avoid full-tree dumps and per-frame spam.

### Phase E — build the new world adapter
Create:
- manifest;
- room rules;
- attack registry;
- boss modules;
- only the minimum world-specific movement logic needed.

Keep universal controller behavior shared.

## What to measure in every run

Always report:
- authoritative completion yes/no;
- total runtime;
- deaths;
- boss start/end durations;
- room/floor time;
- target switches;
- skill range skips;
- ability-result samples;
- major dodge count;
- direct shifts and spacing;
- movement stalls;
- snapbacks;
- errors.

If one run is obviously interrupted by the user/client, do not treat it as a normal combat failure.

## Underworld facts that may still be useful as design examples

Mage lesson:
mage proximity is not danger; red geometry is danger.

Physical lesson:
closing speed / TTC is more useful than raw distance alone.

Kolvumar lesson:
live world state can change after a plan is created. Recount overlap at the action decision, not only at planning time.

Azrallik lesson:
replicated animations can be excellent predictive tells. Finger gave about 1.03 sec warning; PunchSpread gave about 2.51–2.52 sec warning.

Overgrowth lesson:
a correct general planner may still need a boss-specific opening rule when the first attack happens too quickly.

## How to make changes after testing

If a run is worse:
1. identify which subsystem caused the regression;
2. compare to the last good version;
3. roll back that subsystem only;
4. preserve unrelated improvements;
5. test again.

Do not stack five speculative fixes into one build after a bad run.

## Suggested repository direction

Do not touch production Serenity routing just to preserve research.

Keep DQR documentation under docs/dqr/.

When the DQR runtime is ready for production, modularize toward:

runtime/dqr/core/
runtime/dqr/profiles/
runtime/dqr/dungeons/<world>/

Only then integrate with the actual Serenity loader / game route following the repository’s current production conventions.

## Short prompt the user can send in the next conversation

“Read the DQR handoff in MUshihara/dungeonquest under docs/dqr/. We are moving to the next Dungeon Quest Reborn world. Keep the Underworld V10.x engine as the reference core, do diagnostic/recon first, do not assume the new world’s attacks, and continue evidence-first.”

## Immediate next step

Ask only for the new world if it is not already clear from the user’s next message, then begin recon.

Do not ask the user to re-explain Underworld.
