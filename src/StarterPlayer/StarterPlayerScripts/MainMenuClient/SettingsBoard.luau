-- SettingsBoard: the settings UI of the Settings room, drawn on the room's board.
-- mount(board, playerGui) builds a SurfaceGui named SettingsBoardGui (a SurfaceGui only receives clicks while it sits
-- under PlayerGui with its Adornee set) and returns it, hidden. setEnabled shows or hides it and unmount removes it.
-- The board has a header and four rows, all Scale layout inside the SurfaceGui's own canvas (50 pixels per stud):
--   Header                    "SETTINGS"
--   MusicRow.Slider           SoundService.Music volume (VolumeSlider)
--   SfxRow.Slider             SoundService.SFX volume (VolumeSlider)
--   SwayRow.Toggle            Camera Sway, ON / OFF (MenuSettings)
--   EffectsRow.Toggle         Screen Effects, ON / OFF (MenuSettings)
-- A switch flips its MenuSettings value and shows it, and shows it again whenever MenuSettings changes from anywhere
-- else. Nothing here yields: it runs inside SceneDirector's hooks, behind the black screen.
local SoundService = game:GetService("SoundService")

local MenuSettings = require(script.Parent.MenuSettings)
local VolumeSlider = require(script.Parent.VolumeSlider)

local GUI_NAME = "SettingsBoardGui"
local PIXELS_PER_STUD = 50

-- Factory palette, the same as the menu buttons: dark steel panels with an amber accent.
local PANEL = Color3.fromRGB(38, 36, 34)
local BACKDROP = Color3.fromRGB(22, 20, 18)
local TRACK = Color3.fromRGB(62, 58, 54)
local AMBER = Color3.fromRGB(255, 150, 30)
local WHITE = Color3.new(1, 1, 1)
local KNOB = Color3.fromRGB(235, 230, 224)
local OFF_FILL = Color3.fromRGB(58, 55, 52)
local OFF_TEXT = Color3.fromRGB(165, 160, 154)

-- Oswald with uppercase labels, like the menu (new text objects default to Legacy fonts).
local FONT = Font.fromEnum(Enum.Font.Oswald)
local FONT_BOLD = Font.new(FONT.Family, Enum.FontWeight.Bold)

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

local function label(props, parent)
	local inst = Instance.new("TextLabel")
	inst.BackgroundTransparency = 1
	inst.BorderSizePixel = 0
	inst.FontFace = FONT
	inst.TextColor3 = WHITE
	inst.TextScaled = true
	inst.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

-- A steel row with an amber bar down its left edge, like a menu button. `index` is 1 (top) to 4.
local function newRow(gui, name, index)
	local row = create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, ROWS_TOP + (index - 1) * ROW_PITCH),
		Size = UDim2.fromScale(0.84, ROW_HEIGHT),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
	}, gui)
	create("Frame", {
		Name = "Accent",
		Size = UDim2.fromScale(0.015, 1),
		BackgroundColor3 = AMBER,
		BorderSizePixel = 0,
	}, row)
	return row
end

-- A volume slider row: the title on top, a thick track with an amber Fill and a Knob under it (the shape VolumeSlider
-- drives). The track is tall so it is easy to hit from the camera, and the knob stands out above and below it.
local function newSliderRow(gui, name, title, index, group)
	local row = newRow(gui, name, index)
	label({
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
		BackgroundColor3 = TRACK,
		BorderSizePixel = 0,
	}, row)
	create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = AMBER,
		BorderSizePixel = 0,
	}, slider)
	create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.045, 1.8),
		BackgroundColor3 = KNOB,
		BorderSizePixel = 0,
	}, slider)

	if group and group:IsA("SoundGroup") then
		VolumeSlider.attach(slider, group)
	else
		warn("SettingsBoard: the " .. title .. " slider has no SoundGroup to control")
	end
	return row
end

local function renderToggle(toggle, on)
	toggle.Text = if on then "ON" else "OFF"
	toggle.BackgroundColor3 = if on then AMBER else OFF_FILL
	toggle.TextColor3 = if on then BACKDROP else OFF_TEXT
end

-- An ON / OFF switch row. Returns the row and the connection that keeps the switch in step with MenuSettings
-- (the caller disconnects it with the gui).
local function newSwitchRow(gui, name, title, index, settingName)
	local row = newRow(gui, name, index)
	label({
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
		FontFace = FONT_BOLD,
		TextScaled = true,
	}, row)
	create("UIStroke", { Color = AMBER, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, toggle)

	local function render()
		renderToggle(toggle, MenuSettings.get(settingName))
	end
	render()
	toggle.Activated:Connect(function()
		MenuSettings.set(settingName, not MenuSettings.get(settingName))
	end)
	return row, MenuSettings.changed(settingName):Connect(render)
end

-- Creates SettingsBoardGui on `board`, or returns the one already in `playerGui` (rebuilt if it was made for another
-- board). It starts disabled: setEnabled shows it.
function SettingsBoard.mount(board, playerGui)
	local existing = playerGui:FindFirstChild(GUI_NAME)
	if existing then
		if existing:IsA("SurfaceGui") and existing.Adornee == board then
			return existing
		end
		existing:Destroy()
	end

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
		BackgroundColor3 = BACKDROP,
		BorderSizePixel = 0,
	}, gui)
	-- The amber frame around the board. Its stroke is drawn outside the frame, so the frame sits inside the canvas.
	local border = create("Frame", {
		Name = "Border",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.965, 0.97),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, gui)
	create("UIStroke", { Color = AMBER, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, border)

	label({
		Name = "Header",
		Text = "SETTINGS",
		FontFace = FONT_BOLD,
		TextColor3 = AMBER,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.04),
		Size = UDim2.fromScale(0.84, 0.10),
	}, gui)
	create("Frame", {
		Name = "Divider",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.15),
		Size = UDim2.fromScale(0.84, 0.007),
		BackgroundColor3 = AMBER,
		BorderSizePixel = 0,
	}, gui)

	newSliderRow(gui, "MusicRow", "MUSIC", 1, SoundService:FindFirstChild("Music"))
	newSliderRow(gui, "SfxRow", "SOUND EFFECTS", 2, SoundService:FindFirstChild("SFX"))
	local _, swayConnection = newSwitchRow(gui, "SwayRow", "CAMERA SWAY", 3, "CameraSway")
	local _, effectsConnection = newSwitchRow(gui, "EffectsRow", "SCREEN EFFECTS", 4, "ScreenEffects")
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
