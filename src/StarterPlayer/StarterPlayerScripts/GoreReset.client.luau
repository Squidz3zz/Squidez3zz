-- GoreReset: the Reset Character button (in Roblox's menu) asks the server to kill this player's character through the gore
-- system (ReplicatedStorage.GoreReset, which GoreServer makes), so a reset is a plain death: the body ragdolls and leaves a
-- corpse, the death screen runs, and no limb is hurt. Roblox's own reset would count as a 100-damage hit. SetCore fails
-- until Roblox's core scripts are ready, so it is retried until it takes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local remote = ReplicatedStorage:WaitForChild("GoreReset")
local bindable = Instance.new("BindableEvent")
bindable.Event:Connect(function()
	remote:FireServer()
end)

while not pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", bindable) do
	task.wait(0.5)
end
