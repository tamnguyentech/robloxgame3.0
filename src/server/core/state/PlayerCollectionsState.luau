-- Why: Group inventory, combat-adjacent collections, items, and booster-pack mutations by domain.
-- How: Use these helpers whenever collection state needs to change on the server.

local PlayerStateStore = require(script.Parent:WaitForChild("PlayerStateStore"))

local PlayerCollectionsState = {}

-- Why: Convert counters to safe non-negative integers in one place.
-- How: Pass any numeric-like amount and this returns a floored integer with a floor of zero when applied.
local function toCountDelta(value)
	return math.floor(tonumber(value) or 0)
end

-- Why: Reject invalid card ids before they can corrupt the inventory list.
-- How: Pass any candidate card id and this returns true only for non-empty strings.
local function isValidCardId(cardId)
	return type(cardId) == "string" and cardId ~= ""
end

-- Why: Add one card ref to the player's inventory while preserving insertion order.
-- How: Pass a userId and a validated card id; this returns true on success and false on invalid input.
function PlayerCollectionsState.AddCardToInventory(userId, cardId)
	if not isValidCardId(cardId) then
		return false
	end

	local state = PlayerStateStore.GetState(userId)
	table.insert(state.inventory, cardId)
	return true
end

-- Why: Support batch card grants without duplicating validation logic at each caller.
-- How: Pass a userId and an array of card ids; this returns the number of successfully added cards.
function PlayerCollectionsState.AddCardsToInventory(userId, cardIds)
	if type(cardIds) ~= "table" then
		return 0
	end

	local state = PlayerStateStore.GetState(userId)
	local added = 0
	for _, cardId in ipairs(cardIds) do
		if isValidCardId(cardId) then
			table.insert(state.inventory, cardId)
			added += 1
		end
	end

	return added
end

-- Why: Keep keyed booster-pack counters consistent and tolerant of future pack ids.
-- How: Pass a userId, a pack id string, and a delta; this returns the new stored count.
function PlayerCollectionsState.AddBoosterPack(userId, packId, amount)
	local state = PlayerStateStore.GetState(userId)
	if type(packId) ~= "string" or packId == "" then
		return 0
	end
	if state.boosterPacks[packId] == nil then
		state.boosterPacks[packId] = 0
	end
	state.boosterPacks[packId] = math.max(0, state.boosterPacks[packId] + toCountDelta(amount))
	return state.boosterPacks[packId]
end

-- Why: Keep keyed item counters consistent and tolerant of future item ids.
-- How: Pass a userId, an item id string, and a delta; this returns the new stored count.
function PlayerCollectionsState.AddItem(userId, itemId, amount)
	local state = PlayerStateStore.GetState(userId)
	if type(itemId) ~= "string" or itemId == "" then
		return 0
	end
	if state.items[itemId] == nil then
		state.items[itemId] = 0
	end
	state.items[itemId] = math.max(0, state.items[itemId] + toCountDelta(amount))
	return state.items[itemId]
end

return PlayerCollectionsState
