--!strict
-- Sounds: the sound registry (data). The client builds one Sound per entry and plays it by key.
--
-- ASSET IDs: `reward` and `click` use long-standing Roblox ENGINE built-in sounds (rbxasset://), so
-- they work with no upload. The rest are left EMPTY on purpose -- drop in your own nicer sound asset
-- ids (from the Toolbox / your uploads) as "rbxassetid://XXXXXXX" and they start playing automatically.
-- An empty id just plays nothing (safe). Do not guess ids you do not have.

export type SoundDef = { id: string, volume: number, looped: boolean? }

local M = {}

M.map = {
	reward = { id = "rbxasset://sounds/electronicpingshort.wav", volume = 0.45 }, -- coins / xp gained
	click = { id = "rbxasset://sounds/button.wav", volume = 0.35 }, -- ui / select
	levelup = { id = "", volume = 0.7 }, -- add a triumphant chime
	harvest = { id = "", volume = 0.5 }, -- add a pluck / pop
	plant = { id = "", volume = 0.45 }, -- add a soft dig
	sell = { id = "", volume = 0.5 }, -- add a cash-register
	treasure = { id = "", volume = 0.7 }, -- add a chest-open fanfare
	event = { id = "", volume = 0.7 }, -- add an event horn
	music = { id = "", volume = 0.25, looped = true }, -- add a calm background loop
}

return M
