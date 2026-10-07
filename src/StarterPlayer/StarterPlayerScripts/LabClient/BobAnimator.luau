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
-- Phases, each eased (smoothstep) from where Bob was when it began and timed from PhaseStart, so a late joiner lands in the right
-- place. Each phase picks its way round when it begins and keeps it (a half turn goes back toward home's side, never by rounding):
--   Moving     to the target limb's injection pose over Timings.Move (if the limb goes on the way, he stops where he is)
--   Injecting  aims where the limb was when it began (so the copy's flinch cannot shake him); the needle slides out over
--              NeedleOut, stays in for Hold (NeedleHiss plays), slides back over NeedleIn
--   Returning  home over Return
--   Standby    following: he watches the player closest to him whose HumanoidRootPart is inside Room1.Zone (the copy is not a
--              player). The carriage heads for the spot FOLLOW_DISTANCE from them on his side (inside the travel) at most
--              FOLLOW_SPEED, starting gently and slowing as he arrives; he turns to face them at most TURN_SPEED and lowers the
--              needle tip to their head's height. With nobody to watch he goes home the same way.
-- Swing: the body (and the needle) hangs from ColumnPivot like a pendulum on a damped spring, leaning away from the carriage's
-- acceleration in Bob's frame, at most SWING_MAX each way. It dies away while the needle goes in, so the needle lands.
-- Eyes: each pupil is a GooglyEyes simulation in its white's plane. A white and a pupil are Cylinder discs: the normal is the
-- part's RightVector, the plane's axes its LookVector (x) and UpVector (y), the diameter min(Size.Y, Size.Z), and the pupil's
-- travel radius (white diameter - pupil diameter) / 2; it keeps its built depth along the normal. Each frame it gets gravity,
-- the white's own acceleration and, on Standby, a pull toward the watched player's head. An Explosion inside the zone spins
-- both (SPIN x radius, studs/s).
-- The copy's flinch (on this client only, by editing the copy's joints' C0): while Moving or Injecting its head turns toward
-- NeedleTip (Neck C0, at most FLINCH_YAW and FLINCH_PITCH, smoothed), Returning holds it, and on Standby it faces forward again
-- over RELAX s; during Hold the target limb's joint twitches a few degrees, and goes back as built when the Hold ends. A joint's
-- C0 is saved the first time it is seen, before anything touches it, and stop() puts every saved one back.
-- The screen (Body.Screen.Display) shows the phase, STANDBY pulsing. BobMotor hums from the carriage, louder the faster it goes.
local Players = game:GetService("Players")
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
-- Standby
local FOLLOW_SPEED = 4 -- studs/s, the carriage's top speed
local TURN_SPEED = math.rad(90) -- per second
local ARRIVE = 2 -- per second: the share of the way left he covers in a second near the end, so he slows as he arrives
local GET_GOING = 6 -- per second: how fast the carriage's speed catches up with the speed he wants, so he starts gently
-- Swing
local SWING_MAX = math.rad(12)
local SWING_STIFFNESS = 36 -- (rad/s)^2: a swing of about one second
local SWING_DAMPING = 4 -- per second
-- Eyes and the copy's flinch
local SMOOTH = 20 -- per second: how fast a tracked velocity follows the real one (its change is the acceleration)
local SPIN = 40 -- a blast spins each pupil at SPIN x its travel radius, studs/s
local FLINCH_YAW, FLINCH_PITCH = math.rad(70), math.rad(35)
local FLINCH_RATE = 8 -- per second: how fast the head catches up with the needle
local RELAX = 0.5 -- seconds to face forward again on Standby
local TWITCH = math.rad(4)
local MAX_STEP = 1 / 10 -- the longest frame that following, the swing and the flinch simulate (a slower frame rate slows them)

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
		swinging = parts(bob.Body), -- with the pupils (as built; start() then rolls them inside their whites every frame)
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

-- The short way round from yaw a to yaw b. Front-approach poses are exactly half a turn from home, so a half turn goes back
-- toward home's side (out one way, home the other) instead of a side picked by rounding.
local function turnBetween(a: number, b: number, home: number): number
	local turn = (b - a + math.pi) % (2 * math.pi) - math.pi
	if math.abs(turn) > math.pi - 1e-3 then
		turn = if a < home - 1e-3 then math.pi else -math.pi
	end
	return turn
end

-- turn: the way round from a.yaw, chosen when the phase began
local function blend(a: Pose, b: Pose, t: number, turn: number): Pose
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

local function inside(zone: BasePart, at: Vector3): boolean
	local p = zone.CFrame:PointToObjectSpace(at):Abs()
	local half = zone.Size / 2
	return p.X <= half.X and p.Y <= half.Y and p.Z <= half.Z
end

-- The HumanoidRootPart of the player closest to (x, z) inside the zone, or nil. The copy is not a player, so it never counts.
local function watchedRoot(zone: BasePart?, x: number, z: number): BasePart?
	local best, bestDistance = nil, math.huge
	for _, other in Players:GetPlayers() do
		local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if zone and root and inside(zone, root.Position) then
			local distance = Vector2.new(root.Position.X - x, root.Position.Z - z).Magnitude
			if distance < bestDistance then
				best, bestDistance = root, distance
			end
		end
	end
	return best
end

local function headOf(root: BasePart): Vector3
	local head = root.Parent and root.Parent:FindFirstChild("Head")
	return (head or root).Position
end

-- One Standby frame: toward the spot `distance` from the watched player on Bob's side (or home with nobody), the carriage at most
-- FOLLOW_SPEED, the yaw at most TURN_SPEED. velocity is the carriage's (x, z) velocity, carried from frame to frame.
local function follow(rig, pose: Pose, velocity: Vector2, root: BasePart?, distance: number, dt: number): (Pose, Vector2)
	local home, travel = rig.home, rig.travel
	local spot, yaw, extension = Vector2.new(home.x, home.z), home.yaw, home.extension
	if root then
		local at = root.Position
		local away = Vector2.new(pose.x - at.X, pose.z - at.Z) -- from the player to Bob
		away = if away.Magnitude > 1e-3 then away.Unit else Vector2.xAxis -- right overhead: back off along +X
		spot = Vector2.new(at.X, at.Z) + away * distance
		spot = Vector2.new(math.clamp(spot.X, travel.minX, travel.maxX), math.clamp(spot.Y, travel.minZ, travel.maxZ))
		yaw = math.atan2(away.X, away.Y) -- the needle pointing along -away, at the player
		extension = math.clamp(rig.homePivot.Y + rig.tipLocal.Y - headOf(root).Y, 0, MAX_EXTENSION)
	end
	local gap = spot - Vector2.new(pose.x, pose.z)
	local want = if gap.Magnitude > 1e-4 then gap.Unit * math.min(FOLLOW_SPEED, gap.Magnitude * ARRIVE) else Vector2.zero
	velocity += (want - velocity) * math.min(1, dt * GET_GOING)
	local turn = turnBetween(pose.yaw, yaw, home.yaw) * math.min(1, dt * ARRIVE)
	return {
		x = pose.x + velocity.X * dt,
		z = pose.z + velocity.Y * dt,
		extension = pose.extension + (extension - pose.extension) * math.min(1, dt * ARRIVE),
		yaw = pose.yaw + math.clamp(turn, -TURN_SPEED * dt, TURN_SPEED * dt),
	}, velocity
end

-- Follows a point from frame to frame. Its velocity is smoothed, so one uneven frame cannot spike the acceleration (that velocity's
-- change per second); a frame with dt near 0 only moves the point.
local function newTracker()
	return { at = nil :: Vector3?, velocity = Vector3.zero, accel = Vector3.zero }
end

local function track(tracker, at: Vector3, dt: number)
	if tracker.at and dt > 1e-3 then
		local change = ((at - tracker.at) / dt - tracker.velocity) * math.min(1, dt * SMOOTH)
		tracker.velocity += change
		tracker.accel = change / dt
	end
	tracker.at = at
end

local function finite(v: Vector2): boolean
	return v.Magnitude < math.huge -- false for NaN as well as infinity
end

-- A world vector in an eye white's plane (x along its LookVector, y along its UpVector).
local function flat(v: Vector3, white: CFrame): Vector2
	return Vector2.new(v:Dot(white.LookVector), v:Dot(white.UpVector))
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
	-- Required here, not at the top: the tests require a parentless clone of this module for readRig and injectionPose.
	local GooglyEyes = require(script.Parent:WaitForChild("GooglyEyes", 30))
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

	-- The eyes: the pupil as built, in its white's frame, gives its depth along the normal and its turn.
	local eyes = {}
	for _, side in { "L", "R" } do
		local white, pupil = bob.Body["EyeWhite" .. side], bob.Pupils["Pupil" .. side]
		local built = rig.offsets[white]:Inverse() * rig.offsets[pupil]
		local radius = math.max(0, math.min(white.Size.Y, white.Size.Z) - math.min(pupil.Size.Y, pupil.Size.Z)) / 2
		table.insert(eyes, { white = white, pupil = pupil, depth = built.X, turn = built.Rotation, sim = GooglyEyes.new(radius), motion = newTracker() })
	end
	local blasts = workspace.DescendantAdded:Connect(function(thing)
		local zone = room:FindFirstChild("Zone")
		if thing:IsA("Explosion") and zone and inside(zone, thing.Position) then
			for _, eye in eyes do
				GooglyEyes.spin(eye.sim, SPIN * eye.sim.radius)
			end
		end
	end)

	-- The copy's joints as the server built them (this client is the only one that changes them, and only locally). A new copy
	-- starts a new list. Not a weak table: one keyed by Instances can drop a joint that still exists, and then a turned C0 would
	-- be saved as the built one.
	local savedCopy, builtC0 = nil, {}
	local function c0Of(joint): CFrame
		builtC0[joint] = builtC0[joint] or joint.C0
		return builtC0[joint]
	end
	local random = Random.new()

	local pose: Pose, needle = rig.home, 0
	local phaseState, phaseStart, from, fromNeedle, hissed = nil, nil, pose, 0, false
	local goal: Pose?, turn: number? = nil, nil -- chosen once per phase
	local velocity = Vector2.zero -- the carriage's, on Standby
	local carriage = newTracker()
	local swing, swingVelocity, swingFrom = Vector2.zero, Vector2.zero, Vector2.zero
	local look, lookFrom = Vector2.zero, Vector2.zero -- the copy's head: yaw, pitch
	local twitched = nil -- the joint that twitched last frame
	local function frame(dt: number)
		local state = bob:GetAttribute("State")
		local start = bob:GetAttribute("PhaseStart") or 0
		local target = bob:GetAttribute("Target") or ""
		if state ~= phaseState or start ~= phaseStart then
			phaseState, phaseStart, from, fromNeedle, hissed = state, start, pose, needle, false
			goal, turn, velocity, swingFrom, lookFrom = nil, nil, Vector2.zero, swing, look
		end
		local t = workspace:GetServerTimeNow() - start
		local step = math.min(dt, MAX_STEP)
		local copy = room:FindFirstChild("Subject")
		if copy ~= savedCopy then
			savedCopy, builtC0, twitched = copy, {}, nil
		end

		local watched = nil
		if state == "Moving" or state == "Injecting" then
			-- Moving aims at the live limb (nil once it is lost: Bob stays where he is); Injecting keeps the aim it began with.
			if state == "Moving" or not goal then
				goal = BobAnimator.injectionPose(rig, copy, target)
			end
			if goal then
				turn = turn or turnBetween(from.yaw, goal.yaw, rig.home.yaw)
				pose = blend(from, goal, smooth(t / (if state == "Moving" then Timings.Move else Timings.NeedleOut)), turn)
			end
		elseif state == "Returning" then
			turn = turn or turnBetween(from.yaw, rig.home.yaw, rig.home.yaw)
			pose = blend(from, rig.home, smooth(t / Timings.Return), turn)
		else
			watched = watchedRoot(room:FindFirstChild("Zone"), pose.x, pose.z)
			pose, velocity = follow(rig, pose, velocity, watched, config.FOLLOW_DISTANCE, step)
		end

		local out, hold = Timings.NeedleOut, Timings.Hold
		if state == "Injecting" then
			needle = NEEDLE_OUT * (if t < out then smooth(t / out) elseif t < out + hold then 1 else 1 - smooth((t - out - hold) / Timings.NeedleIn))
		else
			needle = fromNeedle * (1 - smooth(t / Timings.NeedleIn))
		end
		local holding = state == "Injecting" and t >= out and t < out + hold
		if holding and not hissed then
			hissed = true
			hiss:Play()
		elseif not holding and hiss.IsPlaying then
			hiss:Stop()
		end

		if state == "Injecting" then
			-- Bob steadies himself: the swing dies away while the needle goes in, so it lands where it aims.
			swing, swingVelocity = swingFrom * (1 - smooth(t / out)), Vector2.zero
		else
			-- Hanging from the pivot, the body leans away from the carriage's acceleration (pitch from Bob's forward, roll from his
			-- right) and springs about that lean.
			local a = CFrame.Angles(0, pose.yaw, 0):VectorToObjectSpace(carriage.accel)
			local g = workspace.Gravity
			local lean = Vector2.new(math.atan2(a.Z, g), -math.atan2(a.X, g))
			swingVelocity += ((lean - swing) * SWING_STIFFNESS - swingVelocity * SWING_DAMPING) * step
			local swung = swing + swingVelocity * step
			swing = Vector2.new(math.clamp(swung.X, -SWING_MAX, SWING_MAX), math.clamp(swung.Y, -SWING_MAX, SWING_MAX))
			if swing ~= swung then
				swingVelocity = Vector2.zero -- at the stop
			end
		end

		BobAnimator.applyPose(rig, pose, needle, swing)
		track(carriage, rig.carriage.Position, dt)
		motor.Volume = math.clamp(carriage.velocity.Magnitude / MOTOR_FULL_SPEED, 0, 1) * MOTOR_VOLUME

		-- The pupils, in their whites' planes as placed this frame. Bad numbers skip the step, and a broken pupil drops to the bottom.
		local gravity = Vector3.new(0, -workspace.Gravity, 0)
		local head = watched and headOf(watched)
		for _, eye in eyes do
			local white = eye.white.CFrame
			track(eye.motion, white.Position, dt)
			local sim = eye.sim
			local fall, jolt = flat(gravity, white), flat(eye.motion.accel, white)
			local pull = if head then flat((head - white.Position).Unit, white) else Vector2.zero
			if finite(fall) and finite(pull) and finite(jolt) then
				GooglyEyes.step(sim, fall, pull, jolt, dt)
			end
			if not (finite(sim.offset) and finite(sim.velocity)) then
				sim.offset, sim.velocity = Vector2.new(0, -sim.radius), Vector2.zero
			end
			eye.pupil.CFrame = white * CFrame.new(eye.depth, sim.offset.Y, -sim.offset.X) * eye.turn
		end

		-- The copy's flinch: the head toward the needle tip, from the neck, in the torso's frame (-Z ahead, +Y up).
		local neck = copy and LabConfig.limbJoint(copy, "Head")
		if neck and neck.Part0 then
			local c0 = c0Of(neck)
			if state == "Moving" or state == "Injecting" then
				local torso = neck.Part0.CFrame
				local to = torso:VectorToObjectSpace(rig.needle.NeedleTip.WorldPosition - torso:PointToWorldSpace(c0.Position))
				local want = Vector2.new(
					math.clamp(math.atan2(-to.X, -to.Z), -FLINCH_YAW, FLINCH_YAW),
					math.clamp(math.atan2(to.Y, Vector2.new(to.X, to.Z).Magnitude), -FLINCH_PITCH, FLINCH_PITCH)
				)
				look += (want - look) * math.min(1, step * FLINCH_RATE)
			elseif state ~= "Returning" then
				look = lookFrom * (1 - smooth(t / RELAX))
			end
			neck.C0 = CFrame.new(c0.Position) * CFrame.Angles(0, look.X, 0) * CFrame.Angles(look.Y, 0, 0) * c0.Rotation
		end
		-- The twitch: the target limb's joint jitters during Hold, then goes back as built (the neck is set above every frame).
		local twitching = if holding and copy then LabConfig.limbJoint(copy, target) else nil
		if twitched and twitched ~= twitching and twitched ~= neck then
			twitched.C0 = builtC0[twitched]
		end
		if twitching then
			local jitter = CFrame.Angles(random:NextNumber(-TWITCH, TWITCH), random:NextNumber(-TWITCH, TWITCH), random:NextNumber(-TWITCH, TWITCH))
			twitching.C0 = (if twitching == neck then twitching.C0 else c0Of(twitching)) * jitter
		end
		twitched = twitching

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
		blasts:Disconnect()
		motor:Stop()
		hiss:Stop()
		BobAnimator.applyPose(rig, rig.home, 0, Vector2.zero)
		for joint, c0 in builtC0 do
			joint.C0 = c0
		end
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
