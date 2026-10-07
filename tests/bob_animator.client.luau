-- Run in the Client datamodel during a playtest, one case at a time (set CASE below). Needs a spawned, claimed player with a whole
-- copy: start a fresh playtest, run tests/fire_play.client.luau (it presses Play), then the server step "claim" of
-- tests/tablet_menu.server.luau, then:
--   A  (B-A) reach: readRig, and every limb's injectionPose is non-nil, inside the gantry's travel and 0 <= extension <= 6
--   B  (B-B) the needle in the limb: run tests/bob_animator.server.luau (Explosive into the left leg), then this case straight away:
--      at the end of NeedleOut (+ 0.05 s) the NeedleTip is inside the copy's left leg's box or within 0.75 studs of it, and the
--      screen reads INJECTING
--   C  (B-C) home: run straight after B: 0.2 s into Standby, ColumnPivot's X/Z is within 0.2 of BobHome's and the screen reads
--      STANDBY
-- B blows the copy's left leg off, so run the server step "claim" again before another A or B.
local CASE = "A"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
local Timings = LabConfig.Timings

local player = Players.LocalPlayer
local room = workspace:WaitForChild("Room1", 10)
assert(room, "Workspace.Room1 missing on the client")
local bob = room:WaitForChild("BobTheInjector")
local headline = bob.Body.Screen.Display.Headline
local pivot = bob.Column.Core.ColumnPivot

local function waitFor(predicate, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		task.wait()
	end
	return predicate()
end

local function now()
	return workspace:GetServerTimeNow()
end

local function waitUntil(serverTime)
	while now() < serverTime do
		task.wait()
	end
end

local function state()
	return bob:GetAttribute("State")
end

-- A fresh copy of the BobAnimator module (so a push mid-playtest is picked up; the real one LabClient started is left alone).
local function animatorModule()
	local labClient = player:WaitForChild("PlayerScripts"):WaitForChild("LabClient")
	local source = labClient:FindFirstChild("BobAnimator")
	assert(source and source:IsA("ModuleScript"), "LabClient.BobAnimator (ModuleScript) missing")
	return require(source:Clone())
end

if CASE == "A" then
	local BobAnimator = animatorModule()
	assert(waitFor(function()
		return state() == "Standby"
	end, 10), "Bob is not on Standby")
	local subject = room:WaitForChild("Subject", 5)
	assert(subject, "no Room1.Subject: run the server step 'claim' of tests/tablet_menu.server.luau first")
	local rig = BobAnimator.readRig(room)
	local travel = rig.travel
	local report = {}
	for _, key in LabConfig.LIMB_KEYS do
		local pose = BobAnimator.injectionPose(rig, subject, key)
		assert(pose, "no injection pose for " .. key)
		local where = ("%s x %.2f z %.2f ext %.2f yaw %.0f"):format(key, pose.x, pose.z, pose.extension, math.deg(pose.yaw))
		assert(pose.x >= travel.minX and pose.x <= travel.maxX and pose.z >= travel.minZ and pose.z <= travel.maxZ, where .. " is outside the travel")
		assert(pose.extension >= 0 and pose.extension <= rig.MAX_EXTENSION, where .. ": extension out of range")
		table.insert(report, where)
	end
	return "PASS bob_animator B-A (" .. table.concat(report, "; ") .. ")"
elseif CASE == "B" then
	assert(waitFor(function()
		return state() == "Injecting"
	end, Timings.Move + 5), "Bob never started Injecting: run tests/bob_animator.server.luau first")
	local start = bob:GetAttribute("PhaseStart")
	assert(now() < start + Timings.NeedleOut + Timings.Hold - 0.1, "ran too late (the Hold is over): run the server step and this case back to back")
	waitUntil(start + Timings.NeedleOut + 0.05)
	local tip = bob.Needle.NeedleTip.WorldPosition
	local text = headline.Text
	local leg = room.Subject["Left Leg"]
	local inLeg = leg.CFrame:PointToObjectSpace(tip)
	local half = leg.Size / 2
	local nearest = inLeg:Max(-half):Min(half)
	local gap = (inLeg - nearest).Magnitude
	assert(gap <= 0.75, ("the NeedleTip %s is %.2f studs from the left leg's box (centre %s)"):format(tostring(tip), gap, tostring(leg.Position)))
	assert(text == "INJECTING", "Headline reads " .. text)
	return ("PASS bob_animator B-B (the tip is %.2f studs from the left leg's box)"):format(gap)
elseif CASE == "C" then
	assert(waitFor(function()
		return state() == "Standby"
	end, Timings.Move + Timings.NeedleOut + Timings.Hold + Timings.NeedleIn + Timings.Return + 3), "Bob never got back to Standby")
	waitUntil(bob:GetAttribute("PhaseStart") + 0.2)
	local at, home = pivot.WorldPosition, room.BobHome.Position
	local off = Vector3.new(at.X - home.X, 0, at.Z - home.Z).Magnitude
	assert(off <= 0.2, ("ColumnPivot is %.2f studs from BobHome (at %s)"):format(off, tostring(at)))
	assert(headline.Text == "STANDBY", "Headline reads " .. headline.Text)
	return ("PASS bob_animator B-C (%.3f studs from BobHome)"):format(off)
end
error("unknown CASE " .. tostring(CASE))
