-- DamageNumberView.luau
-- Legacy facade: forwards to DamagePopupManager (see DamagePopupManager.luau).

local DamagePopupManager = require(script.Parent:WaitForChild("DamagePopupManager"))

local DamageNumberView = {}

function DamageNumberView.showFloatingOnRoot(rootFrame, targetGui, rawAmount, kind)
	DamagePopupManager.EnqueueFloating({
		sessionId = nil,
		targetKey = "legacy_" .. tostring(kind or "float"),
		rootFrame = rootFrame,
		targetGui = targetGui,
		amount = rawAmount,
		category = "NormalDamage",
		contextKind = kind or "Default",
		sequence = 0,
	})
end

function DamageNumberView.show(parent, rawAmount, kind)
	DamagePopupManager.EnqueueOnCard({
		sessionId = nil,
		targetKey = "legacy_card_" .. tostring(kind or "card"),
		cardFrame = parent,
		amount = rawAmount,
		category = "NormalDamage",
		contextKind = kind or "PvpHit",
		sequence = 0,
	})
end

return DamageNumberView
