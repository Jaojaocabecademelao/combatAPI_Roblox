local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local ServerScriptService = game:GetService("ServerScriptService")
local ServerTests = ServerScriptService:WaitForChild("Server")
local TEST_TIMEOUT_SECONDS = 30

if ServerTests:GetAttribute("CombatTestRunnerStarted") then
	warn("CombatTestRunner already started for this server session")
	return
end
ServerTests:SetAttribute("CombatTestRunnerStarted", true)

local testsByName = {}
for _, child in ipairs(ServerTests:GetChildren()) do
	if child:IsA("ModuleScript") and string.match(child.Name, "Test$") then
		if testsByName[child.Name] then
			warn(("CombatTestRunner found duplicate test module %q; running one copy")
				:format(child.Name))
		else
			testsByName[child.Name] = child
		end
	end
end
local tests = {}
for _, testModule in pairs(testsByName) do
	table.insert(tests, testModule)
end
table.sort(tests, function(left, right)
	return left.Name < right.Name
end)

assert(#tests > 0, "CombatTestRunner found no test modules")

local failures = {}
local executed = 0
for _, testModule in ipairs(tests) do
	executed += 1
	local loadOk, runTest = pcall(require, testModule)
	if not loadOk then
		table.insert(failures, testModule.Name .. " failed to load: " .. tostring(runTest))
		warn("TEST FAIL " .. failures[#failures])
		continue
	end
	if type(runTest) ~= "function" then
		table.insert(failures, testModule.Name .. " must return a test function")
		warn("TEST FAIL " .. failures[#failures])
		continue
	end

	local completed = false
	local passed, detail
	local startedAt = os.clock()
	local thread = task.spawn(function()
		passed, detail = pcall(runTest)
		completed = true
	end)

	local deadline = startedAt + TEST_TIMEOUT_SECONDS
	while not completed and os.clock() < deadline do
		task.wait(0.05)
	end

	if not completed then
		if coroutine.status(thread) ~= "dead" then
			task.cancel(thread)
		end
		table.insert(failures, testModule.Name .. " timed out after "
			.. tostring(TEST_TIMEOUT_SECONDS) .. " seconds")
		warn("TEST FAIL " .. failures[#failures])
		break
	elseif passed then
		print(("TEST PASS %s (%.3fs)"):format(testModule.Name, os.clock() - startedAt))
	else
		table.insert(failures, testModule.Name .. " failed: " .. tostring(detail))
		warn("TEST FAIL " .. failures[#failures])
	end
end

if #failures > 0 then
	error(("CombatTestRunner: %d test(s) failed; executed %d of %d:\n- %s")
		:format(#failures, executed, #tests, table.concat(failures, "\n- ")))
end

print(("CombatTestRunner: PASS (%d tests)"):format(#tests))
