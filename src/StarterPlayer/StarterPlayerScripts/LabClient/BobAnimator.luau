-- BobAnimator: Bob the Injector on this player's screen. The server only publishes what Bob is doing, as attributes on
-- Room1.BobTheInjector (State, Target, HardDrive, PhaseStart); every client moves its own copy of Bob's anchored parts each frame,
-- and the server never moves them, so these moves stand.
--   readRig(room)                        Bob and the gantry as built (the home pose): each part's offset from ColumnPivot, the
--                                        needle tip and direction, the carriage's travel. Call it while Bob is at home.
--   applyPose(rig, pose, needle, swing)  puts the gantry and Bob in a pose, the needle pushed `needle` studs along its axis and the
--                                        body tilted by swing (pitch X, roll Y, radians) about ColumnPivot
--   injectionPose(rig, copy, limbKey)    the pose that leaves the needle tip NEEDLE_OUT short of the limb's centre (so pushing it
--                                        out lands it there), approaching from the copy's front (its left for LeftArm, its right
--                                        for RightArm); nil when the limb is lost
--   start(room, config) / stop()         animate every frame from the attributes (start is safe to call again)
-- A pose is { x, z (the carriage's centre, which is the column's axis), extension (studs the column is lowered, 0 = as built),
-- yaw (the needle's heading, radians about +Y, 0 = facing -Z, as in CFrame.Angles(0, yaw, 0)) }.
-- Phases, each eased (smoothstep) from where Bob was when it began and timed from PhaseStart, so a late joiner lands in the right place:
--   Moving     to the target limb's injection pose over Timings.Move (if the limb goes on the way, he stops where he is)
--   Injecting  the needle slides out over NeedleOut, stays in for Hold (NeedleHiss plays), slides back over NeedleIn
--   Returning  home over Return; Standby stays home
-- The screen (Body.Screen.Display) shows the phase, STANDBY pulsing. BobMotor hums from the carriage, louder the faster it goes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local LabConfig = require(ReplicatedStorage:WaitForChild("LabConfig"))

-- The carriage centre's travel along the gantry.
local TRAVEL = { minX = 35.5, maxX = 56, minZ = 19.2, maxZ = 52.2 }
local MAX_EXTENSION = 6
local NEEDLE_OUT = 1.5
local MOTOR_FULL_SPEED = 6 -- studs/s at which BobMotor is loudest
local MOTOR_VOLUME = 0.6
local PULSE_SECONDS = 2 -- one STANDBY pulse

export type Pose = { x: number, z: number, extension: number, yaw: number }

local BobAnimator = {}

local function parts(model: Instance): { BasePart }
	local list = {}
	for _, thing in model:GetDescendants() do
		if thing:IsA("BasePart") then
			table.insert(list, thing)
		end
	end
	return list
end

function BobAnimator.readRig(room: Model)
	local bob, gantry = room.BobTheInjector, room.Gantry
	local homePivot = bob.Column.Core.ColumnPivot.WorldCFrame
	local needle = bob.Needle
	local tip, base = needle.NeedleTip.WorldPosition, needle.NeedleBase.WorldPosition
	local look = homePivot.LookVector
	local rig = {
		homePivot = homePivot,
		home = { x = homePivot.X, z = homePivot.Z, extension = 0, yaw = math.atan2(-look.X, -look.Z) },
		offsets = {},
		tipLocal = homePivot:PointToObjectSpace(tip),
		needleDirLocal = homePivot:VectorToObjectSpace(tip - base).Unit,
		travel = TRAVEL,
		MAX_EXTENSION = MAX_EXTENSION,
		NEEDLE_OUT = NEEDLE_OUT,
		column = parts(bob.Column),
		swinging = parts(bob.Body), -- with the pupils (Task 9 moves those itself)
		needle = needle,
		carriage = gantry.Carriage,
		sleeve = gantry.Sleeve,
		crossbeam = gantry.Crossbeam,
	}
	for _, part in parts(bob.Pupils) do
		table.insert(rig.swinging, part)
	end
	for _, list in { rig.column, rig.swinging, { needle, rig.carriage, rig.sleeve, rig.crossbeam } } do
		for _, part in list do
			rig.offsets[part] = homePivot:ToObjectSpace(part.CFrame)
		end
	end
	return rig
end

function BobAnimator.applyPose(rig, pose: Pose, needle: number, swing: Vector2)
	local home, offsets = rig.homePivot, rig.offsets
	local x = math.clamp(pose.x, rig.travel.minX, rig.travel.maxX)
	local z = math.clamp(pose.z, rig.travel.minZ, rig.travel.maxZ)
	-- The gantry only slides: the carriage and the sleeve with Bob, the crossbeam along the rails (Z).
	local slide = Vector3.new(x - home.X, 0, z - home.Z)
	rig.carriage.CFrame = home * offsets[rig.carriage] + slide
	rig.sleeve.CFrame = home * offsets[rig.sleeve] + slide
	rig.crossbeam.CFrame = home * offsets[rig.crossbeam] + Vector3.new(0, 0, slide.Z)

	local pivot = CFrame.new(x, home.Y - pose.extension, z) * CFrame.Angles(0, pose.yaw, 0)
	for _, part in rig.column do
		part.CFrame = pivot * offsets[part]
	end
	local tilted = pivot * CFrame.Angles(swing.X, 0, swing.Y)
	for _, part in rig.swinging do
		part.CFrame = tilted * offsets[part]
	end
	rig.needle.CFrame = tilted * offsets[rig.needle] + tilted:VectorToWorldSpace(rig.needleDirLocal) * needle
end

function BobAnimator.injectionPose(rig, copy: Model?, limbKey: string): Pose?
	local root = copy and copy:FindFirstChild("HumanoidRootPart")
	local centre = root and LabConfig.limbCentre(copy, limbKey)
	if not centre then
		return nil
	end
	local f = root.CFrame -- the copy faces f.LookVector
	local d = (limbKey == "LeftArm" and f.RightVector) or (limbKey == "RightArm" and -f.RightVector) or -f.LookVector
	d = Vector3.new(d.X, 0, d.Z).Unit -- the direction the needle points
	local restTip = centre - d * rig.NEEDLE_OUT -- extending NEEDLE_OUT lands the tip on the limb's centre
	local yaw = math.atan2(-d.X, -d.Z) -- the pivot (and so the needle) faces along d
	local tipOffset = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(rig.tipLocal)
	local extension = (rig.homePivot.Y + rig.tipLocal.Y) - restTip.Y
	return { x = restTip.X - tipOffset.X, z = restTip.Z - tipOffset.Z, extension = math.clamp(extension, 0, rig.MAX_EXTENSION), yaw = yaw }
end

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function blend(a: Pose, b: Pose, t: number): Pose
	local turn = (b.yaw - a.yaw + math.pi) % (2 * math.pi) - math.pi -- the short way round
	return {
		x = a.x + (b.x - a.x) * t,
		z = a.z + (b.z - a.z) * t,
		extension = a.extension + (b.extension - a.extension) * t,
		yaw = a.yaw + turn * t,
	}
end

-- "LeftArm" -> "LEFT ARM"
local function limbWords(key: string): string
	return string.upper((key:gsub("(%l)(%u)", "%1 %2")))
end

local function sound(parent: Instance, name: string, id: string): Sound
	local s = parent:FindFirstChild(name) or Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.SoundGroup = SoundService:FindFirstChild("SFX")
	s.Parent = parent
	return s :: Sound
end

local running = false
local connection: RBXScriptConnection? = nil
local stopping: (() -> ())? = nil

function BobAnimator.start(room: Model, config)
	if running then
		return
	end
	running = true
	local bob = room:WaitForChild("BobTheInjector", 30)
	assert(bob and room:WaitForChild("Gantry", 30), "Room1.BobTheInjector or Room1.Gantry did not appear")
	local rig = BobAnimator.readRig(room)
	local Timings = config.Timings
	local display = bob.Body.Screen.Display
	local headline, detail = display.Headline, display.Detail
	local motor = sound(rig.carriage, "BobMotor", config.Sounds.BobMotor)
	motor.Looped = true
	motor.Volume = 0
	motor:Play()
	local hiss = sound(rig.needle, "NeedleHiss", config.Sounds.NeedleHiss)

	local hardDriveNames = {}
	for _, item in config.HardDrives do
		hardDriveNames[item.id] = item.name
	end

	local pose: Pose, needle = rig.home, 0
	local phaseState, phaseStart, from, fromNeedle, hissed = nil, nil, pose, 0, false
	local function frame(dt: number)
		local state = bob:GetAttribute("State")
		local start = bob:GetAttribute("PhaseStart") or 0
		local target = bob:GetAttribute("Target") or ""
		if state ~= phaseState or start ~= phaseStart then
			phaseState, phaseStart, from, fromNeedle, hissed = state, start, pose, needle, false
		end
		local t = workspace:GetServerTimeNow() - start

		-- Moving and Injecting aim at the target limb (nil once it is lost: Bob stays where he is); anything else goes home.
		local goal, seconds = rig.home, Timings.Return
		if state == "Moving" or state == "Injecting" then
			goal = BobAnimator.injectionPose(rig, room:FindFirstChild("Subject"), target)
			seconds = if state == "Moving" then Timings.Move else Timings.NeedleOut
		end
		local a = smooth(t / seconds)
		if goal then
			pose = blend(from, goal, a)
		end

		local out, hold = Timings.NeedleOut, Timings.Hold
		if state == "Injecting" then
			needle = NEEDLE_OUT * (if t < out then smooth(t / out) elseif t < out + hold then 1 else 1 - smooth((t - out - hold) / Timings.NeedleIn))
		else
			needle = fromNeedle * (1 - a)
		end
		local holding = state == "Injecting" and t >= out and t < out + hold
		if holding and not hissed then
			hissed = true
			hiss:Play()
		elseif not holding and hiss.IsPlaying then
			hiss:Stop()
		end

		local before = rig.carriage.Position
		BobAnimator.applyPose(rig, pose, needle, Vector2.zero)
		local speed = if dt > 0 then (rig.carriage.Position - before).Magnitude / dt else 0
		motor.Volume = math.clamp(speed / MOTOR_FULL_SPEED, 0, 1) * MOTOR_VOLUME

		headline.TextTransparency = 0
		if state == "Moving" then
			headline.Text, detail.Text = "TARGET: " .. limbWords(target), hardDriveNames[bob:GetAttribute("HardDrive")] or ""
		elseif state == "Injecting" then
			headline.Text, detail.Text = "INJECTING", limbWords(target)
		elseif state == "Returning" then
			headline.Text, detail.Text = "RETURNING", ""
		else
			headline.Text, detail.Text = "STANDBY", ""
			headline.TextTransparency = 0.3 - 0.3 * math.cos(os.clock() * 2 * math.pi / PULSE_SECONDS)
		end
	end

	local warned = false
	connection = RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(frame, dt)
		if not ok and not warned then
			warned = true
			warn("BobAnimator: a frame failed: " .. tostring(err))
		end
	end)
	stopping = function()
		motor:Stop()
		hiss:Stop()
		BobAnimator.applyPose(rig, rig.home, 0, Vector2.zero)
	end
end

-- Stops animating and puts Bob back home, silent.
function BobAnimator.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if stopping then
		stopping()
		stopping = nil
	end
	running = false
end

return BobAnimator
