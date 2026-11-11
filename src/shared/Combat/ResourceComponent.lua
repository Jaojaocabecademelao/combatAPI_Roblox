local Component = require(script.Parent.Parent.Core.Component)

local ResourceComponent = setmetatable({}, Component)
ResourceComponent.__index = ResourceComponent
ResourceComponent.RollbackKey = "Combat.ResourceComponent"

local function finite(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function validateName(name)
	assert(type(name) == "string" and name ~= "", "Resource name must be a non-empty string")
end

local function validateAmount(value, label)
	assert(finite(value) and value >= 0, label .. " must be a finite non-negative number")
end

local function normalizeDefinition(name, definition)
	validateName(name)
	if type(definition) == "number" then
		validateAmount(definition, "Resource " .. name .. " maximum")
		assert(definition > 0, "Resource " .. name .. " maximum must be positive")
		return { Max = definition, Current = definition }
	end
	assert(type(definition) == "table", "Resource " .. name .. " must be a number or definition table")
	local max = definition.Max
	local current = definition.Current
	validateAmount(max, "Resource " .. name .. " maximum")
	assert(max > 0, "Resource " .. name .. " maximum must be positive")
	if current == nil then current = max end
	validateAmount(current, "Resource " .. name .. " current value")
	assert(current <= max, "Resource " .. name .. " current value cannot exceed maximum")
	return { Max = max, Current = current }
end

function ResourceComponent.new(options)
	options = options or {}
	assert(type(options) == "table", "ResourceComponent.new() expects an options table or nil")
	local self = setmetatable(Component.new(), ResourceComponent)
	self.Resources = {}
	for name, definition in pairs(options.Resources or {}) do
		local normalized = normalizeDefinition(name, definition)
		self.Resources[name] = normalized
	end
	return self
end

function ResourceComponent:Get(name)
	validateName(name)
	local resource = self.Resources[name]
	return resource and resource.Current or nil
end

function ResourceComponent:GetMax(name)
	validateName(name)
	local resource = self.Resources[name]
	return resource and resource.Max or nil
end

function ResourceComponent:Set(name, value)
	validateName(name)
	validateAmount(value, "Resource value")
	local resource = self.Resources[name]
	if not resource then return false, "UnknownResource" end
	if value > resource.Max then return false, "ExceedsMaximum" end
	resource.Current = value
	return value
end

function ResourceComponent:Consume(name, amount)
	validateName(name)
	validateAmount(amount, "Resource amount")
	local resource = self.Resources[name]
	if not resource then return false, "UnknownResource" end
	if amount > resource.Current then return false, "InsufficientResource" end
	resource.Current -= amount
	return resource.Current
end

function ResourceComponent:Restore(name, amount)
	validateName(name)
	validateAmount(amount, "Resource amount")
	local resource = self.Resources[name]
	if not resource then return false, "UnknownResource" end
	resource.Current = math.min(resource.Max, resource.Current + amount)
	return resource.Current
end

function ResourceComponent:GetResources()
	local result = {}
	for name, resource in pairs(self.Resources) do
		result[name] = { Max = resource.Max, Current = resource.Current }
	end
	return result
end

function ResourceComponent:CaptureRollbackState()
	local resources = {}
	local names = {}
	for name in pairs(self.Resources) do table.insert(names, name) end
	table.sort(names)
	for _, name in ipairs(names) do
		local resource = self.Resources[name]
		table.insert(resources, { Name = name, Max = resource.Max, Current = resource.Current })
	end
	return { Version = 1, Resources = resources }
end

function ResourceComponent:ValidateRollbackState(state)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1 then
		return false, "Invalid ResourceComponent state version"
	end
	if type(state.Resources) ~= "table" then return false, "Resources must be an array" end
	local previousName
	for index, resource in ipairs(state.Resources) do
		if type(resource) ~= "table" or getmetatable(resource) ~= nil then
			return false, "Invalid resource entry at index " .. tostring(index)
		end
		if type(resource.Name) ~= "string" or resource.Name == ""
			or (previousName ~= nil and resource.Name <= previousName)
		then
			return false, "Resource names must be unique and sorted"
		end
		if not finite(resource.Max) or resource.Max <= 0
			or not finite(resource.Current) or resource.Current < 0
			or resource.Current > resource.Max
		then
			return false, "Resource values are outside valid bounds"
		end
		previousName = resource.Name
	end
	for key in pairs(state) do
		if key ~= "Version" and key ~= "Resources" then
			return false, "Unknown ResourceComponent state field: " .. tostring(key)
		end
	end
	return true
end

function ResourceComponent:RestoreRollbackState(state)
	local valid, reason = self:ValidateRollbackState(state)
	if not valid then return false, reason end
	local resources = {}
	for _, saved in ipairs(state.Resources) do
		local current = self.Resources[saved.Name]
		if not current or current.Max ~= saved.Max then
			return false, "Resource configuration mismatch: " .. saved.Name
		end
		resources[saved.Name] = { Max = saved.Max, Current = saved.Current }
	end
	for name in pairs(self.Resources) do
		if not resources[name] then return false, "Snapshot is missing resource: " .. name end
	end
	self.Resources = resources
	return true
end

return ResourceComponent
