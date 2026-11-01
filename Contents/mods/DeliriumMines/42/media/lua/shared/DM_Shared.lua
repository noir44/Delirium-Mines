-- Delirium Mines - definitions shared by client and server.
--
-- A mine is a 3x3 rock the admin puts down (no item: players can neither
-- pick it up nor carry it away). Two kinds, a light limestone quarry and a
-- dark ore mine, each with its work face to the south or to the east - the
-- two sides the PZ camera sees. A player with a pickaxe stands at the face
-- and hits it: every hit is one item rolled from the kind's table. Each mine
-- holds a stock of hits that refills a little every game hour, so it is
-- slow but never runs dry for good.
--
-- Tiles: tileset delmines_01, 9 sprites per kind and facing, sprite index =
-- (kind * 2 + facing) * 9 + dy * 3 + dx, where (dx, dy) is the cell inside
-- the rock counted from its north-west cell, the anchor. The code knows a
-- mine by its anchor whichever cell was clicked.

DelMines = DelMines or {}
DelMines.MODULE = "DelMines"
DelMines.STATE_KEY = "DelMines_State"
DelMines.TILESET = "delmines_01_"
DelMines.SIZE = 3

DelMines.KINDS = { "quarry", "mine" }
DelMines.FACINGS = { "S", "E" }

-- Default drop tables, weights; the admin overrides them in the sandbox
-- (QuarryTable, MineTable). Vanilla items only.
DelMines.DEFAULT_TABLES = {
	quarry = "Base.Limestone:40; Base.Stone2:30; Base.Clay:20; Base.LargeStone:10",
	mine = "Base.IronOre:30; Base.CopperOre:10; Base.Stone2:60",
}

-- How far from the face the player may stand when the server checks.
DelMines.REACH = 1.8

-- ---------------------------------------------------------------------------
-- Sandbox: read at the point of use, never at file scope (see E:\mods\CLAUDE.md).
-- ---------------------------------------------------------------------------

local function sandbox()
	return SandboxVars and SandboxVars.DelMines or {}
end

local function int(value, default, min)
	return math.max(min, math.floor(tonumber(value) or default))
end

function DelMines.capacity()
	return int(sandbox().Capacity, 200, 1)
end

function DelMines.regenPerHour()
	return int(sandbox().RegenPerHour, 5, 0)
end

-- Percent of vanilla's time to break a boulder (300 - Strength * 10 ticks).
function DelMines.hitTimePercent()
	return int(sandbox().HitTimePercent, 100, 1)
end

function DelMines.xpPerHit()
	return int(sandbox().XpPerHit, 5, 0)
end

-- "Base.Limestone:40; Base.Stone2:30" -> { { type, weight }, ... }, total.
-- A bad table falls back to the default one, so a typo never stops a mine.
function DelMines.parseTable(text)
	local out, total = {}, 0
	for entry in string.gmatch(tostring(text or ""), "[^;,]+") do
		local fullType, weight = string.match(entry, "^%s*([%w_]+%.[%w_]+)%s*:%s*(%d+)%s*$")
		weight = tonumber(weight)
		if fullType and weight and weight > 0 then
			table.insert(out, { type = fullType, weight = weight })
			total = total + weight
		end
	end
	return out, total
end

function DelMines.dropTable(kind)
	local key = kind == "mine" and "MineTable" or "QuarryTable"
	local list, total = DelMines.parseTable(sandbox()[key])
	if total <= 0 then list, total = DelMines.parseTable(DelMines.DEFAULT_TABLES[kind]) end
	return list, total
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

function DelMines.key(x, y, z)
	return tostring(math.floor(x)) .. "," .. tostring(math.floor(y)) .. "," .. tostring(math.floor(z))
end

function DelMines.spriteName(kind, facing, dx, dy)
	local k = kind == "mine" and 1 or 0
	local f = facing == "E" and 1 or 0
	return DelMines.TILESET .. tostring((k * 2 + f) * 9 + dy * 3 + dx)
end

