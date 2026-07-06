--!strict
-- Rules: the PURE functional core of the loop. NO Roblox globals, NO requires. Every dependency
-- (randomness, the current time, the data tables) is passed IN as a plain value. That is exactly
-- what lets this one file run two ways:
--   * inside Roblox -- called by Farm (the shell), which injects a Random-backed rand + os.clock()
--   * on the VPS    -- called by tests/run.luau, which injects a deterministic rand + a fixed time
--
-- The feel-critical and exploit-critical bits (the mutation roll, grow timing, the price floor)
-- live HERE so they can be proven correct on the VPS before they ever reach Studio. As the game
-- grows, push logic into this file; the more that lives here, the more of the game is testable
-- without opening Studio.

export type Mutation = { id: string, chance: number, mult: number, rank: number }

local Rules = {}

-- Sort a mutation list rarest-first (highest rank first). Call once; reuse the result.
function Rules.buildLadder(mutations: { Mutation }): { Mutation }
	local ladder = table.clone(mutations)
	table.sort(ladder, function(a: Mutation, b: Mutation)
		return a.rank > b.rank
	end)
	return ladder
end

-- The mutation roll. `rand` must return a number in [0,1). We check the ladder rarest-first and
-- return the first mutation that hits -> "highest-rank wins". `chanceMult` (default 1) scales every
-- chance (fertilizer / weather / biome bias). Returns the mutation id, or `normalId` when nothing
-- hits (the common case: a plain crop).
--
-- This is the single most exploit-sensitive rule in the game. It is pure and injected precisely so
-- a test can pin its behavior (a fixed `rand` gives a known tier; a stream of `rand` gives a known
-- distribution) -- see tests/run.luau.
function Rules.rollMutation(ladder: { Mutation }, rand: () -> number, normalId: string, chanceMult: number?): string
	local m = chanceMult or 1
	for _, mut in ladder do
		if rand() < mut.chance * m then
			return mut.id
		end
	end
	return normalId
end

-- Grow timing. growMs is milliseconds (ported field); the timer runs in seconds. `now` is injected
-- so growth is deterministic in tests (Roblox passes os.clock()).
function Rules.readyAt(now: number, growMs: number): number
	return now + growMs / 1000
end

function Rules.isReady(now: number, readyAt: number?): boolean
	return readyAt ~= nil and now >= (readyAt :: number)
end

-- NPC price FLOOR (spec §3.3 / §3.4): floor(baseValue * mutationMult). The other multipliers
-- (biomeTier / cropOfDay / rebirth) are 1.0 in the slice and multiply in at the call site when
-- those systems exist.
function Rules.sellPrice(baseSell: number, mult: number): number
	return math.floor(baseSell * mult)
end

-- XP granted for one harvest. Higher-tier crops and rarer mutations are worth more.
-- Pure integer math; mutationRank is 0 for a plain crop, 1..6 for a mutation.
function Rules.xpForHarvest(tier: number, mutationRank: number): number
	return tier * 3 + mutationRank * 5
end

-- Level from total XP. Ported from the web `levelOf`: floor(sqrt(xp/50)) + 1.
-- Level 1 at 0 XP, level 2 at 50, level 3 at 200, level 4 at 450, ... (each level costs more).
function Rules.levelForXp(xp: number): number
	return math.floor(math.sqrt(xp / 50)) + 1
end

return Rules
