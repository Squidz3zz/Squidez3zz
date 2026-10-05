-- MenuAudio: the main menu's background music, on the Music slider.
-- start() makes three looping Sounds in SoundService, all in the Music SoundGroup (whose Volume is the Music slider on the
-- Settings board, so the Sounds themselves only fade between 0 and 1):
--   MenuMusic      the Menu scene
--   SettingsMusic  the Settings scene
--   CreditsMusic   the Credits scene
-- Their asset ids are ReplicatedFirst.MenuAssets.Sounds, under the same names. Only the track of the scene the player is in is
-- audible:
--   start()          fades MenuMusic in
--   setScene(name)   crossfades to that scene's track over CROSSFADE seconds. The track that leaves fades out and is PAUSED, so
--                    it resumes from where it was on the next visit (a track plays from its start the first time)
--   stop()           the Play path: fades whatever is playing out over FADE_OUT seconds, then stops and destroys the Sounds
-- None of them yield, and stop() only touches the music: the button sounds (ButtonSounds) keep playing through Play's fade.
-- setScene works from the Sounds' own state (which of them is playing), not from a "previous scene" it remembers, and cancels
-- the fade running on a Sound before it starts another, so scene changes in quick succession never leave two tracks audible or
-- stack fades, and a fade that was cut short never pauses or destroys anything afterwards.
-- The functions look the Sounds up by name on every call, so any copy of this module (the tests make their own) drives the
-- same Sounds.
-- A track that did not load (Roblox refused the asset: its key is in the PlayerGui attribute LoadingFailedSounds, or it is
-- still not loaded once the load attempt is over) is skipped with one warning; the others still play.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local CROSSFADE = TweenInfo.new(0.8, Enum.EasingStyle.Linear)
local FADE_OUT = TweenInfo.new(0.4, Enum.EasingStyle.Linear)
-- How long start's background thread waits for ReplicatedFirst.MenuAssets if it is not there yet.
local ASSETS_TIMEOUT = 10

-- The scene -> the name of its Sound in SoundService, which is also its key in MenuAssets.Sounds.
local TRACKS = {
	Menu = "MenuMusic",
	Settings = "SettingsMusic",
	Credits = "CreditsMusic",
}

local MenuAudio = {}

local started = false
local stopped = false -- Play has started: the music is on its way out, and nothing starts it again
local current = "Menu" -- the scene whose track should be playing
-- Per Sound, weak so a destroyed one is not kept alive: the tween running on its Volume and the Volume it is heading for.
local fades = setmetatable({}, { __mode = "k" })
local goals = setmetatable({}, { __mode = "k" })
local failed = {} -- track name -> true once it is known not to load
local loadAttempted = {} -- track name -> true once its load attempt has finished
local warned = {} -- track name -> true once it was warned about

local function warnOnce(name, message)
	if not warned[name] then
		warned[name] = true
		warn("MenuAudio: " .. message)
	end
end

local function skipMessage(name)
	return ("%s did not load (check MenuAssets.Sounds.%s); skipping it"):format(name, name)
end

local function findSound(name)
	local sound = SoundService:FindFirstChild(name)
	return if sound and sound:IsA("Sound") then sound else nil
end

-- Cancels the fade running on `sound`, if any. Its Completed handler sees it is no longer the current one and does nothing.
local function cancel(sound)
	local tween = fades[sound]
	if tween then
		fades[sound] = nil
		goals[sound] = nil
		tween:Cancel()
	end
end

-- Tweens the Volume of `sound` to `volume`, replacing any fade already running on it, and calls `onDone` if this fade runs to
-- its end (not if another fade or stop() replaced it first). A fade already heading for `volume` is left alone.
local function fadeTo(sound, volume, info, onDone)
	if fades[sound] and goals[sound] == volume then
		return
	end
	cancel(sound)
	local tween = TweenService:Create(sound, info, { Volume = volume })
	fades[sound] = tween
	goals[sound] = volume
	tween.Completed:Once(function(state)
		if fades[sound] ~= tween then
			return
		end
		fades[sound] = nil
		goals[sound] = nil
		if state == Enum.PlaybackState.Completed and onDone then
			onDone()
		end
	end)
	tween:Play()
end

-- Brings the track of scene `scene` in: resumes it where it paused (or plays it from the start the first time) and fades it up.
local function fadeIn(scene)
	local name = TRACKS[scene]
	local sound = findSound(name)
	if not sound then
		return
	end
	if failed[name] or (loadAttempted[name] and not sound.IsLoaded) then
		warnOnce(name, skipMessage(name))
		return
	end
	if sound.IsPaused then
		sound:Resume()
	elseif not sound.Playing then
		sound:Play()
	end
	fadeTo(sound, 1, CROSSFADE)
