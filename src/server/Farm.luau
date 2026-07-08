--!strict
-- Farm: the SERVER-SIDE rules of the core loop. Pure-ish logic that mutates a player's
-- PlayerState. Every function here runs ONLY on the server. The client cannot call these; it can
-- only send an intent (Plant/Harvest/SellAll) that the server's handler forwards here after
-- validating. If a rule matters for fairness, it is enforced in this file.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plants = require(ReplicatedStorage.Bloomly.data.Plants)
local Mutations = require(ReplicatedStorage.Bloomly.data.Mutations)
local Config = require(ReplicatedStorage.Bloomly.data.Config)
local Rules = require(ReplicatedStorage.Bloomly.Rules) -- the pure, VPS-tested loop core
local UpgradeRules = require(ReplicatedStorage.Bloomly.UpgradeRules)
local Upgrades = require(ReplicatedStorage.Bloomly.data.Upgrades)
local Catalog = require(ReplicatedStorage.Bloomly.data.Catalog)
local Trees = require(ReplicatedStorage.Bloomly.data.Trees)
local Animals = require(ReplicatedStorage.Bloomly.data.Animals)
local Recipes = require(ReplicatedStorage.Bloomly.data.Recipes)
local Bees = require(ReplicatedStorage.Bloomly.data.Bees)
local Pets = require(ReplicatedStorage.Bloomly.data.Pets)
local PetRules = require(ReplicatedStorage.Bloomly.PetRules)
local LeaderRules = require(ReplicatedStorage.Bloomly.LeaderRules)
local PlayerData = require(script.Parent.PlayerData)
local Events = require(script.Parent.Events) -- active server-wide event multipliers (coins/mutation/grow/luck)

-- Sell value + emoji for ANY inventory key. Crops are "plantId|mutationId"; gathered items are
-- "category|id" (fish|carp, bug|white, ore|gem, shell|pearl, forage|apple, mushroom|mushroom).
local GATHER_LISTS: { [string]: { any } } = {
	fish = Catalog.Fish,
	winterfish = Catalog.WinterFish,
	bug = Catalog.Bugs,
	ore = Catalog.Ores,
	shell = Catalog.Shells,
	fruit = Trees.Fruits, -- orchard (block 7): {id,emoji,sell}
	product = Animals.Products, -- pen animals (block 8): {id,emoji,sell}
	dish = Recipes.list, -- cooked dishes (block 9): rows carry id/emoji/sell
	honey = { { id = Bees.HONEY.id, emoji = Bees.HONEY.emoji, sell = Bees.HONEY.sell } }, -- beehive (block 9)
}
local function itemSell(key: string): (number, string)
	local sep = string.find(key, Config.INV_SEP, 1, true)
	local a = if sep then string.sub(key, 1, sep - 1) else key
	local b = if sep then string.sub(key, sep + 1) else ""
	local plant = Plants.get(a)
	if plant then
		return math.floor(plant.sell * Mutations.multOf(b)), plant.emoji
	end
	local list = GATHER_LISTS[a]
	if list then
		for _, row in list do
			if row.id == b then
				return row.sell, row.emoji
			end
		end
	end
	if a == "mushroom" then
		return Catalog.Mushroom.sell, Catalog.Mushroom.emoji
	end
	return 0, "?"
end

-- The equipped pet's multiplier for a dimension (coins/luck/grow), or 1.0 if none.
local function petMult(state: PlayerData.PlayerState, key: string): number
	local eq = state.pets and state.pets.equipped
	if not eq then
		return 1
	end
	return PetRules.abilityMult(Pets.get(eq), key)
end

-- Effect value of an upgrade track for this player (1.0 / base if unbought).
local function upEffect(state: PlayerData.PlayerState, trackId: string): number
	local track = Upgrades.get(trackId)
	if not track then
		return 1
	end
	return UpgradeRules.effectAt(track, (state.upgrades and state.upgrades[trackId]) or 0)
end

type PlayerState = PlayerData.PlayerState

local Farm = {}

-- Public alias so the gathering handler in init.server can apply the same equipped-pet luck bonus.
Farm.petMult = petMult

-- One RNG for the whole server. Roblox seeds Random.new() from a secure source. We wrap it as a
-- plain `() -> number` so we can hand it to the pure Rules core (tests inject a fake instead).
local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

-- Mutations sorted rarest-first (built once by the pure core, reused every roll).
local ladder = Rules.buildLadder(Mutations.list)

