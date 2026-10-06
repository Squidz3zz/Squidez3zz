-- One-shot build script: run in the Edit datamodel via execute_luau.
-- Builds the two heavy-factory menu rooms under the map as Persistent Models: Workspace.SettingsRoom and
-- Workspace.CreditsRoom. It adopts the user's four parts (BackgroundForSettings, Settingsboard, BackgroundForCredits,
-- PlayerCreditStand) from Workspace, moving each by (0, -200, 0) into its room, or creates stand-ins with the same
-- names, sizes and layout when they are missing. It adds ViewerCreditStand (an empty second podium), the camera markers
-- SettingsCameraShot and CreditsCameraShot, ViewerSpot (the invisible marker the viewer's avatar stands on in the Credits
-- foreground, back to the camera, looking at PlayerCreditStand), the Settingsboard BoardFace attribute, and the dressing
-- (shell, grate trench, girders, pipes, caged amber lamps, haze and steam).
-- The rooms assume the user's parts are axis-aligned with their front faces toward -Z (the cameras look along +Z).
-- After it runs, Studio is the source of truth for the rooms. The script refuses to run while either room exists.
-- To rebuild: delete workspace.SettingsRoom and workspace.CreditsRoom, then run this script. With no user parts present
-- it recreates them (stand-in path).
if workspace:FindFirstChild("SettingsRoom") or workspace:FindFirstChild("CreditsRoom") then
	error("rooms already exist")
end

local DROP = Vector3.new(0, -200, 0)
local VIEWER_OFFSET = -4.5 -- ViewerCreditStand sits this far along BackgroundForCredits' RightVector (camera's right)
local TAN_HALF_FOV = math.tan(math.rad(70 / 2)) -- default Camera.FieldOfView (vertical)
local NARROW = 4 / 3 -- narrowest landscape aspect the shots must fit horizontally
-- ViewerSpot, on the floor plan: SPOT_ALONG of the way from CreditsCameraShot to PlayerCreditStand, then SPOT_SIDE studs to
-- the side away from the developer (toward ViewerCreditStand). The side step is not square to the camera-to-stand line, so
-- it pulls the spot back along that line a little: 0.4 along plus the side step lands about 0.31 of the way (about a
-- third), 2.9 studs off the line. It faces the developer's stand turned
-- SPOT_TURN of the way toward the way the camera looks (0 = straight at the stand, 1 = the camera's own direction), so the
-- camera sees the viewer's back and not its side. Tuned with screenshots, at 16:9 down to a phone in landscape (844x390):
-- the viewer's head and shoulders fill the lower right of the Credits shot, seen from behind, without covering the
-- developer, the developer's name label or BACK. (The camera is about as high as an avatar's head, so the head sits about
-- 40% down the frame, and the body runs off the bottom edge.)
local SPOT_ALONG = 0.4
local SPOT_SIDE = 3.0
local SPOT_TURN = 0.5

-- Room shell, in studs.
local HALF_WIDTH = 11.4 -- inner half-width either side of the camera's centre line
local HEIGHT = 17 -- floor to ceiling
local WALL = 1
local TRENCH_DEPTH = 3
local BACK_GAP = 1.3 -- backdrop back face to back wall
local FRONT_DEPTH = 17 -- backdrop front face to front wall

-- Factory palette: rust and steel, amber accents.
local AMBER = Color3.fromRGB(255, 150, 30)
local LAMP_LIGHT = Color3.fromRGB(255, 160, 60)
local GLOW_LIGHT = Color3.fromRGB(255, 110, 30)
local BULB = Color3.fromRGB(255, 140, 40)
local HOT = Color3.fromRGB(255, 90, 15) -- glowing element in the trench
local RING = Color3.fromRGB(210, 100, 20)
local RUST = Color3.fromRGB(110, 62, 36)
local RUST_DARK = Color3.fromRGB(72, 46, 32)
local STEEL = Color3.fromRGB(88, 87, 84)
local STEEL_DARK = Color3.fromRGB(46, 45, 44)
local IRON = Color3.fromRGB(40, 39, 38)
local GRIME = Color3.fromRGB(26, 25, 24)
local GAUGE_FACE = Color3.fromRGB(225, 215, 195)
local HAZE = Color3.fromRGB(160, 145, 128)
local STEAM = Color3.fromRGB(190, 175, 160)
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local M = Enum.Material

