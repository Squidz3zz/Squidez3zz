-- Run in the Server datamodel of a running playtest (no player needed: start the playtest, then run this). It builds R6 bodies
-- here, far from the rooms (x 9030 and up, y 300, z 9000, root anchored unless a case needs it standing), and drives the game's
-- own Gore through ServerScriptService.GoreServer.TestHook ("call", fnName, ...). The gore level is fixed with GoreConfig
-- overrides (attributes on the module, Studio only), removed however the case ends.
--   H-A torso      Gore.hit(torso, 30) three times: Torso Intact 85, Intact 70, Torn 55; no other limb changes and Health
--                  drops by exactly 90 (the watcher does not count it again). A part on no GoreBody, and damage 0 or below,
--                  do nothing
--   H-B hat        Gore.hit(hat.Handle, 40) on a hat welded to the Head damages the Head (80)
--   H-C corpse     Gore.hit(corpse's Left Arm, 200) leaves it Broken, never Severed, over seeds 1 to 10, with no error
--   H-D floor      a body standing on an anchored floor walks into a low wall (unanchored, welded to the floor: grounded); right
--                  after the wall touches its leg, humanoid:TakeDamage(30) lands on the Torso (85), not a leg
--   H-E touch      an unanchored ball thrown at the RightLeg: within 0.1 s of its touch, TakeDamage(30) lands on the RightLeg (85)
--   H-F GoreHit    each hit (Gore.hit or an unknown one) sets GoreHit "<Limb>|<damage>|<n>", n counting up
--   H-G level 0    at GORE_LEVEL 0 Gore.hit takes the health and still marks GoreHit, but changes no limb
-- Every case runs (one failing does not stop the rest); the error lists each case's result. It removes its bodies and
-- corpses, and returns "PASS gore_hits".
local CASE = "all" -- or one letter, "A" to "G"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LIMB_KEYS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local configModule = ReplicatedStorage:WaitForChild("GoreConfig")

local server = ServerScriptService:WaitForChild("GoreServer", 10)
local hook = server and server:WaitForChild("TestHook", 10)
assert(hook and hook:IsA("BindableFunction"), "ServerScriptService.GoreServer.TestHook is missing (is Gore pushed?)")
local function gore(fnName: string, ...: any): any
	return hook:Invoke("call", fnName, ...)
end

local old = workspace:FindFirstChild("GoreHitsTest")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "GoreHitsTest"
folder.Parent = workspace
local torsos: { BasePart } = {}

local count = 0
-- A fresh R6 body at its own spot, tracked by the game's Gore. free: the root is not anchored (it stands on a floor of its own).
local function newBody(free: boolean?): (Model, BasePart?)
	count += 1
	local x = 9000 + 30 * count
	local body = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	body.Name = "Body" .. count
	body.HumanoidRootPart.Anchored = not free
	body:PivotTo(CFrame.new(x, 300, 9000))
	body.Parent = folder
	local floor
	if free then
		floor = Instance.new("Part")
		floor.Name = "Floor"
		floor.Anchored = true
		floor.Size = Vector3.new(20, 1, 20)
		floor.Position = Vector3.new(x, 296.5, 9000)
		floor.Parent = folder
		pcall(body.HumanoidRootPart.SetNetworkOwner, body.HumanoidRootPart, nil)
	end
	table.insert(torsos, body.Torso)
	task.wait(0.1) -- a Humanoid must step before its death counts
	gore("track", body)
	return body, floor
end

local function withOverrides(overrides: { [string]: any }, fn: () -> ())
	for name, value in overrides do
		configModule:SetAttribute(name, value)
	end
	local ok, err = pcall(fn)
	for name in overrides do
		configModule:SetAttribute(name, nil)
	end
	if not ok then
		error(err, 0)
	end
end

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

local function expect(body: Model, key: string, wantState: string, wantHp: number, label: string)
	local state, hp = body:GetAttribute("Gore_" .. key), body:GetAttribute("GoreHP_" .. key)
	assert(state == wantState and hp == wantHp, ("%s: %s is %s at %s, expected %s at %s"):format(label, key, tostring(state), tostring(hp), wantState, tostring(wantHp)))
end

local function untouched(body: Model, except: { [string]: boolean }, label: string)
	for _, key in LIMB_KEYS do
		if not except[key] then
			expect(body, key, "Intact", 100, label)
		end
	end
end

local cases = {}

cases.A = function()
	local body = newBody()
	for i, want in { { "Intact", 85 }, { "Intact", 70 }, { "Torn", 55 } } do
		gore("hit", body.Torso, 30)
		expect(body, "Torso", want[1], want[2], "H-A hit " .. i)
	end
	gore("hit", body.Torso, 0)
	gore("hit", body.Torso, -5)
	local stray = Instance.new("Part")
	stray.Anchored = true
	stray.Parent = folder
	gore("hit", stray, 30)
	task.wait(0.3)
	expect(body, "Torso", "Torn", 55, "H-A after 0 and -5")
	untouched(body, { Torso = true }, "H-A")
	assert(body.Humanoid.Health == 10, "H-A: three hits of 30 should leave Health 10, got " .. body.Humanoid.Health)
end

cases.B = function()
	local body = newBody()
	-- Worn the way Roblox wears one: the Humanoid welds the Handle's HatAttachment to the Head's (an AccessoryWeld).
	local hat = Instance.new("Accessory")
	hat.Name = "TestHat"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 0.4, 1)
	handle.CanCollide = false
	local attachment = Instance.new("Attachment")
	attachment.Name = "HatAttachment"
	attachment.Parent = handle
	handle.Parent = hat
	body.Humanoid:AddAccessory(hat)
	local weld = handle:FindFirstChild("AccessoryWeld")
	assert(weld and weld:IsA("Weld") and weld.Part1 == body.Head, "H-B: the hat is not welded to the Head")
	gore("hit", handle, 40)
	expect(body, "Head", "Intact", 80, "H-B")
	untouched(body, { Head = true }, "H-B")
	assert(body.Humanoid.Health == 60, "H-B: Health should be 60, got " .. body.Humanoid.Health)
