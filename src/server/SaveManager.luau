local DataStoreService = game:GetService("DataStoreService")
local inventoryStore = DataStoreService:GetDataStore("PlayerInventoryV1")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local saveEvent = ReplicatedStorage:WaitForChild("SaveDataEvent")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local BalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))
local ServerStateManager = require(script.Parent.core:WaitForChild("ServerStateManager"))
local PlayerStateConstants = require(script.Parent.core:WaitForChild("state"):WaitForChild("PlayerStateConstants"))
local AutoRollRuntime = require(script.Parent:WaitForChild("AutoRollRuntime"))

local SAVE_THROTTLE_SECONDS = 6
local SAVE_FLUSH_INTERVAL_SECONDS = 8
local MAX_COMBAT_SLOTS = 5
local DATASTORE_MAX_BYTES = 4000000
local DATASTORE_RETRY_COUNT = 3
local DATASTORE_RETRY_DELAY_SECONDS = 0.4

-- In-memory storage for player data
local playerData = {}
-- Rate limiting for saves
local lastSave = {}
local pendingSave = {}
local dirtyPlayers = {}
local warnedDataStoreUnavailable = false
local loadingPlayers = {}

local saveManagerBridge = ServerStorage:FindFirstChild("SaveManagerBridge")
if saveManagerBridge and not saveManagerBridge:IsA("BindableFunction") then
	saveManagerBridge:Destroy()
	saveManagerBridge = nil
end
if not saveManagerBridge then
	saveManagerBridge = Instance.new("BindableFunction")
	saveManagerBridge.Name = "SaveManagerBridge"
	saveManagerBridge.Parent = ServerStorage
end

local function isDataStoreUnavailableError(err)
	local msg = string.lower(tostring(err or ""))
	return string.find(msg, "501", 1, true) ~= nil
		or string.find(msg, "not implemented", 1, true) ~= nil
		or string.find(msg, "api services", 1, true) ~= nil
		or string.find(msg, "datastore", 1, true) ~= nil and string.find(msg, "studio", 1, true) ~= nil
end

local function warnDataStoreError(prefix, playerName, err)
	if isDataStoreUnavailableError(err) then
		if not warnedDataStoreUnavailable then
			warnedDataStoreUnavailable = true
			warn("DataStore unavailable in current environment (commonly Studio/API setting). Using in-session fallback data.")
		end
		return
	end
	warn(prefix .. tostring(playerName) .. ": " .. tostring(err))
end

local function loadPlayerDataFromStore(userId, playerName)
	local attempts = 0
	local lastErr = nil

	while attempts < DATASTORE_RETRY_COUNT do
		attempts = attempts + 1
		local ok, result = pcall(function()
			return inventoryStore:GetAsync(userId)
		end)
		if ok then
			return true, result
		end

		lastErr = result
		if attempts < DATASTORE_RETRY_COUNT then
			task.wait(DATASTORE_RETRY_DELAY_SECONDS)
		end
	end

	warnDataStoreError("Failed to load data for player ", tostring(playerName or userId), lastErr)
	return false, lastErr
end

local function savePlayerDataToStore(userId, data, playerName)
	local attempts = 0
	local lastErr = nil

	while attempts < DATASTORE_RETRY_COUNT do
		attempts = attempts + 1
		local ok, err = pcall(function()
			inventoryStore:UpdateAsync(userId, function(_old)
				return data
			end)
		end)
		if ok then
			return true
		end

		lastErr = err
		if attempts < DATASTORE_RETRY_COUNT then
			task.wait(DATASTORE_RETRY_DELAY_SECONDS)
		end
	end

	warnDataStoreError("Failed to save data for player ", tostring(playerName or userId), lastErr)
	return false, lastErr
end

local function persistPlayerData(userId, playerName)
	local data = playerData[userId]
	if not data then
		return
	end
	-- Why: Stats may have been mutated inside server-core (e.g., level-up points granted via
	-- PlayerStatsState) without being written back to playerData. Always snapshot from the
	-- authoritative ServerStateManager cache before every DataStore write so the two stores
	-- never diverge.
	local coreStats = ServerStateManager.getStats(userId)
	if coreStats then
		data.stats = coreStats
	end
	-- Snapshot potion/roll buff state from AutoRollRuntime so it persists across sessions.
	local buffState = AutoRollRuntime.GetBuffStateForPersistence(userId)
	data.buffs = buffState or nil
	local success = savePlayerDataToStore(userId, data, playerName)
	if not success then
		dirtyPlayers[userId] = true
		return
	end
	dirtyPlayers[userId] = nil
