--!strict
-- Tutorials: one coaching row per ACTIVITY (block 2). Bloomy the mascot delivers `mascotLine` the first
-- time a player meets an activity; the "?" Help panel lists every `hint`. The COVERAGE test asserts that
-- every activity in Tutorials.ACTIVITIES has a row here, so no mechanic ever ships without a kid-friendly
-- explanation ("dzieci mają dojść jak co zebrać").

export type Tutorial = {
	id: string,
	title: string,
	emoji: string,
	mascotLine: string, -- what Bloomy says the first time
	hint: string, -- the short how-to shown in the Help panel
}

-- The canonical list of activities that MUST each have a tutorial (coverage-tested).
local ACTIVITIES = {
	"welcome", "plant", "harvest", "sell", "mutations", "quests", "upgrade",
	"fish", "catch_bug", "mine", "forage", "orchard", "animals", "breed",
	"cook", "bees", "house", "decorate", "trade", "sail", "treasure",
	"museum", "rebirth", "daily", "map", "events", "pets",
}

local Tutorials: { Tutorial } = {
	{ id = "welcome", title = "Welcome to Bloomly!", emoji = "🌱", mascotLine = "Hi! I'm Bloomy 🌱 Welcome to your farm! Walk to a plot pad and press E to plant a seed.", hint = "Use WASD to walk, press E on things to use them. Start by planting on your farm!" },
	{ id = "plant", title = "Planting", emoji = "🌾", mascotLine = "Press E on an empty plot pad to plant your selected seed. Pick seeds on the bottom bar!", hint = "Empty pad + E = plant. Change seed on the bottom seed bar." },
	{ id = "harvest", title = "Harvesting", emoji = "🧺", mascotLine = "When a crop is ready (timer hits 0), press E again to harvest it into your bag!", hint = "Ready crop + E = harvest. It goes into your 🎒 bag." },
	{ id = "sell", title = "Selling", emoji = "💰", mascotLine = "Take your crops to the 🧺 Market and press E to sell everything for coins!", hint = "Market + E (or /sell) sells your whole bag for coins." },
	{ id = "mutations", title = "Mutations", emoji = "✨", mascotLine = "Sometimes crops grow SHINY or RAINBOW -- these rare mutations sell for WAY more!", hint = "Rare mutations (up to Bloomly tier!) sell for huge coins. Lucky Charm + hives raise the odds." },
	{ id = "quests", title = "Quests", emoji = "📜", mascotLine = "Talk to 🌳 Elder Willow to get quests. They guide you and give big rewards!", hint = "Talk to NPCs (E) to accept + turn in quests. Track them top-right, or /quests." },
	{ id = "upgrade", title = "Upgrades", emoji = "⬆️", mascotLine = "Visit the upgrade kiosk to buy more plots, faster growth, more luck and more!", hint = "Upgrade kiosk in the plaza: plots, sell bonus, growth, walk speed, luck, greenhouse." },
	{ id = "fish", title = "Fishing", emoji = "🎣", mascotLine = "Stand by the 🎣 pond and press E to fish. Rarer fish sell for more!", hint = "Fishing spots + E. Lucky Charm boosts rare catches." },
	{ id = "catch_bug", title = "Bug Catching", emoji = "🦋", mascotLine = "Sneak up to a 🦋 bug patch and press E to catch bugs and rare butterflies!", hint = "Bug patches + E. Some bugs only appear at certain times." },
	{ id = "mine", title = "Mining", emoji = "⛏️", mascotLine = "Press E on the rocks to mine ore and gems -- the deeper the rarer!", hint = "Rock nodes + E to mine ore/gems." },
	{ id = "forage", title = "Foraging", emoji = "🍄", mascotLine = "Press E on bushes to forage mushrooms, berries and herbs!", hint = "Forage bushes + E for wild goodies." },
	{ id = "orchard", title = "Orchard", emoji = "🌳", mascotLine = "Plant fruit trees at the Orchard! They make fruit over time -- come back to pick it.", hint = "Orchard station: Plant tree, then Pick fruit later. Greenhouse upgrade = faster fruit." },
	{ id = "animals", title = "Animals", emoji = "🐄", mascotLine = "Buy animals at the Pen! They make eggs, milk and more while you play.", hint = "Pen: Buy animal, Collect products, and Breed two of the same for a baby!" },
	{ id = "breed", title = "Breeding", emoji = "🐣", mascotLine = "Have two of the same animal? Press Breed for a baby -- sometimes even rarer!", hint = "Two same-species animals + an empty pen slot = Breed for a baby." },
	{ id = "cook", title = "Cooking", emoji = "🍳", mascotLine = "Gather ingredients, then Cook a dish at the Kitchen for big coins + XP!", hint = "Kitchen: Cook dish (uses ingredients), then Collect dish when it's ready." },
	{ id = "bees", title = "Bees & Honey", emoji = "🐝", mascotLine = "Build a Beehive! It makes honey AND helps your crops mutate more.", hint = "Beehive: Build/upgrade, then Collect honey. A live hive boosts mutation odds." },
	{ id = "house", title = "Your House", emoji = "🏠", mascotLine = "Upgrade your House to earn passive rent coins -- collect them at the door!", hint = "House: Upgrade house, Collect rent, and Buy decor for a rent bonus." },
	{ id = "decorate", title = "Decorating", emoji = "🖼️", mascotLine = "Buy decorations for your house -- they look great AND boost your rent!", hint = "House: Buy decor to make it cozy + earn a little more rent." },
	{ id = "trade", title = "Trading", emoji = "🤝", mascotLine = "Press the Trade button to swap items with friends -- totally safe, both must confirm!", hint = "Trade button (or /trade <name>): offer items, both confirm, done. No scams possible." },
	{ id = "sail", title = "Sailing", emoji = "⛵", mascotLine = "Buy a boat at the Harbor, then sail to the islands -- each has its own treasures!", hint = "Boat Shop at the Harbor, then a boat per island. Islands unlock as you level up." },
	{ id = "treasure", title = "Treasures", emoji = "🗺️", mascotLine = "Look for glowing chests hidden around the world -- press E to claim the coins!", hint = "Hidden chests on every island + the plaza. Find all 55!" },
	{ id = "museum", title = "Museum", emoji = "🏛️", mascotLine = "Donate one of each item to the 🏛️ Museum for badges and rewards!", hint = "Museum + E donates 1 of each new item you own for coins + achievements." },
	{ id = "rebirth", title = "Rebirth", emoji = "🔮", mascotLine = "When you're rich, Rebirth to reset coins for a PERMANENT boost. Big players do it lots!", hint = "Rebirth Shrine: resets coins for +10% coins forever. /rebirth explains it." },
	{ id = "daily", title = "Daily Gift", emoji = "🎁", mascotLine = "Come back every day for the 🎁 Daily Gift -- the streak makes it bigger!", hint = "Daily Gift stand: claim once a day, keep your streak alive for more." },
	{ id = "map", title = "The Map", emoji = "🗺️", mascotLine = "Lost? Check the minimap in the corner, or press the Map button for the whole world!", hint = "Minimap (corner) + Map button. Red dot = you, green = your farm." },
	{ id = "events", title = "Epic Events", emoji = "🌟", mascotLine = "Watch for EPIC events like Blood Moon and Gold Rush -- huge boosts for everyone!", hint = "Server events (top banner) give everyone big coin/mutation/luck boosts for a while." },
	{ id = "pets", title = "Pets", emoji = "🐾", mascotLine = "Adopt a pet or hatch an egg! Your equipped pet gives a passive boost -- all earned, never P2W.", hint = "Pet Shop = adopt; Egg Hatchery = mystery pet. The strongest owned pet auto-equips (coins/luck/grow)." },
}

local M = {}
M.list = Tutorials
M.ACTIVITIES = ACTIVITIES
local byId: { [string]: Tutorial } = {}
for _, t in Tutorials do
	byId[t.id] = t
end
function M.get(id: string): Tutorial?
	return byId[id]
end
return M
