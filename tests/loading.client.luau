-- Run in the Client datamodel of a FRESH playtest, and run it FIRST: it must be the first execute_luau call after the
-- playtest starts. Pick the case with CASE below, then run the whole file as an execute_luau call.
-- Tests ReplicatedFirst.LoadingScreen (and the menu waiting for it) through the attributes it leaves on the PlayerGui,
-- because the loading gui is destroyed once the menu is open, long before a late test call could look inside it.
--   A  the loading screen runs and hands over to the menu. It built Title, Spinner and Tip (LoadingParts), stayed up
--      for at least LOADING_MIN_SECONDS and at most LOADING_MAX_SECONDS (+ the fade), cycled its tip when it lasted
--      long enough, and is gone shortly after the menu opened. The menu opened only after LoadingDone. Prints the
--      keys of the sounds Roblox refused to load (LoadingFailedSounds), so the user learns which asset ids need fixing.
--   B  run with the LoadingScreen script disabled (in Edit, set ReplicatedFirst.LoadingScreen.Disabled = true, start a
--      fresh playtest, run this, stop the playtest, and set Disabled back to false). The menu still opens, there is no
--      loading gui, and Play still spawns the character: a missing loading screen never stops the menu or Play.
local CASE = "A"

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local player = Players.LocalPlayer

-- The timing constants live in ReplicatedFirst.MenuAssets; these are only used if that module is missing or broken.
local LOADING_MIN_SECONDS = 2
local LOADING_MAX_SECONDS = 20
local TIP_SECONDS = 4
local assetsModule = ReplicatedFirst:FindFirstChild("MenuAssets")
if assetsModule then
	local ok, assets = pcall(require, assetsModule)
	if ok and type(assets) == "table" then
		LOADING_MIN_SECONDS = assets.LOADING_MIN_SECONDS or LOADING_MIN_SECONDS
		LOADING_MAX_SECONDS = assets.LOADING_MAX_SECONDS or LOADING_MAX_SECONDS
		TIP_SECONDS = assets.TIP_SECONDS or TIP_SECONDS
	end
end

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

local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "PlayerGui missing")

if CASE == "A" then
	-- The menu opens by itself once the loading screen has handed over (at most LOADING_MAX_SECONDS, plus the preload
	-- and the fade).
	local opened = waitFor(function()
		return playerGui:GetAttribute("MenuOpen") == true
	end, 30)
	assert(opened, "MenuOpen did not become true within 30s")

	local shownAt = playerGui:GetAttribute("LoadingShownAt")
	assert(type(shownAt) == "number", "LoadingShownAt missing: the loading screen never showed")
	-- The menu waits for the loading screen before it parents anything, so LoadingDone is already true when it opens.
	assert(
		playerGui:GetAttribute("LoadingDone") == true,
		"the menu opened before the loading screen was done: LoadingDone is " .. tostring(playerGui:GetAttribute("LoadingDone"))
	)
	local doneAt = playerGui:GetAttribute("LoadingDoneAt")
	assert(type(doneAt) == "number", "LoadingDoneAt missing")

	-- The gui is already gone (or going), so what it built is read from the attribute the script left behind.
	local parts = playerGui:GetAttribute("LoadingParts")
	assert(type(parts) == "string", "LoadingParts missing")
	local built = {}
	for name in string.gmatch(parts, "[^,]+") do
		built[name] = true
	end
	for _, name in { "Title", "Spinner", "Tip" } do
		assert(built[name], "the loading screen did not build its " .. name .. " (LoadingParts is '" .. parts .. "')")
	end

	-- It stays up for at least LOADING_MIN_SECONDS (LoadingDoneAt is stamped after the 0.4s fade to black, so this is
	-- loose) and hands over at the latest at LOADING_MAX_SECONDS.
	local elapsed = doneAt - shownAt
	assert(
		elapsed >= LOADING_MIN_SECONDS - 0.05,
		"the loading screen was up for only " .. string.format("%.2f", elapsed) .. "s, the minimum is " .. LOADING_MIN_SECONDS
	)
	assert(
		elapsed <= LOADING_MAX_SECONDS + 1,
		"the loading screen was up for " .. string.format("%.2f", elapsed) .. "s, the maximum is " .. LOADING_MAX_SECONDS
	)

	-- The tip changes every TIP_SECONDS, and a change lands a frame or two late, so only a screen that lasted a little
	-- longer than TIP_SECONDS has to have changed.
	local tipChanges = playerGui:GetAttribute("LoadingTipChanges")
	assert(type(tipChanges) == "number", "LoadingTipChanges missing")
	if elapsed >= TIP_SECONDS + 0.2 then
		assert(
			tipChanges >= 1,
			"the loading screen lasted " .. string.format("%.2f", elapsed) .. "s but its tip never changed"
		)
	else
		print("loading: the screen lasted " .. string.format("%.2f", elapsed) .. "s, too short to expect a tip change; skipped")
	end

	-- Its own fade out takes 0.4s after the menu opened, so it is gone well within 2s of MenuOpen.
	local gone = waitFor(function()
		return playerGui:FindFirstChild("LoadingScreen") == nil
	end, 2)
	assert(gone, "PlayerGui.LoadingScreen was still there 2s after the menu opened")

	-- The Studio-only TestHook reports the same state.
	local loadingScript = ReplicatedFirst:FindFirstChild("LoadingScreen")
	local hook = loadingScript and loadingScript:FindFirstChild("TestHook")
	assert(hook and hook:IsA("BindableFunction"), "ReplicatedFirst.LoadingScreen.TestHook (BindableFunction) missing")
	local state = hook:Invoke("state")
	assert(type(state) == "table", "TestHook state should be a table")
	assert(state.done == true, "TestHook state.done should be true after the handoff")
	local failed = playerGui:GetAttribute("LoadingFailedSounds")
	assert(type(failed) == "string", "LoadingFailedSounds missing (it should be a string, empty if none failed)")
	assert(state.failed == failed, "TestHook state.failed should match the LoadingFailedSounds attribute")

	-- Reported to the user: the sounds Roblox refused (asset permissions or a bad id), by key.
	print("loading: screen up for " .. string.format("%.2f", elapsed) .. "s, " .. tipChanges .. " tip change(s)")
	if failed == "" then
		print("loading: LoadingFailedSounds = (none) all six sounds loaded")
	else
		warn("loading: LoadingFailedSounds = " .. failed .. "  <- Roblox refused these sounds; fix their asset permissions or ids")
	end