-- The user's parts, with their original (pre-drop) layout for stand-ins.
local USER_PARTS = {
	{
		name = "BackgroundForSettings",
		room = "SettingsRoom",
		size = Vector3.new(14.901, 16.256, 0.83),
		cframe = CFrame.new(-144.3835, 8.128, 70.809),
		material = M.CorrodedMetal,
		color = RUST,
	},
	{
		name = "Settingsboard",
		room = "SettingsRoom",
		size = Vector3.new(9.239, 10.271, 1.352),
		cframe = CFrame.new(-144.4064, 5.1355, 70.548),
		material = M.Metal,
		color = Color3.fromRGB(58, 56, 54),
	},
	{
		name = "BackgroundForCredits",
		room = "CreditsRoom",
		size = Vector3.new(14.901, 16.256, 0.83),
		cframe = CFrame.new(-168.1605, 8.128, 70.866),
		material = M.CorrodedMetal,
		color = RUST,
	},
	{
		name = "PlayerCreditStand",
		room = "CreditsRoom",
		size = Vector3.new(1.872, 3.375, 3.611),
		cframe = CFrame.new(-168.0777, 0.936, 66.9222) * CFrame.fromOrientation(0, math.rad(90), math.rad(90)),
		shape = Enum.PartType.Cylinder,
		material = M.DiamondPlate,
		color = STEEL,
	},
}

-- Resolve the user's parts and where they will sit, without touching anything yet.
local user = {}
for _, def in USER_PARTS do
	local existing = workspace:FindFirstChild(def.name)
	if existing and existing:IsA("BasePart") then
		user[def.name] = { def = def, part = existing, cframe = existing.CFrame + DROP, size = existing.Size }
	else
		user[def.name] = { def = def, cframe = def.cframe + DROP, size = def.size }
	end
end

local function bounds(cframe, size)
	local half = size / 2
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local corner = cframe:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
				lo, hi = lo:Min(corner), hi:Max(corner)
			end
		end
	end
	return lo, hi
end

local function corners(lo, hi)
	local list = {}
	for _, x in { lo.X, hi.X } do
		for _, y in { lo.Y, hi.Y } do
			for _, z in { lo.Z, hi.Z } do
				table.insert(list, Vector3.new(x, y, z))
			end
		end
	end
	return list
end

-- Camera CFrame looking along +Z, pitched by pitchDeg, that fits every point inside `fit` of the screen
-- (vertically at FOV 70, and horizontally at a 4:3 screen, the narrowest landscape case).
local function frameShot(points, pitchDeg, fit)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in points do
		lo, hi = lo:Min(p), hi:Max(p)
	end
	local centre = (lo + hi) / 2
	local pitch = math.rad(pitchDeg)
	local look = Vector3.new(0, math.sin(pitch), math.cos(pitch))
	local up = Vector3.new(0, math.cos(pitch), -math.sin(pitch))
	local right = look:Cross(up)
	local distance = 0
	for _, p in points do
		local v = p - centre
		local depthOffset = v:Dot(look)
		distance = math.max(
			distance,
			math.abs(v:Dot(up)) / (TAN_HALF_FOV * fit) - depthOffset,
			math.abs(v:Dot(right)) / (TAN_HALF_FOV * NARROW * fit) - depthOffset
		)
	end
	return CFrame.lookAt(centre - look * distance, centre)
end

-- Part builders. Every built part is anchored, non-colliding and non-queryable unless `extra` says otherwise.
local function newPart(parent, name, size, cframe, color, material, extra)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = material
	part.Color = color
	if extra then
		if extra.Shape then
			part.Shape = extra.Shape
		end
		for key, value in extra do
			part[key] = value
		end
	end
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

-- Axis-aligned box between two corners. Solid shell pieces collide (so they also stop rays) but stay CanQuery false.
local function box(parent, name, lo, hi, color, material, extra)
	return newPart(parent, name, hi - lo, CFrame.new((lo + hi) / 2), color, material, extra)
end

-- Cylinder from point a to point b.
local function rod(parent, name, a, b, diameter, color, material, extra)
	local axis = b - a
	local upHint = math.abs(axis.Unit.Y) > 0.99 and Vector3.zAxis or Vector3.yAxis
	local cframe = CFrame.lookAt((a + b) / 2, b, upHint) * CFrame.Angles(0, math.pi / 2, 0)
	local options = { Shape = Enum.PartType.Cylinder }
	for key, value in extra or {} do
		options[key] = value
	end
	return newPart(parent, name, Vector3.new(axis.Magnitude, diameter, diameter), cframe, color, material, options)
