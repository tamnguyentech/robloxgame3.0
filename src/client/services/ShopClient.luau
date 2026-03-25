local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EconomyProtocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EconomyProtocol"))
local EconomyClient = require(script.Parent:WaitForChild("EconomyClient"))

local ShopClient = {}

function ShopClient.BuyItem(itemId, amount)
    local ok, responseOrErr = EconomyClient.Request(EconomyProtocol.ActionType.BuyItem, {
        itemId = itemId,
        amount = amount or 1,
    })
    if not ok then
        warn("[ShopClient] Failed to buy item: " .. tostring(responseOrErr))
        return false, "Failed"
    end
    return true, responseOrErr
end

function ShopClient.BuyDirectCard(cardId, amount)
    local ok, responseOrErr = EconomyClient.Request(EconomyProtocol.ActionType.BuyDirectCard, {
        cardId = cardId,
        amount = amount or 1,
    })
    if not ok then
        warn("[ShopClient] Failed to buy card: " .. tostring(responseOrErr))
        return false, "Failed"
    end
    return true, responseOrErr
end

function ShopClient.UseItem(itemId, amount)
    local ok, responseOrErr = EconomyClient.Request(EconomyProtocol.ActionType.UseItem, {
        itemId = itemId,
        amount = amount or 1,
    })
    if not ok then
        warn("[ShopClient] Failed to use item: " .. tostring(responseOrErr))
        return false, "Failed"
    end
    return true, responseOrErr
end

function ShopClient.SellCards(cards)
    local ok, responseOrErr = EconomyClient.Request(EconomyProtocol.ActionType.SellCards, {
        cards = cards,
    })
    if not ok then
        warn("[ShopClient] Failed to sell cards: " .. tostring(responseOrErr))
        return false, tostring(responseOrErr)
    end
    return true, responseOrErr
end

return ShopClient
