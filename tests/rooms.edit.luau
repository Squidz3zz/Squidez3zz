-- Run in Edit datamodel. Verifies the factory Settings and Credits rooms built by studio/build_menu_rooms.luau:
-- Persistent Models under the map, the user's parts adopted, camera markers, BoardFace, line of sight to the
-- centrepieces, full enclosure (no sky) and non-queryable decoration, the empty ViewerCreditStand and the ViewerSpot
-- marker (where the viewer's avatar stands in the Credits foreground).
local ROOMS = {
	{
		name = "SettingsRoom",
		marker = "SettingsCameraShot",
		centrepiece = "Settingsboard",
		userParts = { "BackgroundForSettings", "Settingsboard" },
	},
	{
		name = "CreditsRoom",
		marker = "CreditsCameraShot",
		centrepiece = "PlayerCreditStand",
		userParts = { "BackgroundForCredits", "PlayerCreditStand" },
	},
}
-- Parts that keep their own query settings: the user's four parts and both credit stands.
local EXEMPT = {
	BackgroundForSettings = true,
	Settingsboard = true,
	BackgroundForCredits = true,
	PlayerCreditStand = true,
	ViewerCreditStand = true,
}
local MAX_PARTS = 80
local LAMP_COLOR = Color3.fromRGB(255, 160, 60)
local AXES = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }

local function sameColor(a, b)
	return math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01
end

