-- Fang-over-fang: after a connecting primary strike, one follow-up hit for Magnitude * effective attack.
-- PvP uses a card target; PvE vs NPC uses target nil (caller applies ApplyDamageToNpc).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardAbilityConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardAbilityConfig"))
local CombatFormulas = require(script.Parent:WaitForChild("CombatFormulas"))
local DamagePipeline = require(script.Parent:WaitForChild("DamagePipeline"))

local ABILITY_ID = "fangoverfang"

local CombatFangFollowup = {}

function CombatFangFollowup.maybeFangFollowup(attacker, target, primaryResult, now, session)
	if not attacker or attacker.abilityId ~= ABILITY_ID then
		return nil
	end
	if not primaryResult or primaryResult.isFangFollowup then
		return nil
	end
	if primaryResult.isDodged or (tonumber(primaryResult.finalDamage) or 0) <= 0 then
		return nil
	end
	if target then
		if (tonumber(target.health) or 0) <= 0 then
			return nil
		end
	elseif session and (tonumber(session.npcHealth) or 0) <= 0 then
		return nil
	end

	local def = CardAbilityConfig.GetAbility(ABILITY_ID)
	local mag = tonumber(def and def.Magnitude) or 0.2
	mag = math.clamp(mag, 0, 2)

	local atk = CombatFormulas.GetEffectiveAttack(attacker, now)
	local followRaw = math.max(1, math.floor(atk * mag))
	return DamagePipeline.ResolveHit(attacker, target, followRaw, now, { isFangFollowup = true })
end

return CombatFangFollowup
