local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsMicroButton.lua");
end

local Private = Achievements.private;

local LEGACY_MICRO_BUTTON_SCALE = Private.LEGACY_MICRO_BUTTON_SCALE or 0.9;
local LEGACY_MICRO_BUTTON_SPACING = Private.LEGACY_MICRO_BUTTON_SPACING or -3;
local LEGACY_MICRO_BUTTON_BASE_X = 552 + 42;
local LEGACY_MICRO_BUTTON_BASE_Y = 4;
local LEGACY_MAIN_MENU_BAR_WIDTH = 1024;
local LEGACY_MAIN_MENU_BAR_HEIGHT = 53;
local LEGACY_MAIN_MENU_BAR_ART_HEIGHT = 43;
local LEGACY_MAIN_MENU_BAR_XP_HEIGHT = 13;
local LEGACY_MAIN_MENU_BAR_MAX_LEVEL_HEIGHT = 7;

local nativeAchievementUILoaded;
local nativeAchievementUILoadReason;
local achievementMicroButtonInserted;
local microMenuButtonInfoHooked;
local updateMicroButtonsHooked;
local achievementShieldOnLoadPatched;
local achievementComparisonShieldDisplayPatched;
local achievementComparisonShieldButtonPatched;
local achievementStatsUIPatched;
local achievementSummaryUIPatched;
local achievementComparisonUIPatched;
local achievementSummaryStatisticSelectionPatched;
local achievementCriteriaRefreshUIPatched;
local originalAchievementFrameStatsOnEvent;
local statsUICacheVersion = 0;
local statsUIDisplayCache = {
	category = nil,
	version = nil,
	rows = {},
};
local comparisonStatsUIDisplayCache = {
	category = nil,
	version = nil,
	rows = {},
};

local function IsInCombatLockdown()
	return InCombatLockdown() == true;
end

local function PrintMessage(message)
	if Private.PrintMessage then
		Private.PrintMessage(message);
	elseif DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(message);
	end
end

local function SetAchievementMicroButtonTooltip(button)
	local title = ACHIEVEMENT_BUTTON or "Achievements";
	button.tooltipText = MicroButtonTooltipText(title, "TOGGLEACHIEVEMENT");

	button.newbieText = NEWBIE_TOOLTIP_ACHIEVEMENT or "View information about your achievements and statistics.";
end

local function ConfigureAchievementMicroButton(button)
	LoadMicroButtonTextures(button, "Achievement");

	SetAchievementMicroButtonTooltip(button);
	button:SetScript("OnEvent", SetAchievementMicroButtonTooltip);
	button:SetScript("OnClick", function()
		Achievements.ToggleAchievementFrame();
	end);
	button:Show();
end

local function InsertAchievementMicroButtonName()
	if IsInCombatLockdown() then
		return;
	end

	if type(MICRO_BUTTONS) ~= "table" then
		return;
	end

	for _, buttonName in ipairs(MICRO_BUTTONS) do
		if buttonName == "AchievementMicroButton" then
			return;
		end
	end

	local insertIndex = #MICRO_BUTTONS + 1;
	for index, buttonName in ipairs(MICRO_BUTTONS) do
		if buttonName == "QuestLogMicroButton" then
			insertIndex = index;
			break;
		end
	end

	table.insert(MICRO_BUTTONS, insertIndex, "AchievementMicroButton");
end

local function InsertAchievementMicroButtonInfo(buttonInfos, button)
	if IsInCombatLockdown() then
		return buttonInfos;
	end

	if type(buttonInfos) ~= "table" or not button or not MicroMenuUtil or not MicroMenuUtil.GenerateButtonInfo then
		return buttonInfos;
	end

	for _, buttonInfo in ipairs(buttonInfos) do
		if buttonInfo.button == button then
			return buttonInfos;
		end
	end

	local insertIndex = #buttonInfos + 1;
	for index, buttonInfo in ipairs(buttonInfos) do
		if buttonInfo.button == QuestLogMicroButton then
			insertIndex = index;
			break;
		end
	end

	table.insert(buttonInfos, insertIndex, MicroMenuUtil.GenerateButtonInfo(button));
	return buttonInfos;
end

local function HookMicroMenuButtonInfos()
	if microMenuButtonInfoHooked or not MicroMenuMixin or not MicroMenuMixin.GenerateButtonInfos then
		return;
	end

	local originalGenerateButtonInfos = MicroMenuMixin.GenerateButtonInfos;
	MicroMenuMixin.GenerateButtonInfos = function(self)
		local buttonInfos = originalGenerateButtonInfos(self);
		return InsertAchievementMicroButtonInfo(buttonInfos, AchievementMicroButton);
	end;
	microMenuButtonInfoHooked = true;
end

local function InsertAchievementMicroButtonIntoLiveMenu(button)
	if IsInCombatLockdown() then
		return;
	end

	if achievementMicroButtonInserted or not button or not MicroMenu or not MicroMenu.AddButton then
		return;
	end

	local alreadyInMenu = button.GetParent and button:GetParent() == MicroMenu and button.layoutIndex;
	if not alreadyInMenu then
		MicroMenu:AddButton(button);
	end

	local desiredIndex = QuestLogMicroButton and QuestLogMicroButton.layoutIndex;
	if desiredIndex and button.layoutIndex and button.layoutIndex > desiredIndex then
		for _, child in ipairs({ MicroMenu:GetChildren() }) do
			if child ~= button and child.layoutIndex and child.layoutIndex >= desiredIndex then
				child.layoutIndex = child.layoutIndex + 1;
			end
		end

		button.layoutIndex = desiredIndex;
	end

	local numButtons = 0;
	for _, child in ipairs({ MicroMenu:GetChildren() }) do
		if child.layoutIndex then
			numButtons = math.max(numButtons, child.layoutIndex);
		end
	end

	MicroMenu.numButtons = numButtons;
	MicroMenu.stride = MicroMenu.isStacked and math.floor(numButtons / 2) or numButtons;
	MicroMenu:MarkDirty();
	MicroMenu:Layout();

	if MicroMenuContainer and MicroMenuContainer.Layout then
		MicroMenuContainer:Layout();
	end

	achievementMicroButtonInserted = true;
