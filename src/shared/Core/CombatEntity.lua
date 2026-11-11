local EntityState = require(script.Parent.EntityState)

local CombatEntity = {}
CombatEntity.__index = CombatEntity

function CombatEntity.new(id)
	assert(id ~= nil, "CombatEntity.new() requires an ID")

	local self = setmetatable({}, CombatEntity)

	self.Id = id
	self.State = EntityState.Alive

	self.Instance = nil
	self.Components = {}
	self.ComponentOrder = {}

	self.Destroyed = false

	return self
end

function CombatEntity:BindInstance(instance)
	assert(instance == nil or instance:IsA("Model"),
		"CombatEntity:BindInstance() expects a Model or nil"
	)

	self.Instance = instance

	return self
end

function CombatEntity:GetInstance()
	return self.Instance
end

function CombatEntity:AddComponent(component)
	if self.World and self.World:GetExecutionContext() ~= "Normal" then
		self.World:_AssertNormalOperation("AddComponent")
	end
	assert(component, "CombatEntity:AddComponent() requires a component")

	if component.Entity then
		error("Component is already attached to an entity")
	end

	local componentType = getmetatable(component)

	if self.Components[componentType] then
		error("Entity already has this component type")
	end

	self.Components[componentType] = component

	component:Attach(self)
	table.insert(self.ComponentOrder, componentType)

	return component
end

function CombatEntity:GetComponent(componentType)
	return self.Components[componentType]
end

function CombatEntity:RemoveComponent(componentType)
	if self.World and self.World:GetExecutionContext() ~= "Normal" then
		self.World:_AssertNormalOperation("RemoveComponent")
	end
	local component = self.Components[componentType]

	if not component then
		return false
	end

	component:Detach()
	self.Components[componentType] = nil
	for index, existingType in ipairs(self.ComponentOrder) do
		if existingType == componentType then
			table.remove(self.ComponentOrder, index)
			break
		end
	end

	return true
end

local function updateComponents(self, methodName, deltaTime)
	if self.Destroyed then
		return
	end

	local components = {}
	for _, componentType in ipairs(self.ComponentOrder) do
		local component = self.Components[componentType]
		if component then table.insert(components, { componentType, component }) end
	end

	for _, entry in ipairs(components) do
		local componentType = entry[1]
		local component = entry[2]

		if self.Destroyed then
			break
		end

		if self.Components[componentType] == component
			and component.Entity == self
			and component:IsEnabled()
			and type(component[methodName]) == "function"
		then
			component[methodName](component, deltaTime)
		end
	end
end

function CombatEntity:Update(deltaTime)
	updateComponents(self, "Update", deltaTime)
end

function CombatEntity:Step(deltaTime)
	updateComponents(self, "Step", deltaTime)
end

function CombatEntity:SetState(state)
	assert(state ~= nil, "CombatEntity:SetState() requires a state")

	if self.Destroyed then
		error("Cannot change the state of a destroyed entity")
	end

	self.State = state
	for _, componentType in ipairs(self.ComponentOrder) do
		local component = self.Components[componentType]
		if component and component.Entity == self and type(component.OnEntityStateChanged) == "function" then
			component:OnEntityStateChanged(state)
		end
	end

	return self
end

function CombatEntity:GetState()
	return self.State
end

function CombatEntity:IsAlive()
	return self.State == EntityState.Alive
end

function CombatEntity:IsDead()
	return self.State == EntityState.Dead
end

function CombatEntity:Destroy()
	assert(not (self.World and self.World:GetExecutionContext() ~= "Normal"),
		"Entity destruction is not allowed during rollback execution")
	if self.Destroyed then
		return
	end

	for _, componentType in ipairs(self.ComponentOrder) do
		local component = self.Components[componentType]
		if component then
			component:Detach()
			self.Components[componentType] = nil
		end
	end
	table.clear(self.ComponentOrder)

	self.Instance = nil
	self.Destroyed = true
end

return CombatEntity
