-- MenuAssets: the one place to edit the menu's sound ids, the loading screen's title and tips, and the loading timings.
-- It lives in ReplicatedFirst so the loading screen can read it before anything else has replicated.
-- Used by LoadingScreen (this folder) and by the menu itself (MainMenuClient: its music, its button sounds, and how long it
-- waits for the loading screen).
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
local MenuAssets = {
	GAME_TITLE = "A Regular Experiment",

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
}

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
