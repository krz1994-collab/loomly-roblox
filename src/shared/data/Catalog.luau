--!strict
-- Catalog: ALL content ported from the web game (economy.js) as pure data tables. No Roblox
-- globals -> VPS-loadable + testable. These are the tables the collection systems, shops and
-- upgrades read in the layers being built on top (fishing, bugs, mining, animals, cooking, pets,
-- cosmetics, house, vehicles...). "Add more" = append a row; never touch logic.
--
-- Every sellable carries `sell` (= baseValue for the NPC price floor). Buyables carry `cost`.
-- Values are ported verbatim from the web economy so the balance is the proven one.

local Catalog = {}

-- ---- collection: fishing (skill minigame; `min` = accuracy needed) ----
Catalog.Fish = {
	{ id = "carp", emoji = "🐟", sell = 8, min = 0 },
	{ id = "perch", emoji = "🐠", sell = 20, min = 0.55 },
	{ id = "koi", emoji = "🎏", sell = 65, min = 0.8 },
	{ id = "golden", emoji = "✨", sell = 220, min = 0.95 },
}
Catalog.WinterFish = {
	{ id = "trout", emoji = "🐟", sell = 40, min = 0 },
	{ id = "salmon", emoji = "🐠", sell = 120, min = 0.6 },
	{ id = "kingfish", emoji = "🐋", sell = 600, min = 0.95 },
}

-- ---- collection: bugs (weight = relative spawn chance) ----
Catalog.Bugs = {
	{ id = "white", emoji = "🦋", sell = 12, w = 34 },
	{ id = "yellow", emoji = "🐝", sell = 18, w = 26 },
	{ id = "blue", emoji = "🦋", sell = 40, w = 18 },
	{ id = "red", emoji = "🪲", sell = 70, w = 12 },
	{ id = "moth", emoji = "🦗", sell = 130, w = 7, dusk = true },
	{ id = "firefly", emoji = "✨", sell = 90, w = 10, dusk = true, glow = true },
	{ id = "rainbow", emoji = "🌈", sell = 420, w = 3 },
}

-- ---- collection: shells (beach) + ores (caves) + forest mushroom ----
Catalog.Shells = {
	{ id = "pink", emoji = "🐚", sell = 40, w = 60 },
	{ id = "spiral", emoji = "🌀", sell = 90, w = 30 },
	{ id = "pearl", emoji = "🦪", sell = 300, w = 10 },
}
Catalog.Ores = {
	{ id = "stone", emoji = "🪨", sell = 15, w = 55 },
	{ id = "coal", emoji = "⚫", sell = 45, w = 35 },
	{ id = "gem", emoji = "💎", sell = 400, w = 10 },
}
Catalog.Mushroom = { id = "mushroom", emoji = "🍄", sell = 55 }

-- ---- production: orchard trees / animals / cooking / honey ----
Catalog.Orchard = {
	{ id = "apple", emoji = "🍎", cost = 500, growMs = 300000, fruitMs = 240000, sell = 30 },
	{ id = "cherry", emoji = "🍒", cost = 2500, growMs = 480000, fruitMs = 360000, sell = 90 },
	{ id = "peach", emoji = "🍑", cost = 9000, growMs = 600000, fruitMs = 600000, sell = 280 },
}
Catalog.Animals = {
	{ id = "chicken", emoji = "🐔", cost = 3000, prodMs = 180000, prod = "egg", prodEmoji = "🥚", sell = 25 },
	{ id = "sheep", emoji = "🐑", cost = 8000, prodMs = 360000, prod = "wool", prodEmoji = "🧶", sell = 90 },
	{ id = "cow", emoji = "🐄", cost = 15000, prodMs = 480000, prod = "milk", prodEmoji = "🥛", sell = 150 },
}
Catalog.Recipes = {
	{ id = "salad", emoji = "🥗", needs = { radish = 2, strawberry = 2 }, ms = 120000, sell = 180 },
	{ id = "soup", emoji = "🍲", needs = { pumpkin = 3 }, ms = 180000, sell = 900 },
	{ id = "jam", emoji = "🍯", needs = { blueberry = 4 }, ms = 300000, sell = 3200 },
	{ id = "feast", emoji = "👑", needs = { crystalrose = 1, pumpkin = 3, blueberry = 2 }, ms = 480000, sell = 18000 },
}
Catalog.Honey = { sell = 80, hiveCost = 9000, prodMs = 300000 }

