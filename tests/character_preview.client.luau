-- Run in the Client datamodel of a FRESH playtest, with the main menu still open. Pick the case with CASE:
--   "A": the player's avatar shows up in CharacterView (needs the server to have built MenuAvatars[UserId], a few seconds
--        after join): Humanoid present, no Animate, PreviewCamera set and framing the whole body, idle track looping.
--   "B": pressing Play immediately (before the avatar arrives) causes no errors and still spawns the player.
--        Uses the Studio-only MainMenuClient.TestHook, because execute_luau cannot reach the script's locals.
--   "C": CharacterPreview.show returns nil, without error, when the viewport has already been destroyed.
--        Requires the ModuleScript directly (a separate copy of the module, so it only touches the Instances passed in).
local CASE = "A"

local LogService = game:GetService("LogService")
local Players = game:GetService("Players")

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

	-- The whole body must be inside the viewport: project the top and bottom of the bounding box.
	local cframe, size = model:GetBoundingBox()
	local viewSize = camera.ViewportSize
	local top = camera:WorldToViewportPoint(cframe.Position + Vector3.new(0, size.Y / 2, 0))
	local bottom = camera:WorldToViewportPoint(cframe.Position - Vector3.new(0, size.Y / 2, 0))
	assert(top.Z > 0 and bottom.Z > 0, "character is behind the preview camera")
	assert(top.Y >= 0 and bottom.Y <= viewSize.Y, ("character is cropped: top y=%.0f bottom y=%.0f of %.0f"):format(top.Y, bottom.Y, viewSize.Y))
	assert(bottom.Y - top.Y > viewSize.Y * 0.5, "character is too small in the viewport")

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