end

local tryPersistPlayerData
tryPersistPlayerData = function(userId, playerName)
	if not playerData[userId] then
		pendingSave[userId] = nil
		return
	end
	dirtyPlayers[userId] = true -- Ensure retry runs if throttled (e.g. StatsHandler, merge)

	local now = tick()
	local last = lastSave[userId]
	if last and (now - last) < SAVE_THROTTLE_SECONDS then
		if not pendingSave[userId] then
			pendingSave[userId] = true
			local waitTime = math.max(0.05, SAVE_THROTTLE_SECONDS - (now - last))
			task.delay(waitTime, function()
				pendingSave[userId] = nil
				if dirtyPlayers[userId] then
					tryPersistPlayerData(userId, playerName)
				end
			end)
		end
		return
	end

	lastSave[userId] = now
	persistPlayerData(userId, playerName)
end

local function buildDefaultData()
	return {
		combat = {},
		rollCount = 0,
		level = 1,
		coins = 0,
		boosterPacks = {},
		items = PlayerStateConstants.GetDefaultItems(),
		stats = {
			Luck = 0,
			RollSpeed = 1,
			PotionDuration = 0,
			FoilChance = 0,
			Points = 1,
		},
		clientSettings = {
			ShowIdleRollCardNotifications = true,
		},
	}
end

local function sanitizeNumberMap(valueTable)
	local out = {}
	if type(valueTable) ~= "table" then
		return out
	end
	for key, value in pairs(valueTable) do
		if type(key) == "string" and type(value) == "number" then
			out[key] = math.max(0, math.floor(value))
		end
	end
	return out
end

local function normalizeCardReference(cardRef)
	if type(cardRef) ~= "string" or cardRef == "" then
		return nil
	end
	return CardDatabase.NormalizeCardReference(cardRef)
end

local function getUniqueOwnershipKey(cardRef)
	local parsed = CardDatabase.ParseCardReference(cardRef)
	if not parsed then
		return nil
	end
	local data = CardDatabase.GetCardData(parsed.BaseCardId)
	if data and data.Rarity == "Transcendent" then
		return parsed.BaseCardId
	end
	return parsed.CardRef
end

local function sanitizeInventoryList(cardList)
	local out = {}
	if type(cardList) ~= "table" then
		return out
	end
	for _, cardRef in ipairs(cardList) do
		if type(cardRef) == "string" then
			local normalized = normalizeCardReference(cardRef)
			if normalized then
				table.insert(out, normalized)
			end
		end
	end
	return out
end

local function sanitizeCombatSlots(cardList, maxLen)
	local out = {}
	maxLen = math.max(1, math.floor(tonumber(maxLen) or 5))
	if type(cardList) ~= "table" then
		for i = 1, maxLen do
			out[i] = ""
		end
		return out
	end

	for i = 1, maxLen do
		local cardRef = cardList[i]
		if type(cardRef) == "string" and cardRef ~= "" then
			local normalized = normalizeCardReference(cardRef)
			out[i] = normalized or ""
		else
			out[i] = ""
		end
	end

	return out
end

local function isTranscendentUniqueCard(cardId)
	if type(cardId) ~= "string" or cardId == "" then
		return false
	end
	local parsed = CardDatabase.ParseCardReference(cardId)
	local data = parsed and CardDatabase.GetCardData(parsed.BaseCardId) or nil
	return data ~= nil and data.Rarity == "Transcendent"
end

local function enforceUniqueTranscendentOwnership(inventoryList, combatList)
	local seen = {}
	local normalizedCombat = {}

	for i, cardId in ipairs(combatList or {}) do
		local uniqueKey = getUniqueOwnershipKey(cardId)
		if type(cardId) == "string" and cardId ~= "" and isTranscendentUniqueCard(cardId) then
			if uniqueKey and seen[uniqueKey] then
				normalizedCombat[i] = ""
			else
				if uniqueKey then
					seen[uniqueKey] = true
				end
				normalizedCombat[i] = cardId
			end
		else
			normalizedCombat[i] = (type(cardId) == "string") and cardId or ""
		end
	end

	local normalizedInventory = {}
	for _, cardId in ipairs(inventoryList or {}) do
		local uniqueKey = getUniqueOwnershipKey(cardId)
		if type(cardId) == "string" and cardId ~= "" and isTranscendentUniqueCard(cardId) then
			if uniqueKey and not seen[uniqueKey] then
				seen[uniqueKey] = true
				table.insert(normalizedInventory, cardId)
			end
		elseif type(cardId) == "string" and cardId ~= "" then
			table.insert(normalizedInventory, cardId)
		end
	end

	return normalizedInventory, normalizedCombat
