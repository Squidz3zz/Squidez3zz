-- Build script: run in the Edit datamodel via execute_luau (or paste it into the Command Bar).
-- Builds Room 1's injection lab around the room the user built from loose Parts (those walls stay loose and untouched):
--   Workspace.Room1 (Model, ModelStreamingMode Persistent, attribute Owner = 0) holding
--     Zone            an invisible box filling the room ("is a player in the room?")
--     Chair           the patient chair, facing the window (-X); its Seat holds Attachment SubjectSpot
--     ClaimButton     the panel outside the window wall: Button (with ProximityPrompt ClaimPrompt) and SurfaceGui Sign
--     Shutter         the doorway's steel shutter, built open (invisible, not collidable); attribute ClosedCFrame
--     Gantry          RailA, RailB, Crossbeam, Carriage and Sleeve: Bob's ceiling gantry, the carriage at BobHome
--     BobHome         an invisible marker: Bob's carriage spot at rest, looking the way his needle points
--     BobTheInjector  the user's Bob, moved under the carriage and rewired into Column, Body, Needle and Pupils
--   ServerStorage.Tablet                            a Tool made from the user's Workspace.Tablet model
--   ReplicatedStorage.LabAssets.HardDrives.Explosive  the user's Workspace.ExplosiveHardDrive part
--   ReplicatedStorage.TabletMenu                    the tablet menu's ScreenGui template (see its comment, near the end)
-- The first time, before it changes anything, it copies the user's originals (BobTheInjector, Tablet and
-- ExplosiveHardDrive) into ServerStorage.LabBackup.
-- Safe to run again: only missing pieces are built, and an existing piece is left as it is (a marker or Chair you moved
-- stays moved). The exception is the Gantry and Bob, which every run lines up under wherever BobHome is: to move Bob's
-- resting spot, drag BobHome and run this again. To rebuild a piece, delete it and run this again. Bob, the
-- Tablet tool and the hard drive are made from the user's originals, so to rebuild one of those, first copy its original
-- from ServerStorage.LabBackup into Workspace.
-- Bob's parts are told apart only by class, material and colour, never by where they are.
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Room 1 as the user built it, measured in Studio: the floor's top, and the doorway in the window wall (the wall's two
-- layers run from x 32.13 to 32.78; the posts leave z 40.70 to 45.03 open, up to the header at y 6.33).
local FLOOR_Y = 0.334
local DOOR_LO = Vector3.new(32.15, FLOOR_Y, 40.702)
local DOOR_HI = Vector3.new(32.75, 6.334, 45.032)

-- Where the new pieces go when first built. Every one of them faces the window (-X). HOME is where BobHome is first
-- put; after that the marker itself is read. It is at z 48.5 so Bob's screen, which reaches 4.6 studs to his left,
-- clears the back wall (its inner face is at z 54.33).
local WEST = -Vector3.xAxis
local HOME = CFrame.lookAt(Vector3.new(56, 20.25, 48.5), Vector3.new(56, 20.25, 48.5) + WEST)
local CHAIR = CFrame.lookAt(Vector3.new(51.5, FLOOR_Y, 35), Vector3.new(51.5, FLOOR_Y, 35) + WEST) -- on the floor
local CLAIM = CFrame.lookAt(Vector3.new(31.95, 3.5, 48.5), Vector3.new(31.95, 3.5, 48.5) + WEST) -- its back on the wall

-- The Tablet tool's Grip: where the tablet sits from the R6 right hand. With the arm raised to hold a tool, the hand's
-- grip frame lines up with the torso (X right, Y up, Z back), about (1.5, 0.5, -1.5) from the torso's centre. This puts
-- the tablet in front of the chest, its long side across, the screen (its top) tilted 45 degrees up toward the face.
local TABLET_IN_HAND = CFrame.new(-1.2, -0.5, -0.1) * CFrame.Angles(math.rad(45), 0, 0) * CFrame.Angles(0, math.rad(90), 0)

