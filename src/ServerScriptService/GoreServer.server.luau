-- GoreServer: starts the gore system on the server. It loads Gore (ServerScriptService.Gore) and tracks every player's
-- character as it spawns (Gore.track), so every character's limbs keep score, break, dangle and come off, and every death
-- ragdolls and leaves a corpse (Gore and its Ragdoll do the rest, including removing old corpses). A character Gore fails to
-- track only warns (once) and plays on without gore. Every BLEED_TICK seconds it bleeds every open body (Gore.bleed, with the
-- time since the last tick); a failed tick only warns (once).
-- ReplicatedStorage.GoreReset: a RemoteEvent this makes, which each player's GoreReset.client fires from the Reset Character
-- button. It kills the sender's own character, only while it is alive, through Gore.hurt (so the reset is no hit and no limb
-- is damaged); it reads nothing else the client sends.
-- TestHook: a BindableFunction inside this script, made only in Studio. A test that requires Gore gets a separate copy of it
-- (its own Random, links and hit watchers), so the tests reach the game's own Gore through this instead:
-- TestHook:Invoke("call", fnName, ...) calls Gore[fnName](...) here and returns what it returns.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Gore = require(script.Parent:WaitForChild("Gore"))

local BLEED_TICK = 0.25

local warned = false
local function onCharacter(character: Model)
	character:WaitForChild("Humanoid", 5)
	local ok, err = pcall(Gore.track, character)
	if not ok and not warned then
		warned = true
		warn("GoreServer: Gore could not track " .. character.Name .. ": " .. tostring(err))
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end

local reset = Instance.new("RemoteEvent")
reset.Name = "GoreReset"
reset.OnServerEvent:Connect(function(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		local ok = pcall(Gore.hurt, character, math.huge)
		if not ok then
			humanoid.Health = 0
		end
	end
end)
reset.Parent = ReplicatedStorage

task.spawn(function()
	local bleedWarned = false
	while true do
		local ok, err = pcall(Gore.bleed, task.wait(BLEED_TICK))
		if not ok and not bleedWarned then
			bleedWarned = true
			warn("GoreServer: bleeding failed: " .. tostring(err))
		end
	end
end)

if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "TestHook"
	hook.OnInvoke = function(action, fnName, ...)
		if action == "call" and type(Gore[fnName]) == "function" then
			return Gore[fnName](...)
		end
		error("TestHook: unknown action " .. tostring(action) .. " " .. tostring(fnName))
	end
	hook.Parent = script
end
