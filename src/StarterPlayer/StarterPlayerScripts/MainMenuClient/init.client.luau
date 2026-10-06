-- MainMenuClient: shows the main menu at join and wires its Play, Settings and Credits buttons.
-- The menu lives in ReplicatedStorage (not StarterGui) because the server holds players without a character
-- until PlayPressed; it is cloned into PlayerGui here and destroyed once the player has spawned.
-- It is three ScreenGuis: MainMenu stays in the phone's safe area, while the Vignette and the Fader are full-screen
-- overlays of their own (ScreenInsets None) so they reach the notch strips and rounded corners.
-- Settings and Credits are 3D rooms: their buttons ask SceneDirector (a module under this script) to fade and cut there.
-- The Credits room shows the developer's avatar (built by MenuServer in ReplicatedStorage.CreditAvatars) and the player's own.
-- While either room shows, RoomLighting switches the outdoor light off (client-only), so the room already looks right on the
-- first frames after the cut (Roblox lights it like open ground until its lighting catches up). Leaving the room and Play
-- put the normal lighting back, so gameplay never sees it.
-- At join the factory loading screen (ReplicatedFirst.LoadingScreen) preloads the menu's assets first: setup waits for its
-- LoadingDone attribute before it shows anything, and a missing, disabled or broken loading screen is simply not waited for.
-- The buttons make sounds (ButtonSounds, on the Sound Effects slider): hover when the pointer enters one, confirm when one is
-- clicked, and the play sound for PLAY. Every call is in pcall and none of them yields, so a missing or failing sound module
-- never touches the menu or Play, and Play's fade does not cut the play sound (it lives in SoundService).
-- The menu has background music (MenuAudio, on the Music slider): one looping track per scene, started when the menu opens,
-- crossfaded by SceneDirector's onSceneChanged callback and faded out by runPlay. Same rules: pcall'd, never yields.
--
-- UI names this script depends on (three ScreenGuis under ReplicatedStorage). Restyle anything, but keep these names:
--   MainMenu
--     Root
--     Root.Buttons.Play, Root.Buttons.Settings, Root.Buttons.Credits
--     Root.CharacterView
--     Back
--   MainMenuVignette
--     Vignette
--   MainMenuFader
--     Fader
-- Root.Title is never looked up, so it can be renamed or restyled freely.
-- If the UI is broken or never appears, setup warns and the player is spawned straight away instead: nobody
-- spawns until PlayPressed (CharacterAutoLoads is off), so a menu that cannot open must not trap the player.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local FADE_TIME = 0.4
-- The loading screen (ReplicatedFirst.LoadingScreen) hands over after LOADING_MAX_SECONDS at the latest, or after
-- LOADING_MIN_SECONDS if that is longer (it never ends before its minimum). These are the values in
-- ReplicatedFirst.MenuAssets; the ones here are only used if that module cannot be read. The menu waits for the longer of
-- the two, and a few seconds more, for it.
local LOADING_MIN_SECONDS = 2
local LOADING_MAX_SECONDS = 20
local LOADING_WAIT_EXTRA = 5
-- How long the loading screen has to remove itself once the menu is open (its fade out takes 0.4s) before this script
-- destroys it.
local LOADING_CLEANUP_DELAY = 1.5
local MENU_TIMEOUT = 10
local CHARACTER_TIMEOUT = 10
local AVATAR_TIMEOUT = 15
local AVATAR_PARTS_TIMEOUT = 10
local AVATAR_DESCENDANTS_TIMEOUT = 5
local CREDITS_AVATAR_WAIT = 20
local CREDITS_AVATAR_POLL = 0.25

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

