local Definition = require(script.Parent.AnimationDefinition)
local Profile = {}
Profile.__index = Profile

function Profile.new(options)
	options = options or {}
	assert(type(options) == "table", "AnimationProfile.new() expects a table")
	local self = setmetatable({ Id = options.Id or "Default", Definitions = {}, Defaults = table.clone(options.Defaults or {}) }, Profile)
	for _, definition in ipairs(options.Definitions or {}) do self:Register(definition) end
	return self
end
function Profile:Register(definition)
	assert(getmetatable(definition) == Definition, "AnimationProfile requires AnimationDefinition")
	self.Definitions[definition.Id] = definition
	return self
end
function Profile:Get(id) return self.Definitions[id] end
function Profile:Remove(id) self.Definitions[id] = nil; return self end
return Profile