end

cases.C = function()
	for seed = 1, 10 do
		local body = newBody()
		local arm = body["Left Arm"]
		gore("hurt", body, math.huge)
		assert(waitFor(function()
			local parent = arm.Parent
			return parent ~= nil and parent.Parent == workspace:FindFirstChild("Corpses")
		end, 3), "H-C: the body left no corpse (seed " .. seed .. ")")
		local corpse = arm.Parent :: Model
		gore("seed", seed)
		gore("hit", arm, 200)
		expect(corpse, "LeftArm", "Broken", 0, "H-C seed " .. seed)
	end
end

cases.D = function()
	local body, floor = newBody(true)
	local humanoid = body.Humanoid
	task.wait(1.5) -- standing, and out of any Freefall from being built (a drop counts as a fall for 0.5 s)
	local legs = body["Right Leg"]
	assert(math.abs(legs.Position.Y - 298) < 0.5, "H-D: the body is not standing on its floor (right leg at y " .. legs.Position.Y .. ")")
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Size = Vector3.new(1, 1.5, 8)
	wall.Position = Vector3.new(body.Torso.Position.X + 2.5, 297.75, 9000)
	local joint = Instance.new("WeldConstraint")
	joint.Part0 = wall
	joint.Part1 = floor :: BasePart
	joint.Parent = wall
	wall.Parent = folder
	assert(not wall.Anchored and wall:IsGrounded(), "H-D: the wall should be unanchored and grounded")
	local touchedAt
	for _, part in body:GetChildren() do
		if part:IsA("BasePart") then
			part.Touched:Connect(function(other)
				if other == wall and not touchedAt then
					touchedAt = os.clock()
				end
			end)
		end
	end
	humanoid:Move(Vector3.xAxis)
	local touched = waitFor(function()
		return touchedAt ~= nil
	end, 3)
	humanoid:Move(Vector3.zero)
	assert(touched, "H-D: the body never touched the wall")
	assert(humanoid:GetState() ~= Enum.HumanoidStateType.Freefall, "H-D: the body is falling")
	humanoid:TakeDamage(30)
	task.wait(0.3)
	expect(body, "Torso", "Intact", 85, "H-D")
	untouched(body, { Torso = true }, "H-D")
