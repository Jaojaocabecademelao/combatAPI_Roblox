local EntityRegistry = {}
EntityRegistry.__index = EntityRegistry

function EntityRegistry.new()
	local self = setmetatable({}, EntityRegistry)

	self.Entities = {}

	return self
end

function EntityRegistry:Register(entity)
	assert(entity, "EntityRegistry:Register() requires an entity")

	if self.Entities[entity.Id] then
		error(("Entity with Id %s is already registered"):format(entity.Id))
	end

	self.Entities[entity.Id] = entity

	return entity
end

function EntityRegistry:Get(id)
	return self.Entities[id]
end

function EntityRegistry:Remove(entityOrId)
	local id

	if type(entityOrId) == "table" then
		id = entityOrId.Id
	else
		id = entityOrId
	end

	local entity = self.Entities[id]

	if not entity then
		return false
	end

	self.Entities[id] = nil

	return true
end

function EntityRegistry:Has(entityOrId)
	local id

	if type(entityOrId) == "table" then
		id = entityOrId.Id
	else
		id = entityOrId
	end

	return self.Entities[id] ~= nil
end

function EntityRegistry:GetAll()
	local entities = {}

	for _, entity in pairs(self.Entities) do
		table.insert(entities, entity)
	end
	table.sort(entities, function(a, b)
		local aType, bType = type(a.Id), type(b.Id)
		if aType ~= bType then return aType < bType end
		if aType == "number" or aType == "string" then return a.Id < b.Id end
		return tostring(a.Id) < tostring(b.Id)
	end)

	return entities
end

function EntityRegistry:Clear()
	table.clear(self.Entities)
end

return EntityRegistry