end

local function SetBottomPoint(frame, relativeTo, x, y)
	if not frame or not relativeTo then
		return;
	end

	frame:ClearAllPoints();
	frame:SetPoint("BOTTOM", relativeTo, "BOTTOM", x, y or 0);
end

local function ApplyLegacyMicroButtonScale(...)
	for index = 1, select("#", ...) do
		local button = select(index, ...);
		if button and button.SetScale then
			button:SetScale(LEGACY_MICRO_BUTTON_SCALE);
		end
	end
end

local function ApplyLegacyMainMenuBarStockLayout()
	if not MainMenuBar or not MainMenuBarArtFrame then
		return;
	end

	local parent = MainMenuBar:GetParent() or UIParent;

	MainMenuBar:ClearAllPoints();
	MainMenuBar:SetPoint("BOTTOM", parent, "BOTTOM", 0, 0);
	MainMenuBar:SetSize(LEGACY_MAIN_MENU_BAR_WIDTH, LEGACY_MAIN_MENU_BAR_HEIGHT);

	if MainMenuExpBar then
		MainMenuExpBar:SetSize(LEGACY_MAIN_MENU_BAR_WIDTH, LEGACY_MAIN_MENU_BAR_XP_HEIGHT);
	end

	if MainMenuBarMaxLevelBar then
		MainMenuBarMaxLevelBar:SetSize(LEGACY_MAIN_MENU_BAR_WIDTH, LEGACY_MAIN_MENU_BAR_MAX_LEVEL_HEIGHT);
	end

	SetBottomPoint(MainMenuBarTexture0, MainMenuBarArtFrame, -384, 0);
	SetBottomPoint(MainMenuBarTexture1, MainMenuBarArtFrame, -128, 0);
	SetBottomPoint(MainMenuBarTexture2, MainMenuBarArtFrame, 128, 0);
	if MainMenuBarTextureExtender then
		MainMenuBarTextureExtender:Hide();
	end
	if MainMenuBarTexture3 then
		MainMenuBarTexture3:SetSize(256, LEGACY_MAIN_MENU_BAR_ART_HEIGHT);
		SetBottomPoint(MainMenuBarTexture3, MainMenuBarArtFrame, 384, 0);
	end

	SetBottomPoint(MainMenuBarLeftEndCap, MainMenuBarArtFrame, -544, 0);
	SetBottomPoint(MainMenuBarRightEndCap, MainMenuBarArtFrame, 544, 0);

	SetBottomPoint(MainMenuXPBarTexture0, MainMenuExpBar, -384, 3);
	SetBottomPoint(MainMenuXPBarTexture1, MainMenuExpBar, -128, 3);
	SetBottomPoint(MainMenuXPBarTexture2, MainMenuExpBar, 128, 3);
	if MainMenuXPBarTexture3 then
		MainMenuXPBarTexture3:SetSize(256, 10);
		SetBottomPoint(MainMenuXPBarTexture3, MainMenuExpBar, 384, 3);
	end

	if MainMenuBarPageNumber then
		MainMenuBarPageNumber:ClearAllPoints();
		MainMenuBarPageNumber:SetPoint("CENTER", MainMenuBarArtFrame, "CENTER", 30, -5);
	end

	if ActionBarUpButton then
		ActionBarUpButton:ClearAllPoints();
		ActionBarUpButton:SetPoint("CENTER", MainMenuBarArtFrame, "TOPLEFT", 522, -22);
	end
	if ActionBarDownButton then
		ActionBarDownButton:ClearAllPoints();
		ActionBarDownButton:SetPoint("CENTER", MainMenuBarArtFrame, "TOPLEFT", 522, -42);
	end

end

local function LayoutLegacyAchievementMicroButton(button)
	if IsInCombatLockdown() then
		return false;
	end

	if MicroMenu and MicroMenu.AddButton then
		return false;
	end

	if not button or not CharacterMicroButton or not SpellbookMicroButton or not TalentMicroButton or not QuestLogMicroButton or not SocialsMicroButton then
		return false;
	end

	local parent = CharacterMicroButton:GetParent() or UIParent;
	button:SetParent(parent);
	button:SetFrameStrata(QuestLogMicroButton:GetFrameStrata());
	button:SetFrameLevel(QuestLogMicroButton:GetFrameLevel());
	ApplyLegacyMicroButtonScale(CharacterMicroButton, SpellbookMicroButton, TalentMicroButton, button, QuestLogMicroButton, SocialsMicroButton, GuildMicroButton, WorldMapMicroButton, MainMenuMicroButton, HelpMicroButton);
	button:ClearAllPoints();

	if TalentMicroButton:IsShown() then
		button:SetPoint("BOTTOMLEFT", TalentMicroButton, "BOTTOMRIGHT", LEGACY_MICRO_BUTTON_SPACING, 0);
	else
		button:SetPoint("BOTTOMLEFT", TalentMicroButton, "BOTTOMLEFT", 0, 0);
	end

	QuestLogMicroButton:ClearAllPoints();
	QuestLogMicroButton:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", LEGACY_MICRO_BUTTON_SPACING, 0);

	SocialsMicroButton:ClearAllPoints();
	SocialsMicroButton:SetPoint("BOTTOMLEFT", QuestLogMicroButton, "BOTTOMRIGHT", LEGACY_MICRO_BUTTON_SPACING, 0);

	if GuildMicroButton then
		GuildMicroButton:ClearAllPoints();
		GuildMicroButton:SetPoint("CENTER", SocialsMicroButton, "CENTER", 0, 0);
	end

	if WorldMapMicroButton then
		WorldMapMicroButton:ClearAllPoints();
		WorldMapMicroButton:SetPoint("BOTTOMLEFT", GuildMicroButton or SocialsMicroButton, "BOTTOMRIGHT", LEGACY_MICRO_BUTTON_SPACING, 0);
	end

	if MainMenuMicroButton and WorldMapMicroButton then
		MainMenuMicroButton:ClearAllPoints();
		MainMenuMicroButton:SetPoint("BOTTOMLEFT", WorldMapMicroButton, "BOTTOMRIGHT", LEGACY_MICRO_BUTTON_SPACING, 0);
	end

	if HelpMicroButton and MainMenuMicroButton then
		HelpMicroButton:ClearAllPoints();
		HelpMicroButton:SetPoint("BOTTOMLEFT", MainMenuMicroButton, "BOTTOMRIGHT", LEGACY_MICRO_BUTTON_SPACING, 0);
	end

	if MainMenuBarArtFrame then
		ApplyLegacyMainMenuBarStockLayout();
		MICRO_BUTTONS_X_OFFSET = math.max(MICRO_BUTTONS_X_OFFSET or 0, 0);
		CharacterMicroButton:ClearAllPoints();
		CharacterMicroButton:SetPoint("BOTTOMLEFT", MainMenuBarArtFrame, "BOTTOMLEFT", LEGACY_MICRO_BUTTON_BASE_X + MICRO_BUTTONS_X_OFFSET, LEGACY_MICRO_BUTTON_BASE_Y);
	end

	button:Show();
	return true;
