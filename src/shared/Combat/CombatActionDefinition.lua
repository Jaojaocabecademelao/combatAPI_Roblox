local Definition = {}
Definition.__index = Definition
Definition.Version = 2
local MovementState = require(script.Parent.MovementState)

Definition.DurationModel = table.freeze({
	Phased = "Phased",
	Instant = "Instant",
	Persistent = "Persistent",
})

local validMovementStates = {}
for _, state in pairs(MovementState) do validMovementStates[state] = true end

local function nonNegativeInteger(value, name)
	assert(type(value) == "number" and value == value and value >= 0
		and value < math.huge and value % 1 == 0, name .. " must be a non-negative integer")
end

local function normalizeResources(values, label)
	assert(values == nil or type(values) == "table", label .. " must be a table or nil")
	local result = {}
	for name, amount in pairs(values or {}) do
		assert(type(name) == "string" and name ~= "", label .. " names must be non-empty strings")
		assert(type(amount) == "number" and amount == amount and amount >= 0
			and amount < math.huge, label .. " values must be finite non-negative numbers")
		result[name] = amount
	end
	return table.freeze(result)
end

local function normalizeStringList(values, label, allowedValues)
	assert(values == nil or type(values) == "table", label .. " must be a table or nil")
	local result, seen = {}, {}
	local count, maxIndex = 0, 0
	for key in pairs(values or {}) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
			error(label .. " must be a dense array")
		end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	assert(count == maxIndex, label .. " must be a dense array")
	for index, value in ipairs(values or {}) do
		assert(type(value) == "string" and value ~= "", label .. " entries must be non-empty strings")
		assert(not seen[value], label .. " entries must not contain duplicates")
		if allowedValues then assert(allowedValues[value], "Unknown " .. label .. " entry: " .. value) end
		seen[value] = true
		result[index] = value
	end
	return table.freeze(result), seen
end

function Definition.new(options)
	options = options or {}
	assert(type(options) == "table", "CombatActionDefinition.new expects a table")
	assert((type(options.Id) == "string" and options.Id ~= "")
		or (type(options.Id) == "number" and options.Id == options.Id
			and options.Id > -math.huge and options.Id < math.huge and options.Id % 1 == 0),
		"CombatActionDefinition requires a stable Id")
	local startup = options.StartupFrames
	if startup == nil then startup = 0 end
	local active = options.ActiveFrames
	if active == nil then active = 1 end
	local recovery = options.RecoveryFrames
	if recovery == nil then recovery = 0 end
	local durationModel = options.DurationModel
	if durationModel == nil then durationModel = Definition.DurationModel.Phased end
	assert(durationModel == Definition.DurationModel.Phased
		or durationModel == Definition.DurationModel.Instant
		or durationModel == Definition.DurationModel.Persistent,
		"DurationModel must be Phased, Instant, or Persistent")
	nonNegativeInteger(startup, "StartupFrames")
	assert(type(active) == "number" and active >= 1 and active < math.huge and active % 1 == 0,
		"ActiveFrames must be a positive integer")
	nonNegativeInteger(recovery, "RecoveryFrames")
	local tags = {}
	for index, tag in ipairs(options.Tags or {}) do
		assert(type(tag) == "string" and tag ~= "", "Action tags must be non-empty strings")
		tags[index] = tag
	end
	local requirements = options.Requirements
	if requirements == nil then requirements = {} end
	assert(type(requirements) == "table", "Action Requirements must be a table or nil")
	local requiredStatusTags, requiredStatusTagSet =
		normalizeStringList(requirements.RequiredStatusTags, "RequiredStatusTags")
	local forbiddenStatusTags, forbiddenStatusTagSet =
		normalizeStringList(requirements.ForbiddenStatusTags, "ForbiddenStatusTags")
	for tag in pairs(requiredStatusTagSet) do
		assert(not forbiddenStatusTagSet[tag], "A status tag cannot be both required and forbidden: " .. tag)
	end
	local movementStates = normalizeStringList(requirements.MovementStates,
		"MovementStates", validMovementStates)
	return table.freeze(setmetatable({
		Version = Definition.Version,
		Id = options.Id,
		StartupFrames = startup,
		ActiveFrames = active,
		RecoveryFrames = recovery,
		DurationModel = durationModel,
		Cancelable = options.Cancelable == true,
		Tags = table.freeze(tags),
		Requirements = table.freeze({
			Resources = normalizeResources(requirements.Resources, "Action requirements"),
			RequiredStatusTags = requiredStatusTags,
			ForbiddenStatusTags = forbiddenStatusTags,
			MovementStates = movementStates,
		}),
		Costs = table.freeze({
			Resources = normalizeResources(options.Costs and options.Costs.Resources, "Action costs"),
		}),
	}, Definition))
end

function Definition:GetTotalFrames()
	if self.DurationModel == Definition.DurationModel.Persistent then
		return nil
	end
	if self.DurationModel == Definition.DurationModel.Instant then
		return 1
	end
	return self.StartupFrames + self.ActiveFrames + self.RecoveryFrames
end

return Definition
