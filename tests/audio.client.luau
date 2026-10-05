-- Run in the Client datamodel of a playtest. Pick the case with CASE below, then run the whole file as an execute_luau
-- call. S-B and S-D need a real mouse (user_mouse_input) and a FRESH playtest (no character yet); S-A and S-C need neither.
-- Tests the menu's sound effects: ButtonSounds (SoundService.MenuSfxHover / MenuSfxConfirm / MenuSfxPlay, in the SFX
-- group) and the hover hook ButtonEffects.attach(button, { onHover = ... }) that plays them.
-- Sounds are counted by the test itself (it keeps the counts and times in PlayerGui attributes, so the next call can read
-- them): every Played event, plus every restart of a sound that is still playing (Play() on a playing sound makes no Played
-- event, but TimePosition jumps back). A sound has to start within 0.5 s of the input that caused it.
-- Wait for PlayerGui.LoadingScreen to be gone before using the mouse: its black backdrop swallows clicks for a moment
-- after the menu opens. user_mouse_input coordinates are window relative; the printed points are the centres of the
-- buttons by AbsolutePosition (the menu ignores the GUI inset), and the board points are already reduced by 58 px.
-- The mouse starts wherever the last test left it and may sweep over buttons on the way to the parking point, so each real
-- sequence parks the mouse first and only then "arms" the counters (they are zeroed), before the moves that are checked.
--   S-A   hover counts, no mouse. onHover fires once per idle -> hover change of setState, not for a repeated hover and not
--         for hover after a press, again after the button went idle; also through the real SelectionGained event; an
--         onHover that throws is contained; attach without opts still works.
--   S-B1..S-B6  real mouse on the menu, one step per call, with user_mouse_input between them:
--         B1  sets up the counters and prints the parking point. Then: moveTo the parking point.
--         B2  arms the counters, prints PLAY's centre. Then: moveTo it, wait 300, moveTo a point a few pixels off it
--             (printed too), wait 300.
--         B3  PLAY was hovered once only (moving inside it did not repeat the sound). Prints SETTINGS's centre. Then: moveTo
--             it, wait 300, left click.
--         B4  SETTINGS made the confirm sound, the scene is Settings. Prints BACK's centre. Then: moveTo it, left click.
--         B5  BACK made the confirm sound again, the scene is Menu. Prints PLAY's centre. Then: moveTo it, left click.
--         B6  PLAY made the play sound, and Play's fade did not cut it off (it ends by itself, never Stopped); the character
--             spawned.
--   S-C   a sound that did not load, no mouse: with MenuSfxConfirm's SoundId pointing at nothing, confirm() three times
--         does not error, does not play it, warns once; hover() still plays; the sound works again once the id is back.
--   S-D1..S-D5  real mouse on the Settings board's switch rows (Camera Sway is switched off for the test, Screen Effects is
--         used as the switch), one step per call:
--         D1  goes to Settings and prints the parking point, the Screen Effects row's title point and its ON / OFF button
--             point. Then: moveTo the parking point.
--         D2  arms the counters. Then: moveTo the title point, wait 300, moveTo the button point, wait 300.
--         D3  the row made the hover sound once (moving from the row onto its button did not repeat it) and no confirm yet.
--             Then: left click (the mouse is on the button).
--         D4  the click made the confirm sound once and flipped the switch. Prints the title point again. Then: moveTo it,
--             left click (the row's RowHit flips it too).
--         D5  that made the confirm sound a second time and flipped the switch back. Restores every setting.
-- The scene music (MenuAudio: SoundService.MenuMusic / SettingsMusic / CreditsMusic, in the Music group). No mouse; each M case
-- needs a FRESH playtest. They drive the menu through MainMenuClient's TestHook, as scenes.client.luau does.
--   M-A   the menu opens: MenuMusic plays, looped, in the Music group, at full volume within 2 s; the other two tracks exist
--         (looped, Music group) but do not play. Reports the music keys that did not load.
--   M-B   goTo Settings: SettingsMusic plays at full volume and MenuMusic pauses within 1.5 s; back to Menu: MenuMusic RESUMES
--         from where it paused (not from 0). goTo Credits then goTo Menu (refused: a transition is running): after 2 s exactly
--         one track is audible. Then setScene is hammered through a test copy of the module (Credits, Settings, Menu, Credits, Menu
--         about a quarter of a second apart): exactly one track is audible at the end and stays that way (no stale fade pauses it).
--   M-C   Play pressed 0.2 s after goTo Settings (mid fade to black): within 1.5 s none of the music Sounds exist, the character
--         spawns, and the SFX Sounds are untouched.
--   M-D   Play pressed in the middle of the music crossfade itself (Settings fading in, Menu fading out): same checks as M-C.
--   M-E   hover is silent once PLAY was pressed: selecting a menu button before Play makes the hover sound (the control), selecting
--         one after Play does not.
--   M-F   a track that did not load is skipped with one warning, and the others still play. Two ways: the loading screen's list
--         (PlayerGui attribute LoadingFailedSounds) names it, or it is still not loaded once the module's own load attempt is
--         over (its SoundId is pointed at nothing). Each is tried on a fresh copy of the module (a clone of the ModuleScript).
local CASE = "S-A"

local GuiService = game:GetService("GuiService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local INSET = 58
local WINDOW = 0.5 -- a sound has to start this soon after the input that caused it

local player = Players.LocalPlayer

local function waitFor(predicate, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local value = predicate()
		if value then
			return value
		end
		task.wait(0.05)
	end
	return predicate()
end

local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui missing")
local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
assert(clientScript, "MainMenuClient missing")

-- The menu is open and the loading screen is gone. Returns the MainMenu gui and the Fader.
local function waitForMenu()
	local ready = waitFor(function()
		return playerGui:GetAttribute("MenuOpen") == true and playerGui:FindFirstChild("LoadingScreen") == nil
	end, 30)
	assert(ready, "the menu did not open, and the loading screen clear, within 30s")
	local menu = playerGui:FindFirstChild("MainMenu")
	assert(menu, "MainMenu missing in PlayerGui")
	local faderGui = playerGui:FindFirstChild("MainMenuFader")
	local fader = faderGui and faderGui:FindFirstChild("Fader")
	assert(fader, "MainMenuFader.Fader missing")
	assert(
		waitFor(function()
			return fader.BackgroundTransparency > 0.99
		end, 5),
		"the Fader never cleared"
	)
	return menu, fader
end

local function getHook()
	local hook = clientScript:WaitForChild("TestHook", 10)
	assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook (BindableFunction) missing")
	return hook
end

-- The scene is `name` and settled (the Fader clear again, a few frames later still).
local function waitForScene(name, fader)
	local settled = waitFor(function()
		return playerGui:GetAttribute("MenuScene") == name and fader.BackgroundTransparency > 0.99
	end, 4)
	assert(settled, ("scene %s did not settle within 4s (MenuScene=%s)"):format(name, tostring(playerGui:GetAttribute("MenuScene"))))
	task.wait(0.15)
end

-- The three sounds, by the names ButtonSounds gives them. Each must be in the SFX group (the Sound Effects slider).
local SOUND_NAMES = { Hover = "MenuSfxHover", Confirm = "MenuSfxConfirm", Play = "MenuSfxPlay" }
local function getSound(key)
	local sound = SoundService:FindFirstChild(SOUND_NAMES[key])
	assert(sound and sound:IsA("Sound"), "SoundService." .. SOUND_NAMES[key] .. " (Sound) missing: ButtonSounds.init has not run")
	return sound
end

-- The three music tracks, by the names MenuAudio gives them. getMusic asserts the Sound is there; musicSound may return nil.
local MUSIC_SCENES = { "Menu", "Settings", "Credits" }
local MUSIC_NAMES = { Menu = "MenuMusic", Settings = "SettingsMusic", Credits = "CreditsMusic" }
local function musicSound(scene)
	local sound = SoundService:FindFirstChild(MUSIC_NAMES[scene])
	return if sound and sound:IsA("Sound") then sound else nil
end
local function getMusic(scene)
	local sound = musicSound(scene)
	assert(sound, "SoundService." .. MUSIC_NAMES[scene] .. " (Sound) missing: MenuAudio.start has not run")
	return sound
end

-- One line about each track, for failure messages.
local function describeMusic()
	local parts = {}
	for _, scene in MUSIC_SCENES do
		local sound = musicSound(scene)
		table.insert(
			parts,
			if sound
				then ("%s{Playing=%s IsPlaying=%s IsPaused=%s Volume=%.2f Time=%.2f Loaded=%s}"):format(
					sound.Name,
					tostring(sound.Playing),
					tostring(sound.IsPlaying),
					tostring(sound.IsPaused),
					sound.Volume,
					sound.TimePosition,
					tostring(sound.IsLoaded)
				)
				else MUSIC_NAMES[scene] .. "{missing}"
		)
	end
	return table.concat(parts, " ")
end

-- The scenes whose track is audible right now: it exists, plays and is above half volume.
local function audibleTracks()
	local audible = {}
	for _, scene in MUSIC_SCENES do
		local sound = musicSound(scene)
		if sound and sound.Playing and sound.Volume > 0.5 then
			table.insert(audible, scene)
		end
	end
	return audible
end

local function noMusicSounds()
	for _, scene in MUSIC_SCENES do
		if musicSound(scene) then
			return false
		end
	end
	return true
end

local function describePoint(label, point, inset)
	print(("audio: %s -> user_mouse_input x=%.0f y=%.0f"):format(label, point.X, point.Y - (inset or 0)))
end

-- Somewhere on screen with no button under it (the lower right corner of the window).
local function parkingPoint()
	local size = workspace.CurrentCamera.ViewportSize
	return Vector2.new(math.floor(size.X * 0.95), math.floor(size.Y * 0.85))
end

local function centreOf(guiObject)
	-- AbsolutePosition of the menu's buttons is already in the viewport space user_mouse_input uses (no inset to remove).
	return guiObject.AbsolutePosition + guiObject.AbsoluteSize / 2
end

-- Counters live in PlayerGui attributes: AudioCount_<label> (how often), AudioFirst_<label> and AudioLast_<label> (when).
local function bump(label)
	local now = os.clock()
	local number = (playerGui:GetAttribute("AudioCount_" .. label) or 0) + 1
	playerGui:SetAttribute("AudioCount_" .. label, number)
	if number == 1 then
		playerGui:SetAttribute("AudioFirst_" .. label, now)
	end
	playerGui:SetAttribute("AudioLast_" .. label, now)
end

local function count(label)
	return playerGui:GetAttribute("AudioCount_" .. label) or 0
end

-- Counts every start of the sound `key`: its Played events (label Sound<key>) and its restarts while it still plays
-- (label Restart<key>: Play() on a playing sound makes no Played event, but TimePosition jumps back).
local function countPlays(key)
	local sound = getSound(key)
	assert(sound.SoundGroup == SoundService:FindFirstChild("SFX"), sound.Name .. " should be in SoundService.SFX, it is in " .. tostring(sound.SoundGroup))
	playerGui:SetAttribute("AudioCount_Sound" .. key, 0)
	playerGui:SetAttribute("AudioCount_Restart" .. key, 0)
	sound.Played:Connect(function()
		bump("Sound" .. key)
	end)
	local previous = sound.TimePosition
	RunService.Heartbeat:Connect(function()
		local position = sound.TimePosition
		if sound.IsPlaying and position < previous - 0.05 then
			bump("Restart" .. key)
		end
		previous = position
	end)
	return sound
end

-- Counts a GuiButton (or Sound) event under `label`.
local function countEvent(signal, label)
	playerGui:SetAttribute("AudioCount_" .. label, 0)
	signal:Connect(function()
		bump(label)
	end)
end

-- Zeroes every counter, so what happened before this point (the mouse sweeping to its parking point) does not count.
local function arm()
	for name in playerGui:GetAttributes() do
		if string.sub(name, 1, 11) == "AudioCount_" then
			playerGui:SetAttribute(name, 0)
		elseif string.sub(name, 1, 11) == "AudioFirst_" or string.sub(name, 1, 10) == "AudioLast_" then
			playerGui:SetAttribute(name, nil)
		end
	end
end

-- How often the sound `key` started (Played events and restarts).
local function starts(key)
	return count("Sound" .. key) + count("Restart" .. key)
end

local function describeStarts(key)
	return ("%d (%d Played, %d restarts)"):format(starts(key), count("Sound" .. key), count("Restart" .. key))
end

-- The sound `key` has started `needed` times by now, the last start within WINDOW of the first time the input `label` fired.
local function expectPlay(key, needed, label)
	assert(playerGui:GetAttribute("AudioCount_" .. label) ~= nil, "run the earlier steps first, in this same playtest")
	assert(
		waitFor(function()
			return starts(key) >= needed
		end, WINDOW),
		("%s should have started %d time(s) within %.1fs of %s, it started %s (IsPlaying=%s)"):format(
			SOUND_NAMES[key],
			needed,
			WINDOW,
			label,
			describeStarts(key),
			tostring(getSound(key).IsPlaying)
		)
	)
	local inputAt = playerGui:GetAttribute("AudioFirst_" .. label)
	assert(inputAt, "the real input never reached " .. label .. " (no event); check the mouse position")
	local startedAt = math.max(playerGui:GetAttribute("AudioLast_Sound" .. key) or 0, playerGui:GetAttribute("AudioLast_Restart" .. key) or 0)
	local delay = startedAt - inputAt
	assert(math.abs(delay) <= WINDOW, ("%s started %.2fs after %s, it should be within %.1fs"):format(SOUND_NAMES[key], delay, label, WINDOW))
end

if CASE == "S-A" then
	local ButtonEffects = require(clientScript:WaitForChild("ButtonEffects", 10))
	assert(type(ButtonEffects.attach) == "function" and type(ButtonEffects.setState) == "function", "ButtonEffects.attach / setState missing")

	local scaffold = Instance.new("ScreenGui")
	scaffold.Name = "AudioTestScaffold"
	scaffold.ResetOnSpawn = false
	scaffold.Parent = playerGui
	local function newButton(name)
		local button = Instance.new("TextButton")
		button.Name = name
		button.Size = UDim2.fromOffset(120, 50)
		button.Position = UDim2.fromOffset(20, 20)
		button.Parent = scaffold
		return button
	end

	local ok, err = pcall(function()
		-- The brief's sequence: hover, hover, idle, hover is two idle -> hover changes.
		local count = 0
		local btn = newButton("Counted")
		ButtonEffects.attach(btn, {
			onHover = function()
				count += 1
			end,
		})
		assert(btn:FindFirstChild("PopScale") and btn:FindFirstChild("PopStroke"), "attach with opts should still add PopScale and PopStroke")
		assert(count == 0, "onHover must not fire on attach")
		ButtonEffects.setState(btn, "hover")
		ButtonEffects.setState(btn, "hover")
		assert(count == 1, "hovering twice in a row should fire onHover once, fired " .. count)
		ButtonEffects.setState(btn, "idle")
		assert(count == 1, "going idle must not fire onHover, fired " .. count)
		ButtonEffects.setState(btn, "hover")
		assert(count == 2, "hover, hover, idle, hover should fire onHover twice, fired " .. count)

		-- Pressing and letting go while still over the button is not a new hover.
		ButtonEffects.setState(btn, "press")
		assert(count == 2, "a press must not fire onHover, fired " .. count)
		ButtonEffects.setState(btn, "hover")
		assert(count == 2, "hover after a press (still over the button) must not fire onHover, fired " .. count)
		-- But a press that ended with the cursor off the button, then a new enter, is.
		ButtonEffects.setState(btn, "press")
		ButtonEffects.setState(btn, "idle")
		ButtonEffects.setState(btn, "hover")
		assert(count == 3, "idle then hover after a press should fire onHover, fired " .. count)
		ButtonEffects.setState(btn, "idle")

		-- The real SelectionGained event (a controller moving onto the button) counts as a hover, once.
		local selectCount = 0
		local selectable = newButton("Selectable")
		selectable.Selectable = true
		ButtonEffects.attach(selectable, {
			onHover = function()
				selectCount += 1
			end,
		})
		GuiService.SelectedObject = selectable
		assert(
			waitFor(function()
				return selectCount >= 1
			end, 1),
			"SelectionGained should fire onHover (GuiService.SelectedObject did not select the button, or the hook is not wired)"
		)
		task.wait(0.2)
		assert(selectCount == 1, "one SelectionGained should fire onHover once, fired " .. selectCount)
		-- Already hovered: a mouse enter on top of the selection does not repeat it.
		ButtonEffects.setState(selectable, "hover")
		assert(selectCount == 1, "hover while already selected must not fire onHover, fired " .. selectCount)
		GuiService.SelectedObject = nil
		task.wait(0.2)
		assert(selectCount == 1, "SelectionLost must not fire onHover, fired " .. selectCount)
		GuiService.SelectedObject = selectable
		assert(
			waitFor(function()
				return selectCount == 2
			end, 1),
			"selecting the button again after it was idle should fire onHover again, fired " .. selectCount
		)
		GuiService.SelectedObject = nil

		-- An onHover that throws is contained: setState still finishes and the pop is still applied.
		local thrower = newButton("Thrower")
		ButtonEffects.attach(thrower, {
			onHover = function()
				error("onHover boom")
			end,
		})
		local fine, why = pcall(ButtonEffects.setState, thrower, "hover")
		assert(fine, "an onHover that throws must not break setState: " .. tostring(why))
		task.wait(0.3)
		assert(math.abs(thrower.PopScale.Scale - 1.1) <= 0.01, "the pop should still play when onHover throws, Scale is " .. thrower.PopScale.Scale)

		-- No opts, and opts without onHover: unchanged behaviour.
		local plain = newButton("Plain")
		ButtonEffects.attach(plain)
		local bare = newButton("Bare")
		ButtonEffects.attach(bare, {})
		for _, button in { plain, bare } do
			ButtonEffects.setState(button, "hover")
			ButtonEffects.setState(button, "idle")
			assert(button:FindFirstChild("PopScale") and button:FindFirstChild("PopStroke"), button.Name .. " should be attached")
		end
	end)
	GuiService.SelectedObject = nil
	scaffold:Destroy()
	assert(ok, err)
elseif CASE == "S-B1" then
	local menu = waitForMenu()
	assert(player.Character == nil, "player already has a character; run this in a fresh playtest")
	local buttons = menu.Root.Buttons

	local hoverSound = countPlays("Hover")
	local confirmSound = countPlays("Confirm")
	local playSound = countPlays("Play")
	print(
		("audio: sound lengths (s): hover %.2f, confirm %.2f, play %.2f"):format(hoverSound.TimeLength, confirmSound.TimeLength, playSound.TimeLength)
	)
	assert(hoverSound.IsLoaded and confirmSound.IsLoaded and playSound.IsLoaded, "all three sounds should have loaded (see LoadingFailedSounds: " .. tostring(playerGui:GetAttribute("LoadingFailedSounds")) .. ")")

	countEvent(buttons.Play.MouseEnter, "EnterPlay")
	countEvent(buttons.Settings.Activated, "ClickSettings")
	countEvent(menu.Back.Activated, "ClickBack")
	countEvent(buttons.Play.Activated, "ClickPlay")
	countEvent(playSound.Ended, "PlayEnded")
	countEvent(playSound.Stopped, "PlayStopped")

	describePoint("parking point (no button there)", parkingPoint())
elseif CASE == "S-B2" then
	local menu = waitForMenu()
	arm()
	describePoint("PLAY centre", centreOf(menu.Root.Buttons.Play))
	describePoint("PLAY, a few pixels off centre", centreOf(menu.Root.Buttons.Play) + Vector2.new(12, 6))
elseif CASE == "S-B3" then
	local menu = waitForMenu()
	local buttons = menu.Root.Buttons
	expectPlay("Hover", 1, "EnterPlay")
	-- The mouse moved around inside PLAY, and the engine may report MouseEnter more than once for that (it does, with no
	-- MouseLeave in between): the hover sound still plays only once.
	print("audio: PLAY's MouseEnter fired " .. count("EnterPlay") .. " time(s); hover started " .. describeStarts("Hover"))
	assert(starts("Hover") == 1, "hover should have started once for PLAY, it started " .. describeStarts("Hover") .. ": moving inside the button must not repeat it")
	assert(starts("Confirm") == 0 and starts("Play") == 0, "hovering PLAY must not make the confirm or play sound")
	local mouse = UserInputService:GetMouseLocation()
	local centre = centreOf(buttons.Play)
	print(("audio: mouse is at (%.0f, %.0f); PLAY's centre is (%.0f, %.0f); GetMouseLocation y is %.0f above user_mouse_input y"):format(mouse.X, mouse.Y, centre.X, centre.Y, INSET))
	describePoint("SETTINGS centre", centreOf(buttons.Settings))
elseif CASE == "S-B4" then
	local menu, fader = waitForMenu()
	expectPlay("Confirm", 1, "ClickSettings")
	assert(count("ClickSettings") == 1, "SETTINGS should have been clicked once, got " .. count("ClickSettings"))
	assert(starts("Confirm") == 1, "confirm should have started once for the SETTINGS click, it started " .. describeStarts("Confirm"))
	assert(starts("Play") == 0, "the SETTINGS click must not make the play sound")
	waitForScene("Settings", fader)
	describePoint("BACK centre", centreOf(menu.Back))
elseif CASE == "S-B5" then
	local menu, fader = waitForMenu()
	expectPlay("Confirm", 2, "ClickBack")
	assert(count("ClickBack") == 1, "BACK should have been clicked once, got " .. count("ClickBack"))
	assert(starts("Confirm") == 2, "confirm should have started twice by now (SETTINGS, BACK), it started " .. describeStarts("Confirm"))
	assert(starts("Play") == 0, "the BACK click must not make the play sound")
	waitForScene("Menu", fader)
	describePoint("PLAY centre", centreOf(menu.Root.Buttons.Play))
elseif CASE == "S-B6" then
	expectPlay("Play", 1, "ClickPlay")
	assert(count("ClickPlay") == 1, "PLAY should have been clicked once, got " .. count("ClickPlay"))
	assert(starts("Play") == 1, "the play sound should have started once, it started " .. describeStarts("Play"))
	assert(starts("Confirm") == 2, "PLAY must not make the confirm sound, confirm has started " .. describeStarts("Confirm"))
	local sound = getSound("Play")
	-- Play's fade (0.4 s) and the menu's destruction must not cut the sound: it ends by itself and is never Stopped.
	local length = sound.TimeLength
	local finished = waitFor(function()
		return count("PlayEnded") >= 1
	end, length + 2)
	assert(count("PlayStopped") == 0, "the play sound was Stopped " .. count("PlayStopped") .. " time(s): something cut it off")
	assert(finished, ("the play sound (%.2fs long) never ended by itself within %.2fs"):format(length, length + 2))
	assert(sound.Parent == SoundService, "the play sound should still be in SoundService")
	assert(
		waitFor(function()
			return player.Character
		end, 10),
		"the character should spawn after Play"
	)
elseif CASE == "S-C" then
	local ButtonSounds = require(clientScript:WaitForChild("ButtonSounds", 10))
	assert(
		type(ButtonSounds.init) == "function"
			and type(ButtonSounds.hover) == "function"
			and type(ButtonSounds.confirm) == "function"
			and type(ButtonSounds.playSelect) == "function",
		"ButtonSounds.init / hover / confirm / playSelect missing"
	)
	-- This copy of the module finds the live Sounds by name; init is idempotent, so it makes no second set.
	local before = #SoundService:GetChildren()
	ButtonSounds.init()
	assert(#SoundService:GetChildren() == before, "ButtonSounds.init should not create a second set of sounds")
	-- Counted here, not in the PlayerGui attributes the S-B steps use, so a playtest that ran those still counts right.
	local hoverSound = getSound("Hover")
	local confirmSound = getSound("Confirm")
	local plays = { Hover = 0, Confirm = 0 }
	local connections = {
		hoverSound.Played:Connect(function()
			plays.Hover += 1
		end),
		confirmSound.Played:Connect(function()
			plays.Confirm += 1
		end),
	}
	local originalId = confirmSound.SoundId
	assert(
		waitFor(function()
			return hoverSound.IsLoaded and confirmSound.IsLoaded
		end, 10),
		"the sounds never loaded (LoadingFailedSounds: " .. tostring(playerGui:GetAttribute("LoadingFailedSounds")) .. ")"
	)
	task.wait(0.5) -- the module's own load attempt is over

	local warnings = 0
	local logConnection = LogService.MessageOut:Connect(function(message, messageType)
		if messageType == Enum.MessageType.MessageWarning and string.find(message, "ButtonSounds", 1, true) then
			warnings += 1
		end
	end)
	local ok, err = pcall(function()
		-- Healthy: confirm plays.
		ButtonSounds.confirm()
		assert(
			waitFor(function()
				return plays.Confirm == 1
			end, 1),
			"confirm() should play a healthy sound, it played " .. plays.Confirm .. " time(s)"
		)
		-- Broken: an id that is no sound. IsLoaded goes false once the new id is tried.
		confirmSound.SoundId = "rbxassetid://1"
		assert(
			waitFor(function()
				return not confirmSound.IsLoaded
			end, 5),
			"MenuSfxConfirm should not be loaded with SoundId rbxassetid://1"
		)
		task.wait(1) -- the load attempt for the new id has finished
		confirmSound:Stop()
		warnings = 0
		local playedBefore = plays.Confirm
		for call = 1, 3 do
			local fine, why = pcall(ButtonSounds.confirm)
			assert(fine, "confirm() #" .. call .. " with a sound that did not load must not error: " .. tostring(why))
		end
		task.wait(0.3)
		assert(plays.Confirm == playedBefore, "confirm() must skip a sound that did not load, it played " .. (plays.Confirm - playedBefore) .. " time(s)")
		assert(not confirmSound.IsPlaying, "confirm() must not leave a sound that did not load queued to play")
		assert(warnings == 1, "the skipped sound should be warned about once in three calls, ButtonSounds warned " .. warnings .. " time(s)")

		-- The others are unaffected.
		local hoverBefore = plays.Hover
		local fine, why = pcall(ButtonSounds.hover)
		assert(fine, "hover() must not error: " .. tostring(why))
		assert(
			waitFor(function()
				return plays.Hover == hoverBefore + 1
			end, 1),
			"hover() should still play while confirm's sound is broken"
		)
		local fine2, why2 = pcall(ButtonSounds.playSelect)
		assert(fine2, "playSelect() must not error: " .. tostring(why2))
	end)
	confirmSound.SoundId = originalId
	logConnection:Disconnect()
	local restored = ok
		and waitFor(function()
			return confirmSound.IsLoaded
		end, 10)
	if restored then
		-- Restored: the sound loads again and confirm() plays it again.
		local playedBefore = plays.Confirm
		ButtonSounds.confirm()
		restored = waitFor(function()
			return plays.Confirm == playedBefore + 1
		end, 1)
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	assert(ok, err)
	assert(restored, "confirm() should play again once its SoundId is restored and loaded")
elseif CASE:sub(1, 3) == "S-D" then
	local MenuSettings = require(clientScript:WaitForChild("MenuSettings", 10))
	local menu, fader = waitForMenu()

	local settingsRoom = workspace:WaitForChild("SettingsRoom", 10)
	local board = settingsRoom and settingsRoom:WaitForChild("Settingsboard", 10)
	assert(board and board:IsA("BasePart"), "workspace.SettingsRoom.Settingsboard missing")

	-- Where `guiObject` (at `fraction` across and down it) is on the screen, on the board's Front face.
	local function screenPointOf(gui, guiObject, fraction)
		assert(gui.Face == Enum.NormalId.Front, "screenPointOf only knows the Front face, the gui is on " .. gui.Face.Name)
		local canvas = gui.AbsoluteSize
		local pixel = guiObject.AbsolutePosition + guiObject.AbsoluteSize * fraction
		local right = (pixel.X - canvas.X / 2) / gui.PixelsPerStud
		local up = (canvas.Y / 2 - pixel.Y) / gui.PixelsPerStud
		local world = board.CFrame:PointToWorldSpace(Vector3.new(-right, up, -board.Size.Z / 2))
		local viewport, onScreen = workspace.CurrentCamera:WorldToViewportPoint(world)
		assert(onScreen, "the point is not on screen: " .. tostring(viewport))
		return Vector2.new(viewport.X, viewport.Y)
	end

	local function effectsRow()
		local gui = playerGui:FindFirstChild("SettingsBoardGui")
		assert(gui, "SettingsBoardGui missing in PlayerGui (is the scene Settings?)")
		local row = gui:FindFirstChild("EffectsRow")
		assert(row and row:FindFirstChild("Toggle") and row:FindFirstChild("RowHit"), "EffectsRow.Toggle / RowHit missing")
		return gui, row
	end

	local function restore()
		MenuSettings.set("ScreenEffects", true)
		MenuSettings.set("CameraSway", true)
	end

	if CASE == "S-D1" then
		assert(player.Character == nil, "player already has a character; run this in a fresh playtest")
		assert(getHook():Invoke("goTo", "Settings") == true, "goTo(Settings) should start a transition")
		waitForScene("Settings", fader)
		local gui, row = effectsRow()
		assert(MenuSettings.get("ScreenEffects") == true, "ScreenEffects should start on")
		MenuSettings.set("CameraSway", false)
		local camera = workspace.CurrentCamera
		assert(
			waitFor(function()
				local base = camera:GetAttribute("MenuBaseCFrame")
				return typeof(base) == "CFrame" and (camera.CFrame.LookVector - base.LookVector).Magnitude < 0.0005
			end, 5),
			"the camera never settled onto the room shot"
		)
		countPlays("Hover")
		countPlays("Confirm")
		countEvent(row.RowHit.MouseEnter, "EnterRowHit")
		countEvent(row.Toggle.MouseEnter, "EnterToggle")
		countEvent(row.RowHit.Activated, "ClickRowHit")
		countEvent(row.Toggle.Activated, "ClickToggle")
		describePoint("parking point (no button there)", parkingPoint())
		describePoint("Screen Effects row, title area", screenPointOf(gui, row, Vector2.new(0.2, 0.5)), INSET)
		describePoint("Screen Effects ON / OFF button", screenPointOf(gui, row.Toggle, Vector2.new(0.5, 0.5)), INSET)
	elseif CASE == "S-D2" then
		effectsRow()
		arm()
	elseif CASE == "S-D3" then
		local _, row = effectsRow()
		local ok, err = pcall(function()
			assert(count("EnterRowHit") >= 1, "the mouse never entered the row (RowHit), check the mouse position")
			assert(count("EnterToggle") >= 1, "the mouse never entered the ON / OFF button, check the mouse position")
			expectPlay("Hover", 1, "EnterRowHit")
			assert(starts("Hover") == 1, "the row should have made the hover sound once (the mouse went row -> button inside it), it made " .. describeStarts("Hover"))
			assert(starts("Confirm") == 0, "hovering must not make the confirm sound")
			assert(MenuSettings.get("ScreenEffects") == true, "hovering must not flip the switch")
		end)
		if not ok then
			restore()
		end
		assert(ok, err)
		print("audio: now left click where the mouse is (the ON / OFF button)")
	elseif CASE == "S-D4" then
		local gui, row = effectsRow()
		local ok, err = pcall(function()
			expectPlay("Confirm", 1, "ClickToggle")
			assert(count("ClickToggle") == 1, "the button should have been clicked once, got " .. count("ClickToggle"))
			assert(starts("Confirm") == 1, "the flip should have made the confirm sound once, it made " .. describeStarts("Confirm"))
			assert(MenuSettings.get("ScreenEffects") == false, "the click should have switched Screen Effects off")
		end)
		if not ok then
			restore()
		end
		assert(ok, err)
		describePoint("Screen Effects row, title area", screenPointOf(gui, row, Vector2.new(0.2, 0.5)), INSET)
	elseif CASE == "S-D5" then
		local _, row = effectsRow()
		local ok, err = pcall(function()
			expectPlay("Confirm", 2, "ClickRowHit")
			assert(count("ClickRowHit") == 1, "the row should have been clicked once, got " .. count("ClickRowHit"))
			assert(starts("Confirm") == 2, "the second flip should have made the confirm sound again, confirm started " .. describeStarts("Confirm"))
			assert(MenuSettings.get("ScreenEffects") == true, "the row click should have switched Screen Effects back on")
			assert(row.Toggle.Text == "ON", "the button should read ON again")
			-- Only real input and flips make the confirm sound: a change from outside the board does not.
			MenuSettings.set("ScreenEffects", false)
			task.wait(0.4)
			assert(starts("Confirm") == 2, "a change from outside the board (MenuSettings.set) must not make the confirm sound")
		end)
		restore()
		assert(ok, err)
	else
		error("unknown CASE " .. tostring(CASE))
	end
elseif CASE == "M-A" then
	waitForMenu()
	local MenuAssets = require(game:GetService("ReplicatedFirst"):WaitForChild("MenuAssets", 10))
	local musicGroup = SoundService:FindFirstChild("Music")
	assert(musicGroup and musicGroup:IsA("SoundGroup"), "SoundService.Music (SoundGroup) missing")

	-- Within 2 s of the menu being open: MenuMusic plays at full volume.
	local menuMusic = waitFor(function()
		local sound = musicSound("Menu")
		return sound and sound.Playing and sound.IsPlaying and sound.Volume > 0.9 and sound
	end, 2)
	assert(menuMusic, "MenuMusic should be playing (Volume > 0.9) within 2s of the menu opening: " .. describeMusic())
	assert(menuMusic.SoundGroup == musicGroup, "MenuMusic should be in SoundService.Music, it is in " .. tostring(menuMusic.SoundGroup))
	assert(menuMusic.Looped, "MenuMusic should loop")
	assert(menuMusic.SoundId == MenuAssets.Sounds.MenuMusic, "MenuMusic should use MenuAssets.Sounds.MenuMusic, it uses " .. menuMusic.SoundId)

	-- The other two exist, set up the same way, and are not playing.
	for _, scene in { "Settings", "Credits" } do
		local sound = getMusic(scene)
		assert(not sound.Playing, sound.Name .. " should not play on the main menu: " .. describeMusic())
		assert(sound.SoundGroup == musicGroup, sound.Name .. " should be in SoundService.Music, it is in " .. tostring(sound.SoundGroup))
		assert(sound.Looped, sound.Name .. " should loop")
		assert(sound.SoundId == MenuAssets.Sounds[sound.Name], sound.Name .. " should use MenuAssets.Sounds." .. sound.Name .. ", it uses " .. sound.SoundId)
		assert(sound.Volume < 0.01, sound.Name .. " should be at Volume 0 until its scene, it is at " .. sound.Volume)
	end
	assert(#audibleTracks() == 1, "exactly one track should be audible on the main menu: " .. describeMusic())

	-- Report the keys Roblox refused (the loading screen's list, and any track that is still not loaded).
	task.wait(1)
	local notLoaded = {}
	for _, scene in MUSIC_SCENES do
		if not getMusic(scene).IsLoaded then
			table.insert(notLoaded, MUSIC_NAMES[scene])
		end
	end
	print(
		("audio: music keys that failed to load: loading screen says [%s], not loaded now: [%s]"):format(
			tostring(playerGui:GetAttribute("LoadingFailedSounds")),
			table.concat(notLoaded, ",")
		)
	)
	assert(#notLoaded == 0, "these music tracks never loaded: " .. table.concat(notLoaded, ", "))
elseif CASE == "M-B" then
	local _, fader = waitForMenu()
	local hook = getHook()
	local menuMusic = getMusic("Menu")
	-- Let the menu track play for a while first, so a restart from 0 cannot pass for a resume.
	assert(
		waitFor(function()
			return menuMusic.IsPlaying and menuMusic.Volume > 0.9 and menuMusic.TimePosition > 2.5
		end, 10),
		"MenuMusic should be playing for 2.5s on the menu: " .. describeMusic()
	)
	local before = menuMusic.TimePosition

	-- Menu -> Settings: the Settings track plays at full volume and the Menu track pauses, within 1.5 s.
	assert(hook:Invoke("goTo", "Settings") == true, "goTo(Settings) should start a transition")
	local settingsMusic = getMusic("Settings")
	local switched = waitFor(function()
		return settingsMusic.Playing and settingsMusic.Volume > 0.9 and not menuMusic.Playing
	end, 1.5)
	assert(switched, "within 1.5s of goTo(Settings) SettingsMusic should play at full volume and MenuMusic pause: " .. describeMusic())
	assert(menuMusic.IsPaused, "MenuMusic should be paused, not stopped: " .. describeMusic())
	local pausedAt = menuMusic.TimePosition
	assert(pausedAt >= before, ("MenuMusic went back from %.2f to %.2f while it faded out"):format(before, pausedAt))
	assert(#audibleTracks() == 1 and audibleTracks()[1] == "Settings", "only the Settings track should be audible: " .. describeMusic())
	assert(not getMusic("Credits").Playing, "CreditsMusic should not play in Settings: " .. describeMusic())
	waitForScene("Settings", fader)

	-- Settings -> Menu: the Menu track resumes from where it paused.
	assert(hook:Invoke("goTo", "Menu") == true, "goTo(Menu) should start a transition")
	local back = waitFor(function()
		return menuMusic.Playing and menuMusic.Volume > 0.9 and not settingsMusic.Playing
	end, 1.5)
	assert(back, "within 1.5s of goTo(Menu) MenuMusic should play at full volume and SettingsMusic pause: " .. describeMusic())
	local resumedAt = menuMusic.TimePosition
	assert(resumedAt > before, ("MenuMusic should resume after Settings, not restart: it was at %.2f before Settings, it is at %.2f"):format(before, resumedAt))
	assert(resumedAt >= pausedAt, ("MenuMusic should resume from where it paused (%.2f), it is at %.2f"):format(pausedAt, resumedAt))
	waitForScene("Menu", fader)

	-- Credits, then Menu straight away: the second call is refused (a transition is running), so Credits stays and wins.
	assert(hook:Invoke("goTo", "Credits") == true, "goTo(Credits) should start a transition")
	assert(hook:Invoke("goTo", "Menu") == false, "goTo(Menu) straight after goTo(Credits) should be refused")
	task.wait(2)
	assert(hook:Invoke("scene") == "Credits", "the scene should be Credits, it is " .. tostring(hook:Invoke("scene")))
	local audible = audibleTracks()
	assert(#audible == 1 and audible[1] == "Credits", "after 2s in Credits exactly the Credits track should be audible: " .. describeMusic())
	assert(getMusic("Credits").IsPlaying, "CreditsMusic should be playing: " .. describeMusic())
	assert(not menuMusic.Playing and not settingsMusic.Playing, "the other two tracks should be paused: " .. describeMusic())

	-- setScene hammered (through this test's own copy of the module, which finds the Sounds by name): the earlier fades are
	-- cancelled, never stacked, and no late fade-out pauses the track that won.
	local MenuAudio = require(clientScript:WaitForChild("MenuAudio", 10))
	assert(type(MenuAudio.start) == "function" and type(MenuAudio.setScene) == "function" and type(MenuAudio.stop) == "function", "MenuAudio.start / setScene / stop missing")
	for _, scene in { "Menu", "Settings", "Credits", "Menu" } do
		local fine, why = pcall(MenuAudio.setScene, scene)
		assert(fine, "setScene(" .. scene .. ") must not error: " .. tostring(why))
		task.wait(0.25)
	end
	local settled = waitFor(function()
		local now = audibleTracks()
		return #now == 1 and now[1] == "Menu" and menuMusic.Volume > 0.95 and not getMusic("Credits").Playing and not settingsMusic.Playing
	end, 2)
	assert(settled, "after the last of 4 quick setScene calls only MenuMusic should be audible: " .. describeMusic())
	-- And it stays that way: nothing left over from the cancelled fades changes anything.
	for _ = 1, 15 do
		task.wait(0.1)
		local now = audibleTracks()
		assert(#now == 1 and now[1] == "Menu" and menuMusic.IsPlaying and menuMusic.Volume > 0.95, "a stale fade changed the music: " .. describeMusic())
		assert(getMusic("Credits").Volume < 0.01 and settingsMusic.Volume < 0.01, "a track that was faded out came back: " .. describeMusic())
	end
elseif CASE == "M-C" or CASE == "M-D" then
	-- M-C presses Play 0.2 s after goTo(Settings) (the screen is still fading to black, the music has not moved yet). M-D waits
	-- until the music itself is in the middle of its crossfade (Settings fading in, Menu fading out) and presses Play then.
	waitForMenu()
	local hook = getHook()
	local menuMusic = getMusic("Menu")
	assert(
		waitFor(function()
			return menuMusic.IsPlaying and menuMusic.Volume > 0.9
		end, 5),
		"MenuMusic should be playing before Play: " .. describeMusic()
	)
	assert(player.Character == nil, "player already has a character; run this in a fresh playtest")
	assert(hook:Invoke("goTo", "Settings") == true, "goTo(Settings) should start a transition")
	if CASE == "M-C" then
		task.wait(0.2)
	else
		local settingsMusic = getMusic("Settings")
		local mid = waitFor(function()
			return settingsMusic.Playing and settingsMusic.Volume > 0.2 and settingsMusic.Volume < 0.8 and menuMusic.Volume < 0.8 and menuMusic.Volume > 0.2
		end, 3)
		assert(mid, "the crossfade should be under way (both tracks between 0.2 and 0.8): " .. describeMusic())
	end
	print("audio: pressing Play with the music at: " .. describeMusic())
	assert(hook:Invoke("play") == true, "play should start the Play flow")

	local gone = waitFor(noMusicSounds, 1.5)
	assert(gone, "within 1.5s of Play none of the three music Sounds should exist: " .. describeMusic())
	-- Nothing comes back (no late tween or Resume): a second later still nothing.
	task.wait(1)
	assert(noMusicSounds(), "a music Sound came back after Play: " .. describeMusic())
	assert(
		waitFor(function()
			return player.Character
		end, 10),
		"the character should spawn after Play"
	)
	-- Only the music is stopped: the button sounds stay (the play sound is not cut off by Play).
	for _, name in { "MenuSfxHover", "MenuSfxConfirm", "MenuSfxPlay" } do
		assert(SoundService:FindFirstChild(name), "SoundService." .. name .. " should survive Play, MenuAudio.stop must only touch the music")
	end
elseif CASE == "M-E" then
	local menu = waitForMenu()
	local hook = getHook()
	local hoverSound = countPlays("Hover")
	assert(hoverSound.IsLoaded, "the hover sound should have loaded")
	local settingsButton = menu.Root.Buttons.Settings
	local creditsButton = menu.Root.Buttons.Credits
	assert(settingsButton.Selectable and creditsButton.Selectable, "the menu buttons should be selectable")

	-- Control: before Play, a selection (a controller moving onto the button) makes the hover sound once.
	GuiService.SelectedObject = settingsButton
	assert(
		waitFor(function()
			return starts("Hover") >= 1
		end, WINDOW),
		"before Play, selecting SETTINGS should make the hover sound (the control for this test)"
	)
	task.wait(0.3)
	assert(starts("Hover") == 1, "selecting SETTINGS once should make the hover sound once, it made " .. describeStarts("Hover"))
	GuiService.SelectedObject = nil
	task.wait(0.3)

	-- Play, then select another button while the menu is still fading out: silence.
	arm()
	assert(hook:Invoke("play") == true, "play should start the Play flow")
	assert(creditsButton:IsDescendantOf(playerGui), "the menu should still be there for the fade out")
	GuiService.SelectedObject = creditsButton
	-- A hover sound would start within a frame or two. Short, and the selection is cleared again before the menu is destroyed
	-- (a button destroyed while selected makes ButtonEffects' SelectionLost handler throw on its already removed pop).
	task.wait(0.25)
	assert(starts("Hover") == 0, "no hover sound should play once Play was pressed, it made " .. describeStarts("Hover"))
	GuiService.SelectedObject = nil
	assert(
		waitFor(function()
			return player.Character
		end, 10),
		"the character should spawn after Play"
	)
elseif CASE == "M-F" then
	waitForMenu()
	local menuMusic = getMusic("Menu")
	local settingsMusic = getMusic("Settings")
	local creditsMusic = getMusic("Credits")
	assert(
		waitFor(function()
			return menuMusic.IsPlaying and menuMusic.Volume > 0.9
		end, 5),
		"MenuMusic should be playing: " .. describeMusic()
	)
	local warnings = {}
	local logConnection = LogService.MessageOut:Connect(function(message, messageType)
		if messageType == Enum.MessageType.MessageWarning and string.find(message, "MenuAudio", 1, true) then
			table.insert(warnings, message)
		end
	end)
	local function warningsAbout(name)
		local found = 0
		for _, message in warnings do
			if string.find(message, name, 1, true) then
				found += 1
			end
		end
		return found
	end
	-- A module copy with no state of its own (the clone is a new ModuleScript, so require runs it again).
	local function freshCopy()
		local clone = clientScript:WaitForChild("MenuAudio", 10):Clone()
		clone.Parent = clientScript
		local copy = require(clone)
		clone:Destroy()
		return copy
	end
	local function expectAudible(sound, why)
		assert(
			waitFor(function()
				return sound.Playing and sound.Volume > 0.9
			end, 2.5),
			why .. ": " .. describeMusic()
		)
	end
	local settingsId = settingsMusic.SoundId
	local ok, err = pcall(function()
		-- 1. The loading screen's list names CreditsMusic: start() warns once, setScene("Credits") plays nothing and does not error.
		playerGui:SetAttribute("LoadingFailedSounds", "CreditsMusic")
		local copy = freshCopy()
		copy.start()
		task.wait(0.3)
		assert(warningsAbout("CreditsMusic") == 1, "start() should warn once about CreditsMusic, it warned " .. warningsAbout("CreditsMusic") .. " time(s)")
		for call = 1, 3 do
			local fine, why = pcall(copy.setScene, "Credits")
			assert(fine, "setScene(Credits) #" .. call .. " with a failed track must not error: " .. tostring(why))
			task.wait(0.2)
		end
		task.wait(1)
		assert(not creditsMusic.Playing, "a track the loading screen reported as failed must not play: " .. describeMusic())
		assert(#audibleTracks() == 0, "the Menu track should have faded out, nothing else plays: " .. describeMusic())
		assert(warningsAbout("CreditsMusic") == 1, "the failed track should be warned about once, it was " .. warningsAbout("CreditsMusic") .. " time(s)")
		-- The others still play.
		copy.setScene("Settings")
		expectAudible(settingsMusic, "SettingsMusic should still play while CreditsMusic is failed")
		copy.setScene("Menu")
		expectAudible(menuMusic, "MenuMusic should still play while CreditsMusic is failed")
		task.wait(1) -- SettingsMusic has faded out and paused

		-- 2. SettingsMusic points at nothing: it is still not loaded once the module's own load attempt is over.
		playerGui:SetAttribute("LoadingFailedSounds", "")
		settingsMusic.SoundId = "rbxassetid://1"
		assert(
			waitFor(function()
				return not settingsMusic.IsLoaded
			end, 5),
			"SettingsMusic should not be loaded with SoundId rbxassetid://1"
		)
		local copy2 = freshCopy()
		copy2.start()
		task.wait(2) -- its load attempt is over
		assert(warningsAbout("SettingsMusic") == 1, "the load attempt should warn once about SettingsMusic, it warned " .. warningsAbout("SettingsMusic") .. " time(s)")
		for call = 1, 3 do
			local fine, why = pcall(copy2.setScene, "Settings")
			assert(fine, "setScene(Settings) #" .. call .. " with a track that did not load must not error: " .. tostring(why))
			task.wait(0.2)
		end
		task.wait(1)
		assert(not settingsMusic.Playing, "a track that did not load must not play: " .. describeMusic())
		assert(warningsAbout("SettingsMusic") == 1, "the track that did not load should be warned about once, it was " .. warningsAbout("SettingsMusic") .. " time(s)")
		-- The others still play (CreditsMusic is not failed for this copy).
		copy2.setScene("Credits")
		expectAudible(creditsMusic, "CreditsMusic should still play while SettingsMusic did not load")
	end)
	logConnection:Disconnect()
	playerGui:SetAttribute("LoadingFailedSounds", "")
	settingsMusic.SoundId = settingsId
	assert(ok, err)
else
	error("unknown CASE " .. tostring(CASE))
end

return "PASS"