-- MenuCamera requires MenuSettings too (a broken MenuSettings warns here, at join, and takes MenuCamera down with it).
local MenuSettings = loadModule("MenuSettings")
local MenuCamera = loadModule("MenuCamera")
local ButtonEffects = loadModule("ButtonEffects")
local CharacterPreview = loadModule("CharacterPreview")
-- The button sound effects. Without it the menu is silent, but nothing else is affected.
local ButtonSounds = loadModule("ButtonSounds")
-- The scene music. Without it the menu has no music, but nothing else is affected.
local MenuAudio = loadModule("MenuAudio")
-- Runs the Settings and Credits rooms: without it their buttons do nothing.
local SceneDirector = loadModule("SceneDirector")
-- The Settings room's board. Without it the room is empty, but the menu and Play are not affected.
local SettingsBoard = loadModule("SettingsBoard")
-- The Credits room's avatars. Without it that room is empty, but the menu and Play are not affected.
local CreditsRoom = loadModule("CreditsRoom")
-- The rooms' lighting profile (outdoor light off while a room shows). Without it the rooms show the game's normal lighting
-- for the first few seconds after the cut, but nothing else is affected.
local RoomLighting = loadModule("RoomLighting")

-- Set by setupMenu: the three cloned ScreenGuis, and the frames this script uses from them.
local menu, vignetteGui, faderGui
local root, vignette, fader, back

-- Bumped whenever the Credits scene is entered, exited or disposed. A late avatar placement stops when it changes.
local creditsVisit = 0

-- Whether `model` has everything CharacterPreview needs: its Humanoid and root part, and as many descendants as the
-- server counted just before it parented the model (the DescendantCount attribute). Never waits; the avatar thread
-- below waits for the same things, and the Credits scene just goes without an avatar that is not there yet.
local function avatarIsReady(model)
	if not (model:FindFirstChildOfClass("Humanoid") and model:FindFirstChild("HumanoidRootPart")) then
		return false
	end
	local expected = model:GetAttribute("DescendantCount")
	return type(expected) ~= "number" or #model:GetDescendants() >= expected
end

-- The Credits room's source avatars that are there and complete right now: { Developer = Model?, Viewer = Model? }.
local function readyCreditSources()
	local sources = {}
	local creditAvatars = ReplicatedStorage:FindFirstChild("CreditAvatars")
	local developer = creditAvatars and creditAvatars:FindFirstChild("Developer")
	if developer and avatarIsReady(developer) then
		sources.Developer = developer
	end
	local menuAvatars = ReplicatedStorage:FindFirstChild("MenuAvatars")
	local viewer = menuAvatars and menuAvatars:FindFirstChild(tostring(player.UserId))
	if viewer and avatarIsReady(viewer) then
		sources.Viewer = viewer
	end
	return sources
end

local playing = false

-- Plays one of ButtonSounds' sounds ("confirm" or "playSelect") for a click. Never yields, never throws, and is silent once
-- Play has started (the menu is on its way out).
local function playSfx(soundName)
	if ButtonSounds and not playing then
		pcall(ButtonSounds[soundName])
	end
end

-- Settings and Credits are rooms run by SceneDirector. Without it (or once Play has started) the buttons do nothing.
-- Returns true if a transition started. Guarded: a failing scene change must never touch the menu or the Play path.
local function goToScene(name)
	if playing or not SceneDirector then
		return false
	end
	local ok, result = pcall(SceneDirector.goTo, name)
	if not ok then
		warn("MainMenuClient: SceneDirector.goTo(" .. tostring(name) .. ") failed: " .. tostring(result))
		return false
	end
	return result == true
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

-- The rooms sit under the map and nobody sees them after Play, but their emitters and lights would keep running on
-- this client. Switches them off (client-side only). Never yields.
local function quietRooms()
	for _, roomName in { "SettingsRoom", "CreditsRoom" } do
		local room = workspace:FindFirstChild(roomName)
		if room then
			for _, item in room:GetDescendants() do
				if item:IsA("ParticleEmitter") or item:IsA("Light") then
					item.Enabled = false
				end
			end
		end
	end
end

-- Puts the room lighting profile on, or the normal lighting back (see RoomLighting). Neither yields, both are safe to repeat,
-- and neither throws: a failing one is warned about and must never stop a room's own hook, the fade or Play.
local function applyRoomLighting()
	if RoomLighting then
		local ok, err = pcall(RoomLighting.apply)
		if not ok then
			warn("MainMenuClient: RoomLighting.apply failed: " .. tostring(err))
		end
	end
