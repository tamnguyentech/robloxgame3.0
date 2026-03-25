local TweenService   = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDatabase       = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local DeviceContext      = require(script.Parent.Parent.core:WaitForChild("DeviceContext"))
local HoloFoilController        = require(script.Parent.Parent.ui.effects:WaitForChild("HoloFoilController"))
local LightningOverlayController = require(script.Parent.Parent.ui.effects:WaitForChild("LightningOverlayController"))
local UltraRareTextEffect       = require(script.Parent.Parent.ui.effects:WaitForChild("UltraRareTextEffect"))
local RainbowBorderStroke       = require(script.Parent.Parent.ui.effects:WaitForChild("RainbowBorderStroke"))

local ShopRenderer = {}

-- Dimensions: CARD_HEIGHT raised from 248 to 270 so internal layout no longer overlaps.
-- All absolute Y positions inside CreateProductCard are recalculated from this.
local CARD_WIDTH  = 190
local CARD_HEIGHT = 270

local function getCardWidth()
	return DeviceContext.getIsMobile() and 140 or CARD_WIDTH
end

local function getCardHeight()
	return DeviceContext.getIsMobile() and 200 or CARD_HEIGHT
end

-- Gallery-specific constants
local GALLERY_TILE_PAD       = 14   -- gap between gallery tiles (and edge padding)
local GALLERY_HEADER_H       = 48   -- height of the "Border Tier Gallery" header strip
local GALLERY_BASE_CARD      = "mastereduigoku"
local GALLERY_LIGHTNING_CARD = "sinbad"  -- separate from base: Lightning concept uses this
local GALLERY_TIER_ORDER     = { "Silver", "Gold", "Diamond", "Rainbow" }
local GALLERY_TIER_CONFIG    = {
	Silver  = { label = "Silver",  accent = Color3.fromRGB(210, 218, 232) },
	Gold    = { label = "Gold",    accent = Color3.fromRGB(255, 210, 60)  },
	Diamond = { label = "Diamond", accent = Color3.fromRGB(178, 224, 255) },
	Rainbow = { label = "Rainbow", accent = Color3.fromRGB(255, 160, 210) },
}

-- Concept tiles: gallery-only previews, not purchasable tiers.
-- Per SPEC_V1: UltraRare is intentionally absent from VALID_BORDER_TIERS in
-- CardDatabase so it can never pollute inventory/save data.
-- foilTier: use HoloFoilController with this tier; nil = UltraRareTextEffect path.
local GALLERY_CONCEPT_CONFIG = {
	{
		key     = "UltraRare",
		label   = "Ultra Rare",
		accent  = Color3.fromRGB(235, 240, 255),
		sub     = "Concept | Preview Only",
		badge   = "* Concept Preview",
		cardRef = GALLERY_BASE_CARD .. "::Foil::Rainbow",
		foilTier = nil,
	},
	{
		key         = "Lightning",
		label       = "Lightning",
		accent      = Color3.fromRGB(180, 220, 255),
		sub         = "Concept | Divine Storm",
		badge       = "* Concept Preview",
		cardRef     = GALLERY_LIGHTNING_CARD,
		foilTier    = nil,
		useLightning = true,
	},
	{
		key     = "Corrupted",
		label   = "Ember Vein",
		accent  = Color3.fromRGB(255, 100, 50),
		sub     = "Concept | Volcanic",
		badge   = "* Concept Preview",
		cardRef = GALLERY_BASE_CARD .. "::Foil::Corrupted",
		foilTier = "Corrupted",
	},
}

-- ── Shared card styling ───────────────────────────────────────────────────────
local function styleCard(frame, accent)
	frame.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
	frame.BorderSizePixel  = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Thickness    = 2
	stroke.Color        = accent
	stroke.Transparency = 0.15
	stroke.Parent       = frame

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 45, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 26, 36)),
	})
	gradient.Rotation = 90
	gradient.Parent   = frame
end

