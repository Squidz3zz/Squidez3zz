-- Run in the Client datamodel of a FRESH playtest (the player must not have a character yet). One case per playtest:
-- pick it with CASE below, then run the whole file as an execute_luau call. It waits for the menu to be open and the
-- loading screen to be gone (PlayerGui.MenuOpen == true and PlayerGui.LoadingScreen missing), then drives the menu through
-- MainMenuClient's Studio-only TestHook and watches the Lighting service.
-- The two rooms (Settings, Credits) sit under the map, and Roblox lights an enclosed room like an outdoor one for a few
-- seconds after the camera cuts there. RoomLighting switches the outdoor light contributions off while a room shows
-- (Brightness, OutdoorAmbient, EnvironmentDiffuseScale and EnvironmentSpecularScale all go to 0) and puts them back after.
--   A   room and back. Records the four values on the Menu (they must be non-zero, or the test proves nothing). For
--       Settings and then Credits: within 1s of MenuScene reaching the room Brightness is 0, OutdoorAmbient is black and
--       both Environment scales are 0 (Ambient and ClockTime are untouched); going back to the Menu puts all four back,
--       exactly, the moment MenuScene says Menu, and leaves no MenuRoomLighting_* attribute on Lighting. Then a hop from
--       one room straight to the other (the profile stays on), and back to the Menu (the same originals come back).
--   B   Play from a room. Goes to Credits (the profile is on), presses Play. The values are the Menu's originals again as
--       soon as the press returns (before any character exists), and still are when the character arrives (within 10s)
--       and a second later. Leaves no MenuRoomLighting_* attribute.
--   C   unit test on a separate copy of the ModuleScript (a clone, so it shares no state with the one init loaded; the
--       only thing the two can share is Lighting itself, which is why the originals are saved as attributes on it).
--       restore() with nothing saved changes nothing; apply() twice then restore() twice: the profile is on, the
--       second apply keeps the first apply's saved originals, the originals come back exactly, no attribute is left,
--       none of the calls yields (no frame passes) and none raises an error. Run it on the Menu.
local CASE = "A"

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local PROPERTIES = { "Brightness", "OutdoorAmbient", "EnvironmentDiffuseScale", "EnvironmentSpecularScale" }
local BLACK = Color3.new(0, 0, 0)
local ATTRIBUTE_PREFIX = "MenuRoomLighting_"
-- The room's profile is in place this soon after MenuScene says the room (it is set behind the black Fader, in the same
-- frame; the second is the margin the task asks for).
local PROFILE_WITHIN = 1
-- Between cuts: a transition takes 0.8s and refuses a second goTo until it lets go of its debounce.
local BETWEEN_CUTS = 0.9

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
local opened = waitFor(function()
	return playerGui:GetAttribute("MenuOpen") == true and playerGui:FindFirstChild("LoadingScreen") == nil
end, 40)
assert(opened, "the menu did not open (MenuOpen true and LoadingScreen gone) within 40s")
assert(player.Character == nil, "player already has a character; run this in a fresh playtest")
local playerScripts = player:WaitForChild("PlayerScripts", 10)
local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
assert(clientScript, "PlayerScripts.MainMenuClient missing")
local hook = clientScript:WaitForChild("TestHook", 10)
assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook (BindableFunction) missing")
-- The test starts on the Menu, and on the Menu nobody has applied the profile.
assert(hook:Invoke("scene") == "Menu", "the test must start on the Menu, scene is " .. tostring(hook:Invoke("scene")))

local function snapshot()
	local values = {}
	for _, name in PROPERTIES do
		values[name] = Lighting[name]
	end
	return values
end

local function describe(values)
	return ("Brightness=%s OutdoorAmbient=%s DiffuseScale=%s SpecularScale=%s"):format(
		tostring(values.Brightness),
		tostring(values.OutdoorAmbient),
		tostring(values.EnvironmentDiffuseScale),
		tostring(values.EnvironmentSpecularScale)
	)
end

