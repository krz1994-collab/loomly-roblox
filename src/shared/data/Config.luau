--!strict
-- Config: global tunables for the vertical slice.
-- Values ported from the web Bloomly economy.js (START_COINS) plus slice-only knobs.
-- This is DATA. Changing the slice's size = changing numbers here, not logic.

local Config = {
	-- Ported: economy.js `START_COINS = 20`
	START_COINS = 20,

	-- How many garden plots each player owns in the slice.
	-- The web game lets you BUY plots (PLOT_COSTS); the slice grants a fixed set so
	-- we can prove the plant/grow/harvest/sell loop without a plot-shop.
	-- NOTE: this doubles as "owned plot count" for unlock rules of type `plot`
	-- (see Plants.isUnlocked). 6 plots => plant unlocks gated at plot>=4 / plot>=6 open once you own them.
	PLOT_COUNT = 6,

	-- Server pushes each player's farm state to their client on this cadence so the
	-- "growing / ready" readout and countdown stay live. A production build would push
	-- on-change and let the client predict countdowns; every-second is simplest to learn from.
	STATE_PUSH_SECONDS = 1,

	-- Separator used to build an inventory key from a crop + its mutation:
	--   key = plantId .. INV_SEP .. mutationId   e.g. "radish|golden"
	-- (web uses "radish.golden"; we use "|" so it never collides with an id containing a dot)
	INV_SEP = "|",

	-- ---- Multiplayer (shared-world model) ----
	-- Max players per server instance. MUST also be set in Studio: Game Settings -> Places ->
	-- Server Size = 50. This mirror is the value the world-builder reads.
	MAX_PLAYERS = 50,

	-- The shared world holds this many numbered farm sections. One per max player so nobody is
	-- ever refused a farm on join. Each section renders a player's persisted `state.plots`.
	PLOT_SECTIONS = 50,

	-- ---- Persistence (DataStore) ----
	-- Save every player on this cadence (seconds). NEVER save per-action (blows the request budget
	-- at 50 players). Also save on PlayerRemoving + BindToClose. Spec §5.2 says 30-60s.
	SAVE_CADENCE_SECONDS = 45,

	-- DataStore name (versioned so a breaking format change can start a clean store if ever needed).
	DATASTORE_NAME = "BloomlyPlayers_v1",

	-- A session lock older than this (seconds) is treated as stale and stolen (covers a server that
	-- crashed without releasing). Must exceed SAVE_CADENCE so a live session never looks stale.
	LOCK_STALE_SECONDS = 120,
}

return Config
