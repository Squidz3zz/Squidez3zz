-- Run in the Server datamodel of a running playtest (no character needed): start the playtest, then run this.
-- Checks ReplicatedStorage.LabConfig: its values, and the limb table on a real R6 body.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local module = ReplicatedStorage:FindFirstChild("LabConfig")
assert(module and module:IsA("ModuleScript"), "ReplicatedStorage.LabConfig is missing")
local LabConfig = require(module)

-- The values.
for name, seconds in LabConfig.Timings do
	assert(type(seconds) == "number" and seconds > 0, "Timings." .. name .. " must be a number above 0")
end
assert(type(LabConfig.FUSE_SECONDS) == "number" and LabConfig.FUSE_SECONDS > 0, "FUSE_SECONDS must be above 0")
assert(#LabConfig.HardDrives >= 1, "HardDrives is empty")
for name, id in LabConfig.Sounds do
	assert(type(id) == "string" and string.match(id, "^rbxassetid://%d+$"), "Sounds." .. name .. " is not rbxassetid://<number>")
end
assert(#LabConfig.LIMB_KEYS == 6, "LIMB_KEYS should list six limbs")

-- The limb table, on a real R6 body.
local body = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
body.Parent = workspace
local strays = {}

local function expectOnly(lostKey)
	for _, key in LabConfig.LIMB_KEYS do
		assert(LabConfig.isLost(body, key) == (key == lostKey), "isLost(" .. key .. ") should be " .. tostring(key == lostKey))
		assert(
			(LabConfig.limbCentre(body, key) == nil) == (key == lostKey),
			"limbCentre(" .. key .. ") should be " .. (if key == lostKey then "nil" else "a point")
		)
	end
end

-- A whole body: every limb has a part, is not lost and has a centre; every limb except the torso has a joint.
for _, key in LabConfig.LIMB_KEYS do
	assert(#LabConfig.limbParts(body, key) >= 1, "limbParts(" .. key .. ") is empty")
	assert(
		(LabConfig.limbJoint(body, key) ~= nil) == (key ~= "Torso"),
		"limbJoint(" .. key .. ") should " .. (if key == "Torso" then "be nil" else "exist")
	)
end
expectOnly(nil)

-- Destroy the left arm's joint (found by its real name, not through LabConfig): the arm is lost at once.
body.Torso["Left Shoulder"]:Destroy()
assert(LabConfig.limbJoint(body, "LeftArm") == nil, "limbJoint(LeftArm) should be nil once its joint is gone")
expectOnly("LeftArm")

-- Its part leaves the body: still lost, and no parts left.
for _, part in LabConfig.limbParts(body, "LeftArm") do
	part.Parent = workspace
	table.insert(strays, part)
end
assert(#LabConfig.limbParts(body, "LeftArm") == 0, "limbParts(LeftArm) should be empty after the part left")
expectOnly("LeftArm")

-- A limb whose joint is intact but whose part is gone is lost too.
for _, part in LabConfig.limbParts(body, "RightLeg") do
	part.Parent = workspace
	table.insert(strays, part)
end
assert(LabConfig.isLost(body, "RightLeg"), "RightLeg with no part should be lost")
assert(LabConfig.limbCentre(body, "RightLeg") == nil, "limbCentre(RightLeg) should be nil with no part")

body:Destroy()
for _, part in strays do
	part:Destroy()
end

return "PASS lab_config"
