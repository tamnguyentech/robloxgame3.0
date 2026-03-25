-- InventoryUIController.luau
-- DEPRECATED: This module is no longer used.
-- All inventory UI functionality has been moved to InventoryController.client.luau
-- Kept for backwards compatibility only.

local InventoryUIController = {}

function InventoryUIController.Setup(_contentFrame)
	-- No-op: Inventory UI is managed directly by InventoryController.client.luau
end

function InventoryUIController.GetInventoryContainer()
	return nil
end

return InventoryUIController
