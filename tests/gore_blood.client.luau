-- Run in the Client datamodel during a playtest, with the server step tests/gore_blood.server.luau. Start a fresh playtest, run
-- tests/fire_play.client.luau (it presses Play) and wait for the character, then, in this order:
--   A-1  Client, CASE = "A-1": arms the watcher (it keeps running) and returns at once
--   S    Server: tests/gore_blood.server.luau (a blood boom at a wall of its own, then the Explosive into the copy's head)
--   A-2  Client, CASE = "A-2": waits for the watcher's verdict and returns it
--   F    Client, CASE = "F" (any time after A-2): S-F
-- GoreClient's splats are parts named BloodSplat (in Workspace.GoreSplats); its blood burst is an Attachment named BloodBurst
-- in Workspace.Terrain. Each splat is checked the moment it appears: a ray into it along its thin axis, from just above it
-- (0.1 studs: a splat on glass inside the raised Shutter's box reads the glass, not the Shutter), finds the part it lies on.
--   S-A  the boom at the wall puts at least 2 splats on GoreBloodWall.Wall, each flat on it (axis within 10 degrees of the
--        wall's normal, centre within 0.2 studs of its face) and longer down the wall than across it
--   S-B  the head blast on the seated copy (facing -X, the window) puts at least 1 splat on the inside of the observation glass
--        (a Glass part, the splat facing +X)
--   S-C  every BloodBurst's Spray throws its droplets at 40 to 90 studs/s
--   S-D  every splat is wet-looking Foil (ruling R17: Material Foil), holds no Decal, and is drawn as a disc: a SpecialMesh
--        Cylinder (whose axis is the part's X) on a part whose X is its thinnest side (otherwise it draws a rod)
--   S-E  no splat lies on Room1.Shutter or on a body (a GoreBody, a character or anything in Workspace.Corpses)
--   S-F  200 splats asked of GoreClient (its Studio-only TestHook, "splatter", at a wall this client makes for itself) leave
--        at most SPLAT_MAX (150) at once; the test removes its wall and its splats
local CASE = "A-1"
local FLAT_DEGREES = 10

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoreConfig = require(ReplicatedStorage:WaitForChild("GoreConfig"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RESULT = "GB_Result"

local function onBody(part: Instance): boolean
	local corpses = workspace:FindFirstChild("Corpses")
	if corpses and part:IsDescendantOf(corpses) then
		return true
	end
	for _, body in CollectionService:GetTagged("GoreBody") do
		if part:IsDescendantOf(body) then
			return true
		end
	end
	for _, other in Players:GetPlayers() do
		if other.Character and part:IsDescendantOf(other.Character) then
			return true
		end
	end
	return false
end

-- A splat's thin axis and the other two, each with the splat's size along it (thin first).
local function axes(splat: BasePart): { { any } }
	local list = {
		{ splat.CFrame.RightVector, splat.Size.X },
		{ splat.CFrame.UpVector, splat.Size.Y },
		{ splat.CFrame.LookVector, splat.Size.Z },
	}
	table.sort(list, function(a, b)
		return a[2] < b[2]
	end)
	return list
end

-- What a splat lies on, read as it appears.
local function inspect(splat: BasePart)
	local axis = axes(splat)
	local normal = axis[1][1]
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { splat }
	local hit = workspace:Raycast(splat.Position + normal * 0.1, normal * -0.6, params)
	-- A cylinder (a SpecialMesh one, or the part's own shape) is drawn along the part's X.
	local mesh = splat:FindFirstChildOfClass("SpecialMesh")
	local cylinder = if mesh then mesh.MeshType == Enum.MeshType.Cylinder else splat.Shape == Enum.PartType.Cylinder
	local entry = {
		splat = splat,
		normal = normal,
		foil = splat.Material == Enum.Material.Foil,
		disc = cylinder and splat.Size.X <= math.min(splat.Size.Y, splat.Size.Z),
		decal = splat:FindFirstChildWhichIsA("Decal", true) ~= nil,
	}
	if hit then
		entry.host = hit.Instance
		entry.flat = math.deg(math.acos(math.clamp(normal:Dot(hit.Normal), -1, 1))) <= FLAT_DEGREES
			and math.abs((splat.Position - hit.Position):Dot(hit.Normal)) <= 0.2
		-- Its extent down the surface and across it (an ellipse with semi-axes along its other two axes).
		local down = -Vector3.yAxis - hit.Normal * hit.Normal:Dot(-Vector3.yAxis)
		if down.Magnitude > 0.5 then
			down = down.Unit
			local across = hit.Normal:Cross(down)
			local function extent(d: Vector3): number
				return math.sqrt((axis[2][1]:Dot(d) * axis[2][2]) ^ 2 + (axis[3][1]:Dot(d) * axis[3][2]) ^ 2)
			end
			entry.long = extent(down) > extent(across)
		end
		entry.body = onBody(hit.Instance)
		entry.shutter = hit.Instance.Name == "Shutter" and hit.Instance.Parent == workspace:FindFirstChild("Room1")
	end
	return entry
end

if CASE == "A-1" then
	playerGui:SetAttribute(RESULT, "running")
	local entries, sprays = {}, {}
	local splatWatch = workspace.DescendantAdded:Connect(function(thing)
		if thing.Name == "BloodSplat" and thing:IsA("BasePart") then
			task.defer(function()
				table.insert(entries, inspect(thing))
			end)
		end
	end)
	local burstWatch = workspace.Terrain.ChildAdded:Connect(function(thing)
		if thing.Name == "BloodBurst" then
			task.defer(function()
				local spray = thing:FindFirstChild("Spray")
				table.insert(sprays, if spray then spray.Speed else false)
			end)
		end
	end)
	task.spawn(function()
		local ok, err = pcall(function()
			local model = workspace:WaitForChild("GoreBloodWall", 60)
			assert(model, "no GoreBloodWall: run tests/gore_blood.server.luau")
			local deadline = os.clock() + 90
			while model.Parent and model:GetAttribute("Done") ~= true and os.clock() < deadline do
				task.wait(0.2)
			end
			assert(model:GetAttribute("Done") == true, "the server step never finished")
			task.wait(0.5)
			local wall = model:FindFirstChild("Wall")
			local onWall, onGlass, notes = 0, 0, {}
			for _, entry in entries do
				local name = entry.splat:GetFullName()
				-- S-D
				assert(entry.foil, "S-D: a splat is " .. entry.splat.Material.Name .. ", not Foil")
				assert(not entry.decal, "S-D: a splat holds a Decal")
				assert(entry.disc, ("S-D: a splat is not drawn as a disc (Size %s): its cylinder axis X must be its thinnest side"):format(tostring(entry.splat.Size)))
				-- S-E
				assert(not entry.shutter, "S-E: a splat lies on Room1.Shutter")
				assert(not entry.body, "S-E: a splat lies on a body: " .. (if entry.host then entry.host:GetFullName() else "?"))
				if not entry.host then
					table.insert(notes, "one splat had no surface under it: " .. name)
				elseif entry.host == wall then
					-- S-A
					assert(entry.flat, "S-A: a splat on the wall is not flat on it")
					assert(entry.long, ("S-A: a splat on the wall is not longer down it than across (%s)"):format(tostring(entry.splat.Size)))
					onWall += 1
				elseif entry.host.Material == Enum.Material.Glass and entry.normal.X > 0.7 then
					onGlass += 1
				end
			end
			assert(#notes == 0, notes[1])
			assert(onWall >= 2, ("S-A: %d splats on the wall, expected at least 2"):format(onWall))
			assert(onGlass >= 1, "S-B: no splat on the inside of the observation glass")
			-- S-C
			assert(#sprays >= 2, ("S-C: %d BloodBursts seen, expected at least 2"):format(#sprays))
			for _, speed in sprays do
				assert(speed, "S-C: a BloodBurst has no Spray")
				assert(speed.Min == 40 and speed.Max == 90, ("S-C: Spray speed %s, expected 40 to 90"):format(tostring(speed)))
			end
			return ("%d splats checked: %d on the wall, %d on the inside of the glass; %d bursts at 40-90 studs/s"):format(#entries, onWall, onGlass, #sprays)
		end)
		splatWatch:Disconnect()
		burstWatch:Disconnect()
		playerGui:SetAttribute(RESULT, if ok then "PASS gore_blood (S-A to S-E; " .. err .. ")" else "FAIL " .. tostring(err))
	end)
	return "armed: now run tests/gore_blood.server.luau, then CASE A-2"
elseif CASE == "A-2" then
	local deadline = os.clock() + 100
	while playerGui:GetAttribute(RESULT) == "running" and os.clock() < deadline do
		task.wait(0.2)
	end
	local result = playerGui:GetAttribute(RESULT)
	playerGui:SetAttribute(RESULT, nil)
	assert(type(result) == "string" and string.sub(result, 1, 4) == "PASS", tostring(result))
	return result
elseif CASE == "F" then
	local gore = player:WaitForChild("PlayerScripts"):WaitForChild("GoreClient")
	local hook = gore:FindFirstChild("TestHook")
	assert(hook and hook:IsA("BindableFunction"), "GoreClient.TestHook (BindableFunction) missing")
	local wall = Instance.new("Part")
	wall.Name = "GoreBloodTestWall"
	wall.Anchored = true
	wall.Size = Vector3.new(1, 40, 60)
	wall.Position = Vector3.new(8010, 320, 8000)
	wall.Parent = workspace
	local made, most = 0, 0
	local ok, err = pcall(function()
		while made < 200 do
			made += hook:Invoke("splatter", Vector3.new(8006.5, 320, 8000), Vector3.xAxis)
			local folder = workspace:FindFirstChild("GoreSplats")
			most = math.max(most, if folder then #folder:GetChildren() else 0)
		end
		local max = GoreConfig.get("SPLAT_MAX")
		assert(most <= max, ("S-F: %d splats at once, more than SPLAT_MAX %d"):format(most, max))
	end)
	wall:Destroy()
	local folder = workspace:FindFirstChild("GoreSplats")
	for _, splat in if folder then folder:GetChildren() else {} do
		if splat.Position.X > 7900 then
			splat:Destroy()
		end
	end
	assert(ok, err)
	return ("PASS gore_blood S-F (%d splats asked for, at most %d at once)"):format(made, most)
end
error("unknown CASE " .. CASE)