-- Rainbow-animated stroke for concept gallery tiles (UIGradient parented to UIStroke).
local function styleCardRainbow(frame)
	frame.BackgroundColor3 = Color3.fromRGB(28, 31, 42)
	frame.BorderSizePixel  = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Name           = "RainbowConceptStroke"
	stroke.Thickness      = 2.8
	stroke.Color          = Color3.new(1, 1, 1)
	stroke.Transparency   = 0.06
	stroke.Parent         = frame
	RainbowBorderStroke.attach(stroke)

	local bgGrad = Instance.new("UIGradient")
	bgGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 45, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 26, 36)),
	})
	bgGrad.Rotation = 90
	bgGrad.Parent   = frame
end

-- ── Art box helper ─────────────────────────────────────────────────────────────
-- Why ScaleType.Fit + dark container: card art has many aspect ratios.  Fit
-- shows the full artwork without cropping (no important detail cut off) while
-- the dark container background fills any letterbox gap cleanly.
local function buildArtBox(parent, assetId, x, y, w, h)
	local box = Instance.new("Frame")
	box.Name                   = "ArtBox"
	box.Size                   = UDim2.fromOffset(w, h)
	box.Position               = UDim2.fromOffset(x, y)
	box.BackgroundColor3       = Color3.fromRGB(14, 16, 24)
	box.BackgroundTransparency = 0.18
	box.BorderSizePixel        = 0
	box.Parent                 = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = box

	local img = Instance.new("ImageLabel")
	img.Name                   = "ArtImage"
	img.Size                   = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image                  = assetId or ""
	img.ScaleType              = Enum.ScaleType.Fit  -- full art, no crop
	img.Parent                 = box

	return box
end

-- ── Public API ────────────────────────────────────────────────────────────────

function ShopRenderer.CreateCurrencyPanel(parent, currencyValue)
	local panel = Instance.new("Frame")
	panel.Name                   = "CurrencyPanel"
	panel.Size                   = UDim2.new(1, 0, 0, 54)
	panel.BackgroundColor3       = Color3.fromRGB(18, 20, 28)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel        = 0
	panel.Parent                 = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color        = Color3.fromRGB(255, 215, 120)
	stroke.Transparency = 0.2
	stroke.Parent       = panel

	local label = Instance.new("TextLabel")
	label.Name               = "CoinsLabel"
	label.Size               = UDim2.new(1, -24, 1, 0)
	label.Position           = UDim2.fromOffset(12, 0)
	label.BackgroundTransparency = 1
	label.TextXAlignment     = Enum.TextXAlignment.Left
	label.Font               = Enum.Font.GothamBold
	label.TextSize           = 20
	label.TextColor3         = Color3.fromRGB(255, 228, 130)
	label.Parent             = panel

	local function refresh()
		label.Text = string.format("Coins: %d", math.max(0, math.floor(currencyValue.Value)))
	end
	currencyValue:GetPropertyChangedSignal("Value"):Connect(refresh)
	refresh()
	return panel
end

function ShopRenderer.CreateTabBar(parent, tabs, onTabSelected)
	local tabBar = Instance.new("Frame")
	tabBar.Name                 = "ShopTabBar"
	tabBar.Size                 = UDim2.new(1, 0, 0, 48)
	tabBar.Position             = UDim2.fromOffset(0, 62)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent               = parent

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding       = UDim.new(0, 10)
	layout.SortOrder     = Enum.SortOrder.LayoutOrder
	layout.Parent        = tabBar

	local buttons = {}
	local tabBtnW = DeviceContext.getIsMobile() and 72 or 132
	for index, tab in ipairs(tabs) do
		local button = Instance.new("TextButton")
		button.Name              = tab.Id .. "Tab"
		button.Size              = UDim2.fromOffset(tabBtnW, math.max(48, DeviceContext.getTouchTargetMin()))
		button.LayoutOrder       = index
		button.BackgroundColor3  = Color3.fromRGB(38, 40, 54)
		button.Text              = tab.Label
		button.Font              = Enum.Font.GothamBold
		button.TextSize          = 16
		button.TextColor3        = Color3.new(1, 1, 1)
		button.AutoButtonColor   = false
		button.BorderSizePixel   = 0
		button.Parent            = tabBar

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = button

		local stroke = Instance.new("UIStroke")
		stroke.Thickness    = 2
		stroke.Color        = tab.Accent
		stroke.Transparency = 0.45
		stroke.Parent       = button

		buttons[tab.Id] = { Button = button, Stroke = stroke, Accent = tab.Accent }
		button.MouseButton1Click:Connect(function()
			onTabSelected(tab.Id)
		end)
	end

	local function setActive(tabId)
		for id, entry in pairs(buttons) do
			local isActive = id == tabId
			TweenService:Create(entry.Button, TweenInfo.new(0.15), {
				BackgroundColor3 = isActive
					and entry.Accent:lerp(Color3.fromRGB(24, 28, 40), 0.45)
					or  Color3.fromRGB(38, 40, 54),
			}):Play()
			TweenService:Create(entry.Stroke, TweenInfo.new(0.15), {
				Transparency = isActive and 0 or 0.45,
			}):Play()
		end
	end

	return { SetActive = setActive }
