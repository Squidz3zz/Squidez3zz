-- GoreServer: starts the gore system on the server. For now it only loads Gore (ServerScriptService.Gore) and, in Studio only,
-- makes its TestHook; tracking every player's character comes later.
-- TestHook: a BindableFunction inside this script, made only in Studio. A test that requires Gore gets a separate copy of it
-- (its own Random, links and big-hit watchers), so the tests reach the game's own Gore through this instead:
-- TestHook:Invoke("call", fnName, ...) calls Gore[fnName](...) here and returns what it returns.
local RunService = game:GetService("RunService")

local Gore = require(script.Parent:WaitForChild("Gore"))

if RunService:IsStudio() then
	local hook = Instance.new("BindableFunction")
	hook.Name = "TestHook"
	hook.OnInvoke = function(action, fnName, ...)
		if action == "call" and type(Gore[fnName]) == "function" then
			return Gore[fnName](...)
		end
		error("TestHook: unknown action " .. tostring(action) .. " " .. tostring(fnName))
	end
	hook.Parent = script
end
