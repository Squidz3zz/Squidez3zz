-- CharacterPreview: shows a copy of the player's avatar in the menu's ViewportFrame, idling and facing the
-- camera, and waves once when it appears. The camera frames the upper body.
-- show(viewport, source) returns the clone, or nil if the viewport was already destroyed.
-- clonePosed and playIdle are the two halves of "a still copy of an avatar that idles": show uses them for the menu, and
-- CreditsRoom uses them for the avatars standing in the Credits room.
local CAMERA_FOV = 30
-- Room around the upper body (torso bottom to head top). The wave swings the arm about a stud above the head and about
-- three studs to the side of the body, and the menu's CharacterView is a little narrower than tall, so the width
-- decides: measured over a looping wave on R6 and R15 (default and the real avatar), the arm reaches 0.96 of the frame
-- half-width at 2.25 and 0.94 at 2.3 (aspect 0.95; wider frames have more room), and R6 reaches furthest.
local FRAMING_MARGIN = 2.3

-- Fallbacks for models that carry no Animate script (the idle is read from Animate when there is one).
local ANIMATIONS = {
	R15 = { idle = "rbxassetid://507766666", wave = "rbxassetid://507770239" },
	R6 = { idle = "rbxassetid://180435571", wave = "rbxassetid://128777973" },
}

-- Loads and plays one animation. A failure leaves the bind pose and never throws.
local function playAnimation(animator, animationId, looped, priority)
	local ok, err = pcall(function()
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		local track = animator:LoadAnimation(animation)
		track.Looped = looped
		track.Priority = priority
		track:Play()
	end)
	if not ok then
		warn("CharacterPreview: could not play " .. animationId .. ": " .. tostring(err))
	end
end

-- The idle the player's own Animate script would use, or nil if the model has none.
local function readIdleId(model)
	local animate = model:FindFirstChild("Animate")
	local idle = animate and animate:FindFirstChild("idle")
	local animation = idle and idle:FindFirstChild("Animation1")
	if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then
		return animation.AnimationId
	end
	return nil
end

-- The Humanoid's Animator (made if it has none) and the fallback animation ids for its rig.
local function animationTools(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator, ANIMATIONS[humanoid.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6"]
end

-- The centre and height of the upper body: from the bottom of the torso (LowerTorso on R15) to the top of the head.
-- Measured on the model as it stands (upright, at the origin). Falls back to the whole model if it lacks either part.
local function upperBody(clone, rootPart)
	local torso = clone:FindFirstChild("LowerTorso") or clone:FindFirstChild("Torso")
	local head = clone:FindFirstChild("Head")
	if torso and torso:IsA("BasePart") and head and head:IsA("BasePart") then
		local bottom = torso.Position.Y - torso.Size.Y / 2
		local top = head.Position.Y + head.Size.Y / 2
		if top > bottom then
			return Vector3.new(rootPart.Position.X, (top + bottom) / 2, rootPart.Position.Z), top - bottom
		end
	end
	local boxCFrame, boxSize = clone:GetBoundingBox()
	return boxCFrame.Position, boxSize.Y
end

local CharacterPreview = {}

-- A copy of `source` that stands still: no Animate script (a LocalScript, it would run wherever the copy goes),
-- anchored root, the root as the pivot (so the pivot and the bounding box are oriented like the root, not like the Head).
-- Returns the copy, not yet parented, and the idle animation id its Animate script used (nil if it had none).
function CharacterPreview.clonePosed(source)
	local clone = source:Clone()
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local rootPart = clone:FindFirstChild("HumanoidRootPart")
	if not (humanoid and rootPart) then
		clone:Destroy()
		error("CharacterPreview: source has no Humanoid / HumanoidRootPart")
	end

	local idleId = readIdleId(clone)
	local animate = clone:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	rootPart.Anchored = true
	clone.PrimaryPart = rootPart
	return clone, idleId
end

-- Plays the idle on loop. Call it once the copy is parented to a WorldModel or to Workspace: an animation needs that.
-- A failure leaves the bind pose and never throws.
function CharacterPreview.playIdle(clone, idleId)
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local animator, fallback = animationTools(humanoid)
	playAnimation(animator, idleId or fallback.idle, true, Enum.AnimationPriority.Idle)
end

function CharacterPreview.show(viewport, source)
	-- Play may have destroyed the menu while the avatar was still on its way.
	if not viewport:IsDescendantOf(game) then
		return nil
	end

	local clone, idleId = CharacterPreview.clonePosed(source)
	local rootPart = clone.PrimaryPart
	clone:PivotTo(CFrame.new())
	clone.Parent = viewport.WorldModel

	-- Measured after parenting: accessory welds only settle once the model is in the WorldModel.
	local centre, height = upperBody(clone, rootPart)
	local distance = (height / 2) / math.tan(math.rad(CAMERA_FOV / 2)) * FRAMING_MARGIN
	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = CAMERA_FOV
	camera.CFrame = CFrame.lookAt(centre + rootPart.CFrame.LookVector * distance, centre)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	CharacterPreview.playIdle(clone, idleId)
	local animator, fallback = animationTools(clone:FindFirstChildOfClass("Humanoid"))
	playAnimation(animator, fallback.wave, false, Enum.AnimationPriority.Action)

	return clone
end

return CharacterPreview