-- ===================================================================================
-- THE MUTATION ROLL -- SERVER ONLY. This is the single most exploit-sensitive line in the loop.
-- If the client rolled this, every harvest would be a celestial. The client is TOLD the result;
-- it never decides it. The algorithm lives in Rules.rollMutation (pure + VPS-tested for both the
-- fixed-outcome case and the overall distribution); this wrapper just injects the server RNG.
-- `chanceMult` is a hook for fertilizer/weather/biome bias (spec §2.2), 1.0 here.
-- ===================================================================================
function Farm.rollMutation(chanceMult: number?): string
	return Rules.rollMutation(ladder, rand, Mutations.NORMAL_ID, chanceMult)
end

-- Grow clock. os.time() = Unix epoch seconds (server wall-clock, consistent across servers and
-- restarts). We store plot.readyAt in this space so grow timers SURVIVE saves AND crops keep
-- growing while a player is offline (they come back to ready crops -- a retention win). 1-second
-- resolution is plenty for 20s..45min grow times. (The slice used os.clock() which resets each run
-- and would make every saved timer wrong -- fixed here before persistence ships.)
local function now(): number
	return os.time()
end

local function isReady(plot: PlayerData.Plot): boolean
	-- readiness math lives in Rules.isReady (pure + time-injected so tests are deterministic)
	return plot.seedId ~= nil and Rules.isReady(now(), plot.readyAt)
end

local function invKey(plantId: string, mutationId: string): string
	return plantId .. Config.INV_SEP .. mutationId
end

-- ---- PLANT ----------------------------------------------------------------------
-- Validates ownership of the plot, that it is empty, that the seed exists, and that the seed is
-- unlocked for THIS player. Returns (ok, reason).
function Farm.plant(state: PlayerState, seedId: string, plotIndex: number, ownedPlots: number): (boolean, string)
	if type(plotIndex) ~= "number" or plotIndex < 1 or plotIndex > #state.plots then
		return false, "bad_plot"
	end
	local plot = state.plots[plotIndex]
	if plot.seedId ~= nil then
		return false, "occupied" -- can't plant on a plot that's already growing something
	end
	local plant = Plants.get(seedId)
	if not plant then
		return false, "no_such_seed"
	end
	-- Re-check the unlock server-side. NEVER trust that the client only offered unlocked seeds.
	if not Plants.isUnlocked(plant, state, ownedPlots) then
		return false, "locked"
	end
	-- SEED COST (coin sink). The server charges plant.cost and refuses if the player can't afford it.
	-- The client never touches coins -- it only asks to plant. This is what makes the loop an economy.
	if state.coins < plant.cost then
		return false, "too_poor"
	end
	state.coins -= plant.cost
	plot.seedId = seedId
	-- grow time shrinks with the Fast-Growth upgrade, an active "grow" event (Time Storm ×4 etc.), and
	-- an equipped grow pet
	local growDiv = upEffect(state, "growSpeed") * Events.mult(now(), "grow") * petMult(state, "grow")
	plot.readyAt = Rules.readyAt(now(), plant.growMs / growDiv)
	return true, "ok"
end

-- ---- HARVEST --------------------------------------------------------------------
-- Validates the plot has a crop that is actually READY (grow timer elapsed, checked against the
-- server clock -- the client cannot fast-forward growth). Rolls the mutation server-side, banks
-- the crop into inventory, clears the plot. Returns (ok, reason, mutationId).
function Farm.harvest(state: PlayerState, plotIndex: number): (boolean, string, string?)
	if type(plotIndex) ~= "number" or plotIndex < 1 or plotIndex > #state.plots then
		return false, "bad_plot", nil
	end
	local plot = state.plots[plotIndex]
	if plot.seedId == nil then
		return false, "empty", nil
	end
	if not isReady(plot) then
		return false, "not_ready", nil -- server says it's still growing; client cannot override
	end
	local seedId = plot.seedId :: string
	-- SERVER decides the mutation. Lucky-Charm upgrade, a live beehive (pollination), AND any active
	-- "mutation" event (Blood Moon ×3 etc.) all push the odds toward rarer tiers.
	local hiveLvl = (state.bees and state.bees.level) or 0
	local mutBoost = upEffect(state, "luck") * Events.mult(now(), "mutation") * Bees.pollinationMult(hiveLvl) * petMult(state, "luck")
	-- Enchanted Forest crops lean hard toward rare mutations (block 15 biome bias).
	local seedPlant = Plants.get(seedId)
	if seedPlant and seedPlant.biome == "enchanted" then
		mutBoost *= 2.5
	end
	local mutationId = Farm.rollMutation(mutBoost)
	local key = invKey(seedId, mutationId)
	state.inventory[key] = (state.inventory[key] or 0) + 1
	state.harvests += 1
	-- progression (server-owned): XP drives level; codex records each discovered plant x mutation combo
	local plant = Plants.get(seedId)
	local mut = Mutations.get(mutationId)
	state.xp += Rules.xpForHarvest(if plant then plant.tier else 1, if mut then mut.rank else 0)
	state.codex[key] = true
	-- clear the plot
	plot.seedId = nil
	plot.readyAt = nil
	return true, "ok", mutationId