end

local function EnsureAchievementMicroButton()
	if AchievementMicroButton then
		if IsInCombatLockdown() then
			return AchievementMicroButton;
		end

		InsertAchievementMicroButtonName();
		HookMicroMenuButtonInfos();
		InsertAchievementMicroButtonIntoLiveMenu(AchievementMicroButton);
		LayoutLegacyAchievementMicroButton(AchievementMicroButton);
		return AchievementMicroButton;
	end

	if IsInCombatLockdown() then
		return nil;
	end

	if not CreateFrame or not UIParent then
		return nil;
	end

	local created, button = pcall(CreateFrame, "Button", "AchievementMicroButton", UIParent, "MainMenuBarMicroButton");
	if not created or not button then
		return nil;
	end

	ConfigureAchievementMicroButton(button);
	InsertAchievementMicroButtonName();
	HookMicroMenuButtonInfos();
	InsertAchievementMicroButtonIntoLiveMenu(button);
	LayoutLegacyAchievementMicroButton(button);

	return button;
end

local function HookUpdateMicroButtons()
	if updateMicroButtonsHooked or not UpdateMicroButtons then
		return;
	end

	local secureHook = rawget(_G, "hooksecurefunc");
	if secureHook then
		secureHook("UpdateMicroButtons", function()
			Achievements.AchievementMicroButton_Update();
		end);
		updateMicroButtonsHooked = true;
		return;
	end

	local originalUpdateMicroButtons = UpdateMicroButtons;
	UpdateMicroButtons = function(...)
		originalUpdateMicroButtons(...);
		Achievements.AchievementMicroButton_Update();
	end;
	updateMicroButtonsHooked = true;
end

local function SetAchievementShieldTextureCoords(shield, saturated)
	if not shield or not shield.icon or not shield.icon.SetTexCoord then
		return;
	end

	if saturated then
		shield.icon:SetTexCoord(0, 0.5, 0, 0.5);
	else
		shield.icon:SetTexCoord(0.5, 1, 0, 0.5);
	end
end

local function SaturateAchievementShield(shield)
	SetAchievementShieldTextureCoords(shield, true);
end

local function DesaturateAchievementShield(shield)
	SetAchievementShieldTextureCoords(shield, false);
end

local function PatchAchievementShieldInstance(shield, saturated)
	if not shield then
		return;
	end
	shield.Saturate = SaturateAchievementShield;
	shield.Desaturate = DesaturateAchievementShield;
	SetAchievementShieldTextureCoords(shield, saturated == true);
end

local function PatchComparisonButtonShields(button)
	if not button then
		return;
	end
	if button.player and button.player.shield then
		PatchAchievementShieldInstance(button.player.shield, button.player.completed == true);
	end
	if button.friend and button.friend.shield then
		PatchAchievementShieldInstance(button.friend.shield, button.friend.completed == true);
	end
end

local function PatchVisibleComparisonShields()
	if AchievementFrameComparisonContainer and AchievementFrameComparisonContainer.buttons then
		for _, button in ipairs(AchievementFrameComparisonContainer.buttons) do
			PatchComparisonButtonShields(button);
		end
	end
end

local function PatchComparisonShieldDisplayFunction()
	if not AchievementFrameComparison_DisplayAchievement or achievementComparisonShieldDisplayPatched then
		return;
	end
	local originalDisplayAchievement = AchievementFrameComparison_DisplayAchievement;
	AchievementFrameComparison_DisplayAchievement = function(button, ...)
		originalDisplayAchievement(button, ...);
		PatchComparisonButtonShields(button);
	end;
	achievementComparisonShieldDisplayPatched = true;
end

local function PatchComparisonShieldButtonFunctions()
	if achievementComparisonShieldButtonPatched then
		return;
	end
	if not AchievementComparisonPlayerButton_OnLoad and not AchievementComparisonFriendButton_OnLoad then
		return;
	end

	if AchievementComparisonPlayerButton_OnLoad then
		local originalPlayerOnLoad = AchievementComparisonPlayerButton_OnLoad;
		AchievementComparisonPlayerButton_OnLoad = function(button, ...)
			originalPlayerOnLoad(button, ...);
			PatchAchievementShieldInstance(button and button.shield, false);
		end;
	end

	if AchievementComparisonFriendButton_OnLoad then
		local originalFriendOnLoad = AchievementComparisonFriendButton_OnLoad;
		AchievementComparisonFriendButton_OnLoad = function(button, ...)
			originalFriendOnLoad(button, ...);
			PatchAchievementShieldInstance(button and button.shield, false);
		end;
	end

	achievementComparisonShieldButtonPatched = true;
end

