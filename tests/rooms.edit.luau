-- Run in Edit datamodel. Verifies the factory Settings and Credits rooms built by studio/build_menu_rooms.luau:
-- Persistent Models under the map, the user's parts adopted, camera markers, BoardFace, line of sight to the
-- centrepieces, full enclosure (no sky) and non-queryable decoration.
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

return "PASS"
