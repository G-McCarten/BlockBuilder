--!strict
--[[
	SiteConfig: geometry every site shares.

	Cell space: cell (x, y, z) fills [x, x + 1) x [y, y + 1) x [z, z + 1),
	counted in cells from the site's origin, y up. A cell is BLOCK_STUDS studs
	on a side, so a world point is origin * (cellPoint * BLOCK_STUDS).

	A player's position in cell space is their root, which stands one cell
	above their feet. Reach is measured from there to a slot's centre.
]]

return table.freeze({
	-- Studs on a side of one block.
	BLOCK_STUDS = 3,
	-- Cells on a side of a chunk, the unit of drawing and collision.
	CHUNK_CELLS = 8,
	-- Reach before skills, in cells.
	BASE_GRASP_CELLS = 5,
	-- Free cells a character needs to stand, counting the one its feet are in.
	HEADROOM_CELLS = 2,
})
