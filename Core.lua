--[[
Author: Starinnia
InnervationTrak is an addon designed to give healers a quick list of raiders Spiritual Innervation stacks
during the Spiritbinger Gara'jal encounter in Mogu'shan Vaults
contact: codemaster2010 AT gmail DOT com

Copyright (c) 2012 Michael J. Murray aka Lyte of Lothar(US)
All rights reserved unless otherwise explicitly stated.
]]

local addon = LibStub("AceAddon-3.0"):NewAddon("InnervationTrak", "AceEvent-3.0", "AceTimer-3.0")

--upvalue globals used in health/ui updates
local pairs = pairs
local wipe = wipe
local tconcat = table.concat
local format = string.format

local GARAJAL = 60143
local INNERVATION = GetSpellInfo(117549)
local CROSSED = GetSpellInfo(116161)
local unlock = "Interface\\AddOns\\InnervationTrak\\Textures\\un_lock"
local lock = "Interface\\AddOns\\InnervationTrak\\Textures\\lock"

--tables for displaying the info
local innervationPlayers = {}
local sortedInnervation = {}
local stringBuilder = {}

local lineFormat = "%s: %d%%"

--save the hex color escape codes
local hexColors = {}
for k, v in pairs(RAID_CLASS_COLORS) do
	hexColors[k] = format("|cff%02x%02x%02x", v.r * 255, v.g * 255, v.b * 255)
end

local function getCID(guid)
	return tonumber(guid:sub(6, 10), 16)
end

--forward declaration of the functions for the lock functions
local lockDisplay
local unlockDisplay
local updateLockButton
local toggleLock

function addon:OnInitialize()
	local defaults = {
		profile = {
			position = {},
			locked = false,
			width = 100,
			height = 122,
		},
	}
	self.db = LibStub("AceDB-3.0"):New("InnervationTrakDB2", defaults, "Default")
	
	_G["SlashCmdList"]["INNERVATIONTRAK_MAIN"] = function(s)
		if self.ui:IsVisible() then
			self.ui:Hide()
		else
			self.ui:Show()
		end
	end
	
	_G["SLASH_INNERVATIONTRAK_MAIN1"] = "/innervation"
end

function addon:OnEnable()
	self:CreateUI()
	self:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
end

function addon:OnDisable()
	self:UnregisterAllEvents()
	self.ui:Hide()
end

function addon:INSTANCE_ENCOUNTER_ENGAGE_UNIT()
	if UnitExists("boss1") and getCID(UnitGUID("boss1")) == GARAJAL then
		--ignore LFR pulls
		local zone, _, diff = GetInstanceInfo()
		if diff == 7 then return end
		
		--reset on new fight
		wipe(innervationPlayers)
		self:RegisterEvent("UNIT_AURA")
		self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self.ui:Show()
		self:UpdateUI()
	end
end

function addon:UNIT_AURA(event, unit)
	if not UnitInRaid(unit) then return end
	if UnitGroupRolesAssigned(unit) ~= "DAMAGER" then return end
	
	local _, spell, spellid, val1, val2, val3
	spell, _, _, _, _, _, _, _, _, _, spellid, _, _, val1, val2, val3 = UnitBuff(unit, INNERVATION)
	
	if spell then
		innervationPlayers[UnitName(unit)] = val2 < 100 and val2 or 100
	else
		innervationPlayers[UnitName(unit)] = nil
	end
	
	self:UpdateUI()
end

function addon:COMBAT_LOG_EVENT_UNFILTERED(_, _, subevent, _, _, _, _, _, dstGUID)
	if event == "UNIT_DIED" then
		if getCID(dstGUID) == GARAJAL then
			self:UnregisterAllEvents()
			wipe(innervationPlayers)
			wipe(sortedInnervation)
			wipe(stringBuilder)
			self.ui:Hide()
		end 
	end
end

local function checkForWipe()
	local wiped = true
	local num = GetNumGroupMembers()
	
	for i = 1, num do
		local name = GetRaidRosterInfo(i)
		if UnitAffectingCombat(name) then
			wiped = false
			break
		end
	end
	
	if wiped then
		addon.ui:Hide()
		addon:UnregisterEvent("UNIT_AURA")
		addon:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
		addon:UnregisterEvent("PLAYER_REGEN_ENABLED")
	else
		addon:ScheduleTimer(checkForWipe, 2)
	end
end

function addon:PLAYER_REGEN_ENABLED()
	if addon.ui:IsVisible() then
		checkForWipe()
	end
end

local coloredNames = setmetatable({}, {__index =
	function(self, key)
		if type(key) == "nil" then return nil end
		local _, class = UnitClass(key)
		if class then
			self[key] = hexColors[class] .. key .. "|r"
			return self[key]
		else
			return key
		end
	end
})

