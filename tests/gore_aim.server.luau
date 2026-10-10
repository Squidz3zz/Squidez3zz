-- Run in the Server datamodel of a running playtest (no player needed: start the playtest, then run this). It builds pairs of
-- linked R6 bodies (a "copy" and its "owner", as the lab links them) here, far from the rooms (x 8030 and up, y 300, z 8000,
-- root anchored, each on a floor of its own), and drives the game's own Gore through ServerScriptService.GoreServer.TestHook
-- ("call", fnName, ...). Chances and the gore level (2, except in A-G) are fixed with GoreConfig overrides (attributes on the
-- module, Studio only), removed however the case ends.
--   A-A aimed     Gore.blastLimb(copy, "LeftArm", 150): the left arm is Broken or Severed on both bodies, and the Torso, Head,
--                 RightArm, LeftLeg and RightLeg are Intact at 100 on both
--   A-B explode   Gore.explode at the copy's left arm (150, radius 6) still tears the Torso: the radius blast is unchanged
--   A-C two arms  blastLimb LeftArm, then RightArm: both bodies still live
--   A-D head      damageLimb(copy, "Head", 45, "hit") tears the head: both bodies are at Health 0 within 0.2 s, and the copy
--                 becomes a corpse in Workspace.Corpses
--   A-E open      with TORSO_OPEN_CHANCE 1, blastLimb(copy, "Torso", 50) tears and opens the torso: both die
--   A-F sealed    with TORSO_OPEN_CHANCE 0 the same blast leaves the torso Torn and sealed, and both live
--   A-G level 0   with GORE_LEVEL 0 a torn head does not kill
-- Every case runs (one failing does not stop the rest); the error lists each case's result. It removes its bodies and
-- corpses, and returns "PASS gore_aim".
local CASE = "all" -- or one letter, "A" to "G"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local configModule = ReplicatedStorage:WaitForChild("GoreConfig")

local server = ServerScriptService:WaitForChild("GoreServer", 10)
local hook = server and server:WaitForChild("TestHook", 10)
assert(hook and hook:IsA("BindableFunction"), "ServerScriptService.GoreServer.TestHook is missing (is Gore pushed?)")
local function gore(fnName: string, ...: any): any
	return hook:Invoke("call", fnName, ...)
end

local old = workspace:FindFirstChild("GoreAimTest")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "GoreAimTest"
folder.Parent = workspace
local torsos: { BasePart } = {}

local count = 0
local function newBody(name: string): Model
	count += 1
	local x = 8000 + 30 * count
	local body = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	body.Name = name .. count
	body.HumanoidRootPart.Anchored = true
	body:PivotTo(CFrame.new(x, 300, 8000))
	body.Parent = folder
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(20, 1, 20)
	floor.Position = Vector3.new(x, 296.5, 8000)
	floor.Parent = folder
	table.insert(torsos, body.Torso)
	return body
end

-- A copy and its owner, tracked and linked by the game's Gore.
local function newPair(): (Model, Model)
	local copy, owner = newBody("Copy"), newBody("Owner")
	task.wait(0.1) -- a Humanoid must step before its death counts
	gore("track", copy)
	gore("track", owner)
	gore("link", copy, owner)
	return copy, owner
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

local function health(body: Model): number
	return body:FindFirstChildOfClass("Humanoid").Health
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

local function bothDead(copy: Model, owner: Model): boolean
	return health(copy) == 0 and health(owner) == 0
end

local cases = {}

cases.A = function()
	local copy, owner = newPair()
	gore("blastLimb", copy, "LeftArm", 150)
	for _, body in { copy, owner } do
		local arm = body:GetAttribute("Gore_LeftArm")
		assert(arm == "Broken" or arm == "Severed", ("A-A: %s's left arm is %s"):format(body.Name, tostring(arm)))
		for _, key in { "Torso", "Head", "RightArm", "LeftLeg", "RightLeg" } do
			local state, hp = body:GetAttribute("Gore_" .. key), body:GetAttribute("GoreHP_" .. key)
			assert(state == "Intact" and hp == 100, ("A-A: %s's %s is %s at %s, expected Intact at 100"):format(body.Name, key, tostring(state), tostring(hp)))
		end
	end
	assert(copy:GetAttribute("Gore_LeftArm") == owner:GetAttribute("Gore_LeftArm"), "A-A: the two left arms differ")