elseif CASE == "B" then
	local loadingScript = ReplicatedFirst:FindFirstChild("LoadingScreen")
	assert(loadingScript, "ReplicatedFirst.LoadingScreen does not exist")
	assert(loadingScript.Disabled == true, "case B needs ReplicatedFirst.LoadingScreen.Disabled = true (set it in Edit first)")

	local opened = waitFor(function()
		return playerGui:GetAttribute("MenuOpen") == true
	end, LOADING_MAX_SECONDS + 6)
	assert(opened, "MenuOpen did not become true within " .. (LOADING_MAX_SECONDS + 6) .. "s with the loading screen disabled")
	-- The menu must not sit out its timeout for a loading screen that can never hand over. A wait that long would put
	-- MenuOpen past LOADING_MAX_SECONDS + 5 on the game's clock; this test is run right after the playtest starts, so it
	-- sees the menu opened long before that (time() is seconds since the game began running).
	print("loading B: the menu was open " .. string.format("%.1f", time()) .. "s into the game")
	assert(
		time() < LOADING_MAX_SECONDS + 5,
		"the menu only opened " .. string.format("%.1f", time()) .. "s into the game: it waited for the disabled loading screen"
	)
	assert(playerGui:FindFirstChild("LoadingScreen") == nil, "there should be no PlayerGui.LoadingScreen with the script disabled")
	assert(playerGui:GetAttribute("LoadingShownAt") == nil, "LoadingShownAt should not exist with the script disabled")
	assert(player.Character == nil, "player already has a character; run this in a fresh playtest")

	-- Play still works.
	local playerScripts = player:WaitForChild("PlayerScripts", 10)
	local clientScript = playerScripts and playerScripts:WaitForChild("MainMenuClient", 10)
	local hook = clientScript and clientScript:WaitForChild("TestHook", 10)
	assert(hook and hook:IsA("BindableFunction"), "MainMenuClient.TestHook (BindableFunction) missing")
	assert(hook:Invoke("play") == true, "play() should start the Play flow")
	local character = waitFor(function()
		return player.Character
	end, 10)
	assert(character, "player.Character is nil 10s after play() with the loading screen disabled")
else
	error("unknown CASE " .. tostring(CASE))
end

return "PASS"
