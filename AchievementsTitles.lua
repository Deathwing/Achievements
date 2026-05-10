local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsTitles.lua");
end

local Private = Achievements.private;
local TITLE_DATA = Private.data and Private.data.titles or {};
local ACHIEVEMENT_DATA = Private.data and Private.data.achievements or {};

local TITLE_MESSAGE_VERSION = "1";
local TITLE_BROADCAST_COOLDOWN = 2;

local titleIDByMask;
local paperDollOnShowHooked;
local paperDollFrameScriptHooked;
local characterFrameOnShowHooked;
local characterFrameOnEventHooked;
local titleAvailabilityHooked;
local tooltipUnitHooked;
local tooltipOnUpdateHooked;
local fallbackTitleMenuFrame;
local lastTitleBroadcast = 0;
local accountTitleNamesSanitised;
local UpdateTooltipKnownPlayerName;
local UpdateVisibleKnownTitleNames;

local function GetNow()
	return GetServerTime();
end

local function CallAfter(delay, callback)
	C_Timer.After(delay, callback);
end

local function PrintMessage(message)
	if Private and Private.PrintMessage then
		Private.PrintMessage(message);
	elseif DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(message);
	end
end

local function DebugTitle(message)
	if Private and Private.DebugMessage then
		Private.DebugMessage("titles: " .. tostring(message));
	end
end

local function NormaliseName(name)
	if type(name) ~= "string" or name == "" then
		return nil;
	end
	local shortName = Ambiguate(name, "short");
	if shortName and shortName ~= "" then
		return shortName:match("^([^%-]+)") or shortName;
	end
	return name:match("^([^%-]+)") or name;
end