end

local function normalizeLoadedData(savedData)
	local data = buildDefaultData()
	if type(savedData) ~= "table" then
		return data
	end

	if type(savedData.inventory) == "table" then
		data.inventory = sanitizeInventoryList(savedData.inventory)
	end
	if type(savedData.combat) == "table" then
		data.combat = sanitizeCombatSlots(savedData.combat, MAX_COMBAT_SLOTS)
	end
	if type(savedData.rollCount) == "number" then
		data.rollCount = math.max(0, math.floor(savedData.rollCount))
	end
	if type(savedData.level) == "number" then
		data.level = math.max(1, math.floor(savedData.level))
	end
	if type(savedData.coins) == "number" then
		data.coins = math.max(0, math.floor(savedData.coins))
	end
	if type(savedData.boosterPacks) == "table" then
		data.boosterPacks = sanitizeNumberMap(savedData.boosterPacks)
	end
	if type(savedData.items) == "table" then
		data.items = sanitizeNumberMap(savedData.items)
		-- Migrate legacy BorderChancePotion to FoilChancePotion (backward compat).
		local borderPotionCount = tonumber(data.items.BorderChancePotion)
		if borderPotionCount ~= nil then
			data.items.FoilChancePotion = (tonumber(data.items.FoilChancePotion) or 0) + borderPotionCount
			data.items.BorderChancePotion = nil
		end
		local defaultItems = PlayerStateConstants.GetDefaultItems()
		for key, defaultVal in pairs(defaultItems) do
			if data.items[key] == nil then
				data.items[key] = defaultVal
			end
		end
	end
	if type(savedData.stats) == "table" then
		data.stats = {
			Luck = math.max(0, math.floor(tonumber(savedData.stats.Luck) or 0)),
			RollSpeed = math.max(1, math.floor(tonumber(savedData.stats.RollSpeed) or 1)),
			PotionDuration = math.max(0, math.floor(tonumber(savedData.stats.PotionDuration) or 0)),
			FoilChance = math.max(0, math.floor(tonumber(savedData.stats.FoilChance or savedData.stats.BorderChance) or 0)),
			Points = math.max(0, math.floor(tonumber(savedData.stats.Points) or data.level or 1)),
		}
	end

	data.inventory, data.combat = enforceUniqueTranscendentOwnership(data.inventory, data.combat)

	if type(savedData.buffs) == "table" then
		data.buffs = savedData.buffs
	end

	if type(savedData.clientSettings) == "table" then
		data.clientSettings = {
			ShowIdleRollCardNotifications = (savedData.clientSettings.ShowIdleRollCardNotifications == true),
		}
	else
		data.clientSettings = { ShowIdleRollCardNotifications = true }
	end

	return data
end

local function cloneSaveState(data)
	return {
		inventory = data.inventory,
		combat = data.combat,
		rollCount = data.rollCount,
		level = data.level,
		coins = data.coins,
		boosterPacks = data.boosterPacks,
		items = data.items,
		stats = data.stats,
		buffs = data.buffs,
		clientSettings = type(data.clientSettings) == "table" and table.clone(data.clientSettings) or { ShowIdleRollCardNotifications = true },
	}
end

local function cloneNumberMap(valueTable)
	local out = {}
	for key, value in pairs(valueTable or {}) do
		if type(key) == "string" and type(value) == "number" then
			out[key] = value
		end
	end
	return out
end

