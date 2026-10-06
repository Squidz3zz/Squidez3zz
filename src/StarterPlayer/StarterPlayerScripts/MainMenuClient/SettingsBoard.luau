-- SettingsBoard: the settings UI of the Settings room, drawn on the room's board.
-- mount(board, playerGui, sounds?) builds a SurfaceGui named SettingsBoardGui (a SurfaceGui only receives clicks while it sits
-- under PlayerGui with its Adornee set) and returns it, hidden. setEnabled shows or hides it and unmount removes it.
-- The board has a header and four rows, all Scale layout inside the SurfaceGui's own canvas (50 pixels per stud):
--   Header                    "SETTINGS"
--   MusicRow.Slider           SoundService.Music volume (VolumeSlider)
--   SfxRow.Slider             SoundService.SFX volume (VolumeSlider)
--   SwayRow.Toggle            Camera Sway, ON / OFF (MenuSettings)
--   EffectsRow.Toggle         Screen Effects, ON / OFF (MenuSettings)
-- A switch flips its MenuSettings value and shows it, and shows it again whenever MenuSettings changes from anywhere
-- else. Nothing here yields: it runs inside SceneDirector's hooks, behind the black screen.
-- `sounds` (optional, ButtonSounds) gives the switch rows their sound effects: hover() when the pointer enters a row (once,
-- not again while it moves around inside it, on its button or its RowHit) and confirm() when the row flips the switch.
-- Both are called in pcall; without `sounds` the rows are silent.
-- Colours and fonts come from the menu theme (MenuTheme.get(): ReplicatedFirst.MenuAssets THEME and Themes, Factory when that
-- cannot be read), read once per mount(): the backdrop, the frame, the header, the rows (and their thin border), the accent
-- bars, the sliders and the ON / OFF switches. Editing them in Studio has no effect: the board is built here, in code.
--
-- Touch targets: on a phone in landscape the board is only about 270 px tall on screen, so the sliders and the ON / OFF
-- buttons themselves are far under the 40 px a finger needs. The whole ROW (about 45 px there) is the target instead: a
-- press anywhere on a slider row starts that slider's drag (the X still maps through the slider's own width), and a
-- tap anywhere on a switch row (SwayRow.RowHit, under the title and the button) flips the switch.
local SoundService = game:GetService("SoundService")

local MenuSettings = require(script.Parent.MenuSettings)
local MenuTheme = require(script.Parent.MenuTheme)
local VolumeSlider = require(script.Parent.VolumeSlider)

local GUI_NAME = "SettingsBoardGui"
local PIXELS_PER_STUD = 50

-- Row layout, as fractions of the canvas height.
local ROWS_TOP = 0.19
local ROW_PITCH = 0.195
local ROW_HEIGHT = 0.17

local SettingsBoard = {}

local function create(className, props, parent)
	local inst = Instance.new(className)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

-- Text in the theme's body font and text colour (new text objects default to Legacy fonts); `props` can override either.
local function label(theme, props, parent)
	local inst = Instance.new("TextLabel")
	inst.BackgroundTransparency = 1
	inst.BorderSizePixel = 0
	inst.FontFace = theme.bodyFont
	inst.TextColor3 = theme.text
	inst.TextScaled = true
	inst.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

-- A row with an accent bar down its left edge (and the theme's thin border, if it has one), like a menu button. `index` is 1
-- (top) to 4.
local function newRow(theme, gui, name, index)
	local row = create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, ROWS_TOP + (index - 1) * ROW_PITCH),
		Size = UDim2.fromScale(0.84, ROW_HEIGHT),
		BackgroundColor3 = theme.boardPanel,
		BorderSizePixel = 0,
	}, gui)
	create("Frame", {
		Name = "Accent",
		Size = UDim2.fromScale(0.015, 1),
		BackgroundColor3 = theme.boardAccent,
		BorderSizePixel = 0,
	}, row)
	if theme.panelBorder then
		create("UIStroke", {
			Name = "PanelBorder",
			Color = theme.panelBorder,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, row)
	end
	return row
end

-- A volume slider row: the title on top, a thick track with an accent Fill and a Knob under it (the shape VolumeSlider
-- drives). The track is tall so it is easy to hit from the camera, and the knob stands out above and below it. The
-- whole row starts a drag, so a finger need not find the thin track.
local function newSliderRow(theme, gui, name, title, index, group)
	local row = newRow(theme, gui, name, index)
	row.Active = true
	label(theme, {
		Name = "Title",
		Text = title,
		Position = UDim2.fromScale(0.05, 0.06),
		Size = UDim2.fromScale(0.7, 0.46),
	}, row)
	local slider = create("Frame", {
		Name = "Slider",
		Active = true,
		Position = UDim2.fromScale(0.05, 0.6),
		Size = UDim2.fromScale(0.9, 0.28),
		BackgroundColor3 = theme.sliderTrack,
		BorderSizePixel = 0,
	}, row)
	create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = theme.boardAccent,
		BorderSizePixel = 0,
	}, slider)
	create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.045, 1.8),
		BackgroundColor3 = theme.sliderKnob,
		BorderSizePixel = 0,
	}, slider)

	if group and group:IsA("SoundGroup") then
		VolumeSlider.attach(slider, group, row)
	else
		warn("SettingsBoard: the " .. title .. " slider has no SoundGroup to control")
	end
	return row
end

local function renderToggle(theme, toggle, on)
	toggle.Text = if on then "ON" else "OFF"
	toggle.BackgroundColor3 = if on then theme.switchOn else theme.switchOff
	toggle.TextColor3 = if on then theme.switchOnText else theme.switchOffText
