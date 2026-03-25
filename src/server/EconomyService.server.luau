local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EconomyProtocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EconomyProtocol"))
local EconomyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EconomyCatalog"))
local BoosterBalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BoosterBalanceConfig"))
local BalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))
local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local AutoRollRuntime = require(script.Parent:WaitForChild("AutoRollRuntime"))
local PlayerStatsService = require(script.Parent:WaitForChild("PlayerStatsService"))
local ServerStateManager = require(script.Parent:WaitForChild("core"):WaitForChild("ServerStateManager"))
local PlayerStateEvents = require(script.Parent:WaitForChild("core"):WaitForChild("state"):WaitForChild("PlayerStateEvents"))
local saveManagerBridge = ServerStorage:WaitForChild("SaveManagerBridge")

local RARITY_ORDER = {"Common", "Uncommon", "Rare", "Epic", "Legendary"}

local function ensureRemoteFolder()
	local folder = ReplicatedStorage:FindFirstChild(EconomyProtocol.Remotes.FolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = EconomyProtocol.Remotes.FolderName
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureRemoteFunction(folder, remoteName)
	local remote = folder:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteFunction") then
		return remote
	end
	if remote then
		remote:Destroy()
	end
	remote = Instance.new("RemoteFunction")
	remote.Name = remoteName
	remote.Parent = folder
	return remote
end

local remotesFolder = ensureRemoteFolder()
local requestRemote = ensureRemoteFunction(remotesFolder, EconomyProtocol.Remotes.Request)

local function bridgeCall(action, payload)
	local ok, a, b = pcall(function()
		return saveManagerBridge:Invoke(action, payload)
	end)
	if not ok then
		return false, tostring(a)
	end
	return a, b
end

local function clampWholeNumber(value, minValue, maxValue, defaultValue)
	local n = math.floor(tonumber(value) or defaultValue or minValue)
	return math.max(minValue, math.min(maxValue, n))
end

local function pickRarityFromRates(rates)
	local totalWeight = 0
	for _, rarity in ipairs(RARITY_ORDER) do
		totalWeight += math.max(0, tonumber(rates and rates[rarity]) or 0)
	end

	if totalWeight <= 0 then
		return "Common"
	end

	local roll = math.random() * totalWeight
	local running = 0
	for _, rarity in ipairs(RARITY_ORDER) do
		running += math.max(0, tonumber(rates and rates[rarity]) or 0)
		if roll <= running then
			return rarity
		end
	end

	return "Common"
end

local function pickCardForRarity(rarity)
	local function isRollEligible(cardId)
		local data = CardDatabase.GetCardData(cardId)
		return not (
			data and (
				data.Rarity == "God" or
				data.Rarity == "Transcendent" or
				data.Category == "NPC"
			)
		)
	end

	local pool = {}
	for _, cardRef in ipairs(CardDatabase.GetAllCardIdsSorted()) do
		local parsed = CardDatabase.ParseCardReference(cardRef)
		local resolvedId = (parsed and parsed.BaseCardId) or cardRef
		local data = CardDatabase.GetCardData(resolvedId)
		if data and data.Rarity == rarity and isRollEligible(resolvedId) then
			table.insert(pool, resolvedId)
		end
	end

	if #pool == 0 then
		for _, cardRef in ipairs(CardDatabase.GetAllCardIdsSorted()) do
			local parsed = CardDatabase.ParseCardReference(cardRef)
			local resolvedId = (parsed and parsed.BaseCardId) or cardRef
			if isRollEligible(resolvedId) then
				table.insert(pool, resolvedId)
			end
		end
	end

	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

local function rollPackRewards(pack, openCount)
	local rewards = {}
	local rates = pack.RarityRates or BoosterBalanceConfig.DefaultRarityRates
	local cardsPerOpen = math.max(1, math.floor(pack.CardsPerOpen or BoosterBalanceConfig.DefaultCardsPerOpen))

	for _ = 1, openCount do
		for _ = 1, cardsPerOpen do
			local rarity = pickRarityFromRates(rates)
			local cardId = pickCardForRarity(rarity)
			if cardId then
				table.insert(rewards, cardId)
			end
		end
	end

	return rewards
end

local function fail(reason)
	return {
		ok = false,
		reason = reason,
	}
end

local function success(state, extra)
	local out = {
		ok = true,
		state = state,
	}
	if type(extra) == "table" then
		for k, v in pairs(extra) do
			out[k] = v
		end
	end
	return out
end

requestRemote.OnServerInvoke = function(player, request)
	if type(request) ~= "table" then
		return fail("InvalidRequest")
	end

	local actionType = request.actionType
	local payload = request.payload
	if type(actionType) ~= "string" or actionType == "" then
		return fail("InvalidActionType")
	end

	if actionType == EconomyProtocol.ActionType.GetState then
		local ok, stateOrReason = bridgeCall("GetEconomyState", player.UserId)
		if not ok then
			return fail(stateOrReason)
		end
		return success(stateOrReason)
	end

	if actionType == EconomyProtocol.ActionType.BuyPack then
		local packId = payload and payload.packId
		local amount = clampWholeNumber(payload and payload.amount, 1, 20, 1)
		local pack = EconomyCatalog.GetPack(packId)
		if not pack then
			return fail("PackNotFound")
		end

		local totalCost = math.max(0, math.floor(tonumber(pack.Price) or 0)) * amount
		local ok, stateOrReason = bridgeCall("ExecuteEconomyDelta", {
			userId = player.UserId,
			coinsDelta = -totalCost,
			boosterPacksDelta = {
				[packId] = amount,
			},
		})
		if not ok then
			return fail(stateOrReason)
		end
		return success(stateOrReason)
	end

	if actionType == EconomyProtocol.ActionType.OpenPack then
		local packId = payload and payload.packId
		local amount = clampWholeNumber(payload and payload.amount, 1, 5, 1)
		local pack = EconomyCatalog.GetPack(packId)
		if not pack then
			return fail("PackNotFound")
		end

		local gotState, stateOrReason = bridgeCall("GetEconomyState", player.UserId)
		if not gotState then
			return fail(stateOrReason)
		end
		local ownedCount = math.max(0, math.floor(tonumber(stateOrReason.boosterPacks and stateOrReason.boosterPacks[packId]) or 0))
		if ownedCount < amount then
			return fail("NotEnoughPacks")
		end

		local rewards = rollPackRewards(pack, amount)
		if #rewards == 0 then
			return fail("NoRewardCardsConfigured")
		end

		local ok, state = bridgeCall("ExecuteEconomyDelta", {
			userId = player.UserId,
			boosterPacksDelta = {
				[packId] = -amount,
			},
			grantCards = rewards,
		})
		if not ok then
			return fail(state)
		end
		return success(state, {
			grantedCards = rewards,
		})
	end

	if actionType == EconomyProtocol.ActionType.BuyItem then
		local itemId = payload and payload.itemId
		local amount = clampWholeNumber(payload and payload.amount, 1, 50, 1)
		local offer = EconomyCatalog.GetItemOffer(itemId)
		if not offer then
			return fail("ItemNotFound")
		end

		local effect = offer.Effect or {}

		-- Dev/test fast-path: SetFoilChance items apply instantly on purchase.
		-- Why: These items exist purely for visual testing; they should not clutter
		-- the player's item bag — they deduct 1 coin and mutate FoilChance directly.
		if effect.type == "SetFoilChance" then
			local totalCost = math.max(0, math.floor(tonumber(offer.Price) or 0)) * amount
			local ok, state = bridgeCall("ExecuteEconomyDelta", {
				userId = player.UserId,
				coinsDelta = -totalCost,
			})
			if not ok then
				return fail(state)
			end
			-- Write the new FoilChance into the live server-core state and push
			-- it to the client so the inventory foil updates without a rejoin.
			local currentStats = ServerStateManager.getStats(player.UserId)
			currentStats.FoilChance = math.max(0, math.floor(tonumber(effect.value) or 0))
			local newStats = ServerStateManager.setStats(player.UserId, currentStats)
			PlayerStateEvents.SyncStatsToPlayer(player.UserId, newStats)
			return success(state)
		end

		local grantAmount = math.max(1, math.floor(tonumber(offer.GrantAmount) or 1)) * amount
		local totalCost = math.max(0, math.floor(tonumber(offer.Price) or 0)) * amount
		local ok, state = bridgeCall("ExecuteEconomyDelta", {
			userId = player.UserId,
			coinsDelta = -totalCost,
			itemsDelta = {
				[itemId] = grantAmount,
			},
		})
		if not ok then
			return fail(state)
		end
		return success(state)
	end

	if actionType == EconomyProtocol.ActionType.UseItem then
		local itemId = payload and payload.itemId
		local amount = clampWholeNumber(payload and payload.amount, 1, 10, 1)
		local offer = EconomyCatalog.GetItemOffer(itemId)
		if not offer then
			return fail("ItemNotFound")
		end

		local ok, state = bridgeCall("ExecuteEconomyDelta", {
			userId = player.UserId,
			itemsDelta = {
				[itemId] = -amount,
			},
		})
		if not ok then
			return fail(state)
		end

		if itemId == "AutoRoll2x20s" then
			local effect = offer.Effect or {}
			local duration = math.max(1, math.floor(tonumber(effect.duration) or 20)) * amount
			AutoRollRuntime.AddAutoRollBuff(player.UserId, tonumber(effect.multiplier) or 2, duration)
			return success(state, {
				effect = {
					itemId = itemId,
					type = "AutoRoll",
					multiplier = tonumber(effect.multiplier) or 2,
					duration = duration,
				},
			})
		end

		if itemId == "LuckPotion" then
			local effect = offer.Effect or {}
			local potionDuration = PlayerStatsService.GetPotionDuration(player)
			local duration = BalanceConfig.CalculatePotionDurationSeconds((tonumber(effect.duration) or 180) * amount, potionDuration)
			local luckBonus = math.max(0, math.floor(tonumber(effect.luckBonus) or 0))
			AutoRollRuntime.AddLuckBuff(player.UserId, luckBonus, duration)
			return success(state, {
				effect = {
					itemId = itemId,
					type = "Luck",
					luckBonus = luckBonus,
					duration = duration,
				},
			})
		end

		if itemId == "FoilChancePotion" then
			local effect = offer.Effect or {}
			local potionDuration = PlayerStatsService.GetPotionDuration(player)
			local duration = BalanceConfig.CalculatePotionDurationSeconds((tonumber(effect.duration) or 180) * amount, potionDuration)
			local foilChanceBonus = math.max(0, math.floor(tonumber(effect.foilChanceBonus) or 0))
			AutoRollRuntime.AddFoilChanceBuff(player.UserId, foilChanceBonus, duration)
			return success(state, {
				effect = {
					itemId = itemId,
					type = "FoilChance",
					foilChanceBonus = foilChanceBonus,
					duration = duration,
				},
			})
		end

		return success(state)
	end

	if actionType == EconomyProtocol.ActionType.SellCards then
		-- Accepts { cards = { [cardRef] = count } } — dict format allows the
		-- client to send one entry per unique card type rather than one per unit,
		-- making bulk sells efficient without inflating the RemoteFunction payload.
		local cardsPayload = (payload and type(payload.cards) == "table") and payload.cards or {}
		local MAX_SELL_PER_REQUEST = 200  -- hard cap to prevent abuse
		local consumeCards = {}
		local totalValue   = 0

		for cardRef, count in pairs(cardsPayload) do
			if type(cardRef) == "string" and cardRef ~= "" then
				local sellCount = math.max(0, math.min(
					math.floor(tonumber(count) or 0),
					MAX_SELL_PER_REQUEST
				))
				if sellCount > 0 then
					local parsed    = CardDatabase.ParseCardReference(cardRef)
					local baseId    = parsed and parsed.BaseCardId or cardRef
					local unitValue = math.max(0, math.floor(EconomyCatalog.GetCardSellValue(baseId) or 0))
					for _ = 1, sellCount do
						table.insert(consumeCards, cardRef)
						totalValue = totalValue + unitValue
					end
				end
			end
			-- Abort early if the client sent a maliciously large request.
			if #consumeCards > MAX_SELL_PER_REQUEST then
				return fail("TooManyCardsInSell")
			end
		end

		if #consumeCards == 0 or totalValue <= 0 then
			return fail("NoSellableCards")
		end

		local ok, state = bridgeCall("ExecuteEconomyDelta", {
			userId      = player.UserId,
			coinsDelta  = totalValue,
			consumeCards = consumeCards,
		})
		if not ok then
			return fail(state)
		end
		return success(state, {
			consumedCards = state.consumedCards or consumeCards,
			soldCoins     = totalValue,
		})
	end

	if actionType == EconomyProtocol.ActionType.BuyDirectCard then
		local cardId = payload and payload.cardId
		local amount = clampWholeNumber(payload and payload.amount, 1, 10, 1)
		local offer = EconomyCatalog.GetDirectCardOffer(cardId)
		if not offer then
			return fail("DirectCardNotFound")
		end

		local grantAmount = math.max(1, math.floor(tonumber(offer.GrantAmount) or 1)) * amount
		local totalCost = math.max(0, math.floor(tonumber(offer.Price) or 0)) * amount
		local grants = {}
		for _ = 1, grantAmount do
			table.insert(grants, cardId)
		end

		local ok, state = bridgeCall("ExecuteEconomyDelta", {
			userId = player.UserId,
			coinsDelta = -totalCost,
			grantCards = grants,
		})
		if not ok then
			if state == "AlreadyOwnedUniqueCard" then
				return fail("AlreadyOwnedTranscendent")
			end
			return fail(state)
		end
		return success(state, {
			grantedCards = grants,
		})
	end

	return fail("UnsupportedAction")
end
