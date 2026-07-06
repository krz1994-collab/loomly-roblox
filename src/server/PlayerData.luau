--!strict
-- PlayerData: the SERVER's authoritative store of every player's state.
--
-- The client never holds this. It lives here, on the server, in memory. The client only ever
-- receives a read-only *view* of it (Farm.buildView) and can only change it by sending an intent
-- that the server validates.
--
-- PERSISTENCE SEAM (spec §5.2): the slice keeps state in a plain in-memory table that is lost on
-- server shutdown. The load() and save() functions below are the exact seam where a
-- session-locked DataStore drops in later. Build against these two functions and the rest of the
-- game never needs to know whether the bytes come from RAM or DataStore. See the TODOs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Bloomly.data.Config)

export type Plot = {
	seedId: string?, -- nil = empty plot
	readyAt: number?, -- os.clock() timestamp when the crop finishes growing; nil = empty
}

export type PlayerState = {
	coins: number,
	lifetimeEarned: number,
	harvests: number,
	xp: number, -- earned on every harvest; drives level (see Rules.levelForXp)
	codex: { [string]: boolean }, -- discovered "plantId|mutationId" combos -> true (collection)
	plots: { Plot }, -- 1..Config.PLOT_COUNT
	inventory: { [string]: number }, -- key = plantId|mutationId  ->  quantity
}

local PlayerData = {}

-- userId -> PlayerState. THE authoritative table. Server-only; never replicated wholesale.
local store: { [number]: PlayerState } = {}

-- A fresh garden for a brand-new player. Ported starting values: Config.START_COINS (=20).
local function makeDefault(): PlayerState
	local plots: { Plot } = {}
	for i = 1, Config.PLOT_COUNT do
		plots[i] = { seedId = nil, readyAt = nil }
	end
	return {
		coins = Config.START_COINS,
		lifetimeEarned = 0,
		harvests = 0,
		xp = 0,
		codex = {},
		plots = plots,
		inventory = {},
	}
end

-- Called once when a player joins. Returns their authoritative state.
function PlayerData.load(player: Player): PlayerState
	-- TODO(DataStore §5.2): session-locked load goes HERE.
	--   1. Acquire a session lock for this userId (MemoryStore or a DataStore "lock" key) so two
	--      server instances can never own the same save at once -- the "owner"-tag problem already
	--      solved on the web version.
	--   2. GetAsync the player's save with retries; if found, decode into a PlayerState.
	--   3. Fall back to makeDefault() only when there is genuinely no save.
	-- For the slice: in-memory only. New every server start.
	local existing = store[player.UserId]
	if existing then
		return existing
	end
	local fresh = makeDefault()
	store[player.UserId] = fresh
	return fresh
end

-- Read the already-loaded state (assumes load() ran on join).
function PlayerData.get(player: Player): PlayerState?
	return store[player.UserId]
end

-- Called on a cadence and when the player leaves.
function PlayerData.save(player: Player): ()
	local state = store[player.UserId]
	if not state then
		return
	end
	-- TODO(DataStore §5.2): session-locked save goes HERE.
	--   1. UpdateAsync (not SetAsync) the player's key with retries, writing `state`.
	--   2. NEVER write per-action; write on this cadence + on PlayerRemoving + on BindToClose.
	--   3. On the final leave, release the session lock acquired in load().
	-- For the slice: no-op (state already lives in `store`).
end

-- Called on PlayerRemoving to release memory (and, later, the session lock).
function PlayerData.unload(player: Player): ()
	PlayerData.save(player)
	store[player.UserId] = nil
end

return PlayerData
