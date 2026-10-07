-- LabClient: this player's side of Room 1's injection lab. This part: the claim prompt's text, set locally.
-- Free: "Claim Room 1". Yours: "Release Room 1". Someone else's: the prompt is switched off for this player. The server checks every
-- trigger anyway; this only keeps the prompt honest on screen.
-- Every piece runs through run(): a failure warns once in Output and never stops the other pieces.
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local warned = {}
local function run(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not warned[name] then
		warned[name] = true
		warn("LabClient: " .. name .. " failed: " .. tostring(err))
	end
	return ok
end

local function wireClaimPrompt()
	local room = workspace:WaitForChild("Room1", 30)
	local button = room and room:WaitForChild("ClaimButton", 30)
	local face = button and button:WaitForChild("Button", 30)
	local prompt = face and face:WaitForChild("ClaimPrompt", 30)
	assert(prompt, "Workspace.Room1.ClaimButton.Button.ClaimPrompt did not appear")

	local function refresh()
		local owner = room:GetAttribute("Owner") or 0
		if owner == 0 then
			prompt.Enabled = true
			prompt.ActionText = "Claim Room 1"
		elseif owner == player.UserId then
			prompt.Enabled = true
			prompt.ActionText = "Release Room 1"
		else
			prompt.Enabled = false
		end
	end
	room:GetAttributeChangedSignal("Owner"):Connect(function()
		run("claim prompt", refresh)
	end)
	refresh()
end

task.spawn(run, "claim prompt", wireClaimPrompt)
