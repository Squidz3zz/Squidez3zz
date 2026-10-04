-- CharacterPreview: shows a copy of the player's avatar in the menu's ViewportFrame, idling and facing the
-- camera, and waves once when it appears.
-- show(viewport, source) returns the clone, or nil if the viewport was already destroyed.
local CAMERA_FOV = 30
-- Extra room around the standing character (the brief's 1.15 only just fit it) so the arm raised by the wave is not cropped.
local FRAMING_MARGIN = 1.4

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

local CharacterPreview = {}

function CharacterPreview.show(viewport, source)
	-- Play may have destroyed the menu while the avatar was still on its way.
	if not viewport:IsDescendantOf(game) then
		return nil
	end

	local clone = source:Clone()
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local rootPart = clone:FindFirstChild("HumanoidRootPart")
	assert(humanoid and rootPart, "CharacterPreview.show: source has no Humanoid / HumanoidRootPart")

	-- Animate is a LocalScript: left in, it would run inside PlayerGui.
	local idleId = readIdleId(clone)
	local animate = clone:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	rootPart.Anchored = true
	clone.PrimaryPart = rootPart -- the pivot and the bounding box are then oriented like the root, not like the Head
	clone:PivotTo(CFrame.new())
	clone.Parent = viewport.WorldModel

	-- Measured after parenting: accessory welds only settle once the model is in the WorldModel.
	local boxCFrame, boxSize = clone:GetBoundingBox()
	local distance = (boxSize.Y / 2) / math.tan(math.rad(CAMERA_FOV / 2)) * FRAMING_MARGIN
	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = CAMERA_FOV
	camera.CFrame = CFrame.lookAt(boxCFrame.Position + rootPart.CFrame.LookVector * distance, boxCFrame.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local fallback = ANIMATIONS[humanoid.RigType == Enum.HumanoidRigType.R15 and "R15" or "R6"]
	playAnimation(animator, idleId or fallback.idle, true, Enum.AnimationPriority.Idle)
	playAnimation(animator, fallback.wave, false, Enum.AnimationPriority.Action)

	return clone
end

return CharacterPreview
