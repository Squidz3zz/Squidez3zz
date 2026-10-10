-- Run in the Server datamodel of a running playtest (no player needed: start the playtest, then run this). Each case builds
-- tracked R6 bodies standing on test floors of their own, far from the rooms (x 12030 and up, y 300, z 12000), and parents a
-- real Roblox Explosion (Instance.new("Explosion")) to Workspace, so the game's own ExplosionReplacer and Gore handle it. Cases
-- with no sever check fix SEVER_CHANCE at 0, so a broken limb stays on (a severed one would leave the body on purpose).
-- E-A and E-C check the push, so their Explosions have BlastPressure 0 (Roblox shoves nothing: the speed is BLAST_PUSH's
-- alone), with EXPLOSIVE_POWER overridden to 500 so the gore power is still 150 (500 * the 0.3 floor), as with the defaults.
--   E-A kill     an Explosion 2 studs from the Torso (BlastRadius 4, DestroyJointRadiusPercent 1, the defaults): the body
--                dies and leaves a corpse; every limb part is in the corpse, still on its joint (no plain flung limbs); at
--                least one limb is Torn or worse; on the frame after the corpse appears, its Torso moves away from the blast
--                at more than 5 studs/s
--   E-B alive    DestroyJointRadiusPercent 0 and BlastRadius 8, 5 studs away: the body lives and its nearest limb is Torn
--   E-C corpse   an existing (settled) corpse 3 studs from an Explosion: its limbs lose integrity and it is pushed away at
--                more than 5 studs/s
--   E-D GoreHit  a blast between two bodies sets GoreHit "<Limb>|<damage>|<n>" on both; a body out of reach gets none
--   E-E level 0  at GORE_LEVEL 0, the E-A blast leaves every joint (a Motor6D or a socket) in place
-- Every case runs (one failing does not stop the rest); the error lists each case's result. It removes its bodies, floors,
-- corpses and overrides, and returns "PASS gore_explosions".
local CASE = "all" -- or one letter, "A" to "E"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local LIMB_KEYS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local PARTS = { Head = "Head", Torso = "Torso", LeftArm = "Left Arm", RightArm = "Right Arm", LeftLeg = "Left Leg", RightLeg = "Right Leg" }
local JOINTS = { Head = "Neck", LeftArm = "Left Shoulder", RightArm = "Right Shoulder", LeftLeg = "Left Hip", RightLeg = "Right Hip" }
local configModule = ReplicatedStorage:WaitForChild("GoreConfig")

local server = ServerScriptService:WaitForChild("GoreServer", 10)
local hook = server and server:WaitForChild("TestHook", 10)
assert(hook and hook:IsA("BindableFunction"), "ServerScriptService.GoreServer.TestHook is missing (is Gore pushed?)")
local function gore(fnName: string, ...: any): any
	return hook:Invoke("call", fnName, ...)
end

local old = workspace:FindFirstChild("GoreExplosionsTest")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "GoreExplosionsTest"
folder.Parent = workspace
local torsos: { BasePart } = {}

local count = 0
-- A fresh R6 body standing on a floor of its own (root not anchored), tracked by the game's Gore. dx shifts it along x from
-- the case's spot; a new spot every call unless `same` (then it shares the last one).
local function newBody(dx: number?, same: boolean?): Model
	if not same then
		count += 1
	end
	local x = 12000 + 40 * count + (dx or 0)
	local body = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	body.Name = "Body" .. count
	body:PivotTo(CFrame.new(x, 300, 12000))
	body.Parent = folder
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Size = Vector3.new(30, 1, 30)
	floor.Position = Vector3.new(x, 296.5, 12000)
	floor.Parent = folder
	pcall(body.HumanoidRootPart.SetNetworkOwner, body.HumanoidRootPart, nil)
	table.insert(torsos, body.Torso)
	task.wait(0.1) -- a Humanoid must step before its death counts
	gore("track", body)
	return body
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

local function waitFor(check: () -> any, timeout: number): any
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = check()
		if value then
			return value
		end
		task.wait()
	end
	return check()
end

local function boom(position: Vector3, props: { [string]: any }?): Explosion
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	for name, value in props or {} do
		(explosion :: any)[name] = value
	end
	explosion.Parent = workspace
	return explosion
end

-- The corpse a body's Torso moved into, once it has.
local function corpseOf(torso: BasePart): Model?
	local parent = torso.Parent
	return if parent and parent.Parent == workspace:FindFirstChild("Corpses") then parent :: Model else nil
end

-- Every limb of `body` still on its joint (Motor6D or BallSocketConstraint, under the Torso, joining it to the limb part).
local function jointsInPlace(body: Model, label: string)
	local torso = body:FindFirstChild("Torso")
	assert(torso, label .. ": no Torso in " .. body:GetFullName())
	for key, jointName in JOINTS do
		local joint = torso:FindFirstChild(jointName)
		local part = body:FindFirstChild(PARTS[key])
		assert(part, ("%s: %s is not in %s"):format(label, PARTS[key], body:GetFullName()))
		local joined = joint
			and (
				(joint:IsA("Motor6D") and joint.Part1 == part)
				or (joint:IsA("BallSocketConstraint") and joint.Attachment1 and joint.Attachment1.Parent == part)
			)
		assert(joined, ("%s: %s is not on its joint %s (found %s)"):format(label, PARTS[key], jointName, if joint then joint.ClassName else "nothing"))
	end
