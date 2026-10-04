-- MainMenuClient: shows the main menu at join, wires the Settings/Credits panels and the Play button.
-- The menu lives in ReplicatedStorage (not StarterGui) because the server holds players without a character
-- until PlayPressed; it is cloned into PlayerGui here and destroyed once the player has spawned.
--
-- UI names this script depends on (all under ReplicatedStorage.MainMenu). Restyle anything, but keep these names:
--   Root
--   Root.Buttons.Play, Root.Buttons.Settings, Root.Buttons.Credits
--   Root.SettingsPanel (with Close and Slider), Root.CreditsPanel (with Close)
--   Root.CharacterView
--   Fader
-- Root.Title is never looked up, so it can be renamed or restyled freely.
-- If the UI is broken or never appears, setup warns and the player is spawned straight away instead: nobody
-- spawns until PlayPressed (CharacterAutoLoads is off), so a menu that cannot open must not trap the player.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local FADE_TIME = 0.4
local MENU_TIMEOUT = 10
local CHARACTER_TIMEOUT = 10
local AVATAR_TIMEOUT = 15
local AVATAR_PARTS_TIMEOUT = 10
local AVATAR_DESCENDANTS_TIMEOUT = 5

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
local VolumeSlider = loadModule("VolumeSlider")

-- Set by setupMenu.
local menu, root, fader, panels

local playing = false

local function closePanels()
	for _, panel in panels do
		panel.Visible = false
	end
	-- A hidden button may never get its MouseLeave / touch-up, so reset the Close buttons here or they would
	-- reopen still popped. Guarded: a missing or broken ButtonEffects must never stop the panels closing.
	if ButtonEffects then
		for _, panel in panels do
			pcall(ButtonEffects.setState, panel.Close, "idle")
		end
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
	GuiService.SelectedObject = nil
	local fadeIn = fadeTo(0)
	-- Guarded: a throw here must never stop the Play press from reaching the server.
	if MenuCamera then
		local ok, err = pcall(MenuCamera.stop)
		if not ok then
			warn("MainMenuClient: MenuCamera.stop failed: " .. tostring(err))
		end
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

-- Clones the menu, wires it up and shows it. Throws if the UI tree is not what this script expects.
local function setupMenu()
	local template = ReplicatedStorage:WaitForChild("MainMenu", MENU_TIMEOUT)
	assert(template, "ReplicatedStorage.MainMenu did not appear within " .. MENU_TIMEOUT .. "s")
	menu = template:Clone()
	root = menu.Root
	fader = menu.Fader
	panels = {
		Settings = root.SettingsPanel,
		Credits = root.CreditsPanel,
	}

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

	-- Guarded like ButtonEffects: a broken slider must never keep the menu from opening.
	if VolumeSlider then
		local ok, err = pcall(function()
			VolumeSlider.attach(root.SettingsPanel.Slider, SoundService.Music)
		end)
		if not ok then
			warn("MainMenuClient: VolumeSlider.attach failed: " .. tostring(err))
		end
	end

	menu.Parent = playerGui
	playerGui:SetAttribute("MenuOpen", true)
end

local setupOk, setupError = pcall(setupMenu)
if not setupOk then
	warn("MainMenuClient: the menu could not be set up (" .. tostring(setupError) .. "); spawning without it")
	-- setupMenu parents the menu last, but never leave a half-built one on screen.
	if menu then
		menu:Destroy()
	end
	playerGui:SetAttribute("MenuOpen", false)
	playPressed:FireServer()
	return
end

-- Gamepad players have no cursor, so start them on Play (ButtonEffects pops it, so it shows as focused).
-- runPlay clears the selection again.
if UserInputService.GamepadEnabled then
	GuiService.SelectedObject = root.Buttons.Play
end

if MenuCamera then
	local ok, err = pcall(MenuCamera.start)
	if not ok then
		warn("MainMenuClient: MenuCamera.start failed: " .. tostring(err))
	end
end

-- Waits until the client copy of `model` has as many descendants as the server counted just before it parented the
-- model (the DescendantCount attribute), i.e. every part has replicated, or until `timeout` seconds pass.
-- A timeout (or a missing attribute) just returns: a slightly incomplete avatar beats none.
local function waitForDescendants(model, timeout)
	local expected = model:GetAttribute("DescendantCount")
	if type(expected) ~= "number" then
		return true
	end
	local deadline = os.clock() + timeout
	while #model:GetDescendants() < expected do
		if os.clock() >= deadline then
			return false
		end
		-- Play may have destroyed the menu while waiting.
		if not root:IsDescendantOf(playerGui) then
			return true
		end
		task.wait(0.1)
	end
	return true
end

-- The server builds the avatar a few seconds after join (web calls), so it is shown whenever it arrives.
-- Its own thread, and guarded: a slow or broken preview must never delay the menu or the Play path.
if CharacterPreview then
	task.spawn(function()
		local avatars = ReplicatedStorage:WaitForChild("MenuAvatars", AVATAR_TIMEOUT)
		local avatar = avatars and avatars:WaitForChild(tostring(player.UserId), AVATAR_TIMEOUT)
		if not avatar then
			return
		end
		-- The model can appear before its children have replicated; show() needs both of these.
		if
			not avatar:WaitForChild("Humanoid", AVATAR_PARTS_TIMEOUT)
			or not avatar:WaitForChild("HumanoidRootPart", AVATAR_PARTS_TIMEOUT)
		then
			warn("MainMenuClient: avatar never got its Humanoid / HumanoidRootPart; skipping the preview")
			return
		end
		-- Humanoid and root part are not enough: show() clones the whole model, so wait for the rest of it too.
		local waited, complete = pcall(waitForDescendants, avatar, AVATAR_DESCENDANTS_TIMEOUT)
		if not waited then
			warn("MainMenuClient: waiting for the avatar's parts failed: " .. tostring(complete))
		elseif not complete then
			warn("MainMenuClient: avatar still incomplete after " .. AVATAR_DESCENDANTS_TIMEOUT .. "s; showing it anyway")
		end
		-- Play may have destroyed the menu while waiting.
		if not root:IsDescendantOf(playerGui) then
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
