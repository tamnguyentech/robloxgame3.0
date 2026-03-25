-- ServerStateManager.luau
-- Centralized server-side state management for all game systems
-- Provides single source of truth and prevents state duplication across services

-- Why: Preserve the existing ServerStateManager require path while delegating actual work to focused,
-- easier-to-maintain state modules.
-- How: External callers continue using this facade API, while internal responsibilities live in
-- `src/server/core/state`.

local Players = game:GetService("Players")

local stateFolder = script.Parent:WaitForChild("state")
local PlayerStateSchema = require(stateFolder:WaitForChild("PlayerStateSchema"))
local PlayerStateStore = require(stateFolder:WaitForChild("PlayerStateStore"))
local PlayerProgressionState = require(stateFolder:WaitForChild("PlayerProgressionState"))
local PlayerCollectionsState = require(stateFolder:WaitForChild("PlayerCollectionsState"))
local PlayerStatsState = require(stateFolder:WaitForChild("PlayerStatsState"))
local PlayerStateEvents = require(stateFolder:WaitForChild("PlayerStateEvents"))

local ServerStateManager = {}

-- Why: Release cached player state when Roblox removes the player from the server.
-- How: This callback is connected once at module load and clears the user's in-memory state entry.
local function handlePlayerRemoving(player)
    PlayerStateStore.RemoveState(player.UserId)
end

-- Why: Keep backward compatibility for any existing callers that expect direct live-state access.
-- How: Pass a userId and this returns the mutable cached player-state table from the shared store.
function ServerStateManager.getPlayerState(userId)
    return PlayerStateStore.GetState(userId)
end

-- Why: Load and normalize save data without duplicating schema rules in multiple services.
-- How: Pass a userId and raw save data; the cached state is sanitized in place and returned.
function ServerStateManager.loadPlayerData(userId, data)
    local state = PlayerStateStore.GetState(userId)
    return PlayerStateSchema.ApplyLoadedData(state, data)
end

-- Why: Build save-safe snapshots without leaking references to the mutable cache.
-- How: Pass a userId and this returns a cloned, sanitized payload ready for persistence.
function ServerStateManager.getSaveData(userId)
    return PlayerStateSchema.CreateSaveData(PlayerStateStore.GetState(userId))
end

-- Why: Preserve the existing public API for coin mutation while moving progression logic into its own module.
-- How: Pass a userId and a delta; this returns the updated coin total.
function ServerStateManager.addCoins(userId, amount)
    return PlayerProgressionState.AddCoins(userId, amount)
end

-- Why: Preserve the existing public API for roll-count mutation while keeping progression rules centralized.
-- How: Pass a userId and a delta; this returns the updated roll count.
function ServerStateManager.addRollCount(userId, amount)
    return PlayerProgressionState.AddRollCount(userId, amount)
end

-- Why: Preserve the existing public API for level mutation while keeping level rules centralized.
-- How: Pass a userId and a level value; this returns the sanitized stored level.
function ServerStateManager.setLevel(userId, level)
    return PlayerProgressionState.SetLevel(userId, level)
end

-- Why: Preserve the existing inventory grant API while delegating collection rules to the collections module.
-- How: Pass a userId and a card id; this returns true on success and false on invalid input.
function ServerStateManager.addCardToInventory(userId, cardId)
    return PlayerCollectionsState.AddCardToInventory(userId, cardId)
end

-- Why: Preserve the existing batch inventory grant API while delegating collection rules to the collections module.
-- How: Pass a userId and a list of card ids; this returns the number of cards that were added.
function ServerStateManager.addCardsToInventory(userId, cardIds)
    return PlayerCollectionsState.AddCardsToInventory(userId, cardIds)
end

-- Why: Preserve the existing booster-pack mutation API while delegating collection rules to the collections module.
-- How: Pass a userId, a pack id, and a delta; this returns the updated stored count.
function ServerStateManager.addBoosterPack(userId, packId, amount)
    return PlayerCollectionsState.AddBoosterPack(userId, packId, amount)