local function ensurePlayerDataLoaded(userId, playerName)
	userId = tonumber(userId)
	if not userId then
		return nil
	end

	if playerData[userId] then
		return playerData[userId]
	end

	while loadingPlayers[userId] do
		task.wait()
		if playerData[userId] then
			return playerData[userId]
		end
	end

	loadingPlayers[userId] = true

	local loadedData
	local ok, savedData = loadPlayerDataFromStore(userId, playerName)

	if ok and type(savedData) == "table" then
		loadedData = normalizeLoadedData(savedData)
	else
		loadedData = buildDefaultData()
	end

	playerData[userId] = loadedData
	loadingPlayers[userId] = nil
	-- Restore potion/roll buffs from persisted state so they continue across rejoin.
	if type(loadedData.buffs) == "table" then
		AutoRollRuntime.RestoreBuffs(userId, loadedData.buffs)
	end
	-- Sync with ServerStateManager -- this reconciles Points to the authoritative level.
	ServerStateManager.loadPlayerData(userId, loadedData)
	-- Pull the reconciled stats back so every snapshot sent to the client is authoritative.
	-- Why: normalizeLoadedData builds stats from the raw DataStore value, which may carry a
	-- stale Points field. ServerStateManager.loadPlayerData runs ReconcileStatsToLevel and is
	-- the single source of truth; we overwrite loadedData.stats before any FireClient call.
	local initialReconciledStats = ServerStateManager.getStats(userId)
	if initialReconciledStats then
		loadedData.stats = initialReconciledStats
	end
	-- Push reconciled stats through StatsUpdatedEvent so the Profile UI receives them
	-- immediately on join, independently of whether the client's WaitForChild for
	-- AllocatePointsRemote resolves before or after this point.
	pcall(ServerStateManager.syncStatsToPlayer, userId)
	-- Fire initial save and economy snapshots to client for UI sync
	local initPlayer = Players:GetPlayerByUserId(userId)
	if initPlayer then
		pcall(function()
			-- Include live buff state (from restore) so client shows potion timers
			local dataToSend = table.clone(loadedData)
			dataToSend.buffs = AutoRollRuntime.GetBuffStateForPersistence(userId)
			dataToSend.clientSettings = loadedData.clientSettings or { ShowIdleRollCardNotifications = true }
			saveEvent:FireClient(initPlayer, dataToSend)
			local econEvent = ReplicatedStorage:FindFirstChild("EconomySnapshotEvent")
			if not (econEvent and econEvent:IsA("RemoteEvent")) then
				econEvent = Instance.new("RemoteEvent")
				econEvent.Name = "EconomySnapshotEvent"
				econEvent.Parent = ReplicatedStorage
			end
			local econSnapshot = {
				coins        = math.max(0, math.floor(tonumber(loadedData.coins) or 0)),
				boosterPacks = loadedData.boosterPacks or {},
				items        = loadedData.items or PlayerStateConstants.GetDefaultItems(),
				rollCount    = math.max(0, math.floor(tonumber(loadedData.rollCount) or 0)),
				level        = math.max(1, math.floor(tonumber(loadedData.level) or 1)),
				stats        = loadedData.stats or {
					Luck = 0, RollSpeed = 1, PotionDuration = 0,
					FoilChance = 0, Points = loadedData.level or 1,
				},
			}
			econEvent:FireClient(initPlayer, econSnapshot)
		end)
	end
	return loadedData
end

local function buildOwnedCardCounts(inventoryList, combatList)
	local counts = {}

	for _, cardRef in ipairs(inventoryList or {}) do
		local normalized = normalizeCardReference(cardRef)
		if normalized then
			counts[normalized] = (counts[normalized] or 0) + 1
		end
	end

	for _, cardRef in ipairs(combatList or {}) do
		local normalized = normalizeCardReference(cardRef)
		if normalized then
			counts[normalized] = (counts[normalized] or 0) + 1
		end
	end

	return counts
end

local function getEconomyState(userId)
	local current = playerData[userId] or ensurePlayerDataLoaded(userId, userId)
	if not current then
		return {
			coins = 0,
			boosterPacks = {},
			items = PlayerStateConstants.GetDefaultItems(),
			rollCount = 0,
			level = 1,
			stats = {
				Luck = 0,
				RollSpeed = 1,
				PotionDuration = 0,
				FoilChance = 0,
				Points = 1,
			},
		}
	end

	local items = cloneNumberMap(current.items)
	items.AutoRoll2x20s = items.AutoRoll2x20s or 0
	items.LuckPotion = items.LuckPotion or 0
	items.FoilChancePotion = items.FoilChancePotion or 0

	-- Why: Read stats from the server-core cache so level-up points that have been granted
	-- but not yet flushed to playerData are still reflected in the economy snapshot returned
	-- to the client.
	local coreStats = ServerStateManager.getStats(userId)
	local stats = coreStats or current.stats or {
		Luck = 0, RollSpeed = 1, PotionDuration = 0,
		FoilChance = 0, Points = current.level or 1,
	}

	return {
		coins        = math.max(0, math.floor(tonumber(current.coins) or 0)),
		boosterPacks = cloneNumberMap(current.boosterPacks),
		items        = items,
		rollCount    = math.max(0, math.floor(tonumber(current.rollCount) or 0)),
		level        = math.max(1, math.floor(tonumber(current.level) or 1)),
		stats = {
			Luck          = math.max(0, math.floor(tonumber(stats.Luck) or 0)),
			RollSpeed     = math.max(1, math.floor(tonumber(stats.RollSpeed) or 1)),
			PotionDuration = math.max(0, math.floor(tonumber(stats.PotionDuration) or 0)),
			FoilChance    = math.max(0, math.floor(tonumber(stats.FoilChance) or 0)),
			Points        = math.max(0, math.floor(tonumber(stats.Points) or (tonumber(current.level) or 1))),
		},
	}
