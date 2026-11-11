local NetworkSnapshot = require(script.Parent.NetworkSnapshot)

local Snapshot = {}
Snapshot.__index = Snapshot

local function keyOrder(a, b)
	local aType, bType = type(a), type(b)
	if aType ~= bType then return aType < bType end
	if aType == "number" then return a < b end
	return tostring(a) < tostring(b)
end

local function validFrame(frame)
	return type(frame) == "number" and frame == frame and frame >= 0
		and frame < math.huge and frame % 1 == 0
end

local function validInputData(value, ancestors)
	local valueType = type(value)
	if valueType == "nil" or valueType == "boolean" or valueType == "string" then return true end
	if valueType == "number" then
		return value == value and value > -math.huge and value < math.huge
	end
	if valueType ~= "table" or ancestors[value] then return false end
	ancestors[value] = true
	for key, child in pairs(value) do
		if (type(key) ~= "string"
			and (type(key) ~= "number" or key ~= key or key == math.huge or key == -math.huge))
			or not validInputData(child, ancestors) then
			ancestors[value] = nil
			return false
		end
	end
	ancestors[value] = nil
	return true
end

local function compare(expected, actual, path, entityId, frame, result, visited)
	if type(expected) ~= type(actual) then
		table.insert(result, {
			EntityId = entityId, Frame = frame, Path = path,
			Expected = expected, Actual = actual, Kind = "TypeMismatch",
		})
		return
	end
	if type(expected) ~= "table" then
		if expected ~= actual then
			table.insert(result, {
				EntityId = entityId, Frame = frame, Path = path,
				Expected = expected, Actual = actual, Kind = "ValueMismatch",
			})
		end
		return
	end
	visited[expected] = visited[expected] or {}
	if visited[expected][actual] then return end
	visited[expected][actual] = true

	local keys, seen = {}, {}
	for key in pairs(expected) do table.insert(keys, key); seen[key] = true end
	for key in pairs(actual) do
		if not seen[key] then table.insert(keys, key) end
	end
	table.sort(keys, keyOrder)
	for _, key in ipairs(keys) do
		local childPath = path == "" and tostring(key) or (path .. "." .. tostring(key))
		if expected[key] == nil then
			table.insert(result, {
				EntityId = entityId, Frame = frame, Path = childPath,
				Expected = nil, Actual = actual[key], Kind = "UnexpectedValue",
			})
		elseif actual[key] == nil then
			table.insert(result, {
				EntityId = entityId, Frame = frame, Path = childPath,
				Expected = expected[key], Actual = nil, Kind = "MissingValue",
			})
		else
			compare(expected[key], actual[key], childPath, entityId, frame, result, visited)
		end
	end
end

function Snapshot.new(networkSnapshot)
	assert(type(networkSnapshot) == "table" and getmetatable(networkSnapshot) == NetworkSnapshot,
		"PredictionSnapshot requires a NetworkSnapshot")
	assert(validFrame(networkSnapshot.SimulationFrame)
		and type(networkSnapshot.Entities) == "table"
		and type(networkSnapshot.Components) == "table",
		"PredictionSnapshot network data is invalid")
	return setmetatable({
		NetworkSnapshot = networkSnapshot,
		SimulationFrame = networkSnapshot.SimulationFrame,
	}, Snapshot)
end

function Snapshot:CompareFrame(entityId, predictionFrame)
	assert(type(predictionFrame) == "table"
		and type(predictionFrame.Frame) == "number", "PredictionSnapshot requires a PredictionFrame")

	local entities = self.NetworkSnapshot.Entities
	local components = self.NetworkSnapshot.Components
	if not validInputData(predictionFrame.Inputs, {}) then
		return { {
			EntityId = entityId, Frame = predictionFrame.Frame, Path = "Prediction",
			Expected = "Serializable local prediction frame", Actual = predictionFrame.Inputs,
			Kind = "InvalidLocalPrediction",
		} }
	end
	local entity = entities[entityId]
	local predictionComponents = components.Prediction
	local remote = type(predictionComponents) == "table" and predictionComponents[entityId] or nil
	if remote == nil and type(entity) == "table" then remote = entity.Prediction end

	local divergences = {}
	if remote == nil then
		table.insert(divergences, {
			EntityId = entityId, Frame = predictionFrame.Frame, Path = "Prediction",
			Expected = "PredictionFrame", Actual = nil, Kind = "MissingPrediction",
		})
		return divergences
	end
	if type(remote) ~= "table" or not validFrame(remote.Frame)
		or type(remote.Inputs) ~= "table" or not validInputData(remote.Inputs, {}) then
		table.insert(divergences, {
			EntityId = entityId, Frame = predictionFrame.Frame, Path = "Prediction",
			Expected = "Serializable prediction frame", Actual = remote, Kind = "InvalidPredictionData",
		})
		return divergences
	end

	compare(predictionFrame.Frame, remote.Frame, "Frame", entityId, predictionFrame.Frame, divergences, {})
	compare(predictionFrame.Inputs, remote.Inputs, "Inputs", entityId, predictionFrame.Frame, divergences, {})
	return divergences
end

return Snapshot