-- Sprite name -> kind, facing, dx, dy; nil when it is not ours.
function DelMines.parseSprite(name)
	if not name or string.sub(name, 1, #DelMines.TILESET) ~= DelMines.TILESET then return nil end
	local index = tonumber(string.sub(name, #DelMines.TILESET + 1))
	if not index or index < 0 or index >= 36 then return nil end
	local block = math.floor(index / 9)
	local cell = index % 9
	local kind = DelMines.KINDS[math.floor(block / 2) + 1]
	local facing = DelMines.FACINGS[block % 2 + 1]
	return kind, facing, cell % 3, math.floor(cell / 3)
end

-- Our object on this square and what it is:
-- object, { kind, facing, x, y, z (anchor), key }, or nil.
function DelMines.cellAt(square)
	if not square then return nil end
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		local sprite = object:getSprite()
		local kind, facing, dx, dy = DelMines.parseSprite(sprite and sprite:getName())
		if kind then
			local x, y, z = square:getX() - dx, square:getY() - dy, square:getZ()
			return object, { kind = kind, facing = facing, x = x, y = y, z = z, key = DelMines.key(x, y, z) }
		end
	end
	return nil
end

-- The squares in front of the face: south of the bottom row or east of the
-- right column. Returned as { x, y } pairs.
function DelMines.faceTiles(mine)
	local out = {}
	for i = 0, DelMines.SIZE - 1 do
		if mine.facing == "E" then
			table.insert(out, { x = mine.x + DelMines.SIZE, y = mine.y + i })
		else
			table.insert(out, { x = mine.x + i, y = mine.y + DelMines.SIZE })
		end
	end
	return out
end

-- The face cell the player at (px, py) works on: the rock cell next to the
-- nearest face tile.
function DelMines.faceCell(mine, px, py)
	local best, bestDist
	for _, tile in ipairs(DelMines.faceTiles(mine)) do
		local d = math.abs(tile.x + 0.5 - px) + math.abs(tile.y + 0.5 - py)
		if not bestDist or d < bestDist then best, bestDist = tile, d end
	end
	if mine.facing == "E" then return best.x - 1, best.y end
	return best.x, best.y - 1
end

-- Standing in front of the face, within reach of it.
function DelMines.atFace(mine, px, py, pz)
	if math.floor(pz) ~= math.floor(mine.z) then return false end
	local size, reach = DelMines.SIZE, DelMines.REACH
	if mine.facing == "E" then
		return px >= mine.x + size - 0.2 and px <= mine.x + size + reach
			and py >= mine.y - 0.5 and py <= mine.y + size + 0.5
	end
	return py >= mine.y + size - 0.2 and py <= mine.y + size + reach
		and px >= mine.x - 0.5 and px <= mine.x + size + 0.5
end

-- ---------------------------------------------------------------------------
-- Tools: the set vanilla breaks ore boulders with
-- (ISPickAxeGroundCoverItem:predicatePickAxe).
-- ---------------------------------------------------------------------------

function DelMines.isTool(item)
	if not item or item:isBroken() then return false end
	return item:hasTag(ItemTag.PICK_AXE) or item:getType() == "PickAxe" or item:hasTag(ItemTag.SLEDGEHAMMER)
		or item:hasTag(ItemTag.CLUB_HAMMER) or item:hasTag(ItemTag.STONE_MAUL) or item:hasTag(ItemTag.HAMMER)
end

function DelMines.toolInHand(player)
	local item = player:getPrimaryHandItem()
	if DelMines.isTool(item) then return item end
	return nil
end

-- The best tool the player carries, to put in hand before working.
function DelMines.findTool(player)
	local inHand = DelMines.toolInHand(player)
	if inHand then return inHand end
	local items = player:getInventory():getAllEvalRecurse(DelMines.isTool)
	local pick
	for i = 0, items:size() - 1 do
		local item = items:get(i)
		if item:hasTag(ItemTag.PICK_AXE) or item:getType() == "PickAxe" then return item end
		pick = pick or item
	end
	return pick
end

-- ---------------------------------------------------------------------------
-- Admin rights: same test as Delirium Shops, kept here so the mod stands
-- alone.
-- ---------------------------------------------------------------------------

function DelMines.isAdmin(player)
	if not player then return false end
	if player.getAccessLevel and player:getAccessLevel() == "admin" then return true end
	local role = player.getRole and player:getRole()
	if role and role.hasCapability and Capability and Capability.CanSetupNonPVPZone then
		if role:hasCapability(Capability.CanSetupNonPVPZone) then return true end
	end
	if role and role.hasAdminPower and role:hasAdminPower() then return true end
	return false
end

-- mines = { ["x,y,z"] = { kind, facing, left, by } }, the server's ModData
-- (the client holds a read-only copy).
function DelMines.getState()
	local s = ModData.get(DelMines.STATE_KEY)
	if type(s) ~= "table" or type(s.mines) ~= "table" then return nil end
	return s
end

function DelMines.getMine(key)
	local s = DelMines.getState()
	return s and s.mines[key] or nil
end
