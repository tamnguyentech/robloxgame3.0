local CombatEventBus = {}

local handlersByEvent = {}

function CombatEventBus.Subscribe(eventName, priority, fn)
	if type(eventName) ~= "string" or eventName == "" or type(fn) ~= "function" then
		return
	end
	local bucket = handlersByEvent[eventName]
	if not bucket then
		bucket = {}
		handlersByEvent[eventName] = bucket
	end
	table.insert(bucket, {
		priority = tonumber(priority) or 100,
		fn = fn,
	})
	table.sort(bucket, function(a, b)
		return a.priority < b.priority
	end)
end

function CombatEventBus.Fire(eventName, payload)
	local bucket = handlersByEvent[eventName]
	if not bucket then
		return
	end
	for _, entry in ipairs(bucket) do
		entry.fn(payload)
	end
end

return CombatEventBus
