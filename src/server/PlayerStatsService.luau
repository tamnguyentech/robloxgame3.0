-- PlayerStatsService.luau
-- Server-side service for managing player stat points
-- Refactored to use ServerStateManager as single source of truth

local AutoRollRuntime = require(script.Parent:WaitForChild("AutoRollRuntime"))
local ServerStateManager = require(script.Parent.core:WaitForChild("ServerStateManager"))

local PlayerStatsService = {}

-- Get or create stats for a player
function PlayerStatsService.GetStats(player)
	if not player or not player.UserId then
		return { Luck = 0, RollSpeed = 1, PotionDuration = 0, FoilChance = 0, Points = 0 }
	end
	return ServerStateManager.getStats(player.UserId)
end

-- Allocate a point to a stat
function PlayerStatsService.AllocatePoint(player, statName)
	if not player or not player.UserId then
		return false, "InvalidPlayer"
	end

	local success, result = ServerStateManager.allocateStatPoint(player.UserId, statName)

	return success, result
end

-- Reset all stats and refund points based on level
function PlayerStatsService.ResetStats(player, level)
	if not player or not player.UserId then
		return nil
	end

	local stats = ServerStateManager.resetStats(player.UserId, level)
	return stats
end

-- Grant a point when player levels up
function PlayerStatsService.OnLevelUp(player)
	if not player or not player.UserId then
		return nil
	end

	local stats = ServerStateManager.onLevelUp(player.UserId)
	return stats
end

-- Get current stats table for saving
function PlayerStatsService.GetSaveData(player)
	if not player or not player.UserId then
		return { Luck = 0, RollSpeed = 1, PotionDuration = 0, FoilChance = 0, Points = 0 }
	end

	return ServerStateManager.getStats(player.UserId)
end

-- Get specific values
function PlayerStatsService.GetLuck(player)
	if not player or not player.UserId then
		return 0
	end
	local luck = ServerStateManager.getLuck(player.UserId)
	local bonus = AutoRollRuntime.GetLuckBonus(player.UserId)
	return luck + bonus
end

function PlayerStatsService.GetRollSpeed(player)
	if not player or not player.UserId then
		return 1
	end
	return ServerStateManager.getRollSpeed(player.UserId)
end

function PlayerStatsService.GetPotionDuration(player)
	if not player or not player.UserId then
		return 0
	end
	return ServerStateManager.getPotionDuration(player.UserId)
end

function PlayerStatsService.GetFoilChance(player)
	if not player or not player.UserId then
		return 0
	end
	local base = ServerStateManager.getFoilChance(player.UserId)
	local bonus = AutoRollRuntime.GetFoilChanceBonus(player.UserId)
	return base + bonus
end

function PlayerStatsService.GetPoints(player)
	if not player or not player.UserId then
		return 0
	end
	return ServerStateManager.getPoints(player.UserId)
end

return PlayerStatsService