local function sortFunc(a, b) return innervationPlayers[a] > innervationPlayers[b] end
function addon:UpdateUI()
	--order the names with highest stack first
	wipe(sortedInnervation)
	for k in pairs(innervationPlayers) do
		sortedInnervation[#sortedInnervation+1] = k
	end
	table.sort(sortedInnervation, sortFunc)
	
	--use a table as a string builder
	wipe(stringBuilder)
	for i = 1, #sortedInnervation do
		local n = sortedInnervation[i]
		if n and UnitExists(n) and not UnitIsDeadOrGhost(n) then
			stringBuilder[#stringBuilder + 1] = lineFormat:format(coloredNames[n], innervationPlayers[n])
		end
	end
	
	--update the text on the display
	if #stringBuilder == 0 then
		self.ui.text:SetText("|cff777777:-P|r")
	else
		self.ui.text:SetText(tconcat(stringBuilder, "\n"))
	end
end

local function onDragStart(self) self:StartMoving() end
local function onDragStop(self)
	self:StopMovingOrSizing()
	local point, _, anchor, x, y = self:GetPoint()
	addon.db.profile.position.x = floor(x)
	addon.db.profile.position.y = floor(y)
	addon.db.profile.position.anchor = anchor
	addon.db.profile.position.point = point
end
local function OnDragHandleMouseDown(self) self.frame:StartSizing("BOTTOMRIGHT") end
local function OnDragHandleMouseUp(self) self.frame:StopMovingOrSizing() end
local function onResize(self, width, height)
	addon.db.profile.width = width
	addon.db.profile.height = height
end

local function lockDisplay()
	addon.ui:EnableMouse(false)
	addon.ui:SetMovable(false)
	addon.ui:SetResizable(false)
	addon.ui:RegisterForDrag()
	addon.ui:SetScript("OnSizeChanged", nil)
	addon.ui:SetScript("OnDragStart", nil)
	addon.ui:SetScript("OnDragStop", nil)
	addon.ui.drag:Hide()
end

local function unlockDisplay()
	addon.ui:EnableMouse(true)
	addon.ui:SetMovable(true)
	addon.ui:SetResizable(true)
	addon.ui:RegisterForDrag("LeftButton")
	addon.ui:SetScript("OnSizeChanged", onResize)
	addon.ui:SetScript("OnDragStart", onDragStart)
	addon.ui:SetScript("OnDragStop", onDragStop)
	addon.ui.drag:Show()
end

local function updateLockButton()
	if not addon.ui then return end
	addon.ui.lock:SetNormalTexture(addon.db.profile.locked and lock or unlock)
end

local function toggleLock()
	addon.db.profile.locked = not addon.db.profile.locked
	if addon.db.profile.locked then
		lockDisplay()
	else
		unlockDisplay()
	end
	updateLockButton()
end

local function onControlEnter(self)
	GameTooltip:ClearLines()
	GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
	GameTooltip:AddLine(self.tooltipHeader)
	GameTooltip:AddLine(self.tooltipText, 1, 1, 1, 1)
	GameTooltip:Show()
end
local function onControlLeave() GameTooltip:Hide() end
local function closeWindow()
	addon.ui:Hide()
end

function addon:CreateUI()
	if self.ui then return end
	
	local f = CreateFrame("FRAME", nil, UIParent)
	f:SetWidth(self.db.profile.width)
	f:SetHeight(self.db.profile.height)
	f:SetClampedToScreen(true)
	f:SetMinResize(100, 60)
	
	f.bg = f:CreateTexture(nil, "PARENT")
	f.bg:SetAllPoints(f)
	f.bg:SetBlendMode("BLEND")
	f.bg:SetTexture(0, 0, 0, 0.5)
	
	if self.db.profile.position.x then
		f:SetPoint(self.db.profile.position.point, UIParent, self.db.profile.position.anchor, self.db.profile.position.x, self.db.profile.position.y)
	else
		f:SetPoint("CENTER")
	end
	
	f:SetScript("OnDragStart", onDragStart)
	f:SetScript("OnDragStop", onDragStop)
	f:SetScript("OnSizeChanged", onResize)
	
	f.close = CreateFrame("Button", nil, f)
	f.close:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -2, 2)
	f.close:SetHeight(16)
	f.close:SetWidth(16)
	f.close.tooltipHeader = "Close"
	f.close.tooltipText = "Closes the InnervationTrak display."
	f.close:SetNormalTexture("Interface\\AddOns\\InnervationTrak\\Textures\\close")
	f.close:SetScript("OnEnter", onControlEnter)
	f.close:SetScript("OnLeave", onControlLeave)
	f.close:SetScript("OnClick", closeWindow)

	f.lock = CreateFrame("Button", nil, f)
	f.lock:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 2, 2)
	f.lock:SetHeight(16)
	f.lock:SetWidth(16)
	f.lock.tooltipHeader = "Toggle lock"
	f.lock.tooltipText = "Toggle whether or not the window should be locked or not."
	f.lock:SetScript("OnEnter", onControlEnter)
	f.lock:SetScript("OnLeave", onControlLeave)
	f.lock:SetScript("OnClick", toggleLock)
	
	f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.header:SetText("Innervation")
	f.header:SetPoint("BOTTOM", f, "TOP", 0, 4)
	
	f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	f.text:SetFont("Fonts\\FRIZQT__.TTF", 12)
	f.text:SetText("")
	f.text:SetAllPoints(f)
	f:SetScript("OnShow", function(frame) frame.text:SetText("|cff777777:-P|r") end)
	
	f.drag = CreateFrame("Frame", nil, f)
	f.drag.frame = f
	f.drag:SetFrameLevel(f:GetFrameLevel() + 10)
	f.drag:SetWidth(16)
	f.drag:SetHeight(16)
	f.drag:SetPoint("BOTTOMRIGHT", f, -1, 1)
	f.drag:EnableMouse(true)
	f.drag:SetScript("OnMouseDown", OnDragHandleMouseDown)
	f.drag:SetScript("OnMouseUp", OnDragHandleMouseUp)
	f.drag:SetAlpha(0.5)
	
	f.drag.tex = f.drag:CreateTexture(nil, "BACKGROUND")
	f.drag.tex:SetTexture("Interface\\AddOns\\InnervationTrak\\Textures\\draghandle")
	f.drag.tex:SetWidth(16)
	f.drag.tex:SetHeight(16)
	f.drag.tex:SetBlendMode("ADD")
	f.drag.tex:SetPoint("CENTER", f.drag)
	
	f:Hide()
	self.ui = f
	
	if self.db.profile.locked then
		lockDisplay()
	else
		unlockDisplay()
	end
	updateLockButton()
end
