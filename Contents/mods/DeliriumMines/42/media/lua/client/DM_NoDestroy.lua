-- Delirium Mines - vanilla's sledgehammer destroys any object that is not
-- on its short list of exceptions (ISDestroyCursor:canDestroy), a mine's
-- rock included. Only an admin removes a mine, from its context menu.

if isServer() then return end

require "BuildingObjects/ISDestroyCursor"
require "DM_Shared"

local canDestroy = ISDestroyCursor.canDestroy

function ISDestroyCursor:canDestroy(object)
	local sprite = object and object.getSprite and object:getSprite()
	if sprite and DelMines.parseSprite(sprite:getName()) then return false end
	return canDestroy(self, object)
end
