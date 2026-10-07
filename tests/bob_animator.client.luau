-- Run in the Client datamodel during a playtest, one case at a time (set CASE below). Needs a spawned, claimed player with a whole
-- copy: start a fresh playtest, run tests/fire_play.client.luau (it presses Play), then the server step "claim" of
-- tests/tablet_menu.server.luau, then:
--   A  (B-A) reach: readRig, and every limb's injectionPose is non-nil and inside the gantry's travel, and the extension it
--      needs before clamping (the needle tip's home height minus the limb centre's height) is strictly between 0 and 6
--   B  (B-B) the needle in the limb: run tests/bob_animator.server.luau (Explosive into the left leg), then this case straight away:
--      at the end of NeedleOut (+ 0.05 s) the NeedleTip is inside the copy's left leg's box or within 0.75 studs of it, and the
--      screen reads INJECTING
--   C  (B-C) home: run straight after B: 0.2 s into Standby, ColumnPivot's X/Z is within 0.2 of BobHome's and the screen reads
--      STANDBY
--   D  (B-D) follow: needs only a spawned character outside the room (no claim) and Bob at home on Standby. The character is put
--      in the room at (40, 3.5, 25); for FOLLOW_WINDOW s, every frame, the horizontal distance from Bob's eyes (the midpoint of
--      the two EyeCenters) to it never drops below FOLLOW_DISTANCE - 1, and at the end it is between FOLLOW_DISTANCE - 1 and
--      FOLLOW_DISTANCE + 1.5
--   E  (B-E) outside: run straight after D. The character is put outside at (25, 3.5, 30); within HOME_WINDOW s ColumnPivot's X/Z
--      is within 0.5 of BobHome's
--   F  (B-F) eyes: checked on every frame of D and E (more than 5 s in all): each pupil is at most its travel radius + 0.01 from its
--      EyeCenter, measured in the eye's plane (the white is a cylinder disc: its RightVector is the normal, its diameter
--      min(Size.Y, Size.Z), and the radius is (white diameter - pupil diameter) / 2)
--   G  (B-G) flinch: needs the server step "claim" (a whole copy). Asks for Explosive into the copy's left arm through the real
--      RequestInjection remote, as the tablet does. At the end of Moving the copy's Neck C0 is turned more than 5 degrees from
--      its built C0 (read on Standby before the request); 1 s into Standby it is back within 1 degree. Run "claim" again after G.
--   H  (B-H) cornered: needs Bob at home on Standby and the character outside (as for D). The character is put at
--      (50, 3.5, 48.5), next to BobHome on the gantry's edge, where Bob cannot back off; for CORNER_WINDOW s, on every frame his eyes
--      are closer than FOLLOW_DISTANCE - 1, the NeedleTip must be above the top of the player's Head. It fails if that close state
--      never happens. It puts the character back outside at the end, so D can follow.
-- B blows the copy's left leg off, so run the server step "claim" again before another A or B.
local CASE = "A"
local FOLLOW_WINDOW = 8
local HOME_WINDOW = 6
local CORNER_WINDOW = 6

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))
local Timings = LabConfig.Timings
local FOLLOW_DISTANCE = LabConfig.FOLLOW_DISTANCE

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

local function rootPart()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	assert(root, "no character: run tests/fire_play.client.luau first")
	return root
end

local function flatDistance(a: Vector3, b: Vector3)
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

-- Bob's eyes: the midpoint of the two EyeCenters.
local function eyes()
	return (bob.Body.EyeWhiteL.EyeCenter.WorldPosition + bob.Body.EyeWhiteR.EyeCenter.WorldPosition) / 2
end

-- B-F: returns a check to call every frame, and a function giving the largest overshoot past a radius seen so far.
local function eyeChecker()
	local eyes = {}
	for _, side in { "L", "R" } do
		local white, pupil = bob.Body["EyeWhite" .. side], bob.Pupils["Pupil" .. side]
		local function diameter(part)
			return math.min(part.Size.Y, part.Size.Z)
		end
		table.insert(eyes, { side = side, white = white, pupil = pupil, radius = (diameter(white) - diameter(pupil)) / 2 })
	end
	local worst, frames = -math.huge, 0
	local function check()
		frames += 1
		for _, eye in eyes do
			local d = eye.pupil.Position - eye.white.EyeCenter.WorldPosition
			local n = eye.white.CFrame.RightVector
			local inPlane = (d - n * d:Dot(n)).Magnitude
			worst = math.max(worst, inPlane - eye.radius)
			assert(inPlane <= eye.radius + 0.01, ("B-F: Pupil%s is %.3f studs from its EyeCenter in the eye's plane (radius %.3f)"):format(eye.side, inPlane, eye.radius))
		end
	end
	return check, function()
		return ("B-F %d frames, worst %.4f past the radius"):format(frames, worst)
	end
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
		-- injectionPose clamps the extension, so check the one the limb needs before clamping.
		local needed = rig.homePivot.Y + rig.tipLocal.Y - LabConfig.limbCentre(subject, key).Y
		local where = ("%s x %.2f z %.2f ext %.2f (unclamped %.2f) yaw %.0f"):format(key, pose.x, pose.z, pose.extension, needed, math.deg(pose.yaw))
		assert(pose.x >= travel.minX and pose.x <= travel.maxX and pose.z >= travel.minZ and pose.z <= travel.maxZ, where .. " is outside the travel")
		assert(needed > 0 and needed < rig.MAX_EXTENSION, where .. ": the limb is out of the column's reach")
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
elseif CASE == "D" then
	local root = rootPart()
	assert(state() == "Standby", "Bob is not on Standby")
	assert(flatDistance(pivot.WorldPosition, room.BobHome.Position) <= 0.5, "Bob is not at home: put the character outside the room (case E) first")
	local check, eyeReport = eyeChecker()
	root.CFrame = CFrame.new(40, 3.5, 25)
	local began = os.clock()
	local closest, distance, reached = math.huge, math.huge, nil
	while os.clock() - began < FOLLOW_WINDOW do
		task.wait()
		distance = flatDistance(eyes(), root.Position)
		closest = math.min(closest, distance)
		if not reached and distance <= FOLLOW_DISTANCE + 1.5 then
			reached = os.clock() - began
		end
		check()
		assert(closest >= FOLLOW_DISTANCE - 1, ("B-D: Bob's eyes came %.2f studs from the player"):format(closest))
	end
	assert(distance >= FOLLOW_DISTANCE - 1 and distance <= FOLLOW_DISTANCE + 1.5, ("B-D: after %d s Bob's eyes are %.2f studs from the player (at %s)"):format(FOLLOW_WINDOW, distance, tostring(eyes())))
	local carriage = room.Gantry.Carriage.Position
	return ("PASS bob_animator B-D (eyes in range after %.2f s, %.2f studs at the end, closest %.2f; carriage %.2f studs away); %s"):format(reached, distance, closest, flatDistance(carriage, root.Position), eyeReport())
