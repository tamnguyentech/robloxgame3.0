-- ShopUI.client.luau
-- Shop UI module for RPG HUD

local ShopUIController = require(script.Parent.shop:WaitForChild("ShopUIController"))

local ShopUI = {}

function ShopUI.Setup(contentFrame)
	return ShopUIController.Setup(contentFrame)
end

return ShopUI