end

local function executeEconomyDelta(payload)
	if type(payload) ~= "table" then
		return false, "InvalidPayload"
	end

	local userId = tonumber(payload.userId)
	if not userId then
		return false, "InvalidUserId"
	end

	local current = playerData[userId] or ensurePlayerDataLoaded(userId, userId) or buildDefaultData()
	current.inventory, current.combat = enforceUniqueTranscendentOwnership(current.inventory, current.combat)
	current.boosterPacks = sanitizeNumberMap(current.boosterPacks)
	current.items = sanitizeNumberMap(current.items)
	current.items.AutoRoll2x20s = current.items.AutoRoll2x20s or 0
	current.items.LuckPotion = current.items.LuckPotion or 0
	current.items.FoilChancePotion = current.items.FoilChancePotion or 0

	local coinsDelta = math.floor(tonumber(payload.coinsDelta) or 0)
	local nextCoins = math.floor(tonumber(current.coins) or 0) + coinsDelta
	if nextCoins < 0 then
		return false, "InsufficientCoins"
	end

	local rollCountDelta = math.floor(tonumber(payload.rollCountDelta) or 0)
	local nextRollCount = math.max(0, math.floor(tonumber(current.rollCount) or 0) + rollCountDelta)
	local rollsPerLevel = BalanceConfig.ROLLS_PER_LEVEL
	local previousLevel = math.max(1, math.floor((tonumber(current.rollCount) or 0) / rollsPerLevel) + 1)
	local nextLevel = math.max(1, math.floor(nextRollCount / rollsPerLevel) + 1)

	local rawPackDelta = (type(payload.boosterPacksDelta) == "table") and payload.boosterPacksDelta or {}
	local packDelta = sanitizeNumberMap(rawPackDelta)
	for packId, deltaAbs in pairs(rawPackDelta) do
		if type(packId) == "string" and type(deltaAbs) == "number" then
			local delta = math.floor(deltaAbs)
			local currentCount = math.max(0, math.floor(tonumber(current.boosterPacks[packId]) or 0))
			if (currentCount + delta) < 0 then
				return false, "InsufficientBoosterPacks"
			end
			packDelta[packId] = delta
		end
	end

	local rawItemDelta = (type(payload.itemsDelta) == "table") and payload.itemsDelta or {}
	local itemDelta = sanitizeNumberMap(rawItemDelta)
	for itemId, deltaAbs in pairs(rawItemDelta) do
		if type(itemId) == "string" and type(deltaAbs) == "number" then
			local delta = math.floor(deltaAbs)
			local currentCount = math.max(0, math.floor(tonumber(current.items[itemId]) or 0))
			if (currentCount + delta) < 0 then
				return false, "InsufficientItems"
			end
			itemDelta[itemId] = delta
		end
	end

	local ownedCounts = buildOwnedCardCounts(current.inventory, current.combat)
	local consumedCards = {}
	local requestedConsumeCards = {}
	for _, cardRef in ipairs(payload.consumeCards or {}) do
		if type(cardRef) == "string" and cardRef ~= "" then
			local normalized = normalizeCardReference(cardRef)
			if not normalized or (ownedCounts[normalized] or 0) <= 0 then
				return false, "InsufficientCards"
			end
			ownedCounts[normalized] = ownedCounts[normalized] - 1
			table.insert(requestedConsumeCards, normalized)
		end
	end

	local grantedCards = {}
	local skippedUniqueGrant = false
	for _, cardRef in ipairs(payload.grantCards or {}) do
		if type(cardRef) == "string" and cardRef ~= "" then
			local normalized = normalizeCardReference(cardRef)
			if normalized then
				local uniqueKey = getUniqueOwnershipKey(normalized)
				if isTranscendentUniqueCard(normalized) and uniqueKey and (ownedCounts[uniqueKey] or 0) >= 1 then
					skippedUniqueGrant = true
				else
					ownedCounts[normalized] = (ownedCounts[normalized] or 0) + 1
					if uniqueKey and uniqueKey ~= normalized then
						ownedCounts[uniqueKey] = (ownedCounts[uniqueKey] or 0) + 1
					end
					table.insert(grantedCards, normalized)
				end
			end
		end
	end

	if skippedUniqueGrant and #grantedCards == 0 and coinsDelta < 0 then
		return false, "AlreadyOwnedUniqueCard"
	end

	current.coins = nextCoins
	current.rollCount = nextRollCount
	current.level = nextLevel

	-- Keep server-core cache in sync (single source of truth for derived systems like Points).
	-- SaveManager historically mutated only playerData; we also mirror into ServerStateManager so
	-- stats/points derived from level remain deterministic even after /resetrolls or economy deltas.
	ServerStateManager.addCoins(userId, coinsDelta)
	ServerStateManager.addRollCount(userId, rollCountDelta)
	ServerStateManager.setLevel(userId, nextLevel)

	-- Why: Require once outside the loop to avoid redundant require() calls on every
	-- level-up iteration. OnLevelUp mutates server-core state (PlayerStatsState) and
	-- immediately fires StatsUpdatedEvent so the client reflects the new Points value.
	if nextLevel > previousLevel then
		local levelUpPlayer = Players:GetPlayerByUserId(userId)
		if levelUpPlayer then
			local statsModule = script.Parent:FindFirstChild("PlayerStatsService")
			local statsService
			if statsModule then
				statsService = require(statsModule)
			else
				statsService = require(ReplicatedStorage:WaitForChild("Server"):WaitForChild("PlayerStatsService"))
			end
			for _ = 1, (nextLevel - previousLevel) do
				statsService.OnLevelUp(levelUpPlayer)
			end
			-- Why: Pull the newly granted points from server-core back into playerData
			-- immediately so the next DataStore write persists them without waiting for
			-- a separate save cycle. This closes the split-brain gap between the two stores.
			current.stats = ServerStateManager.getStats(userId)
		end
	end

	for packId, delta in pairs(packDelta) do
		local nextCount = math.max(0, math.floor(tonumber(current.boosterPacks[packId]) or 0) + delta)
		current.boosterPacks[packId] = nextCount
	end

	for itemId, delta in pairs(itemDelta) do
		local nextCount = math.max(0, math.floor(tonumber(current.items[itemId]) or 0) + delta)
		current.items[itemId] = nextCount
	end
	current.items.AutoRoll2x20s = current.items.AutoRoll2x20s or 0

	if #requestedConsumeCards > 0 then
		local removalsRemaining = {}
		for _, cardId in ipairs(requestedConsumeCards) do
			removalsRemaining[cardId] = (removalsRemaining[cardId] or 0) + 1
		end

		local nextInventory = {}
		for _, cardId in ipairs(current.inventory) do
			if removalsRemaining[cardId] and removalsRemaining[cardId] > 0 then
				removalsRemaining[cardId] = removalsRemaining[cardId] - 1
				table.insert(consumedCards, cardId)
			else
				table.insert(nextInventory, cardId)
			end
		end
		current.inventory = nextInventory
	end

	for _, cardId in ipairs(grantedCards) do
		table.insert(current.inventory, cardId)
	end

	playerData[userId] = current
	dirtyPlayers[userId] = true
	-- Do not call tryPersistPlayerData here; periodic flush + PlayerRemoving handle persistence.
	-- This prevents DataStore throttle overflow when auto-roll speed is very fast.

	local economy = getEconomyState(userId)
	economy.grantedCards = grantedCards
	economy.consumedCards = consumedCards
	return true, economy