local function SanitiseStoredPlayerNames(players)
	if type(players) ~= "table" then
		return;
	end
	local moves;
	for key, record in pairs(players) do
		if type(record) == "table" then
			local cleanKey = NormaliseName(key);
			local cleanName = NormaliseName(record.name) or cleanKey;
			if (cleanName and cleanName ~= record.name) or (cleanKey and cleanKey ~= key) then
				DebugTitle("sanitize key=" .. tostring(key) .. " name=" .. tostring(record.name) .. " cleanKey=" .. tostring(cleanKey) .. " cleanName=" .. tostring(cleanName));
			end
			if cleanName then
				record.name = cleanName;
			end
			if cleanKey and cleanKey ~= key then
				moves = moves or {};
				moves[#moves + 1] = { from = key, to = cleanKey };
			end
		end
	end
	if not moves then
		return;
	end
	for _, move in ipairs(moves) do
		local record = players[move.from];
		if record then
			if not players[move.to] then
				players[move.to] = record;
			else
				local existing = players[move.to];
				if type(existing) == "table" and type(record) == "table" and (tonumber(record.seenAt) or 0) > (tonumber(existing.seenAt) or 0) then
					existing.titleID = record.titleID;
					existing.titleAchievementID = record.titleAchievementID;
					existing.seenAt = record.seenAt;
				end
			end
			players[move.from] = nil;
		end
	end
end

local function IsLocalName(name)
	local localName = UnitName("player");
	if not localName or not name then
		return false;
	end
	local shortName = Ambiguate(name, "short") or tostring(name):match("^([^%-]+)") or name;
	return shortName == localName;
end

local function GetCharacterTitleDB()
	AchievementsCharacterDB.addonTitles = AchievementsCharacterDB.addonTitles or {};
	return AchievementsCharacterDB.addonTitles;
end

local function GetAccountTitleDB()
	AchievementsDB.addonTitles = AchievementsDB.addonTitles or {};
	AchievementsDB.addonTitles.players = AchievementsDB.addonTitles.players or {};
	if not accountTitleNamesSanitised then
		SanitiseStoredPlayerNames(AchievementsDB.addonTitles.players);
		accountTitleNamesSanitised = true;
	end
	return AchievementsDB.addonTitles;
end

GetAccountTitleDB();

local function GetTitleIDByMask(mask)
	mask = tonumber(mask);
	if not mask or mask <= 0 then
		return nil;
	end
	if not titleIDByMask then
		titleIDByMask = {};
		for titleID, title in pairs(TITLE_DATA) do
			if title.mask and title.mask > 0 then
				titleIDByMask[title.mask] = titleID;
			end
		end
	end
	return titleIDByMask[mask];
end

local function GetPlayerFactionKey()
	local factionGroup = UnitFactionGroup("player");
	if factionGroup == "Horde" then
		return "horde";
	elseif factionGroup == "Alliance" then
		return "alliance";
	end
	return nil;
end

local function GetPlayerSexKey()
	local sex = UnitSex("player");
	if sex == 3 then
		return "female";
	elseif sex == 2 then
		return "male";
	end
	return nil;
end

local function ResolveAchievementTitleID(achievement)
	if type(achievement) ~= "table" then
		return nil;
	end
	local factionKey = GetPlayerFactionKey();
	if factionKey == "horde" and achievement.titleRewardHorde then
		return achievement.titleRewardHorde;
	elseif factionKey == "alliance" and achievement.titleRewardAlliance then
		return achievement.titleRewardAlliance;
	end

	local sexKey = GetPlayerSexKey();
	if sexKey == "male" and achievement.titleRewardMale then
		return achievement.titleRewardMale;
	elseif sexKey == "female" and achievement.titleRewardFemale then
		return achievement.titleRewardFemale;
	end

	return achievement.titleReward;
end

local function IsNativeTitleKnown(title)
	if type(title) ~= "table" or not title.mask or not IsTitleKnown then
		return false;
	end
	local ok, known = pcall(IsTitleKnown, title.mask);
	return ok and known == true;
end

local function FindCompletedAchievementForTitle(titleID)
	titleID = tonumber(titleID);
	if not titleID then
		return nil;
	end
	for achievementID, achievement in pairs(ACHIEVEMENT_DATA) do
		if ResolveAchievementTitleID(achievement) == titleID
			and (not Private.IsAchievementForPlayerFaction or Private.IsAchievementForPlayerFaction(achievement))
			and Private.IsAchievementCompleted and Private.IsAchievementCompleted(achievementID) then
			return achievementID;
		end
	end
	return nil;
end

local function IsTitleAvailableLocally(titleID)
	local title = TITLE_DATA[tonumber(titleID) or 0];
	if not title then
		return false;
	end
	return IsNativeTitleKnown(title) or FindCompletedAchievementForTitle(titleID) ~= nil;
end

local function FormatTitleName(title, playerName, sex)
	if type(title) ~= "table" then
		return playerName or "";
	end
	local formatText;
	if sex == 3 or (not sex and IsLocalName(playerName) and UnitSex("player") == 3) then
		formatText = title.name1 or title.name;
	else
		formatText = title.name or title.name1;
	end
	formatText = type(formatText) == "string" and formatText ~= "" and formatText or "%s";
	if not formatText:find("%s", 1, true) then
		formatText = formatText .. " %s";
	end
	local ok, formatted = pcall(string.format, formatText, playerName or "");
	if ok then
		return formatted;
	end
	return (formatText:gsub("%%s", function()
		return tostring(playerName or "");
	end, 1));
end

local function TrimTitleLabel(text)
	if type(text) ~= "string" then
		return nil;
	end
	text = text:gsub("^%s+", ""):gsub("%s+$", "");
	text = text:gsub("^,+%s*", ""):gsub("%s*,+$", "");
	text = text:gsub("^%-+%s*", ""):gsub("%s*%-$", "");
	return text ~= "" and text or nil;
end

local function StripPlayerNameFromTitleText(text, playerName)
	text = type(text) == "string" and text:gsub("%%s", "") or text;
	if type(text) == "string" and type(playerName) == "string" and playerName ~= "" then
		local startIndex, endIndex = text:find(playerName, 1, true);
		if startIndex then
			text = text:sub(1, startIndex - 1) .. text:sub(endIndex + 1);
		end
	end
	return TrimTitleLabel(text);
end

local function FormatTitleLabel(title, playerName, sex)
	if type(title) ~= "table" then
		return nil;
	end
	local formatText;
	if sex == 3 or (not sex and IsLocalName(playerName) and UnitSex("player") == 3) then
		formatText = title.name1 or title.name;
	else
		formatText = title.name or title.name1;
	end
	return StripPlayerNameFromTitleText(formatText, playerName) or StripPlayerNameFromTitleText(FormatTitleName(title, playerName, sex), playerName);
end

local function StoreSelectedTitleID(titleID)
	local titleDB = GetCharacterTitleDB();
	titleID = tonumber(titleID);
	if titleID and titleID > 0 then
		titleDB.selectedTitleID = titleID;
		titleDB.suppressPVPTitle = nil;
	else
		titleDB.selectedTitleID = nil;
		titleDB.suppressPVPTitle = nil;
	end
end

local function StoreNoTitleSelection()
	local titleDB = GetCharacterTitleDB();
	titleDB.selectedTitleID = nil;
	titleDB.suppressPVPTitle = true;
end

local function IsPVPTitleSuppressed()
	return GetCharacterTitleDB().suppressPVPTitle == true;
end

local function GetNativeCurrentTitleID()
	local ok, mask = pcall(GetCurrentTitle);
	if not ok then
		return nil;
	end
	return GetTitleIDByMask(mask);
end

local function GetCurrentTitleID()
	local selectedTitleID = tonumber(GetCharacterTitleDB().selectedTitleID);
	if selectedTitleID and IsTitleAvailableLocally(selectedTitleID) then
		return selectedTitleID;
	elseif selectedTitleID then
		StoreSelectedTitleID(nil);
	end
	if IsPVPTitleSuppressed() then
		return nil;
	end
	return GetNativeCurrentTitleID();
end

local function GetCurrentTitleSnapshot()
	local titleID = GetCurrentTitleID();
	if not titleID or not TITLE_DATA[titleID] then
		return 0, 0;
	end
	return titleID, FindCompletedAchievementForTitle(titleID) or 0;
end

local function GetLocalPlayerDisplayName()
	local playerName = UnitName("player");
	if not playerName or playerName == "" then
		return nil;
	end

	local titleID = GetCurrentTitleID();
	if titleID and TITLE_DATA[titleID] then
		return FormatTitleName(TITLE_DATA[titleID], playerName, UnitSex("player"));
	end
	if IsPVPTitleSuppressed() then
		return playerName;
	end
	return UnitPVPName("player");
end

local function GetRemoteTitleRecord(playerName)
	local key = NormaliseName(playerName);
	local record = key and GetAccountTitleDB().players[key] or nil;
	if record and record.titleID and TITLE_DATA[record.titleID] then
		return record;
	end
	return nil;
end

local function GetUnitBaseName(unit)
	if not unit then
		return nil;
	end
	local name = UnitName(unit);
	if type(name) == "string" and name ~= "" then
		return name;
	end
	return nil;
end

local function GetKnownPlayerDisplayName(playerName, unit)
	if unit and UnitIsUnit(unit, "player") then
		return GetLocalPlayerDisplayName();
	end
	if playerName and IsLocalName(playerName) then
		return GetLocalPlayerDisplayName();
	end
	if unit and not UnitIsPlayer(unit) then
		return nil;
	end
	playerName = playerName or GetUnitBaseName(unit);
	if not playerName or playerName == "" then
		return nil;
	end

	local record = GetRemoteTitleRecord(playerName);
	if record then
		return FormatTitleName(TITLE_DATA[record.titleID], playerName, unit and UnitSex(unit) or nil);
	end
	return nil;
end

local function StoreRemoteTitleSnapshot(sender, titleID, achievementID)
	if Achievements.RememberKnownPlayerName then
		Achievements.RememberKnownPlayerName(sender);
	end
	if IsLocalName(sender) then
		DebugTitle("ignore local sender=" .. tostring(sender));
		return;
	end
	local key = NormaliseName(sender);
	if not key then
		DebugTitle("ignore sender without key=" .. tostring(sender));
		return;
	end
	titleID = tonumber(titleID) or 0;
	achievementID = tonumber(achievementID) or 0;
	DebugTitle("store sender=" .. tostring(sender) .. " key=" .. tostring(key) .. " titleID=" .. tostring(titleID) .. " achievementID=" .. tostring(achievementID));
	local titleDB = GetAccountTitleDB();
	local record = titleDB.players[key] or {};
	record.name = key;
	record.seenAt = GetNow();
	if titleID > 0 and TITLE_DATA[titleID] then
		record.titleID = titleID;
		record.titleAchievementID = achievementID > 0 and achievementID or nil;
	else
		record.titleID = nil;
		record.titleAchievementID = nil;
	end
	titleDB.players[key] = record;
	if UpdateVisibleKnownTitleNames then
		UpdateVisibleKnownTitleNames();
	end
	if UpdateTooltipKnownPlayerName and GameTooltip and (not GameTooltip.IsShown or GameTooltip:IsShown()) then
		UpdateTooltipKnownPlayerName(GameTooltip);
	end
end

local function SendTitleBroadcast(force)
	if not Achievements.SendNetworkAddonMessage then
		return false;
	end
	local now = GetNow();
	if not force and now - lastTitleBroadcast < TITLE_BROADCAST_COOLDOWN then
		return false;
	end
	lastTitleBroadcast = now;

	local titleID, achievementID = GetCurrentTitleSnapshot();
	local message = string.format("TTL\t%s\t%d\t%d", TITLE_MESSAGE_VERSION, titleID or 0, achievementID or 0);
	local sent = false;
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		sent = Achievements.SendNetworkAddonMessage(message, "INSTANCE_CHAT") or sent;
	elseif IsInRaid() then
		sent = Achievements.SendNetworkAddonMessage(message, "RAID") or sent;
	elseif IsInGroup() then
		sent = Achievements.SendNetworkAddonMessage(message, "PARTY") or sent;
	end
	if IsInGuild() then
		sent = Achievements.SendNetworkAddonMessage(message, "GUILD") or sent;
	end
	local channelID = Achievements.GetAchievementsChannelID and Achievements.GetAchievementsChannelID() or nil;
	local channelName = Achievements.GetAchievementsChannelName and Achievements.GetAchievementsChannelName() or nil;
	if channelID then
		sent = Achievements.SendNetworkAddonMessage(message, "CHANNEL", channelID) or sent;
	elseif channelName then
		sent = Achievements.SendNetworkAddonMessage(message, "CHANNEL", channelName) or sent;
	end
	return sent;
end

local function RefreshPaperDollTitleDropdown()
	if PaperDollFrame and PaperDollFrame:IsVisible() and Achievements.UpdateAddonTitleDropdown then
		Achievements.UpdateAddonTitleDropdown(PaperDollFrame);
	end
end

local function UpdatePaperDollCharacterName()
	if not CharacterNameText then
		return;
	end

	local displayName = GetLocalPlayerDisplayName();
	if not displayName or displayName == "" then
		return;
	end
	CharacterNameText:SetText(displayName);
end

local function RefreshVisibleTooltipName()
	if UpdateTooltipKnownPlayerName and GameTooltip and (not GameTooltip.IsShown or GameTooltip:IsShown()) then
		UpdateTooltipKnownPlayerName(GameTooltip);
	end
	if UpdateVisibleKnownTitleNames then
		UpdateVisibleKnownTitleNames();
	end
end

local function SelectNativeTitle(mask)
	mask = tonumber(mask) or -1;
	pcall(SetCurrentTitle, mask);
	StoreSelectedTitleID(GetTitleIDByMask(mask));
	SendTitleBroadcast(true);
	RefreshPaperDollTitleDropdown();
	UpdatePaperDollCharacterName();
	RefreshVisibleTooltipName();
end

local function IsNativeTitleSelected(mask)
	local ok, currentMask = pcall(GetCurrentTitle);
	return ok and tonumber(currentMask) == tonumber(mask);
end

local function SelectAddonTitle(titleID)
	Achievements.SetCurrentAddonTitle(titleID);
end

local function IsAddonTitleSelected(titleID)
	return GetCurrentTitleID() == tonumber(titleID);
end

local function SelectNoTitle()
	Achievements.SetCurrentAddonTitle(nil);
end

local function GetCurrentPVPTitleText(playerName)
	playerName = playerName or UnitName("player");
	if not playerName or playerName == "" then
		return nil;
	end
	local pvpName = UnitPVPName("player");
	if type(pvpName) == "string" and pvpName ~= "" and pvpName ~= playerName then
		return pvpName;
	end
	return nil;
end

local function SelectPVPTitle()
	pcall(SetCurrentTitle, -1);
	StoreSelectedTitleID(nil);
	SendTitleBroadcast(true);
	RefreshPaperDollTitleDropdown();
	UpdatePaperDollCharacterName();
	RefreshVisibleTooltipName();
end

local function IsPVPTitleSelected()
	if not GetCurrentPVPTitleText() then
		return false;
	end
	if IsPVPTitleSuppressed() then
		return false;
	end
	if tonumber(GetCharacterTitleDB().selectedTitleID) then
		return false;
	end
	local ok, currentMask = pcall(GetCurrentTitle);
	if ok and tonumber(currentMask) and tonumber(currentMask) > 0 then
		return false;
	end
	return true;
end

local function IsNoTitleSelected()
	if IsPVPTitleSuppressed() then
		return true;
	end
	local ok, currentMask = pcall(GetCurrentTitle);
	if ok and tonumber(currentMask) and tonumber(currentMask) > 0 then
		return false;
	end
	if GetCurrentPVPTitleText() then
		return false;
	end
	local currentTitleID = GetCurrentTitleID();
	return currentTitleID == nil;
end

local function SetTitleButtonSize(button, width, height)
	if button.SetSize then
		button:SetSize(width, height);
	else
		if button.SetWidth then
			button:SetWidth(width);
		end
		if button.SetHeight then
			button:SetHeight(height);
		end
	end
end

local function SetTitleButtonText(button, text)
	if button.SetText then
		button:SetText(text);
		return;
	end
	if not button.Text and button.CreateFontString then
		button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
		button.Text:SetAllPoints(button);
		button.Text:SetJustifyH("CENTER");
	end
	if button.Text then
		button.Text:SetText(text);
	end
end

local function CreateFallbackTitleButton(frame)
	local ok, button = pcall(CreateFrame, "Button", "AchievementsPaperDollTitleButton", frame, "UIPanelButtonTemplate");
	if not ok or not button then
		ok, button = pcall(CreateFrame, "Button", "AchievementsPaperDollTitleButton", frame);
	end
	if not ok or not button then
		return nil;
	end
	button.achievementsTitleDropdownStyle = "button";
	if button.RegisterForClicks then
		button:RegisterForClicks("AnyUp");
	end
	if button.SetNormalFontObject and GameFontNormalSmall then
		button:SetNormalFontObject(GameFontNormalSmall);
	end
	if button.SetHighlightFontObject and GameFontHighlightSmall then
		button:SetHighlightFontObject(GameFontHighlightSmall);
	end
	if button.SetBackdrop then
		button:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 8,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		});
		button:SetBackdropColor(0, 0, 0, 0.45);
		button:SetBackdropBorderColor(0.75, 0.75, 0.75, 0.85);
	end
	SetTitleButtonSize(button, 160, 22);
	SetTitleButtonText(button, PAPERDOLL_SELECT_TITLE or "Select Title");
	return button;