-- The Factory look.
local STEEL = Color3.fromRGB(58, 55, 52)
local PANEL_COLOR = Color3.fromRGB(38, 36, 34)
local AMBER = Color3.fromRGB(255, 150, 30)
local BLACK = Color3.new(0, 0, 0)
local FONT = Font.fromEnum(Enum.Font.Oswald)
local FONT_BOLD = Font.new(FONT.Family, Enum.FontWeight.Bold)
local M = Enum.Material

local function apply(inst, props, parent)
	for key, value in props do
		inst[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function make(className, props, parent)
	return apply(Instance.new(className), props, parent)
end

-- An anchored dark steel part.
local function part(props, parent)
	return apply(make("Part", { Anchored = true, Material = M.Metal, Color = STEEL }), props, parent)
end

-- No collisions, touches or raycasts.
local function ghost(inst)
	inst.CanCollide = false
	inst.CanTouch = false
	inst.CanQuery = false
	return inst
end

local function label(props, parent)
	local inst = make("TextLabel", {
		BorderSizePixel = 0,
		FontFace = FONT,
		TextColor3 = AMBER,
		TextScaled = true,
	})
	apply(inst, props, parent)
	make("UIPadding", {
		PaddingLeft = UDim.new(0.06, 0),
		PaddingRight = UDim.new(0.06, 0),
		PaddingTop = UDim.new(0.08, 0),
		PaddingBottom = UDim.new(0.08, 0),
	}, inst)
	return inst
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local built, moved = {}, {}
local function missing(parent, name)
	if parent:FindFirstChild(name) then
		return false
	end
	table.insert(built, name)
	return true
end

-- Puts an existing part where the script says, noting it when that moves or resizes it.
local function place(p, cframe, size)
	if (p.Position - cframe.Position).Magnitude > 1e-3 or (p.Size - size).Magnitude > 1e-3 or p.CFrame.LookVector:Dot(cframe.LookVector) < 0.99999 then
		table.insert(moved, p.Name)
	end
	p.Size = size
	p.CFrame = cframe
end

-- A piece made from one of the user's originals in Workspace: built only while the piece is missing, from the
-- original, which it uses up.
local function adopt(parent, name, originalName, build)
	if parent:FindFirstChild(name) then
		return
	end
	local original = workspace:FindFirstChild(originalName)
	if not original then
		warn(("build_lab: %s is missing and so is Workspace.%s; copy ServerStorage.LabBackup.%s into Workspace and run again"):format(name, originalName, originalName))
		return
	end
	build(original)
	table.insert(built, name)
end

-- Ruling R7: keep the untouched originals, once.
local originals = {}
for _, name in { "BobTheInjector", "Tablet", "ExplosiveHardDrive" } do
	local original = workspace:FindFirstChild(name)
	if original then
		table.insert(originals, original)
	end
end
if #originals > 0 and not ServerStorage:FindFirstChild("LabBackup") then
	local backup = make("Folder", { Name = "LabBackup" })
	for _, original in originals do
		local copy = original:Clone()
		assert(copy, "build_lab: cannot copy Workspace." .. original.Name .. " (its Archivable is off)")
		copy.Parent = backup
	end
	backup.Parent = ServerStorage
end

local room = workspace:FindFirstChild("Room1")
if not room then
	room = make("Model", { Name = "Room1", ModelStreamingMode = Enum.ModelStreamingMode.Persistent })
	room:SetAttribute("Owner", 0)
	room.Parent = workspace
	table.insert(built, "Room1")
end

if missing(room, "Zone") then
	ghost(part({
		Name = "Zone",
		CFrame = CFrame.new(45.75, 11.45, 35.7),
		Size = Vector3.new(26.9, 22.2, 37.8),
		Transparency = 1,
	}, room))
end

if missing(room, "BobHome") then
	ghost(part({ Name = "BobHome", CFrame = HOME, Size = Vector3.one, Transparency = 1 }, room))
end
local home = room.BobHome.CFrame -- the marker as it is now: the user may have dragged it

-- The chair, built in its own frame: -Z is its front (toward the window), +Z its back.
if missing(room, "Chair") then
	local chair = make("Model", { Name = "Chair" })
	local seat = part({
		Name = "Seat",
		Material = M.DiamondPlate,
		Size = Vector3.new(2.2, 0.4, 2.2),
		CFrame = CHAIR * CFrame.new(0, 1.8, 0),
	}, chair)
	make("Attachment", { Name = "SubjectSpot", CFrame = CFrame.new(0, seat.Size.Y / 2, 0) }, seat)
	part({ Name = "Back", Size = Vector3.new(2.2, 3, 0.4), CFrame = CHAIR * CFrame.new(0, 3.1, 1.3) }, chair)
	for _, corner in { Vector3.new(-0.9, 0, -0.9), Vector3.new(0.9, 0, -0.9), Vector3.new(-0.9, 0, 0.9), Vector3.new(0.9, 0, 0.9) } do
		part({ Name = "Leg", Size = Vector3.new(0.3, 1.6, 0.3), CFrame = CHAIR * CFrame.new(corner.X, 0.8, corner.Z) }, chair)
	end
	chair.Parent = room
end

if missing(room, "ClaimButton") then
	local claim = make("Model", { Name = "ClaimButton" })
	local panel = part({ Name = "Panel", Size = Vector3.new(2.6, 3.2, 0.3), CFrame = CLAIM }, claim)
	local button = part({
		Name = "Button",
		Material = M.Neon,
		Color = AMBER,
		Size = Vector3.new(1.2, 0.6, 0.3),
		CFrame = CLAIM * CFrame.new(0, -1, -0.3),
	}, claim)
	make("ProximityPrompt", {
		Name = "ClaimPrompt",
		ObjectText = "Room 1",
		ActionText = "Claim Room 1",
		HoldDuration = 0,
		MaxActivationDistance = 8,
		RequiresLineOfSight = false,
	}, button)
	local sign = make("SurfaceGui", {
		Name = "Sign",
		Adornee = panel,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 100,
		LightInfluence = 0,
	}, claim)
	local text = label({
		Name = "Text",
		Text = "ROOM 1 / FREE",
		FontFace = FONT_BOLD,
		TextWrapped = true,
		BackgroundColor3 = PANEL_COLOR,
		Position = UDim2.fromScale(0.06, 0.05),
		Size = UDim2.fromScale(0.88, 0.55),
	}, sign)
	make("UIStroke", { Color = AMBER, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, text)
	claim.Parent = room
end

if missing(room, "Shutter") then
	local closed = CFrame.new((DOOR_LO + DOOR_HI) / 2)
	local shutter = part({ Name = "Shutter", Size = DOOR_HI - DOOR_LO, CFrame = closed, Transparency = 1, CanCollide = false }, room)
	shutter:SetAttribute("ClosedCFrame", closed)
end

-- The gantry, its carriage at BobHome. The sleeve is wide enough to hide the column's fins (2.95 studs from its axis).
if missing(room, "Gantry") then
	make("Model", { Name = "Gantry" }, room)
end
do
	local gantry = room.Gantry
	local x, z = home.X, home.Z
	for _, def in {
		{ "RailA", Vector3.new(33.8, 22.05, 35.7), Vector3.new(1, 1, 37.8), M.Metal },
		{ "RailB", Vector3.new(57.7, 22.05, 35.7), Vector3.new(1, 1, 37.8), M.Metal },
		{ "Crossbeam", Vector3.new(45.75, 21.15, z), Vector3.new(57.7 - 33.8, 0.8, 1.2), M.Metal },
		{ "Carriage", Vector3.new(x, 20.25, z), Vector3.new(3, 1, 3), M.DiamondPlate },
		{ "Sleeve", Vector3.new(x, 16.75, z), Vector3.new(6.4, 6, 6.4), M.DiamondPlate },
	} do
		local cframe, size = CFrame.new(def[2]), def[3]
		place(gantry:FindFirstChild(def[1]) or ghost(part({ Name = def[1], CFrame = cframe, Size = size, Material = def[4] }, gantry)), cframe, size)
	end
end

-- One pivot change for the whole of Bob: turn him about his column axis until the needle (look) points along BobHome's
-- look, and carry the axis to BobHome's X/Z (heights unchanged).
local function moveBob(bob, axis, look)
	local turn = CFrame.lookAt(Vector3.zero, flat(home.LookVector)) * CFrame.lookAt(Vector3.zero, flat(look)):Inverse()
	bob:PivotTo(CFrame.new(home.X, 0, home.Z) * turn * CFrame.new(-flat(axis)) * bob:GetPivot())
end

-- Bob's screen: two lines of amber Oswald on black, on the screen's large face that points away from the column.
local function addDisplay(screen, away)
	local size = screen.Size
	local faces = if size.Y <= size.X and size.Y <= size.Z
		then { Enum.NormalId.Top, Enum.NormalId.Bottom }
		elseif size.X <= size.Z then { Enum.NormalId.Right, Enum.NormalId.Left }
		else { Enum.NormalId.Back, Enum.NormalId.Front }
	local face = faces[1]
	if screen.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face)):Dot(away) < 0 then
		face = faces[2]
	end
	local display = make("SurfaceGui", {
		Name = "Display",
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 100,
		LightInfluence = 0,
	}, screen)
	label({ Name = "Headline", Text = "STANDBY", FontFace = FONT_BOLD, BackgroundColor3 = BLACK, Size = UDim2.fromScale(1, 0.6) }, display)
	label({ Name = "Detail", Text = "", BackgroundColor3 = BLACK, Position = UDim2.fromScale(0, 0.6), Size = UDim2.fromScale(1, 0.4) }, display)