local function ApplyAchievementShieldTexturePatch()
	if AchievementShield_SetPoints then
		AchievementShield_SetPoints = function(points, pointString, normalFont, smallFont)
			points = tonumber(points) or 0;
			if ( points == 0 ) then
				pointString:SetText("");
				return;
			end
			if ( points < 100 ) then
				pointString:SetFontObject(normalFont);
			else
				pointString:SetFontObject(smallFont);
			end
			pointString:SetText(points);
		end;
	end

	AchievementShield_Saturate = SaturateAchievementShield;
	AchievementShield_Desaturate = DesaturateAchievementShield;

	PatchComparisonShieldDisplayFunction();
	PatchComparisonShieldButtonFunctions();

	if AchievementShield_OnLoad and not achievementShieldOnLoadPatched then
		local originalAchievementShieldOnLoad = AchievementShield_OnLoad;
		AchievementShield_OnLoad = function(self, ...)
			originalAchievementShieldOnLoad(self, ...);
			PatchAchievementShieldInstance(self, false);
		end;
		achievementShieldOnLoadPatched = true;
	end

	if AchievementFrameAchievements and AchievementFrameAchievements.buttons then
		for _, button in ipairs(AchievementFrameAchievements.buttons) do
			if button.shield then
				PatchAchievementShieldInstance(button.shield, button.completed == true);
			end
		end
	end

	PatchVisibleComparisonShields();
end

