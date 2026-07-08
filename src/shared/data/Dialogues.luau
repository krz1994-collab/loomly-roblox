--!strict
-- Dialogues: branching dialogue TREES (RPG block 1). Each NPC's tree is a map of nodes; a node has
-- `text` and `choices`, each choice pointing to another node id or to a special action token:
--   "ACT_QUEST" -> accept / turn in this NPC's next quest (runs Quest.talkTo)
--   "ACT_CLOSE" -> end the conversation
-- NPCs without a custom tree get a generic tree built on the server from their greet/idle lines, so
-- every NPC is talkable and scenario choices ("what you say -> what happens") work everywhere.

local M = {}

M.trees = {
	willow = {
		start = {
			text = "Welcome home, little sprout. Every great farm, and every hero, starts with a single seed.",
			choices = {
				{ label = "Do you have work for me?", to = "ACT_QUEST" },
				{ label = "What is this place?", to = "lore1" },
				{ label = "Any advice?", to = "advice" },
				{ label = "Goodbye", to = "ACT_CLOSE" },
			},
		},
		lore1 = {
			text = "This is Bloomly. A calm hub in the middle, farms all around, and beyond the sea, eleven islands full of secrets and monsters.",
			choices = {
				{ label = "Monsters?", to = "lore2" },
				{ label = "Thank you", to = "ACT_CLOSE" },
			},
		},
		lore2 = {
			text = "Aye. Slimes, wolves, even a young dragon. Buy a boat from Captain Bay, take a weapon, and mind the Frost Yeti.",
			choices = {
				{ label = "I'm ready", to = "ACT_QUEST" },
				{ label = "Later", to = "ACT_CLOSE" },
			},
		},
		advice = {
			text = "Plant, harvest, sell, repeat. Chase the rare mutations. And come back each day, the world changes.",
			choices = { { label = "Got it", to = "ACT_CLOSE" } },
		},
	},
	bay = {
		start = {
			text = "Ahoy! Ye can't reach them islands by wishin'. Ye need a BOAT, har har!",
			choices = {
				{ label = "Sell me a boat then", to = "ACT_QUEST" },
				{ label = "What's out there?", to = "sea" },
				{ label = "Farewell", to = "ACT_CLOSE" },
			},
		},
		sea = {
			text = "Eleven isles, each with its own beasts, crops and treasure. The further out, the richer the loot.",
			choices = {
				{ label = "Let's set sail", to = "ACT_QUEST" },
				{ label = "Maybe later", to = "ACT_CLOSE" },
			},
		},
	},
	hank = {
		start = {
			text = "A real farmer knows: the rarest crops come to the patient. And the bees help more than you'd think.",
			choices = {
				{ label = "Teach me something", to = "ACT_QUEST" },
				{ label = "Tell me about mutations", to = "mut" },
				{ label = "Bye", to = "ACT_CLOSE" },
			},
		},
		mut = {
			text = "Eight tiers, from Wet to the legendary Bloomly. A hive nearby, a Lucky Charm, an event, all tilt the odds.",
			choices = { { label = "Fascinating", to = "ACT_QUEST" }, { label = "Thanks", to = "ACT_CLOSE" } },
		},
	},
}

function M.get(npcId: string): any
	return M.trees[npcId]
end

return M
