-- Starburst Scream: counter-based burst after every 2 connecting primary hits.
-- After triggering, unleash 3 follow-up hits dealing Magnitude * effectiveAttack.
--
-- Key rules:
-- - Only "primary" hits advance the counter (follow-ups never re-trigger).
-- - Counter advances when primaryResult is NOT dodged and finalDamage > 0.
-- - Follow-up hits are tagged via DamagePipeline.ResolveHit options so they can be ignored defensively.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardAbilityConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardAbilityConfig"))

local CombatFormulas = require(script.Parent:WaitForChild("CombatFormulas"))
local DamagePipeline = require(script.Parent:WaitForChild("DamagePipeline"))
local CombatAbilityState = require(script.Parent:WaitForChild("CombatAbilityState"))

local ABILITY_ID = "starburstscream"

local CombatStarburstScream = {}

local function getAbilityMagnitude()
	local def = CardAbilityConfig.GetAbility(ABILITY_ID)
	return tonumber(def and def.Magnitude) or 0.5
end

local function shouldCountPrimaryHit(primaryResult)
	if not primaryResult then
		return false
	end
	-- Defensive: never count any starburst follow-up as a new primary.
	if primaryResult.isStarburstFollowup then
		return false
	end
	-- Also avoid counting other attached follow-ups (e.g. fang).
	if primaryResult.isFangFollowup then
		return false
	end
	if primaryResult.isDodged then
		return false
	end
	return (tonumber(primaryResult.finalDamage) or 0) > 0
end

function CombatStarburstScream.maybeTriggerBurst(attacker, target, primaryResult, now, session)
	if not attacker or attacker.abilityId ~= ABILITY_ID then
		return nil
	end
	if not shouldCountPrimaryHit(primaryResult) then
		return nil
	end

	local counter = tonumber(CombatAbilityState.getCounter(attacker, ABILITY_ID)) or 0
	counter += 1

	-- Not yet: just update the counter.
	if counter < 2 then
		CombatAbilityState.setCounter(attacker, ABILITY_ID, counter)
		return nil
	end

	-- Trigger: reset counter immediately so follow-ups cannot re-trigger.
	CombatAbilityState.setCounter(attacker, ABILITY_ID, 0)

	local mag = getAbilityMagnitude()
	mag = math.max(0, tonumber(mag) or 0)

	local atk = CombatFormulas.GetEffectiveAttack(attacker, now)
	local followRaw = math.max(1, math.floor(atk * mag))

	local followResults = {}
	for i = 1, 3 do
		-- Stop early only for PvP where target health is immediately updated by ResolveHit.
		if target and (tonumber(target.health) or 0) <= 0 then
			break
		end
		if not target and session and (tonumber(session.npcHealth) or 0) <= 0 then
			break
		end

		local r = DamagePipeline.ResolveHit(attacker, target, followRaw, now, {
			isStarburstFollowup = true,
		})
		table.insert(followResults, r)
	end

	return followResults
end

return CombatStarburstScream