for _, spec in ROOMS do
	local room = workspace:FindFirstChild(spec.name)
	assert(room, spec.name .. " missing")
	assert(room:IsA("Model"), spec.name .. " must be a Model")
	assert(
		room.ModelStreamingMode == Enum.ModelStreamingMode.Persistent,
		spec.name .. " ModelStreamingMode must be Persistent, got " .. room.ModelStreamingMode.Name
	)

	-- The user's parts: children of their room, moved under the map, anchored so they cannot fall.
	for _, partName in spec.userParts do
		local part = room:FindFirstChild(partName)
		assert(part and part:IsA("BasePart"), spec.name .. "." .. partName .. " missing")
		assert(part.Parent == room, partName .. " must be a direct child of " .. spec.name)
		assert(part.Position.Y < -150, partName .. " must sit under the map (Y < -150), got Y " .. part.Position.Y)
		assert(part.Anchored, partName .. " must be anchored")
		assert(not workspace:FindFirstChild(partName), partName .. " is also still loose in Workspace")
	end

	-- Camera marker.
	local marker = room:FindFirstChild(spec.marker)
	assert(marker and marker:IsA("BasePart"), spec.name .. "." .. spec.marker .. " missing")
	assert(marker.Anchored, spec.marker .. " must be anchored")
	assert(marker.Transparency == 1, spec.marker .. " must have Transparency 1")
	assert(not marker.CanCollide, spec.marker .. " must have CanCollide false")
	assert(not marker.CanQuery, spec.marker .. " must have CanQuery false")
	assert(not marker.CanTouch, spec.marker .. " must have CanTouch false")

	-- Line of sight from the marker to the centrepiece.
	local origin = marker.Position
	local centrepiece = room[spec.centrepiece]
	local toCentre = centrepiece.Position - origin
	local sight = workspace:Raycast(origin, toCentre.Unit * (toCentre.Magnitude + 10))
	assert(
		sight and sight.Instance == centrepiece,
		spec.marker .. " cannot see " .. spec.centrepiece .. "; ray hit " .. (sight and sight.Instance:GetFullName() or "nothing")
	)

	-- Enclosure: every axis ray from the camera hits this room, so no sky or sun shows.
	for _, axis in AXES do
		local hit = workspace:Raycast(origin, axis * 300)
		assert(hit, spec.name .. ": ray " .. tostring(axis) .. " from the marker escapes the room")
		assert(
			hit.Instance:IsDescendantOf(room),
			spec.name .. ": ray " .. tostring(axis) .. " hits " .. hit.Instance:GetFullName() .. ", outside the room"
		)
	end

	-- Every built part is anchored and non-queryable (the user's parts and the stands are exempt from CanQuery).
	local count, lamps, haze = 0, 0, 0
	for _, inst in room:GetDescendants() do
		if inst:IsA("BasePart") then
			count += 1
			assert(inst.Anchored, inst:GetFullName() .. " must be anchored")
			if not EXEMPT[inst.Name] then
				assert(not inst.CanQuery, inst:GetFullName() .. " must have CanQuery false")
			end
		elseif (inst:IsA("PointLight") or inst:IsA("SpotLight")) and sameColor(inst.Color, LAMP_COLOR) then
			lamps += 1
		elseif inst:IsA("ParticleEmitter") then
			haze += 1
		end
	end
	assert(count <= MAX_PARTS, spec.name .. " has " .. count .. " parts, over the " .. MAX_PARTS .. " budget")
	assert(lamps >= 2, spec.name .. " needs at least 2 amber lamp lights, found " .. lamps)
	assert(haze >= 1, spec.name .. " needs a haze ParticleEmitter")
end

-- Settings board: BoardFace names the face that points at the camera marker.
local settingsRoom = workspace.SettingsRoom
local board = settingsRoom.Settingsboard
local faceName = board:GetAttribute("BoardFace")
assert(type(faceName) == "string", "Settingsboard BoardFace attribute missing")
local ok, face = pcall(function()
	return Enum.NormalId[faceName]
end)
assert(ok and face, "BoardFace is not an Enum.NormalId name: " .. faceName)
local normal = board.CFrame:VectorToWorldSpace(Vector3.FromNormalId(face))
local toMarker = (settingsRoom.SettingsCameraShot.Position - board.Position).Unit
assert(normal:Dot(toMarker) > 0.7, "BoardFace " .. faceName .. " does not point at SettingsCameraShot")

-- Credits: a matching ViewerCreditStand 4.5 studs beside the developer's stand, along the backdrop.
local creditsRoom = workspace.CreditsRoom
local devStand = creditsRoom.PlayerCreditStand
local viewerStand = creditsRoom:FindFirstChild("ViewerCreditStand")
assert(viewerStand and viewerStand:IsA("BasePart"), "CreditsRoom.ViewerCreditStand missing")
assert((viewerStand.Size - devStand.Size).Magnitude < 0.01, "ViewerCreditStand must match PlayerCreditStand's size")
local offset = viewerStand.Position - devStand.Position
local along = creditsRoom.BackgroundForCredits.CFrame.RightVector
assert(math.abs(math.abs(offset:Dot(along)) - 4.5) < 0.05, "ViewerCreditStand must be 4.5 studs along the backdrop")
assert((offset - along * offset:Dot(along)).Magnitude < 0.05, "ViewerCreditStand must be level with and beside PlayerCreditStand")

-- Credits: ViewerSpot, the invisible marker the viewer's avatar stands on, in the foreground with its back to the camera.
-- The marker rests on the floor (its bottom face is the avatar's feet) and faces PlayerCreditStand horizontally.
local spot = creditsRoom:FindFirstChild("ViewerSpot")
assert(spot and spot:IsA("BasePart"), "CreditsRoom.ViewerSpot missing")
assert(spot.Anchored, "ViewerSpot must be anchored")
assert(spot.Transparency == 1, "ViewerSpot must have Transparency 1")
assert(not spot.CanCollide, "ViewerSpot must have CanCollide false")
assert(not spot.CanQuery, "ViewerSpot must have CanQuery false")
assert(not spot.CanTouch, "ViewerSpot must have CanTouch false")
assert((spot.Size - Vector3.one).Magnitude < 0.001, "ViewerSpot must be 1x1x1, got " .. tostring(spot.Size))

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- On walkable floor inside the room (not in the grate trench, not on a prop): a ray down through the marker hits the room's
-- floor right at the marker's bottom face.
local spotFloorY = spot.Position.Y - spot.Size.Y / 2
local down = workspace:Raycast(spot.Position + Vector3.new(0, 5, 0), Vector3.new(0, -20, 0))
assert(down and down.Instance:IsDescendantOf(creditsRoom), "nothing of the Credits room under ViewerSpot; ray hit " .. (down and down.Instance:GetFullName() or "nothing"))
assert(down.Instance.Name == "FloorFront", "ViewerSpot must stand on FloorFront, the floor in front of the trench, not " .. down.Instance.Name)
assert(math.abs(down.Position.Y - spotFloorY) < 0.05, ("ViewerSpot's bottom face (Y %.3f) must rest on the floor (Y %.3f)"):format(spotFloorY, down.Position.Y))

-- Faces the developer's podium, level (no tilt), turned a little toward the camera's direction so the camera sees its back.
local cameraPosition = creditsRoom.CreditsCameraShot.Position
local look = spot.CFrame.LookVector
assert(math.abs(look.Y) < 0.01, "ViewerSpot must look horizontally, LookVector.Y is " .. look.Y)
local atPodium = look:Dot(flat(devStand.Position - spot.Position).Unit)
assert(atPodium > 0.85, ("ViewerSpot must face PlayerCreditStand (dot %.2f)"):format(atPodium))
local awayFromCamera = look:Dot(flat(spot.Position - cameraPosition).Unit)
assert(awayFromCamera > 0.55, ("ViewerSpot must look away from the camera, so the camera sees its back (dot %.2f)"):format(awayFromCamera))

-- Between the camera and the developer, about a third of the way, and to the side away from the developer.
local toDeveloper = flat(devStand.Position - cameraPosition)
local fromCamera = flat(spot.Position - cameraPosition)
local fraction = fromCamera:Dot(toDeveloper.Unit) / toDeveloper.Magnitude
assert(fraction > 0.2 and fraction < 0.5, ("ViewerSpot should be about a third of the way from the camera to the developer, it is %.2f"):format(fraction))
local lateral = fromCamera - toDeveloper.Unit * fromCamera:Dot(toDeveloper.Unit)
local awayFromDeveloper = flat(viewerStand.Position - devStand.Position).Unit
assert(lateral:Dot(awayFromDeveloper) > 0.3, "ViewerSpot should be offset to the side away from the developer, toward ViewerCreditStand")

return "PASS"
