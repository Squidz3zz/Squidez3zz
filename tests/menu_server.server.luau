-- Run in the Server datamodel during a playtest, one case at a time (set CASE below).
-- Order: A -> client fire_play (N=1) -> B -> C1 -> client fire_play (N=3) -> C2 -> D
--   A  avatar built and parked in MenuAvatars, no character yet; the developer's credit avatar built in CreditAvatars
--   B  after Play: character spawned, avatar removed (the developer's credit avatar stays)
--   C1 death respawns exactly once per death (two deaths, so stacked Died connections would show)
--   C2 repeat PlayPressed fires after the first spawn do not spawn again
--   D  cleanup (the PlayerRemoving logic, via the Studio-only TestHook) removes avatar and state
local CASE = "A"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

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

local player = waitFor(function()
	return Players:GetPlayers()[1]
end, 10)
assert(player, "no player in the playtest")
local key = tostring(player.UserId)

local function menuAvatar()
	local folder = ReplicatedStorage:FindFirstChild("MenuAvatars")
	return folder and folder:FindFirstChild(key)
end

local function testHook()
	local menuServer = ServerScriptService:FindFirstChild("MenuServer")
	local hook = menuServer and menuServer:FindFirstChild("TestHook")
	assert(hook and hook:IsA("BindableFunction"), "MenuServer.TestHook (BindableFunction) missing")
	return hook
end

-- Kills the current character and returns how many CharacterAdded events fire while it respawns.
local function killAndCountRespawns(character)
	local added = 0
	local conn = player.CharacterAdded:Connect(function()
		added += 1
	end)
	character.Humanoid.Health = 0
	task.wait(Players.RespawnTime + 2)
	conn:Disconnect()
	return added
end

if CASE == "A" then
	assert(ReplicatedStorage:FindFirstChild("MenuAvatars"), "ReplicatedStorage.MenuAvatars missing")
	local avatar = waitFor(menuAvatar, 10)
	assert(avatar, "MenuAvatars[" .. key .. "] missing after 10s")
	assert(avatar:IsA("Model"), "avatar must be a Model")
	assert(avatar:FindFirstChildOfClass("Humanoid"), "avatar has no Humanoid")
	assert(avatar:FindFirstChild("HumanoidRootPart"), "avatar has no HumanoidRootPart")
	assert(player.Character == nil, "player must not have a character before Play")
	local playPressed = ReplicatedStorage:FindFirstChild("PlayPressed")
	assert(playPressed and playPressed:IsA("RemoteEvent"), "ReplicatedStorage.PlayPressed (RemoteEvent) missing")
	assert(Players.CharacterAutoLoads == false, "CharacterAutoLoads must be false")
	assert(testHook():Invoke("state", player.UserId) == "menu", "player should be in the menu state")
	-- The developer's credit avatar: built once, in its own thread (web calls), so allow it time.
	local credit = ReplicatedStorage:FindFirstChild("CreditAvatars")
	assert(credit and credit:IsA("Folder"), "ReplicatedStorage.CreditAvatars (Folder) missing")
	local developer = waitFor(function()
		return credit:FindFirstChild("Developer")
	end, 20)
	assert(developer and developer:IsA("Model"), "CreditAvatars.Developer missing after 20s")
	assert(developer:FindFirstChildOfClass("Humanoid"), "Developer has no Humanoid")
	assert(developer:FindFirstChild("HumanoidRootPart"), "Developer has no HumanoidRootPart")
	local displayName = developer:GetAttribute("DisplayName")
	assert(type(displayName) == "string" and displayName ~= "", "Developer has no DisplayName attribute")
	-- Set before parenting, so the client can wait for the parts (the model may gain an Animator after that).
	local expected = developer:GetAttribute("DescendantCount")
	assert(type(expected) == "number" and expected > 0 and expected <= #developer:GetDescendants(), "Developer DescendantCount is wrong: " .. tostring(expected))
	return "PASS"
elseif CASE == "B" then
	local character = waitFor(function()
		return player.Character
	end, 10)
	assert(character, "player.Character is nil after PlayPressed")
	assert(character:FindFirstChildOfClass("Humanoid"), "spawned character has no Humanoid")
	assert(character:IsDescendantOf(workspace), "spawned character is not in Workspace")
	assert(menuAvatar() == nil, "MenuAvatars[" .. key .. "] should be destroyed after Play")
	assert(testHook():Invoke("state", player.UserId) == "playing", "player should be in the playing state")
	-- The developer's credit avatar is shared by everyone: Play must not remove it.
	assert(ReplicatedStorage.CreditAvatars:FindFirstChild("Developer"), "Play must not destroy the developer's credit avatar")
	return "PASS"
elseif CASE == "C1" then
	local c = player.Character
	assert(c, "no character to kill; run case B first")
	local added = killAndCountRespawns(c)
	assert(player.Character ~= c, "player did not respawn after dying")
	assert(added == 1, "first death spawned " .. added .. " characters, expected 1")
	-- A second death on the respawned character: stacked Died connections would double-spawn here.
	local second = player.Character
	added = killAndCountRespawns(second)
	assert(player.Character ~= second, "player did not respawn after the second death")
	assert(added == 1, "second death spawned " .. added .. " characters, expected 1")
	-- Record c2 for C2 (the server and client snippets share no state, so park it in ServerStorage).
	local old = ServerStorage:FindFirstChild("MenuServerTest_c2")
	if old then
		old:Destroy()
	end
	local c2 = Instance.new("ObjectValue")
	c2.Name = "MenuServerTest_c2"
	c2.Value = player.Character
	c2.Parent = ServerStorage
	return "PASS"
elseif CASE == "C2" then
	local holder = ServerStorage:FindFirstChild("MenuServerTest_c2")
	assert(holder and holder.Value, "run C1 first; MenuServerTest_c2 missing")
	local c2 = holder.Value
	holder:Destroy()
	task.wait(1)
	assert(player.Character == c2, "repeat PlayPressed fires spawned an extra character")
	return "PASS"
elseif CASE == "D" then
	local hook = testHook()
	local folder = ReplicatedStorage:FindFirstChild("MenuAvatars")
	assert(folder, "MenuAvatars missing")
	local fake = Instance.new("Model")
	fake.Name = "999"
	fake.Parent = folder
	hook:Invoke("cleanup", 999)
	assert(folder:FindFirstChild("999") == nil, "cleanup did not remove the fake avatar entry")
	-- The played flag is cleared too: the real player was playing (after B/C), now has no state.
	assert(hook:Invoke("state", player.UserId) == "playing", "expected the playing state before cleanup")
	hook:Invoke("cleanup", player.UserId)
	assert(hook:Invoke("state", player.UserId) == nil, "cleanup did not clear the player's state")
	return "PASS"
else
	error("unknown CASE: " .. tostring(CASE))
end
