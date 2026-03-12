local AutoRollRuntime = {}

local buffStateByUserId = {}

function AutoRollRuntime.AddAutoRollBuff(userId, multiplier, durationSeconds)
	userId = tonumber(userId)
	if not userId then
		return
	end

	local mult = math.max(1, tonumber(multiplier) or 1)
	local dur = math.max(1, tonumber(durationSeconds) or 1)
	local now = os.clock()
	local current = buffStateByUserId[userId]
	local currentEnd = (current and current.endsAt) or now

	buffStateByUserId[userId] = {
		multiplier = mult,
		endsAt = math.max(now, currentEnd) + dur,
	}
end

function AutoRollRuntime.GetAutoRollMultiplier(userId)
	userId = tonumber(userId)
	if not userId then
		return 1
	end

	local state = buffStateByUserId[userId]
	if not state then
		return 1
	end

	if state.endsAt <= os.clock() then
		buffStateByUserId[userId] = nil
		return 1
	end

	return math.max(1, tonumber(state.multiplier) or 1)
end

function AutoRollRuntime.ClearPlayer(userId)
	userId = tonumber(userId)
	if not userId then
		return
	end
	buffStateByUserId[userId] = nil
end

return AutoRollRuntime
