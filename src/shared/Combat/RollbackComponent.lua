local Component = require(script.Parent.Parent.Core.Component)
local State = require(script.Parent.RollbackState)

local RollbackComponent = setmetatable({}, Component)
RollbackComponent.__index = RollbackComponent
RollbackComponent.RollbackKey = "Combat.RollbackComponent"

function RollbackComponent.new(profile)
	local self = setmetatable(Component.new(), RollbackComponent)
	self.Profile = profile
	self.CurrentFrame = 0
	self.LastRestoredFrame = nil
	self.LastRollbackFrame = nil
	self.RollbackCount = 0
	self.RollbackState = State.Idle
	self.PendingRollback = nil
	self.EntityId = nil
	self.Resolver = nil
	return self
end

function RollbackComponent:Attach(entity)
	Component.Attach(self, entity)
	self.EntityId = entity.Id
	return self
end

function RollbackComponent:Destroy()
	if self.Resolver then self.Resolver:_onComponentRemoved(self) end
	self.Resolver = nil
	self.EntityId = nil
	self.PendingRollback = nil
end

return RollbackComponent
