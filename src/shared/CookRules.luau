--!strict
-- CookRules: PURE cooking logic (block 9). A recipe consumes ingredient inventory keys, cooks for
-- cookSec, then yields a "dish|<id>". These functions operate on plain tables (the inventory map) so
-- they are fully VPS-testable; the shell owns the timer (kitchen.doneAt) + banking the dish.

local CookRules = {}

-- Does the inventory hold every ingredient in the required quantity?
function CookRules.canCook(inventory: { [string]: number }, recipe: any): boolean
	for key, need in recipe.needs do
		if (inventory[key] or 0) < need then
			return false
		end
	end
	return true
end

-- Remove a recipe's ingredients from inventory. Assumes canCook already passed. Mutates inventory
-- (clears a key that hits 0). Returns true.
function CookRules.consume(inventory: { [string]: number }, recipe: any): boolean
	for key, need in recipe.needs do
		local left = (inventory[key] or 0) - need
		if left > 0 then
			inventory[key] = left
		else
			inventory[key] = nil
		end
	end
	return true
end

-- Is a cook that finishes at `doneAt` ready now?
function CookRules.isDone(doneAt: number?, now: number): boolean
	return doneAt ~= nil and now >= doneAt
end

return CookRules
