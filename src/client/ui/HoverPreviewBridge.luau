-- HoverPreviewBridge.luau
-- Module-singleton that holds the initialized HoverPreview API so any client
-- module can trigger the shared preview panel without needing a direct require
-- chain back to InventoryController.
--
-- Usage:
--   Writer (InventoryController):  HoverPreviewBridge.set(hoverPreviewApi)
--   Reader (ShopUIController etc): local api = HoverPreviewBridge.get()

local HoverPreviewBridge = {}

local _api = nil

-- Register the initialized HoverPreview API.  Call this once after HoverPreview.Init().
function HoverPreviewBridge.set(api)
	_api = api
end

-- Returns the shared API, or nil if it has not been registered yet.
-- Why: Callers check for nil so they gracefully skip hover effects before the
-- InventoryController script has finished its initialization phase.
function HoverPreviewBridge.get()
	return _api
end

return HoverPreviewBridge