end

function ShopRenderer.CreateContentArea(parent)
	local contentArea = Instance.new("Frame")
	contentArea.Name                 = "ContentArea"
	contentArea.Size                 = UDim2.new(1, 0, 1, -118)
	contentArea.Position             = UDim2.fromOffset(0, 118)
	contentArea.BackgroundTransparency = 1
	contentArea.Parent               = parent
	return contentArea
end

-- CreateScrollTab now returns { scroll, grid }.
--
-- scroll : the root ScrollingFrame — store in tabFrames for show/hide.
-- grid   : inner Frame that owns the UIGridLayout — pass as parent to CreateProductCard.
--
-- Why the split: the scroll frame's outer UIListLayout arranges the gallery strip
-- (LayoutOrder 0) ABOVE the product grid (LayoutOrder 1), while the UIGridLayout
-- inside the grid wrapper lays out product cards in a normal tiled grid.
function ShopRenderer.CreateScrollTab(parent, tab)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name                  = tab.Id .. "Content"
	scroll.Size                  = UDim2.fromScale(1, 1)
	scroll.BackgroundColor3      = Color3.fromRGB(21, 24, 34)
	scroll.BackgroundTransparency = 0.08
	scroll.BorderSizePixel       = 0
	scroll.ScrollBarThickness    = 6
	scroll.CanvasSize            = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize   = Enum.AutomaticSize.Y
	scroll.Visible               = false
	scroll.Parent                = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = scroll

	-- Outer layout: stacks gallery section (0) then product grid (1) vertically.
	local outerList = Instance.new("UIListLayout")
	outerList.FillDirection = Enum.FillDirection.Vertical
	outerList.SortOrder     = Enum.SortOrder.LayoutOrder
	outerList.Padding       = UDim.new(0, 0)
	outerList.Parent        = scroll

	-- Grid wrapper: the actual tiled product card area.
	local gridWrapper = Instance.new("Frame")
	gridWrapper.Name                 = "ProductGrid"
	gridWrapper.Size                 = UDim2.new(1, 0, 0, 0)
	gridWrapper.AutomaticSize        = Enum.AutomaticSize.Y
	gridWrapper.BackgroundTransparency = 1
	gridWrapper.LayoutOrder          = 1
	gridWrapper.Parent               = scroll

	local cellPad = DeviceContext.getIsMobile() and 8 or 14
	local innerPad = Instance.new("UIPadding")
	innerPad.PaddingTop    = UDim.new(0, cellPad)
	innerPad.PaddingBottom = UDim.new(0, cellPad)
	innerPad.PaddingLeft   = UDim.new(0, cellPad)
	innerPad.PaddingRight  = UDim.new(0, cellPad)
	innerPad.Parent        = gridWrapper

	local grid = Instance.new("UIGridLayout")
	grid.CellSize    = UDim2.fromOffset(getCardWidth(), getCardHeight())
	grid.CellPadding = UDim2.fromOffset(cellPad, cellPad)
	grid.SortOrder   = Enum.SortOrder.LayoutOrder
	grid.Parent      = gridWrapper

	return { scroll = scroll, grid = gridWrapper }
end

