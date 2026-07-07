--!strict
-- PlayerData: the SERVER's authoritative store of every player's state.
--
-- The client never holds this. It lives here, on the server, in memory. The client only ever
-- receives a read-only *view* of it (Farm.buildView) and can only change it by sending an intent
-- that the server validates.
--
-- PERSISTENCE (spec §5.2): state lives in an in-memory cache per session and is written to
-- DataStore on a cadence + on leave + on shutdown -- NEVER per action. The pure decisions
-- (shape/migration/validation) live in SaveSchema (VPS-tested); this module is the thin Roblox
-- shell that does the actual DataStoreService calls + the session lock.
--
-- SESSION LOCK (v1, in-value): the save carries { lockedBy=serverId, lockedAt=epoch }. On load we
-- take the lock inside the same UpdateAsync that reads the save. On save we refuse to write if
-- another LIVE server holds the lock -- so two servers can never clobber one player's save. A lock
-- older than Config.LOCK_STALE_SECONDS is treated as a dead server and stolen. (MemoryStore upgrade
-- path noted but unneeded at this scale.)
--
-- SAFETY RULE: if a load FAILS after retries, the player plays on a fresh default but we set a
-- no-save flag so we NEVER overwrite their real (unreadable-right-now) save with defaults.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local Config = require(ReplicatedStorage.Bloomly.data.Config)
local SaveSchema = require(ReplicatedStorage.Bloomly.SaveSchema)

-- GetDataStore THROWS in an unpublished place ("must publish to access DataStore"). Wrap it so the
-- game still runs locally (in-memory only) instead of crashing the whole server. Persistence turns
-- on by itself once the place is published + Studio API access is enabled.
local dataStore: any = nil
do
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore(Config.DATASTORE_NAME)
	end)
	if ok then
		dataStore = ds
	else
		warn("[Bloomly] DataStore unavailable (" .. tostring(ds) .. ") -> IN-MEMORY ONLY. Publish the place for real saves.")
	end
end
-- Unique id for THIS server instance. Empty in Studio solo -> stable fallback so the lock still works.
local SERVER_ID = if game.JobId ~= "" then game.JobId else "studio-solo"

export type Plot = {
	seedId: string?, -- nil = empty plot
	readyAt: number?, -- os.time() epoch when the crop finishes growing; nil = empty. Persists across sessions.
}

export type PlayerState = {
	coins: number,
	lifetimeEarned: number,
	harvests: number,
	xp: number, -- earned on every harvest; drives level (see Rules.levelForXp)
	codex: { [string]: boolean }, -- discovered "plantId|mutationId" combos -> true (collection)
	plots: { Plot }, -- 1..Config.PLOT_COUNT
	inventory: { [string]: number }, -- key = plantId|mutationId  ->  quantity
	vehicle: string?, -- owned vehicle id (nil = on foot)
	rebirths: number, -- prestige count (+10% coins each)
	daily: { day: number, streak: number }, -- daily-login streak
	quests: { done: { [string]: boolean }, active: { [string]: { step: number, prog: number } } },
	unlocks: { [string]: boolean }, -- boats/islands/features from quest rewards
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
		rebirths = 0,
		daily = { day = 0, streak = 0 },
		quests = { done = {}, active = {} },
		unlocks = {},
	}
end

-- userId -> true when a load FAILED. save() checks this and refuses to write, so a transient
-- DataStore outage never overwrites a real save with the fresh default the player is playing on.
local noSave: { [number]: boolean } = {}

local function keyFor(userId: number): string
	return "u_" .. userId
end

-- Retry an async DataStore call with exponential backoff. Returns (ok, resultOrError).
local function retry<T>(fn: () -> T, tries: number?): (boolean, any)
	local n = tries or 4
	local ok, res
	for i = 1, n do
		ok, res = pcall(fn)
		if ok then
			return true, res
		end
		task.wait(0.5 * i) -- 0.5s, 1s, 1.5s ...
	end
	return false, res
end

-- Is a stored lock owned by a DIFFERENT, still-live server? (fresh lock from another JobId)
local function foreignLiveLock(stored: any): boolean
	return type(stored) == "table"
		and type(stored.lockedBy) == "string"
		and stored.lockedBy ~= SERVER_ID
		and (os.time() - (tonumber(stored.lockedAt) or 0)) < Config.LOCK_STALE_SECONDS
end

-- Called once when a player joins. Reads their save + takes the session lock, atomically.
function PlayerData.load(player: Player): PlayerState
	local existing = store[player.UserId]
	if existing then
		return existing
	end
	local template = makeDefault()

	if not dataStore then
		-- no persistence (place not published): fresh in-memory garden, no save calls
		store[player.UserId] = template
		return template
	end

	-- Take the lock inside the read: UpdateAsync gives us read-modify-write atomicity.
	local ok, saved = retry(function()
		return dataStore:UpdateAsync(keyFor(player.UserId), function(old)
			old = old or {}
			old.lockedBy = SERVER_ID
			old.lockedAt = os.time()
			return old
		end)
	end)

	local state: PlayerState
	if ok then
		-- `saved` carries the game fields (if any) + our lock fields; deserialize ignores the lock fields.
		state = SaveSchema.deserialize(saved, template)
	else
		warn("[Bloomly] load FAILED for userId " .. player.UserId .. " (" .. tostring(saved) .. ") -> default, no-save")
		state = template
		noSave[player.UserId] = true -- never clobber the unreadable real save
	end

	store[player.UserId] = state
	return state
end

-- Read the already-loaded state (assumes load() ran on join).
function PlayerData.get(player: Player): PlayerState?
	return store[player.UserId]
end

-- Write the player's state to DataStore. Called on cadence + on leave -- NEVER per action.
-- Refuses to write if another live server stole the lock, or if this session is flagged no-save.
-- `release` = clear the lock (used on final leave) so a rejoin isn't blocked.
function PlayerData.save(player: Player, release: boolean?): ()
	local state = store[player.UserId]
	if not state or noSave[player.UserId] or not dataStore then
		return -- nothing to save, load failed, or no persistence available (unpublished place)
	end
	local payload = SaveSchema.serialize(state)
	retry(function()
		return dataStore:UpdateAsync(keyFor(player.UserId), function(old)
			if foreignLiveLock(old) then
				return nil -- another live server owns this save now: cancel the write, don't clobber
			end
			if release then
				payload.lockedBy = nil
				payload.lockedAt = nil
			else
				payload.lockedBy = SERVER_ID
				payload.lockedAt = os.time()
			end
			return payload
		end)
	end)
end

-- Called on PlayerRemoving: final save + release lock + free memory.
function PlayerData.unload(player: Player): ()
	PlayerData.save(player, true) -- release the lock on the way out
	store[player.UserId] = nil
	noSave[player.UserId] = nil
end

return PlayerData
