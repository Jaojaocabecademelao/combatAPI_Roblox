local Component = {}
Component.__index = Component

function Component.new()
	local self = setmetatable({}, Component)

	self.Entity = nil
	self.Enabled = true

	return self
end

function Component:Attach(entity)
	assert(entity, "Component:Attach() requires an entity")

	if self.Entity then
		error("Component is already attached to an entity")
	end

	self.Entity = entity

	if self.Init then
		self:Init()
	end

	return self
end

function Component:Detach()
	if not self.Entity then
		return
	end

	if self.Destroy then
		self:Destroy()
	end

	self.Entity = nil
end

function Component:SetEnabled(enabled)
	self.Enabled = enabled == true
end

function Component:IsEnabled()
	return self.Enabled
end

return Component