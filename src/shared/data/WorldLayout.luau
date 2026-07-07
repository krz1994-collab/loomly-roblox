--!strict
-- WorldLayout: PURE geometry + constants for the shared world (no Roblox globals; returns plain
-- {x,z} tables). World.luau turns these into CFrames/Parts. This is the rare 3D bit that IS
-- VPS-testable -- unit tests prove the 100 big plots never overlap and everything sits inside its plot.
--
-- Layout: a central PLAZA (shops + spawn) at the front; behind it a spread grid of 100 personal
-- FARM PLOTS, each 300x300 studs (mega room to expand: crop field + house + pen + utility + orchard).
-- 60-stud roads run in the gaps. The map is huge (~3600 wide) so World enables StreamingEnabled.

local WorldLayout = {}

-- ---- plot grid (studs) ----
WorldLayout.SECTION_SIZE = 300 -- each personal plot is 300 x 300
WorldLayout.SECTION_SPACING = 360 -- centre-to-centre (=> 60-stud roads between plots)
WorldLayout.SECTION_COLS = 10 -- 10 x 10 = 100 plots
WorldLayout.GRID_START_Z = 500 -- first plot row sits this far behind the plaza (plaza fills z<~300)

-- ---- crop field inside a plot ----
WorldLayout.PAD_SIZE = 14 -- a plantable pad is 14 x 14
WorldLayout.PAD_COLS = 4 -- pads per row in the crop field
WorldLayout.PAD_SPACING = 22 -- centre-to-centre between pads
WorldLayout.CROP_FIELD = { x = 0, z = -80 } -- crop field centre, local to the plot (toward the entrance)

-- ---- plaza ----
WorldLayout.PLAZA_RADIUS = 90 -- central hub platform radius (spawn + main shops)
WorldLayout.PLAZA_Z = 120 -- plaza centre z (in front of the plot grid)

-- World position of plot `i` (1-based), laid out as a SECTION_COLS-wide grid centred on x=0.
function WorldLayout.sectionCenter(i: number): { x: number, z: number }
	local idx = i - 1
	local col = idx % WorldLayout.SECTION_COLS
	local row = math.floor(idx / WorldLayout.SECTION_COLS)
	local x = (col - (WorldLayout.SECTION_COLS - 1) / 2) * WorldLayout.SECTION_SPACING
	local z = WorldLayout.GRID_START_Z + row * WorldLayout.SECTION_SPACING
	return { x = x, z = z }
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