end

local function restoreRoomLighting()
	if RoomLighting then
		local ok, err = pcall(RoomLighting.restore)
		if not ok then
			warn("MainMenuClient: RoomLighting.restore failed: " .. tostring(err))
		end
	end
end

-- Destroys the clones of the menu's three ScreenGuis (MainMenu, MainMenuVignette, MainMenuFader). Never yields. One that
-- was never cloned (a setup that failed half way) is still nil and is skipped by the loop.
local function destroyMenuGuis()
	for _, gui in { menu, vignetteGui, faderGui } do
		gui:Destroy()
	end
end

local function runPlay()
	GuiService.SelectedObject = nil
	-- Play can be pressed in the middle of a scene change. stop() ends it (it never yields) before the fade below
	-- starts, so the transition can no longer touch the Fader, Root, Back or the camera.
	-- Guarded: a throw here must never stop the Play press from reaching the server.
	if SceneDirector then
		local ok, err = pcall(SceneDirector.stop)
		if not ok then
			warn("MainMenuClient: SceneDirector.stop failed: " .. tostring(err))
		end
	end
	-- Gameplay always gets the normal lighting, even if the room's exit hook (stop() runs it detached) has not run yet.
	-- Never yields. Guarded like the above.
	restoreRoomLighting()
	-- The music fades out over the screen fade below and is gone after it. Never yields, and leaves the button sounds
	-- alone (the play sound keeps going). Guarded like the above.
	if MenuAudio then
		local ok, err = pcall(MenuAudio.stop)
		if not ok then
			warn("MainMenuClient: MenuAudio.stop failed: " .. tostring(err))
		end
	end
	-- Guarded like the above.
	local quietOk, quietErr = pcall(quietRooms)
	if not quietOk then
		warn("MainMenuClient: could not switch the rooms' effects off: " .. tostring(quietErr))
	end
	-- Whatever scene the player was in, Play ends on the main menu's own screen.
	root.Visible = true
	back.Visible = false
	local fadeIn = fadeTo(0)
	-- Guarded like the above.
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
	-- The Vignette is in a ScreenGui of its own, so destroying Root does not touch it and it would otherwise stay on
	-- screen through the fade out.
	vignette.Visible = false
	fadeTo(1).Completed:Wait()
	destroyMenuGuis()
	playerGui:SetAttribute("MenuOpen", false)
	playerGui:SetAttribute("MenuScene", nil)
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

-- Waits for one of the three ScreenGui templates in ReplicatedStorage. Throws if it does not appear.
local function waitForTemplate(name)
	local template = ReplicatedStorage:WaitForChild(name, MENU_TIMEOUT)
	assert(template, "ReplicatedStorage." .. name .. " did not appear within " .. MENU_TIMEOUT .. "s")
	return template
end

-- Waits for the loading screen to hand over (it sets the PlayerGui attribute LoadingDone once it has faded to black), so
-- the menu opens under the black and not under the loading screen. Returns at once if there is no loading screen (or it is
-- disabled), and carries on with a warning if it never hands over. Never throws.
local function waitForLoading()
	local loadingScript = ReplicatedFirst:FindFirstChild("LoadingScreen")
	if not loadingScript or (loadingScript:IsA("BaseScript") and loadingScript.Disabled) then
		return
	end
	if playerGui:GetAttribute("LoadingDone") == true then
		return
	end
	local minimum, limit = LOADING_MIN_SECONDS, LOADING_MAX_SECONDS
	local assetsModule = ReplicatedFirst:FindFirstChild("MenuAssets")
	if assetsModule then
		local ok, assets = pcall(require, assetsModule)
		if ok and type(assets) == "table" then
			if type(assets.LOADING_MIN_SECONDS) == "number" then
				minimum = assets.LOADING_MIN_SECONDS
			end
			if type(assets.LOADING_MAX_SECONDS) == "number" then
				limit = assets.LOADING_MAX_SECONDS
			end
		end
	end
	-- A MIN set above MAX still makes the loading screen stay MIN seconds, so the menu must not give up before that.
	limit = math.max(minimum, limit) + LOADING_WAIT_EXTRA

	local thread = coroutine.running()
	local connection, timer
	connection = playerGui:GetAttributeChangedSignal("LoadingDone"):Connect(function()
		if playerGui:GetAttribute("LoadingDone") == true then
			connection:Disconnect()
			task.cancel(timer)
			task.spawn(thread, true)
		end
	end)
	timer = task.delay(limit, function()
		connection:Disconnect()
		task.spawn(thread, false)
	end)
	if not coroutine.yield() then
		warn("MainMenuClient: the loading screen did not hand over within " .. limit .. "s; opening the menu anyway")
	end