end

local function EnsurePaperDollTitleDropdown(frame)
	frame = frame or PaperDollFrame;
	if not frame then
		return nil;
	end

	local dropdown = frame.TitleDropdown or _G.PlayerTitleDropdown;
	if dropdown then
		frame.TitleDropdown = dropdown;
		return dropdown;
	end
	local modernAttempts = {
		{ "DropdownButton", "AchievementsPaperDollTitleDropdownButton" },
	};
	for _, attempt in ipairs(modernAttempts) do
		local ok, created = pcall(CreateFrame, attempt[1], attempt[2], frame, "WowStyle1DropdownTemplate");
		if ok and created and created.SetupMenu and created.GenerateMenu then
			dropdown = created;
			dropdown.achievementsTitleDropdownStyle = "modern";
			break;
		elseif ok and created and created.Hide then
			created:Hide();
		end
	end

	if not dropdown then
		local ok, created = pcall(CreateFrame, "Frame", "AchievementsPaperDollTitleDropdownLegacy", frame, "UIDropDownMenuTemplate");
		if ok and created then
			dropdown = created;
			dropdown.achievementsTitleDropdownStyle = "legacy";
		end
	end

	if not dropdown then
		dropdown = CreateFallbackTitleButton(frame);
	end

	if not dropdown then
		return nil;
	end

	frame.TitleDropdown = dropdown;
	if dropdown.SetFrameLevel and frame.GetFrameLevel then
		dropdown:SetFrameLevel((frame:GetFrameLevel() or 0) + 20);
	end
	if dropdown.SetWidth then
		dropdown:SetWidth(160);
	else
		UIDropDownMenu_SetWidth(dropdown, 160);
	end
	if dropdown.SetDefaultText then
		dropdown:SetDefaultText(PAPERDOLL_SELECT_TITLE or "Select Title");
	else
		UIDropDownMenu_SetText(dropdown, PAPERDOLL_SELECT_TITLE or "Select Title");
	end
	if dropdown.ClearAllPoints then
		dropdown:ClearAllPoints();
	end
	if CharacterLevelText then
		dropdown:SetPoint("TOP", CharacterLevelText, "BOTTOM", 0, -6);
	elseif CharacterNameFrame then
		dropdown:SetPoint("TOP", CharacterNameFrame, "BOTTOM", 0, -18);
	else
		dropdown:SetPoint("TOP", frame, "TOP", 0, -32);
	end
	return dropdown;