end

cases.E = function()
	local body = newBody()
	local leg = body["Right Leg"]
	local ball = Instance.new("Part")
	ball.Name = "Ball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one
	ball.Position = leg.Position + Vector3.new(3, 0, 0)
	ball.Parent = folder
	pcall(ball.SetNetworkOwner, ball, nil)
	local touchedAt
	leg.Touched:Connect(function(other)
		if other == ball and not touchedAt then
			touchedAt = os.clock()
		end
	end)
	ball.AssemblyLinearVelocity = Vector3.new(-40, 0, 0)
	assert(waitFor(function()
		return touchedAt ~= nil
	end, 2), "H-E: the ball never touched the right leg")
	body.Humanoid:TakeDamage(30)
	local after = os.clock() - touchedAt
	assert(after < 0.1, ("H-E: the damage came %.3f s after the touch"):format(after))
	task.wait(0.3)
	expect(body, "RightLeg", "Intact", 85, "H-E")
	untouched(body, { RightLeg = true }, "H-E")
end

cases.F = function()
	local body = newBody()
	task.wait(1) -- out of any Freefall from being built
	gore("hit", body["Left Arm"], 10)
	assert(body:GetAttribute("GoreHit") == "LeftArm|10|1", "H-F: GoreHit after the first hit is " .. tostring(body:GetAttribute("GoreHit")))
	gore("hit", body.Torso, 20)
	assert(body:GetAttribute("GoreHit") == "Torso|20|2", "H-F: GoreHit after the second hit is " .. tostring(body:GetAttribute("GoreHit")))
	body.Humanoid:TakeDamage(5)
	assert(waitFor(function()
		return body:GetAttribute("GoreHit") ~= "Torso|20|2"
	end, 1), "H-F: an unknown hit left GoreHit unchanged")
	assert(body:GetAttribute("GoreHit") == "Torso|5|3", "H-F: GoreHit after an unknown hit is " .. tostring(body:GetAttribute("GoreHit")))
end

cases.G = function()
	withOverrides({ GORE_LEVEL = 0 }, function()
		local body = newBody()
		gore("hit", body["Left Arm"], 40)
		task.wait(0.3)
		untouched(body, {}, "H-G")
		assert(body.Humanoid.Health == 60, "H-G: Health should be 60, got " .. body.Humanoid.Health)
		assert(body:GetAttribute("GoreHit") == "LeftArm|40|1", "H-G: GoreHit is " .. tostring(body:GetAttribute("GoreHit")))
	end)
end

local order = if CASE == "all" then { "A", "B", "C", "D", "E", "F", "G" } else { CASE }
local results, failed = {}, false
for _, name in order do
	-- Every case but G runs at GORE_LEVEL 2, whatever the module says.
	local ok, err = pcall(withOverrides, if name == "G" then {} else { GORE_LEVEL = 2 }, cases[name])
	failed = failed or not ok
	table.insert(results, name .. (if ok then " ok" else ": " .. tostring(err)))
end
task.wait(0.5) -- let the deaths finish moving into their corpses
for _, torso in torsos do
	local corpse = torso.Parent
	if corpse and corpse.Parent == workspace:FindFirstChild("Corpses") then
		corpse:Destroy()
	end
end
folder:Destroy()
assert(not failed, "FAIL gore_hits: " .. table.concat(results, " | "))
return "PASS gore_hits (H-" .. table.concat(order, ", H-") .. ")"