end

-- An ON / OFF switch row. Returns the row and the connection that keeps the switch in step with MenuSettings
-- (the caller disconnects it with the gui).
local function newSwitchRow(theme, gui, name, title, index, settingName, sounds)
	local row = newRow(theme, gui, name, index)
	local function sfx(soundName)
		if sounds then
			pcall(sounds[soundName])
		end
	end
	-- The whole row is the switch's touch target. It is created first, so it sits under the title and the button, and
	-- the button still takes its own presses. Transparent; it only needs the text properties the board's checks expect.
	local rowHit = create("TextButton", {
		Name = "RowHit",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Selectable = false,
		FontFace = theme.bodyFont,
		Text = "",
		TextScaled = true,
	}, row)
	label(theme, {
		Name = "Title",
		Text = title,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.05, 0.5),
		Size = UDim2.fromScale(0.6, 0.5),
	}, row)
	local toggle = create("TextButton", {
		Name = "Toggle",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.95, 0.5),
		Size = UDim2.fromScale(0.26, 0.64),
		AutoButtonColor = false,
		BorderSizePixel = 0,
		FontFace = theme.labelFont,
		TextScaled = true,
	}, row)
	create("UIStroke", { Color = theme.boardAccent, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, toggle)

	local function render()
		renderToggle(theme, toggle, MenuSettings.get(settingName))
	end
	render()
	local function flip()
		MenuSettings.set(settingName, not MenuSettings.get(settingName))
		sfx("confirm")
	end
	toggle.Activated:Connect(flip)
	rowHit.Activated:Connect(flip)

	-- Hover: once when the pointer comes onto the row. The button sits on top of RowHit, so going from one to the other
	-- is a leave and an enter; `inside` counts the two and the row is only left once neither has the pointer (checked a
	-- moment later, because the leave and the enter can arrive in either order).
	local inside = 0
	local hovered = false
	local function enter()
		inside += 1
		if not hovered then
			hovered = true
			sfx("hover")
		end
	end
	local function leave()
		inside -= 1
		task.defer(function()
			if inside <= 0 then
				hovered = false
			end
		end)
	end
	for _, hit in { rowHit, toggle } do
		hit.MouseEnter:Connect(enter)
		hit.MouseLeave:Connect(leave)
	end
	return row, MenuSettings.changed(settingName):Connect(render)
end

-- Creates SettingsBoardGui on `board`, or returns the one already in `playerGui` (rebuilt if it was made for another
-- board). It starts disabled: setEnabled shows it.
function SettingsBoard.mount(board, playerGui, sounds)
	local existing = playerGui:FindFirstChild(GUI_NAME)
	if existing then
		if existing:IsA("SurfaceGui") and existing.Adornee == board then
			return existing
		end
		existing:Destroy()
	end

	-- The theme: read once, so one board is never half one look and half another.
	local theme = MenuTheme.get()

	-- The face that points at the camera shot; a missing or unknown BoardFace attribute means the Front.
	local faceName = board:GetAttribute("BoardFace")
	local face = if type(faceName) == "string" then Enum.NormalId:FromName(faceName) else nil
	face = face or Enum.NormalId.Front

	local gui = create("SurfaceGui", {
		Name = GUI_NAME,
		Enabled = false,
		Adornee = board,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PIXELS_PER_STUD,
		ClipsDescendants = true,
		-- The room's lamps would dim the board; it should read like a lit panel.
		LightInfluence = 0,
		Active = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})

	create("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = theme.boardBackdrop,
		BorderSizePixel = 0,
	}, gui)
	-- The accent frame around the board. Its stroke is drawn outside the frame, so the frame sits inside the canvas.
	local border = create("Frame", {
		Name = "Border",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.965, 0.97),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, gui)
	create("UIStroke", { Color = theme.boardAccent, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, border)

	label(theme, {
		Name = "Header",
		Text = "SETTINGS",
		FontFace = theme.titleFont,
		TextColor3 = theme.boardHeader,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.04),
		Size = UDim2.fromScale(0.84, 0.10),
	}, gui)
	create("Frame", {
		Name = "Divider",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.15),
		Size = UDim2.fromScale(0.84, 0.007),
		BackgroundColor3 = theme.boardAccent,
		BorderSizePixel = 0,
	}, gui)

	newSliderRow(theme, gui, "MusicRow", "MUSIC", 1, SoundService:FindFirstChild("Music"))
	newSliderRow(theme, gui, "SfxRow", "SOUND EFFECTS", 2, SoundService:FindFirstChild("SFX"))
	local _, swayConnection = newSwitchRow(theme, gui, "SwayRow", "CAMERA SWAY", 3, "CameraSway", sounds)
	local _, effectsConnection = newSwitchRow(theme, gui, "EffectsRow", "SCREEN EFFECTS", 4, "ScreenEffects", sounds)
	-- MenuSettings outlives the board: stop listening once it is gone.
	gui.Destroying:Connect(function()
		swayConnection:Disconnect()
		effectsConnection:Disconnect()
	end)

	gui.Parent = playerGui
	return gui
end

function SettingsBoard.setEnabled(gui, on)
	gui.Enabled = on
end

-- Removes the board. Safe to call when there is none.
function SettingsBoard.unmount(playerGui)
	for _, child in playerGui:GetChildren() do
		if child.Name == GUI_NAME then
			child:Destroy()
		end
	end
end

return SettingsBoard