end

local function BuildTitleMenuEntries()
	local playerName = UnitName("player") or "";
	local playerSex = UnitSex("player");
	local entries = {};
	local nativeMasks = {};
	local ok, numTitles = pcall(GetNumTitles);
	numTitles = ok and tonumber(numTitles) or 0;
	for titleMask = 1, numTitles do
		local knownOK, known = pcall(IsTitleKnown, titleMask);
		if knownOK and known then
			local nameOK, titleName = pcall(GetTitleName, titleMask);
			if nameOK and type(titleName) == "string" and titleName ~= "" then
				nativeMasks[titleMask] = true;
				entries[#entries + 1] = {
					text = StripPlayerNameFromTitleText(titleName, playerName) or titleName,
					check = IsNativeTitleSelected,
					select = SelectNativeTitle,
					value = titleMask,
				};
			end
		end
	end

	local pvpTitleText = GetCurrentPVPTitleText(playerName);
	if pvpTitleText then
		entries[#entries + 1] = {
			text = StripPlayerNameFromTitleText(pvpTitleText, playerName) or pvpTitleText,
			check = IsPVPTitleSelected,
			select = SelectPVPTitle,
			value = "pvp",
		};
	end

	for _, entry in ipairs(Achievements.GetEarnedAddonTitles()) do
		local title = entry.title;
		if not (title.mask and nativeMasks[title.mask]) then
			entries[#entries + 1] = {
				text = FormatTitleLabel(title, playerName, playerSex) or FormatTitleName(title, playerName, playerSex),
				check = IsAddonTitleSelected,
				select = SelectAddonTitle,
				value = entry.id,
			};
		end
	end

	entries[#entries + 1] = {
		text = NONE or "None",
		check = IsNoTitleSelected,
		select = SelectNoTitle,
		value = -1,
	};
	return entries;