end

local function rewireBob(bob)
	local column, body, needles, whites, pupils, screens = {}, {}, {}, {}, {}, {}
	for _, p in bob:GetChildren() do
		if p:IsA("MeshPart") then
			table.insert(needles, p)
		elseif p:IsA("BasePart") and p.Material == M.CorrodedMetal then
			table.insert(column, p)
		elseif p:IsA("BasePart") and (p.Material == M.Foil or p.Material == M.Metal) then
			table.insert(body, p) -- the hose segments, the head and the nozzle
		elseif p:IsA("BasePart") then
			error("build_lab: Bob has a part that is not column, body or needle: " .. p:GetFullName())
		end
	end
	local panel = bob:FindFirstChild("DisplayPanel")
	local eyes = bob:FindFirstChild("GooglyEyesForBob")
	assert(panel and eyes, "build_lab: Bob's DisplayPanel or GooglyEyesForBob is missing")
	for _, p in panel:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(if p.Material == M.Metal and p.BrickColor.Name == "Really black" then screens else body, p)
		end
	end
	for _, p in eyes:GetDescendants() do
		if p:IsA("BasePart") then
			table.insert(if p.BrickColor.Name == "Really black" then pupils else whites, p)
		end
	end
	assert(
		#column == 16 and #needles == 1 and #whites == 2 and #pupils == 2 and #screens == 1,
		("build_lab: Bob is not as expected: %d column parts (16), %d needles (1), %d eye whites (2), %d pupils (2), %d screens (1)"):format(
			#column, #needles, #whites, #pupils, #screens
		)
	)
	local needle = needles[1]

	-- The column's axis: the centre of the column parts' combined box, seen from above.
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, p in column do
		local half = p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local corner = p.CFrame:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
					lo, hi = lo:Min(corner), hi:Max(corner)
				end
			end
		end
	end
	local axis = Vector3.new((lo.X + hi.X) / 2, 0, (lo.Z + hi.Z) / 2)

	-- The needle's two ends along its long axis (local Y); the tip is the one farther from the column.
	local function ends()
		local a = needle.CFrame:PointToWorldSpace(Vector3.new(0, needle.Size.Y / 2, 0))
		local b = needle.CFrame:PointToWorldSpace(Vector3.new(0, -needle.Size.Y / 2, 0))
		return a, b
	end
	local a, b = ends()
	local tipSign = if flat(a - axis).Magnitude > flat(b - axis).Magnitude then 1 else -1
	local tip, base = a, b
	if tipSign < 0 then
		tip, base = b, a
	end

	moveBob(bob, axis, tip - base)

	a, b = ends()
	tip, base = if tipSign > 0 then a else b, if tipSign > 0 then b else a
	local needleDir = flat(tip - base).Unit
	local pivotPosition = Vector3.new(home.X, lo.Y, home.Z)
	local bobRight = CFrame.lookAt(Vector3.zero, needleDir).RightVector

	local columnModel = make("Model", { Name = "Column" }, bob)
	local core, coreVolume = nil, 0
	for _, p in column do
		p.Parent = columnModel
		local volume = p.Size.X * p.Size.Y * p.Size.Z
		if volume > coreVolume then
			core, coreVolume = p, volume
		end
	end
	core.Name = "Core"
	make("Attachment", {
		Name = "ColumnPivot",
		CFrame = core.CFrame:ToObjectSpace(CFrame.lookAt(pivotPosition, pivotPosition + needleDir)),
	}, core)

	needle.Name = "Needle"
	make("Attachment", { Name = "NeedleBase", CFrame = CFrame.new(0, -tipSign * needle.Size.Y / 2, 0) }, needle)
	make("Attachment", { Name = "NeedleTip", CFrame = CFrame.new(0, tipSign * needle.Size.Y / 2, 0) }, needle)

	local bodyModel = make("Model", { Name = "Body" }, bob)
	for _, p in body do
		p.Parent = bodyModel
	end
	local screen = screens[1]
	screen.Name = "Screen"
	screen.Parent = bodyModel
	addDisplay(screen, flat(screen.Position - pivotPosition))

	-- The eyes sit either side of Bob's arm, each disc (its axis is the part's X) facing out to its own side.
	local whiteR, whiteL = whites[1], whites[2]
	if (whiteR.Position - whiteL.Position):Dot(bobRight) < 0 then
		whiteR, whiteL = whiteL, whiteR
	end
	local middle = (whiteL.Position + whiteR.Position) / 2
	local pupilsModel = make("Model", { Name = "Pupils" }, bob)
	for side, white in { L = whiteL, R = whiteR } do
		white.Name = "EyeWhite" .. side
		white.Parent = bodyModel
		local out = white.CFrame.RightVector
		if out:Dot(white.Position - middle) < 0 then
			out = -out
		end
		make("Attachment", {
			Name = "EyeCenter",
			CFrame = white.CFrame:ToObjectSpace(CFrame.lookAt(white.Position, white.Position + out)),
		}, white)
	end
	for _, pupil in pupils do
		local nearL = (pupil.Position - whiteL.Position).Magnitude < (pupil.Position - whiteR.Position).Magnitude
		pupil.Name = if nearL then "PupilL" else "PupilR"
		pupil.Parent = pupilsModel
	end
	assert(pupilsModel:FindFirstChild("PupilL") and pupilsModel:FindFirstChild("PupilR"), "build_lab: both pupils are nearest the same eye")
	panel:Destroy()
	eyes:Destroy()

	for _, p in bob:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = true
			ghost(p)
		end
	end
	bob:SetAttribute("State", "Standby")
	bob:SetAttribute("Target", "")
	bob:SetAttribute("HardDrive", "")
	bob:SetAttribute("PhaseStart", 0)
	bob.Parent = room