end

-- The loading screen fades out and destroys itself once the menu is open (or has fallen back to spawning). One that is
-- still there after LOADING_CLEANUP_DELAY is broken or stuck: remove it, so it can never keep covering the game.
-- Never yields.
local function scheduleLoadingCleanup()
	task.delay(LOADING_CLEANUP_DELAY, function()
		local leftover = playerGui:FindFirstChild("LoadingScreen")
		if leftover then
			leftover:Destroy()
		end
	end)
end

-- Clones the menu's three ScreenGuis, wires them up and shows them. Throws if the UI is not what this script expects.
local function setupMenu()
	-- Before anything is cloned or shown. The loading screen has already preloaded what the menu needs.
	waitForLoading()
	-- The button sounds. Guarded like everything else: a broken one leaves the menu silent, never closed.
	if ButtonSounds then
		local ok, err = pcall(ButtonSounds.init)
		if not ok then
			warn("MainMenuClient: ButtonSounds.init failed: " .. tostring(err))
		end
	end
	-- All three templates first, so a missing one throws before anything is cloned.
	local menuTemplate = waitForTemplate("MainMenu")
	local vignetteTemplate = waitForTemplate("MainMenuVignette")
	local faderTemplate = waitForTemplate("MainMenuFader")
	menu = menuTemplate:Clone()
	vignetteGui = vignetteTemplate:Clone()
	faderGui = faderTemplate:Clone()
	root = menu.Root
	back = menu.Back
	vignette = vignetteGui.Vignette
	fader = faderGui.Fader

	root.Buttons.Play.Activated:Connect(function()
		-- Before play() sets `playing`, so a second press (which play() ignores) stays silent.
		playSfx("playSelect")
		play()
	end)
	root.Buttons.Settings.Activated:Connect(function()
		playSfx("confirm")
		goToScene("Settings")
	end)
	root.Buttons.Credits.Activated:Connect(function()
		playSfx("confirm")
		goToScene("Credits")
	end)
	-- SceneDirector wires BACK itself (it goes back to the Menu); this only adds the click sound.
	back.Activated:Connect(function()
		playSfx("confirm")
	end)

	if ButtonEffects then
		local menuButtons = { root.Buttons.Play, root.Buttons.Settings, root.Buttons.Credits }
		-- Guarded: a failing effect must never keep the menu from opening (and the player from spawning).
		-- The hover sound is silent once Play has started (the menu is fading out, nothing there is a choice any more).
		local hoverOptions = {
			onHover = ButtonSounds and function()
				if not playing then
					pcall(ButtonSounds.hover)
				end
			end,
		}
		local function attachEffects(button)
			local ok, err = pcall(ButtonEffects.attach, button, hoverOptions)
			if not ok then
				warn("MainMenuClient: ButtonEffects.attach failed for " .. button.Name .. ": " .. tostring(err))
			end
		end
		for _, button in menuButtons do
			attachEffects(button)
		end
		attachEffects(back)

		-- A button that is hidden never gets its MouseLeave / touch-up, so one hidden while popped (the Settings
		-- button, when its click hides Root) would come back still popped. Reset them whenever they are hidden.
		local function resetWhenHidden(container, containerButtons)
			container:GetPropertyChangedSignal("Visible"):Connect(function()
				if container.Visible then
					return
				end
				for _, button in containerButtons do
					pcall(ButtonEffects.setState, button, "idle")
				end
			end)
		end
		resetWhenHidden(root, menuButtons)
		resetWhenHidden(back, { back })
	end

	-- The Vignette follows the Screen Effects setting, now and whenever it changes.
	-- Guarded like ButtonEffects: a broken setting must never keep the menu from opening.
	if MenuSettings then
		local ok, err = pcall(function()
			local function update()
				vignette.Visible = MenuSettings.get("ScreenEffects")
			end
			update()
			local connection = MenuSettings.changed("ScreenEffects"):Connect(update)
			-- The setting outlives the menu: stop listening once Play has destroyed it.
			menu.Destroying:Connect(function()
				connection:Disconnect()
			end)
		end)
		if not ok then
			warn("MainMenuClient: could not bind the Vignette to Screen Effects: " .. tostring(err))
		end
	end

	-- Guarded like the rest: a broken SceneDirector leaves Settings and Credits dead, never the menu or Play.
	if SceneDirector then
		local ok, err = pcall(SceneDirector.init, {
			fader = fader,
			root = root,
			back = back,
			menuCamera = MenuCamera,
			-- The music follows the scene (nil without MenuAudio: SceneDirector then calls nothing).
			onSceneChanged = MenuAudio and MenuAudio.setScene,
		})
		if not ok then
			warn("MainMenuClient: SceneDirector.init failed: " .. tostring(err))
		end
	end

	-- The Settings scene shows the board. SceneDirector runs these in pcall, behind the black screen, and the exit and
	-- dispose hooks on the Play path: none of them yield, and exit and dispose can run twice or with no board mounted.
	if SceneDirector and SettingsBoard then
		local ok, err = pcall(SceneDirector.register, "Settings", {
			enter = function()
				-- First, behind the black screen, so the room already has its own lighting on the first frame it is seen.
				applyRoomLighting()
				-- Mounted on the first visit and reused after that (dispose unmounts it, so it is looked up each time).
				local boardGui = playerGui:FindFirstChild("SettingsBoardGui")
				if not boardGui then
					local settingsRoom = workspace:FindFirstChild("SettingsRoom")
					local board = settingsRoom and settingsRoom:FindFirstChild("Settingsboard")
					if not (board and board:IsA("BasePart")) then
						warn("MainMenuClient: workspace.SettingsRoom.Settingsboard is missing; the Settings room stays empty")
						return
					end
					boardGui = SettingsBoard.mount(board, playerGui, ButtonSounds)
				end
				SettingsBoard.setEnabled(boardGui, true)
			end,
			exit = function()
				-- First, so nothing below can keep the normal lighting from coming back.
				restoreRoomLighting()
				local boardGui = playerGui:FindFirstChild("SettingsBoardGui")
				if boardGui then
					SettingsBoard.setEnabled(boardGui, false)
				end
			end,
			dispose = function()
				SettingsBoard.unmount(playerGui)
			end,
		})
		if not ok then
			warn("MainMenuClient: could not register the Settings board: " .. tostring(err))
		end
	end

	-- The Credits scene shows the developer's and the player's avatars. Same contract as above: nothing here yields, and
	-- exit and dispose are safe to run twice or with no avatars placed. enter never waits for an avatar: one that is not
	-- ready leaves its stand empty, and a short-lived thread places it if it arrives while the player is still here.
	if SceneDirector and CreditsRoom then
		local function findCreditsRoom()
			return workspace:FindFirstChild("CreditsRoom")
		end
		local ok, err = pcall(SceneDirector.register, "Credits", {
			enter = function()
				-- First, behind the black screen, so the room already has its own lighting on the first frame it is seen.
				applyRoomLighting()
				creditsVisit += 1
				local visit = creditsVisit
				local room = findCreditsRoom()
				if not room then
					warn("MainMenuClient: workspace.CreditsRoom is missing; the Credits room stays empty")
					return
				end
				CreditsRoom.enter(room, readyCreditSources())
				task.spawn(function()
					local deadline = os.clock() + CREDITS_AVATAR_WAIT
					while true do
						task.wait(CREDITS_AVATAR_POLL)
						-- Left Credits (or pressed Play) in the meantime, or nothing more to wait for.
						local folder = room:FindFirstChild("CreditAvatars")
						if visit ~= creditsVisit or os.clock() >= deadline or not folder then
							return
						end
						if folder:FindFirstChild("Developer") and folder:FindFirstChild("Viewer") then
							return
						end
						CreditsRoom.place(room, readyCreditSources())
					end
				end)
			end,
			exit = function()
				-- First, so nothing below can keep the normal lighting from coming back.
				restoreRoomLighting()
				creditsVisit += 1
				local room = findCreditsRoom()
				if room then
					CreditsRoom.exit(room)
				end
			end,
			dispose = function()
				creditsVisit += 1
				local room = findCreditsRoom()
				if room then
					CreditsRoom.dispose(room)
				end
			end,
		})
		if not ok then
			warn("MainMenuClient: could not register the Credits room: " .. tostring(err))
		end
	end

	-- All three go in together; DisplayOrder stacks them (Vignette 9 behind, MainMenu 10, Fader 11 on top).
	vignetteGui.Parent = playerGui
	menu.Parent = playerGui
	faderGui.Parent = playerGui
	playerGui:SetAttribute("MenuOpen", true)
	-- The scene the player is looking at: SceneDirector keeps this up to date from here on.
	playerGui:SetAttribute("MenuScene", "Menu")
