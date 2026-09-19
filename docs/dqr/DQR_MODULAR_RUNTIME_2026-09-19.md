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
