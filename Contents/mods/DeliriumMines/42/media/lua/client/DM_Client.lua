-- Delirium Mines - client: the read-only copy of the mines, the server's
-- replies and the context menu (work the face; admin: put down, remove,
-- refill).

if isServer() then return end

require "ISUI/ISToolTip"
require "DM_Shared"
require "TimedActions/DM_MineAction"

local MODULE = DelMines.MODULE

function DelMines.send(command, args)
	local player = getPlayer()
	if not player then return end
	sendClientCommand(player, MODULE, command, args or {})
end

-- ---------------------------------------------------------------------------
-- State: read-only copy of the server's ModData. A connect-time request can
-- be lost (see E:\mods\CLAUDE.md), so it is asked again until it arrives.
-- ---------------------------------------------------------------------------

local received = false

local function request()
	if not isClient() or received then return end
	ModData.request(DelMines.STATE_KEY)
end

local function retry()
	if received then
		Events.EveryOneMinute.Remove(retry)
		return
	end
	request()
end

Events.OnGameStart.Add(request)
Events.OnCreatePlayer.Add(function() request() end)
Events.EveryOneMinute.Add(retry)

local function onReceiveGlobalModData(key, data)
	if key ~= DelMines.STATE_KEY or type(data) ~= "table" then return end
	ModData.remove(key)
	ModData.add(key, data)
	received = true
end
Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)

-- ---------------------------------------------------------------------------
-- Server replies
-- ---------------------------------------------------------------------------

local Replies = {}

function Replies.notify(args)
	local player = getPlayer()
	if not player or type(args.key) ~= "string" then return end
	local text
	if args.arg1 ~= nil then
		text = getText(args.key, tostring(args.arg1))
	else
		text = getText(args.key)
	end
	player:setHaloNote(text, 255, 255, 255, 300)
end

-- { key, left }: the stock after this player's hit.
function Replies.left(args)
	local record = DelMines.getMine(args.key or "")
	if record and tonumber(args.left) then record.left = tonumber(args.left) end
end

local function onServerCommand(module, command, args)
	if module ~= MODULE then return end
	local handler = Replies[command]
	if handler then handler(args or {}) end
end
Events.OnServerCommand.Add(onServerCommand)

-- ---------------------------------------------------------------------------
-- Working the face
-- ---------------------------------------------------------------------------

-- Stock left, or nil while the state has not arrived (a mine without a
-- record is adopted full by the server).
local function stockOf(mine)
	if not DelMines.getState() then return nil end
	local record = DelMines.getMine(mine.key)
	if not record then return DelMines.capacity() end
	return record.left or 0
end

-- Free tile in front of the face nearest to the player.
local function faceSquare(player, mine)
	local best, bestDist
	for _, tile in ipairs(DelMines.faceTiles(mine)) do
		local square = getCell():getGridSquare(tile.x, tile.y, mine.z)
		if square and square:isFree(false) then
			local d = math.abs(tile.x + 0.5 - player:getX()) + math.abs(tile.y + 0.5 - player:getY())
			if not bestDist or d < bestDist then best, bestDist = square, d end
		end
	end
	return best
end

local function work(player, mine, times)
	local tool = DelMines.findTool(player)
	if not tool then return end
	if not DelMines.atFace(mine, player:getX(), player:getY(), player:getZ()) then
		local square = faceSquare(player, mine)
		if not square then
			player:setHaloNote(getText("IGUI_DelMines_FaceBlocked"), 255, 120, 120, 300)
			return
		end
		ISTimedActionQueue.add(ISWalkToTimedAction:new(player, square))
	end
	ISWorldObjectContextMenu.equip(player, player:getPrimaryHandItem(), tool, true, tool:isTwoHandWeapon())
	for _ = 1, times do
		ISTimedActionQueue.add(DM_MineAction:new(player, mine))
	end
end

local function tooltip(mine, stock, tool)
	local lines = {}
	if stock then
		table.insert(lines, getText("IGUI_DelMines_Stock", tostring(stock), tostring(DelMines.capacity())))
	end
	local regen = DelMines.regenPerHour()
	if regen > 0 then table.insert(lines, getText("IGUI_DelMines_Regen", tostring(regen))) end
	table.insert(lines, " <LINE> " .. getText("IGUI_DelMines_Yields"))
	local list, total = DelMines.dropTable(mine.kind)
	for _, entry in ipairs(list) do
		local name = getItemNameFromFullType(entry.type) or entry.type
		table.insert(lines, string.format(" %s %d%%", name, math.floor(entry.weight * 100 / total + 0.5)))
	end
	if not tool then table.insert(lines, " <LINE> <RGB:1,0.4,0.4> " .. getText("IGUI_DelMines_NeedTool")) end
	if stock and stock <= 0 then table.insert(lines, " <LINE> <RGB:1,0.4,0.4> " .. getText("IGUI_DelMines_Exhausted")) end
	local tip = ISToolTip:new()
	tip:initialise()
	tip:setVisible(false)
	tip.description = table.concat(lines, " <LINE> ")
	return tip
end

-- ---------------------------------------------------------------------------
-- Context menu
-- ---------------------------------------------------------------------------

local BATCH = 10

local function adminMenu(context, square, mine)
	local parent = context:addOption(getText("IGUI_DelMines_Admin"))
	local sub = ISContextMenu:getNew(context)
	context:addSubMenu(parent, sub)
	local args = { x = square:getX(), y = square:getY(), z = square:getZ() }
	if mine then
		sub:addOption(getText("IGUI_DelMines_Refill"), MODULE, function() DelMines.send("refill", args) end)
		sub:addOption(getText("IGUI_DelMines_Remove"), MODULE, function() DelMines.send("remove", args) end)
		return
	end
	for _, kind in ipairs(DelMines.KINDS) do
		for _, facing in ipairs(DelMines.FACINGS) do
			local name = getText("IGUI_DelMines_Place", getText("IGUI_DelMines_Kind_" .. kind),
				getText("IGUI_DelMines_Facing_" .. facing))
			sub:addOption(name, MODULE, function()
				DelMines.send("place", { x = args.x, y = args.y, z = args.z, kind = kind, facing = facing })
			end)
		end
	end
end

local function onFill(playerNum, context, worldobjects, test)
	if test then return end
	local player = getSpecificPlayer(playerNum)
	local object = worldobjects and worldobjects[1]
	local square = object and object:getSquare()
	if not player or not square then return end
	local _, mine = DelMines.cellAt(square)

	if mine then
		local stock = stockOf(mine)
		local tool = DelMines.findTool(player)
		local name = getText("IGUI_DelMines_Kind_" .. mine.kind)
		local parent = context:addOption(name)
		local sub = ISContextMenu:getNew(context)
		context:addSubMenu(parent, sub)
		local can = tool ~= nil and (stock == nil or stock > 0)
		local one = sub:addOption(getText("IGUI_DelMines_Work"), player, work, mine, 1)
		one.toolTip = tooltip(mine, stock, tool)
		one.notAvailable = not can
		local many = sub:addOption(getText("IGUI_DelMines_WorkMany", tostring(BATCH)), player, work, mine, BATCH)
		many.toolTip = tooltip(mine, stock, tool)
		many.notAvailable = not can
	end

	if DelMines.isAdmin(player) then adminMenu(context, square, mine) end
end
Events.OnFillWorldObjectContextMenu.Add(onFill)
