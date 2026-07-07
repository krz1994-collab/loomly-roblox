--!strict
-- Homestead: the SERVER shell for the four passive/craft systems (blocks 7-10): ORCHARD (fruit trees),
-- PEN (animals + breeding), KITCHEN (cooking), HIVE (honey), HOUSE (rent + decor). Like Farm, every
-- function here runs only on the server and mutates the caller's own PlayerState. The exploit-sensitive
-- decisions (cost, unlock, timers, RNG) are enforced here + in the pure rules (ProduceRules/CookRules/
-- AnimalRules/HouseRules, all VPS-tested). Interactions are kid-simple: PLANT/BUY fills the next empty
-- slot with the best you can afford; PICK/COLLECT harvests every ready slot at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Trees = require(ReplicatedStorage.Bloomly.data.Trees)
local Animals = require(ReplicatedStorage.Bloomly.data.Animals)
local Recipes = require(ReplicatedStorage.Bloomly.data.Recipes)
local Bees = require(ReplicatedStorage.Bloomly.data.Bees)
local House = require(ReplicatedStorage.Bloomly.data.House)
local Upgrades = require(ReplicatedStorage.Bloomly.data.Upgrades)
local UpgradeRules = require(ReplicatedStorage.Bloomly.UpgradeRules)
local ProduceRules = require(ReplicatedStorage.Bloomly.ProduceRules)
local CookRules = require(ReplicatedStorage.Bloomly.CookRules)
local AnimalRules = require(ReplicatedStorage.Bloomly.AnimalRules)
local HouseRules = require(ReplicatedStorage.Bloomly.HouseRules)
local Rules = require(ReplicatedStorage.Bloomly.Rules)
local PlayerData = require(script.Parent.PlayerData)

type PlayerState = PlayerData.PlayerState

local Homestead = {}

Homestead.ORCHARD_SLOTS = 4
Homestead.PEN_SLOTS = 4

-- Greenhouse upgrade speed multiplier (shrinks orchard cycles).
local function greenhouseMult(state: PlayerState): number
	local tr = Upgrades.get("greenhouse")
	if not tr then
		return 1
	end
	return UpgradeRules.effectAt(tr, (state.upgrades and state.upgrades.greenhouse) or 0)
end

-- The player's level (for unlock gates).
local function levelOf(state: PlayerState): number
	return Rules.levelForXp(state.xp)
end

-- Next empty slot key ("1".."N") in a slot map, or nil if full.
local function nextEmptySlot(map: { [string]: any }, n: number): string?
	for i = 1, n do
		local k = tostring(i)
		if map[k] == nil then
			return k
		end
	end
	return nil
end

local function bank(state: PlayerState, key: string, n: number)
	if n > 0 then
		state.inventory[key] = (state.inventory[key] or 0) + n
	end
end

-- ================= ORCHARD (block 7) =================
-- Plant the most valuable tree you can afford + are high enough level for, into the next empty slot.
function Homestead.plantTree(state: PlayerState, now: number): (boolean, string)
	local slot = nextEmptySlot(state.orchard, Homestead.ORCHARD_SLOTS)
	if not slot then
		return false, "Your orchard is full! Pick fruit or wait."
	end
	local lvl = levelOf(state)
	local best: any = nil
	for _, t in Trees.list do
		if t.unlockLevel <= lvl and state.coins >= t.cost then
			if best == nil or t.cost > best.cost then
				best = t
			end
		end
	end
	if not best then
		return false, "Can't afford any tree yet -- earn more coins!"
	end
	state.coins -= best.cost
	state.orchard[slot] = { treeId = best.id, lastPick = now }
	return true, best.emoji .. " Planted a " .. best.name .. "!"
end

