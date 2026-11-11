local Component = require(script.Parent.Parent.Core.Component)
local ComponentClass = setmetatable({}, Component)
ComponentClass.__index = ComponentClass

function ComponentClass.new(profile)
	return setmetatable({
		Entity = nil, Enabled = true, Profile = profile,
		EntityId = nil, CharacterId = nil, Adapter = nil, Representation = nil,
		Attached = false, Lifecycle = "Unattached",
		AttachedFrame = nil, DetachedFrame = nil,
	}, ComponentClass)
end

function ComponentClass:Attach(entity)
	assert(entity, "CharacterComponent:Attach() requires an entity")
	self.Entity = entity
	self.EntityId = entity.Id
	return self
end

function ComponentClass:Detach()
	self.Entity = nil
	self.EntityId = nil
	self:Reset()
end

function ComponentClass:Reset()
	self.CharacterId, self.Adapter, self.Representation = nil, nil, nil
	self.Attached, self.Lifecycle = false, "Unattached"
	self.AttachedFrame, self.DetachedFrame = nil, nil
	return self
end

return ComponentClass
