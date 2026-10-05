-- LoadingScreen: the factory loading screen. It shows at once, preloads what the main menu needs, then fades to black
-- and hands over to the menu (MainMenuClient waits for it before it shows anything).
-- It lives in ReplicatedFirst so it runs before the rest of the game has replicated, and it builds its UI in code
-- (a template in ReplicatedStorage would not have arrived yet). Sound ids, tips and timings: ReplicatedFirst.MenuAssets.
--
-- What it does:
--   1. Builds the ScreenGui "LoadingScreen" (above every menu gui), parents it, then removes Roblox's own loading screen.
--   2. Preloads in parallel: the game itself, the six menu sounds (ContentProvider:PreloadAsync), the menu's three
--      ScreenGuis, the Settings and Credits rooms and the player's menu avatar. Each wait is capped, and the whole thing
--      is capped by LOADING_MAX_SECONDS.
--   3. Once everything is there and at least LOADING_MIN_SECONDS have passed (or LOADING_MAX_SECONDS have), it fades to
--      black, sets the PlayerGui attribute LoadingDone, waits (briefly) for the menu to open under the black, fades out
--      and destroys itself.
-- A failure anywhere in here must never keep the menu from opening: if this script throws, it sets LoadingDone anyway and
-- removes its gui. MainMenuClient also destroys any leftover "LoadingScreen" gui once the menu is open.
--
-- PlayerGui attributes it leaves for MainMenuClient, the audio code and the tests:
--   LoadingDone          boolean  false while loading, true once it has faded to black (the menu may open now)
--   LoadingShownAt       number   os.clock() when the gui was shown
--   LoadingDoneAt        number   os.clock() when LoadingDone was set
--   LoadingParts         string   the parts it built, e.g. "Title,Spinner,Tip" (the gui is gone before a test can look)
--   LoadingFailedSounds  string   comma-separated keys of the sounds Roblox refused to load, "" if none
--   LoadingTipChanges    number   how many times the tip has changed
-- In Studio it also has a TestHook (BindableFunction) under this script: Invoke("state") -> { done, elapsed, failed }.
--
-- UI names other code depends on (tests look for them): Title, Spinner, Tip. Restyle anything else freely.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local FADE_TIME = 0.4
local MENU_OPEN_TIMEOUT = 3 -- how long to wait for the menu to open under the black before fading out anyway
local ASSETS_MODULE_TIMEOUT = 2
local POLL = 0.05
local SPINNER_DEGREES_PER_SECOND = 220

-- Factory look, the same as the menu (see studio/build_main_menu_ui.luau).
local TITLE_TEXT = "GAME TITLE"
local AMBER = Color3.fromRGB(255, 150, 30)
local BACKDROP_COLOR = Color3.fromRGB(16, 14, 12)
local VIGNETTE_COLOR = Color3.fromRGB(12, 9, 6)
local VIGNETTE_DEPTH = 0.18
local TIP_COLOR = Color3.fromRGB(220, 208, 190)
local FONT = Font.fromEnum(Enum.Font.Oswald)
local FONT_BOLD = Font.new(FONT.Family, Enum.FontWeight.Bold)

-- Defaults, used only if ReplicatedFirst.MenuAssets is missing or broken.
local minSeconds = 2
local maxSeconds = 20
local tipSeconds = 4
local tips = { "LOADING..." }
local sounds = {}

local player = Players.LocalPlayer
if not player then
	Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	player = Players.LocalPlayer
end
local playerGui
local gui
local spinnerConnection
local shownAt = 0
local finishing = false
local failedKeys = {}

local function readConfig()
	local module = ReplicatedFirst:WaitForChild("MenuAssets", ASSETS_MODULE_TIMEOUT)
	assert(module, "ReplicatedFirst.MenuAssets is missing")
	local assets = require(module)
	if type(assets.LOADING_MIN_SECONDS) == "number" then
		minSeconds = assets.LOADING_MIN_SECONDS
	end
	if type(assets.LOADING_MAX_SECONDS) == "number" then
		maxSeconds = assets.LOADING_MAX_SECONDS
	end
	if type(assets.TIP_SECONDS) == "number" and assets.TIP_SECONDS > 0 then
		tipSeconds = assets.TIP_SECONDS
	end
	if type(assets.Tips) == "table" and #assets.Tips > 0 then
		tips = assets.Tips
	end
	if type(assets.Sounds) == "table" then
		sounds = assets.Sounds
	end
	maxSeconds = math.max(maxSeconds, minSeconds)
