---
description: How to create modal/tab-specific UI elements that only appear when the right modal and tab are active
---

# Modal/Tab-Specific UI Pattern

## Overview
This pattern ensures UI elements (like buttons, panels, or overlays) only appear when:
- A specific modal is open
- A specific tab within that modal is active

## When to Use
- Sort buttons that should only exist on one tab
- Contextual actions (e.g., "Sell All" on Inventory tab)
- Tab-specific filters or controls
- Help tooltips that change per tab

## Pattern Implementation

### 1. Create Visibility Sync Helper
```lua
local function updateElementVisibility(modalData, elementName, requiredTabFrame)
    if not modalData or not modalData.frame then
        return
    end

    local element = modalData.frame:FindFirstChild(elementName)
    if not element then
        return
    end

    local isModalVisible = modalData.frame.Visible
    local isRequiredTabVisible = requiredTabFrame and requiredTabFrame.Visible or false

    element.Visible = isModalVisible and isRequiredTabVisible
end
```

### 2. Bind to Visibility Changes (Once)
```lua
local function bindVisibility(modalData, elementName, requiredTabFrame)
    if not modalData or not modalData.visibilityBound then
        modalData.visibilityBound = {}
    end

    if modalData.visibilityBound[elementName] then
        return -- Already bound
    end

    modalData.visibilityBound[elementName] = true

    -- Bind to modal visibility
    if modalData.frame then
        modalData.frame:GetPropertyChangedSignal("Visible"):Connect(function()
            updateElementVisibility(modalData, elementName, requiredTabFrame)
        end)
    end

    -- Bind to tab frame visibility
    if requiredTabFrame then
        requiredTabFrame:GetPropertyChangedSignal("Visible"):Connect(function()
            updateElementVisibility(modalData, elementName, requiredTabFrame)
        end)
    end

    -- Initial sync
    updateElementVisibility(modalData, elementName, requiredTabFrame)
end
```

### 3. Use in Modal Setup
```lua
-- When creating your UI element
local function createTabSpecificButton(modalData, requiredTabFrame)
    local button = Instance.new("TextButton")
    button.Name = "TabSpecificButton"
    button.Parent = modalData.frame
    -- ... styling and behavior ...

    -- Bind visibility
    bindVisibility(modalData, "TabSpecificButton", requiredTabFrame)
end
```

### 4. Call from Modal Initialization
```lua
-- In your modal setup code
createTabSpecificButton(activeModals.Inventory, activeModals.Inventory.inventoryFrame)
```

## Advanced: Multi-Tab Elements

For elements that should appear on multiple tabs:

```lua
local function updateMultiTabVisibility(modalData, elementName, allowedTabFrames)
    if not modalData or not modalData.frame then
        return
    end

    local element = modalData.frame:FindFirstChild(elementName)
    if not element then
        return
    end

    local isModalVisible = modalData.frame.Visible
    local isAnyAllowedTabVisible = false

    for _, tabFrame in pairs(allowedTabFrames) do
        if tabFrame and tabFrame.Visible then
            isAnyAllowedTabVisible = true
            break
        end
    end

    element.Visible = isModalVisible and isAnyAllowedTabVisible
end

local function bindMultiTabVisibility(modalData, elementName, allowedTabFrames)
    if not modalData or not modalData.visibilityBound then
        modalData.visibilityBound = {}
    end

    if modalData.visibilityBound[elementName] then
        return
    end

    modalData.visibilityBound[elementName] = true

    -- Bind modal
    if modalData.frame then
        modalData.frame:GetPropertyChangedSignal("Visible"):Connect(function()
            updateMultiTabVisibility(modalData, elementName, allowedTabFrames)
        end)
    end

    -- Bind each tab
    for _, tabFrame in pairs(allowedTabFrames) do
        if tabFrame then
            tabFrame:GetPropertyChangedSignal("Visible"):Connect(function()
                updateMultiTabVisibility(modalData, elementName, allowedTabFrames)
            end)
        end
    end

    updateMultiTabVisibility(modalData, elementName, allowedTabFrames)
end
```

## Usage Examples

### Sort Button (Single Tab)
```lua
createTabSpecificButton(activeModals.Inventory, activeModals.Inventory.inventoryFrame)
```

### Export Button (Multiple Tabs)
```lua
bindMultiTabVisibility(
    activeModals.Inventory,
    "ExportButton",
    {
        activeModals.Inventory.inventoryFrame,
        activeModals.Inventory.combatDeckFrame
    }
)
```

### Help Tooltip (Tab-Specific)
```lua
createTabSpecificButton(activeModals.Shop, activeModals.Shop.itemsFrame)
```

## Benefits
- **No manual show/hide** in tab switching logic
- **Automatic cleanup** when modal closes
- **Reusable** across all modals
- **Centralized** visibility logic
- **No race conditions** from manual timing

## Common Mistakes to Avoid

### Don't: Manual visibility in tab handlers
```lua
-- AVOID THIS
function switchToItemsTab()
    itemsFrame.Visible = true
    inventoryFrame.Visible = false
    sortButton.Visible = false -- Manual!
end
```

### Don't: Duplicate binding
```lua
-- AVOID THIS
bindVisibility(modalData, "SortButton", inventoryFrame)
bindVisibility(modalData, "SortButton", inventoryFrame) -- Duplicate!
```

### Don't: Forget initial sync
```lua
-- AVOID THIS
local function bindVisibility(modalData, elementName, requiredTabFrame)
    -- ... bindings ...
    -- Missing: updateElementVisibility() for initial state
end
```

## Integration with Existing Code

Replace existing manual visibility with this pattern:

```lua
-- OLD (in ShowModal/HideModal)
if sortButton then
    sortButton.Visible = false
end

-- NEW (automatic via binding)
-- No manual visibility needed!
```

## File Structure Recommendation

Create: `src/client/ui/ModalUIVisibility.luau`

```lua
local ModalUIVisibility = {}

function ModalUIVisibility.bindSingleTab(modalData, elementName, requiredTabFrame)
    -- Implementation from above
end

function ModalUIVisibility.bindMultiTab(modalData, elementName, allowedTabFrames)
    -- Implementation from above
end

return ModalUIVisibility
```

Then require and use in any modal controller:

```lua
local ModalUIVisibility = require(script.Parent.Parent.ModalUIVisibility)

-- In setup
ModalUIVisibility.bindSingleTab(activeModals.Inventory, "SortButton", activeModals.Inventory.inventoryFrame)
```
