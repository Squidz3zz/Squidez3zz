-- Run in the Server datamodel of a running playtest (no player needed: start the playtest, then run this). It builds R6 bodies
-- here (30 studs apart, far from the rooms: x 5030 and up, y 300, z 5000, root anchored, each on a floor of its own) and drives
-- the game's own Gore through ServerScriptService.GoreServer.TestHook ("call", fnName, ...). Chances are fixed with GoreConfig
-- overrides (attributes on the module, Studio only), removed when the test ends. A flesh piece is any part in the body (or in a
-- limb that left it) with the attributes Offset and Limb; a stub is a piece named Stub1. The sets are ServerStorage.Gore.Pieces.
--   F-A torn arm   a torn LeftArm (a "hit") is invisible (Transparency 1) and wears exactly Pieces.LeftArm.Variant<GoreVariant>
--                  (flesh, plus bone for Variant2), each piece welded within 0.2 studs of part.CFrame * Offset, unanchored,
--                  massless and not colliding. Its linked partner (copyState, then link) shows the same
--   F-B torso      a torso torn by a "hit" wears Sealed: TorsoFilling (Layer "flesh") and no Ribcage; an explosion with
--                  TORSO_OPEN_CHANCE 1 opens it: exactly the Open set, with a Ribcage (Layer "deep") and no TorsoFilling (the
--                  open torso kills: the pieces go into the corpse with their torso)
--   F-C legs       both legs severed (SEVER_CHANCE 1) with the torso intact: no torso pieces, no Ribcage, the torso visible,
--                  a stub for each leg, and each flying leg wears its flesh
--   F-D head       a destroyed head with SKULL_BLAST_CHANCE 0 ("shown") wears HeadFlesh and Skull, its face hidden; with 1
--                  ("blasted") HeadFlesh and no Skull. Both die: the pieces lie in the corpse with their head, and damaging the
--                  emptied body (it keeps the GoreBody tag with no parts) makes no Gore warning or error
--   F-E stub       a severed LeftArm leaves one Stub1 welded to the Torso within 0.2 studs of where the arm rests (the shoulder
--                  joint's C0 * C1:Inverse() * Offset). A body built from it (copyState) arrives without its left arm, stub on
--   F-F all six    all six limbs torn: every R6 part is hidden and each wears its own whole variant set (none lost a deep piece),
--                  with at least one deep piece (bone or skull) among them; the seed is reset afterwards. The head tears last,
--                  since a torn head kills (the parts are found before, as they move into the corpse)
--   F-G level 1    with GORE_LEVEL 1 a torn LeftArm gets no pieces and stays visible; a severed one leaves a plain dark-red
--                  GoreStump on the Torso and no Stub1
--   F-H no pieces  with ServerStorage.Gore.Pieces renamed (always put back): a torn LeftArm stays skin (visible, no pieces), an
--                  arm already wearing its flesh keeps it when it breaks, and the output has the warning about the missing set
--                  (Integrity warns once per server, so it may come from an earlier run in the same playtest)
--   F-I scraps     a body wearing a Shirt has its LeftArm torn: its GoreFlesh holds 3-5 GoreScrap parts beside the exact
--                  variant set, each thin (0.05 one way, 0.3-0.7 the others), welded to the arm, massless, not colliding,
--                  queried or touched, its centre in the arm's top 35% and 0.05-0.15 studs outside its surface (never on the
--                  inner side, against the torso), with
--                  Textures showing the ShirtTemplate. The intact torso (also under the Shirt) gets none
--   F-J bare       no clothing, or a Shirt with an empty template: a torn LeftArm gets no scraps and wears exactly its set
--   F-K severed    a severed LeftArm (SEVER_CHANCE 1) on a clothed body flies off with its scraps still welded to it; the
--                  Torso, with the stub, gets none
--   F-L level 1    with GORE_LEVEL 1 a clothed torn LeftArm gets no scraps
-- Every case runs (one failing does not stop the rest); the error lists each case's result. It removes its bodies and
-- corpses, and returns "PASS gore_flesh".
local CASE = "all" -- or one letter, "A" to "L"

