--!strict
-- Events: the 50 EPIC server-wide events (pure data). The EventDirector picks one every so often,
-- announces it to EVERYONE, and applies its global `effect` multipliers for `dur` seconds. Effects:
--   coins (sell payout ×), mutation (mutation-odds ×), grow (grow-speed ×), luck (gather-rare ×).
-- Bespoke 3D spectacle (bosses/meteors/hordes) layers onto these later; for now every event is REAL
-- (server-wide toast + real economy effect). `night` = only fires at night; `weight` = pick chance;
-- `cd` = seconds before it can fire again; `dur` = active seconds.

export type Event = {
	id: string,
	name: string,
	emoji: string,
	desc: string,
	effect: { coins: number?, mutation: number?, grow: number?, luck: number? },
	dur: number,
	weight: number,
	cd: number,
	night: boolean?,
}

local D = 600 -- default cooldown
local Events: { Event } = {
	-- world bosses / giant creatures
	{ id = "volcano_titan", name = "Volcano Titan", emoji = "🌋", desc = "A lava golem erupts! Rare gems surge.", effect = { luck = 2, mutation = 1.5 }, dur = 600, weight = 3, cd = D },
	{ id = "kraken", name = "The Kraken", emoji = "🐙", desc = "The Kraken surfaces! Legendary catches abound.", effect = { luck = 2.5 }, dur = 480, weight = 3, cd = D },
	{ id = "sky_leviathan", name = "Sky Leviathan", emoji = "🐋", desc = "A cloud-whale drifts over — sky loot!", effect = { coins = 1.5, luck = 1.5 }, dur = 420, weight = 3, cd = D },
	{ id = "megacrop", name = "Corrupted Megacrop", emoji = "🌿", desc = "A giant mutant plant sprouts — mutation frenzy!", effect = { mutation = 2.5 }, dur = 480, weight = 3, cd = D },
	{ id = "frost_dragon", name = "Frost Dragon", emoji = "🐉", desc = "An ice dragon circles — frosted crops surge!", effect = { mutation = 2 }, dur = 480, weight = 3, cd = D },
	{ id = "sand_wyrm", name = "Sand Wyrm", emoji = "🪱", desc = "A giant worm churns the dunes — gold everywhere!", effect = { coins = 1.6, luck = 1.5 }, dur = 420, weight = 3, cd = D },
	{ id = "ancient_treant", name = "Ancient Treant Awakens", emoji = "🌳", desc = "The guardian tree blesses the land.", effect = { grow = 1.5, mutation = 1.5 }, dur = 600, weight = 2, cd = D },
	{ id = "phoenix", name = "Phoenix Rebirth", emoji = "🔥", desc = "A phoenix ignites the sky — everything blooms!", effect = { grow = 2, luck = 1.5 }, dur = 420, weight = 2, cd = D },
	-- catastrophes / weather
	{ id = "blood_moon", name = "Blood Moon", emoji = "🌑", desc = "The moon turns red — MUTATIONS TRIPLED!", effect = { mutation = 3 }, dur = 720, weight = 3, cd = D, night = true },
	{ id = "meteor_shower", name = "Mega Meteor Shower", emoji = "☄️", desc = "Meteors crater the isles — cosmic loot!", effect = { luck = 2.5, coins = 1.3 }, dur = 480, weight = 3, cd = D, night = true },
	{ id = "eclipse", name = "Solar Eclipse", emoji = "🌘", desc = "The sun darkens — rare eclipse crops bloom.", effect = { mutation = 2, luck = 1.5 }, dur = 420, weight = 2, cd = D },
	{ id = "hurricane", name = "Hurricane Bloom", emoji = "🌀", desc = "A storm sweeps in — storm seeds everywhere!", effect = { grow = 1.8, mutation = 1.5 }, dur = 420, weight = 3, cd = D },
	{ id = "aurora", name = "Aurora Cascade", emoji = "🌌", desc = "Auroras ripple — buffs for all!", effect = { mutation = 1.8, luck = 1.5 }, dur = 480, weight = 3, cd = D, night = true },
	{ id = "golden_rain", name = "Golden Downpour", emoji = "💰", desc = "It's raining coins over the plaza!", effect = { coins = 2 }, dur = 300, weight = 3, cd = D },
	{ id = "rainbow", name = "Rainbow Convergence", emoji = "🌈", desc = "Seven rainbows arc the isles — mega luck!", effect = { luck = 2.5, mutation = 1.5 }, dur = 360, weight = 3, cd = D },
	{ id = "great_fog", name = "The Great Fog", emoji = "🌫️", desc = "A magic fog reveals hidden treasures.", effect = { luck = 2 }, dur = 420, weight = 2, cd = D },
	{ id = "time_storm", name = "Time Storm", emoji = "⏳", desc = "Time warps — crops grow in a flash!", effect = { grow = 4 }, dur = 300, weight = 2, cd = D },
	{ id = "sandstorm", name = "Sandstorm Siege", emoji = "🏜️", desc = "A sandstorm unearths treasures everywhere.", effect = { luck = 2 }, dur = 420, weight = 2, cd = D },
	-- invasions / hordes
	{ id = "locust", name = "Locust Swarm", emoji = "🦗", desc = "Defend the crops — survivors get rewards!", effect = { coins = 1.4 }, dur = 300, weight = 3, cd = D },
	{ id = "goblins", name = "Treasure Goblin Horde", emoji = "👺", desc = "Goblins scatter loot — catch them fast!", effect = { coins = 1.5, luck = 1.5 }, dur = 300, weight = 3, cd = D },
	{ id = "slime_rain", name = "Slime Rain", emoji = "🟢", desc = "Friendly slimes bounce down — pop them!", effect = { luck = 1.8 }, dur = 360, weight = 3, cd = D },
	{ id = "crows", name = "Crow Invasion", emoji = "🐦‍⬛", desc = "Build scarecrows to repel the flock!", effect = { grow = 1.5 }, dur = 300, weight = 2, cd = D },
	{ id = "moles", name = "Mole Uprising", emoji = "🦔", desc = "Whack the moles for buried gems!", effect = { luck = 2 }, dur = 300, weight = 2, cd = D },
	{ id = "fairy_mischief", name = "Fairy Mischief", emoji = "🧚", desc = "Fairies mutate the crops at random!", effect = { mutation = 2.2 }, dur = 360, weight = 2, cd = D },
	{ id = "ghost_ship", name = "Ghost Ship Raid", emoji = "🏴‍☠️", desc = "A ghost ship docks — grab the cursed gold!", effect = { coins = 1.8 }, dur = 360, weight = 2, cd = D, night = true },
	{ id = "bee_frenzy", name = "Bee Swarm Frenzy", emoji = "🐝", desc = "Mega swarm supercharges all crops!", effect = { mutation = 2, grow = 1.4 }, dur = 420, weight = 3, cd = D },
	-- migrations / runs
	{ id = "whales", name = "Whale Migration", emoji = "🐳", desc = "Whales cross the ocean — rare deep-sea loot!", effect = { luck = 2 }, dur = 420, weight = 2, cd = D },
	{ id = "butterflies", name = "Butterfly Migration", emoji = "🦋", desc = "Rare butterflies everywhere — catch them!", effect = { luck = 2.5 }, dur = 420, weight = 3, cd = D },
	{ id = "salmon_run", name = "Golden Salmon Run", emoji = "🐟", desc = "Golden fish flood the waters!", effect = { luck = 2.5, coins = 1.3 }, dur = 360, weight = 3, cd = D },
	{ id = "firefly_fest", name = "Firefly Festival", emoji = "✨", desc = "A million fireflies light the forest!", effect = { luck = 2, mutation = 1.5 }, dur = 420, weight = 2, cd = D, night = true },
	{ id = "starfall", name = "Starfall Storm", emoji = "🌠", desc = "A SKY of falling stars — collect the shards!", effect = { coins = 1.5, luck = 2, mutation = 1.5 }, dur = 480, weight = 3, cd = D, night = true },
	{ id = "ancients_march", name = "March of the Ancients", emoji = "👻", desc = "Ghost-beasts march to a hidden vault.", effect = { luck = 2 }, dur = 360, weight = 2, cd = D, night = true },
	-- magical / portals
	{ id = "mirror_dim", name = "Mirror Dimension", emoji = "🪞", desc = "A portal to a mirror world opens!", effect = { mutation = 2, luck = 1.5 }, dur = 420, weight = 2, cd = D },
	{ id = "wishing_well", name = "Wishing Well Awakens", emoji = "⛲", desc = "Drop coins, spin for big rewards!", effect = { coins = 1.6 }, dur = 360, weight = 2, cd = D },
	{ id = "dragon_flyover", name = "Dragon Flyover", emoji = "🐲", desc = "A dragon drops treasure chests on plots!", effect = { coins = 1.6, luck = 1.5 }, dur = 360, weight = 3, cd = D },
	{ id = "floating_market", name = "The Floating Market", emoji = "🎪", desc = "A flying bazaar of rare goods descends!", effect = { coins = 1.5 }, dur = 480, weight = 2, cd = D },
	{ id = "enchanted_bloom", name = "Enchanted Bloom", emoji = "🌸", desc = "Magic vines spread — harvest magic anywhere!", effect = { mutation = 2.5, grow = 1.5 }, dur = 420, weight = 2, cd = D },
	{ id = "portal_rifts", name = "Portal Rifts", emoji = "🌀", desc = "Rifts spill loot — seal them for rewards!", effect = { luck = 2, coins = 1.3 }, dur = 360, weight = 2, cd = D },
	{ id = "genie", name = "Genie's Bargain", emoji = "🧞", desc = "The genie grants a server-wide boon!", effect = { coins = 2, mutation = 2 }, dur = 300, weight = 2, cd = D },
	{ id = "comet", name = "Comet of Fortune", emoji = "☄️", desc = "A mineable comet parks in the sky!", effect = { luck = 2.5 }, dur = 420, weight = 2, cd = D },
	{ id = "beanstalk", name = "Giant Beanstalk", emoji = "🌱", desc = "A beanstalk grows to a cloud vault!", effect = { grow = 2.5, coins = 1.4 }, dur = 420, weight = 2, cd = D },
	-- economy / boosts
	{ id = "market_boom", name = "Market Boom", emoji = "📈", desc = "Sell prices DOUBLED — cash out now!", effect = { coins = 2 }, dur = 600, weight = 3, cd = D },
	{ id = "gold_rush", name = "Gold Rush", emoji = "⛏️", desc = "Ore & gems triple — mine fast!", effect = { luck = 2.5, coins = 1.5 }, dur = 480, weight = 3, cd = D },
	{ id = "bumper", name = "Bumper Harvest", emoji = "🌾", desc = "Crops grow twice as fast!", effect = { grow = 2, coins = 1.3 }, dur = 600, weight = 3, cd = D },
	{ id = "fleet", name = "Merchant Fleet", emoji = "⛵", desc = "Three trader ships dock with rare deals!", effect = { coins = 1.5 }, dur = 480, weight = 2, cd = D },
	{ id = "lucky_hour", name = "Lucky Hour", emoji = "🍀", desc = "Rare odds DOUBLED across the board!", effect = { luck = 2, mutation = 2 }, dur = 600, weight = 3, cd = D },
	-- competitive / collaborative
	{ id = "harvest_race", name = "Server Harvest Race", emoji = "🏁", desc = "First to harvest the most wins big!", effect = { coins = 1.4, grow = 1.4 }, dur = 480, weight = 2, cd = D },
	{ id = "grand_hunt", name = "The Grand Treasure Hunt", emoji = "🗺️", desc = "A legendary treasure is hidden — find it!", effect = { luck = 2 }, dur = 600, weight = 2, cd = D },
	{ id = "colossus", name = "Communal Colossus", emoji = "🗿", desc = "Build a monument together for a reward!", effect = { coins = 1.4 }, dur = 600, weight = 1, cd = D },
	{ id = "regatta", name = "Regatta Championship", emoji = "🚤", desc = "A boat race across all the isles!", effect = { coins = 1.5, luck = 1.5 }, dur = 480, weight = 2, cd = D },
}

local E = {}
E.list = Events
local byId: { [string]: Event } = {}
for _, e in Events do
	byId[e.id] = e
end
function E.get(id: string): Event?
	return byId[id]
end
return E
