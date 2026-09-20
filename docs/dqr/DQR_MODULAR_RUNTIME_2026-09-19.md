# DQR Modular Runtime Migration — 2026-09-19

The DQR runtime has moved from a growing single-file controller toward `runtime/dqr/`.

## Entry point

`runtime/dqr/bootstrap.lua`

The bootstrap reads `Workspace.dungeonName`, selects a world adapter, loads that world's
manifest/attacks/rooms/boss knowledge, and executes each core system as an independent
Luau chunk in one isolated shared runtime environment.

Current adapters:
- `runtime/dqr/dungeons/underworld/`
- `runtime/dqr/dungeons/samurai_palace/`

Core invariants preserved:
- one runtime owner
- one physical movement owner
- no tween
- attack while dodging when safe
- strongest-first + sticky target lock
- local finisher
- boss-majority focus
- ranged/mage pressure
- physical closing-speed/TTC pressure
- geometry-aware route safety
- authoritative `loadCompleteGui` completion
- 3-second global direct-shift governor

Latest known monoliths are retained under `runtime/dqr/archive/legacy/`.
Validate Samurai Palace first, then compare modular Underworld against the V10.x reference.


## Modular V1.2 — four-match refinement

Evidence set contained two Modular V1 baselines and three Modular V1.1 runs. V1.1 exposed repeatable failures rather than isolated RNG:

- valid room7 -> room8 PathfindingService waypoints could be rejected as `ground_gap`, causing a multi-minute stall and dungeon timeout;
- single Shuriken line escape could choose the long axis of a ~4 x 73 stud line, producing an unnecessarily huge dodge;
- Samurai Swordsman attack animation `rbxassetid://107260711747781` arrives essentially at impact, so proactive physical spacing is primary;
- Golem small-rock landing positions needed to remain dangerous through the delayed `rockExplosionSmall` handoff;
- Miyamoto Flame Cyclone's ~36 crescent parts inflated threat counts into the 35–43 range and destabilized planning;
- Miyamoto wave solving could drift >130 studs from the boss, so V1.2 adds an arena leash and local-gap ownership across flame phases.

V1.2 keeps the proven architecture: one runtime owner, one physical movement owner, no tween transit, attack while dodging when safe, boss-majority targeting, and the global 3-second direct-shift governor.


## Modular V1.3 — timeout-focused correction

Three Modular V1.2 match logs showed the primary failure had become elapsed time rather than navigation discovery.

- Two matches reached Sanada at roughly 106–126 seconds but were returned to the lobby around 652–676 seconds with Sanada still at full 408M HP.
- The controller was allowing upstairs Sanada hazards and physical-pressure movement to steal ownership from the lower-floor level route.
- Threat geometry was primarily horizontal, so attacks centered ~55–70 studs above the player could still influence pointDanger/routeDanger downstairs.
- In the one run that reached the upper arena, SamuraiLocalGapCandidate still penalized inward boss progress, allowing crossShuriken waves to walk the player far outside the 26-stud damage envelope.
- One run did reach Miyamoto, but only around 592 seconds, leaving ~35 seconds before the authoritative timeout return.

V1.3 changes:
- hard boss-level transit ownership before dodge processing;
- 3D vertical threat relevance for real and virtual hazards;
- opportunistic instant offense during level transit without surrendering movement ownership;
- Samurai boss local-gap scoring preserves boss damage range and strongly penalizes retreat;
- Samurai multi-Shuriken wave search is capped to local 22-stud movement;
- specialized Samurai gap candidates are prevalidated against the movement safety layer.

The global 3-second direct-shift governor, no-tween rule, one movement owner, and authoritative completion remain unchanged.
