-- Run in the Client datamodel of a FRESH playtest, with the main menu still open. Pick the case with CASE:
--   "A": the player's avatar shows up in CharacterView (needs the server to have built MenuAvatars[UserId], a few seconds
--        after join): Humanoid present, no Animate, PreviewCamera set and showing the avatar from the waist up (the bottom
--        edge of the view just under the bottom of the torso, the legs cut off, the head inside the view, the upper body
--        at least 0.55 of the view's height), idle track looping, the head staying fully in frame while the avatar
--        waves, and the waving hand staying in frame (give or take 3%).
--   "B": pressing Play immediately (before the avatar arrives) causes no errors and still spawns the player.
--        Uses the Studio-only MainMenuClient.TestHook, because execute_luau cannot reach the script's locals.
--   "C": CharacterPreview.show returns nil, without error, when the viewport has already been destroyed.
--        Requires the ModuleScript directly (a separate copy of the module, so it only touches the Instances passed in).
--   "D": the avatar waves again every WAVE_INTERVAL (6 s) while the menu is showing. Over 14 s the wave plays at least
--        twice on the real clone's Animator (counted as rising edges of "the wave is among GetPlayingAnimationTracks",
--        polled every frame), always as the same AnimationTrack (reused, not loaded anew), never two at once, and
--        replays start about 6 s apart.
--   "E": after Invoke("play") the repeat loop ends quietly: once the avatar is gone, and for a full WAVE_INTERVAL
--        after (so the loop wakes at least once with the clone destroyed), no error and no CharacterPreview warning is logged.
local CASE = "A"

local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local AVATAR_TIMEOUT = 15
local WAVE_INTERVAL = 6 -- mirrors CharacterPreview.WAVE_INTERVAL (a local of that module)

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

