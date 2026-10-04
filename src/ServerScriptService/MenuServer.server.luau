-- MenuServer: holds each player on the main menu (no character) until they press Play.
-- Builds a menu avatar per player, spawns them once on PlayPressed, then respawns them after death.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

Players.CharacterAutoLoads = false

local function getOrCreate(className, name)
	local instance = ReplicatedStorage:FindFirstChild(name)
	if not instance then
		instance = Instance.new(className)
		instance.Name = name
		instance.Parent = ReplicatedStorage
	end
	return instance
end

local playPressed = getOrCreate("RemoteEvent", "PlayPressed")
local menuAvatars = getOrCreate("Folder", "MenuAvatars")

-- userId -> "menu" (waiting on the menu) or "playing" (Play was pressed). nil once the player is gone.
local sessions = {}

local function getDescription(userId)
	for attempt = 1, 2 do
		local ok, desc = pcall(Players.GetHumanoidDescriptionFromUserId, Players, userId)
		if ok then
			return desc
		end
		if attempt == 1 then
			task.wait(1)
		end
	end
	return Instance.new("HumanoidDescription")
end

local function getRigType(userId)
	local ok, info = pcall(Players.GetCharacterAppearanceInfoAsync, Players, userId)
	if ok and info.playerAvatarType == "R6" then
		return Enum.HumanoidRigType.R6
	end
	return Enum.HumanoidRigType.R15
end

local function createModel(desc, rigType)
	local ok, model = pcall(Players.CreateHumanoidModelFromDescription, Players, desc, rigType)
	return ok and model or nil
end

local function buildAvatar(player)
	local userId = player.UserId
	local rigType = getRigType(userId)
	local model = createModel(getDescription(userId), rigType)
		or createModel(Instance.new("HumanoidDescription"), rigType)
	if not model then
		warn("MenuServer: could not build a menu avatar for " .. player.Name)
		return
	end
	-- The player may have pressed Play or left while the avatar was being built.
	if sessions[userId] ~= "menu" then
		model:Destroy()
		return
	end
	model.Name = tostring(userId)
	-- Lets the client wait until every part has replicated before it clones the model (see MainMenuClient).
	model:SetAttribute("DescendantCount", #model:GetDescendants())
	model.Parent = menuAvatars
end

local function destroyAvatar(userId)
	local avatar = menuAvatars:FindFirstChild(tostring(userId))
	if avatar then
		avatar:Destroy()
	end
end

-- Shared by PlayerRemoving and the Studio test hook.
local function cleanup(userId)
	destroyAvatar(userId)
	sessions[userId] = nil
end

-- Wired once per player, after their first spawn. Humanoid.Died is connected per character,
-- so connections never stack across respawns.
local function wireRespawn(player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid").Died:Once(function()
			task.wait(Players.RespawnTime)
			if player.Parent then
				player:LoadCharacter()
			end
		end)
	end)
end

local function onPlayPressed(player)
	local userId = player.UserId
	if sessions[userId] ~= "menu" then
		return
	end
	sessions[userId] = "playing"
	destroyAvatar(userId)
	wireRespawn(player)
	-- The latch above stays set even if this fails, so a repeated PlayPressed cannot spawn twice.
	local ok, err = pcall(player.LoadCharacter, player)
	if not ok then
		warn("MenuServer: LoadCharacter failed for " .. player.Name .. ": " .. tostring(err))
	end
end

local function onPlayerAdded(player)
	sessions[player.UserId] = "menu"
	buildAvatar(player)
end

playPressed.OnServerEvent:Connect(onPlayPressed)
Players.PlayerRemoving:Connect(function(player)
	cleanup(player.UserId)
end)
Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

if RunService:IsStudio() then
	-- Test hook for tests/menu_server.server.luau (execute_luau cannot reach this script's locals).
	local hook = Instance.new("BindableFunction")
	hook.Name = "TestHook"
	hook.OnInvoke = function(action, userId)
		if action == "cleanup" then
			cleanup(userId)
		elseif action == "state" then
			return sessions[userId]
		else
			error("TestHook: unknown action " .. tostring(action))
		end
	end
	hook.Parent = script
end
