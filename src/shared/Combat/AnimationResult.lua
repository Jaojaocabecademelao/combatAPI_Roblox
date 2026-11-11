local Result = {}
Result.__index = Result
Result.Type = table.freeze({
	Success = "Success", InvalidEntity = "InvalidEntity", EntityDead = "EntityDead",
	InvalidCharacter = "InvalidCharacter", NotAttached = "NotAttached",
	InvalidAnimation = "InvalidAnimation", InvalidProfile = "InvalidProfile",
	InvalidAdapter = "InvalidAdapter", InvalidTrack = "InvalidTrack",
	AlreadyPlaying = "AlreadyPlaying", NotPlaying = "NotPlaying",
	AlreadyPaused = "AlreadyPaused", NotPaused = "NotPaused",
	AlreadyStopped = "AlreadyStopped", AdapterRejected = "AdapterRejected",
	PlayFailed = "PlayFailed", PauseFailed = "PauseFailed", ResumeFailed = "ResumeFailed",
	StopFailed = "StopFailed", Completed = "Completed",
})
function Result.new(data) return setmetatable(data, Result) end
return Result
