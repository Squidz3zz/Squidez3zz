-- CreditsRoom: the avatars in the Credits room. The developer and the viewing player each stand on a stand, facing the
-- camera and idling; the one under the mouse (or the last one tapped) gets an amber outline and a name label.
--
-- The avatars are client-only copies in room.CreditAvatars (a Folder this module makes), named "Developer" and "Viewer",
-- each carrying its name as the attribute DisplayName. They are made once and reused on later visits.
--
--   enter(room, sources)   shows the room: makes the folder, places the copies of sources.Developer and sources.Viewer
--                          (Models, either may be nil) that are not placed yet, and starts hover tracking
--   place(room, sources)   places more of them later (an avatar that had not arrived at enter); does nothing once the
--                          room was exited or disposed
--   exit(room)             stops hover tracking and removes the highlight and label
--   dispose(room)          stops hover tracking and destroys the folder
--   hoverAt(room, camera, point)  decorates the avatar under a screen point (and only it); returns its name, or nil
--   tap(room, camera, touchPositions, processed)  the touch handler: hoverAt at the first touch position
--
-- Scene hooks run behind the black screen or on the Play path, so none of these yields, and exit and dispose are safe to
-- repeat. hoverAt keeps no state of its own (the decorations are Instances in the room), so any copy of this module
-- can show or clear what another copy decorated.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CharacterPreview = require(script.Parent.CharacterPreview)

local AMBER = Color3.fromRGB(255, 150, 30)
local PLATE = Color3.fromRGB(38, 36, 34)
local FONT = Font.new(Font.fromEnum(Enum.Font.Oswald).Family, Enum.FontWeight.Bold)
local RAY_LENGTH = 200
local NAME_OFFSET = Vector3.new(0, 2.5, 0) -- above the head's centre

-- Which stand each avatar stands on, in placement order.
local SLOTS = {
	{ name = "Developer", stand = "PlayerCreditStand" },
	{ name = "Viewer", stand = "ViewerCreditStand" },
}
local DECORATIONS = { "CreditHighlight", "CreditName" }

local CreditsRoom = {}

-- room -> { connections } between enter and exit / dispose. Weak, so a room that is destroyed with no exit is forgotten.
local active = setmetatable({}, { __mode = "k" })

local function stopTracking(room)
	local state = active[room]
	active[room] = nil
	if state then
		for _, connection in state.connections do
			connection:Disconnect()
		end
	end
end

-- Y of the top of the part (its axis-aligned extent: the stands are upright, so this is the top surface).
local function topOf(part)
	local _, _, _, _, _, _, r10, r11, r12 = part.CFrame:GetComponents()
	local size = part.Size
	return part.Position.Y + (math.abs(r10) * size.X + math.abs(r11) * size.Y + math.abs(r12) * size.Z) / 2
end

local function displayNameFor(name, source)
	if name == "Viewer" then
		local localPlayer = Players.LocalPlayer
		if localPlayer then
			return if localPlayer.DisplayName ~= "" then localPlayer.DisplayName else localPlayer.Name
		end
		return name
	end
	local fromServer = source:GetAttribute("DisplayName")
	return if type(fromServer) == "string" and fromServer ~= "" then fromServer else name
end

-- Puts a copy of `source` on the stand, facing the camera marker.
local function placeAvatar(folder, name, source, stand, shot)
	local clone, idleId = CharacterPreview.clonePosed(source)
	local ok, err = pcall(function()
		clone.Name = name
		clone:SetAttribute("DisplayName", displayNameFor(name, source))
		-- The name is the label's job: no second one floating over the head.
		clone:FindFirstChildOfClass("Humanoid").DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

		-- Over the middle of the stand, turned to face the camera marker without tilting.
		local standPosition = stand.Position
		local toShot = Vector3.new(shot.Position.X - standPosition.X, 0, shot.Position.Z - standPosition.Z)
		if toShot.Magnitude < 0.001 then
			toShot = Vector3.new(0, 0, 1)
		end
		local position = Vector3.new(standPosition.X, topOf(stand), standPosition.Z)
		clone:PivotTo(CFrame.lookAt(position, position + toShot))
		clone.Parent = folder

		-- Measured after parenting (accessory welds settle then): the bounding box's bottom goes on the stand's top.
		local boxCFrame, boxSize = clone:GetBoundingBox()
		local bottom = boxCFrame.Position.Y - boxSize.Y / 2
		clone:PivotTo(clone:GetPivot() + Vector3.new(0, topOf(stand) - bottom, 0))
	end)
	if not ok then
		clone:Destroy()
		error(err, 0)
	end
	CharacterPreview.playIdle(clone, idleId)
end

-- Places each given source that is not on its stand yet. A missing stand or a broken source is a warning and an empty
-- stand, never an error.
local function placeSources(room, sources)
	local folder = room:FindFirstChild("CreditAvatars")
	local shot = room:FindFirstChild("CreditsCameraShot")
	if not folder then
		return
	end
	for _, slot in SLOTS do
		local source = sources[slot.name]
		if source and not folder:FindFirstChild(slot.name) then
			local stand = room:FindFirstChild(slot.stand)
			if stand and stand:IsA("BasePart") and shot and shot:IsA("BasePart") then
				local ok, err = pcall(placeAvatar, folder, slot.name, source, stand, shot)
				if not ok then
					warn("CreditsRoom: could not place the " .. slot.name .. ": " .. tostring(err))
				end
			else
				warn("CreditsRoom: " .. room.Name .. "." .. slot.stand .. " or CreditsCameraShot is missing; no " .. slot.name .. " avatar")
			end
		end
	end
