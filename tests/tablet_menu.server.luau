-- Run in the Server datamodel during a playtest, one step at a time (set CASE below): the server steps tests/tablet_menu.client.luau
-- asks for between its client steps. It needs a spawned character: start a fresh playtest, run tests/fire_play.client.luau
-- (it presses Play), wait for the character, then run these.
--   claim              the player's body made whole (a character that lost a limb, or has any gore, is killed and respawns first), at
--                      full health, the room released and claimed afresh (a new copy and a new tablet), Bob on Standby with the
--                      shutter open. It also sets SEVER_CHANCE 1 (an override on GoreConfig), so every blast until "release" rips the
--                      limb off and it reads LOST, as the client cases expect (a Broken limb is not lost)
--   release            the room released (the copy and the tablet go), and the SEVER_CHANCE override removed
--   inject_right_arm   Explosive into the right arm, through the server's TestHook (the owner must hold the room)
--   kill               the player's character killed (Health 0)
local CASE = "claim"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
local RESPAWN_WAIT = LabConfig.RESPAWN_TIME + 5

local function waitFor(predicate, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		task.wait(0.1)
	end
	return predicate()
end

local player = waitFor(function()
	return Players:GetPlayers()[1]
end, 10)
assert(player, "no player in the playtest")
local function aliveHumanoid()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end
assert(waitFor(aliveHumanoid, RESPAWN_WAIT), "the player has no live character: run tests/fire_play.client.luau first")

local room = workspace:WaitForChild("Room1")
local bob = room.BobTheInjector
local labServer = ServerScriptService:FindFirstChild("LabServer")
local hook = labServer and labServer:FindFirstChild("TestHook")
assert(hook and hook:IsA("BindableFunction"), "ServerScriptService.LabServer.TestHook (BindableFunction) missing")

if CASE == "claim" then
	hook:Invoke("release", player)
	assert(waitFor(function()
		return bob:GetAttribute("State") == "Standby" and room.Shutter.CanCollide == false
	end, LabConfig.Timings.Return + 1), "Bob is not back on Standby with the shutter open")
	local whole = true
	for _, key in LabConfig.LIMB_KEYS do
		local state = player.Character:GetAttribute("Gore_" .. key)
		whole = whole and not LabConfig.isLost(player.Character, key) and (state or "Intact") == "Intact"
	end
	if not whole then
		local old = player.Character
		aliveHumanoid().Health = 0
		assert(waitFor(function()
			return player.Character ~= old and aliveHumanoid()
		end, RESPAWN_WAIT), "no new character after the respawn time")
	end
	local humanoid = aliveHumanoid()
	humanoid.Health = humanoid.MaxHealth
	local ok, reason = hook:Invoke("claim", player)
	assert(ok == true, "claim refused: " .. tostring(reason))
	assert(room:FindFirstChild("Subject"), "no Room1.Subject after the claim")
	assert(player.Backpack:FindFirstChild("Tablet"), "no Tablet in the Backpack after the claim")
	ReplicatedStorage:WaitForChild("GoreConfig"):SetAttribute("SEVER_CHANCE", 1)
	return "PASS tablet_menu.server claim"
elseif CASE == "release" then
	ReplicatedStorage:WaitForChild("GoreConfig"):SetAttribute("SEVER_CHANCE", nil)
	hook:Invoke("release", player)
	assert(room:GetAttribute("Owner") == 0, "Owner should be 0")
	return "PASS tablet_menu.server release"
elseif CASE == "inject_right_arm" then
	local ok, reason = hook:Invoke("inject", player, "Explosive", "RightArm")
	assert(ok == true, "the injection was refused: " .. tostring(reason))
	return "PASS tablet_menu.server inject_right_arm (Bob is " .. tostring(bob:GetAttribute("State")) .. ")"
elseif CASE == "kill" then
	aliveHumanoid().Health = 0
	return "PASS tablet_menu.server kill"
end
error("unknown CASE " .. tostring(CASE))
