-- MenuAssets: the one place to edit the menu's look (THEME), its sound ids, the loading screen's title and tips, and the loading timings.
-- It lives in ReplicatedFirst so the loading screen can read it before anything else has replicated.
-- Used by LoadingScreen (this folder) and by the menu itself (MainMenuClient: its theme, its music, its button sounds, and how
-- long it waits for the loading screen).
--
-- Sounds: the keys are fixed (the menu looks them up by name); change only the asset ids. An id can be typed as a plain
-- number (123456) or in quotes ("123456" or "rbxassetid://123456"): the menu turns all three into rbxassetid://123456
-- (soundId below). A sound that Roblox refuses to load (wrong id, or the asset is not yours / not public) is skipped with a
-- warning, and its key is listed in the PlayerGui attribute LoadingFailedSounds.
--   Hover          pointer or gamepad selection enters a menu button
--   Confirm        clicking a button (except PLAY)
--   PlaySelect     clicking PLAY
--   MenuMusic      the main menu's looping track
--   SettingsMusic  the Settings room's looping track
--   CreditsMusic   the Credits room's looping track
--
-- GAME_TITLE: the big title on the loading screen. The main menu has its own title, which is not set here: it is the Title
-- TextLabel inside ReplicatedStorage.MainMenu, edited in Studio.
--
-- Tips: shown one at a time on the loading screen, a new one every TIP_SECONDS. Keep them UPPERCASE and short
-- (about 50 characters or fewer, so they stay on one line on a phone).
--
-- LOADING_MIN_SECONDS: the loading screen always stays up at least this long (so it never just flashes by).
-- LOADING_MAX_SECONDS: it hands over to the menu after this long at the latest, even if an asset is still loading.
--   Keep MIN at most MAX. MainMenuClient reads both too: the menu waits for the longer of the two, plus 5 seconds, for the
--   loading screen to hand over.
-- TIP_SECONDS: how long each tip is shown.
-- MENU_AVATAR_WAIT: how long the loading screen waits for your avatar (the one the menu shows on the right). The menu does not
-- need it: if it is not ready in time the loading screen hands over anyway, and the avatar appears as soon as it is ready.
--
-- THEME: the look of the whole menu, as the name of one preset in Themes (further down). It paints the colours and fonts of the
-- main menu (title, PLAY / SETTINGS / CREDITS / BACK, the dark screen edges), the loading screen, the Settings board and the
-- name label in Credits.
--   THEME = "Factory"        the rusty factory look: dark steel panels, amber, Oswald.
--   THEME = "SterileBright"  a bright bio-lab: white panels, teal, storm-blue text, Michroma and Titillium Web.
-- To make your own, copy a whole preset inside Themes, give the copy a new name (CleanRoom = { ... }), change the colours you
-- like, and set THEME = "CleanRoom". A preset may leave a key out: that key then uses Factory's value, so a half-written preset
-- never breaks the menu. An unknown THEME name, or a value of the wrong kind (text where a colour belongs), uses Factory's
-- value too, with one warning in the Output window.
-- MenuAssets.theme() hands the finished theme (your preset on top of Factory) to the menu, the loading screen, the Settings
-- board and Credits; it returns a fresh table each time.
-- What a theme does NOT do: it paints colours and fonts only. The main menu's words (its Title), positions and sizes are still
-- edited in Studio (ReplicatedStorage.MainMenu), but the colours and fonts of the pieces a theme paints are NOT: while a theme
-- is active it paints over them when the menu opens, so editing them in Studio has no effect (change the theme instead). The
-- 3D rooms and their lamps, the black fade and the room lighting are not themed.
local MenuAssets = {
	GAME_TITLE = "A Regular Experiment",

	THEME = "SterileBright",

	Sounds = {
		Hover = "rbxassetid://113223325628963",
		Confirm = "rbxassetid://111174530730534",
		PlaySelect = "rbxassetid://81613840001484",
		MenuMusic = "rbxassetid://96770396029175",
		SettingsMusic = "rbxassetid://108614839813561",
		CreditsMusic = "rbxassetid://88263973909083",
	},

	Tips = {
		"TIP: THE FURNACE NEVER SLEEPS. NEITHER DO WE.",
		"TIP: KEEP YOUR HANDS CLEAR OF THE ASSEMBLY LINE.",
		"TIP: A WELL-OILED BELT IS A HAPPY BELT.",
		"TIP: STEAM VENTS ARE LOUD. YOU WILL GET USED TO IT.",
		"TIP: EVERY GEAR COUNTS, EVEN THE SMALL ONES.",
		"TIP: SHIFT CHANGE IS AT DAWN. DO NOT BE LATE.",
		"TIP: IF IT IS HOT, DO NOT TOUCH IT.",
		"TIP: THE FOREMAN IS ALWAYS WATCHING.",
	},

	LOADING_MIN_SECONDS = 2,
	LOADING_MAX_SECONDS = 20,
	TIP_SECONDS = 4,
	MENU_AVATAR_WAIT = 5,

	-- Each theme is a table of the keys below (colours are Color3.fromRGB, fonts are Font.new). The comments on the Factory keys
	-- say what each one paints; every other preset uses the same keys.
	Themes = {
		Factory = {
			-- Fonts. titleFont: the main menu's Title, the loading screen's title, the Settings header. bodyFont: the buttons,
			-- the tips, the Settings row names. labelFont: the ON / OFF switches and the name label in Credits.
			titleFont = Font.new(Font.fromEnum(Enum.Font.Oswald).Family, Enum.FontWeight.Bold),
			bodyFont = Font.fromEnum(Enum.Font.Oswald),
			labelFont = Font.new(Font.fromEnum(Enum.Font.Oswald).Family, Enum.FontWeight.Bold),

			-- The title's letters, and the outline around them (transparency 0 is fully visible).
			titleText = Color3.fromRGB(255, 255, 255),
			titleStroke = Color3.fromRGB(255, 150, 30),
			titleStrokeTransparency = 0,
			titleStrokeThickness = 2,

			-- Buttons: panel is their fill, accent the bar down their left edge, text their letters. panelBorder (not set here)
			-- would be a thin outline around each panel; leave it out for no outline. textMuted is the quieter text (the loading
			-- tips).
			panel = Color3.fromRGB(38, 36, 34),
			accent = Color3.fromRGB(255, 150, 30),
			text = Color3.fromRGB(255, 255, 255),
			textMuted = Color3.fromRGB(220, 208, 190),
			-- The outline that appears around a button when it is hovered or selected.
			hoverStroke = Color3.fromRGB(255, 150, 30),

			-- The shaded screen edges (transparency of the outer edge: 0 is solid, 1 is invisible; they always fade to invisible
			-- on the inside). hazardStripe = true adds a thin diagonal stripe of hazardYellow and hazardDark across the top of
			-- the screen, on the menu and on the loading screen.
			vignette = Color3.fromRGB(12, 9, 6),
			vignetteTransparency = 0.15,
			hazardStripe = false,
			hazardYellow = Color3.fromRGB(242, 193, 46),
			hazardDark = Color3.fromRGB(29, 37, 41),

			-- The loading screen's background and its spinning ring.
			loadingBackdrop = Color3.fromRGB(16, 14, 12),
			spinner = Color3.fromRGB(255, 150, 30),

			-- The Settings board: behind the rows, the rows, the accent (the frame, the divider, the bars, the slider fill), the
			-- "SETTINGS" header, the slider track and knob, and the ON / OFF switches (fill and letters).
			boardBackdrop = Color3.fromRGB(22, 20, 18),
			boardPanel = Color3.fromRGB(38, 36, 34),
			boardAccent = Color3.fromRGB(255, 150, 30),
			boardHeader = Color3.fromRGB(255, 150, 30),
			sliderTrack = Color3.fromRGB(62, 58, 54),
			sliderKnob = Color3.fromRGB(235, 230, 224),
			switchOn = Color3.fromRGB(255, 150, 30),
			switchOff = Color3.fromRGB(58, 55, 52),
			switchOnText = Color3.fromRGB(22, 20, 18),
			switchOffText = Color3.fromRGB(165, 160, 154),

			-- Credits: the outline round the avatar you point at, and its name label (fill, letters, outline).
			creditHighlight = Color3.fromRGB(255, 150, 30),
			nameLabelBg = Color3.fromRGB(38, 36, 34),
			nameLabelText = Color3.fromRGB(255, 255, 255),
			nameLabelBorder = Color3.fromRGB(255, 150, 30),
		},

		SterileBright = {
			titleFont = Font.new("rbxasset://fonts/families/Michroma.json"),
			bodyFont = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.SemiBold),
			labelFont = Font.new("rbxasset://fonts/families/TitilliumWeb.json", Enum.FontWeight.Bold),

			titleText = Color3.fromRGB(52, 73, 90),
			titleStroke = Color3.fromRGB(255, 255, 255),
			titleStrokeTransparency = 0,
			titleStrokeThickness = 1.5,

			panel = Color3.fromRGB(255, 255, 255),
			panelBorder = Color3.fromRGB(185, 201, 205),
			accent = Color3.fromRGB(19, 184, 166),
			text = Color3.fromRGB(75, 101, 119),
			textMuted = Color3.fromRGB(110, 130, 145),
			hoverStroke = Color3.fromRGB(19, 184, 166),

			vignette = Color3.fromRGB(205, 218, 222),
			vignetteTransparency = 0.35,
			hazardStripe = true,
			hazardYellow = Color3.fromRGB(242, 193, 46),
			hazardDark = Color3.fromRGB(29, 37, 41),

			loadingBackdrop = Color3.fromRGB(233, 239, 241),
			spinner = Color3.fromRGB(19, 184, 166),

			boardBackdrop = Color3.fromRGB(233, 239, 241),
			boardPanel = Color3.fromRGB(255, 255, 255),
			boardAccent = Color3.fromRGB(19, 184, 166),
			boardHeader = Color3.fromRGB(52, 73, 90),
			sliderTrack = Color3.fromRGB(205, 216, 220),
			sliderKnob = Color3.fromRGB(52, 73, 90),
			switchOn = Color3.fromRGB(19, 184, 166),
			switchOff = Color3.fromRGB(225, 232, 234),
			switchOnText = Color3.fromRGB(255, 255, 255),
			switchOffText = Color3.fromRGB(75, 101, 119),

			creditHighlight = Color3.fromRGB(19, 184, 166),
			nameLabelBg = Color3.fromRGB(255, 255, 255),
			nameLabelText = Color3.fromRGB(75, 101, 119),
			nameLabelBorder = Color3.fromRGB(19, 184, 166),
		},
	},
}