end

local setupOk, setupError = pcall(setupMenu)
if not setupOk then
	warn("MainMenuClient: the menu could not be set up (" .. tostring(setupError) .. "); spawning without it")
	-- setupMenu parents the three ScreenGuis last, but never leave a half-built menu on screen: destroy every clone that exists.
	destroyMenuGuis()
	playerGui:SetAttribute("MenuOpen", false)
	scheduleLoadingCleanup()
	playPressed:FireServer()
	return
end
scheduleLoadingCleanup()

-- The menu is open: its music starts (MenuMusic fades in). Guarded: a failing music module must never touch the menu or Play.
if MenuAudio then
	local ok, err = pcall(MenuAudio.start)
	if not ok then
		warn("MainMenuClient: MenuAudio.start failed: " .. tostring(err))
	end
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
	-- Test hook for tests/menu_client.client.luau and tests/scenes.client.luau (execute_luau cannot reach this script's locals).
	--   goTo(name)  asks SceneDirector for a scene change like the Settings / Credits / BACK buttons do; returns
	--               SceneDirector.goTo's boolean (whether a transition started)
	--   scene()     the scene the menu says it is showing (the PlayerGui attribute MenuScene, kept by SceneDirector)
	--   play()      presses Play; returns false if it was already pressed
	--   gamepad(on) makes SceneDirector behave as if the player is on a gamepad (there is none to plug in), so the
	--               controller selection can be tested
	--   back(state) feeds the ButtonB action ("Begin" or "End") to the function SceneDirector binds to it; returns its
	--               Enum.ContextActionResult
	local hook = Instance.new("BindableFunction")
	hook.Name = "TestHook"
	hook.OnInvoke = function(action, arg)
		if action == "goTo" then
			return goToScene(arg)
		elseif action == "scene" then
			return playerGui:GetAttribute("MenuScene")
		elseif action == "play" then
			return play()
		elseif action == "gamepad" then
			SceneDirector.setGamepadOverride(arg)
		elseif action == "back" then
			return SceneDirector.onBack("MenuBack", Enum.UserInputState[arg])
		else
			error("TestHook: unknown action " .. tostring(action))
		end
	end
	hook.Parent = script
end
