local Track = {}
Track.__index = Track
Track.State = table.freeze({ Stopped = "Stopped", Playing = "Playing", Paused = "Paused", Completed = "Completed" })
function Track.new(data)
	return setmetatable({
		TrackId = data.TrackId, EntityId = data.EntityId, AnimationId = data.AnimationId,
		Definition = data.Definition, State = Track.State.Playing, StartFrame = data.StartFrame,
		CurrentFrame = data.StartFrame, ElapsedFrames = 0, Speed = data.Speed,
		Weight = data.Weight, Priority = data.Priority, Adapter = data.Adapter,
	}, Track)
end
function Track:Advance(frame)
	if self.State ~= Track.State.Playing then return end
	self.CurrentFrame = frame
	self.ElapsedFrames = math.max(0, frame - self.StartFrame)
end
function Track:IsPlaying() return self.State == Track.State.Playing end
function Track:IsPaused() return self.State == Track.State.Paused end
function Track:IsStopped() return self.State == Track.State.Stopped end
return Track
