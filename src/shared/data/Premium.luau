--!strict
-- Premium: OPTIONAL Robux products (block 16). HARD RULE: strictly NO pay-to-win. Every product is
-- cosmetic or a convenience/QoL perk; NONE may touch coins, xp, rarity/mutation odds, sell price, or
-- global grow speed. This is enforced by Premium.isFair + a unit test, so a future edit that sneaks in
-- a P2W product FAILS the build. Rares are always earned by playing.
--
-- `affects` lists exactly which game dimensions a product touches; the fairness check requires every
-- entry to be in ALLOWED and none in BANNED. (Real MarketplaceService product/gamepass IDs get filled
-- in `robuxId` from the Roblox dashboard before selling; 0 = not yet configured.)

export type Product = {
	id: string,
	name: string,
	emoji: string,
	robuxId: number,
	price: number,
	kind: string, -- "product" (consumable) | "gamepass" (permanent)
	desc: string,
	affects: { string },
}

local M = {}

-- Dimensions a paid product is ALLOWED to touch (cosmetic + convenience only).
M.ALLOWED = {
	cosmetic = true, -- hats/auras/trails/skins/name colors/VIP-area access
	storage = true, -- bigger inventory stack cap (QoL)
	autocollect = true, -- auto-pick nearby ready crops (QoL, no extra yield)
	petslots = true, -- equip an extra cosmetic pet slot
	instantgrow_common = true, -- instantly finish a COMMON crop (never rares/mutations)
	loadout = true, -- extra cosmetic outfit slots
}
-- Dimensions a paid product may NEVER touch (would be pay-to-win).
M.BANNED = {
	coins = true,
	xp = true,
	rarity = true,
	mutation = true,
	sellprice = true,
	growspeed = true, -- global grow-speed is earned (Fast Growth upgrade), never bought
	luck = true,
}

local Products: { Product } = {
	{ id = "vip", name = "VIP Pass", emoji = "👑", robuxId = 0, price = 199, kind = "gamepass", desc = "A golden nametag, VIP cosmetic lounge + an exclusive hat. Cosmetic only.", affects = { "cosmetic" } },
	{ id = "starter_cosmetics", name = "Cosmetic Starter Pack", emoji = "🎨", robuxId = 0, price = 99, kind = "product", desc = "3 hats, an aura and a trail. Looks only.", affects = { "cosmetic" } },
	{ id = "big_storage", name = "Big Backpack", emoji = "🎒", robuxId = 0, price = 149, kind = "gamepass", desc = "Doubles your inventory stack cap. A convenience, no extra loot.", affects = { "storage" } },
	{ id = "auto_collect", name = "Auto-Collector", emoji = "🤖", robuxId = 0, price = 249, kind = "gamepass", desc = "Auto-picks ready crops you walk past. Same yield, less clicking.", affects = { "autocollect" } },
	{ id = "extra_pet_slot", name = "Extra Pet Slot", emoji = "🐾", robuxId = 0, price = 129, kind = "gamepass", desc = "Equip one more (cosmetic) pet at a time.", affects = { "petslots" } },
	{ id = "quickgrow_common", name = "Quick-Grow Tokens (Common)", emoji = "⏩", robuxId = 0, price = 79, kind = "product", desc = "Instantly finish COMMON crops. Never affects rares or mutation odds.", affects = { "instantgrow_common" } },
	{ id = "outfit_slots", name = "Wardrobe Expansion", emoji = "👗", robuxId = 0, price = 89, kind = "gamepass", desc = "More saved cosmetic outfit loadouts.", affects = { "loadout", "cosmetic" } },
	{ id = "battlepass_cosmetic", name = "Bloom Pass (Cosmetic)", emoji = "🌷", robuxId = 0, price = 349, kind = "gamepass", desc = "A season of cosmetic + QoL rewards. Zero gameplay power.", affects = { "cosmetic" } },
}
M.list = Products

-- A product is FAIR iff every dimension it affects is ALLOWED and none is BANNED. Pure -> tested.
function M.isFair(product: Product): boolean
	if #product.affects == 0 then
		return false -- a paid product must declare what it touches
	end
	for _, a in product.affects do
		if M.BANNED[a] or not M.ALLOWED[a] then
			return false
		end
	end
	return true
end

return M