-- Fixed product card layout.
-- Changes vs the previous version:
--   • Art preview uses ScaleType.Fit inside a dark rounded container (no crop).
--   • Price label and Buy button no longer overlap (fixed Y positions).
--   • CARD_HEIGHT increased to 270 to give all elements breathing room.
function ShopRenderer.CreateProductCard(parent, entry, onPurchase)
	local accent = entry.Accent or Color3.fromRGB(120, 140, 220)
	local cardW, cardH = getCardWidth(), getCardHeight()
	local scaleY = cardH / CARD_HEIGHT
	local card   = Instance.new("Frame")
	card.Name   = entry.Id
	card.Size   = UDim2.fromOffset(cardW, cardH)
	card.Parent = parent
	styleCard(card, accent)

	-- Title ── y 10, h 22
	local title = Instance.new("TextLabel")
	title.Name                   = "Title"
	title.Size                   = UDim2.new(1, -20, 0, math.floor(22 * scaleY))
	title.Position               = UDim2.fromOffset(10, math.floor(10 * scaleY))
	title.BackgroundTransparency = 1
	title.TextXAlignment         = Enum.TextXAlignment.Left
	title.Font                   = Enum.Font.GothamBold
	title.TextSize               = 15
	title.TextColor3             = Color3.new(1, 1, 1)
	title.TextTruncate           = Enum.TextTruncate.AtEnd
	title.Text                   = entry.Name
	title.Parent                 = card

	-- Kind badge ── y 34, h 16
	local kind = Instance.new("TextLabel")
	kind.Name                   = "Kind"
	kind.Size                   = UDim2.new(1, -20, 0, math.floor(16 * scaleY))
	kind.Position               = UDim2.fromOffset(10, math.floor(34 * scaleY))
	kind.BackgroundTransparency = 1
	kind.TextXAlignment         = Enum.TextXAlignment.Left
	kind.Font                   = Enum.Font.GothamMedium
	kind.TextSize               = 11
	kind.TextColor3             = accent
	kind.Text                   = tostring(entry.Kind or "")
	kind.Parent                 = card

	-- Art box ── y 54, h 120 (only when an image is supplied)
	local hasImage = type(entry.Image) == "string" and entry.Image ~= ""
	if hasImage then
		buildArtBox(card, entry.Image, 10, math.floor(54 * scaleY), cardW - 20, math.floor(120 * scaleY))
	end

	-- Description ── y 178 (with art) or y 54 (no art), h 40
	local descY = math.floor((hasImage and 178 or 54) * scaleY)
	local description = Instance.new("TextLabel")
	description.Name                   = "Description"
	description.Size                   = UDim2.new(1, -20, 0, math.floor(40 * scaleY))
	description.Position               = UDim2.fromOffset(10, descY)
	description.BackgroundTransparency = 1
	description.TextXAlignment         = Enum.TextXAlignment.Left
	description.TextYAlignment         = Enum.TextYAlignment.Top
	description.TextWrapped            = true
	description.Font                   = Enum.Font.Gotham
	description.TextSize               = 12
	description.TextColor3             = Color3.fromRGB(210, 214, 224)
	description.Text                   = entry.Description or ""
	description.Parent                 = card

	-- Price label ── y 222, h 18  (gold)
	local priceY = math.floor(222 * scaleY)
	local price = Instance.new("TextLabel")
	price.Name                   = "Price"
	price.Size                   = UDim2.new(1, -20, 0, math.floor(18 * scaleY))
	price.Position               = UDim2.fromOffset(10, priceY)
	price.BackgroundTransparency = 1
	price.TextXAlignment         = Enum.TextXAlignment.Left
	price.Font                   = Enum.Font.GothamBold
	price.TextSize               = 13
	price.TextColor3             = Color3.fromRGB(255, 224, 120)
	price.Text                   = string.format("%d Coins", math.max(0, math.floor(tonumber(entry.Price) or 0)))
	price.Parent                 = card

	-- Buy button ── min 44px height on mobile for touch target
	local buyH = math.max(24, DeviceContext.getTouchTargetMin())
	local buyY = math.max(priceY + math.floor(18 * scaleY) + 4, cardH - buyH - 8)
	local buyButton = Instance.new("TextButton")
	buyButton.Name             = "BuyButton"
	buyButton.Size             = UDim2.new(1, -20, 0, buyH)
	buyButton.Position         = UDim2.fromOffset(10, buyY)
	buyButton.BackgroundColor3 = accent
	buyButton.BorderSizePixel  = 0
	buyButton.Text             = "Buy"
	buyButton.Font             = Enum.Font.GothamBold
	buyButton.TextSize         = 13
	buyButton.TextColor3       = Color3.new(1, 1, 1)
	buyButton.AutoButtonColor  = false
	buyButton.Parent           = card

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 8)
	btnCorner.Parent = buyButton

	buyButton.MouseEnter:Connect(function()
		TweenService:Create(buyButton, TweenInfo.new(0.12), {
			BackgroundColor3 = accent:lerp(Color3.new(1, 1, 1), 0.15),
		}):Play()
	end)
	buyButton.MouseLeave:Connect(function()
		TweenService:Create(buyButton, TweenInfo.new(0.12), {
			BackgroundColor3 = accent,
		}):Play()
	end)
	buyButton.MouseButton1Click:Connect(function()
		onPurchase(entry, buyButton)
	end)

	return card
