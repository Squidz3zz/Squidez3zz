-- Run in the Client datamodel of a FRESH playtest, with the main menu still open. Pick the case with CASE:
--   "A": the player's avatar shows up in CharacterView (needs the server to have built MenuAvatars[UserId], a few seconds
--        after join): Humanoid present, no Animate, PreviewCamera set and framing the upper body (bottom of the torso to
--        the top of the head, aimed at the centre of that box), idle track looping, and the wave arm staying in frame.
--   "B": pressing Play immediately (before the avatar arrives) causes no errors and still spawns the player.
--        Uses the Studio-only MainMenuClient.TestHook, because execute_luau cannot reach the script's locals.
--   "C": CharacterPreview.show returns nil, without error, when the viewport has already been destroyed.
--        Requires the ModuleScript directly (a separate copy of the module, so it only touches the Instances passed in).
local CASE = "A"

local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local AVATAR_TIMEOUT = 15

local function waitFor(predicate, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		task.wait(0.1)
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
local root = menu:FindFirstChild("Root")
assert(root, "MainMenu.Root missing")
local viewport = root:FindFirstChild("CharacterView")
assert(viewport and viewport:IsA("ViewportFrame"), "Root.CharacterView (ViewportFrame) missing")
local worldModel = viewport:FindFirstChild("WorldModel")
assert(worldModel, "CharacterView.WorldModel missing")

local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
assert(clientScript, "PlayerScripts.MainMenuClient missing")

if CASE == "A" then
	assert(player.Character == nil, "player already has a character; run this in a fresh playtest")

	local model = waitFor(function()
		return worldModel:FindFirstChildOfClass("Model")
	end, AVATAR_TIMEOUT)
	assert(model, "no model in WorldModel")

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "preview model has no Humanoid")
	assert(model:FindFirstChild("Animate", true) == nil, "preview model must not keep its Animate script")

	local camera = viewport.CurrentCamera
	assert(camera, "CharacterView.CurrentCamera is nil")
	assert(camera.Name == "PreviewCamera", "CurrentCamera should be PreviewCamera, got " .. camera.Name)
	assert(camera.FieldOfView == 30, "PreviewCamera.FieldOfView should be 30, got " .. camera.FieldOfView)

	local rootPart = model:FindFirstChild("HumanoidRootPart")
	assert(rootPart and rootPart.Anchored, "HumanoidRootPart should be anchored")

	-- The upper body: from the bottom of the torso (LowerTorso on R15) to the top of the head.
	local torso = model:FindFirstChild("LowerTorso") or model:FindFirstChild("Torso")
	local head = model:FindFirstChild("Head")
	assert(torso and head, "preview model has no torso / head part")
	local bottomY = torso.Position.Y - torso.Size.Y / 2
	local topY = head.Position.Y + head.Size.Y / 2
	local boxCentre = Vector3.new(rootPart.Position.X, (bottomY + topY) / 2, rootPart.Position.Z)

	-- The camera aims at the middle of that box: the centre is within half a stud of the camera's look ray (the brief
	-- allows a stud; the old whole-body framing missed by about 0.9, so a stud would not tell the two framings apart).
	local toCentre = boxCentre - camera.CFrame.Position
	local along = toCentre:Dot(camera.CFrame.LookVector)
	assert(along > 0, "the upper-body centre is behind the preview camera")
	local missBy = (toCentre - camera.CFrame.LookVector * along).Magnitude
	assert(missBy <= 0.5, ("the camera aims %.2f studs away from the centre of the upper body"):format(missBy))

	-- Head top and torso bottom both project inside the viewport (nothing is cropped), and the upper body fills it.
	local viewSize = camera.ViewportSize
	local top = camera:WorldToViewportPoint(Vector3.new(rootPart.Position.X, topY, rootPart.Position.Z))
	local bottom = camera:WorldToViewportPoint(Vector3.new(rootPart.Position.X, bottomY, rootPart.Position.Z))
	assert(top.Z > 0 and bottom.Z > 0, "character is behind the preview camera")
	assert(top.Y >= 0 and top.Y <= viewSize.Y, ("head top is outside the viewport: y=%.0f of %.0f"):format(top.Y, viewSize.Y))
	assert(bottom.Y >= 0 and bottom.Y <= viewSize.Y, ("torso bottom is outside the viewport: y=%.0f of %.0f"):format(bottom.Y, viewSize.Y))
	local fill = (bottom.Y - top.Y) / viewSize.Y
	assert(fill >= 0.4, ("the upper body is too small in the viewport: it spans %.0f%% of the height"):format(fill * 100))
	assert(fill <= 0.9, ("no headroom left for the wave: the upper body spans %.0f%% of the height"):format(fill * 100))

	-- The idle animation plays on loop (animations load asynchronously, so poll).
	local animator = humanoid:FindFirstChildOfClass("Animator")
	assert(animator, "preview Humanoid has no Animator")
	local looping = waitFor(function()
		for _, track in animator:GetPlayingAnimationTracks() do
			if track.Looped then
				return track
			end
		end
		return nil
	end, 10)
	assert(looping, "no looping animation track is playing (idle missing)")

	-- The wave arm stays in frame (top and sides; hands hanging below the waist may be cut off by a waist-up shot):
	-- loop the wave and project every corner of the arm parts, every frame.
	local waveId = if humanoid.RigType == Enum.HumanoidRigType.R15 then "rbxassetid://507770239" else "rbxassetid://128777973"
	local waveAnimation = Instance.new("Animation")
	waveAnimation.AnimationId = waveId
	local wave = animator:LoadAnimation(waveAnimation)
	wave.Looped = true
	wave.Priority = Enum.AnimationPriority.Action
	assert(
		waitFor(function()
			return wave.Length > 0
		end, 8),
		"the wave animation did not load"
	)
	wave:Play()
	local armParts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and (part.Name:find("Arm") or part.Name:find("Hand")) then
			table.insert(armParts, part)
		end
	end
	assert(#armParts > 0, "found no arm parts to check")
	-- A ViewportFrame's camera reports a 1x1 viewport, so its projections assume a square frame: scale x back by the
	-- frame's real aspect ratio (a no-op if ViewportSize ever is the real size).
	local aspectFix = (viewSize.X / viewSize.Y) / (viewport.AbsoluteSize.X / viewport.AbsoluteSize.Y)
	local minY, widest = math.huge, 0
	local deadline = os.clock() + math.max(3, wave.Length * 1.2)
	while os.clock() < deadline do
		RunService.Heartbeat:Wait()
		for _, part in armParts do
			local half = part.Size / 2
			for _, sign in { Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1), Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1) } do
				local point = camera:WorldToViewportPoint(part.CFrame:PointToWorldSpace(half * sign))
				widest = math.max(widest, math.abs(point.X / viewSize.X - 0.5) * 2 * aspectFix)
				minY = math.min(minY, point.Y / viewSize.Y)
			end
		end
	end
	wave:Stop()
	assert(minY >= 0, ("the waving arm leaves the top of the viewport (y %.2f of the height)"):format(minY))
	assert(widest <= 1, ("the arm leaves the side of the viewport (it reaches %.2f of the half-width)"):format(widest))