elseif CASE == "E" then
	local root = rootPart()
	local home = room.BobHome.Position
	local away = flatDistance(pivot.WorldPosition, home)
	assert(away > 1, "Bob is already at home: run case D first")
	local check, eyeReport = eyeChecker()
	root.CFrame = CFrame.new(25, 3.5, 30)
	local began = os.clock()
	local off = away
	while off > 0.5 and os.clock() - began < HOME_WINDOW do
		task.wait()
		off = flatDistance(pivot.WorldPosition, home)
		check()
	end
	assert(off <= 0.5, ("B-E: after %d s ColumnPivot is %.2f studs from BobHome (at %s)"):format(HOME_WINDOW, off, tostring(pivot.WorldPosition)))
	return ("PASS bob_animator B-E (home from %.2f studs away in %.2f s); %s"):format(away, os.clock() - began, eyeReport())
elseif CASE == "G" then
	assert(waitFor(function()
		return state() == "Standby"
	end, 10), "Bob is not on Standby")
	local subject = room:WaitForChild("Subject", 5)
	assert(subject and not LabConfig.isLost(subject, "LeftArm"), "no whole copy: run the server step 'claim' of tests/tablet_menu.server.luau first")
	local neck = LabConfig.limbJoint(subject, "Head")
	assert(neck, "the copy has no Neck")
	local built = neck.C0
	local function turned()
		local _, angle = (built:Inverse() * neck.C0):ToAxisAngle()
		return math.deg(angle)
	end
	local remote = ReplicatedStorage:WaitForChild("LabRemotes"):WaitForChild("RequestInjection")
	local ok, reason = remote:InvokeServer("Explosive", "LeftArm")
	assert(ok == true, "the injection was refused: " .. tostring(reason))
	assert(waitFor(function()
		return state() == "Moving"
	end, 2), "Bob never started Moving")
	waitUntil(bob:GetAttribute("PhaseStart") + Timings.Move - 0.05)
	assert(state() == "Moving", "Moving ended early")
	local atMove = turned()
	assert(atMove > 5, ("B-G: at the end of Moving the Neck C0 is only %.2f degrees from its built C0"):format(atMove))
	assert(waitFor(function()
		return state() == "Standby"
	end, Timings.NeedleOut + Timings.Hold + Timings.NeedleIn + Timings.Return + 3), "Bob never got back to Standby")
	waitUntil(bob:GetAttribute("PhaseStart") + 1)
	local atRest = turned()
	assert(atRest <= 1, ("B-G: 1 s into Standby the Neck C0 is still %.2f degrees from its built C0"):format(atRest))
	return ("PASS bob_animator B-G (Neck %.1f degrees at the end of Moving, %.3f 1 s into Standby)"):format(atMove, atRest)
elseif CASE == "H" then
	local root = rootPart()
	local head = player.Character:FindFirstChild("Head")
	assert(head, "the character has no Head")
	assert(state() == "Standby", "Bob is not on Standby")
	assert(flatDistance(pivot.WorldPosition, room.BobHome.Position) <= 0.5, "Bob is not at home: put the character outside the room (case E) first")
	local tip = bob.Needle.NeedleTip
	root.CFrame = CFrame.new(50, 3.5, 48.5)
	local began = os.clock()
	local closeFrames, nearest, clearance = 0, math.huge, math.huge
	while os.clock() - began < CORNER_WINDOW do
		task.wait()
		local gap = flatDistance(eyes(), root.Position)
		nearest = math.min(nearest, gap)
		if gap < FOLLOW_DISTANCE - 1 then
			closeFrames += 1
			local tipY, top = tip.WorldPosition.Y, head.Position.Y + head.Size.Y / 2
			clearance = math.min(clearance, tipY - top)
			if tipY <= top then
				root.CFrame = CFrame.new(25, 3.5, 30)
				error(("B-H: with Bob's eyes %.2f studs from the player, the NeedleTip is at y %.2f, not above the top of their head (y %.2f)"):format(gap, tipY, top))
			end
		end
	end
	root.CFrame = CFrame.new(25, 3.5, 30)
	assert(closeFrames > 0, ("B-H: Bob's eyes never came closer than FOLLOW_DISTANCE - 1 (nearest %.2f), so nothing was checked"):format(nearest))
	return ("PASS bob_animator B-H (%d frames with the eyes closer than %d studs, nearest %.2f; the tip at least %.2f above the head's top)"):format(closeFrames, FOLLOW_DISTANCE - 1, nearest, clearance)
end
error("unknown CASE " .. tostring(CASE))