end

local function disc(parent, name, centre, normal, diameter, thickness, color, material)
	return rod(parent, name, centre - normal * thickness / 2, centre + normal * thickness / 2, diameter, color, material)
end

local function light(className, parent, props)
	local inst = Instance.new(className)
	inst.Color = LAMP_LIGHT
	inst.Shadows = true
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function attachment(part, name, worldPosition)
	local inst = Instance.new("Attachment")
	inst.Name = name
	inst.Parent = part
	inst.WorldPosition = worldPosition
	return inst
end

local function emitter(parent, name, props)
	local inst = Instance.new("ParticleEmitter")
	inst.Name = name
	inst.Texture = SMOKE_TEXTURE
	inst.LightInfluence = 1
	inst.LightEmission = 0
	inst.Rotation = NumberRange.new(0, 360)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function curve(points)
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

-- Caged bulkhead lamp on a wall: base plate, Neon bulb, a cross of cage bars. Shines along `facing`.
local function cagedLamp(parent, name, pos, facing, lightClass, lightProps)
	local frame = CFrame.lookAt(pos, pos + facing)
	disc(parent, name .. "Base", pos + facing * 0.15, facing, 1.5, 0.3, GRIME, M.Metal)
	disc(parent, name .. "Rim", pos + facing * 0.45, facing, 1.25, 0.3, STEEL_DARK, M.Metal)
	local bulb = newPart(parent, name .. "Bulb", Vector3.one * 0.9, CFrame.new(pos + facing * 0.65) * frame.Rotation, BULB, M.Neon, {
		Shape = Enum.PartType.Ball,
		CastShadow = false,
	})
	local front = pos + facing * 1.15
	rod(parent, name .. "CageH", front - frame.RightVector * 0.62, front + frame.RightVector * 0.62, 0.1, GRIME, M.Metal)
	rod(parent, name .. "CageV", front - frame.UpVector * 0.62, front + frame.UpVector * 0.62, 0.1, GRIME, M.Metal)
	light(lightClass, bulb, lightProps)
	return bulb
end

-- Caged lamp hanging from the ceiling on a cable, aimed at `target` with a SpotLight.
local function hangingLamp(parent, name, pos, target, ceilingY, lightProps)
	local dir = (target - pos).Unit
	rod(parent, name .. "Cable", Vector3.new(pos.X, ceilingY, pos.Z), pos, 0.12, GRIME, M.Metal)
	disc(parent, name .. "Shade", pos + dir * 0.1, dir, 1.9, 0.7, RUST_DARK, M.CorrodedMetal)
	local bulb = newPart(parent, name .. "Bulb", Vector3.one * 0.8, CFrame.lookAt(pos + dir * 0.55, target), BULB, M.Neon, {
		Shape = Enum.PartType.Ball,
		CastShadow = false,
	})
	local frame = CFrame.lookAt(pos, target)
	local front = pos + dir * 1.0
	rod(parent, name .. "CageH", front - frame.RightVector * 0.7, front + frame.RightVector * 0.7, 0.1, GRIME, M.Metal)
	rod(parent, name .. "CageV", front - frame.UpVector * 0.7, front + frame.UpVector * 0.7, 0.1, GRIME, M.Metal)
	local props = { Face = Enum.NormalId.Front }
	for key, value in lightProps do
		props[key] = value
	end
	light("SpotLight", bulb, props)
	return bulb
end

-- I-beam column against the back wall, flanges toward the camera so the H profile reads from the front.
local function column(parent, name, x, r)
	local zMid = r.z2 - 0.6
	local yLo, yHi = r.floorY, r.floorY + HEIGHT
	for i, side in { -1, 1 } do
		box(parent, name .. "Flange" .. i, Vector3.new(x + side * 0.83 - 0.08, yLo, zMid - 0.6), Vector3.new(x + side * 0.83 + 0.08, yHi, zMid + 0.6), RUST, M.CorrodedMetal)
	end
	box(parent, name .. "Web", Vector3.new(x - 0.75, yLo, zMid - 0.07), Vector3.new(x + 0.75, yHi, zMid + 0.07), RUST_DARK, M.CorrodedMetal)
	return zMid - 0.07 -- web front face, for mounting lamps
end

