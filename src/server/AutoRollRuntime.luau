local AutoRollRuntime = {}

local autoRollBuffStateByUserId = {}
local luckBuffStateByUserId = {}
local foilChanceBuffStateByUserId = {}

local function setTimedBuff(stateTable, userId, valueKey, value, durationSeconds, minValue)
	userId = tonumber(userId)
	if not userId then
		return
	end

	local nextValue = math.max(minValue or 0, tonumber(value) or minValue or 0)
	local dur = math.max(1, tonumber(durationSeconds) or 1)
	local now = os.clock()
	local current = stateTable[userId]
	local currentEnd = (current and current.endsAt) or now

	stateTable[userId] = {
		[valueKey] = nextValue,
		endsAt = math.max(now, currentEnd) + dur,
	}
end

local function getTimedBuffValue(stateTable, userId, valueKey, fallback)
	userId = tonumber(userId)
	if not userId then
		return fallback
	end

	local state = stateTable[userId]
	if not state then
		return fallback
	end

	if state.endsAt <= os.clock() then
		stateTable[userId] = nil
		return fallback
	end

	return tonumber(state[valueKey]) or fallback
end

function AutoRollRuntime.AddAutoRollBuff(userId, multiplier, durationSeconds)
	setTimedBuff(autoRollBuffStateByUserId, userId, "multiplier", multiplier, durationSeconds, 1)
end

function AutoRollRuntime.GetAutoRollMultiplier(userId)
	return math.max(1, getTimedBuffValue(autoRollBuffStateByUserId, userId, "multiplier", 1))
end

function AutoRollRuntime.AddLuckBuff(userId, luckBonus, durationSeconds)
	setTimedBuff(luckBuffStateByUserId, userId, "luckBonus", luckBonus, durationSeconds, 0)
end

function AutoRollRuntime.GetLuckBonus(userId)
	return math.max(0, getTimedBuffValue(luckBuffStateByUserId, userId, "luckBonus", 0))
end

function AutoRollRuntime.AddFoilChanceBuff(userId, foilChanceBonus, durationSeconds)
	setTimedBuff(foilChanceBuffStateByUserId, userId, "foilChanceBonus", foilChanceBonus, durationSeconds, 0)
end

function AutoRollRuntime.GetFoilChanceBonus(userId)
	return math.max(0, getTimedBuffValue(foilChanceBuffStateByUserId, userId, "foilChanceBonus", 0))
end

function AutoRollRuntime.ClearPlayer(userId)
	userId = tonumber(userId)
	if not userId then
		return
	end
	autoRollBuffStateByUserId[userId] = nil
	luckBuffStateByUserId[userId] = nil
	borderChanceBuffStateByUserId[userId] = nil
end

-- Restore buffs from persisted data (endsAt = Unix timestamp from os.time())
function AutoRollRuntime.RestoreBuffs(userId, buffs)
	userId = tonumber(userId)
	if not userId or type(buffs) ~= "table" then
		return
	end
	local now = os.time()
	if buffs.autoRoll and type(buffs.autoRoll) == "table" then
		local endsAt = tonumber(buffs.autoRoll.endsAt)
		local mult = tonumber(buffs.autoRoll.multiplier) or 1
		if endsAt and endsAt > now then
			AutoRollRuntime.AddAutoRollBuff(userId, mult, math.max(1, endsAt - now))
		end
	end
	if buffs.luck and type(buffs.luck) == "table" then
		local endsAt = tonumber(buffs.luck.endsAt)
		local bonus = tonumber(buffs.luck.bonus) or 0
		if endsAt and endsAt > now and bonus > 0 then
			AutoRollRuntime.AddLuckBuff(userId, bonus, math.max(1, endsAt - now))
		end
	end
	-- Accept foilChance or legacy borderChance for backward compat
	local fc = buffs.foilChance or buffs.borderChance
	if fc and type(fc) == "table" then
		local endsAt = tonumber(fc.endsAt)
		local bonus = tonumber(fc.bonus) or 0
		if endsAt and endsAt > now and bonus > 0 then
			AutoRollRuntime.AddFoilChanceBuff(userId, bonus, math.max(1, endsAt - now))
		end
	end
end

-- Snapshot current buff state for persistence (endsAt as Unix timestamp)
function AutoRollRuntime.GetBuffStateForPersistence(userId)
	userId = tonumber(userId)
	if not userId then
		return nil
	end
	local now = os.time()
	local out = {}
	local ar = autoRollBuffStateByUserId[userId]
	if ar and ar.endsAt and ar.endsAt > os.clock() then
		local remaining = math.max(0, ar.endsAt - os.clock())
		out.autoRoll = { endsAt = now + remaining, multiplier = ar.multiplier or 1 }
	end
	local luck = luckBuffStateByUserId[userId]
	if luck and luck.endsAt and luck.endsAt > os.clock() then
		local remaining = math.max(0, luck.endsAt - os.clock())
		out.luck = { endsAt = now + remaining, bonus = luck.luckBonus or 0 }
	end
	local fc = foilChanceBuffStateByUserId[userId]
	if fc and fc.endsAt and fc.endsAt > os.clock() then
		local remaining = math.max(0, fc.endsAt - os.clock())
		out.foilChance = { endsAt = now + remaining, bonus = fc.foilChanceBonus or 0 }
	end
	return next(out) and out or nil
end

return AutoRollRuntime
