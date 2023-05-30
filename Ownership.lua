local TycoonService = require(script.Parent)

local CrossServerHandler = TycoonService.Get("CrossServerHandler")
local GameSettings = TycoonService.Get("GameSettings")
local PlayerHandler = TycoonService.Get("PlayerHandler")
local RemoteMod = TycoonService.Get("RemoteMod")

function TycoonService:ClaimTycoon(ownerPlr)
	if not self.Owner and ownerPlr:GetAttribute("Tycoon") == "" then
		local class = PlayerHandler.GetPlayer(ownerPlr)
		if not class or not class.Data._FullyLoaded then return end
		
		self.Owner = ownerPlr
		self.OwnerUserId = ownerPlr.UserId
		self.OwnerClass = class
		self.PlotObj:SetAttribute("Owner", ownerPlr.Name)
		ownerPlr:SetAttribute("Tycoon", self.ID)
		
		--print(class.Data)
		for i, v in pairs(class.Data.TycoonStorageInfo.Unlockables) do
			if v ~= "" then
				local split = v:split("/")
				for _, o in ipairs(split) do
					local object = self.PlotObj.Unlockables[i]:FindFirstChild(o) or self.PlotStorageObj.Unlockables[i]:FindFirstChild(o)
					if object and not object:GetAttribute("Purchased") then
						self:Purchase(object, i, true)
					end
				end
			end
		end
		for _, t in pairs({"StoredDrops", "ProcessingDrops"}) do
			for i, n in pairs(class.Data.TycoonStorageInfo[t]) do
				self[t][i] = n
			end
		end
		for _, i in ipairs({"AllTimeDropsSold"}) do
			self[i] = class.Data.TycoonStorageInfo[i]
		end
		
		self.CashMultiplier = 1 + (class.Data.Rebirths * GameSettings.AddedPerRebirth)
		self.AutoPickupActive = class.Data._GamePasses["AutoPickup"].Owned and class.Data.TycoonStorageInfo.AutoPickupActive or false
		self.AutoSellActive = class.Data._GamePasses["AutoSell"].Owned and class.Data.TycoonStorageInfo.AutoSellActive or false
		
		self:UpdateAllTimeDropsSold()
		self.PlotObj.InitialMap.ClaimPart.ProximityPrompt.Enabled = false
		self.PlotObj.InitialMap.ClaimPart.Color = Color3.fromRGB(0, 255, 0)
		self.PlotObj.InitialMap.OwnerSignPart.OwnerGui.Frame.TextLabel.Text = string.upper(ownerPlr.Name) .. "'S THEATER"
		
		RemoteMod.SendClient(ownerPlr, "ConnectTycoonClient", {
			AutoPickupActive = self.AutoPickupActive,
			AutoSellActive = self.AutoSellActive,
			CashMultiplier = self.CashMultiplier,
			ID = self.ID,
			PlotObj = self.PlotObj,
			PlotStorageObj = self.PlotStorageObj,
			ProcessingDrops = self.ProcessingDrops,
			SellTickRate = self.SellTickRate,
			SoldPerTick = self.SoldPerTick,
			StoredDrops = self.StoredDrops,
		})

		class:Update()
	end
end

function TycoonService:UpdateClientValue(name)
	RemoteMod.SendClient(self.Owner, "UpdateTycoonValue", name, self[name])
end

function TycoonService:SaveTycoon()
	local class = PlayerHandler.GetPlayer(self.Owner)
	if class then
		local ownedObjs = self:GetAllPurchasedObjs()
		for i, t in pairs(ownedObjs) do
			class.Data.TycoonStorageInfo.Unlockables[i] = table.concat(t, "/")
		end
		
		for _, t in pairs({"StoredDrops", "ProcessingDrops"}) do
			for i, n in pairs(self[t]) do
				class.Data.TycoonStorageInfo[t][i] = n
			end
		end
		
		for _, i in ipairs({"AllTimeDropsSold", "AutoPickupActive", "AutoSellActive"}) do
			class.Data.TycoonStorageInfo[i] = self[i]
		end
		--print(class)
	else
		warn("Failed to save tycoon for UserId: " .. self.OwnerUserId)
	end
end

function TycoonService:ResetTycoon()
	local plr = self.Owner
	if plr then
		self:SaveTycoon()
		RemoteMod.SendClient(self.Owner, "ResetTycoonClient")
		plr:SetAttribute("Tycoon", "")
	end	
	
	self:DisconnectTycoonDroppers()
	self:ResetDropStorage(true)
	self:ResetPlotObjects()
	self.Owner = nil
	self.OwnerUserId = nil
	self.OwnerClass = nil
	self.IsSelling = false
	self.PlotObj:SetAttribute("Owner", "")
	self.PlotObj.InitialMap.ClaimPart.ProximityPrompt.Enabled = true
	self.PlotObj.InitialMap.ClaimPart.Color = Color3.fromRGB(255, 0, 0)
	self.PlotObj.InitialMap.OwnerSignPart.OwnerGui.Frame.TextLabel.Text = "UNOWNED THEATER"
end

function TycoonService:Rebirth()
	local class = PlayerHandler.GetPlayer(self.Owner)
	if not class or class.Data.Cash < self.PlotObj.Unlockables.Buttons["Rebirth"]:GetAttribute("CostCash") then return end
	class:TeleportToTycoon()
	class:SetCash(0, true)
	class.Data.Rebirths += 1
	self.Owner.leaderstats.Rebirths.Value = class.Data.Rebirths
	
	self:DisconnectTycoonDroppers()
	self:ResetDropStorage()
	self:ResetPlotObjects()
	self.CashMultiplier = 1 + (GameSettings.AddedPerRebirth * class.Data.Rebirths)
	
	self:SaveTycoon()
	class:Update()
	
	RemoteMod.SendClient(self.Owner, "Rebirth", self.CashMultiplier)
	CrossServerHandler.Publish("rebirth", self.Owner.Name, class.Data.Rebirths)
end


CrossServerHandler.Subscribe("rebirth", function(name, reb)
	RemoteMod.SendAllClients("SystemMessage", {
		Text = ("[GLOBAL] %s now has %d rebirths!"):format(name, reb),
		Color = Color3.fromRGB(96, 255, 250)
	})
end)

return TycoonService