-- Vertical pipe from floor to ceiling, with a flange collar.
local function riser(parent, name, x, z, diameter, r, color, material)
	rod(parent, name, Vector3.new(x, r.floorY - 0.1, z), Vector3.new(x, r.floorY + HEIGHT + 0.1, z), diameter, color, material)
	rod(parent, name .. "Collar", Vector3.new(x, r.floorY + 5.8, z), Vector3.new(x, r.floorY + 6.2, z), diameter + 0.25, STEEL_DARK, M.Metal)
end

local function barrel(parent, name, x, z, r)
	local base = Vector3.new(x, r.floorY, z)
	rod(parent, name, base, base + Vector3.new(0, 2.8, 0), 2, RUST, M.CorrodedMetal)
	rod(parent, name .. "BandLow", base + Vector3.new(0, 0.7, 0), base + Vector3.new(0, 0.85, 0), 2.08, RUST_DARK, M.Metal)
	rod(parent, name .. "BandHigh", base + Vector3.new(0, 1.95, 0), base + Vector3.new(0, 2.1, 0), 2.08, RUST_DARK, M.Metal)
end

-- Builds a room's shell and dressing. `r` holds the room's layout (absolute coordinates).
local function dress(model, r)
	local cx, x1, x2, z1, z2, floorY = r.cx, r.x1, r.x2, r.z1, r.z2, r.floorY
	local ceilingY = floorY + HEIGHT
	local bottomY = floorY - TRENCH_DEPTH - WALL
	local solid = { CanCollide = true }

	-- Shell: no gaps, so neither sun nor sky can leak in. The floor is split by the grate trench.
	local subFloor = box(model, "SubFloor", Vector3.new(x1 - WALL, bottomY, z1 - WALL), Vector3.new(x2 + WALL, floorY - TRENCH_DEPTH, z2 + WALL), GRIME, M.Metal, solid)
	box(model, "FloorFront", Vector3.new(x1, floorY - TRENCH_DEPTH, z1), Vector3.new(x2, floorY, r.trench1), STEEL_DARK, M.DiamondPlate, solid)
	box(model, "FloorBack", Vector3.new(x1, floorY - TRENCH_DEPTH, r.trench2), Vector3.new(x2, floorY, z2), STEEL_DARK, M.DiamondPlate, solid)
	box(model, "WallBack", Vector3.new(x1 - WALL, bottomY, z2), Vector3.new(x2 + WALL, ceilingY + WALL, z2 + WALL), IRON, M.Metal, solid)
	box(model, "WallFront", Vector3.new(x1 - WALL, bottomY, z1 - WALL), Vector3.new(x2 + WALL, ceilingY + WALL, z1), GRIME, M.CorrodedMetal, solid)
	box(model, "WallLeft", Vector3.new(x2, bottomY, z1 - WALL), Vector3.new(x2 + WALL, ceilingY + WALL, z2 + WALL), IRON, M.Metal, solid) -- camera's left (+X)
	box(model, "WallRight", Vector3.new(x1 - WALL, bottomY, z1 - WALL), Vector3.new(x1, ceilingY + WALL, z2 + WALL), IRON, M.Metal, solid) -- camera's right (-X)
	box(model, "Ceiling", Vector3.new(x1 - WALL, ceilingY, z1 - WALL), Vector3.new(x2 + WALL, ceilingY + WALL, z2 + WALL), GRIME, M.CorrodedMetal, solid)

	-- Grate trench: bars and cross members over a glowing pit, an amber safety edge in front, steam rising through.
	local bars = r.trenchBars
	local pitch = (r.trench2 - r.trench1) / bars
	for i = 1, bars do
		local zc = r.trench1 + pitch * (i - 0.5)
		box(model, "GrateBar" .. i, Vector3.new(x1, floorY - 0.3, zc - 0.09), Vector3.new(x2, floorY - 0.02, zc + 0.09), STEEL, M.Metal)
	end
	for i = 1, r.crossBars do
		local xc = x1 + (x2 - x1) * i / (r.crossBars + 1)
		box(model, "GrateCross" .. i, Vector3.new(xc - 0.09, floorY - 0.32, r.trench1), Vector3.new(xc + 0.09, floorY - 0.04, r.trench2), STEEL_DARK, M.Metal)
	end
	local trenchMid = (r.trench1 + r.trench2) / 2
	-- A glowing strip on the trench's far wall, where the camera sees it through the bars.
	box(model, "HotElement", Vector3.new(x1, floorY - 1.3, r.trench2 - 0.08), Vector3.new(x2, floorY - 0.9, r.trench2), HOT, M.Neon, { CastShadow = false })
	box(model, "SafetyEdge", Vector3.new(x1, floorY, r.trench1 - 0.4), Vector3.new(x2, floorY + 0.04, r.trench1 - 0.12), AMBER, M.SmoothPlastic)
	local glow = attachment(subFloor, "TrenchGlow", Vector3.new(cx, floorY - 1.0, trenchMid))
	light("PointLight", glow, { Color = GLOW_LIGHT, Brightness = 3, Range = 8 })
	for i, x in r.steamX do
		emitter(attachment(subFloor, "SteamVent" .. i, Vector3.new(x, floorY - 2.4, trenchMid)), "Steam", {
			Color = ColorSequence.new(STEAM),
			Size = curve({ { 0, 0.8 }, { 1, 4.5 } }),
			Transparency = curve({ { 0, 1 }, { 0.15, 0.78 }, { 0.6, 0.88 }, { 1, 1 } }),
			Lifetime = NumberRange.new(2.5, 4),
			Rate = 4,
			Speed = NumberRange.new(1.5, 2.5),
			SpreadAngle = Vector2.new(12, 12),
			Acceleration = Vector3.new(0, 0.4, 0),
			Drag = 0.6,
			RotSpeed = NumberRange.new(-20, 20),
		})
	end

	-- Kick plates along the back and side walls.
	box(model, "KickPlateBack", Vector3.new(x1, floorY, z2 - 0.15), Vector3.new(x2, floorY + 1.6, z2), STEEL, M.DiamondPlate)
	box(model, "KickPlateLeft", Vector3.new(x2 - 0.15, floorY, z1), Vector3.new(x2, floorY + 1.6, z2 - 0.15), STEEL, M.DiamondPlate)
	box(model, "KickPlateRight", Vector3.new(x1, floorY, z1), Vector3.new(x1 + 0.15, floorY + 1.6, z2 - 0.15), STEEL, M.DiamondPlate)

	-- Side wall ribs.
	for i, dz in { 4, 9 } do
		box(model, "RibLeft" .. i, Vector3.new(x2 - 0.5, floorY, z2 - dz - 0.25), Vector3.new(x2, ceilingY, z2 - dz + 0.25), RUST, M.CorrodedMetal)
		box(model, "RibRight" .. i, Vector3.new(x1, floorY, z2 - dz - 0.25), Vector3.new(x1 + 0.5, ceilingY, z2 - dz + 0.25), RUST, M.CorrodedMetal)
	end

	-- Girder columns flanking the backdrop, and an I-beam gantry spanning between them in front of it.
	local webFront = {}
	for i, x in r.columnX do
		webFront[i] = column(model, "Column" .. i, x, r)
	end
	local beamX1, beamX2 = math.min(r.columnX[1], r.columnX[2]) + 0.83, math.max(r.columnX[1], r.columnX[2]) - 0.83
	local by, bz = r.beamY, r.backdropFront - 0.75
	box(model, "GantryWeb", Vector3.new(beamX1, by, bz + 0.28), Vector3.new(beamX2, by + 0.9, bz + 0.42), RUST_DARK, M.CorrodedMetal)
	box(model, "GantryFlangeLow", Vector3.new(beamX1, by, bz), Vector3.new(beamX2, by + 0.12, bz + 0.7), RUST, M.CorrodedMetal)
	box(model, "GantryFlangeHigh", Vector3.new(beamX1, by + 0.78, bz), Vector3.new(beamX2, by + 0.9, bz + 0.7), RUST, M.CorrodedMetal)

	-- Pipework: risers, branches along both side walls, a valve wheel and a pressure gauge.
	for i, p in r.risers do
		riser(model, "Riser" .. i, p.x, p.z, p.d, r, p.rusty and RUST_DARK or STEEL, p.rusty and M.CorrodedMetal or M.Metal)
	end
	for i, height in { 8.5, 7.5 } do
		local p = r.risers[i]
		rod(model, "BranchPipe" .. i, Vector3.new(p.x, floorY + height, p.z), Vector3.new(p.x, floorY + height, z1), p.d * 0.8, STEEL, M.Metal)
	end
	local valveAt = Vector3.new(r.valve.x, floorY + 4, r.valve.z - r.valve.d / 2)
	local wheelAt = valveAt - Vector3.zAxis * 0.45
	rod(model, "ValveStem", valveAt, wheelAt, 0.2, STEEL_DARK, M.Metal)
	disc(model, "ValveWheel", wheelAt, -Vector3.zAxis, 1.3, 0.14, AMBER, M.SmoothPlastic)
	local spokesAt = wheelAt - Vector3.zAxis * 0.1
	rod(model, "ValveSpokeH", spokesAt - Vector3.xAxis * 0.6, spokesAt + Vector3.xAxis * 0.6, 0.12, GRIME, M.Metal)
	rod(model, "ValveSpokeV", spokesAt - Vector3.yAxis * 0.6, spokesAt + Vector3.yAxis * 0.6, 0.12, GRIME, M.Metal)
	local gaugeAt = Vector3.new(r.gauge.x, floorY + 6.8, r.gauge.z - r.gauge.d / 2 - 0.2)
	disc(model, "GaugeRim", gaugeAt, -Vector3.zAxis, 0.95, 0.3, STEEL_DARK, M.Metal)
	disc(model, "GaugeFace", gaugeAt - Vector3.zAxis * 0.16, -Vector3.zAxis, 0.75, 0.04, GAUGE_FACE, M.SmoothPlastic)

	-- Caged amber lamps.
	for i, lamp in r.wallLamps do
		local pos = lamp.onColumn and Vector3.new(r.columnX[lamp.onColumn], floorY + lamp.y, webFront[lamp.onColumn]) or lamp.pos
		cagedLamp(model, "Lamp" .. i, pos, -Vector3.zAxis, "PointLight", { Brightness = 0.8, Range = 10 })
	end
	hangingLamp(model, "HangingLamp", r.hanging.pos, r.hanging.target, ceilingY, { Brightness = r.hanging.brightness, Range = 18, Angle = 50 })

	for i, b in r.barrels or {} do
		barrel(model, "Barrel" .. i, b.x, b.z, r)
	end

	-- Haze: a few large, faint smoke puffs drifting through the lower room.
	local hazeVolume = box(model, "Haze", Vector3.new(x1, floorY, z1 + 2), Vector3.new(x2, floorY + 8, z2), HAZE, M.SmoothPlastic, {
		Transparency = 1,
		CastShadow = false,
	})
	emitter(hazeVolume, "HazeEmitter", {
		Color = ColorSequence.new(HAZE),
		Size = curve({ { 0, 7 }, { 1, 13 } }),
		Transparency = curve({ { 0, 1 }, { 0.3, 0.84 }, { 0.7, 0.86 }, { 1, 1 } }),
		Lifetime = NumberRange.new(12, 18),
		Rate = 2,
		Speed = NumberRange.new(0.2, 0.5),
		SpreadAngle = Vector2.new(180, 180),
		RotSpeed = NumberRange.new(-6, 6),
	})

	model.WorldPivot = CFrame.new(cx, floorY, (z1 + z2) / 2)