local CollectionService = game:GetService("CollectionService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local configModule = ReplicatedStorage:WaitForChild("GoreConfig")
local Pieces = ServerStorage:WaitForChild("Gore"):WaitForChild("Pieces")

local server = ServerScriptService:FindFirstChild("GoreServer")
local hook = server and server:FindFirstChild("TestHook")
assert(hook and hook:IsA("BindableFunction"), "ServerScriptService.GoreServer.TestHook is missing (is Gore pushed?)")
local function gore(fnName: string, ...: any): any
	return hook:Invoke("call", fnName, ...)
end

local PART = { Head = "Head", Torso = "Torso", LeftArm = "Left Arm", RightArm = "Right Arm", LeftLeg = "Left Leg", RightLeg = "Right Leg" }
local KEYS = { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }

local problems = {}
local expectWarnings = false -- F-H makes Gore warn on purpose
local logging = LogService.MessageOut:Connect(function(message, kind)
	if not expectWarnings and (kind == Enum.MessageType.MessageError or kind == Enum.MessageType.MessageWarning) and string.find(message, "Gore") then
		table.insert(problems, message)
	end
end)

local old = workspace:FindFirstChild("GoreFleshTest")
if old then
	old:Destroy()
end
local folder = Instance.new("Folder")
folder.Name = "GoreFleshTest"
folder.Parent = workspace
local made: { Instance } = {}

local count = 0
local function newBody(): Model
	count += 1
	local x = 5000 + 30 * count
	local body = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	body.Name = "Body" .. count
	body.HumanoidRootPart.Anchored = true
	body:PivotTo(CFrame.new(x, 300, 5000))
	body.Parent = folder
	local floor = Instance.new("Part")
	floor.Anchored = true
	floor.Size = Vector3.new(20, 1, 20)
	floor.Position = Vector3.new(x, 296.5, 5000)
	floor.Parent = folder
	task.wait(0.1) -- a Humanoid must step before its death counts
	gore("track", body)
	return body
end

-- The flesh pieces under `root` for limb `key` (stubs left out unless `stubs`).
local function piecesOf(root: Instance, key: string, stubs: boolean?): { BasePart }
	local list = {}
	for _, thing in root:GetDescendants() do
		if thing:IsA("BasePart") and thing:GetAttribute("Offset") ~= nil and thing:GetAttribute("Limb") == key and (stubs or thing.Name ~= "Stub1") then
			table.insert(list, thing)
		end
	end
	return list
end
local function stubsOf(root: Instance, key: string): { BasePart }
	local list = {}
	for _, piece in piecesOf(root, key, true) do
		if piece.Name == "Stub1" then
			table.insert(list, piece)
		end
	end
	return list
end
local function names(list: { Instance }): string
	local n = {}
	for _, thing in list do
		table.insert(n, thing.Name)
	end
	table.sort(n)
	return table.concat(n, ",")
end
local function find(list: { Instance }, name: string): Instance?
	for _, thing in list do
		if thing.Name == name then
			return thing
		end
	end
	return nil
end

-- `part` wears exactly Pieces[key][setName], each piece welded where its Offset says.
local function wears(part: BasePart, key: string, setName: string, label: string)
	local list = piecesOf(part, key)
	local want = Pieces[key][setName]:GetChildren()
	assert(names(list) == names(want), ("%s: %s wears {%s}, expected %s.%s {%s}"):format(label, key, names(list), key, setName, names(want)))
	for _, piece in list do
		local off = (piece.Position - (part.CFrame * piece:GetAttribute("Offset")).Position).Magnitude
		assert(off < 0.2, ("%s: %s's %s is %.2f studs off its place"):format(label, key, piece.Name, off))
		assert(not piece.Anchored and piece.Massless and not piece.CanCollide, ("%s: %s's %s should be unanchored, massless and not collide"):format(label, key, piece.Name))
	end
end

local function withOverrides(overrides: { [string]: any }, fn: () -> ())
	for name, value in overrides do
		configModule:SetAttribute(name, value)
	end
	local ok, err = pcall(fn)
	for name in overrides do
		configModule:SetAttribute(name, nil)
	end
	if not ok then
		error(err, 0)
	end
end

-- The Model in Workspace.Corpses the part moved into (waits up to 3 s).
local function corpseOf(part: BasePart): Model?
	local deadline = os.clock() + 3
	repeat
		local parent = part.Parent
		if parent and parent.Parent == workspace:FindFirstChild("Corpses") then
			return parent :: Model
		end
		task.wait()
	until os.clock() > deadline
	return nil
end

local cases = {}

-- F-A torn arm, on a linked pair.
cases.A = function()
	local a, b = newBody(), newBody()
	gore("copyState", a, b)
	gore("link", a, b)
	gore("damageLimb", a, "LeftArm", 50, "hit")
	task.wait()
	for _, body in { a, b } do
		assert(body:GetAttribute("Gore_LeftArm") == "Torn", "F-A: 50 hit damage should tear the left arm")
		local arm = body["Left Arm"]
		assert(arm.Transparency == 1, "F-A: the torn arm is still visible on " .. body.Name)
		wears(arm, "LeftArm", "Variant" .. body:GetAttribute("GoreVariant_LeftArm"), "F-A " .. body.Name)
		assert(body["Right Arm"].Transparency == 0 and #piecesOf(body, "RightArm") == 0, "F-A: the intact right arm changed")
	end
end

-- F-B torso.
cases.B = function()
	withOverrides({ TORSO_OPEN_CHANCE = 1 }, function()
		local body = newBody()
		gore("damageLimb", body, "Torso", 50, "hit")
		assert(body:GetAttribute("Gore_Torso") == "Torn" and body:GetAttribute("GoreTorsoOpen") == false, "F-B: a hit should tear the torso, sealed")
		task.wait()
		local torso = body.Torso
		assert(torso.Transparency == 1, "F-B: the torn torso is still visible")
		wears(torso, "Torso", "Sealed", "F-B sealed")
		local list = piecesOf(torso, "Torso")
		assert(not find(list, "Ribcage"), "F-B: the sealed torso shows a Ribcage")
		assert(find(list, "TorsoFilling"):GetAttribute("Layer") == "flesh", "F-B: TorsoFilling's Layer should be flesh")
		gore("damageLimb", body, "Torso", 5, "explosion")
		assert(body:GetAttribute("GoreTorsoOpen") == true and body:GetAttribute("Gore_Torso") == "Torn", "F-B: the explosion should open the torn torso")
		task.wait()
		wears(torso, "Torso", "Open", "F-B open")
		list = piecesOf(torso, "Torso")
		local ribcage = find(list, "Ribcage")
		assert(ribcage and ribcage:GetAttribute("Layer") == "deep", "F-B: the open torso needs a Ribcage with Layer deep")
		assert(not find(list, "TorsoFilling"), "F-B: the open torso still has its TorsoFilling")
		local corpse = corpseOf(torso)
		assert(corpse, "F-B: the open torso did not kill")
		table.insert(made, corpse)
	end)
end

-- F-C both legs severed.
cases.C = function()
	withOverrides({ SEVER_CHANCE = 1 }, function()
		local body = newBody()
		local legs = { LeftLeg = body["Left Leg"], RightLeg = body["Right Leg"] }
		for key, leg in legs do
			gore("damageLimb", body, key, 150, "explosion")
			assert(body:GetAttribute("Gore_" .. key) == "Severed", "F-C: SEVER_CHANCE 1 should sever " .. key)
			assert(not leg:IsDescendantOf(body), "F-C: the severed " .. key .. " is still in the body")
			assert(#piecesOf(leg, key) > 0, "F-C: the flying " .. key .. " shows no flesh")
			assert(#stubsOf(body, key) == 1, "F-C: expected one stub for " .. key)
		end
		assert(body:GetAttribute("Gore_Torso") == "Intact", "F-C: the torso should stay intact")
		assert(#piecesOf(body, "Torso") == 0, "F-C: the intact torso wears pieces: " .. names(piecesOf(body, "Torso")))
		assert(body.Torso.Transparency == 0, "F-C: the intact torso is hidden")
	end)
end

-- F-D head, and the corpse.
cases.D = function()
	for _, case in { { chance = 0, skull = "shown" }, { chance = 1, skull = "blasted" } } do
		withOverrides({ SKULL_BLAST_CHANCE = case.chance }, function()
			local body = newBody()
			local head = body.Head
			gore("damageLimb", body, "Head", 150, "hit")
			assert(body:GetAttribute("Gore_Head") == "Destroyed" and body:GetAttribute("GoreSkull") == case.skull, "F-D: the head should be destroyed with the skull " .. case.skull)
			assert(head.Transparency == 1, "F-D: the destroyed head is still visible")
			local face = head:FindFirstChildOfClass("Decal")
			assert(not face or face.Transparency == 1, "F-D: the face still shows")
			local list = piecesOf(head, "Head")
			assert(find(list, "HeadFlesh"), "F-D: the destroyed head has no HeadFlesh")
			if case.skull == "shown" then
				assert(find(list, "Skull"), "F-D: a shown skull is missing")
			else
				assert(not find(list, "Skull"), "F-D: a blasted skull still shows")
			end
			local corpse = corpseOf(head)
			assert(corpse, "F-D: the body left no corpse holding its head")
			table.insert(made, corpse)
			assert(#piecesOf(corpse, "Head") == #list, "F-D: the head's pieces did not go into the corpse with it")
			-- The emptied body keeps its tag and attributes but has no parts.
			assert(CollectionService:HasTag(body, "GoreBody") and not body:FindFirstChild("Left Arm"), "F-D: expected the emptied body to keep its tag with no parts")
			gore("damageLimb", body, "LeftArm", 50, "hit")
		end)
	end
end

-- F-E stub, and a copy built from it.
cases.E = function()
	withOverrides({ SEVER_CHANCE = 1 }, function()
		local body = newBody()
		local joint = body.Torso["Left Shoulder"]
		local rest = joint.C0 * joint.C1:Inverse()
		gore("damageLimb", body, "LeftArm", 150, "explosion")
		assert(body:GetAttribute("Gore_LeftArm") == "Severed", "F-E: SEVER_CHANCE 1 should sever the left arm")
		task.wait()
		local stubs = stubsOf(body, "LeftArm")
		assert(#stubs == 1, "F-E: expected one Stub1 for the left arm, found " .. #stubs)
		local stub = stubs[1]
		local welded = false
		for _, weld in body:GetDescendants() do
			if weld:IsA("JointInstance") or weld:IsA("WeldConstraint") then
				local p0, p1 = (weld :: any).Part0, (weld :: any).Part1
				welded = welded or (p0 == body.Torso and p1 == stub) or (p1 == body.Torso and p0 == stub)
			end
		end
		assert(welded, "F-E: the stub is not welded to the Torso")
		local off = (stub.Position - (body.Torso.CFrame * rest * stub:GetAttribute("Offset")).Position).Magnitude
		assert(off < 0.2, ("F-E: the stub is %.2f studs off the shoulder"):format(off))
		local copy = newBody()
		gore("copyState", body, copy)
		assert(not copy:FindFirstChild("Left Arm"), "F-E: the copy should arrive without its left arm")
		assert(#stubsOf(copy, "LeftArm") == 1, "F-E: the copy should arrive with the stub on")
	end)
end

-- F-F all six torn.
cases.F = function()
	local body = newBody()
	local parts = {}
	for _, key in KEYS do
		parts[key] = body[PART[key]]
	end
	gore("seed", 14) -- variants: Torso 2, LeftArm 1, RightArm 2, LeftLeg 2, RightLeg 1, Head 2 (bone and skull showing)
	for _, key in { "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Head" } do
		gore("damageLimb", body, key, 50, "hit")
	end
	gore("seed", Random.new():NextInteger(1, 2 ^ 30))
	task.wait()
	local variants = {}
	for _, key in KEYS do
		assert(body:GetAttribute("Gore_" .. key) == "Torn", "F-F: " .. key .. " should be torn")
		local part = parts[key]
		assert(part.Transparency == 1, "F-F: " .. key .. " is still visible")
		local setName = if key == "Torso" then "Sealed" else "Variant" .. body:GetAttribute("GoreVariant_" .. key)
		wears(part, key, setName, "F-F")
		table.insert(variants, key .. "=" .. setName)
	end
	local deep = 0
	for _, key in KEYS do
		for _, piece in piecesOf(parts[key], key) do
			deep += if piece:GetAttribute("Layer") == "deep" then 1 else 0
		end
	end
	assert(deep > 0, "F-F: no limb wears a deep piece (the seed's variants changed?)")
	local corpse = corpseOf(parts.Torso)
	assert(corpse, "F-F: the torn head did not kill")
	table.insert(made, corpse)
	print("gore_flesh F-F sets: " .. table.concat(variants, " ") .. "; deep pieces " .. deep)
end

-- F-G level 1.
cases.G = function()
	withOverrides({ GORE_LEVEL = 1, SEVER_CHANCE = 1 }, function()
		local body = newBody()
		gore("damageLimb", body, "LeftArm", 50, "hit")
		assert(body:GetAttribute("Gore_LeftArm") == "Torn", "F-G: the arm should still tear at level 1")
		assert(#piecesOf(body, "LeftArm") == 0, "F-G: level 1 welded pieces")
		assert(body["Left Arm"].Transparency == 0, "F-G: level 1 hid the torn arm")
		gore("damageLimb", body, "RightArm", 150, "explosion")
		assert(body:GetAttribute("Gore_RightArm") == "Severed", "F-G: the right arm should be severed")
		assert(#stubsOf(body, "RightArm") == 0, "F-G: level 1 welded a Stub1")
		local stump = body.Torso:FindFirstChild("GoreStump")
		assert(stump and stump:IsA("BasePart") and stump.Transparency == 0, "F-G: level 1 should leave a plain GoreStump on the Torso")
	end)
end

-- F-H missing pieces.
cases.H = function()
	local dressed = newBody()
	gore("damageLimb", dressed, "LeftArm", 50, "hit")
	local setName = "Variant" .. dressed:GetAttribute("GoreVariant_LeftArm")
	wears(dressed["Left Arm"], "LeftArm", setName, "F-H before")
	local bare = newBody()
	expectWarnings = true
	Pieces.Name = "PiecesAway"
	local ok, err = pcall(function()
		gore("damageLimb", bare, "LeftArm", 50, "hit")
		assert(bare:GetAttribute("Gore_LeftArm") == "Torn", "F-H: the arm should still tear with no Pieces")
		assert(bare["Left Arm"].Transparency == 0 and #piecesOf(bare, "LeftArm") == 0, "F-H: with no Pieces the torn arm should stay skin")
		gore("damageLimb", dressed, "LeftArm", 50, "hit")
		assert(dressed:GetAttribute("Gore_LeftArm") == "Broken", "F-H: the dressed arm should break")
		assert(dressed["Left Arm"].Transparency == 1, "F-H: the broken arm should stay hidden")
		wears(dressed["Left Arm"], "LeftArm", setName, "F-H broken with no Pieces")
	end)
	Pieces.Name = "Pieces"
	task.wait(0.1)
	expectWarnings = false
	if not ok then
		error(err, 0)
	end
	local warned = false
	for _, entry in LogService:GetLogHistory() do
		local message = entry.message
		warned = warned or (entry.messageType == Enum.MessageType.MessageWarning and string.find(message, "Pieces.LeftArm.", 1, true) ~= nil and string.find(message, "is missing", 1, true) ~= nil)
	end
	assert(warned, "F-H: the output has no warning about the missing pieces")
end

local SHIRT = "rbxassetid://10625577147" -- the user's suit
local function clothe(body: Model, template: string): Shirt
	local shirt = Instance.new("Shirt")
	shirt.ShirtTemplate = template
	shirt.Parent = body
	return shirt
end
local function scrapsOf(root: Instance?): { BasePart }
	local list = {}
	for _, thing in if root then root:GetDescendants() else {} do
		if thing:IsA("BasePart") and thing.Name == "GoreScrap" then
			table.insert(list, thing)
		end
	end
	return list
end
local function weldedTo(scrap: BasePart, part: BasePart): boolean
	for _, joint in scrap:GetChildren() do
		if joint:IsA("Weld") and joint.Part0 == part and joint.Part1 == scrap then
			return true
		end
	end
	return false
end

-- F-I scraps on a torn sleeve.
cases.I = function()
	local body = newBody()
	local shirt = clothe(body, SHIRT)
	gore("damageLimb", body, "LeftArm", 50, "hit")
	task.wait()
	local arm = body["Left Arm"]
	local scraps = scrapsOf(arm:FindFirstChild("GoreFlesh"))
	assert(#scraps >= 3 and #scraps <= 5, "F-I: expected 3-5 scraps in the arm's GoreFlesh, found " .. #scraps)
	assert(#scrapsOf(arm) == #scraps, "F-I: a scrap sits outside GoreFlesh")
	wears(arm, "LeftArm", "Variant" .. body:GetAttribute("GoreVariant_LeftArm"), "F-I")
	for i, scrap in scraps do
		local label = "F-I scrap " .. i
		local size = { scrap.Size.X, scrap.Size.Y, scrap.Size.Z }
		table.sort(size)
		assert(math.abs(size[1] - 0.05) < 0.01 and size[2] >= 0.29 and size[3] <= 0.71, label .. " has size " .. tostring(scrap.Size))
		assert(weldedTo(scrap, arm), label .. " is not welded to the arm")
		assert(scrap.Massless and not scrap.Anchored and not scrap.CanCollide and not scrap.CanQuery and not scrap.CanTouch, label .. " should be massless, unanchored and not collide, query or touch")
		local textures = scrap:GetChildren()
		local shown = 0
		for _, texture in textures do
			if texture:IsA("Texture") then
				assert(texture.Texture == shirt.ShirtTemplate, label .. " shows " .. texture.Texture)
				shown += 1
			end
		end
		assert(shown == 2, label .. " should have a Texture on each large face, has " .. shown)
		local at = arm.CFrame:PointToObjectSpace(scrap.Position)
		assert(at.Y >= arm.Size.Y / 2 - 0.35 * arm.Size.Y, ("%s is at %.2f along the arm, below its top 35%%"):format(label, at.Y))
		local out = math.max(math.abs(at.X) - arm.Size.X / 2, math.abs(at.Z) - arm.Size.Z / 2)
		assert(out >= 0.04 and out <= 0.16, ("%s is %.2f studs outside the arm"):format(label, out))
		assert(at.X < arm.Size.X / 2, label .. " is on the arm's inner side, against the torso")
	end
	assert(#scrapsOf(body.Torso) == 0, "F-I: the intact torso got scraps")
end

-- F-J no clothing, or an empty template.
cases.J = function()
	for _, template in { false, "" } do
		local body = newBody()
		if template then
			clothe(body, template)
		end
		gore("damageLimb", body, "LeftArm", 50, "hit")
		task.wait()
		assert(#scrapsOf(body) == 0, "F-J: a bare arm got scraps (template " .. tostring(template) .. ")")
		wears(body["Left Arm"], "LeftArm", "Variant" .. body:GetAttribute("GoreVariant_LeftArm"), "F-J")
	end
end

-- F-K the scraps fly off with a severed arm.
cases.K = function()
	withOverrides({ SEVER_CHANCE = 1 }, function()
		local body = newBody()
		clothe(body, SHIRT)
		local arm = body["Left Arm"]
		gore("damageLimb", body, "LeftArm", 150, "explosion")
		assert(body:GetAttribute("Gore_LeftArm") == "Severed" and not arm:IsDescendantOf(body), "F-K: SEVER_CHANCE 1 should sever the left arm")
		task.wait()
		local scraps = scrapsOf(arm)
		assert(#scraps >= 3 and #scraps <= 5, "F-K: the flying arm has " .. #scraps .. " scraps")
		for _, scrap in scraps do
			assert(weldedTo(scrap, arm), "F-K: a scrap came loose from the flying arm")
		end
		assert(#stubsOf(body, "LeftArm") == 1, "F-K: expected the stub on the Torso")
		assert(#scrapsOf(body.Torso) == 0, "F-K: the Torso (with the stub) got scraps")
	end)
end

-- F-L level 1.
cases.L = function()
	withOverrides({ GORE_LEVEL = 1 }, function()
		local body = newBody()
		clothe(body, SHIRT)
		gore("damageLimb", body, "LeftArm", 50, "hit")
		task.wait()
		assert(body:GetAttribute("Gore_LeftArm") == "Torn", "F-L: the arm should still tear at level 1")
		assert(#scrapsOf(body) == 0, "F-L: level 1 made scraps")
	end)
end

local results = {}
for _, name in if CASE == "all" then { "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L" } else { CASE } do
	local ok, err = pcall(cases[name])
	table.insert(results, "F-" .. name .. " " .. (if ok then "ok" else "FAIL: " .. tostring(err)))
end

task.wait(0.2)
logging:Disconnect()
for _, thing in made do
	thing:Destroy()
end
folder:Destroy()
local failed = {}
for _, line in results do
	if not string.find(line, " ok$") then
		table.insert(failed, line)
	end
end
assert(#failed == 0, table.concat(results, " | "))
assert(#problems == 0, "Gore complained: " .. table.concat(problems, " | "))
return "PASS gore_flesh (F-A to F-L)"
