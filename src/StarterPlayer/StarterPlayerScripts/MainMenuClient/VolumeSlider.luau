-- VolumeSlider: a draggable music volume slider.
-- attach(slider, group) wires mouse/touch dragging on `slider` (a Frame holding Fill and Knob Frames) to group.Volume.
-- setAlpha(slider, group, alpha) is the only place the volume and the visuals change: dragging calls it, and so do
-- the tests. It acts only on the Instances it is given and keeps no state of its own.
local UserInputService = game:GetService("UserInputService")

local VolumeSlider = {}

function VolumeSlider.setAlpha(slider, group, alpha)
	alpha = math.clamp(alpha, 0, 1)
	group.Volume = alpha

	local fill = slider.Fill
	local knob = slider.Knob
	-- Only the X scale follows alpha; the rest of the layout stays as designed.
	fill.Size = UDim2.new(UDim.new(alpha, fill.Size.X.Offset), fill.Size.Y)
	knob.Position = UDim2.new(UDim.new(alpha, knob.Position.X.Offset), knob.Position.Y)
end

local function alphaAt(slider, input)
	return (input.Position.X - slider.AbsolutePosition.X) / slider.AbsoluteSize.X
end

function VolumeSlider.attach(slider, group)
	VolumeSlider.setAlpha(slider, group, group.Volume)

	local dragging = false

	local function startDrag(input)
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
		local isTouch = input.UserInputType == Enum.UserInputType.Touch
		-- The slider and its knob both report the press, so a drag already running ignores the second report.
		if dragging or not (isMouse or isTouch) then
			return
		end
		dragging = true
		VolumeSlider.setAlpha(slider, group, alphaAt(slider, input))

		local changedConnection, endedConnection
		changedConnection = UserInputService.InputChanged:Connect(function(changed)
			-- A mouse drag follows the cursor; a touch drag follows the finger that started it.
			local follows = if isMouse then changed.UserInputType == Enum.UserInputType.MouseMovement else changed == input
			if follows then
				VolumeSlider.setAlpha(slider, group, alphaAt(slider, changed))
			end
		end)
		endedConnection = UserInputService.InputEnded:Connect(function(ended)
			local releases = if isMouse then ended.UserInputType == Enum.UserInputType.MouseButton1 else ended == input
			if releases then
				changedConnection:Disconnect()
				endedConnection:Disconnect()
				dragging = false
			end
		end)
	end

	slider.InputBegan:Connect(startDrag)
	slider.Knob.InputBegan:Connect(startDrag)
end

return VolumeSlider