local function PatchedAchievementButton_UpdatePlusMinusTexture(button)
	local id = button and button.id;
	if ( not id or not button.plusMinus ) then
		return;
	end

	local display = false;
	if ( GetAchievementNumCriteria(id) ~= 0 ) then
		display = true;
	elseif ( GetPreviousAchievement(id) and button.completed ) then
		display = true;
	end

	if ( display ) then
		button.plusMinus:Show();
		button.plusMinus:SetTexture(button.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up");
		button.plusMinus:SetTexCoord(0, 1, 0, 1);
		if ( button.saturated ) then
			button.plusMinus:SetVertexColor(1, 1, 1, 1);
		else
			button.plusMinus:SetVertexColor(.65, .65, .65, 1);
		end
	else
		button.plusMinus:Hide();
	end
end

local function ApplyAchievementPlusMinusTexturePatch()
	if not AchievementButton_UpdatePlusMinusTexture then
		return;
	end

	AchievementButton_UpdatePlusMinusTexture = PatchedAchievementButton_UpdatePlusMinusTexture;
	if AchievementFrameAchievements and AchievementFrameAchievements.buttons then
		for _, button in ipairs(AchievementFrameAchievements.buttons) do
			if button.plusMinus then
				AchievementButton_UpdatePlusMinusTexture(button);
			end
		end
	end
end

local function InvalidateAchievementStatsUICache()
	statsUICacheVersion = statsUICacheVersion + 1;
	statsUIDisplayCache.category = nil;
	statsUIDisplayCache.version = nil;
	comparisonStatsUIDisplayCache.category = nil;
	comparisonStatsUIDisplayCache.version = nil;
	if achievementFunctions then
		achievementFunctions.lastCategory = nil;
	end
end

local function PatchedAchievementFrameCategories_GetCategoryList(categories)
	local cats = achievementFunctions.categoryAccessor();

	for i in next, categories do
		categories[i] = nil;
	end
	tinsert(categories, { ["id"] = "summary" });

	local topLevelCategories = {};
	local childrenByParent = {};
	for i, id in ipairs(cats) do
		local _, parent = GetCategoryInfo(id);
		if ( parent == -1 ) then
			tinsert(topLevelCategories, id);
		else
			childrenByParent[parent] = childrenByParent[parent] or {};
			tinsert(childrenByParent[parent], id);
		end
	end

	local function AddCategory(id, parentID, hidden)
		local category = { ["id"] = id };
		if ( parentID ) then
			category.parent = parentID;
			category.hidden = hidden;
		end
		tinsert(categories, category);

		local children = childrenByParent[id];
		if ( not children ) then
			return;
		end

		if ( not parentID ) then
			category.parent = true;
			category.collapsed = true;
		end

		for i, childID in ipairs(children) do
			AddCategory(childID, id, true);
		end
	end

	for i, id in ipairs(topLevelCategories) do
		AddCategory(id);
	end
end

local function ApplyAchievementCategoryListPatch()
	if not AchievementFrameCategories_GetCategoryList then
		return;
	end

	AchievementFrameCategories_GetCategoryList = PatchedAchievementFrameCategories_GetCategoryList;

	if ACHIEVEMENTUI_CATEGORIES and achievementFunctions and achievementFunctions.categoryAccessor then
		AchievementFrameCategories_GetCategoryList(ACHIEVEMENTUI_CATEGORIES);
		InvalidateAchievementStatsUICache();
		if AchievementFrameCategories_Update and AchievementFrameCategoriesContainer and AchievementFrameCategoriesContainer.buttons then
			AchievementFrameCategories_Update();
		end
		if AchievementFrameStats and AchievementFrameStats:IsShown() and AchievementFrameStats_Update and AchievementFrameStatsContainer and AchievementFrameStatsContainer.buttons then
			AchievementFrameStats_Update();
		end
	end
end

local function AddCachedStatisticRow(rows, statisticID, quantity)
	local data = Private.data;
	local achievement = data and data.achievements and data.achievements[statisticID];
	tinsert(rows, {
		id = statisticID,
		name = (achievement and achievement.name) or "",
		quantity = quantity or "--",
	});
end

local function AddCachedStatisticRows(rows, categoryID)
	local numStats = GetCategoryNumAchievements(categoryID) or 0;
	for index = 1, numStats do
		local quantity, skip, statisticID = GetStatistic(categoryID, index);
		if ( not skip and statisticID ) then
			AddCachedStatisticRow(rows, statisticID, quantity);
		end
	end
end

local function BuildStatsChildrenByParent()
	local childrenByParent = {};
	for _, category in ipairs(ACHIEVEMENTUI_CATEGORIES or {}) do
		if type(category.id) == "number" and type(category.parent) == "number" then
			childrenByParent[category.parent] = childrenByParent[category.parent] or {};
			tinsert(childrenByParent[category.parent], category.id);
		end
	end
	return childrenByParent;
end

local function BuildCachedStatsRows(categoryID)
	local rows = statsUIDisplayCache.rows;
	for index in next, rows do
		rows[index] = nil;
	end

	local childrenByParent = BuildStatsChildrenByParent();
	local seenCategories = {};
	local function AddCategoryRows(id)
		if seenCategories[id] then
			return;
		end
		seenCategories[id] = true;
		tinsert(rows, { id = id, header = true });
		AddCachedStatisticRows(rows, id);

		for _, childID in ipairs(childrenByParent[id] or {}) do
			AddCategoryRows(childID);
		end
	end

	AddCategoryRows(categoryID);
	statsUIDisplayCache.category = categoryID;
	statsUIDisplayCache.version = statsUICacheVersion;
	if achievementFunctions then
		achievementFunctions.lastCategory = categoryID;
	end
	return rows;
end

local function DisplayCachedStatistic(button, row, colorIndex)
	button.id = row.id;
	button:SetText(row.name or "");
	button.background:Show();
	if ( mod(colorIndex, 2) == 1 ) then
		button.background:SetTexCoord(0, 1, 0.1875, 0.3671875);
		button.background:SetBlendMode("BLEND");
		button.background:SetAlpha(1.0);
		button:SetHeight(24);
	else
		button.background:SetTexCoord(0, 1, 0.375, 0.5390625);
		button.background:SetBlendMode("ADD");
		button.background:SetAlpha(0.5);
		button:SetHeight(24);
	end
	button.value:SetText(row.quantity or "--");
	button.title:Hide();
	button.left:Hide();
	button.middle:Hide();
	button.right:Hide();
	button.isHeader = false;
end

local function PatchedAchievementFrameStats_Update()
	if not achievementFunctions or not AchievementFrameStatsContainer or not AchievementFrameStatsContainer.buttons then
		return;
	end

	local category = achievementFunctions.selectedCategory;
	if category == "summary" then
		category = ACHIEVEMENT_COMPARISON_STATS_SUMMARY_ID;
		achievementFunctions.selectedCategory = category;
	end
	local rows = statsUIDisplayCache.rows;
	if statsUIDisplayCache.category ~= category or statsUIDisplayCache.version ~= statsUICacheVersion then
		rows = BuildCachedStatsRows(category);
	end

	local scrollFrame = AchievementFrameStatsContainer;
	local offset = HybridScrollFrame_GetOffset(scrollFrame);
	local buttons = scrollFrame.buttons;
	local numButtons = #buttons;
	local statHeight = 24;
	local statCount = #rows;
	local totalHeight = statCount * statHeight;
	local displayedHeight = numButtons * statHeight;

	for index = 1, numButtons do
		local button = buttons[index];
		local rowIndex = offset + index;
		local row = rows[rowIndex];
		if row then
			if row.header then
				AchievementFrameStats_SetHeader(button, row.id);
			else
				DisplayCachedStatistic(button, row, rowIndex);
			end
			button:Show();
		else
			button:Hide();
		end
	end

	HybridScrollFrame_Update(scrollFrame, totalHeight, displayedHeight);
end

local function ApplyAchievementStatsUIPatch()
	if not AchievementFrameStats_Update or not AchievementFrameStats_SetHeader then
		return;
	end

	AchievementFrameStats_Update = PatchedAchievementFrameStats_Update;
	if AchievementFrameStatsContainer then
		AchievementFrameStatsContainer.update = PatchedAchievementFrameStats_Update;
	end

	if not achievementStatsUIPatched and AchievementFrameStats_OnEvent then
		originalAchievementFrameStatsOnEvent = AchievementFrameStats_OnEvent;
		AchievementFrameStats_OnEvent = function(self, event, ...)
			if event == "CRITERIA_UPDATE" then
				InvalidateAchievementStatsUICache();
			end
			return originalAchievementFrameStatsOnEvent(self, event, ...);
		end;
		achievementStatsUIPatched = true;
	end
end

local function AddComparisonStatisticRow(rows, statisticID, quantity, friendQuantity)
	local data = Private.data;
	local achievement = data and data.achievements and data.achievements[statisticID];
	tinsert(rows, {
		id = statisticID,
		name = (achievement and achievement.name) or "",
		quantity = quantity or "--",
		friendQuantity = friendQuantity or "--",
	});
end

local function AddComparisonStatisticRows(rows, categoryID)
	local numStats = GetCategoryNumAchievements(categoryID) or 0;
	for statIndex = 1, numStats do
		local quantity, skip, statisticID = GetStatistic(categoryID, statIndex);
		if ( not skip and statisticID ) then
			local friendQuantity = GetComparisonStatistic(statisticID);
			AddComparisonStatisticRow(rows, statisticID, quantity, friendQuantity);
		end
	end
end

local function BuildComparisonStatsRows(categoryID)
	local rows = comparisonStatsUIDisplayCache.rows;
	for rowIndex in next, rows do
		rows[rowIndex] = nil;
	end

	local childrenByParent = BuildStatsChildrenByParent();
	local seenCategories = {};
	local function AddCategoryRows(currentCategoryID)
		if seenCategories[currentCategoryID] then
			return;
		end
		seenCategories[currentCategoryID] = true;
		tinsert(rows, { id = currentCategoryID, header = true });
		AddComparisonStatisticRows(rows, currentCategoryID);

		for _, childCategoryID in ipairs(childrenByParent[currentCategoryID] or {}) do
			AddCategoryRows(childCategoryID);
		end
	end

	AddCategoryRows(categoryID);
	comparisonStatsUIDisplayCache.category = categoryID;
	comparisonStatsUIDisplayCache.version = statsUICacheVersion;
	return rows;
end

local function DisplayCachedComparisonStatistic(button, row, colorIndex)
	button.id = row.id;
	button.background:Show();
	if ( mod(colorIndex, 2) == 1 ) then
		button.background:SetTexCoord(0, 1, 0.1875, 0.3671875);
		button.background:SetBlendMode("BLEND");
		button.background:SetAlpha(1.0);
		button:SetHeight(24);
	else
		button.background:SetTexCoord(0, 1, 0.375, 0.5390625);
		button.background:SetBlendMode("ADD");
		button.background:SetAlpha(0.5);
		button:SetHeight(24);
	end

	local friendQuantity = row.friendQuantity or "--";
	button.value:SetText(row.quantity or "--");
	button.text:SetText(friendQuantity);
	local width = button.text:GetStringWidth();
	if ( width > button.friendValue:GetWidth() ) then
		button.friendValue:SetFontObject("AchievementFont_Small");
		button.mouseover:Show();
		button.mouseover.tooltip = friendQuantity;
	else
		button.friendValue:SetFontObject("GameFontHighlightRight");
		button.mouseover:Hide();
		button.mouseover.tooltip = nil;
	end

	button.text:SetText(row.name or "");
	button.friendValue:SetText(friendQuantity);
	button.title:Hide();
	button.left:Hide();
	button.middle:Hide();
	button.right:Hide();
	button.left2:Hide();
	button.middle2:Hide();
	button.right2:Hide();
	button.isHeader = false;
end

local function PatchedAchievementFrameComparison_UpdateStats()
	if not achievementFunctions or not AchievementFrameComparisonStatsContainer or not AchievementFrameComparisonStatsContainer.buttons then
		return;
	end

	local category = achievementFunctions.selectedCategory;
	if category == "summary" then
		category = ACHIEVEMENT_COMPARISON_STATS_SUMMARY_ID;
		achievementFunctions.selectedCategory = category;
	end

	local rows = comparisonStatsUIDisplayCache.rows;
	if comparisonStatsUIDisplayCache.category ~= category or comparisonStatsUIDisplayCache.version ~= statsUICacheVersion then
		rows = BuildComparisonStatsRows(category);
	end

	local scrollFrame = AchievementFrameComparisonStatsContainer;
	local offset = HybridScrollFrame_GetOffset(scrollFrame);
	local buttons = scrollFrame.buttons;
	local numButtons = #buttons;
	local statHeight = 24;
	local statCount = #rows;
	local totalHeight = statCount * statHeight;
	local displayedHeight = numButtons * statHeight;

	for buttonIndex = 1, numButtons do
		local button = buttons[buttonIndex];
		local rowIndex = offset + buttonIndex;
		local row = rows[rowIndex];
		if row then
			if row.header then
				AchievementFrameComparisonStats_SetHeader(button, row.id);
			else
				DisplayCachedComparisonStatistic(button, row, rowIndex);
			end
			button:Show();
		else
			button:Hide();
		end
	end

	HybridScrollFrame_Update(scrollFrame, totalHeight, displayedHeight);
end

local function GetSelectedComparisonAchievementCategory()
	if not achievementFunctions or achievementFunctions ~= COMPARISON_ACHIEVEMENT_FUNCTIONS then
		return nil;
	end

	local category = achievementFunctions.selectedCategory;
	if not category or category == "summary" or category == ACHIEVEMENT_COMPARISON_STATS_SUMMARY_ID then
		return ACHIEVEMENT_COMPARISON_SUMMARY_ID;
	end
	return category;
end

local function RefreshComparisonAchievementStatusBars()
	if type(AchievementFrameComparison_UpdateStatusBars) ~= "function" then
		return;
	end

	local category = GetSelectedComparisonAchievementCategory();
	if category then
		AchievementFrameComparison_UpdateStatusBars(category);
	end
end

local function ApplyAchievementComparisonUIPatch()
	if achievementComparisonUIPatched or type(AchievementFrameComparison_UpdateStats) ~= "function" then
		return;
	end

	AchievementFrameComparison_UpdateStats = PatchedAchievementFrameComparison_UpdateStats;
	if AchievementFrameComparisonStatsContainer then
		AchievementFrameComparisonStatsContainer.update = PatchedAchievementFrameComparison_UpdateStats;
	end

	if type(AchievementFrameComparison_ForceUpdate) == "function" then
		local originalAchievementFrameComparisonForceUpdate = AchievementFrameComparison_ForceUpdate;
		AchievementFrameComparison_ForceUpdate = function(...)
			RefreshComparisonAchievementStatusBars();
			return originalAchievementFrameComparisonForceUpdate(...);
		end;
	end

	achievementComparisonUIPatched = true;
end

local function MarkAchievementCriteriaUIDirty()
	if AchievementFrameAchievements then
		AchievementFrameAchievements.criteriaDirty = true;
	end
	if AchievementFrameAchievementsObjectives then
		AchievementFrameAchievementsObjectives.id = nil;
	end
end

local function RefreshAchievementCriteriaUIIfDirty()
	if AchievementFrameAchievements and AchievementFrameAchievements.criteriaDirty then
		AchievementFrameAchievements.criteriaDirty = nil;
		if AchievementFrameAchievements_ForceUpdate then
			AchievementFrameAchievements_ForceUpdate();
		end
	end
end

local function ApplyAchievementCriteriaRefreshUIPatch()
	if achievementCriteriaRefreshUIPatched or not AchievementFrameAchievements_OnShow or not AchievementFrameAchievements_OnEvent then
		return;
	end

	local originalAchievementsOnShow = AchievementFrameAchievements_OnShow;
	AchievementFrameAchievements_OnShow = function(...)
		originalAchievementsOnShow(...);
		RefreshAchievementCriteriaUIIfDirty();
	end;

	local originalAchievementsOnEvent = AchievementFrameAchievements_OnEvent;
	AchievementFrameAchievements_OnEvent = function(self, event, ...)
		originalAchievementsOnEvent(self, event, ...);
		if (event == "CRITERIA_UPDATE" or event == "ACHIEVEMENT_EARNED") and self and self.IsVisible and not self:IsVisible() then
			MarkAchievementCriteriaUIDirty();
		end
	end;

	achievementCriteriaRefreshUIPatched = true;
end

local function ApplyAchievementSummaryStatisticSelectionPatch()
	if achievementSummaryStatisticSelectionPatched or type(AchievementFrame_SelectSummaryStatistic) ~= "function" then
		return;
	end

	local originalSelectSummaryStatistic = AchievementFrame_SelectSummaryStatistic;
	AchievementFrame_SelectSummaryStatistic = function(...)
		local ok, result = pcall(originalSelectSummaryStatistic, ...);
		if not ok then
			if Private.DebugMessage then
				Private.DebugMessage("Summary statistic selection failed: " .. tostring(result), "summary-stat-selection-failed");
			end
			return nil;
		end
		return result;
	end;

	achievementSummaryStatisticSelectionPatched = true;
end

local function DisplaySummaryAchievement(button, achievementID, incompleteTooltip)
	local id, name, points, completed, month, day, year, description, flags, icon = GetAchievementInfo(achievementID);
	if not id then
		return false;
	end

	points = tonumber(points) or 0;
	button.label:SetText(name or "");
	button.description:SetText(description or "");
	AchievementShield_SetPoints(points, button.shield.points, GameFontNormal, GameFontNormalSmall);
	if ( points > 0 ) then
		button.shield.icon:SetTexture([[Interface\AchievementFrame\UI-Achievement-Shields]]);
	else
		button.shield.icon:SetTexture([[Interface\AchievementFrame\UI-Achievement-Shields-NoPoints]]);
	end
	button.icon.texture:SetTexture(icon or Private.DEFAULT_ACHIEVEMENT_ICON);
	button.id = id;

	if ( completed and month and day and year ) then
		button.dateCompleted:SetText(string.format(SHORTDATE, day, month, year));
	else
		button.dateCompleted:SetText("");
	end

	button.tooltipTitle = incompleteTooltip and SUMMARY_ACHIEVEMENT_INCOMPLETE or nil;
	button.tooltip = incompleteTooltip and SUMMARY_ACHIEVEMENT_INCOMPLETE_TEXT or nil;
	button:Show();
	return true, completed;
end

local function PatchedAchievementFrameSummary_UpdateAchievements(...)
	local numAchievements = select("#", ...);
	local buttons = AchievementFrameSummaryAchievements.buttons;
	local button, anchorTo, achievementID;
	local defaultAchievementCount = 1;

	for i=1, ACHIEVEMENTUI_MAX_SUMMARY_ACHIEVEMENTS do
		if ( buttons ) then
			button = buttons[i];
		end
		if ( not button ) then
			button = CreateFrame("Button", "AchievementFrameSummaryAchievement"..i, AchievementFrameSummaryAchievements, "SummaryAchievementTemplate");
			if ( i == 1 ) then
				button:SetPoint("TOPLEFT",AchievementFrameSummaryAchievementsHeader, "BOTTOMLEFT", 18, 2 );
				button:SetPoint("TOPRIGHT",AchievementFrameSummaryAchievementsHeader, "BOTTOMRIGHT", -18, 2 );
			else
				anchorTo = _G["AchievementFrameSummaryAchievement"..i-1];
				button:SetPoint("TOPLEFT",anchorTo, "BOTTOMLEFT", 0, 3 );
				button:SetPoint("TOPRIGHT",anchorTo, "BOTTOMRIGHT", 0, 3 );
			end
			if ( not buttons ) then
				buttons = AchievementFrameSummaryAchievements.buttons;
			end
			AchievementFrameSummary_LocalizeButton(button);
		end;

		if ( i <= numAchievements ) then
			achievementID = select(i, ...);
			if DisplaySummaryAchievement(button, achievementID, false) then
				button:Saturate();
			else
				button:Hide();
			end
		else
			button:Hide();
			for j=defaultAchievementCount, ACHIEVEMENTUI_MAX_SUMMARY_ACHIEVEMENTS do
				achievementID = ACHIEVEMENTUI_DEFAULTSUMMARYACHIEVEMENTS and ACHIEVEMENTUI_DEFAULTSUMMARYACHIEVEMENTS[defaultAchievementCount];
				if ( not achievementID ) then
					break;
				end
				local displayed, completed = DisplaySummaryAchievement(button, achievementID, true);
				defaultAchievementCount = defaultAchievementCount+1;
				if ( displayed and not completed ) then
					button:Desaturate();
					break;
				end
			end
		end
	end
end

local function PatchedAchievementFrameSummary_Update(isCompare)
	AchievementFrameSummaryCategoriesStatusBar_Update();
	if Achievements.GetSuggestedAchievements then
		ACHIEVEMENTUI_DEFAULTSUMMARYACHIEVEMENTS = Achievements.GetSuggestedAchievements();
	end
	AchievementFrameSummary_UpdateAchievements(GetLatestCompletedAchievements());
end

local function ApplyAchievementSummaryUIPatch()
	ApplyAchievementCriteriaRefreshUIPatch();
	ApplyAchievementSummaryStatisticSelectionPatch();

	if not AchievementFrameSummary_Update or not AchievementFrameSummary_UpdateAchievements or not AchievementFrameSummaryCategoriesStatusBar_Update then
		return;
	end

	AchievementFrameSummary_Update = PatchedAchievementFrameSummary_Update;
	AchievementFrameSummary_UpdateAchievements = PatchedAchievementFrameSummary_UpdateAchievements;
	achievementSummaryUIPatched = true;
end

local function LoadNativeAchievementUI()
	if IsInCombatLockdown() and not AchievementFrame_ToggleAchievementFrame then
		nativeAchievementUILoaded = false;
		nativeAchievementUILoadReason = "IN_COMBAT_LOCKDOWN";
		return false, nativeAchievementUILoadReason;
	end

	EnsureAchievementMicroButton();
	ApplyAchievementShieldTexturePatch();
	ApplyAchievementPlusMinusTexturePatch();
	ApplyAchievementCategoryListPatch();
	ApplyAchievementStatsUIPatch();
	ApplyAchievementSummaryUIPatch();
	ApplyAchievementComparisonUIPatch();

	if AchievementFrame_ToggleAchievementFrame then
		ApplyAchievementShieldTexturePatch();
		ApplyAchievementPlusMinusTexturePatch();
		ApplyAchievementCategoryListPatch();
		ApplyAchievementStatsUIPatch();
		ApplyAchievementSummaryUIPatch();
		ApplyAchievementComparisonUIPatch();
		nativeAchievementUILoaded = true;
		nativeAchievementUILoadReason = nil;
		return true;
	end

	if C_AddOns.IsAddOnLoaded("Blizzard_AchievementUI") then
		ApplyAchievementShieldTexturePatch();
		ApplyAchievementPlusMinusTexturePatch();
		ApplyAchievementCategoryListPatch();
		ApplyAchievementStatsUIPatch();
		ApplyAchievementSummaryUIPatch();
		ApplyAchievementComparisonUIPatch();
		nativeAchievementUILoaded = true;
		nativeAchievementUILoadReason = nil;
		return true;
	end

	local loaded, reason = C_AddOns.LoadAddOn("Blizzard_AchievementUI");

	nativeAchievementUILoaded = loaded;
	nativeAchievementUILoadReason = reason;
	ApplyAchievementShieldTexturePatch();
	ApplyAchievementPlusMinusTexturePatch();
	ApplyAchievementCategoryListPatch();
	ApplyAchievementStatsUIPatch();
	ApplyAchievementSummaryUIPatch();
	ApplyAchievementComparisonUIPatch();
	return loaded, reason;
end

function Achievements.AchievementFrame_LoadUI()
	if IsInCombatLockdown() and not AchievementFrame_ToggleAchievementFrame then
		nativeAchievementUILoadReason = "IN_COMBAT_LOCKDOWN";
		return false, nativeAchievementUILoadReason;
	end

	EnsureAchievementMicroButton();
	ApplyAchievementShieldTexturePatch();
	ApplyAchievementPlusMinusTexturePatch();
	ApplyAchievementCategoryListPatch();
	ApplyAchievementStatsUIPatch();
	ApplyAchievementSummaryUIPatch();
	ApplyAchievementComparisonUIPatch();
	if AchievementFrame_ToggleAchievementFrame then
		return true;
	end

	local loaded, reason = LoadNativeAchievementUI();
	ApplyAchievementShieldTexturePatch();
	ApplyAchievementPlusMinusTexturePatch();
	ApplyAchievementCategoryListPatch();
	ApplyAchievementStatsUIPatch();
	ApplyAchievementSummaryUIPatch();
	ApplyAchievementComparisonUIPatch();
	return loaded, reason;
end

function Achievements.ToggleAchievementFrame(showStats)
	if IsInCombatLockdown() and not (AchievementFrame and AchievementFrame:IsShown()) then
		UIErrorsFrame:OnEvent("UI_ERROR_MESSAGE", 525, ERR_NOT_IN_COMBAT)
		-- PrintMessage("Achievements: the achievement frame cannot be opened while in combat.");
		return;
	end

	EnsureAchievementMicroButton();
	if not AchievementFrame_ToggleAchievementFrame then
		Achievements.AchievementFrame_LoadUI();
	end

	if AchievementFrame_ToggleAchievementFrame then
		ApplyAchievementShieldTexturePatch();
		ApplyAchievementPlusMinusTexturePatch();
		ApplyAchievementCategoryListPatch();
		ApplyAchievementStatsUIPatch();
		ApplyAchievementSummaryUIPatch();
		ApplyAchievementComparisonUIPatch();
		AchievementFrame_ToggleAchievementFrame(showStats);
		Achievements.AchievementMicroButton_Update();
		ApplyAchievementShieldTexturePatch();
		ApplyAchievementPlusMinusTexturePatch();
		ApplyAchievementCategoryListPatch();
		ApplyAchievementStatsUIPatch();
		ApplyAchievementSummaryUIPatch();
		ApplyAchievementComparisonUIPatch();
	elseif nativeAchievementUILoadReason then
		PrintMessage("Achievements: Blizzard_AchievementUI did not load (" .. tostring(nativeAchievementUILoadReason) .. ").");
	end
end

function Achievements.AchievementMicroButton_Update()
	if IsInCombatLockdown() then
		return;
	end

	local button = AchievementMicroButton;
	if not button or not button.SetButtonState then
		return;
	end

	LayoutLegacyAchievementMicroButton(button);

	if AchievementFrame and AchievementFrame:IsShown() then
		button:SetButtonState("PUSHED", true);
	else
		button:SetButtonState("NORMAL");
	end

	if achievementMicroButtonInserted and MicroMenu and MicroMenu.Layout then
		MicroMenu:MarkDirty();
		MicroMenu:Layout();
	end
end

Achievements.loadNativeAchievementUI = LoadNativeAchievementUI;
Achievements.ensureAchievementMicroButton = EnsureAchievementMicroButton;
Achievements.hookUpdateMicroButtons = HookUpdateMicroButtons;
Achievements.applyAchievementShieldTexturePatch = ApplyAchievementShieldTexturePatch;
Achievements.applyAchievementPlusMinusTexturePatch = ApplyAchievementPlusMinusTexturePatch;
Achievements.applyAchievementCategoryListPatch = ApplyAchievementCategoryListPatch;
Achievements.applyAchievementStatsUIPatch = ApplyAchievementStatsUIPatch;
Achievements.applyAchievementSummaryUIPatch = ApplyAchievementSummaryUIPatch;
Achievements.applyAchievementComparisonUIPatch = ApplyAchievementComparisonUIPatch;
Achievements.applyAchievementCriteriaRefreshUIPatch = ApplyAchievementCriteriaRefreshUIPatch;
Achievements.invalidateAchievementStatsUICache = InvalidateAchievementStatsUICache;