end

local function ConfigureModernTitleMenu(dropdown, entries)
	dropdown:SetupMenu(function(_, rootDescription)
		if rootDescription.SetTag then
			rootDescription:SetTag("MENU_PAPERDOLL_FRAME_TITLE");
		end

		for _, entry in ipairs(entries) do
			rootDescription:CreateRadio(entry.text, entry.check, entry.select, entry.value);
		end
	end);
end

local function LegacyTitleDropdown_OnClick(_, entry)
	if entry and entry.select then
		entry.select(entry.value);
	end
end

local function GetSelectedTitleMenuText(entries)
	for _, entry in ipairs(entries) do
		if entry.check(entry.value) then
			return entry.text;
		end
	end
	return PAPERDOLL_SELECT_TITLE or "Select Title";
end

local function SelectNextTitleMenuEntry(entries)
	local selectedIndex = 0;
	for entryIndex, entry in ipairs(entries) do
		if entry.check(entry.value) then
			selectedIndex = entryIndex;
			break;
		end
	end
	local nextEntry = entries[selectedIndex + 1] or entries[1];
	if nextEntry and nextEntry.select then
		nextEntry.select(nextEntry.value);
	end
end

local function ShowFallbackTitleMenu(button, entries)
	if EasyMenu then
		if not fallbackTitleMenuFrame then
			local ok, menuFrame = pcall(CreateFrame, "Frame", "AchievementsPaperDollTitleMenu", UIParent or button, "UIDropDownMenuTemplate");
			if ok then
				fallbackTitleMenuFrame = menuFrame;
			end
		end
		if fallbackTitleMenuFrame then
			local menu = {};
			for _, entry in ipairs(entries) do
				menu[#menu + 1] = {
					text = entry.text,
					arg1 = entry,
					func = LegacyTitleDropdown_OnClick,
					checked = entry.check(entry.value) == true,
					isNotRadio = false,
					keepShownOnClick = false,
				};
			end
			EasyMenu(menu, fallbackTitleMenuFrame, button, 0, 0, "MENU");
			return;
		end
	end
	SelectNextTitleMenuEntry(entries);
end

local function ConfigureFallbackTitleButton(button, entries)
	SetTitleButtonText(button, GetSelectedTitleMenuText(entries));
	button:SetScript("OnClick", function(self)
		ShowFallbackTitleMenu(self, entries);
	end);
end

local function ConfigureLegacyTitleMenu(dropdown, entries)
	UIDropDownMenu_Initialize(dropdown, function(_, level)
		for _, entry in ipairs(entries) do
			local info = UIDropDownMenu_CreateInfo();
			info.text = entry.text;
			info.arg1 = entry;
			info.func = LegacyTitleDropdown_OnClick;
			info.checked = entry.check(entry.value) == true;
			info.isNotRadio = false;
			UIDropDownMenu_AddButton(info, level);
		end
	end);

	for _, entry in ipairs(entries) do
		if entry.check(entry.value) then
			UIDropDownMenu_SetText(dropdown, entry.text);
			return;
		end
	end
	UIDropDownMenu_SetText(dropdown, PAPERDOLL_SELECT_TITLE or "Select Title");
end

local function ConfigureTitleMenu(dropdown)
	if not dropdown then
		return;
	end

	local entries = BuildTitleMenuEntries();
	if dropdown.achievementsTitleDropdownStyle == "button" then
		ConfigureFallbackTitleButton(dropdown, entries);
	elseif dropdown.SetupMenu and dropdown.GenerateMenu then
		ConfigureModernTitleMenu(dropdown, entries);
	else
		ConfigureLegacyTitleMenu(dropdown, entries);
	end
end

