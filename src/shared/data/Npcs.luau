--!strict
-- Npcs: the 28-NPC roster (pure data). The World shell spawns each as a Model + a `talk`
-- ProximityPrompt that opens dialogue and offers/turns-in that giver's quests. Behavior: "S"
-- stationary, "W" wandering, "T" timed visitor. `island` = nil for plaza NPCs, else an island index.
-- Dialogue lines are scenario-based + kid-friendly.

export type Npc = {
	id: string,
	name: string,
	emoji: string,
	behavior: string,
	island: number?,
	greet: string,
	idle: string,
}

local Npcs: { Npc } = {
	-- hub shopkeepers
	{ id = "pip", name = "Pip Sprout", emoji = "🌱", behavior = "S", greet = "Ooooh a new farmer! Grab a seed, pop it in the dirt, give it a drink — BOOM, snack time!", idle = "Rainbow crops are REAL, ya know! Water lots and watch for sparkles!" },
	{ id = "marge", name = "Marge Bramble", emoji = "🧺", behavior = "S", greet = "Fresh from the field? Let Grandma Marge weigh 'em — fair coins, always, sweetpea.", idle = "Mutated veggies fetch a pretty penny — I pay double!" },
	{ id = "bolt", name = "Bolt Wrenchley", emoji = "🛠️", behavior = "S", greet = "That rusty ol' can? We can do better — bigger can, more splash, happier plants!", idle = "Upgrade the pickaxe and them rocks crack like eggshells. *tink tink!*" },
	{ id = "coco", name = "Coco Whiskers", emoji = "🐾", behavior = "S", greet = "Every good farmer needs a buddy! This egg's wiggling — I think it likes you!", idle = "Feed your pet, play with your pet, and it helps you harvest twice as fast!" },
	{ id = "glimmer", name = "Glimmer Fae", emoji = "✨", behavior = "S", greet = "Darling, that hat with those boots? Chef's kiss. You're the STAR of the plaza!", idle = "Bloom with STYLE, sweetie." },
	{ id = "rusty", name = "Rusty Gearson", emoji = "🔧", behavior = "S", greet = "Zoom-zoom! This lil' tractor'll plow your whole plot before lunch!", idle = "Souped-up cart = carry DOUBLE the crops. Fewer trips, more play!" },
	{ id = "bay", name = "Captain Bay", emoji = "⚓", behavior = "S", greet = "Ahoy, landlubber! Ye can't reach them islands by wishin'. Ye need a BOAT, har har!", idle = "Patch yer sails and ride the wind to islands ye've only dreamed of." },
	-- village specialists
	{ id = "willow", name = "Elder Willow", emoji = "🌳", behavior = "S", greet = "Welcome home, little sprout. Bloomly grows one seed — and one friend — at a time.", idle = "The islands wait beyond the water. Every journey starts with a single carrot, hm?" },
	{ id = "hank", name = "Farmer Hank", emoji = "👨‍🌾", behavior = "S", greet = "You call THAT a pumpkin? Ha! Kidding — it's a beauty. Let's grow a GIANT one!", idle = "Bees + flowers = magic, kiddo." },
	{ id = "sunny", name = "Sunny Meadows", emoji = "🧒", behavior = "W", greet = "Race you to water ten plants! Ready… grow!", idle = "My carrots came up ORANGE. Is that normal? …It is? Phew!" },
	{ id = "rowan", name = "Scout Rowan", emoji = "🧭", behavior = "W", greet = "X marks the spot… somewhere near the old windmill. Wanna dig with me?", idle = "Every island hides a treasure. Bring me the map pieces!" },
	{ id = "finn", name = "Finn Gill", emoji = "🎣", behavior = "S", greet = "Fishin's just waitin' with a smile. Cast it out… and wait for the wiggle.", idle = "A rainbow trout! Whoa. That one only bites when the water sparkles." },
	{ id = "dan", name = "Digger Dan", emoji = "⛏️", behavior = "S", greet = "Deep down there's SPARKLIES — gems big as your fist! Grab that pickaxe, partner.", idle = "Bring a lantern to the caves and you'll strike it rich!" },
	{ id = "chef", name = "Chef Pomme", emoji = "🍳", behavior = "S", greet = "Ah, magnifique! Three carrots and a pumpkin — we make ze soup of champions!", idle = "No no no — you must COOK the berries first! Then… mwah… pie!" },
	{ id = "buzz", name = "Buzz Honeydrop", emoji = "🐝", behavior = "S", greet = "Bzzz… my bees love your flowers. Plant more and we'll make golden honey together.", idle = "A happy hive means sweeter crops. Gently now — they're friendly!" },
	{ id = "bella", name = "Bella Barnaby", emoji = "🐄", behavior = "S", greet = "Aww, this lil' chick imprinted on ya! Feed her up and she'll lay golden eggs.", idle = "Two fluffy sheep… breed 'em right and you might get a RAINBOW lamb, hon!" },
	{ id = "daisy", name = "Décor Daisy", emoji = "🪴", behavior = "S", greet = "Ooh, put the fountain THERE. Yes! Your home should feel like a warm hug.", idle = "Let's make your plot the cutest in Bloomly!" },
	-- per-island NPCs (island index matches WorldLayout.islandCenter)
	{ id = "sandy", name = "Sandy Shells", emoji = "🐚", behavior = "S", island = 1, greet = "Welcome to the Beach! Collect shiny shells before the tide takes 'em!", idle = "The tide's comin' in — grab those shells quick!" },
	{ id = "wwhisper", name = "Willow Whisper", emoji = "🧚", behavior = "W", island = 2, greet = "Shhh… the trees are talking. A rare beetle sleeps by the old oak.", idle = "The forest keeps its secrets… unless you listen." },
	{ id = "frost", name = "Frost Ivy", emoji = "❄️", behavior = "S", island = 3, greet = "Brrr! Bundle up. The Frostberries only grow where it's coldest!", idle = "Careful on the ice — or grab a sled!" },
	{ id = "ember", name = "Ember Ash", emoji = "🌋", behavior = "S", island = 4, greet = "Whoa there, hotshot! Mine the glowing rocks — but watch your boots!", idle = "The lava's warm today. Perfect for fire-crops!" },
	{ id = "dune", name = "Dune Sabir", emoji = "🏜️", behavior = "W", island = 5, greet = "The sand hides ancient treasures, traveler. Dig where the golden light points.", idle = "A sandstorm's brewing… keep your eyes open." },
	{ id = "geode", name = "Geode Gem", emoji = "💎", behavior = "S", island = 6, greet = "See how the crystals GLOW? The rainbow geode is the rarest of all… find it for me?", idle = "Deeper you dig, shinier it gets." },
	{ id = "fungus", name = "Fungus Fred", emoji = "🍄", behavior = "S", island = 7, greet = "Hee hee, mushrooms everywhere! But only pick the GLOWY ones — those are OURS.", idle = "Spores in the air today… good foraging!" },
	{ id = "gale", name = "Gale Skyler", emoji = "🪁", behavior = "S", island = 8, greet = "Hold onto your hat! Up here the wind carries seeds from faraway lands!", idle = "The higher you climb, the rarer the finds." },
	{ id = "marina", name = "Marina Coral", emoji = "🐠", behavior = "S", island = 9, greet = "Dive down and see fish of EVERY color. Bring me a golden pearl and I'm your friend forever!", idle = "The reef sparkles at dawn." },
	{ id = "misty", name = "Misty Dew", emoji = "🌫️", behavior = "S", island = 10, greet = "The mist hides the rarest herbs in all Bloomly. Only true masters find them…", idle = "Breathe the fog… feel the magic." },
	{ id = "fae", name = "Fae Guardian", emoji = "🧚‍♀️", behavior = "S", island = 11, greet = "You found the Enchanted Forest, little one. The Ancient Treant has been waiting…", idle = "Catch a fairy and make a wish — but be kind, always." },
}

local N = {}
N.list = Npcs
local byId: { [string]: Npc } = {}
for _, n in Npcs do
	byId[n.id] = n
end
function N.get(id: string): Npc?
	return byId[id]
end
return N
