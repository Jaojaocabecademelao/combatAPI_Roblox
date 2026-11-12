local PluginVersion = {}

local function normalizePart(part)
	local normalized = string.gsub(part, "^0+", "")
	return normalized == "" and "0" or normalized
end

local function parts(value)
	if type(value) ~= "string" then return nil end
	local major, minor, patch = value:match("^(%d+)%.(%d+)%.(%d+)$")
	if not major then return nil end
	return { normalizePart(major), normalizePart(minor), normalizePart(patch) }
end

function PluginVersion.isValid(value)
	return parts(value) ~= nil
end

function PluginVersion.isAtLeast(actual, minimum)
	if minimum == nil then return PluginVersion.isValid(actual) end
	local actualParts, minimumParts = parts(actual), parts(minimum)
	if not actualParts or not minimumParts then return false end
	for index = 1, 3 do
		local actualPart, minimumPart = actualParts[index], minimumParts[index]
		if #actualPart ~= #minimumPart then return #actualPart > #minimumPart end
		if actualPart ~= minimumPart then return actualPart > minimumPart end
	end
	return true
end

return table.freeze(PluginVersion)
