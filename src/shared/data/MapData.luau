--!strict
-- MapData: PURE map bounds + landmark list derived from the real WorldLayout coords (block 16). The
-- minimap/full-map project these through MapRules.worldToMap. Keeping it derived from WorldLayout means
-- the map can never drift from where things actually are.

local WorldLayout = require(script.Parent.WorldLayout)

local M = {}

-- Bounds enclose the whole map: the plaza + plot grid at the centre, the island ring far out.
local pad = WorldLayout.ISLAND_RING * 1.15
M.BOUNDS = {
	minX = -pad,
	maxX = pad,
	minZ = WorldLayout.MAP_CENTER_Z - pad,
	maxZ = WorldLayout.MAP_CENTER_Z + pad,
}

export type Landmark = { name: string, x: number, z: number, kind: string, island: number? }

-- Fixed landmarks (plaza, harbor) + every island. The player's own farm + "you" dot are added live.
function M.landmarks(): { Landmark }
	local out: { Landmark } = {
		{ name = "Plaza", x = 0, z = WorldLayout.PLAZA_Z, kind = "plaza" },
		{ name = "Harbor", x = 0, z = WorldLayout.PLAZA_Z - 70, kind = "harbor" },
	}
	for i = 1, WorldLayout.ISLAND_COUNT do
		local c = WorldLayout.islandCenter(i)
		table.insert(out, { name = "Island " .. i, x = c.x, z = c.z, kind = "island", island = i })
	end
	return out
end

return M