end

local function make(className, props, parent)
	local inst = Instance.new(className)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function label(props, parent)
	props.BackgroundTransparency = 1
	props.BorderSizePixel = 0
	props.TextColor3 = props.TextColor3 or Color3.new(1, 1, 1)
	props.TextScaled = true
	props.TextWrapped = true
	props.FontFace = props.FontFace or FONT
	return make("TextLabel", props, parent)
end

-- Builds the whole gui, detached. Scale only (the UIStroke thickness is the one exception), so it fits every screen. The
-- backdrop and the vignette fill the full screen (ScreenInsets None); the text sits in Content, an inner frame with
-- margins, so nothing goes under a phone's notch or rounded corners.
local function build(firstTip)
	local built = Instance.new("ScreenGui")
	built.Name = "LoadingScreen"
	built.ResetOnSpawn = false
	built.IgnoreGuiInset = true
	-- Set after IgnoreGuiInset, which moves it to DeviceSafeInsets when it switches on.
	built.ScreenInsets = Enum.ScreenInsets.None
	built.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	built.DisplayOrder = 20

	-- Active, so a click during the fade out does not reach the menu underneath.
	make("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = BACKDROP_COLOR,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 1,
	}, built)

	-- Dark edges on all four sides, each fading with a UIGradient from 0.15 at the screen border to 1 on the inside.
	local vignette = make("Frame", {
		Name = "Vignette",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, built)
	local function edge(name, anchor, position, size, rotation)
		local frame = make("Frame", {
			Name = name,
			AnchorPoint = anchor,
			Position = position,
			Size = size,
			BackgroundColor3 = VIGNETTE_COLOR,
			BorderSizePixel = 0,
		}, vignette)
		make("UIGradient", {
			Rotation = rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}, frame)
	end
	edge("Top", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, VIGNETTE_DEPTH), 90)
	edge("Bottom", Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, VIGNETTE_DEPTH), 270)
	edge("Left", Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(VIGNETTE_DEPTH, 1), 0)
	edge("Right", Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(VIGNETTE_DEPTH, 1), 180)

	local content = make("Frame", {
		Name = "Content",
		Position = UDim2.fromScale(0.08, 0.1),
		Size = UDim2.fromScale(0.84, 0.8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, built)

	local title = label({
		Name = "Title",
		Text = TITLE_TEXT,
		FontFace = FONT_BOLD,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.26),
		Size = UDim2.fromScale(0.9, 0.26),
		ZIndex = 3,
	}, content)
	make("UIStroke", { Name = "Trim", Color = AMBER, Thickness = 2 }, title)

	-- An amber ring with a gap (a UIGradient on the stroke hides the last 40% of it), turned by the RenderStepped loop.
	local spinner = make("Frame", {
		Name = "Spinner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromScale(0.26, 0.26),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, content)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, spinner)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, spinner)
	local ring = make("UIStroke", { Name = "Ring", Color = AMBER, Thickness = 6 }, spinner)
	make("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.6, 0),
			NumberSequenceKeypoint.new(0.601, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, ring)

	label({
		Name = "Tip",
		Text = string.upper(firstTip),
		TextColor3 = TIP_COLOR,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.9),
		Size = UDim2.fromScale(1, 0.1),
		ZIndex = 3,
	}, content)

	return built
end

local function publishFailed()
	local list = {}
	for key in failedKeys do
		table.insert(list, key)
	end
	table.sort(list)
	playerGui:SetAttribute("LoadingFailedSounds", table.concat(list, ","))
	return table.concat(list, ",")
end

-- Records a sound that Roblox refused to load. Warned once per key.
local function failSound(key, reason)
	if failedKeys[key] then
		return
	end
	failedKeys[key] = true
	warn("LoadingScreen: sound '" .. key .. "' (" .. tostring(sounds[key]) .. ") did not load: " .. tostring(reason))
	publishFailed()
end

-- Preloads the six sounds through temporary Sound instances. The callback reports each asset's fetch status; anything
-- but Success is a failure, mapped back to its key by the number in the id.
local function preloadSounds()
	local function idNumber(soundId)
		return type(soundId) == "string" and string.match(soundId, "%d+") or nil
	end
	local keyById = {}
	local instances = {}
	for key, soundId in sounds do
		if idNumber(soundId) then
			local sound = make("Sound", { Name = key, SoundId = soundId }, gui)
			table.insert(instances, sound)
			keyById[idNumber(soundId)] = key
		else
			failSound(key, "the SoundId is empty or not an asset id")
		end
	end
	ContentProvider:PreloadAsync(instances, function(contentId, status)
		if status ~= Enum.AssetFetchStatus.Success then
			local key = keyById[idNumber(contentId)]
			if key then
				failSound(key, tostring(status))
			else
				warn("LoadingScreen: an asset did not load: " .. tostring(contentId) .. " (" .. tostring(status) .. ")")
			end
		end
	end)
end

-- Tweens each { instance, properties } entry together over `duration` seconds.
local function tweenAll(entries, duration)
	local info = TweenInfo.new(duration)
	for _, entry in entries do
		TweenService:Create(entry[1], info, entry[2]):Play()
	end
end

-- Everything on screen goes to black: the backdrop darkens while the title, the spinner and the tip fade out.
local function fadeToBlack()
	local black = Color3.new(0, 0, 0)
	local entries = {
		{ gui.Backdrop, { BackgroundColor3 = black } },
		{ gui.Content.Title, { TextTransparency = 1 } },
		{ gui.Content.Title.Trim, { Transparency = 1 } },
		{ gui.Content.Spinner.Ring, { Transparency = 1 } },
		{ gui.Content.Tip, { TextTransparency = 1 } },
	}
	for _, edge in gui.Vignette:GetChildren() do
		table.insert(entries, { edge, { BackgroundColor3 = black } })
	end
	tweenAll(entries, FADE_TIME)
end

-- The black fades away, revealing the menu underneath.
local function fadeOut()
	local entries = { { gui.Backdrop, { BackgroundTransparency = 1 } } }
	for _, edge in gui.Vignette:GetChildren() do
		table.insert(entries, { edge, { BackgroundTransparency = 1 } })
	end
	tweenAll(entries, FADE_TIME)
end

local function run()
	playerGui = player:WaitForChild("PlayerGui")

	local configOk, configError = pcall(readConfig)
	if not configOk then
		warn("LoadingScreen: could not read MenuAssets, using the defaults: " .. tostring(configError))
	end

	local tipIndex = math.random(#tips)
	gui = build(tostring(tips[tipIndex]))
	local spinner = gui.Content.Spinner
	local tip = gui.Content.Tip

	-- Studio-only test hook: Invoke("state") -> { done, elapsed, failed }.
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "TestHook"
		hook.OnInvoke = function(action)
			if action == "state" then
				local doneAt = playerGui:GetAttribute("LoadingDoneAt")
				return {
					done = playerGui:GetAttribute("LoadingDone") == true,
					elapsed = (type(doneAt) == "number" and doneAt or os.clock()) - shownAt,
					failed = publishFailed(),
				}
			end
			error("TestHook: unknown action " .. tostring(action))
		end
		hook.Parent = script
	end

	spinnerConnection = RunService.RenderStepped:Connect(function()
		spinner.Rotation = (os.clock() * SPINNER_DEGREES_PER_SECOND) % 360
	end)
	gui.Destroying:Connect(function()
		spinnerConnection:Disconnect()
	end)

	-- Shown first, and only then Roblox's own loading screen goes.
	gui.Parent = playerGui
	shownAt = os.clock()
	pcall(function()
		ReplicatedFirst:RemoveDefaultLoadingScreen()
	end)
	local parts = {}
	for _, name in { "Title", "Spinner", "Tip" } do
		if gui:FindFirstChild(name, true) then
			table.insert(parts, name)
		end
	end
	playerGui:SetAttribute("LoadingParts", table.concat(parts, ","))
	playerGui:SetAttribute("LoadingFailedSounds", "")
	playerGui:SetAttribute("LoadingTipChanges", 0)
	playerGui:SetAttribute("LoadingShownAt", shownAt)
	playerGui:SetAttribute("LoadingDone", false)

	-- The tip changes every TIP_SECONDS until the handoff starts.
	if #tips > 1 then
		task.spawn(function()
			local changes = 0
			while true do
				task.wait(tipSeconds)
				if finishing or not gui.Parent then
					return
				end
				tipIndex = tipIndex % #tips + 1
				tip.Text = string.upper(tostring(tips[tipIndex]))
				changes += 1
				playerGui:SetAttribute("LoadingTipChanges", changes)
			end
		end)
	end

	-- Preload, everything at once. Each job has its own pcall and cap; `pending` names the ones still running.
	local deadline = shownAt + maxSeconds
	local pending = {}
	local pendingCount = 0
	local function job(name, fn)
		pending[name] = true
		pendingCount += 1
		task.spawn(function()
			local ok, err = pcall(fn)
			if not ok then
				warn("LoadingScreen: " .. name .. " failed: " .. tostring(err))
			end
			pending[name] = nil
			pendingCount -= 1
		end)
	end
	-- Waits for parent[name] to appear, for at most what is left of the overall time. Returns it, or nil.
	local function waitForChild(parent, name)
		local child = parent:WaitForChild(name, math.max(deadline - os.clock(), 0.1))
		if not child then
			warn("LoadingScreen: " .. parent:GetFullName() .. "." .. name .. " had not appeared when the time was up")
		end
		return child
	end

	job("game", function()
		if not game:IsLoaded() then
			game.Loaded:Wait()
		end
	end)
	job("sounds", preloadSounds)
	for _, name in { "MainMenu", "MainMenuVignette", "MainMenuFader" } do
		job("ReplicatedStorage." .. name, function()
			waitForChild(ReplicatedStorage, name)
		end)
	end
	for _, name in { "SettingsRoom", "CreditsRoom" } do
		job("workspace." .. name, function()
			waitForChild(workspace, name)
		end)
	end
	job("menu avatar", function()
		local avatars = waitForChild(ReplicatedStorage, "MenuAvatars")
		if avatars then
			waitForChild(avatars, tostring(player.UserId))
		end
	end)

	while pendingCount > 0 and os.clock() < deadline do
		task.wait(POLL)
	end
	if pendingCount > 0 then
		local names = {}
		for name in pending do
			table.insert(names, name)
		end
		warn("LoadingScreen: " .. maxSeconds .. "s are up, opening the menu without: " .. table.concat(names, ", "))
	end
	-- It never just flashes by.
	local remaining = shownAt + minSeconds - os.clock()
	if remaining > 0 then
		task.wait(remaining)
	end

	-- Handoff: to black, then LoadingDone (MainMenuClient opens the menu under the black), then the black fades away.
	finishing = true
	publishFailed()
	fadeToBlack()
	task.wait(FADE_TIME)
	playerGui:SetAttribute("LoadingDoneAt", os.clock())
	playerGui:SetAttribute("LoadingDone", true)
	-- MenuOpen stays nil until MainMenuClient has decided: true once the menu is open, false if it fell back to spawning.
	local menuLimit = os.clock() + MENU_OPEN_TIMEOUT
	while playerGui:GetAttribute("MenuOpen") == nil and os.clock() < menuLimit do
		task.wait(POLL)
	end
	fadeOut()
	task.wait(FADE_TIME)
	gui:Destroy()
end

local ok, err = pcall(run)
if not ok then
	warn("LoadingScreen failed, the menu opens without it: " .. tostring(err))
	-- The menu must not wait for a loading screen that is gone.
	finishing = true
	pcall(function()
		if gui then
			gui:Destroy()
		end
		if playerGui then
			playerGui:SetAttribute("LoadingDone", true)
		end
	end)
end
