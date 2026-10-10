-- Run in the Server datamodel during a playtest: the server step of tests/gore_blood.client.luau (run its case A-1 first). It
-- needs a spawned character (tests/fire_play.client.luau).
--   S-A  a wall of its own far from the rooms (Workspace.GoreBloodWall, a Model streamed to every client: Persistent): a floor
--        whose top is at y 300 and a Wall part whose face is at x 7009.5; 1 s later a blood boom 3 studs in front of the face,
--        aimed at it (Booms.at(p, true, +X))
--   S-B  then Room 1: a character with any gore is killed first (so the copy is whole), the room is released and claimed afresh
--        and the Explosive goes into the copy's head (LabServer.TestHook "inject"); it waits for the copy to die
-- Then the model gets the attribute Done and goes 3 s later.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
local Booms = require(ServerScriptService:WaitForChild("Booms"))
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

local player = Players:GetPlayers()[1]
assert(player, "no player in the playtest")
local labHook = ServerScriptService.LabServer:FindFirstChild("TestHook")
local goreHook = ServerScriptService.GoreServer:FindFirstChild("TestHook")
assert(labHook and goreHook, "LabServer.TestHook or GoreServer.TestHook missing")
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

local old = workspace:FindFirstChild("GoreBloodWall")
if old then
	old:Destroy()
end
local model = Instance.new("Model")
model.Name = "GoreBloodWall"
model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
local floor = Instance.new("Part")
floor.Name = "Floor"
floor.Anchored = true
floor.Size = Vector3.new(40, 1, 40)
floor.Position = Vector3.new(7000, 299.5, 7000)
floor.Parent = model
local wall = Instance.new("Part")
wall.Name = "Wall"
wall.Anchored = true
wall.Size = Vector3.new(1, 20, 30)
wall.Position = Vector3.new(7010, 310, 7000)
wall.Parent = model
model.Parent = workspace

local ok, result = pcall(function()
	-- S-A
	task.wait(1)
	local at = Vector3.new(7009.5 - 3, 304, 7000)
	Booms.at(at, true, Vector3.xAxis)
	task.wait(2)

	-- S-B
	assert(waitFor(alive, RESPAWN_WAIT), "the player has no live character: run tests/fire_play.client.luau first")
	local room = workspace.Room1
	labHook:Invoke("release", player)
	assert(waitFor(function()
		return room.BobTheInjector:GetAttribute("State") == "Standby"
	end, 10), "Bob is not back on Standby")
	if not whole(player.Character) then
		local character = player.Character
		goreHook:Invoke("call", "hurt", character, math.huge)
		assert(waitFor(function()
			return player.Character ~= character and alive()
		end, RESPAWN_WAIT), "no new character after the respawn time")
	end
	local claimed, reason = labHook:Invoke("claim", player)
	assert(claimed == true, "claim refused: " .. tostring(reason))
	local subject = room:FindFirstChild("Subject")
	assert(subject and whole(subject), "no whole Room1.Subject after the claim")
	local facing = subject.Torso.CFrame.LookVector
	task.wait(1)
	local injected, why = labHook:Invoke("inject", player, "Explosive", "Head")
	assert(injected == true, "the head injection was refused: " .. tostring(why))
	local humanoid = subject:FindFirstChildOfClass("Humanoid")
	assert(waitFor(function()
		return not humanoid.Parent or humanoid.Health <= 0
	end, 20), "the copy did not die from the head blast")
	return ("boom at %s aimed +X; the copy faced %s and died from the head blast"):format(tostring(at), tostring(facing))
end)
model:SetAttribute("Done", true)
task.delay(3, model.Destroy, model)
assert(ok, result)
return "PASS gore_blood.server (" .. result .. "): now run CASE A-2 of tests/gore_blood.client.luau"
