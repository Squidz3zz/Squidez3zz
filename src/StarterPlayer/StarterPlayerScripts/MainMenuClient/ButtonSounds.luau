-- ButtonSounds: the menu's button sound effects, on the Sound Effects slider.
-- init() makes three Sounds in SoundService, all in the SFX SoundGroup. The group's Volume is the Sound Effects slider on the
-- Settings board, so the Sounds themselves stay at Volume 1:
--   MenuSfxHover    a button is hovered: the mouse enters it, a controller selects it or a finger lands on it
--                   (ButtonEffects calls hover() through its onHover option; the Settings board's switch rows call it too)
--   MenuSfxConfirm  a button was clicked, except PLAY
--   MenuSfxPlay     PLAY was clicked
-- Their asset ids are ReplicatedFirst.MenuAssets.Sounds.Hover / Confirm / PlaySelect.
-- hover(), confirm() and playSelect() restart their sound from the beginning and never yield, so they are safe on the
-- Play path. The Sounds live in SoundService, not in the menu, so Play's fade and the menu's destruction do not cut them off.
-- A sound that did not load (Roblox refused the asset) is skipped with one warning; the others still play.
-- The functions look the Sounds up by name on every call, so any copy of this module (the tests make their own) drives the
-- same Sounds, and nothing here is needed to find them but SoundService.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local SoundService = game:GetService("SoundService")

-- How long init's background thread waits for ReplicatedFirst.MenuAssets if it is not there yet.
local ASSETS_TIMEOUT = 10

-- The key in MenuAssets.Sounds -> the name of its Sound in SoundService.
local SOUND_NAMES = {
	Hover = "MenuSfxHover",
	Confirm = "MenuSfxConfirm",
	PlaySelect = "MenuSfxPlay",
}

local ButtonSounds = {}

local started = false
local loadAttempted = {} -- sound name -> true once its load attempt has finished
local warned = {} -- sound name -> true once it was warned about

local function warnOnce(key, message)
	if not warned[key] then
		warned[key] = true
		warn("ButtonSounds: " .. message)
	end
end

local function skipMessage(key)
	return ("%s did not load (check MenuAssets.Sounds.%s); skipping it"):format(SOUND_NAMES[key], key)
end

-- Creates the Sounds (or takes the ones that are already there) and starts loading them. Never yields.
local function build(assetsModule)
	local ok, assets = pcall(require, assetsModule)
	if not ok or type(assets) ~= "table" or type(assets.Sounds) ~= "table" then
		warn("ButtonSounds: could not read MenuAssets.Sounds (" .. tostring(assets) .. "); the button sounds are off")
		return
	end

	local sfx = SoundService:FindFirstChild("SFX")
	if not (sfx and sfx:IsA("SoundGroup")) then
		warn("ButtonSounds: SoundService.SFX is missing; the button sounds will not follow the Sound Effects slider")
		sfx = nil
	end

	local made = {}
	for key, name in SOUND_NAMES do
		-- A number or a bare digit string becomes rbxassetid://<digits>; nil if there is no usable id.
		local id = assets.soundId(assets.Sounds[key])
		if not id then
			warn(("ButtonSounds: MenuAssets.Sounds.%s is not set (or is not a sound id); that sound is off"):format(key))
		else
			local sound = SoundService:FindFirstChild(name)
			if not sound then
				sound = Instance.new("Sound")
				sound.Name = name
				sound.SoundId = id
				sound.Volume = 1
				sound.SoundGroup = sfx
				sound.Parent = SoundService
			end
			table.insert(made, { key = key, sound = sound })
		end
	end

	-- Until a sound's load attempt is over it just queues (it plays as soon as it has loaded). After that, one that is still
	-- not loaded is skipped.
	local sounds = {}
	for _, entry in made do
		table.insert(sounds, entry.sound)
	end
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, sounds)
		for _, entry in made do
			loadAttempted[entry.sound.Name] = true
			if not entry.sound.IsLoaded then
				warnOnce(entry.key, skipMessage(entry.key))
			end
		end
	end)
end

-- Creates the three Sounds in SoundService, in the SFX group. Safe to call again, and never yields (if MenuAssets has not
-- arrived yet, a background thread waits for it).
function ButtonSounds.init()
	if started then
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
			warn("ButtonSounds: ReplicatedFirst.MenuAssets is missing; the button sounds are off")
		end
	end)
end

local function play(key)
	local sound = SoundService:FindFirstChild(SOUND_NAMES[key])
	if not (sound and sound:IsA("Sound")) then
		return -- init has not run, or failed: no sound, no error
	end
	if loadAttempted[sound.Name] and not sound.IsLoaded then
		warnOnce(key, skipMessage(key))
		return
	end
	sound.TimePosition = 0
	sound:Play()
end

function ButtonSounds.hover()
	play("Hover")
end

function ButtonSounds.confirm()
	play("Confirm")
end

function ButtonSounds.playSelect()
	play("PlaySelect")
end

return ButtonSounds
