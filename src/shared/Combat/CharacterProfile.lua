local Profile = {}
Profile.__index = Profile

local function clone(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = clone(item) end
	return result
end

function Profile.new(options)
	assert(type(options) == "table", "CharacterProfile.new() expects a table")
	assert(type(options.CharacterId) == "string" and options.CharacterId ~= "", "CharacterId is required")
	return setmetatable({
		CharacterId = options.CharacterId,
		DisplayName = options.DisplayName or options.CharacterId,
		AdapterId = options.AdapterId or options.AdapterType or "Custom",
		RepresentationType = options.RepresentationType or "Custom",
		InputProfileId = options.InputProfileId,
		MovementStateProfileId = options.MovementStateProfileId,
		DefaultConfiguration = clone(options.DefaultConfiguration or {}),
		Data = clone(options.Data or {}),
	}, Profile)
end

function Profile:GetData()
	return clone(self.Data)
end

return Profile
