local Input = require(script.Parent.Input)
local InputBinding = require(script.Parent.InputBinding)
local valid = {}
for _, value in pairs(Input) do valid[value] = true end
local Profile = {}
Profile.__index = Profile
function Profile.new(options)
	options = options or {}
	assert(type(options) == "table", "InputProfile.new() expects a table")
	local size = options.BufferSize or 60
	local timeout = options.InputTimeoutFrames or 10
	assert(type(size) == "number" and size >= 1 and size % 1 == 0, "InputProfile BufferSize is invalid")
	assert(type(timeout) == "number" and timeout >= 0 and timeout % 1 == 0, "InputProfile timeout is invalid")
	local self = setmetatable({ BufferSize = size, InputTimeoutFrames = timeout, Bindings = {} }, Profile)
	for _, binding in ipairs(options.Bindings or {}) do
		if getmetatable(binding) ~= InputBinding then binding = InputBinding.new(binding.ExternalId, binding.CombatInput) end
		self:Bind(binding.ExternalId, binding.CombatInput)
	end
	return self
end
function Profile:Bind(externalId, combatInput)
	assert(type(externalId) == "string" and externalId ~= "" and valid[combatInput],
		"Invalid input binding")
	self.Bindings[externalId] = combatInput
	return self
end
function Profile:Unbind(externalId) self.Bindings[externalId] = nil; return self end
function Profile:GetBinding(externalId) return self.Bindings[externalId] end
function Profile:IsValidInput(inputId) return valid[inputId] == true end
return Profile