-- ---- shop: tools / pets / cosmetics ----
Catalog.Tools = {
	{ id = "bugnet", name = "Bug Net", emoji = "🥅", cost = 9000 },
	{ id = "rodpro", name = "Pro Fishing Rod", emoji = "🎣", cost = 12000 },
	{ id = "boots", name = "Speedy Boots", emoji = "👟", cost = 35000, speed = 1.5 },
}
Catalog.Pets = {
	{ id = "chick", emoji = "🐤", cost = 600 },
	{ id = "cat", emoji = "🐱", cost = 2500 },
	{ id = "dog", emoji = "🐶", cost = 2500 },
	{ id = "bunny", emoji = "🐰", cost = 6000 },
	{ id = "parrot", emoji = "🦜", cost = 12000 },
	{ id = "turtle", emoji = "🐢", cost = 18000 },
	{ id = "fox", emoji = "🦊", cost = 30000 },
	{ id = "dragon", emoji = "🐲", cost = 40000 },
	{ id = "unicorn", emoji = "🦄", cost = 120000 },
}
Catalog.Hats = {
	{ id = "straw", name = "Straw Hat", emoji = "👒", cost = 2000 },
	{ id = "party", name = "Party Hat", emoji = "🎉", cost = 5000 },
	{ id = "flower", name = "Flower Crown", emoji = "🌸", cost = 8000 },
	{ id = "wizard", name = "Wizard Hat", emoji = "🧙", cost = 20000 },
	{ id = "crown", name = "Golden Crown", emoji = "👑", cost = 50000 },
}
Catalog.Backs = {
	{ id = "bag", name = "Adventure Bag", emoji = "🎒", cost = 3000 },
	{ id = "cape", name = "Hero Cape", emoji = "🦸", cost = 15000 },
	{ id = "wings", name = "Fairy Wings", emoji = "🦋", cost = 30000 },
	{ id = "jetpack", name = "Jetpack", emoji = "🚀", cost = 80000 },
}
Catalog.Decor = {
	{ id = "flamingo", name = "Pink Flamingo", emoji = "🦩", cost = 400 },
	{ id = "gnome", name = "Gnome Statue", emoji = "🗿", cost = 700 },
	{ id = "scarecrow", name = "Scarecrow", emoji = "🌾", cost = 1500 },
	{ id = "flowerbed", name = "Rainbow Flowerbed", emoji = "🌼", cost = 2500 },
	{ id = "lights", name = "Party Lights", emoji = "🎆", cost = 6000 },
}

-- ---- NEW: vehicles (buyable; speed = walkspeed multiplier). Coin sink now, Robux versions later.
Catalog.Vehicles = {
	{ id = "bike", name = "Bicycle", emoji = "🚲", cost = 5000, speed = 1.35 },
	{ id = "scooter", name = "Scooter", emoji = "🛵", cost = 15000, speed = 1.6 },
	{ id = "car", name = "Car", emoji = "🚗", cost = 60000, speed = 2.0 },
	{ id = "sportscar", name = "Sports Car", emoji = "🏎️", cost = 250000, speed = 2.6 },
}

-- ---- build / upgrade: house parts (rent income/min) + furniture ----
Catalog.House = {
	{ id = "base", name = "Cozy Cottage", emoji = "🏠", cost = 5000, income = 6 },
	{ id = "garden", name = "Flower Garden", emoji = "🌸", cost = 4000, income = 2 },
	{ id = "chimney", name = "Chimney", emoji = "🧱", cost = 2500, income = 2 },
	{ id = "porch", name = "Front Porch", emoji = "🪑", cost = 8000, income = 3 },
	{ id = "greenhouse", name = "Greenhouse Wing", emoji = "🪟", cost = 15000, income = 5 },
	{ id = "floor2", name = "Second Floor", emoji = "🏢", cost = 30000, income = 8 },
	{ id = "pool", name = "Swimming Pool", emoji = "🏊", cost = 50000, income = 10 },
}
Catalog.Furniture = {
	{ id = "rug", name = "Round Rug", emoji = "🟤", cost = 800, income = 1 },
	{ id = "lamp", name = "Night Lamp", emoji = "💡", cost = 1200, income = 1 },
	{ id = "bed", name = "Cozy Bed", emoji = "🛏️", cost = 1600, income = 2 },
	{ id = "table", name = "Dining Table", emoji = "🍽️", cost = 2000, income = 2 },
	{ id = "sofa", name = "Comfy Sofa", emoji = "🛋️", cost = 3000, income = 3 },
	{ id = "tv", name = "Big TV", emoji = "📺", cost = 5000, income = 4 },
}

-- ---- passive-income buildings + farm helpers (upgrades) ----
Catalog.Passive = {
	{ id = "windmill", name = "Windmill", emoji = "🌬️", cost = 100000, perMin = 12, cap = 3000 },
	{ id = "bank", name = "Savings Vault", emoji = "🏦", cost = 25000, ratePerDay = 0.02 },
	{ id = "autoharvest", name = "Auto-Harvester", emoji = "🤖", cost = 45000 },
	{ id = "autoseller", name = "Auto-Seller", emoji = "🏪", cost = 60000 },
	{ id = "sprinklerSmall", name = "Small Sprinkler", emoji = "💧", cost = 500 },
	{ id = "sprinklerBig", name = "Big Sprinkler", emoji = "💦", cost = 9000 },
	{ id = "fertilizer", name = "Fertilizer", emoji = "🧪", cost = 25 },
}

return Catalog
