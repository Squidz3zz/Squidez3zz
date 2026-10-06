-- MenuAssets: the one place to edit the menu's sound ids, the loading screen's tips and its timings.
-- It lives in ReplicatedFirst so the loading screen can read it before anything else has replicated.
-- Used by LoadingScreen (this folder) and, later, by the menu's music and button sounds.
--
-- Sounds: the keys are fixed (the menu looks them up by name); change only the asset ids. A sound that Roblox refuses to
-- load (wrong id, or the asset is not yours / not public) is skipped with a warning, and its key is listed in the
-- PlayerGui attribute LoadingFailedSounds.
--   Hover          pointer or gamepad selection enters a menu button
--   Confirm        clicking a button (except PLAY)
--   PlaySelect     clicking PLAY
--   MenuMusic      the main menu's looping track
--   SettingsMusic  the Settings room's looping track
--   CreditsMusic   the Credits room's looping track
--
-- Tips: shown one at a time on the loading screen, a new one every TIP_SECONDS. Keep them UPPERCASE and short
-- (about 50 characters or fewer, so they stay on one line on a phone).
--
-- LOADING_MIN_SECONDS: the loading screen always stays up at least this long (so it never just flashes by).
-- LOADING_MAX_SECONDS: it hands over to the menu after this long at the latest, even if an asset is still loading.
-- TIP_SECONDS: how long each tip is shown.
-- MENU_AVATAR_WAIT: how long the loading screen waits for your avatar (the one the menu shows on the right). The menu does not
-- need it: if it is not ready in time the loading screen hands over anyway, and the avatar appears as soon as it is ready.
return {
	Sounds = {
		Hover = "rbxassetid://113223325628963",
		Confirm = "rbxassetid://111174530730534",
		PlaySelect = "rbxassetid://81613840001484",
		MenuMusic = "rbxassetid://107320882976955",
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
