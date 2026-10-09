-- Run in the Server datamodel during a playtest: the server step of tests/gore_drips.client.luau (run its case A-1 first). It
-- needs a spawned character (tests/fire_play.client.luau). A character with any gore is killed first, so the new copy is whole;
-- then it releases and claims Room 1 for a fresh copy and, through ServerScriptService.GoreServer.TestHook, opens three of the
-- copy's limbs: LeftArm Torn (a "hit" of 50), RightArm Broken (a "hit" of 100) and LeftLeg Severed (an explosion of 150,
-- seeded to sever). The copy bleeds (3 open limbs) and drips; 8 s later it is killed, so its corpse drips on. The copy is
-- linked, so the owner's limbs open and the owner dies with it (and respawns).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
local RESPAWN_WAIT = LabConfig.RESPAWN_TIME + 5
local SEVER_SEED = 3 -- first roll 0.181: an explosion that breaks a limb severs it
local BLEED_SECONDS = 8

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

local player = Players:GetPlayers()[1]
assert(player, "no player in the playtest")
local labHook = ServerScriptService.LabServer:FindFirstChild("TestHook")
local goreHook = ServerScriptService.GoreServer:FindFirstChild("TestHook")
assert(labHook and goreHook, "LabServer.TestHook or GoreServer.TestHook missing")
local function gore(fnName, ...)
	return goreHook:Invoke("call", fnName, ...)
end
local function alive()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.Health > 0 and humanoid
end
local function whole(body)
	for _, key in LabConfig.LIMB_KEYS do
		if LabConfig.isLost(body, key) or (body:GetAttribute("Gore_" .. key) or "Intact") ~= "Intact" then
			return false
		end
	end
	return true
end

assert(waitFor(alive, RESPAWN_WAIT), "the player has no live character: run tests/fire_play.client.luau first")
local room = workspace.Room1
labHook:Invoke("release", player)
assert(waitFor(function()
	return room.BobTheInjector:GetAttribute("State") == "Standby"
end, 10), "Bob is not back on Standby")
if not whole(player.Character) then
	local old = player.Character
	gore("hurt", old, math.huge)
	assert(waitFor(function()
		return player.Character ~= old and alive()
	end, RESPAWN_WAIT), "no new character after the respawn time")
end
local ok, reason = labHook:Invoke("claim", player)
assert(ok == true, "claim refused: " .. tostring(reason))
local subject = room:FindFirstChild("Subject")
assert(subject and whole(subject), "no whole Room1.Subject after the claim")
task.wait(1) -- the client sees the whole copy first
gore("damageLimb", subject, "LeftArm", 50, "hit")
gore("damageLimb", subject, "RightArm", 100, "hit")
gore("seed", SEVER_SEED)
gore("damageLimb", subject, "LeftLeg", 150, "explosion")
assert(subject:GetAttribute("Gore_LeftArm") == "Torn", "the copy's LeftArm did not tear")
assert(subject:GetAttribute("Gore_RightArm") == "Broken", "the copy's RightArm did not break")
assert(subject:GetAttribute("Gore_LeftLeg") == "Severed", "the copy's LeftLeg was not severed")
task.wait(BLEED_SECONDS)
local humanoid = subject:FindFirstChildOfClass("Humanoid")
local health = humanoid.Health
assert(health > 0 and health < 100, ("the bleeding copy has %.1f health"):format(health))
gore("hurt", subject, math.huge)
return ("PASS gore_drips.server (3 open limbs, %.1f health after %d s, then killed)"):format(health, BLEED_SECONDS)