end
adopt(room, "BobTheInjector", "BobTheInjector", rewireBob)

-- A Bob rewired on an earlier run follows BobHome too.
local columnPivot = room:FindFirstChild("BobTheInjector") and room.BobTheInjector:FindFirstChild("ColumnPivot", true)
if columnPivot then
	local at = columnPivot.WorldCFrame
	if (flat(at.Position) - flat(home.Position)).Magnitude > 1e-3 or flat(at.LookVector).Unit:Dot(flat(home.LookVector).Unit) < 0.99999 then
		moveBob(room.BobTheInjector, at.Position, at.LookVector)
		table.insert(moved, "BobTheInjector")
	end
end

-- The tablet becomes a Tool: Handle = its PrimaryPart, every other part welded to it.
adopt(ServerStorage, "Tablet", "Tablet", function(model)
	local handle = model.PrimaryPart
	assert(handle, "build_lab: Workspace.Tablet has no PrimaryPart")
	local tool = make("Tool", { Name = "Tablet", CanBeDropped = false, Grip = TABLET_IN_HAND:Inverse() })
	handle.Name = "Handle"
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.Massless = true
			if p ~= handle then
				make("WeldConstraint", { Part0 = handle, Part1 = p }, p)
			end
		end
	end
	for _, child in model:GetChildren() do
		child.Parent = tool
	end
	model:Destroy()
	tool.Parent = ServerStorage
end)

