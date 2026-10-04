-- ButtonEffects: hover/press "pop" for the menu buttons.
-- attach(button) adds a UIScale (PopScale) and a UIStroke (PopStroke) to the button and wires the input events.
-- setState(button, state) is the only place tweens happen: events call it, and so do the tests. It finds
-- PopScale/PopStroke on the button itself and keeps no state of its own, so it works on any attached button.
local TweenService = game:GetService("TweenService")

local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local STATES = {
	idle = { scale = 1, strokeTransparency = 1 },
	hover = { scale = 1.1, strokeTransparency = 0 },
	press = { scale = 0.95, strokeTransparency = 0 },
}

local ButtonEffects = {}

function ButtonEffects.setState(button, state)
	local target = STATES[state]
	assert(target, "ButtonEffects.setState: unknown state " .. tostring(state))
	local popScale = button:FindFirstChild("PopScale")
	local popStroke = button:FindFirstChild("PopStroke")
	assert(popScale and popStroke, "ButtonEffects.setState: " .. button:GetFullName() .. " is not attached")

	-- Playing a tween cancels any tween already running on the same property, so quick state changes never fight.
	TweenService:Create(popScale, TWEEN_INFO, { Scale = target.scale }):Play()
	TweenService:Create(popStroke, TWEEN_INFO, { Transparency = target.strokeTransparency }):Play()
end

function ButtonEffects.attach(button)
	if button:FindFirstChild("PopScale") then
		return
	end

	local popScale = Instance.new("UIScale")
	popScale.Name = "PopScale"
	popScale.Scale = STATES.idle.scale
	popScale.Parent = button

	local popStroke = Instance.new("UIStroke")
	popStroke.Name = "PopStroke"
	popStroke.Color = Color3.new(1, 1, 1)
	popStroke.Thickness = 2
	popStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	popStroke.Transparency = STATES.idle.strokeTransparency
	popStroke.Parent = button

	local mouseOver = false

	button.MouseEnter:Connect(function()
		mouseOver = true
		ButtonEffects.setState(button, "hover")
	end)
	button.MouseLeave:Connect(function()
		mouseOver = false
		ButtonEffects.setState(button, "idle")
	end)
	button.SelectionGained:Connect(function()
		ButtonEffects.setState(button, "hover")
	end)
	button.SelectionLost:Connect(function()
		ButtonEffects.setState(button, "idle")
	end)
	button.MouseButton1Down:Connect(function()
		ButtonEffects.setState(button, "press")
	end)
	button.MouseButton1Up:Connect(function()
		ButtonEffects.setState(button, if mouseOver then "hover" else "idle")
	end)

	-- Touch has no cursor, so a finger down counts as hover and lifting it as idle.
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			ButtonEffects.setState(button, "hover")
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			ButtonEffects.setState(button, "idle")
		end
	end)
end

return ButtonEffects