end

local function marker(parent, name, cframe)
	return newPart(parent, name, Vector3.one, cframe, GRIME, M.SmoothPlastic, { Transparency = 1, CastShadow = false })
end

-- Layout, from where the user's parts will sit.
local sBackLo, sBackHi = bounds(user.BackgroundForSettings.cframe, user.BackgroundForSettings.size)
local boardLo, boardHi = bounds(user.Settingsboard.cframe, user.Settingsboard.size)
local cBackLo, cBackHi = bounds(user.BackgroundForCredits.cframe, user.BackgroundForCredits.size)
local devCFrame = user.PlayerCreditStand.cframe
local standSize = user.PlayerCreditStand.size
local viewerCFrame = devCFrame + user.BackgroundForCredits.cframe.RightVector * VIEWER_OFFSET
local _, devHi = bounds(devCFrame, standSize)
local _, viewerHi = bounds(viewerCFrame, standSize)

local settingsLayout = {}
do
	local r = settingsLayout
	r.cx = (sBackLo.X + sBackHi.X) / 2
	r.floorY = sBackLo.Y
	r.x1, r.x2 = r.cx - HALF_WIDTH, r.cx + HALF_WIDTH
	r.z1, r.z2 = sBackLo.Z - FRONT_DEPTH, sBackHi.Z + BACK_GAP
	r.trench1, r.trench2, r.trenchBars, r.crossBars = boardLo.Z - 3.45, boardLo.Z - 0.25, 5, 5
	r.steamX = { r.cx - 9.4, r.cx + 9.4 }
	local edge = (sBackHi.X - sBackLo.X) / 2 + 0.95
	r.columnX = { r.cx + edge, r.cx - edge }
	r.risers = {
		{ x = r.x2 - 0.85, z = r.z2 - 0.85, d = 1.0, rusty = true },
		{ x = r.x1 + 0.85, z = r.z2 - 0.85, d = 1.0, rusty = true },
		{ x = r.x2 - 1.9, z = r.z2 - 2.1, d = 0.5 },
		{ x = r.x1 + 1.9, z = r.z2 - 2.1, d = 0.5 },
	}
	r.valve = r.risers[1]
	r.gauge = r.risers[2]
	local boardTopY = boardHi.Y
	r.wallLamps = {
		{ pos = Vector3.new(r.cx + 6, boardTopY - 0.7, sBackLo.Z) },
		{ pos = Vector3.new(r.cx - 6, boardTopY - 0.7, sBackLo.Z) },
	}
	local boardCentre = (boardLo + boardHi) / 2
	r.hanging = { pos = Vector3.new(r.cx, r.floorY + 13.5, boardLo.Z - 5), target = boardCentre, brightness = 1.5 }
	r.backdropFront, r.beamY = sBackLo.Z, boardTopY + 1.2
