--!strict
-- QuestRules: the PURE quest engine (no Roblox globals; deps injected). Runs on the VPS luau CLI so
-- quest progression is unit-tested before it reaches Studio. The shell (Quest.luau) calls
-- `report(...)` from every activity (harvest/sell/catch/mine/...) and `turnIn(...)` when a player
-- talks to the quest's giver NPC.
--
-- Quest data row: { id, giver, name, steps = { {kind, target?, count} }, reward = {coins?,xp?,item?,unlock?}, prereq?, level? }
--   step matches an event when step.kind == kind AND (step.target == nil / "any" / == target).
-- Player progress lives in state.quests = { done = {[qid]=true}, active = {[qid] = {step=1, prog=0}} }.

export type Step = { kind: string, target: string?, count: number }
export type Reward = { coins: number?, xp: number?, item: string?, unlock: string? }
export type Quest = { id: string, giver: string, name: string, steps: { Step }, reward: Reward, prereq: string?, level: number? }

local QuestRules = {}

local function ensure(state: any)
	if not state.quests then
		state.quests = { done = {}, active = {} }
	end
	if not state.quests.done then
		state.quests.done = {}
	end
	if not state.quests.active then
		state.quests.active = {}
	end
	return state.quests
end

function QuestRules.isDone(state: any, qid: string): boolean
	return ensure(state).done[qid] == true
end

function QuestRules.isActive(state: any, qid: string): boolean
	return ensure(state).active[qid] ~= nil
end

-- Available = not done, not already active, prereq (if any) done, and player level high enough.
function QuestRules.isAvailable(quest: Quest, state: any, level: number): boolean
	if QuestRules.isDone(state, quest.id) or QuestRules.isActive(state, quest.id) then
		return false
	end
	if quest.prereq and not QuestRules.isDone(state, quest.prereq) then
		return false
	end
	return level >= (quest.level or 0)
end

function QuestRules.accept(state: any, quest: Quest): boolean
	if not QuestRules.isActive(state, quest.id) and not QuestRules.isDone(state, quest.id) then
		ensure(state).active[quest.id] = { step = 1, prog = 0 }
		return true
	end
	return false
end

local function stepMatches(step: Step, kind: string, target: string?): boolean
	if step.kind ~= kind then
		return false
	end
	return step.target == nil or step.target == "any" or step.target == target
end

-- All steps satisfied? (active pointer moved past the last step.)
function QuestRules.isReady(state: any, quest: Quest): boolean
	local a = ensure(state).active[quest.id]
	return a ~= nil and a.step > #quest.steps
end

-- Report a gameplay event to ALL active quests. Advances any whose current step matches.
-- Returns true if any quest's progress changed (so the shell can push an update).
function QuestRules.report(state: any, quests: { Quest }, kind: string, target: string?, n: number): boolean
	local q = ensure(state)
	local changed = false
	for _, quest in quests do
		local a = q.active[quest.id]
		if a and a.step <= #quest.steps then
			local step = quest.steps[a.step]
			if stepMatches(step, kind, target) then
				a.prog += (n or 1)
				changed = true
				while a.step <= #quest.steps and a.prog >= quest.steps[a.step].count do
					a.prog -= quest.steps[a.step].count
					a.step += 1
					a.prog = 0 -- leftover progress does not carry to the next step
				end
			end
		end
	end
	return changed
end

-- Turn a ready quest in (called when the player talks to its giver). Moves it to done and RETURNS the
-- reward for the caller to apply (pure: never touches coins/xp itself). Returns nil if not ready.
function QuestRules.turnIn(state: any, quest: Quest): Reward?
	local q = ensure(state)
	if QuestRules.isReady(state, quest) then
		q.active[quest.id] = nil
		q.done[quest.id] = true
		return quest.reward
	end
	return nil
end

-- How many distinct quests the player has completed (for milestone checks / achievements).
function QuestRules.doneCount(state: any): number
	local n = 0
	for _ in ensure(state).done do
		n += 1
	end
	return n
end

-- Turn a machine step {kind,target,count} into a human objective an NPC can read aloud, so quests
-- actually explain themselves ("Plant 3 crops", "Sail to island 3", "Defeat 5 monsters").
function QuestRules.describeStep(step: any): string
	local n = step.count or 1
	local k = step.kind
	if k == "talk" then
		return "Go talk to " .. tostring(step.target or "them")
	elseif k == "sail" then
		return (step.target and ("Sail to island " .. tostring(step.target))) or "Sail to an island"
	elseif k == "buy_boat" then
		return "Buy a boat from the Harbor"
	end
	local phrase: { [string]: string } = {
		plant = "Plant " .. n .. " crops",
		harvest = "Harvest " .. n .. " crops",
		harvest_mut = "Harvest " .. n .. " mutated crops",
		sell = "Sell " .. n .. " items at the Market",
		fish = "Catch " .. n .. " fish",
		catch_bug = "Catch " .. n .. " bugs",
		mine = "Mine " .. n .. " ores",
		forage = "Forage " .. n .. " items",
		cook = "Cook " .. n .. " dishes",
		buy_animal = "Buy " .. n .. " animals",
		collect_animal = "Collect from animals " .. n .. " times",
		breed = "Breed " .. n .. " animals",
		upgrade = "Buy " .. n .. " upgrades",
		decorate = "Place " .. n .. " decorations",
		trade = "Trade with " .. n .. " players",
		buy_vehicle = "Buy a vehicle",
		find_treasure = "Dig up " .. n .. " treasures",
		rebirth = "Rebirth " .. n .. " times",
		donate = "Donate " .. n .. " items to the Museum",
		buy_pet = "Adopt " .. n .. " pets",
		kill = "Defeat " .. n .. " monsters",
		loot = "Collect " .. n .. " monster loot",
	}
	return phrase[k] or (k .. " x" .. n)
end

-- The player's CURRENT objective for an active quest, with live progress ("Plant 3 crops (1/3)").
function QuestRules.describeActive(state: any, quest: Quest): string
	local a = ensure(state).active[quest.id]
	if not a then
		return QuestRules.describeStep(quest.steps[1])
	end
	local step = quest.steps[math.min(a.step, #quest.steps)]
	local need = step.count or 1
	return QuestRules.describeStep(step) .. " (" .. (a.prog or 0) .. "/" .. need .. ")"
end

return QuestRules