end

cases.B = function()
	local copy, owner = newPair()
	gore("explode", copy["Left Arm"].Position, 150, 6)
	for _, body in { copy, owner } do
		assert(body:GetAttribute("Gore_Torso") ~= "Intact", "A-B: the radius blast at the arm left " .. body.Name .. "'s torso Intact")
	end
end

cases.C = function()
	local copy, owner = newPair()
	gore("blastLimb", copy, "LeftArm", 150)
	gore("blastLimb", copy, "RightArm", 150)
	task.wait(0.3)
	for _, body in { copy, owner } do
		assert(health(body) > 0, ("A-C: %s died after two arm blasts"):format(body.Name))
	end
end

cases.D = function()
	local copy, owner = newPair()
	local head = copy.Head
	gore("damageLimb", copy, "Head", 45, "hit")
	assert(copy:GetAttribute("Gore_Head") == "Torn", "A-D: 45 hit damage should tear the head, it is " .. tostring(copy:GetAttribute("Gore_Head")))
	assert(waitFor(function()
		return bothDead(copy, owner)
	end, 0.2), ("A-D: a torn head left Health %s on the copy, %s on the owner"):format(health(copy), health(owner)))
	assert(waitFor(function()
		local parent = head.Parent
		return parent ~= nil and parent.Parent == workspace:FindFirstChild("Corpses")
	end, 3), "A-D: the copy left no corpse")
end

cases.E = function()
	withOverrides({ TORSO_OPEN_CHANCE = 1 }, function()
		local copy, owner = newPair()
		gore("blastLimb", copy, "Torso", 50)
		assert(copy:GetAttribute("Gore_Torso") == "Torn" and copy:GetAttribute("GoreTorsoOpen") == true, "A-E: the torso should be torn and open")
		assert(waitFor(function()
			return bothDead(copy, owner)
		end, 0.2), ("A-E: an open torso left Health %s on the copy, %s on the owner"):format(health(copy), health(owner)))
	end)
end

cases.F = function()
	withOverrides({ TORSO_OPEN_CHANCE = 0 }, function()
		local copy, owner = newPair()
		gore("blastLimb", copy, "Torso", 50)
		task.wait(0.3)
		for _, body in { copy, owner } do
			assert(body:GetAttribute("Gore_Torso") == "Torn" and body:GetAttribute("GoreTorsoOpen") == false, "A-F: " .. body.Name .. "'s torso should be torn and sealed")
			assert(health(body) > 0, "A-F: a torn sealed torso killed " .. body.Name)
		end
	end)
end

cases.G = function()
	withOverrides({ GORE_LEVEL = 0 }, function()
		local copy, owner = newPair()
		gore("damageLimb", copy, "Head", 45, "hit")
		task.wait(0.3)
		for _, body in { copy, owner } do
			assert(body:GetAttribute("Gore_Head") == "Torn", "A-G: " .. body.Name .. "'s head should be torn")
			assert(health(body) > 0, "A-G: at GORE_LEVEL 0 a torn head killed " .. body.Name)
		end
	end)
end

local order = if CASE == "all" then { "A", "B", "C", "D", "E", "F", "G" } else { CASE }
local results, failed = {}, false
for _, name in order do
	-- A-A to A-F run at GORE_LEVEL 2, whatever the module says (A-G sets its own).
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
assert(not failed, "FAIL gore_aim: " .. table.concat(results, " | "))
return "PASS gore_aim (A-" .. table.concat(order, ", A-") .. ")"
