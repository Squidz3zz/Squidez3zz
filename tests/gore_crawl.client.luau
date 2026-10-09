-- Run in the Client datamodel of a running playtest. Needs the player spawned and downed: start the playtest, run
-- tests/fire_play.client.luau (it presses Play), then tests/gore_ragdoll.server.luau with CASE "down" (the server breaks both
-- legs, so GoreDowned is set), then this. Afterwards run gore_ragdoll.server.luau with CASE "kill" so the player respawns whole.
-- Checks GoreClient's crawl on the local character:
--   C-A  with GoreDowned set by the server, Humanoid.PlatformStand is true
--   C-B  left alone (no move direction) the root stays put: under 1 stud in 1 s
--   C-C  holding a move direction (set here every frame, after the PlayerModule's own input) moves the root about
--        GoreConfig.CRAWL_SPEED (3) studs per second, give or take 1, that way
-- It returns "PASS gore_crawl".
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GoreConfig = require(ReplicatedStorage:WaitForChild("GoreConfig"))

local DIRECTION = Vector3.new(0, 0, -1) -- open ground from the spawn
local HOLD = 2 -- seconds the direction is held while measuring

local player = Players.LocalPlayer
local character = player.Character
local humanoid = character and character:FindFirstChildOfClass("Humanoid")
local root = character and character:FindFirstChild("HumanoidRootPart")
assert(humanoid and root and humanoid.Health > 0, "no live character: run tests/fire_play.client.luau first")

local function waitFor(check: () -> boolean, timeout: number): boolean
	local deadline = os.clock() + timeout
	while not check() do
		if os.clock() > deadline then
			return false
		end
		task.wait()
	end
	return true
end

assert(waitFor(function()
	return character:GetAttribute("GoreDowned") == true
end, 5), "GoreDowned is not set on the character: run gore_ragdoll.server.luau with CASE \"down\" first")

-- C-A
assert(waitFor(function()
	return humanoid.PlatformStand
end, 2), "C-A: a downed character should be PlatformStand")
task.wait(1.5) -- it falls over and settles

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- C-B
local still = root.Position
task.wait(1)
local drift = flat(root.Position - still).Magnitude
assert(drift < 1, ("C-B: with no move direction the root moved %.2f studs in 1 s"):format(drift))

-- C-C
local BINDING = "GoreCrawlTestMove"
RunService:BindToRenderStep(BINDING, Enum.RenderPriority.Input.Value + 1, function()
	player:Move(DIRECTION, false)
end)
local ok, err = pcall(function()
	task.wait(0.5) -- up to speed
	local start, began = root.Position, os.clock()
	task.wait(HOLD)
	local moved = flat(root.Position - start)
	local speed = moved:Dot(DIRECTION) / (os.clock() - began)
	assert(
		math.abs(speed - GoreConfig.CRAWL_SPEED) <= 1,
		("C-C: holding a direction moved the root at %.2f studs/s that way (%.2f studs sideways in all), expected %d +- 1"):format(speed, moved.Magnitude, GoreConfig.CRAWL_SPEED)
	)
	assert(humanoid.PlatformStand, "C-C: the crawling character stopped being PlatformStand")
end)
RunService:UnbindFromRenderStep(BINDING)
player:Move(Vector3.zero, false)
assert(ok, err)

return "PASS gore_crawl (C-A to C-C)"