-- The hard drive becomes the Explosive entry's picture, centred on the origin for the tablet's ViewportFrame.
local assets = ReplicatedStorage:FindFirstChild("LabAssets") or make("Folder", { Name = "LabAssets" }, ReplicatedStorage)
local drives = assets:FindFirstChild("HardDrives") or make("Folder", { Name = "HardDrives" }, assets)
adopt(drives, "Explosive", "ExplosiveHardDrive", function(drive)
	drive.Anchored = true
	drive.CFrame = drive.CFrame.Rotation
	drive.Name = "Explosive"
	drive.Parent = drives
end)

-- The tablet menu's template: a ScreenGui (off, ResetOnSpawn false) that LabClient/TabletMenu.luau clones into each player's PlayerGui
-- and fills in. Factory look, scale-only, inside the screen's core-UI safe area (below the top bar, clear of a notch), never wider than
-- 760 px. Everything is fractions of Root's size (width 0.94 of the screen, at most 760 px; the aspect ratio keeps its shape):
--   Header      Title, Dot + Status (Bob's state, or the reason for a refusal), Close; HeaderLine is the amber rule under it
--   Injections  Label, List (a ScrollingFrame; EntryTemplate is the hidden button each Harddrive's entry is copied from: Icon, a
--               ViewportFrame the brick is put in, and Label)
--   Target      Label and six body-part buttons laid out like an R6 body seen from the front: the body's right limbs are on the
--               screen's left (RightArm, RightLeg), the left ones on the right
--   Confirm     the wide amber button under both
-- Restyle it in Studio if you like, as long as these names stay (the colours of a picked, lost or inactive button are set by
-- TabletMenu.luau, not here). Built only while ReplicatedStorage.TabletMenu is missing; to rebuild it, delete it and run this again.
local BACKDROP = Color3.fromRGB(16, 14, 12)
local MUTED = Color3.fromRGB(220, 208, 190)
local WHITE = Color3.new(1, 1, 1)

-- Room for text inside a button or label.
local function pad(inst)
	make("UIPadding", {
		PaddingLeft = UDim.new(0.06, 0),
		PaddingRight = UDim.new(0.06, 0),
		PaddingTop = UDim.new(0.08, 0),
		PaddingBottom = UDim.new(0.08, 0),
	}, inst)
end

-- A dark steel button; its amber outline (Stroke) is off until TabletMenu shows it picked.
local function tabButton(props, parent)
	local inst = make("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = STEEL,
		BorderSizePixel = 0,
		FontFace = FONT,
		TextColor3 = WHITE,
		TextScaled = true,
	})
	apply(inst, props, parent)
	make("UIStroke", { Name = "Stroke", Color = AMBER, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Enabled = false }, inst)
	return inst
