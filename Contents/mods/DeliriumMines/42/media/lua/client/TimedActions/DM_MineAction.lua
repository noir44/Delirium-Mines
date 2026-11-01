-- Delirium Mines - one hit at the face of a mine. A client-side timer
-- modelled on vanilla's ISPickAxeGroundCoverItem (animation, sounds, heavy
-- work, muscle strain); perform() asks the server, which checks the face,
-- the tool and the stock again and gives the item.

if isServer() then return end

require "TimedActions/ISBaseTimedAction"
require "DM_Shared"

DM_MineAction = ISBaseTimedAction:derive("DM_MineAction")

function DM_MineAction:faceCell()
	local x, y = DelMines.faceCell(self.mine, self.character:getX(), self.character:getY())
	return x + 0.5, y + 0.5
end

function DM_MineAction:isValid()
	if not DelMines.toolInHand(self.character) then return false end
	local _, mine = DelMines.cellAt(getCell():getGridSquare(self.mine.x, self.mine.y, self.mine.z))
	if not mine or mine.key ~= self.mine.key then return false end
	local record = DelMines.getMine(self.mine.key)
	if record and (record.left or 0) <= 0 then return false end
	return DelMines.atFace(self.mine, self.character:getX(), self.character:getY(), self.character:getZ())
end

function DM_MineAction:waitToStart()
	self.character:faceLocation(self:faceCell())
	return self.character:shouldBeTurning()
end

function DM_MineAction:update()
	self.character:faceLocation(self:faceCell())
	self.character:setMetabolicTarget(Metabolics.HeavyWork)
end

function DM_MineAction:start()
	self.tool = self.character:getPrimaryHandItem()
	if self.character:isSecondaryHandItem(self.tool) then
		self:setActionAnim("DestroyFloor")
	else
		self:setActionAnim("HammerOre")
	end
	addSound(self.character, self.character:getX(), self.character:getY(), self.character:getZ(), 20, 10)
end

function DM_MineAction:animEvent(event, parameter)
	if not self.tool then return end
	if event == "PlaySwingSound" then
		self.character:playSound(self.tool:getSwingSound())
	elseif event == "PlayHitSound" then
		self.character:addCombatMuscleStrain(self.tool)
		self.character:playSound("CraftMineralDepositHit")
	end
end

function DM_MineAction:stop()
	ISBaseTimedAction.stop(self)
end

function DM_MineAction:perform()
	self.character:playSound("CraftMineralDepositRemove")
	DelMines.send("hit", { x = self.mine.x, y = self.mine.y, z = self.mine.z })
	-- needed to remove from queue / start next.
	ISBaseTimedAction.perform(self)
end

function DM_MineAction:getDuration()
	if self.character:isTimedActionInstant() then return 1 end
	local base = 300 - self.character:getPerkLevel(Perks.Strength) * 10
	return math.max(1, math.floor(base * DelMines.hitTimePercent() / 100))
end

function DM_MineAction:new(character, mine)
	local o = ISBaseTimedAction.new(self, character)
	o.mine = mine
	o.caloriesModifier = 8
	o.maxTime = o:getDuration()
	return o
end
