-- Run in the Server datamodel of a running playtest (no character needed): start the playtest, then run this.
-- Checks ReplicatedStorage.LabConfig: its values, and the limb table on a real R6 body and a real R15 body.
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

-- The limb table, on real bodies of both rigs.
for _, rig in { Enum.HumanoidRigType.R6, Enum.HumanoidRigType.R15 } do
	local body = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), rig)
	body.Parent = workspace
	local label = rig.Name
	local strays = {}
	assert(LabConfig.rigOf(body) == label, label .. ": rigOf gave " .. tostring(LabConfig.rigOf(body)))

	local function expectOnly(lostKey)
		for _, key in LabConfig.LIMB_KEYS do
			assert(
				LabConfig.isLost(body, key) == (key == lostKey),
				label .. ": isLost(" .. key .. ") should be " .. tostring(key == lostKey)
			)
			assert(
				(LabConfig.limbCentre(body, key) == nil) == (key == lostKey),
				label .. ": limbCentre(" .. key .. ") should be " .. (if key == lostKey then "nil" else "a point")
			)
		end
	end

	-- A whole body: every limb has parts, is not lost and has a centre; every limb except the torso has a joint.
	for _, key in LabConfig.LIMB_KEYS do
		assert(#LabConfig.limbParts(body, key) >= 1, label .. ": limbParts(" .. key .. ") is empty")
		assert(
			(LabConfig.limbJoint(body, key) ~= nil) == (key ~= "Torso"),
			label .. ": limbJoint(" .. key .. ") should " .. (if key == "Torso" then "be nil" else "exist")
		)
	end
	expectOnly(nil)

	-- Destroy the left arm's joint (found by its real name, not through LabConfig): the arm is lost at once.
	local leftShoulder = if label == "R6" then body.Torso["Left Shoulder"] else body.LeftUpperArm.LeftShoulder
	leftShoulder:Destroy()
	assert(LabConfig.limbJoint(body, "LeftArm") == nil, label .. ": limbJoint(LeftArm) should be nil once its joint is gone")
	expectOnly("LeftArm")

	-- Its parts leave the body: still lost, and no parts left.
	for _, part in LabConfig.limbParts(body, "LeftArm") do
		part.Parent = workspace
		table.insert(strays, part)
	end
	assert(#LabConfig.limbParts(body, "LeftArm") == 0, label .. ": limbParts(LeftArm) should be empty after the parts left")
	expectOnly("LeftArm")

	-- A limb whose joint is intact but whose parts are gone is lost too.
	for _, part in LabConfig.limbParts(body, "RightLeg") do
		part.Parent = workspace
		table.insert(strays, part)
	end
	assert(LabConfig.isLost(body, "RightLeg"), label .. ": RightLeg with no parts should be lost")
	assert(LabConfig.limbCentre(body, "RightLeg") == nil, label .. ": limbCentre(RightLeg) should be nil with no parts")

	body:Destroy()
	for _, part in strays do
		part:Destroy()
	end
end

return "PASS lab_config"