end

-- CreateBorderTierGallery
-- Inserts a full-width gallery strip as LayoutOrder=0 inside scroll so it
-- appears above the product grid (LayoutOrder=1).
--
-- Each of the four tiles (Silver/Gold/Diamond/Rainbow) displays the BeliodusX
-- card with its matching holographic foil overlay and a "Hover to Preview" hint.
-- Hovering fires HoverPreview via hoverBridgeModule; no purchase, no stat change.
--
-- hoverBridgeModule  the HoverPreviewBridge module (not the result of .get()).
--                    Called lazily on hover so timing of bridge initialisation
--                    is not a concern.
function ShopRenderer.CreateBorderTierGallery(scroll, hoverBridgeModule)
	local baseData = CardDatabase.GetCardData(GALLERY_BASE_CARD)

	-- Outer section frame: header + 2 rows of tiles (each row = card height + padding).
	local rowH = getCardHeight() + GALLERY_TILE_PAD * 2
	local sectionH = GALLERY_HEADER_H + rowH * 2 + GALLERY_TILE_PAD  -- gap between rows
	local section = Instance.new("Frame")
	section.Name                 = "BorderTierGallery"
	section.Size                 = UDim2.new(1, 0, 0, sectionH)
	section.BackgroundTransparency = 1
	section.LayoutOrder          = 0   -- before ProductGrid (LayoutOrder 1)
	section.Parent               = scroll

	-- ── Header strip ─────────────────────────────────────────────────────────
	local header = Instance.new("Frame")
	header.Name                   = "GalleryHeader"
	header.Size                   = UDim2.new(1, 0, 0, GALLERY_HEADER_H)
	header.Position               = UDim2.fromOffset(0, 0)
	header.BackgroundColor3       = Color3.fromRGB(30, 32, 46)
	header.BackgroundTransparency = 0.15
	header.BorderSizePixel        = 0
	header.Parent                 = section

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 12)
	headerCorner.Parent = header

	local headerStroke = Instance.new("UIStroke")
	headerStroke.Color        = Color3.fromRGB(180, 140, 255)
	headerStroke.Transparency = 0.45
	headerStroke.Parent       = header

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Size                   = UDim2.new(1, -20, 0, 26)
	headerTitle.Position               = UDim2.fromOffset(14, 4)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text                   = "✦  Border Tier Gallery"
	headerTitle.Font                   = Enum.Font.GothamBold
	headerTitle.TextSize               = 16
	headerTitle.TextColor3             = Color3.fromRGB(220, 210, 255)
	headerTitle.TextXAlignment         = Enum.TextXAlignment.Left
	headerTitle.Parent                 = header

	local headerSub = Instance.new("TextLabel")
	headerSub.Size                   = UDim2.new(1, -20, 0, 16)
	headerSub.Position               = UDim2.fromOffset(14, 30)
	headerSub.BackgroundTransparency = 1
	headerSub.Text                   = "Hover a card to preview each border tier - no purchase needed."
	headerSub.Font                   = Enum.Font.GothamMedium
	headerSub.TextSize               = 11
	headerSub.TextColor3             = Color3.fromRGB(160, 155, 190)
	headerSub.TextXAlignment         = Enum.TextXAlignment.Left
	headerSub.Parent                 = header

	-- Helper to create a horizontal tile row (ScrollingFrame)
	local function makeTileRow(name)
		local row = Instance.new("ScrollingFrame")
		row.Name                = name
		row.Size                = UDim2.new(1, 0, 0, rowH)
		row.BackgroundTransparency = 1
		row.ScrollBarThickness  = 4
		row.ScrollingDirection  = Enum.ScrollingDirection.X
		row.AutomaticCanvasSize = Enum.AutomaticSize.X
		row.CanvasSize          = UDim2.fromOffset(0, 0)
		local list = Instance.new("UIListLayout")
		list.FillDirection        = Enum.FillDirection.Horizontal
		list.Padding              = UDim.new(0, GALLERY_TILE_PAD)
		list.SortOrder            = Enum.SortOrder.LayoutOrder
		list.VerticalAlignment    = Enum.VerticalAlignment.Center
		list.Parent               = row
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft   = UDim.new(0, GALLERY_TILE_PAD)
		pad.PaddingRight  = UDim.new(0, GALLERY_TILE_PAD)
		pad.PaddingTop    = UDim.new(0, GALLERY_TILE_PAD)
		pad.PaddingBottom = UDim.new(0, GALLERY_TILE_PAD)
		pad.Parent        = row
		return row
	end

	-- Rows wrapper (vertical stack)
	local rowsWrapper = Instance.new("Frame")
	rowsWrapper.Name          = "GalleryRows"
	rowsWrapper.Size          = UDim2.new(1, 0, 0, rowH * 2 + GALLERY_TILE_PAD)
	rowsWrapper.Position      = UDim2.fromOffset(0, GALLERY_HEADER_H)
	rowsWrapper.BackgroundTransparency = 1
	rowsWrapper.Parent        = section

	local rowsList = Instance.new("UIListLayout")
	rowsList.FillDirection   = Enum.FillDirection.Vertical
	rowsList.SortOrder       = Enum.SortOrder.LayoutOrder
	rowsList.Padding         = UDim.new(0, GALLERY_TILE_PAD)
	rowsList.Parent          = rowsWrapper

	-- Row 1: Border tiers (Silver, Gold, Diamond, Rainbow) — uses GALLERY_BASE_CARD
	local tileRow1 = makeTileRow("GalleryRow_BorderTiers")
	tileRow1.LayoutOrder = 1
	tileRow1.Parent      = rowsWrapper

	-- Build one tile per tier (row 1)
	for idx, tier in ipairs(GALLERY_TIER_ORDER) do
		local cfg     = GALLERY_TIER_CONFIG[tier]
		local cardRef = GALLERY_BASE_CARD .. "::Bordered::" .. tier

		local tile = Instance.new("Frame")
		tile.Name        = "GalleryTile_" .. tier
		tile.Size        = UDim2.fromOffset(getCardWidth(), getCardHeight())
		tile.LayoutOrder = idx
		tile.Parent      = tileRow1
		styleCard(tile, cfg.accent)

		-- Art y 10, h 158
		buildArtBox(
			tile,
			baseData and baseData.ArtAssetId or "",
			10, 10,
			getCardWidth() - 20,
			158
		)

		-- Tier name y 172, h 28
		local tierLabel = Instance.new("TextLabel")
		tierLabel.Name                   = "TierLabel"
		tierLabel.Size                   = UDim2.new(1, -20, 0, 28)
		tierLabel.Position               = UDim2.fromOffset(10, 172)
		tierLabel.BackgroundTransparency = 1
		tierLabel.Text                   = cfg.label
		tierLabel.Font                   = Enum.Font.Fantasy
		tierLabel.TextSize               = 20
		tierLabel.TextColor3             = cfg.accent
		tierLabel.TextXAlignment         = Enum.TextXAlignment.Center
		tierLabel.Parent                 = tile

		-- Rarity / type sub-line y 202, h 16
		local subLabel = Instance.new("TextLabel")
		subLabel.Name                   = "SubLabel"
		subLabel.Size                   = UDim2.new(1, -20, 0, 16)
		subLabel.Position               = UDim2.fromOffset(10, 202)
		subLabel.BackgroundTransparency = 1
		subLabel.Text                   = "Foil  •  God"
		subLabel.Font                   = Enum.Font.GothamMedium
		subLabel.TextSize               = 11
		subLabel.TextColor3             = Color3.fromRGB(185, 185, 200)
		subLabel.TextXAlignment         = Enum.TextXAlignment.Center
		subLabel.Parent                 = tile

		-- Hover to Preview hint badge y 222, h 30
		local hint = Instance.new("TextLabel")
		hint.Name                   = "HoverHint"
		hint.Size                   = UDim2.new(1, -20, 0, 30)
		hint.Position               = UDim2.fromOffset(10, 222)
		hint.BackgroundColor3       = Color3.fromRGB(34, 36, 52)
		hint.BackgroundTransparency = 0.25
		hint.Text                   = "✦  Hover to Preview"
		hint.Font                   = Enum.Font.GothamBold
		hint.TextSize               = 12
		hint.TextColor3             = cfg.accent
		hint.TextXAlignment         = Enum.TextXAlignment.Center
		hint.BorderSizePixel        = 0
		hint.Parent                 = tile

		local hintCorner = Instance.new("UICorner")
		hintCorner.CornerRadius = UDim.new(0, 8)
		hintCorner.Parent = hint

		-- Holographic foil overlay (same tier, same intensities as inventory)
		local foilCtrl = HoloFoilController.Attach(tile, {
			tier         = tier,
			cornerRadius = UDim.new(0, 14),
			zIndex       = 6,
		})

		-- Cleanup foil when the tile is destroyed (e.g. shop closed & rebuilt)
		tile.Destroying:Connect(function()
			foilCtrl:Destroy()
		end)

		-- Hover: intensify foil + show full HoverPreview panel (skip on mobile)
		tile.MouseEnter:Connect(function()
			foilCtrl:SetIntensity("Hover")
			if DeviceContext.getIsMobile() then return end
			local api = hoverBridgeModule and hoverBridgeModule.get()
			if api and baseData then
				-- Pass white as fallback rarityColor; HoverPreview uses
				-- CardVisualResolver to compute the correct tier accent internally.
				api.Show(cardRef, baseData, Color3.new(1, 1, 1))
			end
		end)

		tile.MouseLeave:Connect(function()
			foilCtrl:SetIntensity("Idle")
			if DeviceContext.getIsMobile() then return end
			local api = hoverBridgeModule and hoverBridgeModule.get()
			if api then
				api.Hide(0.08)
			end
		end)
	end

	-- Row 2: Concept tiles (UltraRare, Lightning, Corrupted) — each uses its own cardRef for art
	local tileRow2 = makeTileRow("GalleryRow_Concepts")
	tileRow2.LayoutOrder = 2
	tileRow2.Parent      = rowsWrapper

	for conceptIndex = 1, #GALLERY_CONCEPT_CONFIG do
		local conceptCfg = GALLERY_CONCEPT_CONFIG[conceptIndex]
		local conceptRef = conceptCfg.cardRef
		local parsed = CardDatabase.ParseCardReference(conceptRef)
		local conceptBaseId = parsed and parsed.BaseCardId or conceptRef
		local conceptData = CardDatabase.GetCardData(conceptBaseId)
		local conceptAssetId = conceptData and conceptData.ArtAssetId or ""

		local cTile = Instance.new("Frame")
		cTile.Name = "GalleryTile_" .. conceptCfg.key
		cTile.Size = UDim2.fromOffset(getCardWidth(), getCardHeight())
		cTile.LayoutOrder = conceptIndex
		cTile.Parent = tileRow2
		if conceptCfg.useLightning or conceptCfg.foilTier then
			styleCard(cTile, conceptCfg.accent)
		else
			styleCardRainbow(cTile)
		end
		buildArtBox(cTile, conceptAssetId, 10, 10, getCardWidth() - 20, 158)

		local cTierLabel = Instance.new("TextLabel")
		cTierLabel.Name = "TierLabel"
		cTierLabel.Size = UDim2.new(1, -20, 0, 28)
		cTierLabel.Position = UDim2.fromOffset(10, 172)
		cTierLabel.BackgroundTransparency = 1
		cTierLabel.Text = conceptCfg.label
		cTierLabel.Font = Enum.Font.Fantasy
		cTierLabel.TextSize = 20
		cTierLabel.TextColor3 = conceptCfg.accent
		cTierLabel.TextXAlignment = Enum.TextXAlignment.Center
		cTierLabel.Parent = cTile

		local cSubLabel = Instance.new("TextLabel")
		cSubLabel.Name = "SubLabel"
		cSubLabel.Size = UDim2.new(1, -20, 0, 16)
		cSubLabel.Position = UDim2.fromOffset(10, 202)
		cSubLabel.BackgroundTransparency = 1
		cSubLabel.Text = conceptCfg.sub
		cSubLabel.Font = Enum.Font.GothamMedium
		cSubLabel.TextSize = 11
		cSubLabel.TextColor3 = Color3.fromRGB(185, 185, 200)
		cSubLabel.TextXAlignment = Enum.TextXAlignment.Center
		cSubLabel.Parent = cTile

		local cHint = Instance.new("TextLabel")
		cHint.Name = "HoverHint"
		cHint.Size = UDim2.new(1, -20, 0, 30)
		cHint.Position = UDim2.fromOffset(10, 222)
		cHint.BackgroundColor3 = Color3.fromRGB(34, 36, 52)
		cHint.BackgroundTransparency = 0.25
		cHint.Text = conceptCfg.badge
		cHint.Font = Enum.Font.GothamBold
		cHint.TextSize = 12
		cHint.TextColor3 = conceptCfg.accent
		cHint.TextXAlignment = Enum.TextXAlignment.Center
		cHint.BorderSizePixel = 0
		cHint.ZIndex = 14
		cHint.Parent = cTile

		local cHintCorner = Instance.new("UICorner")
		cHintCorner.CornerRadius = UDim.new(0, 8)
		cHintCorner.Parent = cHint

		if conceptCfg.useLightning then
			-- Lightning-only concept tile (replaces Cosmic foil)
			local lightningCtrl = LightningOverlayController.Attach(cTile, {
				baseZIndex       = 20,
				cornerRadius     = UDim.new(0, 14),
				flashIntervalSec = 1.6,
			})
			cTile.Destroying:Connect(function()
				lightningCtrl:Destroy()
			end)
			cTile.MouseEnter:Connect(function()
				lightningCtrl:SetIntensity("Hover")
			end)
			cTile.MouseLeave:Connect(function()
				lightningCtrl:SetIntensity("Idle")
			end)
		elseif conceptCfg.foilTier then
			local foilCtrl = HoloFoilController.Attach(cTile, {
				tier         = conceptCfg.foilTier,
				cornerRadius = UDim.new(0, 14),
				zIndex       = 6,
			})
			cTile.Destroying:Connect(function()
				foilCtrl:Destroy()
			end)
			cTile.MouseEnter:Connect(function()
				foilCtrl:SetIntensity("Hover")
			end)
			cTile.MouseLeave:Connect(function()
				foilCtrl:SetIntensity("Idle")
			end)
		else
			local ultraOpts = {}
			ultraOpts.zIndex = 8
			ultraOpts.cornerRadius = UDim.new(0, 14)
			ultraOpts.textSize = 21
			ultraOpts.snakeSpeed = 3.3
			ultraOpts.snakeAmplitude = 5
			ultraOpts.snakeWavelength = 0.55
			local ultraCtrl = UltraRareTextEffect.Attach(cTile, ultraOpts)
			cTile.Destroying:Connect(function()
				ultraCtrl:Destroy()
			end)
		end

		cTile.MouseEnter:Connect(function()
			if DeviceContext.getIsMobile() then return end
			local api = hoverBridgeModule and hoverBridgeModule.get()
			if api and conceptData then
				local previewOpts
				if conceptCfg.useLightning then
					previewOpts = { lightningOverlay = true }
				elseif not conceptCfg.foilTier then
					previewOpts = { ultraRareOverlay = true }
				else
					previewOpts = nil
				end
				api.Show(conceptRef, conceptData, conceptCfg.accent, previewOpts)
			end
		end)
		cTile.MouseLeave:Connect(function()
			if DeviceContext.getIsMobile() then return end
			local api = hoverBridgeModule and hoverBridgeModule.get()
			if api then
				api.Hide(0.08)
			end
		end)
	end

	return section
end

return ShopRenderer