end

local function buildTabletMenu()
	local gui = make("ScreenGui", {
		Name = "TabletMenu",
		ResetOnSpawn = false,
		Enabled = false,
		DisplayOrder = 30, -- below DeathScreen (100), above the main menu (10 to 11)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})
	local root = make("Frame", {
		Name = "Root",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.94),
		BackgroundColor3 = BACKDROP,
		BorderSizePixel = 0,
	}, gui)
	make("UIStroke", { Color = AMBER, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, root)
	make("UISizeConstraint", { MaxSize = Vector2.new(760, 100000) }, root)
	make("UIAspectRatioConstraint", { AspectRatio = 1.85 }, root)

	local header = make("Frame", { Name = "Header", Size = UDim2.fromScale(1, 0.15), BackgroundTransparency = 1, BorderSizePixel = 0 }, root)
	label({
		Name = "Title",
		Text = "BOB-LINK / ROOM 1",
		FontFace = FONT_BOLD,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.02, 0),
		Size = UDim2.fromScale(0.42, 1),
	}, header)
	local dot = make("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.03, 0.3),
		BackgroundColor3 = AMBER,
		BorderSizePixel = 0,
	}, header)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
	make("UIAspectRatioConstraint", {}, dot)
	label({
		Name = "Status",
		Text = "STANDBY",
		TextColor3 = MUTED,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.53, 0),
		Size = UDim2.fromScale(0.36, 1),
	}, header)
	pad(tabButton({
		Name = "Close",
		Text = "X",
		FontFace = FONT_BOLD,
		TextColor3 = AMBER,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.99, 0.5),
		Size = UDim2.fromScale(0.07, 0.95),
	}, header))
	make("Frame", {
		Name = "HeaderLine",
		Position = UDim2.fromScale(0, 0.15),
		Size = UDim2.fromScale(1, 0.008),
		BackgroundColor3 = AMBER,
		BorderSizePixel = 0,
	}, root)

	-- The injections: each entry is copied from EntryTemplate (hidden) and named after its Harddrive's id.
	local injections = make("Frame", {
		Name = "Injections",
		Position = UDim2.fromScale(0.02, 0.19),
		Size = UDim2.fromScale(0.34, 0.6),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
	}, root)
	label({
		Name = "Label",
		Text = "INJECTIONS",
		FontFace = FONT_BOLD,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(1, 0.12),
	}, injections)
	local list = make("ScrollingFrame", {
		Name = "List",
		Position = UDim2.fromScale(0.04, 0.14),
		Size = UDim2.fromScale(0.92, 0.84),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = AMBER,
	}, injections)
	-- Room around the entries for the picked one's outline, which is drawn outside it and would be cut off by the list.
	make("UIPadding", {
		PaddingLeft = UDim.new(0.02, 0),
		PaddingRight = UDim.new(0.02, 0),
		PaddingTop = UDim.new(0.02, 0),
		PaddingBottom = UDim.new(0.02, 0),
	}, list)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0.04, 0) }, list)
	local entry = tabButton({ Name = "EntryTemplate", Text = "", Visible = false, Size = UDim2.fromScale(1, 0.3) }, list)
	local icon = make("ViewportFrame", {
		Name = "Icon",
		Position = UDim2.fromScale(0.04, 0.1),
		Size = UDim2.fromScale(0.34, 0.8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, entry)
	make("UIAspectRatioConstraint", {}, icon)
	label({
		Name = "Label",
		Text = "",
		FontFace = FONT_BOLD,
		TextColor3 = WHITE,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromScale(0.42, 0),
		Size = UDim2.fromScale(0.56, 1),
	}, entry)

	-- The target: an R6 body seen from the front (the copy faces the window, so its left arm is on the screen's right).
	local target = make("Frame", {
		Name = "Target",
		Position = UDim2.fromScale(0.38, 0.19),
		Size = UDim2.fromScale(0.6, 0.6),
		BackgroundColor3 = PANEL_COLOR,
		BorderSizePixel = 0,
	}, root)
	label({
		Name = "Label",
		Text = "TARGET (FACING YOU)",
		FontFace = FONT_BOLD,
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.fromScale(1, 0.11),
	}, target)
	for _, def in {
		{ "Head", "HEAD", 0.3, 0.12, 0.4 },
		{ "RightArm", "R ARM", 0.04, 0.39, 0.24 },
		{ "Torso", "TORSO", 0.3, 0.39, 0.4 },
		{ "LeftArm", "L ARM", 0.72, 0.39, 0.24 },
		{ "RightLeg", "R LEG", 0.3, 0.66, 0.195 },
		{ "LeftLeg", "L LEG", 0.505, 0.66, 0.195 },
	} do
		pad(tabButton({
			Name = def[1],
			Text = def[2],
			Position = UDim2.fromScale(def[3], def[4]),
			Size = UDim2.fromScale(def[5], 0.26),
		}, target))
	end

	pad(tabButton({
		Name = "Confirm",
		Text = "PICK A HARDDRIVE AND A LIMB",
		FontFace = FONT_BOLD,
		BackgroundColor3 = AMBER,
		TextColor3 = BACKDROP,
		Position = UDim2.fromScale(0.02, 0.83),
		Size = UDim2.fromScale(0.96, 0.14),
	}, root))

	gui.Parent = ReplicatedStorage
end
if not ReplicatedStorage:FindFirstChild("TabletMenu") then
	buildTabletMenu()
	table.insert(built, "TabletMenu")
end

return ("build_lab: built [%s], moved [%s]"):format(table.concat(built, ", "), table.concat(moved, ", "))