end

local function awaySpeed(part: BasePart, from: Vector3): number
	return part.AssemblyLinearVelocity:Dot((part.Position - from).Unit)
end

-- The E-A blast (also E-E's): 2 studs from the Torso, the defaults but for props. Returns the corpse and the blast position.
local function killingBlast(label: string, props: { [string]: any }?): (Model, Vector3)
	local body = newBody()
	task.wait(1) -- standing on its floor
	local torso = body.Torso
	local at = torso.Position + Vector3.new(2, 0, 0)
	boom(at, props)
	local corpse = waitFor(function()
		return corpseOf(torso)
	end, 3)
	assert(corpse, label .. ": the body left no corpse")
	assert(body.Humanoid.Health == 0, label .. ": the body is still alive")
	return corpse, at
end

local cases = {}

cases.A = function()
	local corpse, at = killingBlast("E-A", { BlastPressure = 0 })
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	local speed = awaySpeed(corpse.Torso, at)
	jointsInPlace(corpse, "E-A")
	local worst = nil
	for _, key in LIMB_KEYS do
		local state = corpse:GetAttribute("Gore_" .. key)
		if state ~= "Intact" then
			worst = key .. " " .. tostring(state)
		end
	end
	assert(worst, "E-A: every limb is still Intact")
	assert(speed > 5, ("E-A: the corpse's Torso moves away at %.2f studs/s, expected more than 5"):format(speed))
end

cases.B = function()
	local body = newBody()
	task.wait(1)
	local at = body.Torso.Position + Vector3.new(5, 0, 0)
	local nearest, best = nil, math.huge
	for _, key in LIMB_KEYS do
		local d = (body[PARTS[key]].Position - at).Magnitude
		if d < best then
			nearest, best = key, d
		end
	end
	boom(at, { DestroyJointRadiusPercent = 0, BlastRadius = 8 })
	task.wait(0.5)
	assert(body.Humanoid.Health > 0, "E-B: the body died")
	assert(body:GetAttribute("Gore_" .. nearest) == "Torn", ("E-B: the nearest limb %s is %s at %s, expected Torn"):format(nearest, tostring(body:GetAttribute("Gore_" .. nearest)), tostring(body:GetAttribute("GoreHP_" .. nearest))))
end

cases.C = function()
	local body = newBody()
	local torso = body.Torso
	gore("hurt", body, math.huge)
	local corpse = waitFor(function()
		return corpseOf(torso)
	end, 3)
	assert(corpse, "E-C: the body left no corpse")
	task.wait(2) -- lying still
	local before = 0
	for _, key in LIMB_KEYS do
		before += corpse:GetAttribute("GoreHP_" .. key)
	end
	local at = torso.Position + Vector3.new(3, 0, 0)
	boom(at, { BlastPressure = 0 })
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	local speed = awaySpeed(torso, at)
	local after = 0
	for _, key in LIMB_KEYS do
		after += corpse:GetAttribute("GoreHP_" .. key)
	end
	assert(after < before, ("E-C: the corpse's limbs total %s integrity before and %s after the blast"):format(before, after))
	assert(speed > 5, ("E-C: the corpse's Torso moves away at %.2f studs/s, expected more than 5"):format(speed))
end

cases.D = function()
	local a = newBody(-3)
	local b = newBody(3, true)
	local far = newBody()
	task.wait(1)
	boom((a.Torso.Position + b.Torso.Position) / 2, { DestroyJointRadiusPercent = 0, BlastRadius = 8 })
	task.wait(0.3)
	for name, body in { a = a, b = b } do
		local mark = body:GetAttribute("GoreHit")
		assert(type(mark) == "string" and string.match(mark, "^%a+|[%d%.e%-]+|%d+$"), ("E-D: GoreHit on body %s is %s"):format(name, tostring(mark)))
	end
	assert(far:GetAttribute("GoreHit") == nil, "E-D: the body out of reach has GoreHit " .. tostring(far:GetAttribute("GoreHit")))
end

cases.E = function()
	withOverrides({ GORE_LEVEL = 0 }, function()
		local corpse = killingBlast("E-E")
		task.wait(0.3)
		jointsInPlace(corpse, "E-E")
	end)
end

local order = if CASE == "all" then { "A", "B", "C", "D", "E" } else { CASE }
local results, failed = {}, false
for _, name in order do
	-- GORE_LEVEL 2 (E sets its own 0) and SEVER_CHANCE 0, whatever the module says; A and C also EXPLOSIVE_POWER 500.
	local overrides: { [string]: any } = if name == "E" then { SEVER_CHANCE = 0 } else { GORE_LEVEL = 2, SEVER_CHANCE = 0 }
	if name == "A" or name == "C" then
		overrides.EXPLOSIVE_POWER = 500
	end
	local ok, err = pcall(withOverrides, overrides, cases[name])
	failed = failed or not ok
	table.insert(results, name .. (if ok then " ok" else ": " .. tostring(err)))
end
task.wait(0.5) -- let the deaths finish moving into their corpses
for _, torso in torsos do
	local corpse = corpseOf(torso)
	if corpse then
		corpse:Destroy()
	end
end
folder:Destroy()
assert(not failed, "FAIL gore_explosions: " .. table.concat(results, " | "))
return "PASS gore_explosions (E-" .. table.concat(order, ", E-") .. ")"
