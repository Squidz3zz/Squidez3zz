-- Run in a playtest, after tests/fire_play.client.luau (so the player has a character). Three calls, in this order:
--   A-1  Client, CASE = "A-1": arms the check. It turns Screen Effects on, pins the camera (Scriptable, set every frame at the
--        Camera render priority, before BoomClient's shake) and, for each boom BoomEvent brings, records as PlayerGui attributes:
--        how long until a "Boom" Attachment at that spot was in workspace.Terrain (polled every frame for 0.5 s), how many
--        ParticleEmitters and Sounds it held and how many of those Sounds were playing in SoundService.SFX, and over the next
--        0.6 s the largest angle between the camera and its pinned CFrame (read after the shake). 0.6 s after the first boom it
--        turns Screen Effects off (MenuSetting_ScreenEffects = false) for the second.
--   B    Server: tests/boom.server.luau, CASE = "B" (two booms 1 s apart, near the character)
--   A-2  Client, CASE = "A-2": the first boom's attachment came within 0.5 s with 7 ParticleEmitters and 9 Sounds, all playing in
--        SFX, and turned the camera more than 0.5 degrees; the second (Screen Effects off) has its attachment too but did not move
--        the camera; 13 s after each boom its attachment is gone. Puts the camera and the setting back.
local CASE = "A-1"
local FIND_WINDOW = 0.5
local SHAKE_WINDOW = 0.6
local GONE_AFTER = 13

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera
local SETTING = "MenuSetting_ScreenEffects"
local PIN, READ = "BoomTestPin", "BoomTestRead"

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

local function clear()
	for name in playerGui:GetAttributes() do
		if string.sub(name, 1, 3) == "BT_" then
			playerGui:SetAttribute(name, nil)
		end
	end
end

local function boomAt(position: Vector3): Attachment?
	for _, child in workspace.Terrain:GetChildren() do
		if child.Name == "Boom" and child:IsA("Attachment") and (child.WorldPosition - position).Magnitude < 0.01 then
			return child
		end
	end
	return nil
end

if CASE == "A-1" then
	clear()
	RunService:UnbindFromRenderStep(PIN)
	RunService:UnbindFromRenderStep(READ)
	local boomEvent = ReplicatedStorage:WaitForChild("BoomEvent", 10)
	assert(boomEvent and boomEvent:IsA("RemoteEvent"), "ReplicatedStorage.BoomEvent (RemoteEvent) missing")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	assert(root, "no character: run tests/fire_play.client.luau first")
	local sfx = SoundService:FindFirstChild("SFX")
	assert(sfx and sfx:IsA("SoundGroup"), "SoundService.SFX missing")

	local previous = player:GetAttribute(SETTING)
	if previous ~= nil then
		playerGui:SetAttribute("BT_PreviousSetting", previous)
	end
	player:SetAttribute(SETTING, true)

	local pinned = CFrame.lookAt(root.Position + Vector3.new(0, 8, 12), root.Position)
	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(PIN, Enum.RenderPriority.Camera.Value, function()
		camera.CFrame = pinned
	end)
	local windows = {}
	RunService:BindToRenderStep(READ, Enum.RenderPriority.Camera.Value + 2, function()
		local _, angle = pinned:ToObjectSpace(camera.CFrame):ToAxisAngle()
		angle = math.deg(math.abs(angle))
		for n, window in windows do
			if os.clock() - window.arrived <= SHAKE_WINDOW then
				window.max = math.max(window.max, angle)
			elseif not window.done then
				window.done = true
				playerGui:SetAttribute("BT_" .. n .. "_MaxAngle", window.max)
				if n == 1 then
					player:SetAttribute(SETTING, false)
				end
			end
		end
	end)

	local count = 0
	local connection
	connection = boomEvent.OnClientEvent:Connect(function(position)
		count += 1
		local n = count
		if n >= 2 then
			connection:Disconnect()
		end
		local arrived = os.clock()
		windows[n] = { arrived = arrived, max = 0 }
		local key = "BT_" .. n .. "_"
		playerGui:SetAttribute(key .. "Arrived", arrived)
		playerGui:SetAttribute(key .. "Position", position)
		local boom = boomAt(position)
		while not boom and os.clock() - arrived <= FIND_WINDOW do
			RunService.RenderStepped:Wait()
			boom = boomAt(position)
		end
		if not boom then
			playerGui:SetAttribute(key .. "Found", -1)
			return
		end
		local emitters, sounds, playing = 0, 0, 0
		for _, thing in boom:GetChildren() do
			if thing:IsA("ParticleEmitter") then
				emitters += 1
			elseif thing:IsA("Sound") then
				sounds += 1
				if thing.IsPlaying and thing.SoundGroup == sfx then
					playing += 1
				end
			end
		end
		playerGui:SetAttribute(key .. "Found", os.clock() - arrived)
		playerGui:SetAttribute(key .. "Emitters", emitters)
		playerGui:SetAttribute(key .. "Sounds", sounds)
		playerGui:SetAttribute(key .. "Playing", playing)
	end)
	return "PASS boom A-1 (armed: now run CASE B of tests/boom.server.luau on the Server, then A-2)"
elseif CASE == "A-2" then
	local function restore()
		RunService:UnbindFromRenderStep(PIN)
		RunService:UnbindFromRenderStep(READ)
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		player:SetAttribute(SETTING, playerGui:GetAttribute("BT_PreviousSetting"))
	end
	local ok, result = pcall(function()
		assert(waitFor(function()
			return playerGui:GetAttribute("BT_2_MaxAngle") ~= nil and playerGui:GetAttribute("BT_2_Found") ~= nil
		end, 15), "A-1 did not record two booms: was it run, then CASE B on the Server?")
		local report = {}
		for n = 1, 2 do
			local key = "BT_" .. n .. "_"
			local found = playerGui:GetAttribute(key .. "Found")
			assert(found >= 0, ("boom %d: no Boom attachment at its position within %.1f s"):format(n, FIND_WINDOW))
			assert(playerGui:GetAttribute(key .. "Emitters") == 7, ("boom %d: %d ParticleEmitters, expected 7"):format(n, playerGui:GetAttribute(key .. "Emitters")))
			assert(playerGui:GetAttribute(key .. "Sounds") == 9, ("boom %d: %d Sounds, expected 9"):format(n, playerGui:GetAttribute(key .. "Sounds")))
			table.insert(report, ("boom %d found after %.3f s, max angle %.2f deg"):format(n, found, playerGui:GetAttribute(key .. "MaxAngle")))
		end
		local playing = playerGui:GetAttribute("BT_1_Playing")
		assert(playing == 9, ("boom 1: %d of its 9 Sounds were playing in SFX"):format(playing))
		local shaken = playerGui:GetAttribute("BT_1_MaxAngle")
		assert(shaken > 0.5, ("boom 1 turned the camera at most %.3f degrees, expected more than 0.5"):format(shaken))
		local still = playerGui:GetAttribute("BT_2_MaxAngle")
		assert(still < 0.01, ("with Screen Effects off, boom 2 still turned the camera %.3f degrees"):format(still))
		for n = 1, 2 do
			local key = "BT_" .. n .. "_"
			local left = playerGui:GetAttribute(key .. "Arrived") + GONE_AFTER - os.clock()
			if left > 0 then
				task.wait(left)
			end
			assert(boomAt(playerGui:GetAttribute(key .. "Position")) == nil, ("boom %d's attachment is still there %d s later"):format(n, GONE_AFTER))
		end
		return table.concat(report, "; ")
	end)
	restore()
	clear()
	assert(ok, result)
	return "PASS boom A-2 (" .. result .. "; both attachments gone after " .. GONE_AFTER .. " s)"
end
error("unknown CASE " .. tostring(CASE))