-- The names of the MenuRoomLighting_* attributes that are on Lighting right now.
local function savedAttributes()
	local names = {}
	for name in Lighting:GetAttributes() do
		if string.sub(name, 1, #ATTRIBUTE_PREFIX) == ATTRIBUTE_PREFIX then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

local function isProfile(values)
	return values.Brightness == 0
		and values.OutdoorAmbient == BLACK
		and values.EnvironmentDiffuseScale == 0
		and values.EnvironmentSpecularScale == 0
end

-- Asserts the four values of `values` equal `original` exactly, one by one so the failure names the property.
local function assertSame(values, original, where)
	for _, name in PROPERTIES do
		assert(
			values[name] == original[name],
			("%s: %s should be back to %s but is %s"):format(where, name, tostring(original[name]), tostring(values[name]))
		)
	end
end

local function assertProfile(values, where)
	assert(values.Brightness == 0, ("%s: Brightness should be 0 but is %s (%s)"):format(where, tostring(values.Brightness), describe(values)))
	assert(
		values.OutdoorAmbient == BLACK,
		("%s: OutdoorAmbient should be black but is %s"):format(where, tostring(values.OutdoorAmbient))
	)
	assert(
		values.EnvironmentDiffuseScale == 0,
		("%s: EnvironmentDiffuseScale should be 0 but is %s"):format(where, tostring(values.EnvironmentDiffuseScale))
	)
	assert(
		values.EnvironmentSpecularScale == 0,
		("%s: EnvironmentSpecularScale should be 0 but is %s"):format(where, tostring(values.EnvironmentSpecularScale))
	)
end

-- The Menu's values, recorded before anything happened. They must be non-zero, or "the profile is on" and "the originals
-- are back" could not be told apart.
local original = snapshot()
local originalAmbient, originalClockTime = Lighting.Ambient, Lighting.ClockTime
assert(#savedAttributes() == 0, "Lighting already has MenuRoomLighting_* attributes on the Menu: " .. table.concat(savedAttributes(), ", "))
assert(
	original.Brightness ~= 0 and original.OutdoorAmbient ~= BLACK and original.EnvironmentDiffuseScale ~= 0 and original.EnvironmentSpecularScale ~= 0,
	"the Menu's own lighting must not be all zero, or this test proves nothing: " .. describe(original)
)

-- Starts a scene change (retrying through the debounce) and waits until MenuScene says `name`. Returns the time it saw it.
local function go(name)
	local started = waitFor(function()
		return hook:Invoke("goTo", name)
	end, 3)
	assert(started, "goTo(" .. name .. ") did not start a transition")
	assert(
		waitFor(function()
			return playerGui:GetAttribute("MenuScene") == name
		end, 3),
		("MenuScene never became %s (it is %s)"):format(name, tostring(playerGui:GetAttribute("MenuScene")))
	)
	return os.clock()
end

-- In a room: the profile is in place within 1s of MenuScene, and the sun-independent values are left alone.
local function assertRoom(name, seenAt)
	local profiled = waitFor(function()
		return isProfile(snapshot())
	end, PROFILE_WITHIN)
	local took = os.clock() - seenAt
	assertProfile(snapshot(), name .. " (" .. string.format("%.2f", took) .. "s after MenuScene)")
	assert(profiled and took <= PROFILE_WITHIN + 0.1, name .. ": the profile took " .. took .. "s to appear")
	assert(Lighting.Ambient == originalAmbient, name .. ": Ambient must stay " .. tostring(originalAmbient) .. ", is " .. tostring(Lighting.Ambient))
	assert(Lighting.ClockTime == originalClockTime, name .. ": ClockTime must stay " .. originalClockTime .. ", is " .. tostring(Lighting.ClockTime))
	assert(Lighting:FindFirstChildOfClass("Sky") and Lighting:FindFirstChildOfClass("Atmosphere"), name .. ": Sky and Atmosphere must stay")
	return took
end

-- On the Menu again: the moment MenuScene says Menu (the exit hook runs before that), all four are exactly the originals.
local function assertMenu(where)
	assert(playerGui:GetAttribute("MenuScene") == "Menu", where .. ": not on the Menu")
	assertSame(snapshot(), original, where)
	local left = savedAttributes()
	assert(#left == 0, where .. ": attributes left on Lighting: " .. table.concat(left, ", "))
end

local report = {}

if CASE == "A" then
	for _, room in { "Settings", "Credits" } do
		local took = assertRoom(room, go(room))
		table.insert(report, ("%s profile after %.2fs"):format(room, took))
		task.wait(BETWEEN_CUTS)
		go("Menu")
		assertMenu("back from " .. room)
		table.insert(report, "Menu restored after " .. room)
		task.wait(BETWEEN_CUTS)
	end
	-- Room to room: the profile stays on, and the originals that come back at the end are still the Menu's.
	assertRoom("Settings", go("Settings"))
	task.wait(BETWEEN_CUTS)
	assertRoom("Credits (from Settings)", go("Credits"))
	assert(#savedAttributes() == #PROPERTIES, "going room to room should keep exactly one saved original per property")
	task.wait(BETWEEN_CUTS)
	go("Menu")
	assertMenu("back from Settings -> Credits")
	table.insert(report, "Settings -> Credits -> Menu restored")
elseif CASE == "B" then
	assertRoom("Credits", go("Credits"))
	task.wait(BETWEEN_CUTS)
	local started = hook:Invoke("play")
	assert(started == true, "Invoke(play) should start Play")
	-- runPlay restores before its first yield, so by the time Invoke returns no character exists and the values are back.
	assert(player.Character == nil, "no character should exist yet when the press returns")
	assertSame(snapshot(), original, "right after the Play press")
	local character = waitFor(function()
		return player.Character
	end, 10)
	assert(character, "no character within 10s of Play")
	assertSame(snapshot(), original, "when the character arrived")
	task.wait(1)
	assertSame(snapshot(), original, "1s after the character arrived")
	local left = savedAttributes()
	assert(#left == 0, "attributes left on Lighting after Play: " .. table.concat(left, ", "))
	table.insert(report, "Play from Credits: lighting back before any character, and stayed")
elseif CASE == "C" then
	local moduleScript = clientScript:WaitForChild("RoomLighting", 10)
	assert(moduleScript and moduleScript:IsA("ModuleScript"), "MainMenuClient.RoomLighting (ModuleScript) missing")
	local RoomLighting = require(moduleScript:Clone())
	assert(type(RoomLighting.apply) == "function" and type(RoomLighting.restore) == "function", "RoomLighting needs apply and restore")

	-- A yield inside any call would let a frame pass: count frames across all of them.
	local frames = 0
	local counter = RunService.Heartbeat:Connect(function()
		frames += 1
	end)
	local ok, err = pcall(function()
		-- Nothing saved yet: restore must leave a value somebody else changed alone.
		Lighting.Brightness = original.Brightness + 1
		RoomLighting.restore()
		assert(Lighting.Brightness == original.Brightness + 1, "restore() with nothing saved should change nothing")
		Lighting.Brightness = original.Brightness
		assert(#savedAttributes() == 0, "restore() with nothing saved should leave no attribute")

		RoomLighting.apply()
		assertProfile(snapshot(), "after apply")
		local savedAfterFirst = {}
		for _, name in PROPERTIES do
			savedAfterFirst[name] = Lighting:GetAttribute(ATTRIBUTE_PREFIX .. name)
			assert(
				savedAfterFirst[name] == original[name],
				("apply() should save the original %s (%s) as the attribute %s%s, found %s"):format(
					name,
					tostring(original[name]),
					ATTRIBUTE_PREFIX,
					name,
					tostring(savedAfterFirst[name])
				)
			)
		end
		assert(Lighting.Ambient == originalAmbient and Lighting.ClockTime == originalClockTime, "apply() must leave Ambient and ClockTime alone")

		RoomLighting.apply()
		assertProfile(snapshot(), "after the second apply")
		for _, name in PROPERTIES do
			assert(
				Lighting:GetAttribute(ATTRIBUTE_PREFIX .. name) == savedAfterFirst[name],
				("the second apply() overwrote the saved original of %s: %s -> %s"):format(
					name,
					tostring(savedAfterFirst[name]),
					tostring(Lighting:GetAttribute(ATTRIBUTE_PREFIX .. name))
				)
			)
		end

		RoomLighting.restore()
		assertSame(snapshot(), original, "after restore")
		assert(#savedAttributes() == 0, "restore() should remove the attributes, left: " .. table.concat(savedAttributes(), ", "))
		RoomLighting.restore()
		assertSame(snapshot(), original, "after the second restore")
		assert(#savedAttributes() == 0, "attributes appeared after the second restore")
	end)
	counter:Disconnect()
	-- However the test went, leave the Menu's lighting as it was found.
	pcall(function()
		RoomLighting.restore()
	end)
	for _, name in PROPERTIES do
		Lighting[name] = original[name]
		Lighting:SetAttribute(ATTRIBUTE_PREFIX .. name, nil)
	end
	assert(ok, tostring(err))
	assert(frames == 0, "apply/restore yielded: " .. frames .. " frames passed during the calls")
	table.insert(report, "apply x2, restore x2 on a separate copy: originals back, no yield, no error")
else
	error("unknown CASE " .. tostring(CASE))
end

return "PASS " .. CASE .. ": " .. table.concat(report, "; ")
