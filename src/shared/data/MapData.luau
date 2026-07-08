--!strict
-- MapData: PURE map bounds + landmark list derived from the real WorldLayout coords (block 16). The
-- minimap/full-map project these through MapRules.worldToMap. Keeping it derived from WorldLayout means
-- the map can never drift from where things actually are.

local WorldLayout = require(script.Parent.WorldLayout)
local City = require(script.Parent.City)

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

-- Real biome names so the map labels each island properly (mirrors World.ISLAND_NAMES).
local ISLAND_NAMES = {
	"Sunny Beach", "Whispering Woods", "Frostpeak", "Volcano Isle", "Golden Dunes",
	"Crystal Cove", "Mushroom Grove", "Windy Cliffs", "Coral Reef", "Misty Highlands",
	"Enchanted Forest",
}

-- Fixed landmarks (town centre, harbor) + every island. The player's own farm + "you" dot are added live.
function M.landmarks(): { Landmark }
	local out: { Landmark } = {
		{ name = "Town Centre", x = 0, z = WorldLayout.PLAZA_Z, kind = "plaza" },
		-- harbor sits on the SOUTH coast now (dock bridges land -> sea), not next to the centre
		{ name = "Harbor", x = 0, z = -(WorldLayout.MAINLAND_RADIUS + 140), kind = "harbor" },
	}
	-- every civic building (hospital, car dealer, bike shop...) from the shared City ring
	for k, b in City.buildings do
		local c = City.centerOf(k)
		table.insert(out, { name = b.emoji .. " " .. b.name, x = c.x, z = c.z, kind = "city" })
	end
	for i = 1, WorldLayout.ISLAND_COUNT do
		local c = WorldLayout.islandCenter(i)
		table.insert(out, { name = ISLAND_NAMES[i] or ("Island " .. i), x = c.x, z = c.z, kind = "island", island = i })
	end
	return out
end

return M