end

-- ---- SELL ALL -------------------------------------------------------------------
-- Sells the whole inventory to the NPC at the PRICE FLOOR (spec §3.3/§3.4):
--   unit value = baseValue(plant.sell) x mutation.mult
-- In the slice biomeTierMult, dayMult(cropOfDay) and coinMult(rebirth) are all 1.0; they multiply
-- in at exactly this spot when those systems exist. NPC price is the hard floor a future player
-- market must beat. Returns (ok, coinsGained).
function Farm.sellAll(state: PlayerState): (boolean, number)
	local gained = 0
	for key, qty in state.inventory do
		if qty > 0 then
			local unit = itemSell(key) -- crops + gathered items alike (NPC floor)
			gained += unit * qty
		end
	end
	if gained <= 0 then
		return false, 0 -- nothing sellable
	end
	-- prestige coinMult + Market-Deal upgrade + "coins" event (Market Boom ×2) + equipped coins pet
	gained = math.floor(gained * Rules.coinMult(state.rebirths or 0) * upEffect(state, "sellBonus") * Events.mult(now(), "coins") * petMult(state, "coins"))
	state.coins += gained
	state.lifetimeEarned += gained -- lifetimeEarned only ever grows; drives "earned" unlocks + all-time board
	local t = now()
	LeaderRules.addEarned(state, gained, math.floor(t / 86400), math.floor(t / 604800)) -- daily/weekly boards
	table.clear(state.inventory)
	return true, gained
end

-- ---- CLIENT VIEW ----------------------------------------------------------------
-- Builds a plain, read-only snapshot to send to the client. The client renders THIS and nothing
-- else it computes locally is authoritative. Note we send unlocked AND locked seeds (with a flag)
-- so the UI can show locked crops greyed out.
function Farm.buildView(state: PlayerState, ownedPlots: number)
	local t = now()

	local plots = {}
	for i, plot in state.plots do
		local locked = i > ownedPlots -- pads beyond your owned count -> buy the Farm Plots upgrade
		if plot.seedId then
			local plant = Plants.get(plot.seedId)
			local secondsLeft = math.max(0, math.ceil((plot.readyAt :: number) - t))
			-- how grown this crop is (0 = just planted, 1 = ready) so the 3D crop can scale as it grows
			local grownFrac = if plant then math.clamp(1 - secondsLeft / math.max(1, plant.growMs / 1000), 0, 1) else 1
			plots[i] = {
				index = i,
				seedId = plot.seedId,
				emoji = if plant then plant.emoji else "?",
				ready = secondsLeft <= 0,
				secondsLeft = secondsLeft,
				grownFrac = grownFrac,
				locked = locked,
			}
		else
			plots[i] = { index = i, seedId = nil, emoji = "", ready = false, secondsLeft = 0, locked = locked }
		end
	end

	local seeds = {}
	for _, plant in Plants.list do
		table.insert(seeds, {
			id = plant.id,
			emoji = plant.emoji,
			sell = plant.sell,
			cost = plant.cost,
			growSeconds = math.floor(plant.growMs / 1000),
			unlocked = Plants.isUnlocked(plant, state, ownedPlots),
			affordable = state.coins >= plant.cost, -- client greys out what you can't afford
		})
	end

	local inventory = {}
	for key, qty in state.inventory do
		if qty > 0 then
			local sep = string.find(key, Config.INV_SEP, 1, true)
			local a = if sep then string.sub(key, 1, sep - 1) else key
			local b = if sep then string.sub(key, sep + 1) else ""
			local unit, emoji = itemSell(key)
			table.insert(inventory, {
				plantId = a,
				mutationId = b,
				qty = qty,
				unitValue = unit,
				emoji = emoji,
			})
		end
	end

	local codexCount = 0
	for _ in state.codex do
		codexCount += 1
	end

	local petEmoji = ""
	if state.pets and state.pets.equipped then
		local p = Pets.get(state.pets.equipped)
		petEmoji = if p then p.emoji else ""
	end

	return {
		coins = state.coins,
		lifetimeEarned = state.lifetimeEarned,
		harvests = state.harvests,
		xp = state.xp,
		level = Rules.levelForXp(state.xp),
		codexCount = codexCount,
		plots = plots,
		seeds = seeds,
		inventory = inventory,
		pet = petEmoji,
	}
end

return Farm
