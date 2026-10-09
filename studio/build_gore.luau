-- Build script: run in the Edit datamodel via execute_luau (or paste it into the Command Bar).
-- Makes the gore system's flesh pieces from the user's FleshChart:
--   ServerStorage.Gore.FleshChart   the user's Workspace.Mesh.FleshChart, moved here untouched the first time (the emptied
--                                   Workspace.Mesh folder is removed). It stays the reference: the pieces are read from it.
--   ServerStorage.Gore.Pieces       <Limb>.<Variant1|Variant2|Death> for Head, LeftArm, RightArm, LeftLeg and RightLeg;
--                                   Torso.<Sealed|Open|Death>; FullBody.Variant1. Each is a Model of pieces.
-- Each piece is a copy of a chart piece: unanchored, not collidable, massless, with the attributes
--   Offset  its CFrame relative to the R6 part it belongs to (put it on at part.CFrame * Offset)
--   Layer   "deep" for the bone (every union: the limb bones, Ribcage, Stub1) and the Skull, else "flesh"
--   Limb    the limb key it belongs to (useful in FullBody.Variant1, which holds every limb's pieces)
-- What each set holds, from the chart (user, 2026-10-09; rulings R12 to R14):
--   arm or leg  Variant1  that limb's pieces in <Limb>Variant1: its flesh only
--               Variant2  that limb's flesh and bone as on the rest of the chart body (DeathBodyModelFullBody), since the
--                         chart's <Limb>Variant2 leaves the limb out
--               Death     the bone stub of its DeathBodyModel (the left arm's is named Union in the chart; the copy is Stub1)
--   Head        Variant1  HeadFlesh (HeadVariant1); Variant2 HeadFlesh and Skull (as on the rest of the body); Death the same
--               (DeathBodyModelHead)
--   Torso       Sealed    TorsoVariant1's torso: its flesh and TorsoFilling
--               Open      TorsoVariant2's torso (no filling) plus the Ribcage from DeathBodyModelTorso
--               Death     DeathBodyModelTorso's torso: its flesh and the Ribcage
--   FullBody    Variant1  every piece of FullBodyVariant1
-- A piece's limb is found by where it sits, not by its name (a few chart names are off): its chart body is laid onto the
-- SizingModel's dummy (thxalloverme123) by matching that body's Torso.TorsoFlesh to FullBodyFleshSizing's, scaled to it,
-- and the piece goes to the dummy's R6 part it is in or nearest to. A stub is the exception: its centre is inside the torso,
-- so it goes to the limb of the chart model it is in. Of two chart models with the same name, the first is used.
-- Safe to run again: the pieces are made again from the chart each time, so after you change the chart, run this again. To
-- edit the chart, drag ServerStorage.Gore.FleshChart into Workspace, change it, drag it back, and run this.
local ServerStorage = game:GetService("ServerStorage")

local PART = {
	Head = "Head",
	Torso = "Torso",
	LeftArm = "Left Arm",
	RightArm = "Right Arm",
	LeftLeg = "Left Leg",
	RightLeg = "Right Leg",
}

local gore = ServerStorage:FindFirstChild("Gore")
if not gore then
	gore = Instance.new("Folder")
	gore.Name = "Gore"
	gore.Parent = ServerStorage
end

-- Move the chart, once.
local mesh = workspace:FindFirstChild("Mesh")
local loose = mesh and mesh:FindFirstChild("FleshChart")
if loose then
	assert(not gore:FindFirstChild("FleshChart"), "build_gore: there is a FleshChart in both Workspace.Mesh and ServerStorage.Gore; keep one")
	loose.Parent = gore
	if #mesh:GetChildren() == 0 then
		mesh:Destroy()
	end
end
local chart = gore:FindFirstChild("FleshChart")
assert(chart, "build_gore: ServerStorage.Gore.FleshChart is missing (and so is Workspace.Mesh.FleshChart)")

local sizing = chart.SizingModel.FullBodyFleshSizing
local dummy = chart.SizingModel.thxalloverme123
local sizingTorso = sizing.Torso.TorsoFlesh

local function model(group: string, name: string): Model
	local found = chart[group]:FindFirstChild(name) -- the first, if there are two
	assert(found, "build_gore: FleshChart." .. group .. "." .. name .. " is missing")
	return found
end

-- Where a chart piece sits on the dummy, and how much bigger it is there.
local function onDummy(body: Model, piece: BasePart): (CFrame, number)
	local torso = body.Torso.TorsoFlesh
	local scale = sizingTorso.Size.Y / torso.Size.Y
	local rel = torso.CFrame:ToObjectSpace(piece.CFrame)
	return sizingTorso.CFrame * (rel - rel.Position + rel.Position * scale), scale
end

-- The limb whose dummy part the point is in, or nearest to.
local function limbAt(point: Vector3): string
	local best, bestDistance = nil, math.huge
	for key, name in PART do
		local part = dummy[name]
		local p = part.CFrame:PointToObjectSpace(point)
		local half = part.Size / 2
		local distance = (p - p:Max(-half):Min(half)).Magnitude
		if distance < bestDistance then
			best, bestDistance = key, distance
		end
	end
	return best
end

local function isStub(piece: BasePart): boolean
	return piece:IsA("UnionOperation") and (piece.Name:match("^Stub") ~= nil or piece.Name == "Union")
end

-- The pieces of one chart body: { piece, limb } for each BasePart in it.
local function piecesOf(body: Model, stubLimb: string?)
	local list = {}
	for _, piece in body:GetDescendants() do
		if piece:IsA("BasePart") then
			local limb = if isStub(piece) then stubLimb else limbAt((onDummy(body, piece)).Position)
			table.insert(list, { piece = piece, limb = limb })
		end
	end
	return list
end

local function copy(body: Model, piece: BasePart, limb: string, into: Model)
	local at, scale = onDummy(body, piece)
	local clone = piece:Clone()
	for _, child in clone:GetChildren() do
		child:Destroy() -- welds, scripts or anything else the chart piece carries
	end
	if isStub(clone) then
		clone.Name = "Stub1"
	end
	clone.Size = piece.Size * scale
	clone.CFrame = at
	clone.Anchored = false
	clone.CanCollide = false
	clone.Massless = true
	clone:SetAttribute("Offset", dummy[PART[limb]].CFrame:ToObjectSpace(at))
	clone:SetAttribute("Layer", if clone:IsA("UnionOperation") or clone.Name == "Skull" then "deep" else "flesh")
	clone:SetAttribute("Limb", limb)
	clone.Parent = into
end

-- A set: from each source { group, model name, keep(piece name) }, the pieces that belong to the limb.
local function set(limb: string, sources): Model
	local into = Instance.new("Model")
	for _, source in sources do
		local body = model(source[1], source[2])
		for _, entry in piecesOf(body, limb) do
			if (entry.limb == limb or limb == "FullBody") and (not source[3] or source[3](entry.piece.Name)) then
				copy(body, entry.piece, if limb == "FullBody" then entry.limb else limb, into)
			end
		end
	end
	return into
end

local function only(name: string)
	return function(pieceName: string)
		return pieceName == name
	end
end

local DEATH = {
	LeftArm = "DeathBodyModelLeftArmExp",
	RightArm = "DeathBodyModelRightArmExp",
	LeftLeg = "DeathBodyModelLeftLegExp",
	RightLeg = "DeathBodyModelRightLefExp",
	Head = "DeathBodyModelHead",
}

local pieces = Instance.new("Folder")
pieces.Name = "Pieces"
local function folder(name: string, sets: { [string]: Model })
	local f = Instance.new("Folder")
	f.Name = name
	for setName, m in sets do
		m.Name = setName
		m.Parent = f
	end
	f.Parent = pieces
end

for _, limb in { "Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg" } do
	local group = limb .. "Models"
	folder(limb, {
		Variant1 = set(limb, { { group, limb .. "Variant1" } }),
		Variant2 = set(limb, { { "FullBodyModels", "DeathBodyModelFullBody" } }),
		Death = set(limb, { { group, DEATH[limb] } }),
	})
end
folder("Torso", {
	Sealed = set("Torso", { { "TorsoModels", "TorsoVariant1" } }),
	Open = set("Torso", { { "TorsoModels", "TorsoVariant2" }, { "TorsoModels", "DeathBodyModelTorso", only("Ribcage") } }),
	Death = set("Torso", { { "TorsoModels", "DeathBodyModelTorso" } }),
})
folder("FullBody", { Variant1 = set("FullBody", { { "FullBodyModels", "FullBodyVariant1" } }) })

local old = gore:FindFirstChild("Pieces")
if old then
	old:Destroy()
end
pieces.Parent = gore

local n = 0
for _, p in pieces:GetDescendants() do
	n += if p:IsA("BasePart") then 1 else 0
end
return ("build_gore: %d pieces in ServerStorage.Gore.Pieces"):format(n)
