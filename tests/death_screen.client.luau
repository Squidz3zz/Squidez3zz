-- Run in a playtest, after tests/fire_play.client.luau (so the player has a character). Three calls, in this order:
--   D-1  Client, CASE = "D-1": arms the check. When the local Humanoid dies it records, one frame later (RenderStepped), the
--        black frame's transparency, whether DeathRing is playing and every SoundGroup's volume, as PlayerGui attributes.
--   D-2  Server, one line:  game:GetService("Players"):GetPlayers()[1].Character.Humanoid.Health = 0
--   D-3  Client, CASE = "D-3": the recorded frame was fully black, the ring was playing and every SoundGroup was silent; then,
--        once the new character has been there for 2 s, the black is gone and every SoundGroup is back at the volume the death
--        screen saved (the attribute DeathSavedVolume). If the character has a "Died" Sound, it must be silent.
local CASE = "D-1"

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

local function groups()
	local list = {}
	for _, thing in SoundService:GetDescendants() do
		if thing:IsA("SoundGroup") then
			table.insert(list, thing)
		end
	end
	return list
end

local function clear()
	for name in playerGui:GetAttributes() do
		if string.sub(name, 1, 3) == "D1_" then
			playerGui:SetAttribute(name, nil)
		end
	end
end

if CASE == "D-1" then
	clear()
	local character = waitFor(function()
		return player.Character
	end, 10)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	assert(humanoid and humanoid.Health > 0, "no live character: run tests/fire_play.client.luau first")
	assert(#groups() >= 2, "SoundService should hold the Music and SFX SoundGroups")

	humanoid.Died:Once(function()
		RunService.RenderStepped:Once(function()
			local screen = playerGui:FindFirstChild("DeathScreen")
			local black = screen and screen:FindFirstChild("Black")
			local ring = SoundService:FindFirstChild("DeathRing")
			playerGui:SetAttribute("D1_Black", if black then black.BackgroundTransparency else -1)
			playerGui:SetAttribute("D1_Ring", ring ~= nil and ring.IsPlaying)
			for _, group in groups() do
				playerGui:SetAttribute("D1_Group_" .. group.Name, group.Volume)
			end
			playerGui:SetAttribute("D1_Recorded", true)
		end)
		player.CharacterAdded:Once(function()
			playerGui:SetAttribute("D1_NewCharacterAt", os.clock())
		end)
	end)
	return "PASS death_screen D-1 (armed: now run D-2 on the Server)"
elseif CASE == "D-3" then
	assert(waitFor(function()
		return playerGui:GetAttribute("D1_Recorded")
	end, 10), "D-1 recorded nothing: was it run, and did the player die?")

	assert(playerGui:GetAttribute("D1_Black") == 0, "one frame after the death the black was not fully opaque (BackgroundTransparency "
		.. tostring(playerGui:GetAttribute("D1_Black")) .. "; -1 means PlayerGui.DeathScreen.Black is missing)")
	assert(playerGui:GetAttribute("D1_Ring") == true, "SoundService.DeathRing was not playing one frame after the death")
	local names = {}
	for name, value in playerGui:GetAttributes() do
		if string.sub(name, 1, 9) == "D1_Group_" then
			table.insert(names, name)
			assert(value == 0, name .. " was not silent one frame after the death (volume " .. tostring(value) .. ")")
		end
	end
	assert(#names >= 2, "D-1 recorded no SoundGroups")

	local at = waitFor(function()
		return playerGui:GetAttribute("D1_NewCharacterAt")
	end, 15)
	assert(at, "no new character after the death")
	task.wait(math.max(0, 2 - (os.clock() - at)))

	local black = playerGui.DeathScreen.Black
	assert(black.BackgroundTransparency == 1, "2 s after the respawn the black is still showing (BackgroundTransparency "
		.. black.BackgroundTransparency .. ")")
	local checked = 0
	for _, group in groups() do
		local saved = group:GetAttribute("DeathSavedVolume")
		assert(saved ~= nil, group.Name .. " has no DeathSavedVolume")
		assert(group.Volume == saved, ("%s is at %s, not back at its saved %s"):format(group.Name, tostring(group.Volume), tostring(saved)))
		checked += 1
	end
	local note = ""
	local died = player.Character and player.Character:FindFirstChild("Died", true)
	if died and died:IsA("Sound") then
		assert(died.Volume == 0, "the character's own Died sound is not silent")
		note = ", the character's Died sound is silent"
	end
	clear()
	return ("PASS death_screen D-3 (%d SoundGroups saved, silenced and restored%s)"):format(checked, note)
end
error("unknown CASE " .. tostring(CASE))
