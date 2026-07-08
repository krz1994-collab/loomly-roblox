--!strict
-- Quest: the server shell over the pure QuestRules engine. Other systems call `Quest.report` from
-- every activity (plant/harvest/sell/fish/mine/...); talking to an NPC calls `Quest.talkTo` which
-- turns in a ready quest (applying its reward) or accepts the giver's next available quest.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local QuestRules = require(ReplicatedStorage.Bloomly.QuestRules)
local Rules = require(ReplicatedStorage.Bloomly.Rules)
local Quests = require(ReplicatedStorage.Bloomly.data.Quests)
local ChallengeRules = require(ReplicatedStorage.Bloomly.ChallengeRules)
local Challenges = require(ReplicatedStorage.Bloomly.data.Challenges)
local PlayerData = require(script.Parent.PlayerData)

local Quest = {}

-- Report a gameplay event to a player's active quests. Returns true if any progressed.
function Quest.report(player: Player, kind: string, target: string?, n: number?): boolean
	local state = PlayerData.get(player)
	if not state then
		return false
	end
	-- Same event also feeds the DAILY CHALLENGES (one central hook, zero extra call sites).
	if state.challenges then
		ChallengeRules.bump(state.challenges, math.floor(os.time() / 86400), Challenges.list, Challenges.DAILY_COUNT, kind, n or 1)
	end
	return QuestRules.report(state, Quests.list, kind, target, n or 1)
end

-- Apply a quest reward to the player's state (server-authoritative).
local function applyReward(state: any, reward: any)
	if reward.coins then
		state.coins += reward.coins
		state.lifetimeEarned += reward.coins
	end
	if reward.xp then
		state.xp += reward.xp
	end
	if reward.unlock then
		state.unlocks[reward.unlock] = true
	end
	if reward.item then
		state.inventory[reward.item] = (state.inventory[reward.item] or 0) + 1
	end
end

-- Player talks to NPC `npcId`. Turns in a READY quest (reward applied) or accepts the next AVAILABLE
-- one. Returns { action = "complete"|"accept"|"chat", questName?, reward? } for a dialogue toast.
function Quest.talkTo(player: Player, npcId: string): any
	local state = PlayerData.get(player)
	if not state then
		return { action = "chat" }
	end
	local level = Rules.levelForXp(state.xp)
	QuestRules.report(state, Quests.list, "talk", npcId, 1)

	-- 1) turn in a READY quest from this giver (reward applied)
	for _, q in Quests.forGiver(npcId) do
		if QuestRules.isReady(state, q) then
			local reward = QuestRules.turnIn(state, q)
			if reward then
				applyReward(state, reward)
				return { action = "complete", questName = q.name, reward = reward }
			end
		end
	end
	-- 2) if a quest from this giver is ACTIVE but not done, REMIND the player what to do
	for _, q in Quests.forGiver(npcId) do
		if QuestRules.isActive(state, q.id) then
			return { action = "active", questName = q.name, objective = QuestRules.describeActive(state, q) }
		end
	end
	-- 3) otherwise ACCEPT the next available quest and EXPLAIN its objective
	for _, q in Quests.forGiver(npcId) do
		if QuestRules.isAvailable(q, state, level) then
			QuestRules.accept(state, q)
			return { action = "accept", questName = q.name, objective = QuestRules.describeStep(q.steps[1]) }
		end
	end
	return { action = "chat" }
end

-- A compact list of the player's active quests + progress, for the client quest-tracker.
function Quest.activeView(state: any): { any }
	local out = {}
	if not state.quests or not state.quests.active then
		return out
	end
	for qid, a in state.quests.active do
		local q = Quests.get(qid)
		if q then
			local step = q.steps[math.min(a.step, #q.steps)]
			table.insert(out, { name = q.name, step = a.step, steps = #q.steps, prog = a.prog, need = step and step.count or 0, ready = a.step > #q.steps })
		end
	end
	return out
end

return Quest