end

local creditsLayout = {}
do
	local r = creditsLayout
	r.cx = (devCFrame.Position.X + viewerCFrame.Position.X) / 2
	r.floorY = cBackLo.Y
	r.x1, r.x2 = r.cx - HALF_WIDTH, r.cx + HALF_WIDTH
	r.z1, r.z2 = cBackLo.Z - FRONT_DEPTH, cBackHi.Z + BACK_GAP
	r.trench1, r.trench2, r.trenchBars, r.crossBars = math.max(devHi.Z, viewerHi.Z) + 0.2, cBackLo.Z - 0.15, 3, 0
	r.steamX = { r.cx, r.cx - 7.5 }
	r.columnX = { cBackHi.X + 0.9, cBackLo.X - 0.9 }
	r.risers = {
		{ x = r.x1 + 0.85, z = r.z2 - 0.85, d = 1.0, rusty = true },
		{ x = r.x2 - 0.85, z = r.z2 - 2.2, d = 0.8, rusty = true },
		{ x = r.x1 + 1.9, z = r.z2 - 2.1, d = 0.5 },
	}
	r.valve = r.risers[1]
	r.gauge = r.risers[2]
	r.wallLamps = { { onColumn = 1, y = 8.5 }, { onColumn = 2, y = 8.5 } }
	local standTopY = math.max(devHi.Y, viewerHi.Y)
	local standZ = devCFrame.Position.Z
	r.hanging = {
		pos = Vector3.new(r.cx, r.floorY + 12, standZ - 2.5),
		target = Vector3.new(r.cx, standTopY + 1.5, standZ),
		brightness = 2.5,
	}
	r.backdropFront, r.beamY = cBackLo.Z, r.floorY + 9.4
	r.barrels = { { x = r.cx - 8.1, z = r.z2 - 1.15 }, { x = r.cx - 9.0, z = r.trench1 - 1.6 } }
