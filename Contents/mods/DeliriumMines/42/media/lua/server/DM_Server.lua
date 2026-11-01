-- Delirium Mines - the server side: puts down and removes mines, checks and
-- pays out each hit, refills the stock every game hour.
--
-- State: ModData "DelMines_State", small (one entry per mine), sent whole
-- to every client. It rolls back with the world save; a stock rolled back
-- is no loss, so no file of our own.
--
-- media/lua/server/ is also executed by connected clients, hence the guard
-- (see E:\mods\CLAUDE.md).
if isClient() then return end

require "DM_Shared"

local MODULE = DelMines.MODULE

local Commands = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function log(msg)
	print("DelMines: " .. msg)
	writeLog("DelMines", msg)
end

local function state()
	local s = ModData.getOrCreate(DelMines.STATE_KEY)
	if type(s.mines) ~= "table" then s.mines = {} end
	return s
end

local function transmit()
	ModData.transmit(DelMines.STATE_KEY)
end

local function reply(player, command, args)
	sendServerCommand(player, MODULE, command, args or {})
end

-- The client renders the text in its own language.
local function notify(player, key, arg1)
	reply(player, "notify", { key = key, arg1 = arg1 })
end

local function coords(args)
	local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z)
	if not x or not y or not z then return nil end
	return math.floor(x), math.floor(y), math.floor(z)
end

local function kindOf(value)
	for _, kind in ipairs(DelMines.KINDS) do
		if kind == value then return kind end
	end
	return nil
end

local function facingOf(value)
	for _, facing in ipairs(DelMines.FACINGS) do
		if facing == value then return facing end
	end
	return nil
end

-- Our objects of the mine anchored at x, y, z, by square.
local function cellsOf(x, y, z)
	local out = {}
	for dy = 0, DelMines.SIZE - 1 do
		for dx = 0, DelMines.SIZE - 1 do
			local square = getCell():getGridSquare(x + dx, y + dy, z)
			local object, mine = DelMines.cellAt(square)
			if object and mine.x == x and mine.y == y then table.insert(out, object) end
		end
	end
	return out
end

-- nil when the square takes a rock cell, otherwise a translation key.
local function blocked(square)
	if not square then return "IGUI_DelMines_NotLoaded" end
	if DelMines.cellAt(square) then return "IGUI_DelMines_Occupied" end
	if not square:getFloor() then return "IGUI_DelMines_NoFloor" end
	if square:isSolid() or square:isSolidTrans() or square:has(IsoFlagType.collideN)
		or square:has(IsoFlagType.collideW) or square:getVehicleContainer() then
		return "IGUI_DelMines_Occupied"
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Commands: admin
-- ---------------------------------------------------------------------------

-- { x, y, z (centre), kind, facing }
function Commands.place(player, args)
	if not DelMines.isAdmin(player) then return end
	local cx, cy, z = coords(args)
	local kind, facing = kindOf(args.kind), facingOf(args.facing)
	if not cx or not kind or not facing then return end
	local x, y = cx - 1, cy - 1
	for dy = 0, DelMines.SIZE - 1 do
		for dx = 0, DelMines.SIZE - 1 do
			local why = blocked(getCell():getGridSquare(x + dx, y + dy, z))
			if why then return notify(player, why) end
		end
	end
	for dy = 0, DelMines.SIZE - 1 do
		for dx = 0, DelMines.SIZE - 1 do
			local square = getCell():getGridSquare(x + dx, y + dy, z)
			local object = IsoObject.new(getCell(), square, DelMines.spriteName(kind, facing, dx, dy))
			square:AddTileObject(object)
			object:transmitCompleteItemToClients()
			square:RecalcProperties()
		end
	end
	local key = DelMines.key(x, y, z)
	state().mines[key] = { kind = kind, facing = facing, left = DelMines.capacity(), by = player:getUsername() }
	transmit()
	notify(player, "IGUI_DelMines_Placed")
	log(string.format("Placed: %s %s %s at %s", player:getUsername(), kind, facing, key))
end

