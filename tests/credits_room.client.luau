-- Run in the Client datamodel of a FRESH playtest (the player must not have a character yet), with the main menu open.
-- One case per playtest unless a case says otherwise: pick it with CASE below, then run the whole file as an
-- execute_luau call. Drives the menu through MainMenuClient's Studio-only TestHook and observes the real SceneDirector,
-- the client-only room.CreditAvatars folder and the hover decorations. The Developer stands on PlayerCreditStand facing
-- the camera; the Viewer stands on the floor at room.ViewerSpot in the foreground, back to the camera, looking at the
-- Developer's stand, and is labelled "YOU" (ViewerCreditStand stays in the room, empty).
--   A      goTo("Credits"). Within 3s CreditsRoom.CreditAvatars holds Developer and Viewer; the Developer stands on its
--          stand and faces the camera (horizontal dot > 0.8), the Viewer stands on ViewerSpot's floor, both within 0.3
--          (bounding-box bottom) and each has a looping idle track playing. Then hoverAt (a separate copy of
--          CreditsRoom, so it must be stateless) at the Developer's head returns "Developer", highlights it and labels
--          it with its DisplayName attribute, and the Viewer has neither; the label's top edge is inside the viewport,
--          at this window and scaled to a 390 px high one (a phone in landscape); an empty point returns nil and
--          clears both. The Viewer's DisplayName and label are "YOU". Leaves the menu in Credits.
--   YA     goTo("Credits"). Within 3s the Viewer's feet are within 0.3 of ViewerSpot's floor, its LookVector points at
--          PlayerCreditStand (horizontal dot > 0.8) and away from the camera (dot with the camera-to-Viewer direction
--          > 0.5), hoverAt on its torso returns "Viewer" with the label "YOU", no avatar stands on ViewerCreditStand,
--          and the Viewer's projected bounding box overlaps neither the Developer's head, torso or name label nor the
--          BACK button, at this window and at a simulated 844x390 phone screen (same camera, same vertical field of
--          view). Its torso and its YOU label are on screen at both sizes.
--   POINT  run after A: returns the Viewer head's position to aim a real mouse at (user_mouse_input moveTo).
--   A2     run after the real mouse sits on the Viewer's head: the Viewer's highlight appears within 0.5s, its label
--          is "YOU" and the Developer has neither.
--   A3     run after the real mouse moved off both avatars: both decorations are gone within 0.5s.
--   B      Menu and back: the exit hook clears every decoration and stops hover tracking, and the second visit keeps
--          the same two avatars (nothing is cloned twice). Hover tracking is also alive again after the re-entry.
--   C      CreditsRoom.enter on a fresh copy of the room with only the Developer places exactly one avatar and raises
--          no error; enter / exit / dispose twice is harmless; dispose removes the folder. On a copy of the room without
--          ViewerSpot, enter with both sources places only the Developer and raises no error, and a full poll window of
--          place() retries (init's poll: every 0.25s for 20s, so 80 calls) warns about ViewerSpot exactly once.
--   D      Touch path (Studio has no touch): CreditsRoom.tap forwards the first touch position to hoverAt and ignores
--          taps a GUI already used. Touch positions are in SCREEN space (the viewport minus the GUI inset, ~58 px), so
--          every tap here is fed the head's screen point, with the REAL camera aimed at the Credits shot (a spare
--          Camera has no inset). A point just inside the top edge of the Developer's silhouette must hit in screen
--          space and miss when read as a viewport point (an inset higher, in the air), which is what a tap handled
--          in the wrong space does. hoverAt's explicit "screen" and "viewport" spaces are checked too. The decoration
--          persists with no tracker running until the next tap clears it. The real TouchTap wiring itself is
--          verified by reading the code, and by the Device Emulator.
--   E      Late arrival: both source avatars are missing when Credits opens. enter must not wait or fail. Leaving
--          Credits before they arrive places nothing; arriving while the player is in Credits places them.
--   F      Play from Credits: the avatar folder is destroyed, the player spawns, the console stays clean.
local CASE = "A"

