local Definition = {}
Definition.__index = Definition

local priorities = { Idle = true, Movement = true, Action = true, Reaction = true, Override = true }

function Definition.new(options)
	assert(type(options) == "table", "AnimationDefinition.new() expects a table")
	assert(type(options.Id) == "string" and options.Id ~= "", "AnimationDefinition Id is required")
	local duration = options.DurationFrames or options.Length
	assert(type(duration) == "number" and duration > 0 and duration % 1 == 0,
		"AnimationDefinition DurationFrames is invalid")
	assert(options.Priority == nil or priorities[options.Priority] or type(options.Priority) == "number",
		"AnimationDefinition Priority is invalid")
	return setmetatable({
		Id = options.Id, AssetId = options.AssetId, DurationFrames = duration,
		Loop = options.Loop == true, Priority = options.Priority or "Action",
		Speed = options.Speed or 1, Weight = options.Weight or 1,
		Markers = table.clone(options.Markers or {}), Data = table.clone(options.Data or {}),
	}, Definition)
end

return Definition
