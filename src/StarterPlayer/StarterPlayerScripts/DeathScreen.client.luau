-- DeathScreen: every death in the game cuts to black and rings in the ears. On the local character's Humanoid.Died, in the same frame:
--   * PlayerGui.DeathScreen.Black (a full-screen black Frame, always there, transparent when idle) goes fully opaque;
--   * every SoundGroup under SoundService is silenced (its volume is kept in its DeathSavedVolume attribute);
--   * SoundService.DeathRing (in no group, so it stays audible) plays at full volume and fades to nothing over RESPAWN_TIME;
--   * the "Died" Sound Roblox puts in every character gets Volume 0 as soon as it appears.
-- On the next CharacterAdded the black fades out over FADE_IN seconds and every SoundGroup goes back to its saved volume. The script
-- works with no character (before Play) and across any number of deaths: it wires each character once, through Humanoid.Died:Once.
-- LabConfig (RESPAWN_TIME and Sounds.DeathRing) is optional: without it the ring fades over 5 s, and there is no ring.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local FADE_IN = 1.5

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local respawnTime, ringId = 5, nil
local ok, config = pcall(require, ReplicatedStorage:WaitForChild("LabConfig", 10))
if ok and type(config) == "table" then
	if type(config.RESPAWN_TIME) == "number" and config.RESPAWN_TIME > 0 then
		respawnTime = config.RESPAWN_TIME
	end
	if type(config.Sounds) == "table" and type(config.Sounds.DeathRing) == "string" then
		ringId = config.Sounds.DeathRing
	end
else
	warn("DeathScreen: ReplicatedStorage.LabConfig did not load, so there is no ear ringing and it fades over 5 s: " .. tostring(config))
end

local gui = Instance.new("ScreenGui")
gui.Name = "DeathScreen"
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.DisplayOrder = 100 -- above the menu's screens (up to about 20) and the lab's tablet menu
gui.ResetOnSpawn = false
local black = Instance.new("Frame")
black.Name = "Black"
black.Size = UDim2.fromScale(1, 1)
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BackgroundTransparency = 1
black.BorderSizePixel = 0
black.Parent = gui
gui.Parent = playerGui

local ring
if ringId then
	ring = Instance.new("Sound")
	ring.Name = "DeathRing"
	ring.SoundId = ringId
	ring.Volume = 0
	ring.Parent = SoundService
	-- Loaded now, so it plays the frame the player dies.
	task.spawn(pcall, ContentProvider.PreloadAsync, ContentProvider, { ring })
end

local silenced = false -- true from a death until the next character arrives
local fadeIn, ringFade

local function forEachGroup(fn)
	for _, thing in SoundService:GetDescendants() do
		if thing:IsA("SoundGroup") then
			fn(thing)
		end
	end
end

local function die()
	if fadeIn then
		fadeIn:Cancel()
	end
	black.BackgroundTransparency = 0
	if not silenced then
		silenced = true
		forEachGroup(function(group)
			group:SetAttribute("DeathSavedVolume", group.Volume)
			group.Volume = 0
		end)
	end
	if ring then
		if ringFade then
			ringFade:Cancel()
		end
		ring.Volume = 1
		ring.TimePosition = 0
		ring:Play()
		ringFade = TweenService:Create(ring, TweenInfo.new(respawnTime, Enum.EasingStyle.Linear), { Volume = 0 })
		ringFade:Play()
	end
end

local function recover()
	if not silenced then
		return
	end
	silenced = false
	fadeIn = TweenService:Create(black, TweenInfo.new(FADE_IN), { BackgroundTransparency = 1 })
	fadeIn:Play()
	forEachGroup(function(group)
		local saved = group:GetAttribute("DeathSavedVolume")
		if saved then
			group.Volume = saved
		end
	end)
end

local function onCharacter(character)
	recover()
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		humanoid.Died:Once(die)
	end
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- Roblox's own death sound (a "Sound" named Died under a character's HumanoidRootPart) is silenced, on any character, as it appears.
local function quietDied(thing)
	if thing:IsA("Sound") and thing.Name == "Died" then
		local model = thing:FindFirstAncestorOfClass("Model")
		if model and model:FindFirstChildOfClass("Humanoid") then
			thing.Volume = 0
		end
	end
end
workspace.DescendantAdded:Connect(quietDied)
for _, thing in workspace:GetDescendants() do
	quietDied(thing)
end