end

local function mergePlayerPatch(current, patch, playerName)
	local merged = cloneSaveState(current)

	if patch.inventory ~= nil then
		if type(patch.inventory) ~= "table" then
			return nil, "Invalid inventory data from " .. playerName
		end
		merged.inventory = sanitizeInventoryList(patch.inventory)
	end

	if patch.combat ~= nil then
		if type(patch.combat) ~= "table" then
			return nil, "Invalid combat data from " .. playerName
		end
		merged.combat = sanitizeCombatSlots(patch.combat, MAX_COMBAT_SLOTS)
	end

	if patch.inventory ~= nil or patch.combat ~= nil then
		merged.inventory, merged.combat = enforceUniqueTranscendentOwnership(merged.inventory, merged.combat)

		local currentOwned = buildOwnedCardCounts(current.inventory, current.combat)
		local mergedOwned = buildOwnedCardCounts(merged.inventory, merged.combat)
		local hasInflation = false
		for cardId, ownedCount in pairs(mergedOwned) do
			if ownedCount > (currentOwned[cardId] or 0) then
				hasInflation = true
				break
			end
		end
		-- When client sends inflated inventory (e.g. stale UI after sell), use server's
		-- authoritative inventory but accept client's combat deck (validated against inventory).
		if hasInflation then
			merged.inventory = current.inventory
			-- Validate combat: each slot must have a card that exists in server inventory.
			-- Track remaining count per card as we assign combat slots.
			local remaining = buildOwnedCardCounts(current.inventory, {})
			for i, cardRef in ipairs(merged.combat or {}) do
				if type(cardRef) == "string" and cardRef ~= "" then
					local norm = normalizeCardReference(cardRef)
					if norm and (remaining[norm] or 0) > 0 then
						remaining[norm] = (remaining[norm] or 1) - 1
					else
						merged.combat[i] = ""
					end
				end
			end
			merged.inventory, merged.combat = enforceUniqueTranscendentOwnership(merged.inventory, merged.combat)
		end
	end

	if patch.coins ~= nil then
		if type(patch.coins) ~= "number" then
			return nil, "Invalid coin data from " .. playerName
		end
		merged.coins = math.max(0, math.floor(patch.coins))
	end

	-- Roll count/level progression is server-authoritative and intentionally
	-- ignored from client save patches.

	-- Booster/item ownership is server-authoritative and intentionally
	-- ignored from client save patches.

	if type(patch.clientSettings) == "table" then
		merged.clientSettings = {
			ShowIdleRollCardNotifications = (patch.clientSettings.ShowIdleRollCardNotifications == true),
		}
	end

	return merged
