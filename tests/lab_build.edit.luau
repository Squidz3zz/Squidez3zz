-- Run in the Edit datamodel. Checks what studio/build_lab.luau builds: Workspace.Room1 (Zone, Chair, ClaimButton,
-- Shutter, Gantry, BobHome and the rewired BobTheInjector), ServerStorage.Tablet (a Tool),
-- ReplicatedStorage.LabAssets.HardDrives.Explosive and the ServerStorage.LabBackup of the user's originals.
-- Cases, run in this order, with studio/build_lab.luau run where an arrow says:
--   A   checks the build and records Room1's descendant count            -> run the build again
--   B   checks the build again and that the second run added nothing
--   C1  drags BobHome 2 studs toward the window, to x 54                  -> run the build
--   C2  the drag survived, and the gantry and Bob followed BobHome; drags BobHome back home -> run the build
--   C3  they followed back, and the whole build checks out as in A (the place is as it started)
local CASE = "A"

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local STEEL = Color3.fromRGB(58, 55, 52)
local COUNT_ATTRIBUTE = "LabBuildTestCount" -- on ServerStorage, between case A and case B
local BACK_WALL_Z = 54.33 -- the inner face of Room 1's back wall (measured)
local HOME_POSITION = Vector3.new(56, 20.25, 48.5) -- where the build first puts BobHome
local DRAGGED_POSITION = Vector3.new(54, 20.25, 48.5) -- case C1's drag, inside the gantry's travel (x 35.5 to 56)

local function near(a: Vector3, b: Vector3, tolerance: number): boolean
	return (a - b).Magnitude <= tolerance
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function get(parent: Instance, name: string, class: string): any
	local inst = parent:FindFirstChild(name)
	assert(inst, parent:GetFullName() .. "." .. name .. " missing")
	assert(inst:IsA(class), inst:GetFullName() .. " must be a " .. class .. ", is a " .. inst.ClassName)
	return inst
end

local function only(parent: Instance, name: string)
	local count = 0
	for _, child in parent:GetChildren() do
		if child.Name == name then
			count += 1
		end
	end
	assert(count == 1, parent:GetFullName() .. " has " .. count .. " children named " .. name .. ", expected 1")
end

local function ghost(part: BasePart)
	assert(
		part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery,
		part:GetFullName() .. " must be anchored and have CanCollide, CanTouch and CanQuery false"
	)
end

