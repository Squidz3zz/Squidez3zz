-- Run in the Client datamodel during a playtest. Fires PlayPressed N times.
-- N=1 for the first spawn (before case B), N=3 for the repeat-fire check (before case C2).
local N = 1

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local playPressed = ReplicatedStorage:WaitForChild("PlayPressed", 10)
assert(playPressed and playPressed:IsA("RemoteEvent"), "ReplicatedStorage.PlayPressed (RemoteEvent) missing")

for _ = 1, N do
	playPressed:FireServer()
end

return "PASS"
