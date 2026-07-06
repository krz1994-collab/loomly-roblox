--!strict
-- PlotClaim: server-only bookkeeping of which player owns which farm SECTION this session.
-- Sections are session-only (never persisted). Decisions come from the pure PlotRules module.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Bloomly.data.Config)
local PlotRules = require(ReplicatedStorage.Bloomly.PlotRules)

local PlotClaim = {}

local sectionToUser: { [number]: number } = {} -- section -> userId (a section is "taken" iff present here)
local userToSection: { [number]: number } = {} -- userId -> section

-- Assign the lowest free section to a joining player. Returns the section, or nil if the world is
-- full (won't happen while PLOT_SECTIONS == MAX_PLAYERS).
function PlotClaim.claim(player: Player): number?
	local uid = player.UserId
	if userToSection[uid] then
		return userToSection[uid]
	end
	local section = PlotRules.pickFreeSection(sectionToUser, Config.PLOT_SECTIONS)
	if not section then
		return nil
	end
	sectionToUser[section] = uid
	userToSection[uid] = section
	return section
end

-- Free a leaving player's section so it can be reused. Returns the freed section (for cleanup).
function PlotClaim.release(player: Player): number?
	local uid = player.UserId
	local section = userToSection[uid]
	if section then
		sectionToUser[section] = nil
	end
	userToSection[uid] = nil
	return section
end

function PlotClaim.sectionOf(userId: number): number?
	return userToSection[userId]
end

-- Who owns the section a prompt was fired on (used for the ownership guard on every interaction).
function PlotClaim.ownerOfSection(section: number): number?
	return sectionToUser[section]
end

return PlotClaim