end

saveManagerBridge.OnInvoke = function(action, payload)
	if action == "GetEconomyState" then
		local bridgeUserId = tonumber(payload)
		if not bridgeUserId then
			return false, "InvalidUserId"
		end
		return true, getEconomyState(bridgeUserId)
	end

	if action == "ExecuteEconomyDelta" then
		return executeEconomyDelta(payload)
	end

	return false, "UnsupportedBridgeAction"
end

saveEvent.OnServerEvent:Connect(function(player, data)
	-- Split into two separate if blocks (not elseif) so each branch is an independent
	-- statement; this avoids parser ambiguity that some LSP versions report on elseif.
	if data == "RequestLoad" then
		local loadedData = ensurePlayerDataLoaded(player.UserId, player.Name) or buildDefaultData()
		-- Always send reconciled stats so Points = (level - spent) regardless of
		-- what the DataStore had cached. Server-core is the authoritative source.
		local reconciledStats = ServerStateManager.getStats(player.UserId)
		local requestSnapshot = {
			inventory       = loadedData.inventory,
			combat          = loadedData.combat,
			rollCount       = loadedData.rollCount,
			level           = loadedData.level,
			coins           = loadedData.coins,
			boosterPacks    = loadedData.boosterPacks,
			items           = loadedData.items,
			stats           = reconciledStats or loadedData.stats,
			buffs           = AutoRollRuntime.GetBuffStateForPersistence(player.UserId),
			clientSettings  = loadedData.clientSettings or { ShowIdleRollCardNotifications = true },
		}
		saveEvent:FireClient(player, requestSnapshot)
		return
	end

	if type(data) == "table" then
		local current = playerData[player.UserId]
			or ensurePlayerDataLoaded(player.UserId, player.Name)
			or buildDefaultData()
		local merged, mergeErr = mergePlayerPatch(current, data, player.Name)
		if not merged then
			warn("[SaveManager] Merge rejected for ", player.Name, " — ", mergeErr)
			return
		end

		-- Check data size (4 MB limit)
		local dataSize = #HttpService:JSONEncode(merged)
		if dataSize > DATASTORE_MAX_BYTES then
			warn("Data too large for player " .. player.Name .. " (" .. dataSize .. " bytes)")
			return
		end

		-- Always keep latest state in memory, even when DataStore write is throttled.
		playerData[player.UserId] = merged
		dirtyPlayers[player.UserId] = true

		-- Persist immediately when possible, otherwise queue a delayed write.
		tryPersistPlayerData(player.UserId, player.Name)
	end
end)

