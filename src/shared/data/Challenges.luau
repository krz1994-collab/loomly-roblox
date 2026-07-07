--!strict
-- Challenges: the pool of DAILY challenge templates (content). Each day the game deterministically
-- picks a few of these; completing them pays a bonus -- a fresh reason to log in every day. `kind`
-- matches the report kinds every activity already fires (harvest/sell/fish/...), so progress is tracked
-- with zero new hooks (see ChallengeRules + Quest.report).

export type Challenge = {
	id: string,
	desc: string,
	kind: string, -- the Quest.report kind this counts
	target: number,
	reward: number,
}

local C: { Challenge } = {
	{ id = "c_harvest", desc = "Harvest 20 crops", kind = "harvest", target = 20, reward = 300 },
	{ id = "c_sell", desc = "Sell items 3 times", kind = "sell", target = 3, reward = 250 },
	{ id = "c_fish", desc = "Catch 10 fish", kind = "fish", target = 10, reward = 350 },
	{ id = "c_bug", desc = "Catch 10 bugs", kind = "catch_bug", target = 10, reward = 350 },
	{ id = "c_mine", desc = "Mine 10 ore", kind = "mine", target = 10, reward = 350 },
	{ id = "c_forage", desc = "Forage 10 times", kind = "forage", target = 10, reward = 300 },
	{ id = "c_plant", desc = "Plant 15 seeds", kind = "plant", target = 15, reward = 250 },
	{ id = "c_cook", desc = "Cook 3 dishes", kind = "cook", target = 3, reward = 400 },
	{ id = "c_animal", desc = "Collect 15 animal products", kind = "collect_animal", target = 15, reward = 400 },
	{ id = "c_treasure", desc = "Find 3 treasures", kind = "find_treasure", target = 3, reward = 500 },
	{ id = "c_mutation", desc = "Harvest 3 mutated crops", kind = "harvest_mut", target = 3, reward = 600 },
	{ id = "c_fruit", desc = "Pick 15 fruit", kind = "harvest", target = 15, reward = 300 },
}

local M = {}
M.list = C
M.DAILY_COUNT = 3
local byId: { [string]: Challenge } = {}
for _, c in C do
	byId[c.id] = c
end
function M.get(id: string): Challenge?
	return byId[id]
end
return M
