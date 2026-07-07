--!strict
-- SaveSchema: the PURE rules for turning a PlayerState into something safe to store in DataStore
-- and back. No Roblox globals, no requires -- the caller injects a fresh default `template` (so this
-- stays runnable + unit-testable on the standalone luau CLI on the VPS).
--
-- Why this exists: DataStore hands back whatever bytes were last written -- possibly from an OLDER
-- version of the game that lacked fields we now rely on, or corrupted/partial. Loading that blindly
-- would crash the server or hand a player a broken save. Everything here makes load total and safe:
--   * VERSION + migrations  -> old saves upgrade forward instead of breaking
--   * template fill          -> any field a save lacks is filled from a fresh default (new features never wipe players)
--   * validate               -> clamp impossible values (negative coins, wrong types) instead of trusting them
--   * deep copy on serialize -> DataStore never sees a half-mutated live table
--
-- IMPORTANT: grow timers (plot.readyAt) are stored as os.time() epoch seconds, which persist across
-- sessions as-is (and give offline growth). So there is NO timer conversion here -- epochs just carry.

export type Plot = { seedId: string?, readyAt: number? }
export type PlayerState = {
	coins: number,
	lifetimeEarned: number,
	harvests: number,
	xp: number,
	codex: { [string]: boolean },
	plots: { Plot },
	inventory: { [string]: number },
	vehicle: string?, -- owned vehicle id (nil = on foot); gives a walkspeed boost
	rebirths: number, -- prestige count; each = +10% coin multiplier
	daily: { day: number, streak: number }, -- daily-login streak state
}

local SaveSchema = {}

-- Bump when the ON-DISK shape changes in a way old saves can't be read field-by-field.
-- Add a `migrations[n]` that turns a v(n) table into a v(n+1) table. Never renumber.
SaveSchema.VERSION = 1

-- migrations[fromVersion](raw) -> raw at fromVersion+1. Empty for v1 (nothing older exists yet).
local migrations: { [number]: (any) -> any } = {}

-- ---- helpers ----
local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, val in v do
		out[k] = deepCopy(val)
	end
	return out
end

local function isNonNegNumber(v: any): boolean
	return type(v) == "number" and v == v and v >= 0 and v ~= math.huge -- v==v rejects NaN
end

-- ---- serialize: live PlayerState -> plain versioned table for DataStore ----
-- Deep-copies the mutable subtables so an async write can't capture a torn state.
function SaveSchema.serialize(state: PlayerState): any
	return {
		v = SaveSchema.VERSION,
		coins = state.coins,
		lifetimeEarned = state.lifetimeEarned,
		harvests = state.harvests,
		xp = state.xp,
		codex = deepCopy(state.codex),
		plots = deepCopy(state.plots),
		inventory = deepCopy(state.inventory),
		vehicle = state.vehicle,
		rebirths = state.rebirths,
		daily = deepCopy(state.daily),
	}
end

-- Run the migration chain from raw.v up to VERSION.
function SaveSchema.migrate(raw: any): any
	local data = deepCopy(raw)
	local v = (type(data) == "table" and type(data.v) == "number") and data.v or SaveSchema.VERSION
	while v < SaveSchema.VERSION do
		local step = migrations[v]
		if not step then
			break -- no migration path: fall through; template fill + validate will make it safe
		end
		data = step(data)
		v += 1
		data.v = v
	end
	return data
end

-- ---- validate: clamp/repair a candidate state so it can never crash or cheat the server ----
-- `template` supplies the correct plot count + safe defaults. Returns a guaranteed-valid PlayerState.
function SaveSchema.validate(candidate: any, template: PlayerState): PlayerState
	local t: any = type(candidate) == "table" and candidate or {}
	local out: any = {}

	out.coins = isNonNegNumber(t.coins) and t.coins or template.coins
	out.lifetimeEarned = isNonNegNumber(t.lifetimeEarned) and t.lifetimeEarned or template.lifetimeEarned
	out.harvests = isNonNegNumber(t.harvests) and t.harvests or template.harvests
	out.xp = isNonNegNumber(t.xp) and t.xp or template.xp
	out.vehicle = if type(t.vehicle) == "string" then t.vehicle else nil
	out.rebirths = isNonNegNumber(t.rebirths) and t.rebirths or 0
	local d: any = type(t.daily) == "table" and t.daily or {}
	out.daily = { day = isNonNegNumber(d.day) and d.day or 0, streak = isNonNegNumber(d.streak) and d.streak or 0 }

	-- codex: map of string->true
	out.codex = {}
	if type(t.codex) == "table" then
		for k, val in t.codex do
			if type(k) == "string" and val == true then
				out.codex[k] = true
			end
		end
	end

	-- inventory: map of string->positive integer qty
	out.inventory = {}
	if type(t.inventory) == "table" then
		for k, qty in t.inventory do
			if type(k) == "string" and isNonNegNumber(qty) and qty > 0 then
				out.inventory[k] = math.floor(qty)
			end
		end
	end

	-- plots: EXACTLY #template.plots slots; each { seedId:string?, readyAt:number? }
	out.plots = {}
	local srcPlots = type(t.plots) == "table" and t.plots or {}
	for i = 1, #template.plots do
		local p: any = srcPlots[i]
		if type(p) == "table" and type(p.seedId) == "string" then
			out.plots[i] = { seedId = p.seedId, readyAt = (type(p.readyAt) == "number") and p.readyAt or nil }
		else
			out.plots[i] = { seedId = nil, readyAt = nil } -- empty plot
		end
	end

	return out
end

-- ---- deserialize: raw DataStore value (maybe nil / old / partial) -> valid PlayerState ----
-- `template` is a FRESH default state supplied by the caller (PlayerData.makeDefault), which is the
-- only thing that knows Config.PLOT_COUNT / START_COINS. Missing fields fill from it.
function SaveSchema.deserialize(raw: any, template: PlayerState): PlayerState
	if raw == nil then
		return deepCopy(template) -- brand-new player: fresh garden
	end
	return SaveSchema.validate(SaveSchema.migrate(raw), template)
end

return SaveSchema