local function GetCommandTitleEntries()
	local commandEntries = {};
	for _, entry in ipairs(BuildTitleMenuEntries()) do
		if entry.value ~= -1 then
			commandEntries[#commandEntries + 1] = entry;
		end
	end
	return commandEntries;
end

local function SetKnownTitleText(fontString, playerName, unit)
	if not fontString or not fontString.SetText then
		return false;
	end
	local displayName = GetKnownPlayerDisplayName(playerName, unit);
	if not displayName or displayName == "" then
		if fontString.achievementsTitleApplied then
			local baseName = unit and GetUnitBaseName(unit) or nil;
			local resetText = baseName or "";
			if not fontString.GetText or fontString:GetText() ~= resetText then
				fontString.achievementsTitleUpdating = true;
				fontString:SetText(resetText);
				fontString.achievementsTitleUpdating = nil;
			end
			fontString.achievementsTitleApplied = nil;
			fontString.achievementsTitleDisplayName = nil;
		end
		return false;
	end
	if not fontString.GetText or fontString:GetText() ~= displayName then
		fontString.achievementsTitleUpdating = true;
		fontString:SetText(displayName);
		fontString.achievementsTitleUpdating = nil;
	end
	fontString.achievementsTitleApplied = true;
	fontString.achievementsTitleDisplayName = displayName;
	return true;
end

local function SetKnownTitleUnitText(fontString, unit)
	return SetKnownTitleText(fontString, nil, unit);
end

local function HookKnownTitleFontString(fontString, unit)
	if not fontString then
		return;
	end
	fontString.achievementsTitleUnit = unit or fontString.achievementsTitleUnit;
	if fontString.achievementsTitleHooked then
		return;
	end
	local ok = pcall(hooksecurefunc, fontString, "SetText", function(self, text)
		if self.achievementsTitleUpdating then
			return;
		end
		local hookedUnit = self.achievementsTitleUnit;
		if not hookedUnit then
			return;
		end
		local displayName = GetKnownPlayerDisplayName(nil, hookedUnit);
		if displayName and displayName ~= "" and text ~= displayName then
			DebugTitle("reapply nameplate unit=" .. tostring(hookedUnit) .. " text=" .. tostring(text) .. " title=" .. tostring(displayName));
			SetKnownTitleUnitText(self, hookedUnit);
		end
	end);
	fontString.achievementsTitleHooked = ok == true;
end

local function UpdateKnownTitleUnitFrame(frame, unit)
	if not frame then
		return;
	end
	unit = unit or frame.unit or frame.displayedUnit or frame.unitToken;
	local nameText = frame.name or frame.Name or frame.nameText or frame.NameText;
	if nameText then
		HookKnownTitleFontString(nameText, unit);
		SetKnownTitleUnitText(nameText, unit);
	end
end

local function UpdateKnownTitleNamePlate(unit)
	if not unit then
		return;
	end
	local ok, namePlate = pcall(C_NamePlate.GetNamePlateForUnit, unit);
	if not ok then
		return;
	end
	local unitFrame = namePlate and (namePlate.UnitFrame or namePlate.unitFrame or namePlate);
	if not unitFrame then
		return;
	end
	UpdateKnownTitleUnitFrame(unitFrame, unit);
	if unitFrame.healthBar then
		UpdateKnownTitleUnitFrame(unitFrame.healthBar, unit);
	end
end

UpdateVisibleKnownTitleNames = function()
	for raidIndex = 1, 40 do
		UpdateKnownTitleNamePlate("nameplate" .. raidIndex);
	end
end

UpdateTooltipKnownPlayerName = function(tooltip)
	if not tooltip or not tooltip.GetUnit then
		return;
	end
	local tooltipName, unit = tooltip:GetUnit();
	local displayName = GetKnownPlayerDisplayName(tooltipName, unit);
	if not displayName or displayName == "" then
		return;
	end
	local tooltipFrameName = tooltip.GetName and tooltip:GetName() or nil;
	local titleLine = tooltipFrameName and _G[tooltipFrameName .. "TextLeft1"] or nil;
	if titleLine and titleLine.SetText and (not titleLine.GetText or titleLine:GetText() ~= displayName) then
		DebugTitle("tooltip unit=" .. tostring(unit) .. " tooltipName=" .. tostring(tooltipName) .. " title=" .. tostring(displayName));
		titleLine:SetText(displayName);
	end
end

local function TooltipTitleOnUpdate(self, elapsed)
	self.achievementsTitleElapsed = (self.achievementsTitleElapsed or 0) + (elapsed or 0);
	if self.achievementsTitleElapsed < 0.05 then
		return;
	end
	self.achievementsTitleElapsed = 0;
	UpdateTooltipKnownPlayerName(self);
end

local function HookTooltipTitles()
	if tooltipUnitHooked or not GameTooltip then
		if not tooltipOnUpdateHooked and GameTooltip and GameTooltip.HookScript then
			local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnUpdate", TooltipTitleOnUpdate);
			tooltipOnUpdateHooked = ok == true;
		end
		return;
	end
	if GameTooltip.HookScript then
		local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", UpdateTooltipKnownPlayerName);
		tooltipUnitHooked = ok == true;
	end
	if not tooltipUnitHooked and GameTooltip.SetUnit then
		local originalSetUnit = GameTooltip.SetUnit;
		GameTooltip.SetUnit = function(self, ...)
			originalSetUnit(self, ...);
			UpdateTooltipKnownPlayerName(self);
		end;
		tooltipUnitHooked = true;
	end
	if not tooltipOnUpdateHooked and GameTooltip.HookScript then
		local ok = pcall(GameTooltip.HookScript, GameTooltip, "OnUpdate", TooltipTitleOnUpdate);
		tooltipOnUpdateHooked = ok == true;
	end
end

function Achievements.UpdateAddonTitleDropdown(frame)
	local dropdown = EnsurePaperDollTitleDropdown(frame);
	if not dropdown then
		return;
	end
	local hasTitles = Achievements.PlayerTitleDropdown_IsTitleAvailable();
	if dropdown.SetShown then
		dropdown:SetShown(hasTitles);
	elseif hasTitles then
		dropdown:Show();
	else
		dropdown:Hide();
	end
	if hasTitles then
		ConfigureTitleMenu(dropdown);
	end
	UpdatePaperDollCharacterName();
end

function Achievements.PlayerTitleDropdown_IsTitleAvailable()
	if GetCurrentPVPTitleText() then
		return true;
	end
	local ok, numTitles = pcall(GetNumTitles);
	numTitles = ok and tonumber(numTitles) or 0;
	for titleMask = 1, numTitles do
		local knownOK, known = pcall(IsTitleKnown, titleMask);
		if knownOK and known then
			return true;
		end
	end
	return #Achievements.GetEarnedAddonTitles() > 0;
end

function Achievements.GetEarnedAddonTitles()
	local titles = {};
	local seenTitles = {};
	for achievementID, achievement in pairs(ACHIEVEMENT_DATA) do
		local titleID = ResolveAchievementTitleID(achievement);
		local title = titleID and TITLE_DATA[titleID];
		if title and not seenTitles[titleID]
			and (not Private.IsAchievementForPlayerFaction or Private.IsAchievementForPlayerFaction(achievement))
			and Private.IsAchievementCompleted and Private.IsAchievementCompleted(achievementID) then
			seenTitles[titleID] = true;
			titles[#titles + 1] = {
				id = titleID,
				achievementID = achievementID,
				title = title,
				reward = achievement.reward,
			};
		end
	end
	table.sort(titles, function(left, right)
		local leftName = left.title and left.title.name or "";
		local rightName = right.title and right.title.name or "";
		if leftName ~= rightName then
			return leftName < rightName;
		end
		return (left.achievementID or 0) < (right.achievementID or 0);
	end);
	return titles;
end

function Achievements.GetCurrentAddonTitleID()
	return GetCurrentTitleID();
end

function Achievements.GetCurrentAddonTitleInfo()
	local titleID = GetCurrentTitleID();
	return titleID and TITLE_DATA[titleID] or nil;
end

function Achievements.GetAddonTitleSnapshot()
	return GetCurrentTitleSnapshot();
end

function Achievements.SetCurrentAddonTitle(titleID)
	titleID = tonumber(titleID);
	if not titleID or titleID <= 0 then
		pcall(SetCurrentTitle, -1);
		StoreNoTitleSelection();
		SendTitleBroadcast(true);
		RefreshPaperDollTitleDropdown();
		UpdatePaperDollCharacterName();
		RefreshVisibleTooltipName();
		return true;
	end

	if not IsTitleAvailableLocally(titleID) then
		PrintMessage("|cffff8080Achievements:|r You have not earned that title yet.");
		return false;
	end

	local title = TITLE_DATA[titleID];
	if title and IsNativeTitleKnown(title) then
		pcall(SetCurrentTitle, title.mask);
	else
		pcall(SetCurrentTitle, -1);
	end
	StoreSelectedTitleID(titleID);
	SendTitleBroadcast(true);
	RefreshPaperDollTitleDropdown();
	UpdatePaperDollCharacterName();
	RefreshVisibleTooltipName();
	return true;
end

function Achievements.FormatAddonTitleName(titleID, playerName)
	return FormatTitleName(TITLE_DATA[tonumber(titleID) or 0], playerName);
end

function Achievements.FormatPlayerNameWithAddonTitle(playerName, titleID)
	titleID = tonumber(titleID) or GetCurrentTitleID();
	if titleID and TITLE_DATA[titleID] then
		return FormatTitleName(TITLE_DATA[titleID], playerName);
	end
	return playerName or "";
end

function Achievements.StoreRemoteAddonTitleSnapshot(sender, titleID, achievementID)
	StoreRemoteTitleSnapshot(sender, titleID, achievementID);
end

function Achievements.HandleAddonTitleMessage(payload, sender)
	local version, titleID, achievementID = strsplit("\t", payload or "");
	if version ~= TITLE_MESSAGE_VERSION then
		return;
	end
	StoreRemoteTitleSnapshot(sender, titleID, achievementID);
end

function Achievements.GetRemoteAddonTitle(playerName)
	local record = GetRemoteTitleRecord(playerName);
	if not record then
		return nil;
	end
	return record.titleID, TITLE_DATA[record.titleID], record.titleAchievementID, record.seenAt;
end

function Achievements.BroadcastAddonTitle(force)
	return SendTitleBroadcast(force);
end

function Achievements.hookAddonTitles()
	HookTooltipTitles();

	if not titleAvailabilityHooked then
		local originalAvailability = _G.PlayerTitleDropdown_IsTitleAvailable;
		_G.PlayerTitleDropdown_IsTitleAvailable = function(...)
			if type(originalAvailability) == "function" then
				local ok, available = pcall(originalAvailability, ...);
				if ok and available then
					return true;
				end
			end
			return Achievements.PlayerTitleDropdown_IsTitleAvailable();
		end;
		titleAvailabilityHooked = true;
	end

	if not paperDollOnShowHooked and _G.PaperDollFrame_OnShow then
		local ok = pcall(hooksecurefunc, "PaperDollFrame_OnShow", function(frame)
			Achievements.UpdateAddonTitleDropdown(frame);
			UpdatePaperDollCharacterName();
		end);
		paperDollOnShowHooked = ok == true;
	end

	if not paperDollFrameScriptHooked and PaperDollFrame then
		local function OnPaperDollShow(frame)
			Achievements.UpdateAddonTitleDropdown(frame);
			UpdatePaperDollCharacterName();
		end
		if PaperDollFrame.HookScript then
			local ok = pcall(PaperDollFrame.HookScript, PaperDollFrame, "OnShow", OnPaperDollShow);
			paperDollFrameScriptHooked = ok == true;
		elseif PaperDollFrame.GetScript and PaperDollFrame.SetScript then
			local originalOnShow = PaperDollFrame:GetScript("OnShow");
			local ok = pcall(PaperDollFrame.SetScript, PaperDollFrame, "OnShow", function(frame, ...)
				if originalOnShow then
					originalOnShow(frame, ...);
				end
				OnPaperDollShow(frame);
			end);
			paperDollFrameScriptHooked = ok == true;
		end
	end

	if not characterFrameOnShowHooked and _G.CharacterFrame_OnShow then
		local ok = pcall(hooksecurefunc, "CharacterFrame_OnShow", function()
			Achievements.UpdateAddonTitleDropdown(PaperDollFrame);
			UpdatePaperDollCharacterName();
		end);
		characterFrameOnShowHooked = ok == true;
	end

	if not characterFrameOnEventHooked and _G.CharacterFrame_OnEvent then
		local function UpdateNameAfterCharacterEvent(_, event, unit)
			if event == "PLAYER_PVP_RANK_CHANGED" or (event == "UNIT_NAME_UPDATE" and unit == "player") then
				UpdatePaperDollCharacterName();
			end
		end

		local ok = pcall(hooksecurefunc, "CharacterFrame_OnEvent", UpdateNameAfterCharacterEvent);
		characterFrameOnEventHooked = ok == true;
	end

	RefreshPaperDollTitleDropdown();
	UpdatePaperDollCharacterName();
	if UpdateVisibleKnownTitleNames then
		UpdateVisibleKnownTitleNames();
	end
end

local titleEventFrame = CreateFrame("Frame");
	titleEventFrame:RegisterEvent("ADDON_LOADED");
	titleEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
	pcall(titleEventFrame.RegisterEvent, titleEventFrame, "GROUP_ROSTER_UPDATE");
	pcall(titleEventFrame.RegisterEvent, titleEventFrame, "RAID_ROSTER_UPDATE");
	pcall(titleEventFrame.RegisterEvent, titleEventFrame, "GUILD_ROSTER_UPDATE");
	pcall(titleEventFrame.RegisterEvent, titleEventFrame, "PLAYER_GUILD_UPDATE");
	pcall(titleEventFrame.RegisterEvent, titleEventFrame, "UNIT_NAME_UPDATE");
	pcall(titleEventFrame.RegisterEvent, titleEventFrame, "NAME_PLATE_UNIT_ADDED");
	pcall(titleEventFrame.RegisterEvent, titleEventFrame, "PLAYER_PVP_RANK_CHANGED");
	titleEventFrame:SetScript("OnEvent", function(_, event, arg1)
		if event == "ADDON_LOADED" and arg1 ~= "Achievements" and arg1 ~= "Blizzard_CharacterFrame" then
			return;
		end
		if event == "NAME_PLATE_UNIT_ADDED" then
			UpdateKnownTitleNamePlate(arg1);
			return;
		end
		if event == "UNIT_NAME_UPDATE" then
			UpdateKnownTitleNamePlate(arg1);
			if UpdateTooltipKnownPlayerName and GameTooltip and (not GameTooltip.IsShown or GameTooltip:IsShown()) then
				UpdateTooltipKnownPlayerName(GameTooltip);
			end
			return;
		end
		Achievements.hookAddonTitles();
		if UpdateVisibleKnownTitleNames then
			UpdateVisibleKnownTitleNames();
		end
		if event == "ADDON_LOADED" or event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE"
			or event == "RAID_ROSTER_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
			CallAfter(3, function()
				SendTitleBroadcast(true);
			end);
		end
	end);
	titleEventFrame:SetScript("OnUpdate", function(self, elapsed)
		self.titlePollElapsed = (self.titlePollElapsed or 0) + (elapsed or 0);
		if self.titlePollElapsed < 0.5 then
			return;
		end
		local pollElapsed = self.titlePollElapsed;
		self.titlePollElapsed = 0;
		if PaperDollFrame and not paperDollFrameScriptHooked then
			Achievements.hookAddonTitles();
		end
		if PaperDollFrame and PaperDollFrame:IsVisible() then
			Achievements.UpdateAddonTitleDropdown(PaperDollFrame);
		end
		self.titleNameplatePollElapsed = (self.titleNameplatePollElapsed or 0) + pollElapsed;
		if self.titleNameplatePollElapsed >= 2 and UpdateVisibleKnownTitleNames then
			self.titleNameplatePollElapsed = 0;
			UpdateVisibleKnownTitleNames();
		end
	end);

SLASH_ACHIEVEMENTSTITLE1 = "/ach-title";
SlashCmdList["ACHIEVEMENTSTITLE"] = function(arg)
	local command = tostring(arg or ""):match("^%s*(.-)%s*$");
	if command == "" or string.lower(command) == "list" then
		local titleEntries = GetCommandTitleEntries();
		PrintMessage("Achievements titles available: " .. tostring(#titleEntries));
		for titleIndex, entry in ipairs(titleEntries) do
			PrintMessage("  " .. tostring(titleIndex) .. ". " .. entry.text);
		end
		return;
	end
	if string.lower(command) == "none" or string.lower(command) == "off" then
		Achievements.SetCurrentAddonTitle(nil);
		return;
	end
	local selectedIndex = tonumber(command);
	if selectedIndex then
		local entry = GetCommandTitleEntries()[selectedIndex];
		if entry then
			entry.select(entry.value);
			return;
		end
	end
	PrintMessage("Usage: /ach-title, /ach-title <number>, or /ach-title none");
end