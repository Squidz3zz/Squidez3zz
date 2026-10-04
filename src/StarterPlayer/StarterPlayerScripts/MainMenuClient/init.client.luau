-- MainMenuClient: shows the main menu at join, wires the Settings/Credits panels and the Play button.
-- The menu lives in ReplicatedStorage (not StarterGui) because the server holds players without a character
-- until PlayPressed; it is cloned into PlayerGui here and destroyed once the player has spawned.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FADE_TIME = 0.4
local CHARACTER_TIMEOUT = 10
local AVATAR_TIMEOUT = 15

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local playPressed = ReplicatedStorage:WaitForChild("PlayPressed")

-- Optional ModuleScripts that sit under this script. A missing or broken module never blocks the menu.
local function loadModule(name)
	local moduleScript = script:FindFirstChild(name)
	if not moduleScript then
		return nil
	end
	local ok, result = pcall(require, moduleScript)
	if not ok then
		warn("MainMenuClient: failed to load " .. name .. ": " .. tostring(result))
		return nil
	end
	return result
end

local MenuCamera = loadModule("MenuCamera")
local ButtonEffects = loadModule("ButtonEffects")
local CharacterPreview = loadModule("CharacterPreview")

local menu = ReplicatedStorage:WaitForChild("MainMenu"):Clone()
local root = menu.Root
local fader = menu.Fader
local panels = {
	Settings = root.SettingsPanel,
	Credits = root.CreditsPanel,
}

local playing = false

local function closePanels()
	for _, panel in panels do
		panel.Visible = false
	end
end

-- Opening a panel closes the other one.
local function openPanel(name)
	assert(panels[name], "unknown panel: " .. tostring(name))
	if playing then
		return
	end
	for panelName, panel in panels do
		panel.Visible = panelName == name
	end
end

local function fadeTo(transparency)
	local tween = TweenService:Create(fader, TweenInfo.new(FADE_TIME), { BackgroundTransparency = transparency })
	tween:Play()
	return tween
end

-- Returns the character, or nil if none arrives within `timeout` seconds.
local function waitForCharacter(timeout)
	if player.Character then
		return player.Character
	end
	local thread = coroutine.running()
	local connection
	local timer = task.delay(timeout, function()
		connection:Disconnect()
		task.spawn(thread, nil)
	end)
	connection = player.CharacterAdded:Connect(function(character)
		connection:Disconnect()
		task.cancel(timer)
		task.spawn(thread, character)
	end)
	return coroutine.yield()
end

local function runPlay()
	closePanels()
	local fadeIn = fadeTo(0)
	if MenuCamera then
		MenuCamera.stop()
	end
	playPressed:FireServer()

	-- A timeout still closes the menu, so a slow or failed spawn never leaves the player stuck on it.
	if not waitForCharacter(CHARACTER_TIMEOUT) then
		warn("MainMenuClient: no character after " .. CHARACTER_TIMEOUT .. "s; closing the menu anyway")
	end
	if fadeIn.PlaybackState == Enum.PlaybackState.Playing then
		fadeIn.Completed:Wait()
	end
	root:Destroy()
	fadeTo(1).Completed:Wait()
	menu:Destroy()
	playerGui:SetAttribute("MenuOpen", false)
end

-- Debounced: returns true if this call started the Play flow, false if it was already running.
local function play()
	if playing then
		return false
	end
	playing = true
	task.spawn(runPlay)
	return true
end

root.Buttons.Play.Activated:Connect(play)
root.Buttons.Settings.Activated:Connect(function()
	openPanel("Settings")
end)
root.Buttons.Credits.Activated:Connect(function()
	openPanel("Credits")
end)
root.SettingsPanel.Close.Activated:Connect(closePanels)
root.CreditsPanel.Close.Activated:Connect(closePanels)

if ButtonEffects then
	local buttons = {
		root.Buttons.Play,
		root.Buttons.Settings,
		root.Buttons.Credits,
		root.SettingsPanel.Close,
		root.CreditsPanel.Close,
	}
	-- Guarded: a failing effect must never keep the menu from opening (and the player from spawning).
	for _, button in buttons do
		local ok, err = pcall(ButtonEffects.attach, button)
		if not ok then
			warn("MainMenuClient: ButtonEffects.attach failed for " .. button.Name .. ": " .. tostring(err))
		end
	end
end

menu.Parent = playerGui
playerGui:SetAttribute("MenuOpen", true)

-- The server builds the avatar a few seconds after join (web calls), so it is shown whenever it arrives.
-- Its own thread, and guarded: a slow or broken preview must never delay the menu or the Play path.
if CharacterPreview then
	task.spawn(function()
		local avatars = ReplicatedStorage:WaitForChild("MenuAvatars", AVATAR_TIMEOUT)
		local avatar = avatars and avatars:WaitForChild(tostring(player.UserId), AVATAR_TIMEOUT)
		-- Play may have destroyed the menu while waiting.
		if not avatar or not root:IsDescendantOf(playerGui) then
			return
		end
		local ok, err = pcall(CharacterPreview.show, root.CharacterView, avatar)
		if not ok then
			warn("MainMenuClient: CharacterPreview.show failed: " .. tostring(err))
		end
	end)
end

if RunService:IsStudio() then
	-- Test hook for tests/menu_client.client.luau (execute_luau cannot reach this script's locals).
	local hook = Instance.new("BindableFunction")
	hook.Name = "TestHook"
	hook.OnInvoke = function(action, arg)
		if action == "openPanel" then
			openPanel(arg)
		elseif action == "closePanels" then
			closePanels()
		elseif action == "play" then
			return play()
		else
			error("TestHook: unknown action " .. tostring(action))
		end
	end
	hook.Parent = script
end
