-- DQR modular runtime: core/Services.lua
-- Loaded by runtime/dqr/bootstrap.lua into an isolated shared environment.

-- ============================================================
-- Services
-- ============================================================

Players = game:GetService("Players")
RunService = game:GetService("RunService")
PathfindingService = game:GetService("PathfindingService")
TweenService = game:GetService("TweenService")
ReplicatedStorage = game:GetService("ReplicatedStorage")
HttpService = game:GetService("HttpService")
GuiService = game:GetService("GuiService")

LP = Players.LocalPlayer

-- World identity is validated by runtime/dqr/bootstrap.lua before core startup.


