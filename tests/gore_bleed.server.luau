-- Run in the Server datamodel of a running playtest (no player needed). It builds R6 bodies far from the rooms (x 3030 and up,
-- y 300, z 4000, anchored, each on a floor of its own), tracks them in the game's own Gore (through
-- ServerScriptService.GoreServer.TestHook) and opens their limbs with "hit" damage of 50 (Torn: an open wound, no health lost).
-- GoreServer bleeds them every 0.25 s; each rate below is measured between the first and the last health change it sees, so the
-- tick size does not blur it.
--   B-A  2 open limbs: the body loses 1.66 +- 0.1 health per second over 3 s (BLEED_PER_OPEN_LIMB 0.83 x 2)
--   B-B  1 open limb: it loses none
--   B-C  a linked pair (Gore.link), both with 2 open limbs (torn on one, the link tears the other): they lose exactly the same
--        health, each at 1.66 +- 0.1 per second (a pair hurt twice, once for itself and once through its partner, loses double)
--   B-D  GORE_LEVEL 0 (an override on GoreConfig, always removed): 2 open limbs lose none in 2 s
--   B-E  a body with 2 open limbs is killed: for 1.5 s neither its corpse (in Workspace.Corpses) nor the emptied body it left
--        has any health change, and the output has no Gore error or warning
-- It removes its bodies and returns "PASS gore_bleed".
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RATE = 1.66
local TOLERANCE = 0.1
local SECONDS = 3

local configModule = ReplicatedStorage:WaitForChild("GoreConfig")
local hook = ServerScriptService.GoreServer:FindFirstChild("TestHook")
assert(hook, "ServerScriptService.GoreServer.TestHook is missing (is Gore pushed?)")
local function gore(fnName: string, ...: any): any
	return hook:Invoke("call", fnName, ...)
end

local old = workspace:FindFirstChild("GoreBleedTest")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "GoreBleedTest"
folder.Parent = workspace

local count = 0
local function newBody(): Model
	count += 1
	local x = 3000 + 30 * count
	local body = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	body.Name = "Bleeder" .. count
	body.HumanoidRootPart.Anchored = true
	body:PivotTo(CFrame.new(x, 300, 4000))
	body.Parent = folder
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(20, 1, 20)
	floor.Position = Vector3.new(x, 296.5, 4000)
	floor.Parent = folder
	task.wait(0.1)
	gore("track", body)
	return body
end

local function tear(body: Model, keys: { string })
	for _, key in keys do
		gore("damageLimb", body, key, 50, "hit")
	end
end

-- Watches the bodies' health for `seconds`; returns, per body, its health lost and its rate (health per second between the
-- first and the last change seen; 0 with fewer than two changes).
local function measure(bodies: { Model }, seconds: number): { { lost: number, rate: number, changes: number } }
	local logs, starts, connections = {}, {}, {}
	for i, body in bodies do
		local humanoid = body:FindFirstChildOfClass("Humanoid")
		logs[i], starts[i] = {}, humanoid.Health
		connections[i] = humanoid.HealthChanged:Connect(function(health)
			table.insert(logs[i], { at = os.clock(), health = health })
		end)
	end
	task.wait(seconds)
	local results = {}
	for i, body in bodies do
		connections[i]:Disconnect()
		local log = logs[i]
		local rate = if #log >= 2 then (log[1].health - log[#log].health) / (log[#log].at - log[1].at) else 0
		results[i] = { lost = starts[i] - body:FindFirstChildOfClass("Humanoid").Health, rate = rate, changes = #log }
	end
	return results
end

local function near(rate: number, label: string)
	assert(math.abs(rate - RATE) <= TOLERANCE, ("%s: bleeds %.3f health/s, expected %.2f +- %.2f"):format(label, rate, RATE, TOLERANCE))
end

local ok, err = pcall(function()
	configModule:SetAttribute("GORE_LEVEL", nil)
	local two, one, pairA, pairB = newBody(), newBody(), newBody(), newBody()
	gore("link", pairA, pairB)
	tear(two, { "LeftArm", "RightLeg" })
	tear(one, { "LeftArm" })
	tear(pairA, { "LeftArm", "RightArm" })
	assert(pairB:GetAttribute("Gore_RightArm") == "Torn", "B-C: the link did not tear the partner's arm")
	local r = measure({ two, one, pairA, pairB }, SECONDS)
	-- B-A
	assert(r[1].changes >= 8, ("B-A: only %d health changes in %d s"):format(r[1].changes, SECONDS))
	near(r[1].rate, "B-A")
	-- B-B
	assert(r[2].lost == 0, ("B-B: 1 open limb lost %.3f health"):format(r[2].lost))
	-- B-C
	near(r[3].rate, "B-C (first)")
	near(r[4].rate, "B-C (partner)")
	assert(math.abs(r[3].lost - r[4].lost) < 1e-6, ("B-C: the pair lost %.3f and %.3f"):format(r[3].lost, r[4].lost))
	-- B-D
	configModule:SetAttribute("GORE_LEVEL", 0)
	local zero = newBody()
	tear(zero, { "LeftArm", "RightArm" })
	local z = measure({ zero }, 2)
	assert(z[1].lost == 0, ("B-D: at GORE_LEVEL 0, 2 open limbs lost %.3f health"):format(z[1].lost))
	-- B-E
	configModule:SetAttribute("GORE_LEVEL", nil)
	local dying = newBody()
	tear(dying, { "LeftArm", "RightArm" })
	local torso = dying.Torso
	gore("hurt", dying, math.huge)
	local corpse
	local deadline = os.clock() + 3
	repeat
		task.wait()
		local parent = torso.Parent
		corpse = if parent and parent.Name == "Corpse" and parent.Parent == workspace:FindFirstChild("Corpses") then parent else nil
	until corpse or os.clock() > deadline
	assert(corpse, "B-E: the killed body left no corpse")
	local changes, problems = 0, {}
	local watching = {
		corpse:FindFirstChildOfClass("Humanoid").HealthChanged:Connect(function()
			changes += 1
		end),
		dying:FindFirstChildOfClass("Humanoid").HealthChanged:Connect(function()
			changes += 1
		end),
		LogService.MessageOut:Connect(function(message, kind)
			if (kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning) and string.find(message, "Gore") then
				table.insert(problems, message)
			end
		end),
	}
	task.wait(1.5)
	for _, connection in watching do
		connection:Disconnect()
	end
	corpse:Destroy()
	assert(changes == 0, ("B-E: the corpse or the emptied body changed health %d times"):format(changes))
	assert(#problems == 0, "B-E: Gore complained: " .. table.concat(problems, " | "))
	return ("B-A %.3f/s, B-B 0, B-C %.3f and %.3f/s (lost %.3f each), B-D 0, B-E 0"):format(r[1].rate, r[3].rate, r[4].rate, r[3].lost)
end)
configModule:SetAttribute("GORE_LEVEL", nil)
folder:Destroy()
assert(ok, err)
return "PASS gore_bleed (" .. err .. ")"
