-- Booms: the one boom every explosion in the game makes. Booms.at(position, blood) fires ReplicatedStorage.BoomEvent (made here
-- if it is missing) to every player with (position, blood == true), and each player's BoomClient shows the user's explosion there
-- (the particles and the layered sounds in ReplicatedStorage.LabAssets.Explosion), with a blood burst and splats on the floor
-- when blood is true (LabAssets.Blood), and shakes the camera. It never yields. It only shows and plays: any damage is up to the
-- caller (HardDriveEffects does its own; an Explosion instance keeps its own physics, see ExplosionReplacer).
-- In Studio it counts every boom in its own BoomCount attribute, and the blood ones in BloodCount, for the tests.
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

function Booms.at(position: Vector3, blood: boolean?)
	event:FireAllClients(position, blood == true)
	if counting then
		script:SetAttribute("BoomCount", (script:GetAttribute("BoomCount") or 0) + 1)
		if blood then
			script:SetAttribute("BloodCount", (script:GetAttribute("BloodCount") or 0) + 1)
		end
	end
end

return Booms
