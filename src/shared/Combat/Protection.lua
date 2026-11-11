local Protection = {}
Protection.__index = Protection

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function normalizeCategories(categories)
	if categories == nil then
		return {}
	end
	if type(categories) == "string" then
		return { categories }
	end
	assert(type(categories) == "table", "Protection categories must be a string or table")
	local normalized = {}
	for _, category in ipairs(categories) do
		if category ~= nil and type(category) == "string" and category ~= "" then
			table.insert(normalized, category)
		end
	end
	return normalized
end

function Protection.new(options)
	options = options or {}
	assert(type(options) == "table", "Protection.new() expects an options table")

	local kind = options.Kind or "Invulnerability"
	assert(kind == "Invulnerability" or kind == "Immunity",
		"Protection kind must be Invulnerability or Immunity")

	local categories = normalizeCategories(options.Categories)
	assert(#categories > 0, "Protection requires at least one category")

	local duration = options.DurationFrames
	local permanent = options.Permanent == true
	if permanent then
		duration = nil
	elseif duration ~= nil then
		assert(isFiniteNumber(duration) and duration >= 0 and duration % 1 == 0,
			"Protection DurationFrames must be a non-negative integer")
	end

	local priority = options.Priority or 0
	assert(isFiniteNumber(priority), "Protection Priority must be finite")

	return setmetatable({
		Kind = kind,
		Categories = categories,
		Target = options.Target,
		Source = options.Source,
		Priority = priority,
		Permanent = permanent,
		DurationFrames = duration,
		RemainingFrames = duration,
		StartFrame = options.StartFrame or 0,
		Frame = options.Frame or 0,
		CreatedAt = options.CreatedAt or options.Frame or 0,
		Active = true,
	}, Protection)
end

function Protection:Blocks(category)
	if category == nil then
		return false
	end
	for _, entry in ipairs(self.Categories) do
		if entry == category then
			return true
		end
	end
	return false
end

function Protection:AdvanceFrame()
	if self.Permanent or self.RemainingFrames == nil then
		return self
	end
	self.RemainingFrames = math.max(0, (self.RemainingFrames or 0) - 1)
	if self.RemainingFrames <= 0 then
		self.Active = false
	end
	return self
end

function Protection:IsExpired()
	return self.Permanent == false and self.RemainingFrames ~= nil and self.RemainingFrames <= 0
end

return Protection