end

-- Camera shots.
local settingsShot = frameShot(corners(boardLo, boardHi), -4, 0.70) -- board fills ~70% of the height: ~15% margin top and bottom
local creditPoints = {}
for _, standCFrame in { devCFrame, viewerCFrame } do
	local lo, hi = bounds(standCFrame, standSize)
	for _, p in corners(lo, hi) do
		table.insert(creditPoints, p)
	end
	-- A 5-stud avatar standing on the stand, plus headroom for its name label.
	local c = standCFrame.Position
	for _, p in corners(Vector3.new(c.X - 2, hi.Y, c.Z - 0.8), Vector3.new(c.X + 2, hi.Y + 6.2, c.Z + 0.8)) do
		table.insert(creditPoints, p)
	end
end
local creditsShot = frameShot(creditPoints, -10, 0.82)

-- ViewerSpot: a 1x1x1 marker resting on the floor, so its bottom face is where the viewer's feet go. Its LookVector,
-- horizontal, is the way the avatar looks: at the developer's stand, turned part of the way toward the camera's direction.
local function viewerSpotCFrame(shotCFrame, devPosition, viewerPosition, floorY)
	local shotPosition = shotCFrame.Position
	local toDeveloper = Vector3.new(devPosition.X - shotPosition.X, 0, devPosition.Z - shotPosition.Z)
	local away = Vector3.new(viewerPosition.X - devPosition.X, 0, viewerPosition.Z - devPosition.Z).Unit
	local centre = Vector3.new(shotPosition.X, floorY + 0.5, shotPosition.Z) + toDeveloper * SPOT_ALONG + away * SPOT_SIDE
	local atDeveloper = Vector3.new(devPosition.X - centre.X, 0, devPosition.Z - centre.Z).Unit
	local cameraForward = Vector3.new(shotCFrame.LookVector.X, 0, shotCFrame.LookVector.Z).Unit
	local facing = (atDeveloper * (1 - SPOT_TURN) + cameraForward * SPOT_TURN).Unit
	return CFrame.lookAt(centre, centre + facing)