Players.PlayerAdded:Connect(function(player)
	ensurePlayerDataLoaded(player.UserId, player.Name)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		ensurePlayerDataLoaded(player.UserId, player.Name)
	end)
end

task.spawn(function()
	while true do
		task.wait(SAVE_FLUSH_INTERVAL_SECONDS)
		for userId in pairs(dirtyPlayers) do
			if playerData[userId] then
				tryPersistPlayerData(userId, userId)
			else
				dirtyPlayers[userId] = nil
			end
		end
	end
end)

-- Save data when player leaves
game.Players.PlayerRemoving:Connect(function(player)
	task.wait(0.25) -- Brief grace for in-flight SaveDataEvent
	local data = playerData[player.UserId]
	if data then
		pendingSave[player.UserId] = nil
		local success = savePlayerDataToStore(player.UserId, data, player.Name)
		if not success and not RunService:IsStudio() then
			warn("Failed final save for player " .. player.Name)
		end
		dirtyPlayers[player.UserId] = nil
		playerData[player.UserId] = nil
	end
	loadingPlayers[player.UserId] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local userId = player.UserId
		local data = playerData[userId]
		if data then
			pendingSave[userId] = nil
			local success = savePlayerDataToStore(userId, data, player.Name)
			if not success and not RunService:IsStudio() then
				warn("Failed shutdown save for player " .. player.Name)
			end
			dirtyPlayers[userId] = nil
		end
	end
end)

-- Why: /resetrolls is the "start-anew" command used before launch. Every player field
-- is wiped to defaults so no stale progression leaks into the fresh session.
-- Server-core is repopulated via loadPlayerData (which runs ReconcileStatsToLevel)
-- so Points are always authoritative from the first snapshot after the reset.
local function resetAllPlayers(invoker)
	local freshDefaults = buildDefaultData()

	for userId, data in pairs(playerData) do
		-- Overwrite every field rather than selectively zeroing to avoid silent
		-- leaks when new fields are added in the future.
		data.rollCount    = 0
		data.level        = 1
		data.coins        = 0
		data.inventory    = {}
		data.combat       = {}
		data.boosterPacks = {}
		data.items        = PlayerStateConstants.GetDefaultItems()
		data.stats        = table.clone(freshDefaults.stats)
		dirtyPlayers[userId] = true

		-- Mirror full reset into server-core so point reconciliation is immediate.
		local numericUserId = tonumber(userId)
		if numericUserId then
			pcall(ServerStateManager.loadPlayerData, numericUserId, data)
			-- Fire StatsUpdatedEvent so Profile UI reflects reset points immediately
			-- without the player needing to re-open the profile panel.
			pcall(ServerStateManager.syncStatsToPlayer, numericUserId)
		end

		pcall(tryPersistPlayerData, userId, userId)

		-- Send a complete reconciled snapshot so the client UI reflects the reset
		-- without requiring a rejoin.
		local resetPlayer = Players:GetPlayerByUserId(numericUserId)
		if resetPlayer then
			local reconciledStats = numericUserId and ServerStateManager.getStats(numericUserId) or data.stats
			local resetSnapshot = {
				inventory    = data.inventory,
				combat       = data.combat,
				rollCount    = data.rollCount,
				level        = data.level,
				coins        = data.coins,
				boosterPacks = data.boosterPacks,
				items        = data.items,
				stats        = reconciledStats or data.stats,
			}
			pcall(saveEvent.FireClient, saveEvent, resetPlayer, resetSnapshot)
		end
	end

	local invokerName = "server"
	if invoker and invoker.Name then
		invokerName = invoker.Name
	end
	print("[SaveManager] ResetAllPlayers called by", invokerName)
end

-- Export SaveManager as a module
local SaveManager = {}
SaveManager.playerData = playerData
SaveManager.persistPlayerData = persistPlayerData
SaveManager.tryPersistPlayerData = tryPersistPlayerData
SaveManager.buildDefaultData = buildDefaultData
SaveManager.getEconomyState = getEconomyState
SaveManager.executeEconomyDelta = executeEconomyDelta
SaveManager.ResetAllPlayers = resetAllPlayers
return SaveManager