end

-- Takes the track of scene `scene` out: fades it down, then pauses it. One that is not playing is already silent.
local function fadeOut(scene)
	local sound = findSound(TRACKS[scene])
	if sound and sound.Playing then
		fadeTo(sound, 0, CROSSFADE, function()
			sound:Pause()
		end)
	end
end

-- Makes the music match `current`: its track comes in, the other two go out.
local function refresh()
	for scene in TRACKS do
		if scene == current then
			fadeIn(scene)
		else
			fadeOut(scene)
		end
	end
end

-- Creates the Sounds (or takes the ones that are already there), starts loading them and starts the current scene's track.
-- Never yields.
local function build(assetsModule)
	if stopped then
		return
	end
	local ok, assets = pcall(require, assetsModule)
	if not ok or type(assets) ~= "table" or type(assets.Sounds) ~= "table" then
		warn("MenuAudio: could not read MenuAssets.Sounds (" .. tostring(assets) .. "); the music is off")
		return
	end

	local group = SoundService:FindFirstChild("Music")
	if not (group and group:IsA("SoundGroup")) then
		warn("MenuAudio: SoundService.Music is missing; the music will not follow the Music slider")
		group = nil
	end

	-- The keys the loading screen saw Roblox refuse.
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	local failedList = playerGui and playerGui:GetAttribute("LoadingFailedSounds")
	if type(failedList) == "string" then
		for key in string.gmatch(failedList, "[^,%s]+") do
			for _, name in TRACKS do
				if name == key then
					failed[name] = true
					warnOnce(name, skipMessage(name))
				end
			end
		end
	end

	local made = {}
	for _, name in TRACKS do
		local id = assets.Sounds[name]
		if type(id) ~= "string" or id == "" then
			warn(("MenuAudio: MenuAssets.Sounds.%s is not set; that track is off"):format(name))
			failed[name] = true
		else
			local sound = findSound(name)
			if not sound then
				sound = Instance.new("Sound")
				sound.Name = name
				sound.SoundId = id
				sound.Looped = true
				sound.Volume = 0
				sound.SoundGroup = group
				sound.Parent = SoundService
			end
			table.insert(made, { name = name, sound = sound })
		end
	end

	refresh()

	-- Until a track's load attempt is over it just queues (it plays as soon as it has loaded). After that, one that is still
	-- not loaded is skipped, and silenced if it was already queued to play.
	task.spawn(function()
		local sounds = {}
		for _, entry in made do
			table.insert(sounds, entry.sound)
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, sounds)
		for _, entry in made do
			loadAttempted[entry.name] = true
			if not entry.sound.IsLoaded then
				warnOnce(entry.name, skipMessage(entry.name))
				cancel(entry.sound)
				entry.sound:Stop()
			end
		end
	end)
end

-- Creates the three tracks and fades the Menu one in. Safe to call again, and never yields (if MenuAssets has not arrived yet,
-- a background thread waits for it).
function MenuAudio.start()
	if started or stopped then
		return
	end
	started = true

	local assetsModule = ReplicatedFirst:FindFirstChild("MenuAssets")
	if assetsModule then
		build(assetsModule)
		return
	end
	task.spawn(function()
		local found = ReplicatedFirst:WaitForChild("MenuAssets", ASSETS_TIMEOUT)
		if found then
			build(found)
		else
			warn("MenuAudio: ReplicatedFirst.MenuAssets is missing; the music is off")
		end
	end)
end

-- Crossfades to the track of scene `name`. Never yields.
function MenuAudio.setScene(name)
	if not TRACKS[name] then
		warn("MenuAudio.setScene: unknown scene " .. tostring(name))
		return
	end
	if stopped then
		return
	end
	current = name
	refresh()
end

-- The Play path: fades the music out and removes the Sounds. Never yields, safe to call again, and leaves the button sounds alone.
function MenuAudio.stop()
	if stopped then
		return
	end
	stopped = true
	for _, name in TRACKS do
		local sound = findSound(name)
		if sound then
			cancel(sound)
			if sound.Playing then
				local tween = TweenService:Create(sound, FADE_OUT, { Volume = 0 })
				tween.Completed:Once(function()
					sound:Stop()
					sound:Destroy()
				end)
				tween:Play()
			else
				sound:Destroy()
			end
		end
	end
end

return MenuAudio