end
local viewerSpot = viewerSpotCFrame(creditsShot, devCFrame.Position, viewerCFrame.Position, creditsLayout.floorY)

-- Build the dressing in detached Models first, so a failure here never touches the user's parts.
local settingsRoom = Instance.new("Model")
settingsRoom.Name = "SettingsRoom"
settingsRoom.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
local creditsRoom = Instance.new("Model")
creditsRoom.Name = "CreditsRoom"
creditsRoom.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
local rooms = { SettingsRoom = settingsRoom, CreditsRoom = creditsRoom }

dress(settingsRoom, settingsLayout)
dress(creditsRoom, creditsLayout)
local settingsMarker = marker(settingsRoom, "SettingsCameraShot", settingsShot)
marker(creditsRoom, "CreditsCameraShot", creditsShot)
marker(creditsRoom, "ViewerSpot", viewerSpot)

-- Settings: a steel bezel framing the board's sides and top against the backdrop.
do
	local front, back, t = boardLo.Z - 0.08, sBackLo.Z, 0.3
	box(settingsRoom, "BezelLeft", Vector3.new(boardHi.X, boardLo.Y, front), Vector3.new(boardHi.X + t, boardHi.Y + t, back), STEEL, M.Metal)
	box(settingsRoom, "BezelRight", Vector3.new(boardLo.X - t, boardLo.Y, front), Vector3.new(boardLo.X, boardHi.Y + t, back), STEEL, M.Metal)
	box(settingsRoom, "BezelTop", Vector3.new(boardLo.X, boardHi.Y, front), Vector3.new(boardHi.X, boardHi.Y + t, back), STEEL, M.Metal)
end

-- Credits: a faint amber ring glowing at the foot of each stand.
for i, standCFrame in { devCFrame, viewerCFrame } do
	local ringDiameter = math.min(standSize.Y, standSize.Z) + 0.4
	local base = Vector3.new(standCFrame.Position.X, creditsLayout.floorY, standCFrame.Position.Z)
	rod(creditsRoom, "StandRing" .. i, base, base + Vector3.new(0, 0.06, 0), ringDiameter, RING, M.Neon)
end

-- Adopt the user's parts (or create stand-ins), restyle them, and place them in their rooms.
settingsRoom.Parent = workspace
creditsRoom.Parent = workspace
for _, def in USER_PARTS do
	local entry = user[def.name]
	local part = entry.part
	if not part then
		part = Instance.new("Part")
		part.Name = def.name
		if def.shape then
			part.Shape = def.shape
		end
		part.Size = def.size
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
	end
	part.Anchored = true
	part.CFrame = entry.cframe
	part.Material = def.material
	part.Color = def.color
	part.Parent = rooms[def.room]
	entry.part = part
end

local viewerStand = user.PlayerCreditStand.part:Clone()
viewerStand.Name = "ViewerCreditStand"
viewerStand.CFrame = viewerCFrame
viewerStand.Parent = creditsRoom

-- BoardFace: the board face whose normal points most directly at the Settings camera.
local board = user.Settingsboard.part
local toCamera = (settingsMarker.Position - board.Position).Unit
local bestFace, bestDot = nil, -math.huge
for _, face in Enum.NormalId:GetEnumItems() do
	local dot = board.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face)):Dot(toCamera)
	if dot > bestDot then
		bestFace, bestDot = face, dot
	end
end
board:SetAttribute("BoardFace", bestFace.Name)

local function count(model)
	local n = 0
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

return string.format(
	"SettingsRoom %d parts, CreditsRoom %d parts, BoardFace %s\nSettingsCameraShot %s\nCreditsCameraShot %s\nViewerSpot %s",
	count(settingsRoom),
	count(creditsRoom),
	bestFace.Name,
	tostring(settingsShot),
	tostring(creditsShot),
	tostring(viewerSpot)
)