end

-- Why: Preserve the existing item mutation API while delegating collection rules to the collections module.
-- How: Pass a userId, an item id, and a delta; this returns the updated stored count.
function ServerStateManager.addItem(userId, itemId, amount)
    return PlayerCollectionsState.AddItem(userId, itemId, amount)
end

-- Why: Preserve the existing stats snapshot API while moving stat ownership into a dedicated module.
-- How: Pass a userId and this returns a cloned stats table.
function ServerStateManager.getStats(userId)
    return PlayerStatsState.GetStats(userId)
end

-- Why: Preserve the existing stats write API while centralizing stat sanitization rules.
-- How: Pass a userId and a stats table; this returns the sanitized stored stats snapshot.
function ServerStateManager.setStats(userId, stats)
    return PlayerStatsState.SetStats(userId, stats)
end

-- Why: Preserve the existing stat-allocation API while centralizing point-allocation validation.
-- How: Pass a userId and stat name; returns success + cloned stats or false + error code.
function ServerStateManager.allocateStatPoint(userId, statName)
    return PlayerStatsState.AllocateStatPoint(userId, statName)
end

-- Why: Preserve the existing reset API while delegating stat reset rules to the stats module.
-- How: Pass a userId and a level value; this returns the cloned post-reset stat block.
function ServerStateManager.resetStats(userId, level)
    return PlayerStatsState.ResetStats(userId, level)
end

-- Why: Preserve the existing level-up API while separating pure stat mutation from client synchronization.
-- How: Pass a userId and this grants one point, syncs the client, and returns the cloned updated stat block.
function ServerStateManager.onLevelUp(userId)
    local stats = PlayerStatsState.GrantLevelUpPoint(userId)
    PlayerStateEvents.SyncStatsToPlayer(userId, stats)
    return stats
end

-- Why: Preserve fast scalar stat getters for existing callers that only need one value.
-- How: Pass a userId and this returns the player's stored Luck stat.
function ServerStateManager.getLuck(userId)
    return PlayerStatsState.GetLuck(userId)
end

-- Why: Preserve fast scalar stat getters for existing callers that only need one value.
-- How: Pass a userId and this returns the player's stored RollSpeed stat.
function ServerStateManager.getRollSpeed(userId)
    return PlayerStatsState.GetRollSpeed(userId)
end

-- Why: Preserve fast scalar stat getters for existing callers that only need one value.
-- How: Pass a userId and this returns the player's stored PotionDuration stat.
function ServerStateManager.getPotionDuration(userId)
    return PlayerStatsState.GetPotionDuration(userId)
end

-- Why: Preserve fast scalar stat getters for existing callers that only need one value.
-- How: Pass a userId and this returns the player's stored FoilChance stat.
function ServerStateManager.getFoilChance(userId)
    return PlayerStatsState.GetFoilChance(userId)
end

-- Why: Preserve fast scalar stat getters for existing callers that only need one value.
-- How: Pass a userId and this returns the player's stored unspent stat points.
function ServerStateManager.getPoints(userId)
    return PlayerStatsState.GetPoints(userId)
end

-- Why: Provide a single call-site for pushing the current reconciled stats to the owning
-- client after any server-side mutation (load, reset, potion use). Callers (SaveManager,
-- etc.) use this instead of requiring PlayerStateEvents directly so the facade stays the
-- only public integration surface, matching SPEC_V1 Architectural Validation rules.
-- How: Pass a userId; reconciles stats from the live cache then fires StatsUpdatedEvent.
function ServerStateManager.syncStatsToPlayer(userId)
    local stats = PlayerStatsState.GetStats(userId)
    return PlayerStateEvents.SyncStatsToPlayer(userId, stats)
end

Players.PlayerRemoving:Connect(handlePlayerRemoving)

return ServerStateManager
