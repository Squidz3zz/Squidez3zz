-- Run in the Server datamodel during a playtest, one case at a time (set CASE below). Needs a spawned character: start a fresh
-- playtest, run tests/fire_play.client.luau in the Client datamodel (it presses Play), wait for the character, then:
--   B  the server step of tests/boom.client.luau (run its case A-1 first): two booms through Booms.at, 1 s apart, the first 6 studs
--      in front of the character and the second 6 studs behind it; each adds 1 to Booms' BoomCount attribute
--   X  catch-all: an Explosion (BlastPressure 0, DestroyJointRadiusPercent 0) made at (0, 40, 0) is invisible by the time the next
--      deferred thread runs (the same frame, so before it replicates), and BoomCount went up by exactly 1
local CASE = "B"

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local module = ServerScriptService:FindFirstChild("Booms")
assert(module and module:IsA("ModuleScript"), "ServerScriptService.Booms (ModuleScript) missing")
-- The command bar gets its own copy of the module, but BoomCount lives on the ModuleScript, so both copies count on it.
local Booms = require(module)

local function boomCount(): number
	return module:GetAttribute("BoomCount") or 0
end

if CASE == "B" then
	local player = Players:GetPlayers()[1]
	local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	assert(root, "the player has no character: run tests/fire_play.client.luau first")
	local before = boomCount()
	local front = root.Position + root.CFrame.LookVector * 6
	local back = root.Position - root.CFrame.LookVector * 6
	Booms.at(front)
	assert(boomCount() == before + 1, "BoomCount did not go up by 1 for the first boom")
	task.wait(1)
	Booms.at(back)
	assert(boomCount() == before + 2, "BoomCount did not go up by 1 for the second boom")
	return ("PASS boom.server B (booms at %s and %s): now run case A-2 of tests/boom.client.luau"):format(tostring(front), tostring(back))
elseif CASE == "X" then
	local before = boomCount()
	local explosion = Instance.new("Explosion")
	explosion.Position = Vector3.new(0, 40, 0)
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace
	-- Deferred threads run in order, so this one runs after every DescendantAdded handler the parenting queued.
	local visible = nil
	task.defer(function()
		visible = explosion.Visible
	end)
	local deadline = os.clock() + 2
	while visible == nil and os.clock() < deadline do
		task.wait()
	end
	assert(visible == false, "the Explosion is still Visible right after parenting (" .. tostring(visible) .. ")")
	assert(boomCount() == before + 1, ("BoomCount went from %d to %d, expected +1"):format(before, boomCount()))
	return "PASS boom.server X (the Explosion was hidden at once and made one boom)"
end
error("unknown CASE " .. tostring(CASE))