-- Which warnings have been given already, so a wrong THEME warns once, not on every call.
local warned = {}

local function warnOnce(key, message)
	if not warned[key] then
		warned[key] = true
		warn(message)
	end
end

-- The finished theme: Factory's keys, with the chosen preset's keys on top. Returns a fresh table every time. A key the preset
-- leaves out keeps Factory's value; a value of another kind than Factory's (text where a colour belongs) and a key Factory
-- does not have are ignored, with one warning. panelBorder has no value in Factory (no outline), so it is accepted as a colour.
-- An unknown THEME name (or none) gives Factory itself, with one warning. The menu, the loading screen, the Settings board
-- and Credits all read their colours and fonts through this.
function MenuAssets.theme()
	local presets = if type(MenuAssets.Themes) == "table" then MenuAssets.Themes else {}
	local factory = presets.Factory
	-- Factory renamed or deleted: the chosen preset is taken as it is (there is nothing to check its values against), and the
	-- keys it leaves out are filled from the menu's built-in Factory look by MenuTheme and the loading screen.
	local factoryMissing = type(factory) ~= "table"
	if factoryMissing then
		warnOnce("noFactory", "MenuAssets: Themes.Factory is missing (never rename or delete it); using the chosen preset as it is, and the built-in Factory look for what it leaves out")
		factory = {}
	end
	local theme = {}
	for key, value in factory do
		theme[key] = value
	end

	local name = MenuAssets.THEME
	local chosen = if type(name) == "string" then presets[name] else nil
	if type(chosen) ~= "table" then
		warnOnce("unknown:" .. tostring(name), "MenuAssets: THEME '" .. tostring(name) .. "' is not one of Themes; using Factory")
		return theme
	end
	if chosen == factory then
		return theme
	end
	for key, value in chosen do
		local want = if factoryMissing then typeof(value) elseif key == "panelBorder" then "Color3" else typeof(factory[key])
		if want == "nil" then
			warnOnce(name .. "." .. tostring(key), "MenuAssets: theme '" .. name .. "' has an unknown key '" .. tostring(key) .. "' (ignored)")
		elseif typeof(value) == want then
			theme[key] = value
		else
			warnOnce(
				name .. "." .. tostring(key),
				"MenuAssets: theme '"
					.. name
					.. "' key '"
					.. tostring(key)
					.. "' should be a "
					.. want
					.. ", it is a "
					.. typeof(value)
					.. "; using Factory's value"
			)
		end
	end
	return theme
end

-- The one place a typed sound id becomes what a Sound's SoundId needs: 123456 and "123456" both give "rbxassetid://123456".
-- Any other text is kept as it is ("rbxassetid://123456" already is one). Returns nil for no usable id: nothing, empty or blank
-- text, a number that is not a whole number above 0, or anything that is not a number or text. ButtonSounds, MenuAudio and
-- LoadingScreen all read MenuAssets.Sounds through this.
function MenuAssets.soundId(value)
	if type(value) == "number" then
		if value >= 1 and value == math.floor(value) and value < 2 ^ 53 then
			return string.format("rbxassetid://%d", value)
		end
		return nil
	end
	if type(value) ~= "string" then
		return nil
	end
	local text = string.match(value, "^%s*(.-)%s*$")
	if text == "" then
		return nil
	end
	if string.match(text, "^%d+$") then
		return "rbxassetid://" .. text
	end
	return text
end

return MenuAssets