-- Pick ripe fruit from EVERY orchard slot into inventory. Returns (totalFruit, message).
function Homestead.pickFruit(state: PlayerState, now: number): (number, string)
	local mult = greenhouseMult(state)
	local total = 0
	for _, slotData in state.orchard do
		local tree = Trees.get(slotData.treeId)
		if tree then
			local effCycle = tree.cycleSec / math.max(mult, 1e-6)
			local n, newLast = ProduceRules.collect(slotData.lastPick, now, effCycle, tree.cap)
			if n > 0 then
				bank(state, "fruit|" .. tree.fruitId, n)
				slotData.lastPick = newLast
				total += n
			end
		end
	end
	if total > 0 then
		return total, "🍎 Picked " .. total .. " fruit!"
	end
	return 0, "No ripe fruit yet -- give the trees time."
end

-- ================= PEN (block 8) =================
function Homestead.buyAnimal(state: PlayerState, now: number): (boolean, string)
	local slot = nextEmptySlot(state.animals, Homestead.PEN_SLOTS)
	if not slot then
		return false, "Your pen is full!"
	end
	local lvl = levelOf(state)
	local best: any = nil
	for _, a in Animals.list do
		if a.unlockLevel <= lvl and state.coins >= a.cost then
			if best == nil or a.cost > best.cost then
				best = a
			end
		end
	end
	if not best then
		return false, "Can't afford any animal yet!"
	end
	state.coins -= best.cost
	state.animals[slot] = { animalId = best.id, lastCollect = now }
	return true, best.emoji .. " Bought a " .. best.name .. "!"
end

function Homestead.collectProducts(state: PlayerState, now: number): (number, string)
	local total = 0
	for _, slotData in state.animals do
		local animal = Animals.get(slotData.animalId)
		if animal then
			local n, newLast = ProduceRules.collect(slotData.lastCollect, now, animal.produceSec, animal.cap)
			if n > 0 then
				bank(state, "product|" .. animal.productId, n)
				slotData.lastCollect = newLast
				total += n
			end
		end
	end
	if total > 0 then
		return total, "🧺 Collected " .. total .. " animal products!"
	end
	return 0, "Your animals need more time to produce."
end

-- Breed two same-species animals into a (possibly rarer) baby in an empty slot.
function Homestead.breed(state: PlayerState, rand: () -> number, now: number): (boolean, string)
	local slot = nextEmptySlot(state.animals, Homestead.PEN_SLOTS)
	if not slot then
		return false, "No empty pen slot for a baby!"
	end
	-- find any two DIFFERENT slots holding the SAME species
	local counts: { [string]: number } = {}
	local pairSpecies: string? = nil
	for _, sd in state.animals do
		counts[sd.animalId] = (counts[sd.animalId] or 0) + 1
		if counts[sd.animalId] >= 2 then
			pairSpecies = sd.animalId
		end
	end
	if not pairSpecies then
		return false, "Need two of the SAME animal to breed."
	end
	local parent = Animals.get(pairSpecies)
	if not parent then
		return false, "breed_err"
	end
	local babyTier = AnimalRules.offspringTier(parent.tier, parent.tier, rand)
	local baby = Animals.firstOfTier(babyTier) or parent
	state.animals[slot] = { animalId = baby.id, lastCollect = now }
	return true, "🐣 A baby " .. baby.name .. " was born!"
end

-- ================= KITCHEN (block 9) =================
function Homestead.cook(state: PlayerState, now: number): (boolean, string)
	if state.kitchen.recipeId ~= nil then
		return false, "The kitchen is already cooking something!"
	end
	local lvl = levelOf(state)
	local best: any = nil
	for _, r in Recipes.list do
		if r.unlockLevel <= lvl and CookRules.canCook(state.inventory, r) then
			if best == nil or r.sell > best.sell then
				best = r
			end
		end
	end
	if not best then
		return false, "No recipe you can make -- gather ingredients first!"
	end
	CookRules.consume(state.inventory, best)
	state.kitchen.recipeId = best.id
	state.kitchen.doneAt = now + best.cookSec
	return true, best.emoji .. " Cooking " .. best.name .. " (" .. best.cookSec .. "s)..."
