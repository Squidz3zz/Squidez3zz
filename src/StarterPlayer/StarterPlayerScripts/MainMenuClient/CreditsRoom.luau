-- CreditsRoom: the avatars in the Credits room, both idling. The developer stands on a stand, facing the camera. The
-- viewing player stands in the foreground on the floor spot room.ViewerSpot, with their back to the camera, looking at the
-- developer's stand like a visitor at an exhibit (the second stand, ViewerCreditStand, stays empty). The one under the
-- mouse (or the last one tapped) gets an outline and a name label; the viewer's label reads YOU, not their name,
-- so it does not look as if they were inside the game twice. The outline's colour and the label's fill, text, border and font
-- come from the menu theme (MenuTheme.get(), read when the decoration is made; Factory is amber on dark steel).
--
-- The avatars are client-only copies in room.CreditAvatars (a Folder this module makes), named "Developer" and "Viewer",
-- each carrying its name as the attribute DisplayName. They are made once and reused on later visits. Without a ViewerSpot
-- the viewer is skipped with a warning (one per room, however often place() retries) and the developer still shows.
--
--   enter(room, sources)   shows the room: makes the folder, places the copies of sources.Developer and sources.Viewer
--                          (Models, either may be nil) that are not placed yet, and starts hover tracking
--   place(room, sources)   places more of them later (an avatar that had not arrived at enter); does nothing once the
--                          room was exited or disposed
--   exit(room)             stops hover tracking and removes the highlight and label
--   dispose(room)          stops hover tracking and destroys the folder
--   hoverAt(room, camera, point, space?)  decorates the avatar under a point (and only it); returns its name, or nil.
--                          `space` says what the point is: "viewport" (default, what UserInputService:GetMouseLocation()
--                          returns) or "screen" (what touch events and GUI positions use: the viewport minus the top
--                          bar's inset, which is about 58 px higher up). Mixing them up misses by that inset.
--   tap(room, camera, touchPositions, processed)  the touch handler: hoverAt, in "screen" space, at the first touch
--                          position
--
-- Scene hooks run behind the black screen or on the Play path, so none of these yields, and exit and dispose are safe to
-- repeat. hoverAt keeps no state of its own (the decorations are Instances in the room), so any copy of this module
-- can show or clear what another copy decorated.
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CharacterPreview = require(script.Parent.CharacterPreview)
local MenuTheme = require(script.Parent.MenuTheme)

local RAY_LENGTH = 200
-- Above the head's centre. Low enough that the 56 px label stays inside the view of a 390 px high phone in landscape.
local NAME_OFFSET = Vector3.new(0, 1.5, 0)

-- The viewer's hover label: not their name, so it does not look as if they were inside the game twice.
local VIEWER_LABEL = "YOU"

-- Where each avatar stands, in placement order: on top of a stand, facing the camera marker, or on a floor spot, facing
-- along the spot's LookVector.
local SLOTS = {
	{ name = "Developer", stand = "PlayerCreditStand" },
	{ name = "Viewer", spot = "ViewerSpot" },
}
local DECORATIONS = { "CreditHighlight", "CreditName" }

local CreditsRoom = {}

-- room -> { connections } between enter and exit / dispose. Weak, so a room that is destroyed with no exit is forgotten.
local active = setmetatable({}, { __mode = "k" })
-- room -> { [warning key] = true }: what has been warned about already. place() retries a missing avatar every poll, so
-- without this a missing ViewerSpot would warn about 80 times per visit. Weak like `active`.
local warned = setmetatable({}, { __mode = "k" })

-- Warns once per room and key (a slot and what is wrong with it); later calls with the same key say nothing.
local function warnOnce(room, key, message)
	local seen = warned[room]
	if not seen then
		seen = {}
		warned[room] = seen
	end
	if not seen[key] then
		seen[key] = true
		warn(message)
	end
end

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

-- The name shown for an avatar: the developer's comes from the server's model, the viewer's is always YOU.
local function displayNameFor(name, source)
	if name == "Viewer" then
		return VIEWER_LABEL
	end
	local fromServer = source:GetAttribute("DisplayName")
	return if type(fromServer) == "string" and fromServer ~= "" then fromServer else name
end

-- A direction on the ground plane, or `fallback` when it has no horizontal part.
local function flatDirection(vector, fallback)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude < 0.001 then fallback else flat.Unit
end

-- Where a slot's avatar stands: the point on the ground its feet go, and the horizontal direction it faces. When a part it
-- needs is missing, returns nil, nil and the names of what is missing.
local function standingPlace(room, slot)
	if slot.stand then
		-- Over the middle of the stand, on its top, turned to face the camera marker.
		local stand, shot = room:FindFirstChild(slot.stand), room:FindFirstChild("CreditsCameraShot")
		if stand and stand:IsA("BasePart") and shot and shot:IsA("BasePart") then
			local standPosition = stand.Position
			local toShot = flatDirection(shot.Position - standPosition, Vector3.zAxis)
			return Vector3.new(standPosition.X, topOf(stand), standPosition.Z), toShot
		end
		return nil, nil, slot.stand .. " or CreditsCameraShot"
	end
	-- On the floor spot: the marker rests on the floor, so its bottom face is the ground. It faces along its LookVector.
	local spot = room:FindFirstChild(slot.spot)
	if spot and spot:IsA("BasePart") then
		local spotPosition = spot.Position
		return Vector3.new(spotPosition.X, spotPosition.Y - spot.Size.Y / 2, spotPosition.Z), flatDirection(spot.CFrame.LookVector, Vector3.zAxis)
	end
	return nil, nil, slot.spot
end

-- Puts a copy of `source` on the ground at `position`, turned to face `forward` without tilting.
local function placeAvatar(folder, name, source, position, forward)
	local clone, idleId = CharacterPreview.clonePosed(source)
	local ok, err = pcall(function()
		clone.Name = name
		clone:SetAttribute("DisplayName", displayNameFor(name, source))
		-- The name is the label's job: no second one floating over the head.
		clone:FindFirstChildOfClass("Humanoid").DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

		clone:PivotTo(CFrame.lookAt(position, position + forward))
		clone.Parent = folder

		-- Measured after parenting (accessory welds settle then): the bounding box's bottom goes on the ground.
		local boxCFrame, boxSize = clone:GetBoundingBox()
		local bottom = boxCFrame.Position.Y - boxSize.Y / 2
		clone:PivotTo(clone:GetPivot() + Vector3.new(0, position.Y - bottom, 0))
	end)
	if not ok then
		clone:Destroy()
		error(err, 0)
	end
	CharacterPreview.playIdle(clone, idleId)
end

-- Places each given source that is not placed yet. A missing stand or spot, or a broken source, is a warning (once per room
-- and slot, however often place() retries) and an empty place (the viewer is skipped and the developer still shows), never
-- an error.
local function placeSources(room, sources)
	local folder = room:FindFirstChild("CreditAvatars")
	if not folder then
		return
	end
	for _, slot in SLOTS do
		local source = sources[slot.name]
		if source and not folder:FindFirstChild(slot.name) then
			local position, forward, missing = standingPlace(room, slot)
			if position then
				local ok, err = pcall(placeAvatar, folder, slot.name, source, position, forward)
				if not ok then
					warnOnce(room, slot.name .. ":failed", "CreditsRoom: could not place the " .. slot.name .. ": " .. tostring(err))
				end
			else
				warnOnce(
					room,
					slot.name .. ":missing",
					"CreditsRoom: " .. room.Name .. "." .. missing .. " is missing; no " .. slot.name .. " avatar"
				)
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

-- The outline and the name label above the head, in the theme's colours. Whatever is there already stays, so hovering one
-- avatar for many frames leaves one highlight and one label, not a new pair per frame (and the theme is only read when
-- something has to be made).
local function decorate(avatar)
	local needHighlight = not avatar:FindFirstChild("CreditHighlight")
	local head = avatar:FindFirstChild("Head")
	local needLabel = head and not avatar:FindFirstChild("CreditName")
	if not (needHighlight or needLabel) then
		return
	end
	local theme = MenuTheme.get()
	if needHighlight then
		local highlight = Instance.new("Highlight")
		highlight.Name = "CreditHighlight"
		highlight.OutlineColor = theme.creditHighlight
		highlight.FillTransparency = 1
		highlight.Adornee = avatar
		highlight.Parent = avatar
	end
	if needLabel then
		-- A BillboardGui sized in pixels keeps its size at any camera distance, so the name reads from the Credits shot.
		local gui = Instance.new("BillboardGui")
		gui.Name = "CreditName"
		gui.Adornee = head
		gui.StudsOffset = NAME_OFFSET
		gui.AlwaysOnTop = true
		gui.Size = UDim2.fromOffset(300, 56)

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = theme.nameLabelBg
		label.BackgroundTransparency = 0.1
		label.FontFace = theme.labelFont
		label.TextColor3 = theme.nameLabelText
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
		stroke.Color = theme.nameLabelBorder
		stroke.Thickness = 2
		stroke.Parent = label
		gui.Parent = avatar
	end
end

-- Decorates the avatar under the point and clears the others; returns the hit avatar's name, or nil. `space` is
-- "viewport" (the default) or "screen", see the header.
-- The ray only sees the avatars (an Include list): the room's walls and stands would otherwise block it, and the walls
-- are hit by rays even though they are not queryable.
function CreditsRoom.hoverAt(room, camera, point, space)
	local folder = room:FindFirstChild("CreditAvatars")
	if not folder then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local ray = if space == "screen"
		then camera:ScreenPointToRay(point.X, point.Y)
		else camera:ViewportPointToRay(point.X, point.Y)
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
-- already used (BACK, say) are not for the room. TouchTap positions are in screen space (inset below the top bar).
function CreditsRoom.tap(room, camera, touchPositions, processed)
	local position = touchPositions[1]
	if processed or not position then
		return nil
	end
	return CreditsRoom.hoverAt(room, camera, position, "screen")
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
