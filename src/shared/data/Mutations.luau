--!strict
-- Mutations: the rarity ladder rolled at harvest.
--
-- SCHEMA (spec §2.2): { id, chance, mult, rank, vfx, tradeable, stack }
--   chance   = base probability of this mutation rolling on a single harvest
--   mult     = value multiplier applied to the crop's base sell price
--   rank     = tier 1..6 (higher = rarer/better). Used by "highest-rank wins" stacking.
--   stack    = "highest" -> a crop gets AT MOST ONE mutation (the rarest that hit)
--
-- This is the spec's TARGET 6-tier ladder (§2.2), NOT the web's current 3 (rainbow/golden/giant).
-- Roll rates are chosen so the total mutated fraction is < 15% -> most harvests are plain "normal".
--
-- WHERE THE ROLL HAPPENS: only on the SERVER (Farm.rollMutation). The client never rolls and
-- never learns the rates matter for authority -- it just renders the mutation the server assigned.

export type Mutation = {
	id: string,
	chance: number,
	mult: number,
	rank: number,
	vfx: string,
	tradeable: boolean,
	stack: string,
}

-- Ordered any way you like; Farm sorts by rank for the roll. Kept rarest-first for readability.
-- 8-tier ladder (block 15): the original 6 + Mythic + Bloomly on top. IDs are STABLE (never renamed)
-- so existing saved "plant|mutation" inventory/codex keys keep working.
local Mutations: { Mutation } = {
	{ id = "bloomly",   chance = 0.00003, mult = 300, rank = 8, vfx = "bloomlyaura", tradeable = true, stack = "highest" },
	{ id = "mythic",    chance = 0.00015, mult = 120, rank = 7, vfx = "mythicglow",  tradeable = true, stack = "highest" },
	{ id = "celestial", chance = 0.0005, mult = 50,  rank = 6, vfx = "starfield", tradeable = true, stack = "highest" },
	{ id = "rainbow",   chance = 0.004,  mult = 20,  rank = 5, vfx = "rainbow",   tradeable = true, stack = "highest" },
	{ id = "frosted",   chance = 0.01,   mult = 8,   rank = 4, vfx = "frost",     tradeable = true, stack = "highest" },
	{ id = "golden",    chance = 0.025,  mult = 5,   rank = 3, vfx = "sparkle",   tradeable = true, stack = "highest" },
	{ id = "giant",     chance = 0.04,   mult = 2.5, rank = 2, vfx = "scaleup",   tradeable = true, stack = "highest" },
	{ id = "wet",       chance = 0.08,   mult = 1.5, rank = 1, vfx = "drip",      tradeable = true, stack = "highest" },
}

-- The implicit 7th outcome: no mutation. mult 1.0, rank 0. Not rolled; it's the fallthrough.
export type NormalId = string
local NORMAL_ID = "normal"

local M = {}
M.list = Mutations
M.NORMAL_ID = NORMAL_ID

-- Index by id for O(1) lookup when pricing a sale.
local byId: { [string]: Mutation } = {}
for _, m in Mutations do
	byId[m.id] = m
end

-- Returns the value multiplier for a mutation id. "normal" (or unknown) = 1.0.
function M.multOf(mutationId: string): number
	local m = byId[mutationId]
	return if m then m.mult else 1.0
end

function M.get(mutationId: string): Mutation?
	return byId[mutationId]
end

return M