elseif CASE == "B" then
	assert(player.Character == nil, "player already has a character; run this in a fresh playtest")

	local hook = clientScript:WaitForChild("TestHook", 10)
	assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook (BindableFunction) missing")

	-- Play as early as possible. Ideally the avatar has not arrived yet (the server needs a few seconds of web calls
	-- to build it); if the tool call lands later, this still covers Play while the preview is animating.
	assert(hook:Invoke("play") == true, "play() should start the Play flow")

	-- Stay for the full avatar wait, so a late avatar (or the wait timing out) is covered too.
	task.wait(AVATAR_TIMEOUT)
	assert(player.Character ~= nil, "player.Character is nil " .. AVATAR_TIMEOUT .. "s after play()")
	assert(errorCount == 0, "errors after play(): " .. table.concat(errorLog, " | "))
elseif CASE == "C" then
	local CharacterPreview = require(clientScript:WaitForChild("CharacterPreview", 10))

	local testViewport = Instance.new("ViewportFrame")
	Instance.new("WorldModel").Parent = testViewport
	testViewport.Parent = playerGui
	testViewport:Destroy()

	local source = Instance.new("Model")
	local ok, result = pcall(CharacterPreview.show, testViewport, source)
	source:Destroy()
	assert(ok, "show threw on a destroyed viewport: " .. tostring(result))
	assert(result == nil, "show should return nil for a destroyed viewport")
	assert(errorCount == 0, "errors while calling show: " .. table.concat(errorLog, " | "))
else
	error("unknown CASE " .. tostring(CASE))
end

logConnection:Disconnect()
return "PASS"
