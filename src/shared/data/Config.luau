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
}

return Config
