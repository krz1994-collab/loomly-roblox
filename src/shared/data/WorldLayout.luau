--!strict
-- WorldLayout: PURE geometry + constants for the shared world (no Roblox globals; returns plain
-- {x,z} tables). World.luau turns these into CFrames/Parts. This is the rare 3D bit that IS
-- VPS-testable -- unit tests prove the 100 big plots never overlap and everything sits inside its plot.
--
-- Layout: a central PLAZA (shops + spawn) at the front; behind it a spread grid of 100 personal
-- FARM PLOTS, each 300x300 studs (mega room to expand: crop field + house + pen + utility + orchard).
-- 60-stud roads run in the gaps. The map is huge (~3600 wide) so World enables StreamingEnabled.

local WorldLayout = {}

-- ---- plot ring layout (studs) ----
-- RADIAL: the plaza/hub is the CENTRE (0,0); the 100 personal plots sit in concentric RINGS around it.
WorldLayout.SECTION_SIZE = 300 -- each personal plot is 300 x 300
WorldLayout.SECTION_SPACING = 360 -- min centre-to-centre (=> 60-stud roads between plots)
WorldLayout.SECTION_COLS = 10 -- kept for compatibility (plot count math elsewhere)
WorldLayout.GRID_START_Z = 500 -- legacy; unused by the radial layout
WorldLayout.RING0 = 720 -- radius of the innermost plot ring (clears the plaza)

-- ---- crop field inside a plot ----
WorldLayout.PAD_SIZE = 14 -- a plantable pad is 14 x 14
WorldLayout.PAD_COLS = 4 -- pads per row in the crop field
WorldLayout.PAD_SPACING = 22 -- centre-to-centre between pads
WorldLayout.CROP_FIELD = { x = 0, z = -80 } -- crop field centre, local to the plot (toward the entrance)

-- ---- plaza + mainland ----
WorldLayout.PLAZA_RADIUS = 190 -- central hub platform radius (spawn + main shops), at the map centre
WorldLayout.PLAZA_Z = 0 -- plaza sits at the EXACT map centre (0,0); plots ring around it
WorldLayout.MAINLAND_RADIUS = 2600 -- the grass island reaches out to here (covers every plot ring + margin)

-- World position of plot `i` (1-based). RADIAL: plots fill concentric RINGS around the centre (0,0), so
-- the plaza is in the middle and the farms fan out in a circle. Each ring holds as many plots as fit at
-- >= SECTION_SPACING arc spacing; rings step out by SECTION_SPACING. A per-ring angular offset staggers
-- neighbouring rings so no two plots line up radially (keeps min centre distance >= SECTION_SIZE).
function WorldLayout.sectionCenter(i: number): { x: number, z: number }
	local spacing = WorldLayout.SECTION_SPACING
	local placed = 0
	local r = WorldLayout.RING0
	local ring = 0
	while true do
		local cap = math.max(1, math.floor((2 * math.pi * r) / spacing))
		if i <= placed + cap then
			local k = i - placed - 1
			local ang = (k / cap) * math.pi * 2 + ring * 0.37
			return { x = math.cos(ang) * r, z = math.sin(ang) * r }
		end
		placed += cap
		r += spacing
		ring += 1
	end
end

-- Angle (radians) from the map centre to plot `i` -- used to face the plot's GATEWAY toward the centre
-- so every farm opens onto the ring road, not toward a fixed compass edge.
function WorldLayout.sectionAngle(i: number): number
	local c = WorldLayout.sectionCenter(i)
	return math.atan2(c.z, c.x)
end

-- Local offset of crop pad `plotIndex` (1-based) within the crop field (relative to plot centre).
function WorldLayout.plotPadOffset(plotIndex: number, plotCount: number): { x: number, z: number }
	local idx = plotIndex - 1
	local rows = math.ceil(plotCount / WorldLayout.PAD_COLS)
	local col = idx % WorldLayout.PAD_COLS
	local row = math.floor(idx / WorldLayout.PAD_COLS)
	local x = WorldLayout.CROP_FIELD.x + (col - (WorldLayout.PAD_COLS - 1) / 2) * WorldLayout.PAD_SPACING
	local z = WorldLayout.CROP_FIELD.z + (row - (rows - 1) / 2) * WorldLayout.PAD_SPACING
	return { x = x, z = z }
end

-- ---- islands (reached by boat from the plaza harbor) ----
-- 11 islands: 10 biome isles + the Enchanted Forest (index 11, block 15), unlocked latest (L35).
WorldLayout.ISLAND_COUNT = 11
WorldLayout.ISLAND_RING = 3600 -- islands sit this far out in the ocean, in a ring around the centre
WorldLayout.ISLAND_SIZE = 600 -- approx landmass diameter
WorldLayout.MAP_CENTER_Z = 0 -- everything centres on (0,0): plaza, plot rings, island ring, ambient

-- Centre of island `i` (1-based), scattered in a ring around the map centre (far past the plots).
function WorldLayout.islandCenter(i: number): { x: number, z: number }
	local a = (i - 1) / WorldLayout.ISLAND_COUNT * math.pi * 2 + 0.35
	return {
		x = math.cos(a) * WorldLayout.ISLAND_RING,
		z = WorldLayout.MAP_CENTER_Z + math.sin(a) * WorldLayout.ISLAND_RING,
	}
end

-- Where each expansion ZONE sits inside a plot (local to plot centre). These are reserved now with
-- "soon" markers; the systems (house/animals/utility/orchard) drop into the space in later layers.
local ZONES: { [string]: { x: number, z: number } } = {
	house = { x = -95, z = 95 }, -- back-left: the player's house + storage sheds
	pen = { x = 95, z = 95 }, -- back-right: animal pen (zagroda)
	utility = { x = -95, z = -10 }, -- left: utility / farm buildings (pomieszczenia gospodarcze)
	orchard = { x = 95, z = -10 }, -- right: orchard (sad)
}
function WorldLayout.zoneOffset(name: string): { x: number, z: number }?
	return ZONES[name]
end
function WorldLayout.zoneNames(): { string }
	return { "house", "pen", "utility", "orchard" }
end

return WorldLayout