local GuiService = game:GetService("GuiService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- The hover outline and the name label take the active theme's colours and font (MenuAssets.THEME).
local THEME = require(game:GetService("ReplicatedFirst"):WaitForChild("MenuAssets", 10)).theme()

local function waitFor(predicate, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		task.wait(0.05)
	end
	return predicate()
end

-- Counts MessageError entries from now on.
local errorCount = 0
local errorLog = {}
local logConnection = LogService.MessageOut:Connect(function(message, messageType)
	if messageType == Enum.MessageType.MessageError then
		errorCount += 1
		table.insert(errorLog, message)
	end
end)

local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui missing")
local menu = waitFor(function()
	return playerGui:FindFirstChild("MainMenu")
end, 10)
assert(menu, "MainMenu missing in PlayerGui")
-- The loading screen's backdrop stays on top (and swallows clicks) for a moment after the menu opens: real input and
-- screenshots must wait until it is gone.
waitFor(function()
	return playerGui:FindFirstChild("LoadingScreen") == nil
end, 8)
-- The Fader lives in its own full-screen ScreenGui, MainMenuFader.
local faderGui = waitFor(function()
	return playerGui:FindFirstChild("MainMenuFader")
end, 10)
assert(faderGui, "MainMenuFader missing in PlayerGui")
local fader = faderGui.Fader
local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
assert(clientScript, "PlayerScripts.MainMenuClient missing")
local hook = clientScript:WaitForChild("TestHook", 10)
assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook (BindableFunction) missing")
local camera = workspace.CurrentCamera
assert(camera, "workspace.CurrentCamera missing")
local room = workspace:WaitForChild("CreditsRoom", 10)
assert(room, "workspace.CreditsRoom missing")

local creditAvatars = ReplicatedStorage:FindFirstChild("CreditAvatars")
local menuAvatars = ReplicatedStorage:WaitForChild("MenuAvatars", 10)

-- Whether a source avatar has everything the client needs to clone it.
local function isComplete(model)
	if not (model and model:FindFirstChildOfClass("Humanoid") and model:FindFirstChild("HumanoidRootPart")) then
		return false
	end
	local expected = model:GetAttribute("DescendantCount")
	return type(expected) ~= "number" or #model:GetDescendants() >= expected
end

-- The two server-built source avatars, complete. Fails if the server never built the developer's.
local function waitForSources()
	assert(creditAvatars, "ReplicatedStorage.CreditAvatars missing (the server builds the developer's avatar there)")
	local developer = waitFor(function()
		local source = creditAvatars:FindFirstChild("Developer")
		return isComplete(source) and source
	end, 20)
	assert(developer, "ReplicatedStorage.CreditAvatars.Developer did not appear (complete) within 20s")
	local viewer = waitFor(function()
		local source = menuAvatars and menuAvatars:FindFirstChild(tostring(player.UserId))
		return isComplete(source) and source
	end, 20)
	assert(viewer, "ReplicatedStorage.MenuAvatars[" .. player.UserId .. "] did not appear (complete) within 20s")
	return developer, viewer
end

local function sceneIs(name)
	return playerGui:GetAttribute("MenuScene") == name and fader.BackgroundTransparency == 1
end

-- Starts a scene change (retrying through the debounce's 1-frame window) and waits until it has settled.
local function goAndSettle(name)
	local started = waitFor(function()
		return hook:Invoke("goTo", name)
	end, 2)
	assert(started, "goTo(" .. name .. ") did not start a transition")
	assert(
		waitFor(function()
			return sceneIs(name)
		end, 3),
		("scene %s did not settle: MenuScene=%s Fader=%s"):format(
			name,
			tostring(playerGui:GetAttribute("MenuScene")),
			tostring(fader.BackgroundTransparency)
		)
	)
	task.wait(0.15) -- the transition thread lets go of its debounce a frame after the Fader reaches 1
end

-- The Credits room's folder of client-side avatars, once it holds both of them.
local function waitForAvatars(timeout)
	return waitFor(function()
		local folder = room:FindFirstChild("CreditAvatars")
		return folder and folder:FindFirstChild("Developer") and folder:FindFirstChild("Viewer") and folder
	end, timeout)
end

-- Y of the stand's top surface, measured with a ray down onto the stand itself.
local function standTop(stand)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { stand }
	local result = workspace:Raycast(stand.Position + Vector3.new(0, 20, 0), Vector3.new(0, -40, 0), params)
	assert(result, "no top surface found on " .. stand.Name)
	return result.Position.Y
end

local function headPoint(model, viewCamera)
	viewCamera = viewCamera or camera
	local head = model:FindFirstChild("Head")
	assert(head, model.Name .. " has no Head")
	local point = viewCamera:WorldToViewportPoint(head.Position)
	local size = viewCamera.ViewportSize
	assert(
		point.Z > 0 and point.X > 0 and point.Y > 0 and point.X < size.X and point.Y < size.Y,
		("%s's head is not on screen: %s of %s"):format(model.Name, tostring(point), tostring(size))
	)
	return Vector2.new(point.X, point.Y)
end

local function labelOf(model)
	local gui = model:FindFirstChild("CreditName")
	return gui, gui and gui:FindFirstChildWhichIsA("TextLabel", true)
end

local function loopingTrack(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		if track.Looped and track.IsPlaying then
			return track
		end
	end
	return nil
end

local function requireCreditsRoom()
	local moduleScript = clientScript:WaitForChild("CreditsRoom", 10)
	assert(moduleScript and moduleScript:IsA("ModuleScript"), "MainMenuClient.CreditsRoom (ModuleScript) missing")
	return require(moduleScript)
end

-- Plants a bare Highlight named CreditHighlight on every avatar. A running hover tracker removes it from every
-- avatar that is not under the mouse, so counting what is left says whether tracking is alive.
local function plantMarkers(folder)
	for _, avatar in folder:GetChildren() do
		local marker = Instance.new("Highlight")
		marker.Name = "CreditHighlight"
		marker.Parent = avatar
	end
end

local function countMarkers(folder)
	local count = 0
	for _, avatar in folder:GetChildren() do
		if avatar:FindFirstChild("CreditHighlight") then
			count += 1
		end
	end
	return count
end

local function countDecorations(folder)
	local count = 0
	for _, avatar in folder:GetChildren() do
		for _, descendant in avatar:GetDescendants() do
			if descendant.Name == "CreditHighlight" or descendant.Name == "CreditName" then
				count += 1
			end
		end
	end
	return count
end

assert(player.Character == nil, "player already has a character; run this in a fresh playtest")

if CASE == "A" then
	local developerSource, viewerSource = waitForSources()
	assert(developerSource:GetAttribute("DisplayName"), "the Developer source has no DisplayName attribute")

	assert(room:FindFirstChild("CreditAvatars") == nil, "CreditAvatars should not exist before the first visit")
	goAndSettle("Credits")
	local folder = waitForAvatars(3)
	assert(folder, "Developer and Viewer did not both appear in CreditsRoom.CreditAvatars within 3s of goTo(Credits)")
	assert(#folder:GetChildren() == 2, "CreditAvatars should hold exactly 2 avatars, has " .. #folder:GetChildren())

	local developer, viewer = folder.Developer, folder.Viewer
	-- The Developer stands on its stand; the Viewer on the floor at ViewerSpot (YA checks its pose in detail).
	local spot = room:FindFirstChild("ViewerSpot")
	assert(spot and spot:IsA("BasePart"), "workspace.CreditsRoom.ViewerSpot missing")
	local anchors = { Developer = room.PlayerCreditStand.Position, Viewer = spot.Position }
	local groundY = { Developer = standTop(room.PlayerCreditStand), Viewer = spot.Position.Y - spot.Size.Y / 2 }
	local shotPosition = camera.CFrame.Position
	for _, avatar in { developer, viewer } do
		local name = avatar.Name
		assert(avatar:IsA("Model"), name .. " should be a Model")
		assert(avatar:FindFirstChildOfClass("Humanoid"), name .. " has no Humanoid")
		assert(avatar:FindFirstChild("Animate", true) == nil, name .. " must not keep its Animate script")
		local rootPart = avatar:FindFirstChild("HumanoidRootPart")
		assert(rootPart and rootPart.Anchored, name .. "'s HumanoidRootPart should be anchored")

		-- Standing on the ground: bounding-box bottom on the stand's top surface (the Developer) or the spot's floor (the Viewer).
		local boxCFrame, boxSize = avatar:GetBoundingBox()
		local bottom = boxCFrame.Position.Y - boxSize.Y / 2
		local top = groundY[name]
		assert(math.abs(bottom - top) <= 0.3, ("%s's feet are %.2f studs off the ground (%.2f vs %.2f)"):format(name, bottom - top, bottom, top))
		-- ... and over the middle of its stand, or on its spot, not beside it.
		local offset = Vector3.new(rootPart.Position.X - anchors[name].X, 0, rootPart.Position.Z - anchors[name].Z)
		assert(offset.Magnitude <= 1.5, ("%s is %.2f studs off the middle of its stand or spot"):format(name, offset.Magnitude))

		-- Level (not tilted up or down), and the Developer faces the camera.
		local look = rootPart.CFrame.LookVector
		assert(math.abs(look.Y) < 0.05, ("%s is tilted: LookVector.Y %.3f"):format(name, look.Y))
		if name == "Developer" then
			local flatLook = Vector3.new(look.X, 0, look.Z).Unit
			local toCamera = shotPosition - rootPart.Position
			local flatToCamera = Vector3.new(toCamera.X, 0, toCamera.Z).Unit
			assert(flatLook:Dot(flatToCamera) > 0.8, ("%s does not face the camera (dot %.2f)"):format(name, flatLook:Dot(flatToCamera)))
		end

		-- Its name for hover: the Developer's comes from the server, the Viewer's is "YOU".
		local displayName = avatar:GetAttribute("DisplayName")
		assert(type(displayName) == "string" and displayName ~= "", name .. " has no DisplayName attribute")
	end
	assert(developer:GetAttribute("DisplayName") == developerSource:GetAttribute("DisplayName"), "Developer DisplayName should come from the server's model")
	assert(viewer:GetAttribute("DisplayName") == "YOU", "Viewer DisplayName should be YOU, not the player's name, got " .. tostring(viewer:GetAttribute("DisplayName")))
	-- Idle animations load asynchronously.
	for _, avatar in { developer, viewer } do
		assert(
			waitFor(function()
				return loopingTrack(avatar)
			end, 10),
			avatar.Name .. " has no looping animation track playing (idle missing)"
		)
	end
	assert(menu.Root.Visible == false and menu.Back.Visible == true, "Root should be hidden and Back visible in Credits")

	-- hoverAt, through a separate copy of the module: all its state must live on the Instances.
	local CreditsRoom = requireCreditsRoom()
	-- No yield between a hoverAt and the checks on it: the real tracker (which follows the mouse) runs on RenderStepped.
	local hit = CreditsRoom.hoverAt(room, camera, headPoint(developer))
	assert(hit == "Developer", "hoverAt on the Developer's head returned " .. tostring(hit))
	local highlight = developer:FindFirstChild("CreditHighlight")
	assert(highlight and highlight:IsA("Highlight"), "Developer has no Highlight named CreditHighlight")
	assert(highlight.OutlineColor == THEME.creditHighlight, "CreditHighlight outline should be the theme's creditHighlight " .. tostring(THEME.creditHighlight) .. ", it is " .. tostring(highlight.OutlineColor))
	assert(highlight.FillTransparency == 1, "CreditHighlight fill should be fully transparent")
	local gui, label = labelOf(developer)
	assert(gui and gui:IsA("BillboardGui"), "Developer has no BillboardGui named CreditName")
	assert(gui.Adornee == developer.Head, "CreditName should be adorned to the Head")
	assert(gui.StudsOffset.Y > 0, "CreditName should float above the head, StudsOffset is " .. tostring(gui.StudsOffset))
	-- The label must stay inside the view: its top edge (the label is gui.Size.Y.Offset px tall, a fixed size in pixels,
	-- centred on the head plus the offset) at this window, and at a 390 px high phone in landscape, where the avatars
	-- shrink with the screen and the label does not.
	local labelCentre = camera:WorldToViewportPoint(developer.Head.Position + camera.CFrame:VectorToWorldSpace(gui.StudsOffset))
	local halfLabel = gui.Size.Y.Offset / 2
	local topNow = labelCentre.Y - halfLabel
	local top390 = labelCentre.Y * 390 / camera.ViewportSize.Y - halfLabel
	print(("credits_room A: label top %.1f px now (viewport %d high), %.1f px at 390 high, StudsOffset %s"):format(topNow, camera.ViewportSize.Y, top390, tostring(gui.StudsOffset)))
	assert(topNow >= 0, ("the name label's top is %.1f px, above the %d px high viewport"):format(topNow, camera.ViewportSize.Y))
	assert(top390 >= 0, ("at a 390 px high viewport the name label's top would be %.1f px, clipped by the top edge"):format(top390))
	assert(gui.AlwaysOnTop == true, "CreditName should be AlwaysOnTop")
	assert(label and label.Text == developer:GetAttribute("DisplayName"), "CreditName text should be the Developer's DisplayName, got " .. tostring(label and label.Text))
	assert(
		label.FontFace.Family == THEME.labelFont.Family and label.FontFace.Weight == THEME.labelFont.Weight,
		"CreditName should use the theme's labelFont " .. THEME.labelFont.Family .. "/" .. THEME.labelFont.Weight.Name .. ", it uses " .. label.FontFace.Family .. "/" .. label.FontFace.Weight.Name
	)
	assert(label.BackgroundColor3 == THEME.nameLabelBg, "CreditName background should be the theme's nameLabelBg")
	assert(label.TextColor3 == THEME.nameLabelText, "CreditName text should be the theme's nameLabelText")
	local nameStroke = label:FindFirstChildOfClass("UIStroke")
	assert(nameStroke and nameStroke.Color == THEME.nameLabelBorder, "CreditName border should be the theme's nameLabelBorder")
	assert(viewer:FindFirstChild("CreditHighlight") == nil and viewer:FindFirstChild("CreditName") == nil, "Viewer must have no decorations while the Developer is hovered")

	-- Moving to the other avatar moves the decorations with it.
	hit = CreditsRoom.hoverAt(room, camera, headPoint(viewer))
	assert(hit == "Viewer", "hoverAt on the Viewer's head returned " .. tostring(hit))
	assert(viewer:FindFirstChild("CreditHighlight") and viewer:FindFirstChild("CreditName"), "Viewer should be decorated")
	assert(developer:FindFirstChild("CreditHighlight") == nil and developer:FindFirstChild("CreditName") == nil, "Developer's decorations should be gone")
	local _, viewerLabel = labelOf(viewer)
	assert(viewerLabel and viewerLabel.Text == "YOU", "the Viewer's label should read YOU, got " .. tostring(viewerLabel and viewerLabel.Text))

	-- Nothing under the point (top-left corner): nil, and everything cleared.
	hit = CreditsRoom.hoverAt(room, camera, Vector2.new(2, 2))
	assert(hit == nil, "hoverAt on an empty point should return nil, got " .. tostring(hit))
	assert(countDecorations(folder) == 0, "hoverAt on an empty point should clear every decoration")

	-- Hovering the same avatar twice does not pile decorations up.
	CreditsRoom.hoverAt(room, camera, headPoint(developer))
	CreditsRoom.hoverAt(room, camera, headPoint(developer))
	assert(countDecorations(folder) == 2, "one hovered avatar should carry exactly one highlight and one label, found " .. countDecorations(folder))
	CreditsRoom.hoverAt(room, camera, Vector2.new(2, 2))
	assert(countDecorations(folder) == 0)

	assert(errorCount == 0, "errors during the credits check: " .. table.concat(errorLog, " | "))
elseif CASE == "YA" then
	waitForSources()
	local CreditsRoom = requireCreditsRoom()
	local spot = room:FindFirstChild("ViewerSpot")
	assert(spot and spot:IsA("BasePart"), "workspace.CreditsRoom.ViewerSpot missing")
	local devStand, viewerStand = room.PlayerCreditStand, room.ViewerCreditStand
	local spotFloorY = spot.Position.Y - spot.Size.Y / 2
	local function flat(v)
		return Vector3.new(v.X, 0, v.Z)
	end

	goAndSettle("Credits")
	local folder = waitForAvatars(3)
	assert(folder, "Developer and Viewer did not both appear in CreditsRoom.CreditAvatars within 3s of goTo(Credits)")
	local developer, viewer = folder.Developer, folder.Viewer
	local viewerRoot = viewer.HumanoidRootPart

	-- Its feet are on the spot's floor, over the spot.
	local boxCFrame, boxSize = viewer:GetBoundingBox()
	local bottom = boxCFrame.Position.Y - boxSize.Y / 2
	assert(math.abs(bottom - spotFloorY) <= 0.3, ("the Viewer's feet are %.2f studs off ViewerSpot's floor (%.2f vs %.2f)"):format(bottom - spotFloorY, bottom, spotFloorY))
	assert(flat(viewerRoot.Position - spot.Position).Magnitude <= 0.5, "the Viewer should stand on ViewerSpot, it is " .. flat(viewerRoot.Position - spot.Position).Magnitude .. " studs off it")

	-- It looks at the developer's podium, and the camera sees its back.
	local look = viewerRoot.CFrame.LookVector
	local flatLook = flat(look).Unit
	assert(math.abs(look.Y) < 0.05, "the Viewer is tilted: LookVector.Y " .. look.Y)
	local atPodium = flatLook:Dot(flat(devStand.Position - viewerRoot.Position).Unit)
	assert(atPodium > 0.8, ("the Viewer does not look at PlayerCreditStand (dot %.2f)"):format(atPodium))
	local awayFromCamera = flatLook:Dot(flat(viewerRoot.Position - camera.CFrame.Position).Unit)
	assert(awayFromCamera > 0.5, ("the camera does not see the Viewer's back (LookVector . camera-to-Viewer %.2f)"):format(awayFromCamera))

	-- Nothing stands on ViewerCreditStand.
	for _, avatar in folder:GetChildren() do
		local away = flat(avatar.HumanoidRootPart.Position - viewerStand.Position).Magnitude
		assert(away > 2.5, ("%s stands %.2f studs from ViewerCreditStand's middle, it must stay empty"):format(avatar.Name, away))
	end
	assert(viewerStand:FindFirstChildWhichIsA("Model", true) == nil, "ViewerCreditStand must hold no avatar")

	-- Screen geometry. The Credits shot is projected by hand (vertical field of view, like Roblox) so it can be drawn on
	-- a screen of any shape: this window's, and a phone in landscape (844x390).
	local shotCFrame = room.CreditsCameraShot.CFrame
	local tanHalf = math.tan(math.rad(camera.FieldOfView / 2))
	local function project(cframe, point, w, h)
		local v = cframe:PointToObjectSpace(point)
		local depth = -v.Z
		return Vector2.new((v.X / (depth * tanHalf * (w / h)) + 1) / 2 * w, (1 - v.Y / (depth * tanHalf)) / 2 * h), depth
	end
	-- A rectangle is { x0, y0, x1, y1 } in pixels.
	local function rectOfPoints(points)
		local rect = { x0 = math.huge, y0 = math.huge, x1 = -math.huge, y1 = -math.huge }
		for _, p in points do
			rect.x0, rect.y0 = math.min(rect.x0, p.X), math.min(rect.y0, p.Y)
			rect.x1, rect.y1 = math.max(rect.x1, p.X), math.max(rect.y1, p.Y)
		end
		return rect
	end
	local function rectAround(centre, w, h)
		return { x0 = centre.X - w / 2, y0 = centre.Y - h / 2, x1 = centre.X + w / 2, y1 = centre.Y + h / 2 }
	end
	local function rectsOverlap(a, b)
		return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
	end
	local function rectHolds(rect, p)
		return p.X >= rect.x0 and p.X <= rect.x1 and p.Y >= rect.y0 and p.Y <= rect.y1
	end
	local function describe(rect)
		return ("(%.0f,%.0f to %.0f,%.0f)"):format(rect.x0, rect.y0, rect.x1, rect.y1)
	end
	local function boxCorners(model)
		local cframe, size = model:GetBoundingBox()
		local corners = {}
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					table.insert(corners, cframe:PointToWorldSpace(Vector3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2)))
				end
			end
		end
		return corners
	end
	local function torsoOf(model)
		return model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or model.HumanoidRootPart
	end

	-- The hand projection must agree with the engine's at this window, or every number below means nothing.
	local viewport = camera.ViewportSize
	local viewerTorso, developerTorso = torsoOf(viewer), torsoOf(developer)
	local engine = camera:WorldToViewportPoint(viewerTorso.Position)
	local mine = project(camera.CFrame, viewerTorso.Position, viewport.X, viewport.Y)
	assert((Vector2.new(engine.X, engine.Y) - mine).Magnitude < 1.5, ("the hand projection %s disagrees with WorldToViewportPoint %s"):format(tostring(mine), tostring(Vector2.new(engine.X, engine.Y))))

	-- The Developer's name label: its size and offset (relative to the camera) come from the real BillboardGui.
	assert(CreditsRoom.hoverAt(room, camera, headPoint(developer)) == "Developer", "setup: hovering the Developer's head should return Developer")
	local developerGui = labelOf(developer)
	assert(developerGui, "setup: the hovered Developer should carry a name label")
	local labelOffset, labelW, labelH = developerGui.StudsOffset, developerGui.Size.X.Offset, developerGui.Size.Y.Offset
	CreditsRoom.hoverAt(room, camera, Vector2.new(2, 2))

	-- BACK, bottom left: the real rectangle at this window, and the same button's scale layout on the phone screen.
	local back = menu.Back
	assert(back.Visible, "BACK should be visible in Credits")
	local function backRectAt(w, h)
		local bw, bh = back.Size.X.Scale * w + back.Size.X.Offset, back.Size.Y.Scale * h + back.Size.Y.Offset
		local bx = back.Position.X.Scale * w + back.Position.X.Offset - back.AnchorPoint.X * bw
		local by = back.Position.Y.Scale * h + back.Position.Y.Offset - back.AnchorPoint.Y * bh
		return { x0 = bx, y0 = by, x1 = bx + bw, y1 = by + bh }
	end
	-- GUI positions are in screen space (the viewport minus the top bar's inset, ~58 px); everything here is viewport space.
	local inset = GuiService:GetGuiInset()
	local realBack = {
		x0 = back.AbsolutePosition.X + inset.X,
		y0 = back.AbsolutePosition.Y + inset.Y,
		x1 = back.AbsolutePosition.X + inset.X + back.AbsoluteSize.X,
		y1 = back.AbsolutePosition.Y + inset.Y + back.AbsoluteSize.Y,
	}
	local derivedBack = backRectAt(viewport.X, viewport.Y)
	assert(
		math.abs(derivedBack.x0 - realBack.x0) < 3 and math.abs(derivedBack.y0 - realBack.y0) < 3 and math.abs(derivedBack.x1 - realBack.x1) < 3 and math.abs(derivedBack.y1 - realBack.y1) < 3,
		("BACK's scale layout %s does not match its real rectangle %s, so the phone-screen check would be wrong"):format(describe(derivedBack), describe(realBack))
	)

	local screens = {
		{ name = ("this window (%dx%d)"):format(viewport.X, viewport.Y), w = viewport.X, h = viewport.Y, back = realBack },
		{ name = "a phone in landscape (844x390)", w = 844, h = 390, back = backRectAt(844, 390) },
	}
	for _, screen in screens do
		local corners = {}
		for _, corner in boxCorners(viewer) do
			local p, depth = project(shotCFrame, corner, screen.w, screen.h)
			assert(depth > 0.3, ("%s: a corner of the Viewer's bounding box is %.2f studs from the camera (behind or against it)"):format(screen.name, depth))
			table.insert(corners, p)
		end
		local viewerRect = rectOfPoints(corners)
		local viewerTorsoPoint = project(shotCFrame, viewerTorso.Position, screen.w, screen.h)
		local developerHead = project(shotCFrame, developer.Head.Position, screen.w, screen.h)
		local developerTorsoPoint = project(shotCFrame, developerTorso.Position, screen.w, screen.h)
		local developerLabel = rectAround(project(shotCFrame, developer.Head.Position + shotCFrame:VectorToWorldSpace(labelOffset), screen.w, screen.h), labelW, labelH)
		local viewerLabel = rectAround(project(shotCFrame, viewer.Head.Position + shotCFrame:VectorToWorldSpace(labelOffset), screen.w, screen.h), labelW, labelH)
		print(("credits_room YA %s: Viewer %s, Viewer label %s, Developer head (%.0f,%.0f) label %s, BACK %s"):format(screen.name, describe(viewerRect), describe(viewerLabel), developerHead.X, developerHead.Y, describe(developerLabel), describe(screen.back)))

		assert(rectHolds({ x0 = 0, y0 = 0, x1 = screen.w, y1 = screen.h }, viewerTorsoPoint), screen.name .. ": the Viewer's torso is off screen at " .. tostring(viewerTorsoPoint))
		assert(viewerLabel.x0 >= 0 and viewerLabel.y0 >= 0 and viewerLabel.x1 <= screen.w and viewerLabel.y1 <= screen.h, ("%s: the Viewer's YOU label %s is not inside the screen"):format(screen.name, describe(viewerLabel)))
		assert(not rectHolds(viewerRect, developerHead), ("%s: the Viewer %s covers the Developer's head (%.0f,%.0f)"):format(screen.name, describe(viewerRect), developerHead.X, developerHead.Y))
		assert(not rectHolds(viewerRect, developerTorsoPoint), ("%s: the Viewer %s covers the Developer's torso (%.0f,%.0f)"):format(screen.name, describe(viewerRect), developerTorsoPoint.X, developerTorsoPoint.Y))
		assert(not rectsOverlap(viewerRect, developerLabel), ("%s: the Viewer %s overlaps the Developer's name label %s"):format(screen.name, describe(viewerRect), describe(developerLabel)))
		assert(not rectsOverlap(viewerRect, screen.back), ("%s: the Viewer %s overlaps the BACK button %s"):format(screen.name, describe(viewerRect), describe(screen.back)))
	end

	-- Hover: at the torso's screen point (this window, the real camera). No yield between the hover and its checks, the
	-- real tracker follows the mouse on RenderStepped.
	local torsoPoint = camera:WorldToViewportPoint(viewerTorso.Position)
	local hit = CreditsRoom.hoverAt(room, camera, Vector2.new(torsoPoint.X, torsoPoint.Y))
	assert(hit == "Viewer", "hoverAt on the Viewer's torso returned " .. tostring(hit))
	local gui, label = labelOf(viewer)
	assert(gui and label, "the hovered Viewer has no CreditName label")
	assert(label.Text == "YOU", "the Viewer's label should read YOU, got " .. tostring(label.Text))
	assert(viewer:GetAttribute("DisplayName") == "YOU", "the Viewer's DisplayName attribute should be YOU")
	assert(viewer:FindFirstChild("CreditHighlight"), "the hovered Viewer should carry the amber outline")
	assert(developer:FindFirstChild("CreditHighlight") == nil and developer:FindFirstChild("CreditName") == nil, "the Developer must have no decorations while the Viewer is hovered")
	CreditsRoom.hoverAt(room, camera, Vector2.new(2, 2))
	assert(countDecorations(folder) == 0, "an empty point should clear every decoration")
	assert(errorCount == 0, "errors: " .. table.concat(errorLog, " | "))
elseif CASE == "POINT" then
	local folder = room:FindFirstChild("CreditAvatars")
	assert(folder and folder:FindFirstChild("Viewer"), "run case A first (the menu must be in Credits)")
	local point = headPoint(folder.Viewer)
	return ("viewport x=%.1f y=%.1f (the real mouse's y is 58 lower than this)"):format(point.X, point.Y)
elseif CASE == "A2" then
	local folder = room:FindFirstChild("CreditAvatars")
	assert(folder and folder:FindFirstChild("Viewer"), "run case A first")
	local viewer, developer = folder.Viewer, folder.Developer
	local highlight = waitFor(function()
		return viewer:FindFirstChild("CreditHighlight")
	end, 0.5)
	assert(highlight, "the real mouse on the Viewer's head did not show CreditHighlight within 0.5s")
	local gui, label = labelOf(viewer)
	assert(gui and label, "the real mouse hover did not add the CreditName label")
	assert(label.Text == "YOU", "label should read YOU, got " .. tostring(label.Text))
	assert(developer:FindFirstChild("CreditHighlight") == nil and developer:FindFirstChild("CreditName") == nil, "Developer must have no decorations")
	assert(errorCount == 0, "errors: " .. table.concat(errorLog, " | "))
elseif CASE == "A3" then
	local folder = room:FindFirstChild("CreditAvatars")
	assert(folder, "run case A first")
	assert(
		waitFor(function()
			return countDecorations(folder) == 0
		end, 0.5),
		"moving the real mouse off the avatars should clear the decorations, " .. countDecorations(folder) .. " left"
	)
	assert(errorCount == 0, "errors: " .. table.concat(errorLog, " | "))
elseif CASE == "B" then
	waitForSources()
	local CreditsRoom = requireCreditsRoom()
	goAndSettle("Credits")
	local folder = waitForAvatars(3)
	assert(folder, "avatars did not appear")
	local developer, viewer = folder.Developer, folder.Viewer

	-- Tracking is alive while the scene is Credits: at most one avatar is under the mouse, so some marker goes.
	plantMarkers(folder)
	assert(
		waitFor(function()
			return countMarkers(folder) < 2
		end, 0.5),
		"hover tracking is not running in Credits (planted markers were never cleared)"
	)
	for _, avatar in folder:GetChildren() do
		for _, name in { "CreditHighlight", "CreditName" } do
			local old = avatar:FindFirstChild(name)
			if old then
				old:Destroy()
			end
		end
	end
	-- exit clears what a hover left behind (called on this test's own copy of the module, with no yield in between,
	-- so the real tracker cannot have cleared it first).
	CreditsRoom.hoverAt(room, camera, headPoint(developer))
	assert(countDecorations(folder) == 2, "setup: the Developer should be decorated")
	CreditsRoom.exit(room)
	assert(countDecorations(folder) == 0, "exit should remove every CreditHighlight and CreditName, " .. countDecorations(folder) .. " left")
	goAndSettle("Menu")
	assert(room:FindFirstChild("CreditAvatars") == folder, "exit must keep the avatars for the next visit")

	-- Tracking is stopped: nothing clears a marker any more.
	plantMarkers(folder)
	task.wait(0.4)
	assert(countMarkers(folder) == 2, "hover tracking still runs after exit (a planted marker was cleared)")
	for _, avatar in folder:GetChildren() do
		avatar.CreditHighlight:Destroy()
	end

	goAndSettle("Credits")
	local again = room:FindFirstChild("CreditAvatars")
	assert(again == folder, "the second visit should reuse the same folder")
	assert(#again:GetChildren() == 2, "second visit should still hold exactly 2 avatars, has " .. #again:GetChildren())
	assert(again:FindFirstChild("Developer") == developer and again:FindFirstChild("Viewer") == viewer, "the avatars should be the same ones, not new clones")
	plantMarkers(again)
	assert(
		waitFor(function()
			return countMarkers(again) < 2
		end, 0.5),
		"hover tracking did not restart on the second visit"
	)
	assert(errorCount == 0, "errors: " .. table.concat(errorLog, " | "))
elseif CASE == "C" then
	local developerSource, viewerSource = waitForSources()
	local CreditsRoom = requireCreditsRoom()

	local testRoom = room:Clone()
	testRoom.Name = "CreditsRoomTest"
	local stale = testRoom:FindFirstChild("CreditAvatars")
	if stale then
		stale:Destroy()
	end
	testRoom.Parent = workspace
	local ok, err = pcall(CreditsRoom.enter, testRoom, { Developer = developerSource, Viewer = nil })
	assert(ok, "enter threw with the Viewer missing: " .. tostring(err))
	local folder = testRoom:FindFirstChild("CreditAvatars")
	assert(folder, "enter should create CreditAvatars")
	assert(#folder:GetChildren() == 1 and folder:FindFirstChild("Developer"), "enter should place exactly the Developer, found " .. #folder:GetChildren() .. " children")
	-- enter again with the same source: nothing is cloned twice.
	ok, err = pcall(CreditsRoom.enter, testRoom, { Developer = developerSource, Viewer = nil })
	assert(ok, "a second enter threw: " .. tostring(err))
	assert(#folder:GetChildren() == 1, "a second enter must not clone the Developer again")
	-- No sources at all is fine too.
	ok, err = pcall(CreditsRoom.enter, testRoom, {})
	assert(ok, "enter threw with no sources: " .. tostring(err))

	-- exit and dispose are idempotent.
	for _, step in { "exit", "exit", "dispose", "dispose" } do
		ok, err = pcall(CreditsRoom[step], testRoom)
		assert(ok, step .. " threw: " .. tostring(err))
	end
	assert(testRoom:FindFirstChild("CreditAvatars") == nil, "dispose should destroy CreditAvatars")
	-- Hovering a disposed room is a quiet nil, and enter on a room without stands warns instead of throwing.
	assert(CreditsRoom.hoverAt(testRoom, camera, Vector2.new(10, 10)) == nil, "hoverAt without avatars should be nil")
	local bare = Instance.new("Model")
	bare.Name = "CreditsRoomBare"
	bare.Parent = workspace
	ok, err = pcall(CreditsRoom.enter, bare, { Developer = developerSource, Viewer = nil })
	assert(ok, "enter on a room without stands threw: " .. tostring(err))
	pcall(CreditsRoom.dispose, bare)
	bare:Destroy()
	testRoom:Destroy()

	-- No ViewerSpot: the Viewer is skipped with a warning, the Developer still shows, nothing throws.
	local noSpotRoom = room:Clone()
	noSpotRoom.Name = "CreditsRoomNoSpot"
	local staleFolder = noSpotRoom:FindFirstChild("CreditAvatars")
	if staleFolder then
		staleFolder:Destroy()
	end
	local spotCopy = noSpotRoom:FindFirstChild("ViewerSpot")
	assert(spotCopy, "setup: workspace.CreditsRoom.ViewerSpot missing")
	spotCopy:Destroy()
	noSpotRoom.Parent = workspace
	local warnings = {}
	local warnConnection = LogService.MessageOut:Connect(function(message, messageType)
		if messageType == Enum.MessageType.MessageWarning then
			table.insert(warnings, message)
		end
	end)
	ok, err = pcall(CreditsRoom.enter, noSpotRoom, { Developer = developerSource, Viewer = viewerSource })
	-- MainMenuClient polls place() every 0.25s for up to 20s while an avatar is missing, so a full poll window is 80 more
	-- calls with the Viewer still unplaceable. They must not each warn again.
	for call = 1, 80 do
		local placed, placeErr = pcall(CreditsRoom.place, noSpotRoom, { Developer = developerSource, Viewer = viewerSource })
		assert(placed, "place threw with ViewerSpot missing (call " .. call .. "): " .. tostring(placeErr))
	end
	task.wait(0.3) -- LogService delivers messages a moment later
	warnConnection:Disconnect()
	assert(ok, "enter threw with ViewerSpot missing: " .. tostring(err))
	local noSpotFolder = noSpotRoom:FindFirstChild("CreditAvatars")
	assert(noSpotFolder, "enter should create CreditAvatars")
	assert(noSpotFolder:FindFirstChild("Developer"), "the Developer should still be placed when ViewerSpot is missing")
	assert(noSpotFolder:FindFirstChild("Viewer") == nil, "the Viewer must not be placed when ViewerSpot is missing")
	assert(#noSpotFolder:GetChildren() == 1, "exactly the Developer expected, found " .. #noSpotFolder:GetChildren() .. " children")
	local spotWarnings = 0
	for _, message in warnings do
		if string.find(message, "ViewerSpot", 1, true) then
			spotWarnings += 1
		end
	end
	assert(spotWarnings >= 1, "a missing ViewerSpot should be warned about; warnings were: " .. table.concat(warnings, " | "))
	assert(
		spotWarnings == 1,
		"a missing ViewerSpot should be warned about once per room, not once per poll: " .. spotWarnings .. " warnings over 81 placement attempts"
	)
	pcall(CreditsRoom.dispose, noSpotRoom)
	noSpotRoom:Destroy()
	assert(errorCount == 0, "errors: " .. table.concat(errorLog, " | "))
elseif CASE == "D" then
	waitForSources()
	local CreditsRoom = requireCreditsRoom()
	goAndSettle("Credits")
	local folder = waitForAvatars(3)
	assert(folder, "avatars did not appear")
	local developer, viewer = folder.Developer, folder.Viewer
	-- Leave Credits so the real mouse tracker is stopped, as it is on touch (nothing follows a finger that is not
	-- touching).
	goAndSettle("Menu")
	assert(countDecorations(folder) == 0)

	-- Look at the avatars from the Credits shot through the REAL camera: only the current camera has the GUI inset (a
	-- spare Camera has a 1x1 viewport and no inset, so screen and viewport space would be the same thing). MenuCamera
	-- puts the camera back on the Menu shot on the next frame, so every use of it below comes straight after aim(),
	-- with no yield in between.
	local function aim()
		camera.CFrame = room.CreditsCameraShot.CFrame
	end

	-- TouchTap positions are in SCREEN space: the viewport minus the top bar's inset (about 58 px), like GUI positions.
	-- headPoint gives viewport space (what WorldToViewportPoint and the mouse use), so convert for every tap.
	local inset = GuiService:GetGuiInset()
	assert(inset.Y > 0, "setup: the GUI inset should be non-zero in a playtest, or this test cannot tell the two spaces apart")
	local function tapPoint(avatar)
		aim()
		return headPoint(avatar) - inset
	end
	local function tap(positions, processed)
		aim()
		return CreditsRoom.tap(room, camera, positions, processed)
	end
	local function hover(point, space)
		aim()
		return CreditsRoom.hoverAt(room, camera, point, space)
	end

	-- A tap a GUI already used (BACK, say) does nothing; a tap on empty ground clears; a tap on an avatar shows it.
	assert(tap({ tapPoint(developer) }, true) == nil, "a tap used by a GUI should be ignored")
	assert(countDecorations(folder) == 0, "a tap used by a GUI should not decorate")
	assert(tap({}, false) == nil, "a tap with no position should be ignored")
	assert(tap({ tapPoint(developer), Vector2.new(2, 2) }, false) == "Developer", "tap should use the first touch position, in screen space (a tap on the head's screen point)")
	assert(developer:FindFirstChild("CreditHighlight") and developer:FindFirstChild("CreditName"), "the tapped avatar should be decorated")
	-- hoverAt names the space explicitly: a screen point in screen space and a viewport point in viewport space both hit.
	assert(hover(tapPoint(viewer), "screen") == "Viewer", "hoverAt(screen) on the Viewer's screen point should hit")
	aim()
	assert(hover(headPoint(viewer), "viewport") == "Viewer", "hoverAt(viewport) on the Viewer's viewport point should hit")
	aim()
	assert(hover(headPoint(developer)) == "Developer", "hoverAt without a space is viewport space")
	assert(tap({ tapPoint(developer) }, false) == "Developer", "tap again on the Developer")

	-- The discriminating check: a point just inside the top edge of the Developer's silhouette. In screen space it is a
	-- hit; the same numbers read as a viewport point land an inset (58 px) higher, in the air above the avatar, so a tap
	-- handled in the wrong space misses.
	aim()
	local headViewport = headPoint(developer)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }
	local topY = nil
	for y = headViewport.Y - 150, headViewport.Y, 2 do
		local ray = camera:ViewportPointToRay(headViewport.X, y)
		if workspace:Raycast(ray.Origin, ray.Direction * 200, params) then
			topY = y
			break
		end
	end
	assert(topY, "found no top edge of the Developer above its head")
	local edgeViewport = Vector2.new(headViewport.X, topY + 6)
	assert(tap({ edgeViewport - inset }, false) == "Developer", "a tap just inside the avatar's top edge, given in screen space, should hit")
	assert(hover(edgeViewport - inset) == nil, "the same point read as a viewport point lands an inset higher, above the avatar: it must miss")

	-- It persists until the next tap (no tracker clears it).
	assert(tap({ tapPoint(developer) }, false) == "Developer", "tap on the Developer again")
	task.wait(0.5)
	assert(developer:FindFirstChild("CreditHighlight") and developer:FindFirstChild("CreditName"), "a tap's decoration should persist")
	assert(tap({ tapPoint(viewer) }, false) == "Viewer", "a tap on the Viewer should return Viewer")
	assert(developer:FindFirstChild("CreditHighlight") == nil and viewer:FindFirstChild("CreditHighlight"), "tapping the other avatar moves the decorations")
	assert(tap({ Vector2.new(2, 2) }, false) == nil, "a tap elsewhere should return nil")
	assert(countDecorations(folder) == 0, "a tap elsewhere should clear every decoration")
	assert(errorCount == 0, "errors: " .. table.concat(errorLog, " | "))
elseif CASE == "E" then
	local developerSource, viewerSource = waitForSources()
	local CreditsRoom = requireCreditsRoom()
	local developerParent, viewerParent = developerSource.Parent, viewerSource.Parent
	-- Hide both sources from this client (a local reparent) to stand in for avatars that have not arrived yet.
	developerSource.Parent = nil
	viewerSource.Parent = nil

	-- Phase 1: leave Credits before they arrive. Nothing may be placed afterwards.
	local started = os.clock()
	goAndSettle("Credits")
	assert(os.clock() - started < 2.5, "entering Credits without avatars took " .. (os.clock() - started) .. "s")
	local folder = room:FindFirstChild("CreditAvatars")
	assert(folder and #folder:GetChildren() == 0, "no avatar should be placed while the sources are missing")
	goAndSettle("Menu")
	developerSource.Parent = developerParent
	viewerSource.Parent = viewerParent
	task.wait(2)
	folder = room:FindFirstChild("CreditAvatars")
	assert(folder == nil or #folder:GetChildren() == 0, "avatars arriving after leaving Credits must not be placed")

	-- Phase 2: they arrive while the player is in Credits: placed, one after the other.
	developerSource.Parent = nil
	viewerSource.Parent = nil
	goAndSettle("Credits")
	folder = room:FindFirstChild("CreditAvatars")
	assert(folder and #folder:GetChildren() == 0, "no avatar should be placed while the sources are missing (phase 2)")
	task.wait(1)
	viewerSource.Parent = viewerParent
	assert(
		waitFor(function()
			return folder:FindFirstChild("Viewer")
		end, 4),
		"the Viewer arriving while in Credits was not placed within 4s"
	)
	assert(folder:FindFirstChild("Developer") == nil, "the Developer has not arrived yet")
	developerSource.Parent = developerParent
	assert(
		waitFor(function()
			return folder:FindFirstChild("Developer")
		end, 4),
		"the Developer arriving while in Credits was not placed within 4s"
	)
	assert(#folder:GetChildren() == 2, "exactly two avatars expected, found " .. #folder:GetChildren())
	-- A late arrival lands on its spot just like an early one.
	local boxCFrame, boxSize = folder.Viewer:GetBoundingBox()
	local bottom = boxCFrame.Position.Y - boxSize.Y / 2
	local spot = room:FindFirstChild("ViewerSpot")
	assert(spot, "workspace.CreditsRoom.ViewerSpot missing")
	assert(math.abs(bottom - (spot.Position.Y - spot.Size.Y / 2)) <= 0.3, "the late Viewer is not standing on ViewerSpot's floor")
	assert(errorCount == 0, "errors: " .. table.concat(errorLog, " | "))
elseif CASE == "F" then
	waitForSources()
	local CreditsRoom = requireCreditsRoom()
	goAndSettle("Credits")
	local folder = waitForAvatars(3)
	assert(folder, "avatars did not appear")
	CreditsRoom.hoverAt(room, camera, headPoint(folder.Developer))
	assert(countDecorations(folder) == 2, "setup: the Developer should be decorated")

	assert(hook:Invoke("play") == true, "play() should start the Play flow")
	assert(
		waitFor(function()
			return room:FindFirstChild("CreditAvatars") == nil
		end, 3),
		"Play should destroy room.CreditAvatars"
	)
	assert(
		waitFor(function()
			return player.Character
		end, 12),
		"the player did not spawn after Play from Credits"
	)
	task.wait(1.5)
	assert(room:FindFirstChild("CreditAvatars") == nil, "nothing may recreate CreditAvatars after Play")
	assert(errorCount == 0, "errors after Play from Credits: " .. table.concat(errorLog, " | "))
else
	error("unknown CASE " .. tostring(CASE))
end

logConnection:Disconnect()
return "PASS"
