-- Run in the Server datamodel during a playtest, right before case B of tests/bob_animator.client.luau: Explosive into the copy's
-- left leg, through LabServer's TestHook. Needs the room claimed by the player (the server step "claim" of
-- tests/tablet_menu.server.luau) and Bob on Standby.
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local player = Players:GetPlayers()[1]
assert(player, "no player in the playtest")
local labServer = ServerScriptService:FindFirstChild("LabServer")
local hook = labServer and labServer:FindFirstChild("TestHook")
assert(hook and hook:IsA("BindableFunction"), "ServerScriptService.LabServer.TestHook (BindableFunction) missing")
local ok, reason = hook:Invoke("inject", player, "Explosive", "LeftLeg")
assert(ok == true, "the injection was refused: " .. tostring(reason))
return "PASS bob_animator.server inject (Explosive into the left leg)"
