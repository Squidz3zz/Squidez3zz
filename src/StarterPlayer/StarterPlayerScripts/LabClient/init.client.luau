-- LabClient: this player's side of Room 1's injection lab. Two parts so far:
--   * the claim prompt's text, set locally. Free: "Claim Room 1". Yours: "Release Room 1". Someone else's: the prompt is switched off
--     for this player. The server checks every trigger anyway; this only keeps the prompt honest on screen.
--   * the tablet menu (TabletMenu): activating the Tablet tool opens it; it closes when the tool is unequipped or goes, and when the
--     character dies.
-- Every piece runs through run(): a failure warns once in Output and never stops the other pieces.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

-- The tablet menu. The server hands the owner a Tool named Tablet and takes it away again (a lost right arm, a release, a death), so
-- every tablet that shows up in the hand is wired once, and the menu closes whenever it leaves.
local function wireTablet()
	local TabletMenu = require(script:WaitForChild("TabletMenu", 30))
	local remotes = ReplicatedStorage:WaitForChild("LabRemotes", 30)
	TabletMenu.init({
		template = ReplicatedStorage:WaitForChild("TabletMenu", 30),
		playerGui = player:WaitForChild("PlayerGui"),
		config = require(ReplicatedStorage:WaitForChild("LabConfig", 30)),
		room = workspace:WaitForChild("Room1", 30),
		remote = remotes:WaitForChild("RequestInjection", 30),
	})

	local function close()
		run("tablet menu close", TabletMenu.close)
	end

	local wired = setmetatable({}, { __mode = "k" })
	local function wireTool(tool: Tool)
		if wired[tool] then
			return
		end
		wired[tool] = true
		tool.Activated:Connect(function()
			run("tablet menu open", TabletMenu.open)
		end)
		tool.Unequipped:Connect(close)
		tool.AncestryChanged:Connect(function()
			if not (player.Character and tool.Parent == player.Character) then
				close()
			end
		end)
	end

	local function onCharacter(character: Model)
		close()
		local function check(child: Instance)
			if child:IsA("Tool") and child.Name == "Tablet" then
				wireTool(child)
			end
		end
		character.ChildAdded:Connect(check)
		for _, child in character:GetChildren() do
			check(child)
		end
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(close)
		end
	end
	player.CharacterAdded:Connect(function(character)
		run("tablet menu character", onCharacter, character)
	end)
	player.CharacterRemoving:Connect(close)
	if player.Character then
		task.spawn(run, "tablet menu character", onCharacter, player.Character)
	end
end

task.spawn(run, "claim prompt", wireClaimPrompt)
task.spawn(run, "tablet menu", wireTablet)
