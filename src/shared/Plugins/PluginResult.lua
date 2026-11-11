local Result = {}
Result.__index = Result
function Result.new(success, code, pluginId, value, details)
	return table.freeze(setmetatable({ Success = success == true, Code = code, PluginId = pluginId,
		Value = value, Details = details }, Result))
end
return Result
