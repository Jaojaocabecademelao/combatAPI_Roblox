local Component = require(script.Parent.Parent.Core.Component)
local AnimationComponent = setmetatable({}, Component)
AnimationComponent.__index = AnimationComponent
function AnimationComponent.new()
	local self = setmetatable(Component.new(), AnimationComponent)
	self.EntityId, self.CurrentTracks, self.ActiveAnimations, self.PausedAnimations, self.TrackOrder = nil, {}, {}, {}, {}
	self.CurrentFrame = 0
	return self
end
function AnimationComponent:Attach(entity)
	self.Entity = entity
	self.EntityId = entity.Id
	return self
end
function AnimationComponent:Detach()
	self:Reset()
	self.Entity = nil
end
function AnimationComponent:Reset()
	self.CurrentTracks, self.ActiveAnimations, self.PausedAnimations, self.TrackOrder = {}, {}, {}, {}
	self.CurrentFrame = 0
	return self
end
return AnimationComponent
