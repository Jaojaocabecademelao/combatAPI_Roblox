local TimeEffectResult = {}

TimeEffectResult.Applied = "Applied"
TimeEffectResult.Extended = "Extended"
TimeEffectResult.Ignored = "Ignored"
TimeEffectResult.MissingComponent = "MissingComponent"
TimeEffectResult.EntityUnavailable = "EntityUnavailable"
TimeEffectResult.Disabled = "Disabled"
TimeEffectResult.ZeroFrames = "ZeroFrames"

return table.freeze(TimeEffectResult)
