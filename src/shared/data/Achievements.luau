--!strict
-- Achievements: milestone badges (pure data, block 14). Each tracks one derived STAT against a
-- THRESHOLD; earning it (once) pays a coin reward + a toast. Stats are computed from PlayerState by the
-- server (harvests, lifetimeEarned, level, codexCount, rebirths, treasures, museumCount).

export type Achievement = {
	id: string,
	name: string,
	emoji: string,
	desc: string,
	stat: string,
	threshold: number,
	reward: number,
}

local A: { Achievement } = {
	-- harvesting
	{ id = "first_harvest", name = "First Sprout", emoji = "🌱", desc = "Harvest your first crop", stat = "harvests", threshold = 1, reward = 50 },
	{ id = "harvest_100", name = "Green Thumb", emoji = "🌿", desc = "Harvest 100 crops", stat = "harvests", threshold = 100, reward = 300 },
	{ id = "harvest_1000", name = "Master Farmer", emoji = "🌾", desc = "Harvest 1,000 crops", stat = "harvests", threshold = 1000, reward = 2000 },
	{ id = "harvest_10000", name = "Harvest Legend", emoji = "👑", desc = "Harvest 10,000 crops", stat = "harvests", threshold = 10000, reward = 15000 },
	-- wealth
	{ id = "earn_1k", name = "Piggy Bank", emoji = "🐷", desc = "Earn 1,000 coins total", stat = "lifetimeEarned", threshold = 1000, reward = 100 },
	{ id = "earn_100k", name = "Tycoon", emoji = "💰", desc = "Earn 100,000 coins total", stat = "lifetimeEarned", threshold = 100000, reward = 3000 },
	{ id = "earn_1m", name = "Millionaire", emoji = "🤑", desc = "Earn 1,000,000 coins total", stat = "lifetimeEarned", threshold = 1000000, reward = 25000 },
	-- level
	{ id = "level_10", name = "Getting Started", emoji = "⭐", desc = "Reach level 10", stat = "level", threshold = 10, reward = 200 },
	{ id = "level_25", name = "Seasoned", emoji = "🌟", desc = "Reach level 25", stat = "level", threshold = 25, reward = 800 },
	{ id = "level_50", name = "Grandmaster", emoji = "✨", desc = "Reach level 50", stat = "level", threshold = 50, reward = 5000 },
	-- codex / collection
	{ id = "codex_10", name = "Collector", emoji = "📖", desc = "Discover 10 things", stat = "codexCount", threshold = 10, reward = 150 },
	{ id = "codex_50", name = "Cataloguer", emoji = "📚", desc = "Discover 50 things", stat = "codexCount", threshold = 50, reward = 1000 },
	{ id = "codex_150", name = "Completionist", emoji = "🏆", desc = "Discover 150 things", stat = "codexCount", threshold = 150, reward = 6000 },
	-- rebirth / prestige
	{ id = "rebirth_1", name = "Reborn", emoji = "🔮", desc = "Rebirth once", stat = "rebirths", threshold = 1, reward = 500 },
	{ id = "rebirth_5", name = "Ascended", emoji = "🌀", desc = "Rebirth 5 times", stat = "rebirths", threshold = 5, reward = 5000 },
	{ id = "rebirth_10", name = "Bloomly Legend", emoji = "💫", desc = "Rebirth 10 times", stat = "rebirths", threshold = 10, reward = 20000 },
	-- treasures
	{ id = "treasure_1", name = "Treasure Hunter", emoji = "🗺️", desc = "Find your first treasure", stat = "treasures", threshold = 1, reward = 100 },
	{ id = "treasure_25", name = "Treasure Master", emoji = "💎", desc = "Find 25 treasures", stat = "treasures", threshold = 25, reward = 2500 },
	{ id = "treasure_55", name = "Grand Explorer", emoji = "🧭", desc = "Find all 55 treasures", stat = "treasures", threshold = 55, reward = 10000 },
	-- museum
	{ id = "museum_5", name = "Patron", emoji = "🏛️", desc = "Donate 5 items to the museum", stat = "museumCount", threshold = 5, reward = 200 },
	{ id = "museum_25", name = "Curator", emoji = "🖼️", desc = "Donate 25 items to the museum", stat = "museumCount", threshold = 25, reward = 1500 },
	{ id = "museum_60", name = "Benefactor", emoji = "🏅", desc = "Donate 60 items to the museum", stat = "museumCount", threshold = 60, reward = 8000 },
}

local M = {}
M.list = A
return M
