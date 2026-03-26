-- Centralized follow-up spawning for primary hits.
-- Keeps battle-service/multi-hit plumbing stable as new follow-up mechanics are added.

local CombatFangFollowup = require(script.Parent:WaitForChild("CombatFangFollowup"))
local CombatStarburstScream = require(script.Parent:WaitForChild("CombatStarburstScream"))

local CombatFollowUpDispatcher = {}

-- Returns an array of follow-up hit results (each already tagged in DamagePipeline),
-- or nil when nothing triggers.
function CombatFollowUpDispatcher.maybeGetFollowUps(attacker, target, primaryResult, now, session)
	local out = {}

	local fang = CombatFangFollowup.maybeFangFollowup(attacker, target, primaryResult, now, session)
	if fang then
		table.insert(out, fang)
	end

	local burst = CombatStarburstScream.maybeTriggerBurst(attacker, target, primaryResult, now, session)
	if type(burst) == "table" then
		for _, r in ipairs(burst) do
			table.insert(out, r)
		end
	end

	if #out == 0 then
		return nil
	end
	return out
end

return CombatFollowUpDispatcher