end

function Homestead.collectDish(state: PlayerState, now: number): (boolean, string)
	local rid = state.kitchen.recipeId
	if rid == nil then
		return false, "Nothing is cooking."
	end
	if not CookRules.isDone(state.kitchen.doneAt, now) then
		return false, "Still cooking -- wait a moment!"
	end
	local r = Recipes.get(rid)
	state.kitchen.recipeId = nil
	state.kitchen.doneAt = nil
	if r then
		bank(state, "dish|" .. r.id, 1)
		state.xp += r.xp
		return true, r.emoji .. " " .. r.name .. " is ready! (+" .. r.xp .. " xp)"
	end
	return false, "cook_err"
end

-- ================= HIVE (block 9) =================
function Homestead.upgradeHive(state: PlayerState, now: number): (boolean, string)
	local lvl = state.bees.level
	local cost = Bees.upgradeCost(lvl)
	if cost == nil then
		return false, "Your hive is already max level!"
	end
	if state.coins < cost then
		return false, "Need " .. cost .. " coins for the hive."
	end
	state.coins -= cost
	if lvl == 0 then
		state.bees.lastCollect = now -- first build: start the clock
	end
	state.bees.level = lvl + 1
	return true, "🐝 Hive upgraded to level " .. (lvl + 1) .. "!"
end

function Homestead.collectHoney(state: PlayerState, now: number): (number, string)
	local lvl = state.bees.level
	if lvl <= 0 then
		return 0, "Build a beehive first!"
	end
	local data = Bees.dataAt(lvl)
	if not data then
		return 0, "hive_err"
	end
	local n, newLast = ProduceRules.collect(state.bees.lastCollect, now, data.produceSec, data.cap)
	if n > 0 then
		bank(state, "honey|" .. Bees.HONEY.id, n)
		state.bees.lastCollect = newLast
		return n, "🍯 Collected " .. n .. " honey!"
	end
	return 0, "No honey ready yet."
end

-- ================= HOUSE (block 10) =================
function Homestead.collectRent(state: PlayerState, now: number): (number, string)
	local tier = House.tierData(state.house.tier)
	if not tier then
		return 0, "house_err"
	end
	local rpm = HouseRules.rentPerMin(tier.rentPerMin, state.house.decor, House.decorList)
	local due = HouseRules.rentDue(state.house.lastRent, now, rpm, tier.rentCap)
	state.house.lastRent = now
	if due > 0 then
		state.coins += due
		state.lifetimeEarned += due
		return due, "🏠 Collected " .. due .. " coins rent!"
	end
	return 0, "No rent to collect yet."
end

function Homestead.upgradeHouse(state: PlayerState, now: number): (boolean, string)
	local cost = House.upgradeCost(state.house.tier)
	if cost == nil then
		return false, "Your house is already a Castle -- the best!"
	end
	if state.coins < cost then
		return false, "Need " .. cost .. " coins to upgrade your house."
	end
	-- collect any pending rent at the OLD rate first so the upgrade is fair
	Homestead.collectRent(state, now)
	state.coins -= cost
	state.house.tier += 1
	local t = House.tierData(state.house.tier)
	return true, "🏠 Upgraded to " .. (t and t.name or "?") .. "!"
end

function Homestead.buyDecor(state: PlayerState): (boolean, string)
	local best: any = nil
	for _, d in House.decorList do
		if d.unlockTier <= state.house.tier and state.coins >= d.cost then
			if best == nil or d.cost > best.cost then
				best = d
			end
		end
	end
	if not best then
		return false, "No decor you can afford/unlock yet."
	end
	state.coins -= best.cost
	state.house.decor[best.id] = (state.house.decor[best.id] or 0) + 1
	return true, best.emoji .. " Placed a " .. best.name .. "! (+rent)"
end

return Homestead