end

local function clearDecorations(avatar)
	for _, name in DECORATIONS do
		local decoration = avatar:FindFirstChild(name)
		if decoration then
			decoration:Destroy()
		end
	end
end

-- The amber outline and the name label above the head. Whatever is there already stays, so hovering one avatar for
-- many frames leaves one highlight and one label, not a new pair per frame.
local function decorate(avatar)
	if not avatar:FindFirstChild("CreditHighlight") then
		local highlight = Instance.new("Highlight")
		highlight.Name = "CreditHighlight"
		highlight.OutlineColor = AMBER
		highlight.FillTransparency = 1
		highlight.Adornee = avatar
		highlight.Parent = avatar
	end
	local head = avatar:FindFirstChild("Head")
	if head and not avatar:FindFirstChild("CreditName") then
		-- A BillboardGui sized in pixels keeps its size at any camera distance, so the name reads from the Credits shot.
		local gui = Instance.new("BillboardGui")
		gui.Name = "CreditName"
		gui.Adornee = head
		gui.StudsOffset = NAME_OFFSET
		gui.AlwaysOnTop = true
		gui.Size = UDim2.fromOffset(300, 56)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = PLATE
		label.BackgroundTransparency = 0.1
		label.FontFace = FONT
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextScaled = true
		local displayName = avatar:GetAttribute("DisplayName")
		label.Text = if type(displayName) == "string" and displayName ~= "" then displayName else avatar.Name
		label.Parent = gui

		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingBottom = UDim.new(0, 6)
		padding.PaddingLeft = UDim.new(0, 12)
		padding.PaddingRight = UDim.new(0, 12)
		padding.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color = AMBER
		stroke.Thickness = 2
		stroke.Parent = label
		gui.Parent = avatar
	end
end

-- Decorates the avatar under the screen point and clears the others; returns the hit avatar's name, or nil.
-- The ray only sees the avatars (an Include list): the room's walls and stands would otherwise block it, and the walls
-- are hit by rays even though they are not queryable.
function CreditsRoom.hoverAt(room, camera, point)
	local folder = room:FindFirstChild("CreditAvatars")
	if not folder then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local ray = camera:ViewportPointToRay(point.X, point.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)

	-- The hit is a part somewhere inside one of the avatars: walk up to the avatar itself.
	local hit = result and result.Instance
	while hit and hit.Parent ~= folder do
		hit = hit.Parent
	end
	for _, avatar in folder:GetChildren() do
		if avatar ~= hit then
			clearDecorations(avatar)
		end
	end
	if hit then
		decorate(hit)
		return hit.Name
	end
	return nil
end

-- A tap: whatever is at the first touch position gets the decoration, and it stays until the next tap. Taps a GUI
-- already used (BACK, say) are not for the room.
function CreditsRoom.tap(room, camera, touchPositions, processed)
	local position = touchPositions[1]
	if processed or not position then
		return nil
	end
	return CreditsRoom.hoverAt(room, camera, position)
end

-- Not a finger on a screen or a gamepad: the mouse position means something.
local function mouseIsInUse()
	local lastInput = UserInputService:GetLastInputType()
	return lastInput ~= Enum.UserInputType.Touch and not string.find(lastInput.Name, "^Gamepad")
end

local function startTracking(room)
	stopTracking(room)
	active[room] = {
		connections = {
			-- The mouse is followed every frame; with touch the last tap's result simply stays.
			RunService.RenderStepped:Connect(function()
				local camera = workspace.CurrentCamera
				if camera and mouseIsInUse() then
					CreditsRoom.hoverAt(room, camera, UserInputService:GetMouseLocation())
				end
			end),
			UserInputService.TouchTap:Connect(function(touchPositions, processed)
				local camera = workspace.CurrentCamera
				if camera then
					CreditsRoom.tap(room, camera, touchPositions, processed)
				end
			end),
		},
	}
end

function CreditsRoom.enter(room, sources)
	if not room:FindFirstChild("CreditAvatars") then
		local folder = Instance.new("Folder")
		folder.Name = "CreditAvatars"
		folder.Parent = room
	end
	startTracking(room)
	placeSources(room, sources or {})
end

function CreditsRoom.place(room, sources)
	if active[room] then
		placeSources(room, sources or {})
	end
end

function CreditsRoom.exit(room)
	stopTracking(room)
	local folder = room:FindFirstChild("CreditAvatars")
	if folder then
		for _, avatar in folder:GetChildren() do
			clearDecorations(avatar)
		end
	end
end

function CreditsRoom.dispose(room)
	stopTracking(room)
	local folder = room:FindFirstChild("CreditAvatars")
	if folder then
		folder:Destroy()
	end
end

return CreditsRoom
