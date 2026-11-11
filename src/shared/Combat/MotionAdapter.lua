local MotionAdapter = {}
MotionAdapter.__index = MotionAdapter

function MotionAdapter.new(adapter)
    return setmetatable({
        Adapter = adapter,
        LastResult = nil,
    }, MotionAdapter)
end

function MotionAdapter:Apply(result)
    self.LastResult = result
    return result
end

function MotionAdapter:Resolve(request)
    if self.Adapter and type(self.Adapter.Resolve) == "function" then
        return self.Adapter:Resolve(request)
    end
    return request
end

return MotionAdapter
