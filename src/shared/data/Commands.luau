--!strict
-- Commands: the chat-command registry (block 16). /help + /commands auto-generate from this list, so a
-- command is documented the moment it's added here. The server's Chatted handler routes each `name` to
-- the same validated server functions the ProximityPrompts use.

export type Command = { name: string, args: string?, desc: string }

local C: { Command } = {
	{ name = "help", desc = "Show this list of commands" },
	{ name = "commands", desc = "Show this list of commands" },
	{ name = "home", desc = "Teleport back to your own farm" },
	{ name = "stuck", args = "", desc = "Unstuck: warp back to your farm" },
	{ name = "goto", args = "<place>", desc = "Warp to: plaza, harbor, or an island number 1-11" },
	{ name = "map", desc = "Open the world map" },
	{ name = "sell", desc = "Sell your whole inventory" },
	{ name = "daily", desc = "Info about your daily gift streak" },
	{ name = "quests", desc = "Show your active quests" },
	{ name = "trade", args = "<player>", desc = "Ask a player to trade" },
	{ name = "shop", desc = "Where to buy seeds, tools, pets and boats" },
	{ name = "rebirth", desc = "Explain what Rebirth does (does not auto-rebirth)" },
	{ name = "tutorial", args = "<topic>", desc = "Replay a tutorial (or list topics)" },
}

local M = {}
M.list = C
return M
