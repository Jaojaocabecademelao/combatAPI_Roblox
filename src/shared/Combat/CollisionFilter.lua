local CollisionFilter = {}

CollisionFilter.DefaultGroup = "Default"

local function isGroupName(value)
	return type(value) == "string" and value ~= ""
end

function CollisionFilter.Normalize(group, mask)
	if group == nil then group = CollisionFilter.DefaultGroup end
	if not isGroupName(group) then
		return nil, nil, "CollisionGroup must be a non-empty string"
	end
	if mask == nil then
		return group, nil
	end
	if type(mask) ~= "table" or getmetatable(mask) ~= nil then
		return nil, nil, "CollisionMask must be a plain array of group names or nil"
	end

	local normalized = {}
	local seen = {}
	local count, maxIndex = 0, 0
	for index, groupName in pairs(mask) do
		if type(index) ~= "number" or index < 1 or index % 1 ~= 0 then
			return nil, nil, "CollisionMask must be a dense array"
		end
		if not isGroupName(groupName) then
			return nil, nil, "CollisionMask entries must be non-empty strings"
		end
		if seen[groupName] then
			return nil, nil, "CollisionMask entries must be unique"
		end
		seen[groupName] = true
		count += 1
		maxIndex = math.max(maxIndex, index)
		table.insert(normalized, groupName)
	end
	if count ~= maxIndex then
		return nil, nil, "CollisionMask must be a dense array"
	end
	table.sort(normalized)
	return group, table.freeze(normalized)
end

function CollisionFilter.CloneMask(mask)
	if mask == nil then return nil end
	local copy = {}
	for index, group in ipairs(mask) do copy[index] = group end
	return copy
end

local function allows(mask, group)
	if mask == nil then return true end
	for _, allowedGroup in ipairs(mask) do
		if allowedGroup == group then return true end
	end
	return false
end

function CollisionFilter.AllowsPair(left, right)
	return allows(left.CollisionMask, right.CollisionGroup)
		and allows(right.CollisionMask, left.CollisionGroup)
end

function CollisionFilter.MasksEqual(left, right)
	if left == nil or right == nil then return left == right end
	if #left ~= #right then return false end
	for index, group in ipairs(left) do
		if group ~= right[index] then return false end
	end
	return true
end

return CollisionFilter
