-- DeviceContext.luau
-- Centralized device detection and responsive constants for mobile UI compatibility.
-- Single source of truth: all UI reads from here. PC unchanged when isMobile == false.

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local DeviceContext = {}

-- Cached values (lazy init)
local _isMobile = nil
local _safeInsets = { top = 0, bottom = 0, left = 0, right = 0 }
local _viewportSize = Vector2.new(1920, 1080)
local _insetsInitialized = false

-- Get current viewport size from PlayerGui
local function getViewportSize()
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		local mainUI = playerGui:FindFirstChild("MainUI")
		if mainUI and mainUI:IsA("GuiObject") then
			local absSize = mainUI.AbsoluteSize
			if absSize and absSize.X > 0 then
				return absSize
			end
		end
	end
	return Vector2.new(1920, 1080)
end

-- Initialize safe insets from GuiService if available
local function initSafeInsets()
	if _insetsInitialized then
		return
	end
	_insetsInitialized = true
	local ok, result = pcall(function()
		-- GuiService:GetGuiInset() returns Vector2 for top-bar offset
		if GuiService.GetGuiInset then
			local inset = GuiService:GetGuiInset()
			if inset and inset.Y > 0 then
				_safeInsets.top = inset.Y
			end
		end
		-- SafeZoneOffsets for notch/home indicator (if available)
		if GuiService.GetSafeZoneOffsets then
			local insets = GuiService:GetSafeZoneOffsets()
			if insets then
				_safeInsets.top = math.max(_safeInsets.top, insets.Top or 0)
				_safeInsets.bottom = insets.Bottom or 0
				_safeInsets.left = insets.Left or 0
				_safeInsets.right = insets.Right or 0
			end
		end
	end)
	if not ok then
		-- Older Roblox version; keep defaults
	end
end

-- Exported: is this a mobile/touch-primary device?
function DeviceContext.getIsMobile()
	if _isMobile == nil then
		local viewport = getViewportSize()
		-- TouchEnabled is true on mobile. Use viewport heuristic to avoid treating
		-- PC with touchscreen as mobile. Mobile: touch + narrow viewport or no mouse.
		if not UserInputService.TouchEnabled then
			_isMobile = false
		elseif not UserInputService.MouseEnabled then
			_isMobile = true
		else
			-- Touch + mouse: PC touchscreen or tablet. Narrow viewport = mobile layout.
			_isMobile = viewport.X <= 900 or viewport.Y <= 600
		end
	end
	return _isMobile
end

-- Exported: minimum touch target size in px (Apple HIG: 44pt)
function DeviceContext.getTouchTargetMin()
	return DeviceContext.getIsMobile() and 44 or 32
end

-- Exported: safe area insets { top, bottom, left, right }
function DeviceContext.getSafeInsets()
	initSafeInsets()
	return {
		top = _safeInsets.top,
		bottom = _safeInsets.bottom,
		left = _safeInsets.left,
		right = _safeInsets.right,
	}
end

-- Exported: scale factor for large fixed elements (viewport width / 1920), clamped
function DeviceContext.getScaleFactor()
	_viewportSize = getViewportSize()
	local scale = _viewportSize.X / 1920
	return math.clamp(scale, 0.5, 1.2)
end

-- Exported: current viewport size (updates on read; call from layout code)
function DeviceContext.getViewportSize()
	_viewportSize = getViewportSize()
	return _viewportSize
end

-- Bind to safe zone changes (call once from RPGHUDController or UIUtility)
function DeviceContext.bindSafeZoneChanges(callback)
	initSafeInsets()
	local ok, conn = pcall(function()
		return GuiService:GetPropertyChangedSignal("SafeZoneOffsetsChanged"):Connect(function()
			_insetsInitialized = false
			initSafeInsets()
			if callback then
				callback()
			end
		end)
	end)
	if ok and conn then
		return conn
	end
	return nil
end

return DeviceContext
