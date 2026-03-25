local EconomyProtocol = {}

EconomyProtocol.Remotes = {
	FolderName = "EconomyRemotes",
	Request = "EconomyRequest",
}

EconomyProtocol.ActionType = {
	GetState = "GetState",
	BuyPack = "BuyPack",
	OpenPack = "OpenPack",
	BuyItem = "BuyItem",
	UseItem = "UseItem",
	SellCards = "SellCards",
	BuyDirectCard = "BuyDirectCard",
}

return EconomyProtocol
