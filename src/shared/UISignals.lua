--[[
	UISignals Module
	Centralized signal definitions for UI communication using GoodSignal.
	Provides type-safe local events for UI module communication without RemoteEvents.
	
	Usage:
		local UISignals = require(path.to.UISignals)
		
		-- Connecting to a signal
		UISignals.InventoryClicked:Connect(function()
			-- Handle inventory click
		end)
		
		-- Firing a signal
		UISignals.InventoryClicked:Fire()
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local Signal = require(Packages:WaitForChild("GoodSignal"))

local UISignals = {}

--[[ Main HUD Signals ]]
-- Fired when the inventory button is clicked
UISignals.InventoryClicked = Signal.new()

--[[ Inventory UI Signals ]]
-- Fired when an inventory item is selected (item: SelectedItem?)
UISignals.ItemSelected = Signal.new()
-- Fired when an action is performed on a selected item (actionType: string, item: SelectedItem)
UISignals.ItemAction = Signal.new()
-- Fired when inventory visibility changes (visible: boolean)
UISignals.InventoryVisibilityChanged = Signal.new()

--[[ Hatch Preview UI Signals ]]
-- Fired when egg hatch is confirmed (eggId: string, eggType: string)
UISignals.HatchConfirmed = Signal.new()
-- Fired when hatch preview is cancelled
UISignals.HatchCancelled = Signal.new()

--[[ Store UI Signals ]]
-- Fired when an egg purchase is attempted (eggType: string, quantity: number)
UISignals.EggPurchase = Signal.new()
-- Fired when Robux replenish is attempted
UISignals.StoreReplenish = Signal.new()
-- Fired when a Robux item purchase is attempted (itemType: string, itemId: string)
UISignals.RobuxPurchase = Signal.new()
-- Fired when a power-up purchase is attempted (powerUpId: string)
UISignals.PowerUpPurchase = Signal.new()
-- Fired when a trap purchase is attempted (trapType: string)
UISignals.TrapPurchase = Signal.new()
-- Fired when a weapon purchase is attempted (weaponType: string)
UISignals.WeaponPurchase = Signal.new()

--[[ Shield UI Signals ]]
-- Fired when shield activation is requested
UISignals.ShieldActivate = Signal.new()

--[[ Chicken Selling Signals ]]
-- Fired when a chicken is sold (chickenId: string, sellPrice: number, chickenType: string, rarity: string)
UISignals.ChickenSold = Signal.new()
-- Fired when a sale is cancelled
UISignals.SaleCancelled = Signal.new()

--[[ Offline Earnings UI Signals ]]
-- Fired when offline rewards are claimed (moneyEarned: number, eggsCollected: number)
UISignals.OfflineRewardsClaimed = Signal.new()
-- Fired when offline earnings popup is dismissed
UISignals.OfflineEarningsDismissed = Signal.new()

--[[ Trade UI Signals ]]
-- Fired when a trade request is sent (targetUserId: number)
UISignals.TradeRequested = Signal.new()
-- Fired when a trade is accepted (tradeId: number)
UISignals.TradeAccepted = Signal.new()
-- Fired when a trade is declined (tradeId: number)
UISignals.TradeDeclined = Signal.new()
-- Fired when trade confirmation is clicked
UISignals.TradeConfirmed = Signal.new()
-- Fired when trade is cancelled
UISignals.TradeCancelled = Signal.new()

return UISignals
