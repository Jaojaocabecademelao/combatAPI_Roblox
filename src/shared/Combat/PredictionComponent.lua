local Component = require(script.Parent.Parent.Core.Component)
local State = require(script.Parent.PredictionState)

local PredictionComponent = setmetatable({}, Component)
PredictionComponent.__index = PredictionComponent

function PredictionComponent.new(profile)
	local self = setmetatable(Component.new(), PredictionComponent)
	self.Profile = profile
	self.PredictionState = nil
	self.EntityId = nil
	self.Resolver = nil
	return self
end

function PredictionComponent:Attach(entity)
	Component.Attach(self, entity)
	self.EntityId = entity.Id
	self.PredictionState = State.new(entity.Id, self.Profile)
	return self
end

function PredictionComponent:Detach()
	Component.Detach(self)
	self.PredictionState = nil
	self.EntityId = nil
end

function PredictionComponent:Destroy()
	if self.Resolver and self.PredictionState then
		self.Resolver:_onComponentRemoved(self)
	end
	if self.PredictionState then self.PredictionState:Reset() end
	self.Resolver = nil
end

return PredictionComponent
