--!strict
-- Farm: the SERVER-SIDE rules of the core loop. Pure-ish logic that mutates a player's
-- PlayerState. Every function here runs ONLY on the server. The client cannot call these; it can
-- only send an intent (Plant/Harvest/SellAll) that the server's handler forwards here after
-- validating. If a rule matters for fairness, it is enforced in this file.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Plants = require(ReplicatedStorage.Bloomly.data.Plants)
local Mutations = require(ReplicatedStorage.Bloomly.data.Mutations)
local Config = require(ReplicatedStorage.Bloomly.data.Config)
local PlayerData = require(script.Parent.PlayerData)

type PlayerState = PlayerData.PlayerState

local Farm = {}

-- One RNG for the whole server. Roblox seeds Random.new() from a secure source.
local rng = Random.new()

-- Mutations sorted rarest-first (highest rank first) so "highest-rank wins": we check the rarest
-- mutation first and return the first one that hits.
local ladder = table.clone(Mutations.list)
table.sort(ladder, function(a, b)
	return a.rank > b.rank
end)

-- ===================================================================================
-- THE MUTATION ROLL -- SERVER ONLY. This is the single most exploit-sensitive line in the loop.
-- If the client rolled this, every harvest would be a celestial. The client is TOLD the result;
-- it never decides it. `chanceMult` is a hook for fertilizer/weather/biome bias (spec §2.2), 1.0 here.
-- ===================================================================================
function Farm.rollMutation(chanceMult: number?): string
	local mult = chanceMult or 1.0
	for _, m in ladder do -- rarest -> commonest
		if rng:NextNumber() < m.chance * mult then
			return m.id -- highest-rank hit wins; stop
		end
	end
	return Mutations.NORMAL_ID -- the common case: a plain crop
end

-- Elapsed-time clock. os.clock() is a high-precision monotonic timer -- correct for measuring
-- grow durations within a single server run. (A DataStore build would persist os.time() instead so
-- growth continues across sessions; noted at the seam in PlayerData.)
local function now(): number
	return os.clock()
end

local function isReady(plot: PlayerData.Plot): boolean
	return plot.seedId ~= nil and plot.readyAt ~= nil and now() >= (plot.readyAt :: number)
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
	-- TODO(economy): charge plant.cost as a seed sink here once coins are a real constraint.
	-- The slice lets you plant free so the loop is easy to exercise.
	plot.seedId = seedId
	plot.readyAt = now() + plant.growMs / 1000 -- growMs is milliseconds; grow timer is server-owned
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
	local mutationId = Farm.rollMutation() -- SERVER decides the outcome
	local key = invKey(seedId, mutationId)
	state.inventory[key] = (state.inventory[key] or 0) + 1
	state.harvests += 1
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
			local sep = string.find(key, Config.INV_SEP, 1, true)
			local plantId = if sep then string.sub(key, 1, sep - 1) else key
			local mutationId = if sep then string.sub(key, sep + 1) else Mutations.NORMAL_ID
			local plant = Plants.get(plantId)
			if plant then
				local unit = math.floor(plant.sell * Mutations.multOf(mutationId))
				gained += unit * qty
			end
		end
	end
	if gained <= 0 then
		return false, 0 -- nothing sellable
	end
	state.coins += gained
	state.lifetimeEarned += gained -- lifetimeEarned only ever grows; drives "earned" unlocks
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
		if plot.seedId then
			local plant = Plants.get(plot.seedId)
			local secondsLeft = math.max(0, math.ceil((plot.readyAt :: number) - t))
			plots[i] = {
				index = i,
				seedId = plot.seedId,
				emoji = if plant then plant.emoji else "?",
				ready = secondsLeft <= 0,
				secondsLeft = secondsLeft,
			}
		else
			plots[i] = { index = i, seedId = nil, emoji = "", ready = false, secondsLeft = 0 }
		end
	end

	local seeds = {}
	for _, plant in Plants.list do
		table.insert(seeds, {
			id = plant.id,
			emoji = plant.emoji,
			sell = plant.sell,
			growSeconds = math.floor(plant.growMs / 1000),
			unlocked = Plants.isUnlocked(plant, state, ownedPlots),
		})
	end

	local inventory = {}
	for key, qty in state.inventory do
		if qty > 0 then
			local sep = string.find(key, Config.INV_SEP, 1, true)
			local plantId = if sep then string.sub(key, 1, sep - 1) else key
			local mutationId = if sep then string.sub(key, sep + 1) else Mutations.NORMAL_ID
			local plant = Plants.get(plantId)
			local unit = if plant then math.floor(plant.sell * Mutations.multOf(mutationId)) else 0
			table.insert(inventory, {
				plantId = plantId,
				mutationId = mutationId,
				qty = qty,
				unitValue = unit,
				emoji = if plant then plant.emoji else "?",
			})
		end
	end

	return {
		coins = state.coins,
		lifetimeEarned = state.lifetimeEarned,
		harvests = state.harvests,
		plots = plots,
		seeds = seeds,
		inventory = inventory,
	}
end

return Farm
