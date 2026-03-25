local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local IdleRollProtocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IdleRollProtocol"))
local BalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))
local AutoRollRuntime = require(script.Parent:WaitForChild("AutoRollRuntime"))
local PlayerStatsService = require(script.Parent:WaitForChild("PlayerStatsService"))

local saveManagerBridge = ServerStorage:WaitForChild("SaveManagerBridge")

-- Use values from BalanceConfig for easy patching
local BASE_AUTO_ROLL_INTERVAL = BalanceConfig.BASE_AUTO_ROLL_INTERVAL
local TICK_INTERVAL = BalanceConfig.TICK_INTERVAL

local elapsedByUserId = {}
local autoRollEnabledByUserId = {}

local function ensureRemoteFolder()
	local folder = ReplicatedStorage:FindFirstChild(IdleRollProtocol.Remotes.FolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = IdleRollProtocol.Remotes.FolderName
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureRemoteEvent(folder, remoteName)
	local remote = folder:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	if remote then
		remote:Destroy()
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = folder
	return remote
end

local remotesFolder = ensureRemoteFolder()
local rewardEvent = ensureRemoteEvent(remotesFolder, IdleRollProtocol.Remotes.RewardEvent)
local controlEvent = ensureRemoteEvent(remotesFolder, IdleRollProtocol.Remotes.ControlEvent)

controlEvent.OnServerEvent:Connect(function(player, payload)
	if not (player and player:IsA("Player")) then
		return
	end

	if type(payload) ~= "table" then
		return
	end

	local enabled = payload.enabled
	if type(enabled) ~= "boolean" then
		return
	end

	autoRollEnabledByUserId[player.UserId] = enabled
	if not enabled then
		-- Avoid catch-up bursts when re-enabling after long pauses.
		elapsedByUserId[player.UserId] = 0
	end
end)

-- Luck affects ONLY card rarity (God/Mythic/Legendary/Rare/Uncommon). Foil chance
-- and foil tier are controlled solely by the FoilChance stat; no cross-coupling.
local function pickIdleRollRarity(totalLuck)
	local adjustedRates = BalanceConfig.GetRarityRatesWithLuck(totalLuck)
	
	local roll = math.random() * 100
	local running = 0
	for _, entry in ipairs({
		{rarity = "God", weight = adjustedRates.God},
		{rarity = "Mythic", weight = adjustedRates.Mythic},
		{rarity = "Legendary", weight = adjustedRates.Legendary},
		{rarity = "Rare", weight = adjustedRates.Rare},
		{rarity = "Uncommon", weight = adjustedRates.Uncommon},
	}) do
		running += entry.weight
		if roll <= running then
			return entry.rarity
		end
	end
	return "Uncommon"
end

local function pickIdleRollCardId(totalLuck)
	local rarity = pickIdleRollRarity(totalLuck)
	local pool = {}
	for _, cardId in ipairs(CardDatabase.GetCardsByRarity(rarity)) do
		local data = CardDatabase.GetCardData(cardId)
		if data and data.Category ~= "NPC" then
			table.insert(pool, cardId)
		end
	end
	if #pool == 0 then
		for _, cardId in ipairs(CardDatabase.GetAllCardIdsSorted()) do
			local data = CardDatabase.GetCardData(cardId)
			if data and data.Category ~= "NPC" then
				table.insert(pool, cardId)
			end
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

local function grantIdleCard(player, cardId)
	-- CalculateFoilChancePercent returns a percentage value (e.g. 0.25 for 0.25%).
	-- Divide by 100 to convert to a [0,1] probability before comparing with math.random().
	-- math.random() with no args is uniform [0,1) — correct for fractional probabilities.
	local foilChance = PlayerStatsService.GetFoilChance(player)
	local foilPercent = BalanceConfig.CalculateFoilChancePercent(foilChance)
	local isFoiled = math.random() < (foilPercent / 100)
	-- Roll tier via weighted probability — all tiers always rollable, no threshold gates.
	-- FoilChance points shift weight toward rarer tiers as a reward, not a requirement.
	local foilTier = BalanceConfig.RollFoilTier(foilChance)
	local finalCardRef = isFoiled and (cardId .. "::Foil::" .. foilTier) or cardId
	
	local ok, success, stateOrReason = pcall(function()
		return saveManagerBridge:Invoke("ExecuteEconomyDelta", {
			userId = player.UserId,
			grantCards = {finalCardRef},
			rollCountDelta = 1,
		})
	end)
	if not ok then
		warn("Idle roll grant failed: " .. tostring(success))
		return
	end

	if success == false then
		warn("Idle roll grant rejected: " .. tostring(stateOrReason))
		return
	end

	local state = (type(stateOrReason) == "table") and stateOrReason or nil

	-- Include reconciled stats in every reward so the client Profile UI updates
	-- Points correctly even if StatsUpdatedEvent arrives out of order or is missed.
	rewardEvent:FireClient(player, {
		cardId    = cardId,
		rollCount = state and state.rollCount,
		level     = state and state.level,
		stats     = state and state.stats,
	})
end

task.spawn(function()
	while true do
		task.wait(TICK_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			if autoRollEnabledByUserId[player.UserId] == false then
				elapsedByUserId[player.UserId] = 0
				continue
			end

			local multiplier = AutoRollRuntime.GetAutoRollMultiplier(player.UserId)
			-- Use BalanceConfig for roll speed calculation
			local rollSpeed = PlayerStatsService.GetRollSpeed(player)
			local speedMultiplier = BalanceConfig.CalculateRollSpeedMultiplier(rollSpeed)
			local interval = (BASE_AUTO_ROLL_INTERVAL / multiplier) * speedMultiplier
			local currentElapsed = (elapsedByUserId[player.UserId] or 0) + TICK_INTERVAL

			while currentElapsed >= interval do
				currentElapsed -= interval
				-- Luck (base + potion bonus) affects card rarity only. FoilChance is separate.
				local luck = PlayerStatsService.GetLuck(player)
				local cardId = pickIdleRollCardId(luck)
				if cardId then
					grantIdleCard(player, cardId)
				end
			end

			elapsedByUserId[player.UserId] = currentElapsed
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	elapsedByUserId[player.UserId] = nil
	autoRollEnabledByUserId[player.UserId] = nil
	AutoRollRuntime.ClearPlayer(player.UserId)
end)
