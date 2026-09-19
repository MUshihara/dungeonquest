# DQR Modular Runtime

Entry point: `runtime/dqr/bootstrap.lua`.

The bootstrap reads `Workspace.dungeonName`, loads the matching world adapter,
then starts each controller as an independent Luau chunk inside one isolated shared environment.

Supported in Modular V1:
- The Underworld
- Samurai Palace

World-specific data lives under `runtime/dqr/dungeons/<world>/`.
Known monoliths are retained under `archive/legacy/` until modular multi-run validation is complete.

Non-negotiable rules remain: one runtime owner, one physical movement owner, no tween,
walk/local-sidestep first, bounded direct shifts only when necessary, 3.00-second global
direct-shift cooldown, no bypass hooks, no invented remote signatures, no hot full-Workspace scans.
