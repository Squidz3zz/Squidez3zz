-- SceneDirector: the three scenes of the main menu (Menu, Settings, Credits) and the fade-cuts between them.
-- goTo(name) fades the Fader to black, runs the old scene's exit hook, cuts the camera to the new scene's shot, swaps
-- Root and Back, runs the new scene's enter hook and fades back in. Menu has no marker of its own: it uses the menu
-- shot (MenuCamera.menuBase()). Settings and Credits cut to the camera markers inside their rooms, and those two
-- scenes hang their contents (the settings board, the credit avatars) on register()ed hooks:
--   enter    shows the scene, behind the black screen
--   exit     hides it again
--   dispose  final cleanup when Play starts
-- Hooks run in pcall, so a failing one is warned about and the fade back in still completes. Hooks that run on the
-- Play path (exit and dispose, called by stop) should not yield: stop() runs them detached so it never waits, but
-- a hook that yields would be left to finish on its own after the menu is gone.
--
-- Each transition runs in its own thread. stop() (the Play path) cancels it: the thread notices after every step it
-- yields on and ends without touching the camera, Root, Back or the Fader again, because from then on Play owns them.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local FADE = TweenInfo.new(0.4)

local SCENES = { Menu = true, Settings = true, Credits = true }
-- Where the camera goes for each room scene: workspace[room][shot]. Both rooms are Persistent, so they are always there.
local MARKERS = {
	Settings = { room = "SettingsRoom", shot = "SettingsCameraShot" },
	Credits = { room = "CreditsRoom", shot = "CreditsCameraShot" },
}

local SceneDirector = {}

local ctx = nil -- { fader, root, back, menuCamera? }, set by init
local hooks = {} -- scene name -> { enter?, exit?, dispose? }
local current = "Menu"
local running = nil -- { cancelled, tween? } while a transition runs
local stopped = false -- Play has started: no more scene changes
local backConnection = nil

local function setCurrent(name)
	current = name
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		playerGui:SetAttribute("MenuScene", name)
	end
end

local function runHook(sceneName, hookName)
	local sceneHooks = hooks[sceneName]
	local hook = sceneHooks and sceneHooks[hookName]
	if not hook then
		return
	end
	local ok, err = pcall(hook)
	if not ok then
		warn(("SceneDirector: the %s hook of %s failed: %s"):format(hookName, sceneName, tostring(err)))
	end
end

-- Fades the Fader to `transparency` and waits for it. False if stop() cancelled the transition in the meantime.
local function fade(run, transparency)
	if run.cancelled then
		return false
	end
	local tween = TweenService:Create(ctx.fader, FADE, { BackgroundTransparency = transparency })
	run.tween = tween
	tween:Play()
	tween.Completed:Wait() -- fires when stop() cancels the tween, too
	run.tween = nil
	return not run.cancelled
end

local function transition(run, name, marker)
	local old = current
	if not fade(run, 0) then
		return
	end
	runHook(old, "exit")
	if run.cancelled then
		return
	end

	-- Fully black: cut to the new scene.
	local menuCamera = ctx.menuCamera
	if menuCamera then
		local ok, err = pcall(function()
			menuCamera.setBase(if marker then marker.CFrame else menuCamera.menuBase())
		end)
		if not ok then
			warn("SceneDirector: setting the camera for " .. name .. " failed: " .. tostring(err))
		end
	end
	ctx.root.Visible = name == "Menu"
	ctx.back.Visible = name ~= "Menu"
	setCurrent(name)
	runHook(name, "enter")
	if run.cancelled then
		return
	end

	fade(run, 1)
end

function SceneDirector.init(context)
	assert(context.fader and context.root and context.back, "SceneDirector.init: fader, root and back are required")
	ctx = context
	stopped = false
	running = nil
	setCurrent("Menu")
	if backConnection then
		backConnection:Disconnect()
	end
	backConnection = context.back.Activated:Connect(function()
		SceneDirector.goTo("Menu")
	end)
end

-- hooks: { enter: (() -> ())?, exit: (() -> ())?, dispose: (() -> ())? }. Missing hooks are fine.
function SceneDirector.register(name, sceneHooks)
	assert(SCENES[name], "SceneDirector.register: unknown scene " .. tostring(name))
	assert(type(sceneHooks) == "table", "SceneDirector.register: hooks must be a table")
	hooks[name] = sceneHooks
end

-- Starts a fade-cut to `name` in its own thread. False (and nothing happens) if a transition is already running,
-- if `name` is the current scene or unknown, if Play has started, or if the room's camera marker is missing (warns).
function SceneDirector.goTo(name)
	if not ctx or stopped or running or name == current then
		return false
	end
	if not SCENES[name] then
		warn("SceneDirector: unknown scene " .. tostring(name))
		return false
	end

	local marker = nil
	local spec = MARKERS[name]
	if spec then
		local room = workspace:FindFirstChild(spec.room)
		marker = room and room:FindFirstChild(spec.shot)
		if not (marker and marker:IsA("BasePart")) then
			warn(("SceneDirector: cannot open %s, workspace.%s.%s is missing"):format(name, spec.room, spec.shot))
			return false
		end
	end

	local run = { cancelled = false }
	running = run
	task.spawn(function()
		local ok, err = pcall(transition, run, name, marker)
		if not ok then
			warn("SceneDirector: the transition to " .. name .. " failed: " .. tostring(err))
			-- Never leave the player on a black screen.
			if not run.cancelled then
				pcall(function()
					ctx.fader.BackgroundTransparency = 1
				end)
			end
		end
		if running == run then
			running = nil
		end
	end)
	return true
end

-- The Play path. Never yields: it cancels the running transition, leaves the scene the player is in and disposes
-- every scene. Play owns the camera and the Fader from here on. Idempotent.
function SceneDirector.stop()
	if stopped then
		return
	end
	stopped = true

	local run = running
	running = nil
	if run then
		run.cancelled = true
		if run.tween then
			pcall(run.tween.Cancel, run.tween)
		end
	end

	-- Detached, so a hook that yields can never hold up Play.
	task.spawn(runHook, current, "exit")
	for name in hooks do
		task.spawn(runHook, name, "dispose")
	end
end

return SceneDirector
