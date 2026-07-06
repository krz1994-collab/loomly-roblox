--!strict
-- WorldLayout: PURE geometry + constants for the shared world. No Roblox globals (returns plain
-- {x,z} tables and numbers; World.luau turns them into CFrames/Parts). This is the rare 3D bit that
-- IS VPS-testable -- so the "do sections overlap? are pads inside their section?" questions get
-- answered by unit tests before the world is ever built in Studio.
--
-- Layout: a central HUB at the origin (players spawn here). In front of it, a GRID of numbered farm
-- SECTIONS (one per max player). Each section holds PLOT_COUNT plot pads in a small grid.

local WorldLayout = {}

-- ---- tunable constants (studs) ----
WorldLayout.HUB_RADIUS = 30 -- circular hub platform players spawn on
WorldLayout.SECTION_COLS = 10 -- farm sections per grid row
WorldLayout.SECTION_SPACING = 40 -- centre-to-centre distance between sections
WorldLayout.SECTION_SIZE = 30 -- side length of a section's grass platform (< spacing => gaps between)
WorldLayout.GRID_START_Z = 70 -- first section row sits this far in front of the hub centre
WorldLayout.PLOT_PAD_COLS = 3 -- plot pads per row inside a section
WorldLayout.PLOT_PAD_SPACING = 8 -- centre-to-centre distance between pads
WorldLayout.PAD_SIZE = 5 -- side length of a plot pad

-- Centre of section `i` (1-based) laid out as a grid of SECTION_COLS columns, centred on x=0,
-- marching in +z away from the hub. Returns {x=?, z=?}.
function WorldLayout.sectionCenter(i: number): { x: number, z: number }
	local idx = i - 1
	local col = idx % WorldLayout.SECTION_COLS
	local row = math.floor(idx / WorldLayout.SECTION_COLS)
	local x = (col - (WorldLayout.SECTION_COLS - 1) / 2) * WorldLayout.SECTION_SPACING
	local z = WorldLayout.GRID_START_Z + row * WorldLayout.SECTION_SPACING
	return { x = x, z = z }
end

-- Local offset of plot pad `plotIndex` (1-based) within its section, as a grid of PLOT_PAD_COLS
-- columns centred on the section centre. Returns {x=?, z=?} relative to the section centre.
function WorldLayout.plotPadOffset(plotIndex: number, plotCount: number): { x: number, z: number }
	local idx = plotIndex - 1
	local rows = math.ceil(plotCount / WorldLayout.PLOT_PAD_COLS)
	local col = idx % WorldLayout.PLOT_PAD_COLS
	local row = math.floor(idx / WorldLayout.PLOT_PAD_COLS)
	local x = (col - (WorldLayout.PLOT_PAD_COLS - 1) / 2) * WorldLayout.PLOT_PAD_SPACING
	local z = (row - (rows - 1) / 2) * WorldLayout.PLOT_PAD_SPACING
	return { x = x, z = z }
end

return WorldLayout