-- Counts MessageError entries from now on, and keeps the warnings that come from CharacterPreview.
local errorCount = 0
local errorLog = {}
local previewWarnings = {}
local logConnection = LogService.MessageOut:Connect(function(message, messageType)
	if messageType == Enum.MessageType.MessageError then
		errorCount += 1
		table.insert(errorLog, message)
	elseif messageType == Enum.MessageType.MessageWarning and message:find("CharacterPreview", 1, true) then
		table.insert(previewWarnings, message)
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

	-- A ViewportFrame's camera reports a 1x1 viewport, so its projections assume a square frame: scale x back by the
	-- frame's real aspect ratio (a no-op if ViewportSize ever is the real size). project() gives where a world point
	-- lands in the view: x from -1 (left edge) to 1 (right edge), y from -1 (top edge) to 1 (bottom edge).
	local viewSize = camera.ViewportSize
	local aspectFix = (viewSize.X / viewSize.Y) / (viewport.AbsoluteSize.X / viewport.AbsoluteSize.Y)
	local function project(point)
		local p = camera:WorldToViewportPoint(point)
		assert(p.Z > 0, "a point of the character is behind the preview camera")
		return (p.X / viewSize.X - 0.5) * 2 * aspectFix, (p.Y / viewSize.Y - 0.5) * 2
	end
	local rootX, rootZ = rootPart.Position.X, rootPart.Position.Z

	-- Waist up: the bottom of the torso is inside the view, close to its bottom edge (at most 15% of the height above
	-- it), and everything below that is cut off: the lowest point of the avatar is below the bottom edge.
	local _, torsoBottomY = project(Vector3.new(rootX, bottomY, rootZ))
	assert(torsoBottomY <= 1, ("the bottom of the torso is below the view (y %.2f, 1 is the bottom edge)"):format(torsoBottomY))
	assert(torsoBottomY >= 0.7, ("the bottom of the view is too far under the waist: the torso ends at y %.2f, it must be 0.7 to 1"):format(torsoBottomY))
	local boxCFrame, boxSize = model:GetBoundingBox()
	local _, legsY = project(Vector3.new(rootX, boxCFrame.Position.Y - boxSize.Y / 2, rootZ))
	assert(legsY > 1, ("the legs are not cropped: the lowest point of the avatar is at y %.2f, it must be below the bottom edge (above 1)"):format(legsY))

	-- The head is inside the view, and the upper body fills at least 0.55 of its height (the old whole-body shot gave 0.43).
	local centreX, headTopY = project(Vector3.new(rootX, topY, rootZ))
	assert(headTopY >= -1, ("the top of the head is above the view (y %.2f, -1 is the top edge)"):format(headTopY))
	local fill = (torsoBottomY - headTopY) / 2
	assert(fill >= 0.55, ("the upper body is too small in the view: it fills %.0f%% of the height"):format(fill * 100))
	assert(fill <= 0.85, ("no room left for the wave: the upper body fills %.0f%% of the height"):format(fill * 100))
	assert(math.abs(centreX) <= 0.5, ("the avatar is off-centre in the view (x %.2f)"):format(centreX))

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

	-- The wave: loop it (with the idle already playing, so the pose is the real one) and project every corner of the head
	-- and of the arm parts, every frame. The head must stay fully in the view. The raised hand may clip a little at the
	-- edge (3% of the half-width or half-height is accepted); the tuning leaves it inside, see CharacterPreview.
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
	local corners = {
		Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1),
		Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1),
	}
	local headWidest, headHighest = 0, math.huge
	local armWidest, armHighest = 0, math.huge
	local function track(part, widest, highest)
		local half = part.Size / 2
		for _, sign in corners do
			local x, y = project(part.CFrame:PointToWorldSpace(half * sign))
			widest, highest = math.max(widest, math.abs(x)), math.min(highest, y)
		end
		return widest, highest
	end
	local deadline = os.clock() + math.max(3, wave.Length * 1.2)
	while os.clock() < deadline do
		RunService.Heartbeat:Wait()
		headWidest, headHighest = track(head, headWidest, headHighest)
		for _, part in armParts do
			armWidest, armHighest = track(part, armWidest, armHighest)
		end
	end
	wave:Stop()
	assert(headWidest <= 1 and headHighest >= -1, ("the head leaves the view during the wave (x reaches %.2f, top at y %.2f)"):format(headWidest, headHighest))
	assert(armWidest <= 1.03, ("the waving arm leaves the side of the view (it reaches %.2f of the half-width)"):format(armWidest))
	assert(armHighest >= -1.03, ("the waving hand leaves the top of the view (y %.2f, -1 is the top edge)"):format(armHighest))
	print(("character_preview A: torso bottom y %.2f, legs y %.2f, head top y %.2f, fill %.0f%%; wave: head %.2f wide / top y %.2f, arm %.2f wide / top y %.2f"):format(torsoBottomY, legsY, headTopY, fill * 100, headWidest, headHighest, armWidest, armHighest))
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
elseif CASE == "D" then
	assert(player.Character == nil, "player already has a character; run this in a fresh playtest")

	local model = waitFor(function()
		return worldModel:FindFirstChildOfClass("Model")
	end, AVATAR_TIMEOUT)
	assert(model, "no model in WorldModel")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "preview model has no Humanoid")
	local animator = humanoid:FindFirstChildOfClass("Animator")
	assert(animator, "preview Humanoid has no Animator")
	local waveId = if humanoid.RigType == Enum.HumanoidRigType.R15 then "507770239" else "128777973"

	-- The wave track playing on the clone's Animator (nil if none), and how many wave tracks are playing. The engine
	-- rewrites an Animation's AnimationId ("rbxassetid://N" reads back as "http://www.roblox.com/asset/?id=N"), so compare
	-- the number.
	local function playingWave()
		local found, count = nil, 0
		for _, track in animator:GetPlayingAnimationTracks() do
			if track.Animation and track.Animation.AnimationId:match("%d+$") == waveId then
				found, count = track, count + 1
			end
		end
		return found, count
	end

	-- Watch for 14 s from now (the avatar has only just appeared) and note each time the wave starts playing. A wave that
	-- is already playing at the first check counts as one start.
	local OBSERVE = 14
	local starts, tracks, trackCount, mostAtOnce = {}, {}, 0, 0
	local was = false
	local t0 = os.clock()
	while os.clock() - t0 < OBSERVE do
		local track, count = playingWave()
		mostAtOnce = math.max(mostAtOnce, count)
		if track and not was then
			table.insert(starts, os.clock() - t0)
			if not tracks[track] then
				tracks[track] = true
				trackCount += 1
			end
		end
		was = track ~= nil
		RunService.Heartbeat:Wait()
	end

	local startsText = {}
	for _, at in starts do
		table.insert(startsText, ("%.1f"):format(at))
	end
	startsText = table.concat(startsText, ", ")
	assert(#starts >= 2, ("the wave should play at least twice in %ds, it played %d time(s) (starts at: %s)"):format(OBSERVE, #starts, startsText))
	assert(trackCount == 1, ("the wave should be one reused AnimationTrack, saw %d different ones"):format(trackCount))
	assert(mostAtOnce == 1, ("never more than one wave track at a time, saw %d"):format(mostAtOnce))
	for i = 2, #starts do
		local gap = starts[i] - starts[i - 1]
		-- The first start can be late (the animation loads asynchronously), which shortens the gap after it.
		local lowest = if i == 2 then 1 else WAVE_INTERVAL - 1
		assert(gap >= lowest and gap <= WAVE_INTERVAL + 1, ("waves %d and %d started %.1fs apart, expected about %ds (starts at: %s)"):format(i - 1, i, gap, WAVE_INTERVAL, startsText))
	end
	assert(errorCount == 0, "errors while the avatar waved: " .. table.concat(errorLog, " | "))
	print(("character_preview D: %d waves in %ds, starts at %s s, one track"):format(#starts, OBSERVE, startsText))
elseif CASE == "E" then
	assert(player.Character == nil, "player already has a character; run this in a fresh playtest")

	local hook = clientScript:WaitForChild("TestHook", 10)
	assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook (BindableFunction) missing")
	local model = waitFor(function()
		return worldModel:FindFirstChildOfClass("Model")
	end, AVATAR_TIMEOUT)
	assert(model, "no model in WorldModel")

	-- The avatar is on screen and its repeat loop is running when Play is pressed.
	task.wait(1)
	assert(hook:Invoke("play") == true, "play() should start the Play flow")
	assert(
		waitFor(function()
			return not model:IsDescendantOf(game)
		end, 20),
		"the preview avatar was still in the game 20s after play()"
	)

	-- The loop wakes every WAVE_INTERVAL: stay a full interval (plus slack) after the clone is gone, so it wakes at
	-- least once with nothing left to wave, and must end without an error or a warning.
	task.wait(WAVE_INTERVAL + 1)
	assert(player.Character ~= nil, "player.Character is nil after play()")
	assert(errorCount == 0, "errors after play(): " .. table.concat(errorLog, " | "))
	assert(#previewWarnings == 0, "CharacterPreview warned after play(): " .. table.concat(previewWarnings, " | "))
else
	error("unknown CASE " .. tostring(CASE))
end

logConnection:Disconnect()
return "PASS"