local function sameColor(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01
end

local function check(): Model
	only(workspace, "Room1")
	local room = get(workspace, "Room1", "Model")
	assert(room.ModelStreamingMode == Enum.ModelStreamingMode.Persistent, "Room1 must be ModelStreamingMode Persistent")
	assert(room:GetAttribute("Owner") == 0, "Room1.Owner must be 0")
	for _, d in room:GetDescendants() do
		if d:IsA("BasePart") then
			assert(d.Anchored, d:GetFullName() .. " must be anchored")
		end
	end

	-- Zone: the invisible box filling the room.
	local zone = get(room, "Zone", "Part")
	ghost(zone)
	assert(zone.Transparency == 1, "Zone must be invisible")
	assert(near(zone.Size, Vector3.new(26.9, 22.2, 37.8), 0.01), "Zone size is " .. tostring(zone.Size))
	assert(near(zone.Position, Vector3.new(45.75, 11.45, 35.7), 0.01), "Zone position is " .. tostring(zone.Position))
	assert(near(zone.CFrame.LookVector, -Vector3.zAxis, 0.001) and near(zone.CFrame.UpVector, Vector3.yAxis, 0.001), "Zone must not be rotated")

	-- BobHome: the invisible marker Bob's carriage rests at.
	local home = get(room, "BobHome", "Part")
	ghost(home)
	assert(home.Transparency == 1, "BobHome must be invisible")
	assert(near(home.Size, Vector3.one, 0.001), "BobHome must be 1x1x1")
	assert(near(home.Position, HOME_POSITION, 0.01), "BobHome position is " .. tostring(home.Position))
	assert(near(home.CFrame.LookVector, -Vector3.xAxis, 0.001), "BobHome must look along -X")

	-- Chair: seat centre at x 51.5, z 35, facing -X, the back on the +X side.
	local chair = get(room, "Chair", "Model")
	local seat = get(chair, "Seat", "BasePart")
	local spot = get(seat, "SubjectSpot", "Attachment")
	assert(near(spot.WorldCFrame.LookVector, -Vector3.xAxis, 0.01), "SubjectSpot must face -X, looks along " .. tostring(spot.WorldCFrame.LookVector))
	assert(near(flat(spot.WorldPosition), Vector3.new(51.5, 0, 35), 0.01), "SubjectSpot must be at x 51.5, z 35")
	assert(near(flat(seat.Position), Vector3.new(51.5, 0, 35), 0.01), "the seat's centre must be at x 51.5, z 35")
	local seatTop = seat.Position.Y + seat.Size.Y / 2
	assert(math.abs(spot.WorldPosition.Y - seatTop) < 0.01, "SubjectSpot must be on the seat's top")
	local back = get(chair, "Back", "BasePart")
	assert(back.Position.X > seat.Position.X + 0.5, "the chair's back must be on the +X side")

	-- ClaimButton: outside the window wall next to the doorway, facing -X.
	local claim = get(room, "ClaimButton", "Model")
	local button = get(claim, "Button", "BasePart")
	assert(near(button.Position, Vector3.new(31.8, 3.5, 48.5), 1.5), "ClaimButton.Button is at " .. tostring(button.Position))
	assert(button.Position.X < 32.13, "ClaimButton.Button must be outside the wall (x < 32.13)")
	local prompt = get(button, "ClaimPrompt", "ProximityPrompt")
	assert(prompt.ObjectText == "Room 1", "ClaimPrompt.ObjectText must be 'Room 1'")
	assert(prompt.ActionText == "Claim Room 1", "ClaimPrompt.ActionText must be 'Claim Room 1'")
	assert(prompt.HoldDuration == 0, "ClaimPrompt.HoldDuration must be 0")
	assert(prompt.MaxActivationDistance == 8, "ClaimPrompt.MaxActivationDistance must be 8")
	assert(not prompt.RequiresLineOfSight, "ClaimPrompt.RequiresLineOfSight must be false")
	local sign = get(claim, "Sign", "SurfaceGui")
	local panel = sign.Adornee or sign.Parent
	assert(panel and panel:IsA("BasePart") and panel:IsDescendantOf(claim), "Sign must be on a part of ClaimButton")
	local signNormal = panel.CFrame:VectorToWorldSpace(Vector3.FromNormalId(sign.Face))
	assert(signNormal.X < -0.99, "Sign must face -X")
	assert(get(sign, "Text", "TextLabel").Text == "ROOM 1 / FREE", "Sign.Text must read 'ROOM 1 / FREE'")

	-- Shutter: open (invisible, not collidable); ClosedCFrame fills the doorway.
	local shutter = get(room, "Shutter", "BasePart")
	assert(shutter.Material == Enum.Material.Metal and sameColor(shutter.Color, STEEL), "Shutter must be Metal, RGB(58,55,52)")
	assert(shutter.Transparency == 1 and not shutter.CanCollide, "Shutter must be built open (Transparency 1, CanCollide false)")
	local closed = shutter:GetAttribute("ClosedCFrame")
	assert(typeof(closed) == "CFrame", "Shutter.ClosedCFrame must be a CFrame attribute")
	local before = shutter.CFrame
	shutter.CFrame = closed
	shutter.CanCollide = true
	local misses = {}
	for _, point in {
		Vector3.new(30, 3, closed.Position.Z),
		Vector3.new(30, 0.45, 40.8),
		Vector3.new(30, 0.45, 44.95),
		Vector3.new(30, 6.25, 40.8),
		Vector3.new(30, 6.25, 44.95),
	} do
		local hit = workspace:Raycast(point, Vector3.new(5, 0, 0))
		if not (hit and hit.Instance == shutter) then
			table.insert(misses, tostring(point) .. " hit " .. (hit and hit.Instance:GetFullName() or "nothing"))
		end
	end
	shutter.CFrame = before
	shutter.CanCollide = false
	assert(#misses == 0, "the closed Shutter must fill the doorway; rays from " .. table.concat(misses, "; "))

	-- Gantry: rails, crossbeam, carriage and sleeve, the moving parts at BobHome's X/Z.
	local gantry = get(room, "Gantry", "Model")
	local x, z = home.Position.X, home.Position.Z
	for name, spec in {
		RailA = { Vector3.new(33.8, 22.05, 35.7), Vector3.new(1, 1, 37.8) },
		RailB = { Vector3.new(57.7, 22.05, 35.7), Vector3.new(1, 1, 37.8) },
		Crossbeam = { Vector3.new(45.75, 21.15, z), Vector3.new(23.9, 0.8, 1.2) },
		Carriage = { Vector3.new(x, 20.25, z), Vector3.new(3, 1, 3) },
		Sleeve = { Vector3.new(x, 16.75, z), Vector3.new(6.4, 6, 6.4) },
	} do
		local part = get(gantry, name, "BasePart")
		assert(near(part.Position, spec[1], 0.01), "Gantry." .. name .. " is at " .. tostring(part.Position))
		assert(near(part.Size, spec[2], 0.01), "Gantry." .. name .. " has size " .. tostring(part.Size))
	end
	for _, d in gantry:GetDescendants() do
		if d:IsA("BasePart") then
			ghost(d)
		end
	end

	-- Bob: moved under the carriage, rewired into Column, Body, Needle and Pupils.
	local bob = get(room, "BobTheInjector", "Model")
	assert(bob:GetAttribute("State") == "Standby", "Bob's State must be 'Standby'")
	assert(bob:GetAttribute("Target") == "", "Bob's Target must be ''")
	assert(bob:GetAttribute("HardDrive") == "", "Bob's HardDrive must be ''")
	assert(bob:GetAttribute("PhaseStart") == 0, "Bob's PhaseStart must be 0")
	local column = get(bob, "Column", "Model")
	local body = get(bob, "Body", "Model")
	local needle = get(bob, "Needle", "MeshPart")
	local pupils = get(bob, "Pupils", "Model")
	for _, d in bob:GetDescendants() do
		if d:IsA("BasePart") then
			ghost(d)
			assert(
				d == needle or d.Parent == column or d.Parent == body or d.Parent == pupils,
				d:GetFullName() .. " must be in Column, Body or Pupils, or be the Needle"
			)
		end
	end

	-- The corners of a part's box, in world space.
	local function corners(p: BasePart): { Vector3 }
		local list, half = {}, p.Size / 2
		for _, corner in { Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1) } do
			for _, sign in { 1, -1 } do
				table.insert(list, p.CFrame:PointToWorldSpace(half * corner * sign))
			end
		end
		return list
	end

	-- Column: the 16 CorrodedMetal parts; Core holds ColumnPivot at the axis and bottom, upright, looking along the needle.
	-- The sleeve's sides cover the column all round (its fins reach 2.95 studs from the axis).
	local sleeve = gantry.Sleeve
	local columnParts, lowest = 0, math.huge
	for _, p in column:GetChildren() do
		if p:IsA("BasePart") then
			columnParts += 1
			assert(p.Material == Enum.Material.CorrodedMetal, p:GetFullName() .. " must be CorrodedMetal")
			for _, c in corners(p) do
				lowest = math.min(lowest, c.Y)
				assert(
					math.abs(c.X - sleeve.Position.X) <= sleeve.Size.X / 2 and math.abs(c.Z - sleeve.Position.Z) <= sleeve.Size.Z / 2,
					p:GetFullName() .. " sticks out of the Sleeve's sides"
				)
			end
		end
	end
	assert(columnParts == 16, "Column must hold 16 parts, holds " .. columnParts)
	local pivot = get(get(column, "Core", "BasePart"), "ColumnPivot", "Attachment")
	local pivotCF = pivot.WorldCFrame
	assert(near(flat(pivotCF.Position), flat(home.Position), 0.01), "ColumnPivot must be at BobHome's X/Z, is at " .. tostring(pivotCF.Position))
	assert(math.abs(pivotCF.Position.Y - lowest) < 0.01, ("ColumnPivot must be at the column's lowest Y %.3f, is at %.3f"):format(lowest, pivotCF.Position.Y))
	assert(near(pivotCF.UpVector, Vector3.yAxis, 0.001), "ColumnPivot must be upright")

	-- Needle: NeedleBase and NeedleTip at its two ends, the tip 12.02 studs out, pointing along BobHome's look.
	local base = get(needle, "NeedleBase", "Attachment")
	local tip = get(needle, "NeedleTip", "Attachment")
	assert(math.abs((tip.WorldPosition - base.WorldPosition).Magnitude - needle.Size.Y) < 0.01, "NeedleBase and NeedleTip must be at the needle's two ends")
	local reach = flat(tip.WorldPosition - pivotCF.Position).Magnitude
	assert(math.abs(reach - 12.02) <= 0.1, ("the needle tip must be 12.02 studs from ColumnPivot, is %.3f"):format(reach))
	assert(flat(base.WorldPosition - pivotCF.Position).Magnitude < reach, "NeedleTip must be the end farther from the column")
	local needleDir = flat(tip.WorldPosition - base.WorldPosition).Unit
	assert(needleDir:Dot(home.CFrame.LookVector) > 0.9999, "the needle must point along BobHome's LookVector")
	assert(near(pivotCF.LookVector, needleDir, 0.01), "ColumnPivot must look along the needle")

	-- Eyes: EyeWhiteR on Bob's right looking along the needle; each pupil paired to the nearest white.
	local whiteL = get(body, "EyeWhiteL", "BasePart")
	local whiteR = get(body, "EyeWhiteR", "BasePart")
	get(whiteL, "EyeCenter", "Attachment")
	get(whiteR, "EyeCenter", "Attachment")
	assert((whiteR.Position - whiteL.Position):Dot(pivotCF.RightVector) > 0, "EyeWhiteR must be on Bob's right")
	local pupilL = get(pupils, "PupilL", "BasePart")
	local pupilR = get(pupils, "PupilR", "BasePart")
	assert((pupilL.Position - whiteL.Position).Magnitude < (pupilL.Position - whiteR.Position).Magnitude, "PupilL must be nearest EyeWhiteL")
	assert((pupilR.Position - whiteR.Position).Magnitude < (pupilR.Position - whiteL.Position).Magnitude, "PupilR must be nearest EyeWhiteR")

	-- Screen: the Display on its large face, pointing away from the column.
	local screen = get(body, "Screen", "BasePart")
	local display = get(screen, "Display", "SurfaceGui")
	assert(get(display, "Headline", "TextLabel").Text == "STANDBY", "Headline must read 'STANDBY'")
	assert(get(display, "Detail", "TextLabel").Text == "", "Detail must be empty")
	local faceAxis = Vector3.FromNormalId(display.Face)
	local size = screen.Size
	local thinnest = math.min(size.X, size.Y, size.Z)
	assert(math.abs((size * faceAxis.Unit:Abs()).Magnitude - thinnest) < 0.001, "Display must be on the screen's large face")
	local faceNormal = screen.CFrame:VectorToWorldSpace(faceAxis)
	assert(faceNormal:Dot(flat(screen.Position - pivotCF.Position)) > 0, "Display must face away from the column")
	-- At home the screen clears the back wall, whose inner face is at z 54.33.
	for _, c in corners(screen) do
		assert(c.Z < BACK_WALL_Z, ("Bob's Screen reaches z %.2f, into the back wall (inner face z %.2f)"):format(c.Z, BACK_WALL_Z))
	end

	-- Moved out of Workspace.
	for _, name in { "BobTheInjector", "Tablet", "ExplosiveHardDrive" } do
		assert(not workspace:FindFirstChild(name), "Workspace." .. name .. " should be gone (moved)")
	end

	-- The Tablet tool: Handle, every other part welded to it, all unanchored, not colliding, massless.
	only(ServerStorage, "Tablet")
	local tool = get(ServerStorage, "Tablet", "Tool")
	local handle = get(tool, "Handle", "BasePart")
	local welded = {}
	for _, w in tool:GetDescendants() do
		if w:IsA("WeldConstraint") and w.Enabled then
			if w.Part0 == handle and w.Part1 then
				welded[w.Part1] = true
			elseif w.Part1 == handle and w.Part0 then
				welded[w.Part0] = true
			end
		end
	end
	local tabletParts = 0
	for _, p in tool:GetDescendants() do
		if p:IsA("BasePart") then
			tabletParts += 1
			assert(not p.Anchored and not p.CanCollide and p.Massless, p:GetFullName() .. " must be unanchored, CanCollide false and Massless")
			assert(p == handle or welded[p], p:GetFullName() .. " must be welded to the Handle")
		end
	end
	assert(tabletParts > 1, "the Tablet tool has only " .. tabletParts .. " part")
	-- The Grip, with an R6 arm raised to hold a tool (RightGrip's frame lined up with the torso at (1.5, 0.5, -1.5)):
	-- in front of the chest, screen (the handle's top) tilted up toward the face.
	local held = CFrame.new(1.5, 0.5, -1.5) * tool.Grip:Inverse()
	assert(held.Position.Z < -0.8 and math.abs(held.Position.X) < 1 and math.abs(held.Position.Y) < 1, "the Grip must hold the tablet in front of the chest, at " .. tostring(held.Position))
	assert(held.UpVector.Y > 0.5 and held.UpVector.Z > 0.3, "the tablet's screen must face up toward the face, faces " .. tostring(held.UpVector))

	-- The hard drive's picture.
	only(ReplicatedStorage, "LabAssets")
	local drives = get(get(ReplicatedStorage, "LabAssets", "Folder"), "HardDrives", "Folder")
	only(drives, "Explosive")
	assert(get(drives, "Explosive", "BasePart").Anchored, "LabAssets.HardDrives.Explosive must be anchored")

	-- The backup of the user's originals.
	local backup = get(ServerStorage, "LabBackup", "Folder")
	get(backup, "BobTheInjector", "Model")
	get(backup, "Tablet", "Model")
	get(backup, "ExplosiveHardDrive", "BasePart")

	return room
end

-- BobHome is where it was put, and the gantry's moving parts and Bob's column axis are at its X/Z.
local function followsBobHome(position: Vector3)
	local room = workspace.Room1
	local home = room.BobHome.Position
	assert(near(home, position, 0.01), "BobHome should still be at " .. tostring(position) .. " after the build, is at " .. tostring(home))
	local gantry = room.Gantry
	for _, at in {
		{ "Carriage", gantry.Carriage.Position },
		{ "Sleeve", gantry.Sleeve.Position },
		{ "ColumnPivot", room.BobTheInjector.Column.Core.ColumnPivot.WorldPosition },
	} do
		assert(near(flat(at[2]), flat(home), 0.01), at[1] .. " is at " .. tostring(at[2]) .. ", not at BobHome's X/Z " .. tostring(home))
	end
	assert(math.abs(gantry.Crossbeam.Position.Z - home.Z) < 0.01, "the Crossbeam is not at BobHome's Z")
end

local function dragBobHome(position: Vector3)
	workspace.Room1.BobHome.CFrame = CFrame.lookAt(position, position - Vector3.xAxis)
end

if CASE == "A" or CASE == "B" then
	local room = check()
	local count = #room:GetDescendants()
	if CASE == "A" then
		ServerStorage:SetAttribute(COUNT_ATTRIBUTE, count)
		return "PASS lab_build A (Room1 has " .. count .. " descendants; now run studio/build_lab.luau again, then case B)"
	end
	local recorded = ServerStorage:GetAttribute(COUNT_ATTRIBUTE)
	assert(type(recorded) == "number", "run case A first")
	ServerStorage:SetAttribute(COUNT_ATTRIBUTE, nil)
	assert(count == recorded, "the second run changed Room1's descendant count from " .. recorded .. " to " .. count)
	return "PASS lab_build B (second run added nothing: " .. count .. " descendants)"
elseif CASE == "C1" then
	check()
	dragBobHome(DRAGGED_POSITION)
	return "PASS lab_build C1 (BobHome dragged to " .. tostring(DRAGGED_POSITION) .. "; now run studio/build_lab.luau, then case C2)"
elseif CASE == "C2" then
	followsBobHome(DRAGGED_POSITION)
	dragBobHome(HOME_POSITION)
	return "PASS lab_build C2 (the gantry and Bob followed the drag; BobHome dragged back, now run studio/build_lab.luau, then case C3)"
elseif CASE == "C3" then
	followsBobHome(HOME_POSITION)
	check()
	return "PASS lab_build C3 (followed back home; the build checks out as it started)"
end
error("unknown CASE " .. CASE)
