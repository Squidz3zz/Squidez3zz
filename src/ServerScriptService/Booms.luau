-- Booms: the one boom every explosion in the game makes. Booms.at(position) fires ReplicatedStorage.BoomEvent (made here if it
-- is missing) to every player, and each player's BoomClient shows the user's explosion there (the particles and the layered
-- sounds in ReplicatedStorage.LabAssets.Explosion) and shakes the camera. It never yields. It only shows and plays: any damage is
-- up to the caller (HardDriveEffects does its own; an Explosion instance keeps its own physics, see ExplosionReplacer).
-- In Studio it counts every boom in its own BoomCount attribute, for the tests.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local event = ReplicatedStorage:FindFirstChild("BoomEvent")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "BoomEvent"
	event.Parent = ReplicatedStorage
end
local counting = RunService:IsStudio()

local Booms = {}

function Booms.at(position: Vector3)
	event:FireAllClients(position)
	if counting then
		script:SetAttribute("BoomCount", (script:GetAttribute("BoomCount") or 0) + 1)
	end
end

return Booms
