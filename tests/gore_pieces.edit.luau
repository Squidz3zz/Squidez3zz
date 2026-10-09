-- Run in the Edit datamodel. Checks what studio/build_gore.luau builds: ServerStorage.Gore.FleshChart (the user's chart, moved
-- untouched) and ServerStorage.Gore.Pieces.<Limb>.<Variant1|Variant2|Death> (the torso: Sealed, Open, Death), plus
-- Pieces.FullBody.Variant1.
-- Cases, run in this order, with studio/build_gore.luau run where an arrow says:
--   A   checks the build and records a fingerprint of every piece      -> run the build again
--   B   checks the build again and that the second run changed nothing
local CASE = "A"

local ServerStorage = game:GetService("ServerStorage")

local CHART_DESCENDANTS = 400 -- Workspace.Mesh.FleshChart as the user built it (measured 2026-10-09)
local PRINT_ATTRIBUTE = "GorePiecesTestPrint" -- on ServerStorage, between case A and case B
local TOLERANCE = 0.2 -- studs
local PART = {
	Head = "Head",
	Torso = "Torso",
	LeftArm = "Left Arm",
	RightArm = "Right Arm",
	LeftLeg = "Left Leg",
	RightLeg = "Right Leg",
}
local LIMBS = { "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local FLESH = { LeftArm = "LeftarmFlesh", RightArm = "RightarmFlesh", LeftLeg = "LeftlegFlesh", RightLeg = "RightlegFlesh" }
local BONE = { LeftArm = "LeftArm", RightArm = "RightArm", LeftLeg = "LeftLeg", RightLeg = "RightLeg" }

local function get(parent: Instance, name: string, class: string): any
	local inst = parent:FindFirstChild(name)
	assert(inst, parent:GetFullName() .. "." .. name .. " missing")
	assert(inst:IsA(class), inst:GetFullName() .. " must be a " .. class .. ", is a " .. inst.ClassName)
	return inst
end

-- A set's pieces by name, after checking each one is a well-formed piece.
local function pieces(set: Model): { [string]: BasePart }
	local byName = {}
	for _, piece in set:GetChildren() do
		assert(piece:IsA("BasePart"), piece:GetFullName() .. " is not a BasePart")
		assert(not byName[piece.Name], set:GetFullName() .. " has two pieces named " .. piece.Name)
		assert(not piece.Anchored and not piece.CanCollide and piece.Massless, piece:GetFullName() .. " must be unanchored, non-collidable and massless")
		assert(typeof(piece:GetAttribute("Offset")) == "CFrame", piece:GetFullName() .. " has no Offset")
		local layer = piece:GetAttribute("Layer")
		local deep = piece:IsA("UnionOperation") or piece.Name == "Skull"
		assert(layer == (if deep then "deep" else "flesh"), piece:GetFullName() .. " has Layer " .. tostring(layer))
		byName[piece.Name] = piece
	end
	return byName
end

local function has(set: Model, byName, name: string, expected: boolean)
	assert((byName[name] ~= nil) == expected, set:GetFullName() .. (if expected then " lacks " else " must not have ") .. name)
end

local function count(byName, layer: string): number
	local n = 0
	for _, piece in byName do
		n += if piece:GetAttribute("Layer") == layer then 1 else 0
	end
	return n
end

local function check(): string
	assert(not workspace:FindFirstChild("Mesh"), "Workspace.Mesh must be gone")
	local gore = get(ServerStorage, "Gore", "Folder")
	local chart = get(gore, "FleshChart", "Model")
	local found = #chart:GetDescendants()
	assert(found == CHART_DESCENDANTS, "the FleshChart has " .. found .. " descendants, not " .. CHART_DESCENDANTS)
	for _, p in chart:GetDescendants() do
		assert(p:GetAttribute("Offset") == nil and p:GetAttribute("Layer") == nil, "the chart was touched: " .. p:GetFullName())
	end
	local sizing = chart.SizingModel.FullBodyFleshSizing
	local dummy = chart.SizingModel.thxalloverme123
	local all = get(gore, "Pieces", "Folder")

	-- Every piece whose twin is in FullBodyFleshSizing, put on the dummy's matching part, lands on that twin.
	local function placed(set: Model, partOf: (BasePart) -> string)
		for _, piece in set:GetChildren() do
			local twin = sizing:FindFirstChild(piece.Name, true)
			if twin then
				local at = (dummy[partOf(piece)].CFrame * piece:GetAttribute("Offset")).Position
				local off = (at - twin.Position).Magnitude
				assert(off <= TOLERANCE, ("%s lands %.2f studs from its place in FullBodyFleshSizing"):format(piece:GetFullName(), off))
			end
		end
	end

	for _, limb in LIMBS do
		local folder = get(all, limb, "Folder")
		local v1, v2, death = get(folder, "Variant1", "Model"), get(folder, "Variant2", "Model"), get(folder, "Death", "Model")
		local p1, p2, pd = pieces(v1), pieces(v2), pieces(death)
		-- Variant1 as drawn: the flesh only. Variant2: flesh and bone (user, 2026-10-09). Death: the stub only (R12).
		has(v1, p1, FLESH[limb], true)
		assert(count(p1, "deep") == 0, v1:GetFullName() .. " must have no bone")
		has(v2, p2, FLESH[limb], true)
		has(v2, p2, BONE[limb], true)
		local only = death:GetChildren()
		assert(#only == 1 and only[1].Name:match("^Stub") and only[1]:GetAttribute("Layer") == "deep", death:GetFullName() .. " must hold one Stub* and nothing else")
		for _, set in { v1, v2, death } do
			placed(set, function()
				return PART[limb]
			end)
		end
	end

	local head = get(all, "Head", "Folder")
	local h1, h2, hd = get(head, "Variant1", "Model"), get(head, "Variant2", "Model"), get(head, "Death", "Model")
	local ph1, ph2, phd = pieces(h1), pieces(h2), pieces(hd)
	has(h1, ph1, "HeadFlesh", true)
	has(h1, ph1, "Skull", false)
	for _, pair in { { h2, ph2 }, { hd, phd } } do
		has(pair[1], pair[2], "HeadFlesh", true)
		has(pair[1], pair[2], "Skull", true)
	end
	for _, set in { h1, h2, hd } do
		placed(set, function()
			return "Head"
		end)
	end

	local torso = get(all, "Torso", "Folder")
	local sealed, open, td = get(torso, "Sealed", "Model"), get(torso, "Open", "Model"), get(torso, "Death", "Model")
	assert(not torso:FindFirstChild("Variant1") and not torso:FindFirstChild("Variant2"), "the torso's variants are Sealed and Open")
	local ps, po, ptd = pieces(sealed), pieces(open), pieces(td)
	has(sealed, ps, "TorsoFilling", true)
	has(sealed, ps, "Ribcage", false)
	has(open, po, "TorsoFilling", false)
	has(open, po, "Ribcage", true)
	has(td, ptd, "Ribcage", true)
	for _, set in { sealed, open, td } do
		has(set, pieces(set), "TorsoFlesh", true)
		placed(set, function()
			return "Torso"
		end)
	end

	local full = get(get(all, "FullBody", "Folder"), "Variant1", "Model")
	local pf = pieces(full)
	for limb, name in FLESH do
		has(full, pf, name, true)
		assert(pf[name]:GetAttribute("Limb") == limb, pf[name]:GetFullName() .. " has Limb " .. tostring(pf[name]:GetAttribute("Limb")))
	end
	has(full, pf, "HeadFlesh", true)
	has(full, pf, "TorsoFlesh", true)
	placed(full, function(piece)
		return PART[piece:GetAttribute("Limb")]
	end)

	-- A fingerprint of every piece: where it is, its name, size, layer and offset (rounded).
	local lines = {}
	for _, piece in all:GetDescendants() do
		if piece:IsA("BasePart") then
			local o = piece:GetAttribute("Offset")
			local x, y, z = o:ToEulerAnglesXYZ()
			table.insert(lines, ("%s %s %s %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f"):format(
				piece:GetFullName(), piece:GetAttribute("Layer"), tostring(piece:GetAttribute("Limb")),
				piece.Size.X, piece.Size.Y, piece.Size.Z, o.X, o.Y, o.Z, x, y, z
			))
		end
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

if CASE == "A" then
	local stamp = check()
	ServerStorage:SetAttribute(PRINT_ATTRIBUTE, stamp)
	local _, n = stamp:gsub("\n", "")
	return "PASS gore_pieces A (" .. (n + 1) .. " pieces; now run studio/build_gore.luau again, then case B)"
elseif CASE == "B" then
	local stamp = check()
	local recorded = ServerStorage:GetAttribute(PRINT_ATTRIBUTE)
	assert(type(recorded) == "string", "run case A first")
	ServerStorage:SetAttribute(PRINT_ATTRIBUTE, nil)
	assert(stamp == recorded, "the second run changed the pieces")
	return "PASS gore_pieces B (the second run changed nothing)"
end
error("unknown CASE " .. CASE)