-- { x, y, z (any cell) }
function Commands.remove(player, args)
	if not DelMines.isAdmin(player) then return end
	local x, y, z = coords(args)
	if not x then return end
	local _, mine = DelMines.cellAt(getCell():getGridSquare(x, y, z))
	if not mine then return end
	for _, object in ipairs(cellsOf(mine.x, mine.y, mine.z)) do
		local square = object:getSquare()
		square:transmitRemoveItemFromSquare(object)
		square:RecalcProperties()
	end
	state().mines[mine.key] = nil
	transmit()
	notify(player, "IGUI_DelMines_Removed")
	log(string.format("Removed: %s %s at %s", player:getUsername(), mine.kind, mine.key))
end

-- { x, y, z (any cell) }: stock back to full.
function Commands.refill(player, args)
	if not DelMines.isAdmin(player) then return end
	local x, y, z = coords(args)
	if not x then return end
	local _, mine = DelMines.cellAt(getCell():getGridSquare(x, y, z))
	if not mine then return end
	local s = state()
	local record = s.mines[mine.key]
	if not record then
		-- Rock without a record (placed before a world rollback): adopt it.
		record = { kind = mine.kind, facing = mine.facing, by = player:getUsername() }
		s.mines[mine.key] = record
	end
	record.left = DelMines.capacity()
	transmit()
	notify(player, "IGUI_DelMines_Refilled", tostring(record.left))
	log(string.format("Refilled: %s %s", player:getUsername(), mine.key))
end

-- ---------------------------------------------------------------------------
-- Commands: anyone
-- ---------------------------------------------------------------------------

local function roll(kind)
	local list, total = DelMines.dropTable(kind)
	local r = ZombRand(total)
	for _, entry in ipairs(list) do
		if r < entry.weight then return entry.type end
		r = r - entry.weight
	end
	return list[#list] and list[#list].type
end

-- { x, y, z (any cell) }: one hit at the face.
function Commands.hit(player, args)
	local x, y, z = coords(args)
	if not x then return end
	local _, mine = DelMines.cellAt(getCell():getGridSquare(x, y, z))
	if not mine then return end
	if not DelMines.atFace(mine, player:getX(), player:getY(), player:getZ()) then
		return notify(player, "IGUI_DelMines_TooFar")
	end
	local tool = DelMines.toolInHand(player)
	if not tool then return notify(player, "IGUI_DelMines_NeedTool") end
	local s = state()
	local record = s.mines[mine.key]
	if not record then
		-- Rock without a record (placed before a world rollback): adopt it full.
		record = { kind = mine.kind, facing = mine.facing, left = DelMines.capacity(), by = "?" }
		s.mines[mine.key] = record
	end
	if (record.left or 0) <= 0 then return notify(player, "IGUI_DelMines_Exhausted") end
	local fullType = roll(mine.kind)
	local item = fullType and instanceItem(fullType)
	if not item then
		log("Bad item in the drop table: " .. tostring(fullType))
		return
	end
	record.left = record.left - 1
	local inventory = player:getInventory()
	inventory:AddItem(item)
	sendAddItemToContainer(inventory, item)
	local xp = DelMines.xpPerHit()
	if xp > 0 then addXp(player, Perks.Masonry, xp) end
	-- Vanilla means to wear the pickaxe here but writes to a misspelt field
	-- (self.pickaxe), so its pickaxes never wear; ours do.
	if not player:isBuildCheat() then tool:damageCheck(0, 2, false) end
	addSound(player, player:getX(), player:getY(), player:getZ(), 20, 10)
	reply(player, "left", { key = mine.key, left = record.left })
end

-- ---------------------------------------------------------------------------

local function regen()
	local add = DelMines.regenPerHour()
	if add <= 0 then return end
	local cap = DelMines.capacity()
	local changed = false
	for _, record in pairs(state().mines) do
		local left = record.left or 0
		if left < cap then
			record.left = math.min(cap, left + add)
			changed = true
		end
	end
	if changed then transmit() end
end

local function onInitGlobalModData()
	state()
end
Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.EveryHours.Add(regen)

local function onClientCommand(module, command, player, args)
	if module ~= MODULE then return end
	local handler = Commands[command]
	if not handler then return end
	handler(player, args or {})
end
Events.OnClientCommand.Add(onClientCommand)
