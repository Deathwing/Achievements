UIPanelWindows["AchievementsFrame"] = { area = "doublewide", pushable = 0, width = 840, xoffset = 80, whileDead = 1 };

ACHIEVEMENTUI_CATEGORIES = {};

ACHIEVEMENTUI_GOLDBORDER_R = 1;
ACHIEVEMENTUI_GOLDBORDER_G = 0.675;
ACHIEVEMENTUI_GOLDBORDER_B = 0.125;
ACHIEVEMENTUI_GOLDBORDER_A = 1;


ACHIEVEMENT_GOLD_BORDER_COLOR	= CreateColor(1, 0.675, 0.125);


ACHIEVEMENTUI_REDBORDER_R = 0.7;
ACHIEVEMENTUI_REDBORDER_G = 0.15;
ACHIEVEMENTUI_REDBORDER_B = 0.05;
ACHIEVEMENTUI_REDBORDER_A = 1;


ACHIEVEMENT_RED_BORDER_COLOR	= CreateColor(0.7, 0.15, 0.05);
ACHIEVEMENT_BLUE_BORDER_COLOR	= CreateColor(0.129, 0.671, 0.875);

ACHIEVEMENTUI_CATEGORIESWIDTH = 175;

ACHIEVEMENTUI_PROGRESSIVEHEIGHT = 50;
ACHIEVEMENTUI_PROGRESSIVEWIDTH = 42;

ACHIEVEMENTUI_MAX_SUMMARY_ACHIEVEMENTS = 4;

ACHIEVEMENTUI_MAXCONTENTWIDTH = 330;
ACHIEVEMENTUI_MAX_LINES_COLLAPSED = 3;		-- can show 3 lines of text when achievement is collapsed

ACHIEVEMENTUI_DEFAULTSUMMARYACHIEVEMENTS = {6, 503, 116, 545, 1017};

ACHIEVEMENT_CATEGORY_NORMAL_R = 0;
ACHIEVEMENT_CATEGORY_NORMAL_G = 0;
ACHIEVEMENT_CATEGORY_NORMAL_B = 0;
ACHIEVEMENT_CATEGORY_NORMAL_A = .9;

ACHIEVEMENT_CATEGORY_HIGHLIGHT_R = 0;
ACHIEVEMENT_CATEGORY_HIGHLIGHT_G = .6;
ACHIEVEMENT_CATEGORY_HIGHLIGHT_B = 0;
ACHIEVEMENT_CATEGORY_HIGHLIGHT_A = .65;

ACHIEVEMENTBUTTON_LABELWIDTH = 320;

ACHIEVEMENT_COMPARISON_SUMMARY_ID = -1
ACHIEVEMENT_COMPARISON_STATS_SUMMARY_ID = -2

ACHIEVEMENT_FILTER_ALL = 1;
ACHIEVEMENT_FILTER_COMPLETE = 2;
ACHIEVEMENT_FILTER_INCOMPLETE = 3;

FEAT_OF_STRENGTH_ID = 81;

-- Vanilla and TBC do not ship playable versions of the achievement menu sound
-- kits. Bundle the original Blizzard sounds just like the earned sound instead
-- of relying on SoundKit IDs 13832/13833, which return an empty result here.
local ACHIEVEMENT_ADDON_NAME = Achievements and Achievements.addonName or "Achievements";
local ACHIEVEMENT_MENU_OPEN_SOUND_FILE = "Interface\\AddOns\\" .. tostring(ACHIEVEMENT_ADDON_NAME) .. "\\Media\\AchievementMenuOpen.ogg";
local ACHIEVEMENT_MENU_CLOSE_SOUND_FILE = "Interface\\AddOns\\" .. tostring(ACHIEVEMENT_ADDON_NAME) .. "\\Media\\AchievementMenuClose.ogg";

function AchievementFrame_UpdateTrackedAchievements (...) 
	local count = select("#", ...);
	
	for i = 1, count do
		AchievementsFrame.trackedAchievements[select(i, ...)] = true;
	end
end

-- [[ AchievementsFrame ]] --

function AchievementFrame_OnShow (self)
	PlaySoundFile(ACHIEVEMENT_MENU_OPEN_SOUND_FILE, "SFX");
	AchievementsFrameHeaderPoints:SetText(GetTotalAchievementPoints());
	if ( not AchievementsFrame.wasShown ) then
		AchievementsFrame.wasShown = true;
		AchievementCategoryButton_OnClick(AchievementsFrameCategoriesContainerButton1);
	end
	UpdateMicroButtons();
	AchievementFrame_LoadTextures();
end

function AchievementFrame_OnHide (self)
	PlaySoundFile(ACHIEVEMENT_MENU_CLOSE_SOUND_FILE, "SFX");
	UpdateMicroButtons();
	AchievementFrame_ClearTextures();
end

function AchievementFrame_ForceUpdate ()
	if ( AchievementsFrameAchievements:IsShown() ) then
		AchievementsFrameAchievements_ForceUpdate();
	elseif ( AchievementsFrameStats:IsShown() ) then
		AchievementsFrameStats_Update();
	elseif ( AchievementsFrameComparison:IsShown() ) then
		AchievementsFrameComparison_ForceUpdate();
	end
end

AchievementsFrameTab_OnClick = AchievementsFrameBaseTab_OnClick;

ACHIEVEMENTFRAME_SUBFRAMES = {
	"AchievementsFrameSummary",
	"AchievementsFrameAchievements",
	"AchievementsFrameStats",
	"AchievementsFrameComparison",
	"AchievementsFrameComparisonContainer",
	"AchievementsFrameComparisonStatsContainer"
};

-- [[ AchievementsFrameCategories ]] --

function AchievementsFrameCategories_OnEvent (self, event, ...)
	if ( event == "ADDON_LOADED" ) then
		local addonName = ...;
		if ( addonName and addonName ~= "Achievements" ) then
			return;
		end
		
		AchievementsFrameCategories_GetCategoryList(ACHIEVEMENTUI_CATEGORIES);
		
		AchievementsFrameCategoriesContainerScrollBar.Show = 
			function (self)
				ACHIEVEMENTUI_CATEGORIESWIDTH = 175;
				AchievementsFrameCategories:SetWidth(175);
				AchievementsFrameCategoriesContainer:GetScrollChild():SetWidth(175);
				AchievementsFrameAchievements:SetPoint("TOPLEFT", "$parentCategories", "TOPRIGHT", 22, 0);
				AchievementsFrameStats:SetPoint("TOPLEFT", "$parentCategories", "TOPRIGHT", 22, 0);
				AchievementsFrameComparison:SetPoint("TOPLEFT", "$parentCategories", "TOPRIGHT", 22, 0)
				AchievementsFrameWaterMark:SetWidth(145);
				AchievementsFrameWaterMark:SetTexCoord(0, 145/256, 0, 1);
				for _, button in next, AchievementsFrameCategoriesContainer.buttons do
					AchievementsFrameCategories_DisplayButton(button, button.element)
				end
				getmetatable(self).__index.Show(self);
			end
			
		AchievementsFrameCategoriesContainerScrollBar.Hide = 
			function (self)
				ACHIEVEMENTUI_CATEGORIESWIDTH = 197;
				AchievementsFrameCategories:SetWidth(197);
				AchievementsFrameCategoriesContainer:GetScrollChild():SetWidth(197);
				AchievementsFrameAchievements:SetPoint("TOPLEFT", "$parentCategories", "TOPRIGHT", 0, 0);
				AchievementsFrameStats:SetPoint("TOPLEFT", "$parentCategories", "TOPRIGHT", 0, 0);
				AchievementsFrameComparison:SetPoint("TOPLEFT", "$parentCategories", "TOPRIGHT", 0, 0)
				AchievementsFrameWaterMark:SetWidth(167);
				AchievementsFrameWaterMark:SetTexCoord(0, 167/256, 0, 1);
				for _, button in next, AchievementsFrameCategoriesContainer.buttons do
					AchievementsFrameCategories_DisplayButton(button, button.element);
				end
				getmetatable(self).__index.Hide(self);
			end
			
		AchievementsFrameCategoriesContainerScrollBarBG:Show();
		AchievementsFrameCategoriesContainer.update = AchievementsFrameCategories_Update;
		HybridScrollFrame_CreateButtons(AchievementsFrameCategoriesContainer, "AchievementCategoryTemplate", 0, 0, "TOP", "TOP", 0, 0, "TOP", "BOTTOM");
		AchievementsFrameCategories_Update();
		self:UnregisterEvent(event)		
	end
end

function AchievementsFrameCategories_OnShow (self)
	AchievementsFrameCategories_Update();
end

function AchievementsFrameCategories_Update ()
	local scrollFrame = AchievementsFrameCategoriesContainer
	
	local categories = ACHIEVEMENTUI_CATEGORIES;
	local offset = HybridScrollFrame_GetOffset(scrollFrame);
	local buttons = scrollFrame.buttons;	
	
	local displayCategories = AchievementsFrame.displayCategories;
	
	for i in next, displayCategories do
		displayCategories[i] = nil;
	end
	
	local selection = achievementFunctions.selectedCategory;
	if ( selection == ACHIEVEMENT_COMPARISON_SUMMARY_ID or selection == ACHIEVEMENT_COMPARISON_STATS_SUMMARY_ID ) then
		selection = "summary";
	end
	
	local parent;
	if ( selection ) then
		for i, category in next, categories do
			if ( category.id == selection ) then
				parent = category.parent;
			end
		end
	end
	
	for i, category in next, categories do
		if ( not category.hidden ) then
			tinsert(displayCategories, category);
		elseif ( parent and category.id == parent ) then
			category.collapsed = false;
			tinsert(displayCategories, category);
		elseif ( parent and category.parent and category.parent == parent ) then
			category.hidden = false;
			tinsert(displayCategories, category);
		end
	end
	
	local numCategories = #displayCategories;
	local numButtons = #buttons;
	
	local totalHeight = numCategories * buttons[1]:GetHeight();
	local displayedHeight = 0;
	
	local element
	for i = 1, numButtons do
		element = displayCategories[i + offset];
		displayedHeight = displayedHeight + buttons[i]:GetHeight();
		if ( element ) then
			AchievementsFrameCategories_DisplayButton(buttons[i], element);
			if ( selection and element.id == selection ) then
				buttons[i]:LockHighlight();
			else
				buttons[i]:UnlockHighlight();
			end
			buttons[i]:Show();
		else
			buttons[i].element = nil;
			buttons[i]:Hide();
		end
	end
	
	HybridScrollFrame_Update(scrollFrame, totalHeight, displayedHeight);
	
	return displayCategories;
end

function AchievementsFrameCategory_StatusBarTooltip(self)
	GameTooltip_SetDefaultAnchor(GameTooltip, self);
	GameTooltip:SetMinimumWidth(128, true);
	GameTooltip:SetText(self.name, 1, 1, 1, nil, 1);
	GameTooltip_ShowStatusBar(GameTooltip, 0, self.numAchievements, self.numCompleted, self.numCompletedText);
	GameTooltip:Show();
end

function AchievementsFrameCategory_FeatOfStrengthTooltip(self)
	GameTooltip_SetDefaultAnchor(GameTooltip, self);
	GameTooltip:SetText(self.name, 1, 1, 1);
	GameTooltip:AddLine(self.text, nil, nil, nil, 1);
	GameTooltip:Show();
end

function AchievementsFrameCategories_UpdateTooltip()
	local container = AchievementsFrameCategoriesContainer;
	if ( not container:IsVisible() or not container.buttons ) then
		return;
	end
	
	for _, button in next, AchievementsFrameCategoriesContainer.buttons do
		if ( button:IsMouseOver() and button.showTooltipFunc ) then
			button:showTooltipFunc();
			break;
		end
	end
end

function AchievementsFrameCategories_ClearSelection ()
	local buttons = AchievementsFrameCategoriesContainer.buttons;
	for _, button in next, buttons do
		button.isSelected = nil;
		button:UnlockHighlight();
	end
	
	for i, category in next, ACHIEVEMENTUI_CATEGORIES do	
		if ( category.parent == true ) then
			category.collapsed = true;
		elseif ( category.parent ) then
			category.hidden = true;
		end
	end
end

function AchievementsFrameComparison_UpdateStatusBars (id)
	local numAchievements, numCompleted = GetCategoryNumAchievements(id);
	local name = GetCategoryInfo(id);
	
	if ( id == ACHIEVEMENT_COMPARISON_SUMMARY_ID ) then
		name = ACHIEVEMENT_SUMMARY_CATEGORY;
	end
	
	local statusBar = AchievementsFrameComparisonSummaryPlayerStatusBar;
	statusBar:SetMinMaxValues(0, numAchievements);
	statusBar:SetValue(numCompleted);
	statusBar.title:SetText(string.format(ACHIEVEMENTS_COMPLETED_CATEGORY, name));
	statusBar.text:SetText(numCompleted.."/"..numAchievements);

	local friendCompleted = GetComparisonCategoryNumAchievements(id);

	statusBar = AchievementsFrameComparisonSummaryFriendStatusBar;
	statusBar:SetMinMaxValues(0, numAchievements);
	statusBar:SetValue(friendCompleted);
	statusBar.text:SetText(friendCompleted.."/"..numAchievements);
end

-- [[ AchievementCategoryButton ]] --

function AchievementCategoryButton_OnClick (button)
	AchievementsFrameCategories_SelectButton(button);
	AchievementsFrameCategories_Update();
end

-- [[ AchievementsFrameAchievements ]] --

function AchievementsFrameAchievements_ForceUpdate ()
	if ( AchievementsFrameAchievements.selection ) then
		local nextID = GetNextAchievement(AchievementsFrameAchievements.selection);
		local id, _, _, completed = GetAchievementInfo(AchievementsFrameAchievements.selection);
		if ( nextID and completed ) then
			AchievementsFrameAchievements.selection = nil;
		end
	end
	AchievementsFrameAchievementsObjectives:Hide();
	AchievementsFrameAchievementsObjectives.id = nil;

	local buttons = AchievementsFrameAchievementsContainer.buttons;
	for i, button in next, buttons do
		button.id = nil;
	end
	
	AchievementsFrameAchievements_Update();
end

-- [[ Achievement Icon ]] --

function AchievementIcon_Desaturate (self)
	self.bling:SetVertexColor(.6, .6, .6, 1);
	self.frame:SetVertexColor(.75, .75, .75, 1);
	self.texture:SetVertexColor(.55, .55, .55, 1);
end

function AchievementIcon_Saturate (self)
	self.bling:SetVertexColor(1, 1, 1, 1);
	self.frame:SetVertexColor(1, 1, 1, 1);
	self.texture:SetVertexColor(1, 1, 1, 1);
end

-- [[ Achievement Shield ]] --

function AchievementShield_OnLoad (self)	
	self.Desaturate = AchievementShield_Desaturate;
	self.Saturate = AchievementShield_Saturate;
end

-- [[ AchievementButton ]] --

ACHIEVEMENTBUTTON_DESCRIPTIONHEIGHT = 20;
ACHIEVEMENTBUTTON_COLLAPSEDHEIGHT = 84;
ACHIEVEMENTBUTTON_CRITERIAROWHEIGHT = 15;
ACHIEVEMENTBUTTON_METAROWHEIGHT = 14;
ACHIEVEMENTBUTTON_MAXHEIGHT = 232;
ACHIEVEMENTBUTTON_TEXTUREHEIGHT = 128;

function AchievementButton_ResetObjectives ()
	AchievementsFrameAchievementsObjectives:Hide();
end

function AchievementShield_SetPoints(points, pointString, normalFont, smallFont)
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
end

function AchievementButton_ResetTable (t)
	for k, v in next, t do
		v:Hide();
	end
end

function AchievementButton_GetCriteria (index)
	local criteriaTable = AchievementsFrame.criteriaTable;
	
	if ( criteriaTable[index] ) then
		return criteriaTable[index];
	end
	
	local frame = CreateFrame("FRAME", "AchievementsFrameCriteria" .. index, AchievementsFrameAchievements, "AchievementCriteriaTemplate");
	AchievementFrame_LocalizeCriteria(frame);
	criteriaTable[index] = frame;
	
	return frame;
end

function AchievementButton_ResetMiniAchievements ()
	AchievementButton_ResetTable(AchievementsFrame.miniTable);
end

function AchievementButton_GetMiniAchievement (index)
	local miniTable = AchievementsFrame.miniTable;
	if ( miniTable[index] ) then
		return miniTable[index];
	end
	
	local frame = CreateFrame("FRAME", "AchievementsFrameMiniAchievement" .. index, AchievementsFrameAchievements, "MiniAchievementTemplate");
	AchievementButton_LocalizeMiniAchievement(frame);
	miniTable[index] = frame;
	
	return frame;
end

function AchievementButton_ResetProgressBars ()
	AchievementButton_ResetTable(AchievementsFrame.progressBarTable);
end

function AchievementButton_GetProgressBar (index)
	local progressBarTable = AchievementsFrame.progressBarTable;
	if ( progressBarTable[index] ) then
		return progressBarTable[index];
	end
	
	local frame = CreateFrame("STATUSBAR", "AchievementsFrameProgressBar" .. index, AchievementsFrameAchievements, "AchievementProgressBarTemplate");
	AchievementButton_LocalizeProgressBar(frame);
	progressBarTable[index] = frame;
	
	return frame;
end

function AchievementButton_ResetMetas ()
	AchievementButton_ResetTable(AchievementsFrame.metaCriteriaTable);
end

function AchievementButton_GetProgressivePoints(achievementID)
	local points;
	local _, _, progressivePoints, completed = GetAchievementInfo(achievementID);

	while GetPreviousAchievement(achievementID) do
		achievementID = GetPreviousAchievement(achievementID);
		_, _, points, completed = GetAchievementInfo(achievementID);
		progressivePoints = progressivePoints+points;
	end
	
	if ( progressivePoints ) then
		return progressivePoints;
	else
		return 0;
	end
end

function AchievementFrame_GetCategoryNumAchievements_All (categoryID)
	local numAchievements, numCompleted = GetCategoryNumAchievements(categoryID);
	
	return numAchievements, numCompleted, 0;
end

function AchievementFrame_GetCategoryNumAchievements_Complete (categoryID)
	local numAchievements, numCompleted = GetCategoryNumAchievements(categoryID);
	
	return numCompleted, numCompleted, 0;
end

function AchievementFrame_GetCategoryNumAchievements_Incomplete (categoryID)
	local numAchievements, numCompleted = GetCategoryNumAchievements(categoryID);
	
	return numAchievements - numCompleted, 0, numCompleted
end

ACHIEVEMENTUI_SELECTEDFILTER = AchievementFrame_GetCategoryNumAchievements_All;

AchievementsFrameFilters = { 
	{text = ACHIEVEMENTFRAME_FILTER_ALL, func = AchievementFrame_GetCategoryNumAchievements_All},
	{text = ACHIEVEMENTFRAME_FILTER_COMPLETED, func = AchievementFrame_GetCategoryNumAchievements_Complete},
	{text = ACHIEVEMENTFRAME_FILTER_INCOMPLETE, func = AchievementFrame_GetCategoryNumAchievements_Incomplete} 
};

function AchievementFrame_SetFilter(value)
	local filter = AchievementsFrameFilters[value];
	if filter.func ~= ACHIEVEMENTUI_SELECTEDFILTER then
		ACHIEVEMENTUI_SELECTEDFILTER = filter.func;
		AchievementsFrameAchievementsContainerScrollBar:SetValue(0);
		AchievementsFrameAchievements_ForceUpdate();
		AchievementsFrameFilterDropdown:GenerateMenu();
	end
end

-- [[ StatsFrames ]]--

function AchievementsFrameStats_OnEvent (self, event, ...)
	if ( event == "CRITERIA_UPDATE" and self:IsVisible() ) then
		AchievementsFrameStats_Update();
	end
end

function AchievementsFrameStats_OnLoad (self)
	AchievementsFrameStatsContainerScrollBar.Show = 
		function (self)
			AchievementsFrameStats:SetWidth(504);
			for _, button in next, AchievementsFrameStats.buttons do
				button:SetWidth(496);
			end
			getmetatable(self).__index.Show(self);
		end
		
	AchievementsFrameStatsContainerScrollBar.Hide = 
		function (self)
			AchievementsFrameStats:SetWidth(530);
			for _, button in next, AchievementsFrameStats.buttons do
				button:SetWidth(522);
			end
			getmetatable(self).__index.Hide(self);
		end
		
	self:RegisterEvent("CRITERIA_UPDATE");
	AchievementsFrameStatsContainerScrollBarBG:Show();
	AchievementsFrameStatsContainer.update = AchievementsFrameStats_Update;
	HybridScrollFrame_CreateButtons(AchievementsFrameStatsContainer, "StatTemplate");
end

local displayStatCategoriesStats = {};

function AchievementsFrameStats_Update ()
	local category = achievementFunctions.selectedCategory;
	local scrollFrame = AchievementsFrameStatsContainer;
	local offset = HybridScrollFrame_GetOffset(scrollFrame);
	local buttons = scrollFrame.buttons;
	local numButtons = #buttons;
	local statHeight = 24;
	
	local numStats, numCompleted = GetCategoryNumAchievements(category);
	
	local categories = ACHIEVEMENTUI_CATEGORIES;
	-- clear out table
	if ( achievementFunctions.lastCategory ~= category ) then
		local statCat;
		for i in next, displayStatCategoriesStats do
			displayStatCategoriesStats[i] = nil;
		end
		-- build a list of shown category and stat id's
		
		tinsert(displayStatCategoriesStats, {id = category, header = true});
		for i=1, numStats do
			local quantity, skip, id = GetStatistic(category, i);
			if ( not skip ) then
				tinsert(displayStatCategoriesStats, {id = id});
			end
		end
		-- add all the subcategories and their stat id's
		for i, cat in next, categories do
			if ( cat.parent == category ) then
				tinsert(displayStatCategoriesStats, {id = cat.id, header = true});
				numStats = GetCategoryNumAchievements(cat.id);
				for k=1, numStats do
					local quantity, skip, id = GetStatistic(cat.id, k);
					if ( not skip ) then
						tinsert(displayStatCategoriesStats, {id = id});
					end
				end
			end
		end
		achievementFunctions.lastCategory = category;
	end

	-- iterate through the displayStatCategories and display them
	local selection = AchievementsFrameStats.selection;
	local statCount = #displayStatCategoriesStats;
	local statIndex, id, button;
	local stat;
	
	local totalHeight = statCount * statHeight;
	local displayedHeight = numButtons * statHeight;
	for i = 1, numButtons do
		button = buttons[i];
		statIndex = offset + i;
		if ( statIndex <= statCount ) then
			stat = displayStatCategoriesStats[statIndex];
			if ( stat.header ) then
				AchievementsFrameStats_SetHeader(button, stat.id);
			else
				AchievementsFrameStats_SetStat(button, stat.id, nil, statIndex);
			end
			button:Show();
		else
			button:Hide();
		end
	end
	HybridScrollFrame_Update(scrollFrame, totalHeight, displayedHeight);
end

function AchievementsFrameStats_SetStat(button, category, index, colorIndex, isSummary)
	--Remove these variables when we know for sure we don't need them
	local id, name;
	if ( not isSummary ) then
		if ( not index ) then
			id, name = GetAchievementInfo(category);
		else
			id, name = GetAchievementInfo(category, index);
		end
		
	else
		-- This is on the summary page
		id, name = GetAchievementInfoFromCriteria(category);
	end

	if (not id) then
		return;
	end

	button.id = id;
	
	if ( not colorIndex ) then
		if ( not index ) then
			SetBasicMessageDialogText("Error, need a color index or index");
		end
		colorIndex = index;
	end
	button:SetText(name);
	button.background:Show();
	-- Color every other line yellow
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
	
	-- Figure out the criteria
	local numCriteria = GetAchievementNumCriteria(id);
	if ( numCriteria == 0 ) then
		-- This is no good!
	end
	-- Just show the first criteria for now
	local criteriaString, criteriaType, completed, quantityNumber, reqQuantity, charName, flags, assetID, quantity;
	if ( not isSummary ) then
		quantity = GetStatistic(id);
	else
		criteriaString, criteriaType, completed, quantityNumber, reqQuantity, charName, flags, assetID, quantity = GetAchievementCriteriaInfo(category);
	end
	if ( not quantity ) then
		quantity = "--";
	end
	button.value:SetText(quantity);

	-- Hide the header images
	button.title:Hide();
	button.left:Hide();
	button.middle:Hide();
	button.right:Hide();
	button.isHeader = false;
end

function AchievementsFrameStats_SetHeader(button, id)
	-- show header
	button.left:Show();
	button.middle:Show();
	button.right:Show();
	local text;
	if ( id == ACHIEVEMENT_COMPARISON_STATS_SUMMARY_ID ) then
		text = ACHIEVEMENT_SUMMARY_CATEGORY;
	else
		text = GetCategoryInfo(id);
	end
	button.title:SetText(text);
	button.title:Show();
	button.value:SetText("");
	button:SetText("");
	button:SetHeight(24);
	button.background:Hide();
	button.isHeader = true;
	button.id = id;
end

function AchievementStatButton_OnClick(self)
	if ( self.isHeader ) then
		achievementFunctions.selectedCategory = self.id;
		AchievementsFrameCategories_Update();
		AchievementsFrameStats_Update();
	elseif ( self.summary ) then
		AchievementFrame_SelectSummaryStatistic(self.id);
	end
end

function AchievementStatButton_OnEnter(self)
	if ( self.text:IsTruncated() ) then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(self.text:GetText(), 1, 1, 1, 1, 1);
	end
end


-- [[ Summary Frame ]] --

function AchievementsFrameSummaryAchievement_OnClick(self)
	local id = self.id
	local nextID, completed = GetNextAchievement(id);
	if ( nextID and completed ) then
		local newID;
		while ( nextID and completed ) do
			newID, completed = GetNextAchievement(nextID);
			if ( completed ) then
				nextID = newID;
			end
		end
		id = nextID;
	end
	
	AchievementFrame_SelectAchievement(id);
end

function AchievementsFrameSummaryAchievement_OnEnter(self)
	self.highlight:Show();
	if ( self.tooltipTitle ) then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(self.tooltipTitle,1,1,1);
		GameTooltip:AddLine(self.tooltip, nil, nil, nil, 1);
		GameTooltip:Show();
	end
end

function AchievementsFrameSummaryCategoryButton_OnClick (self)
	local id = self:GetParent():GetID();
	for _, button in next, AchievementsFrameCategoriesContainer.buttons do
		if ( button.categoryID == id ) then
			button:Click();
			return;
		end
	end
end

function AchievementFrame_GetCategoryTotalNumAchievements (id, showAll)
	-- Not recursive because we only have one deep and this saves time.
	local totalAchievements, totalCompleted = 0, 0;
	local numAchievements, numCompleted = GetCategoryNumAchievements(id, showAll);
	totalAchievements = totalAchievements + numAchievements;
	totalCompleted = totalCompleted + numCompleted;
	
	for _, category in next, ACHIEVEMENTUI_CATEGORIES do
		if ( category.parent == id ) then
			numAchievements, numCompleted = GetCategoryNumAchievements(category.id, showAll);
			totalAchievements = totalAchievements + numAchievements;
			totalCompleted = totalCompleted + numCompleted;
		end
	end
	
	return totalAchievements, totalCompleted;
end

function AchievementsFrameSummaryCategory_OnEvent (self, event, ...)
	AchievementsFrameSummaryCategory_OnShow(self);
end

function AchievementsFrameSummaryCategory_OnShow (self)
	local totalAchievements, totalCompleted = AchievementFrame_GetCategoryTotalNumAchievements(self:GetID(), true);
	
	self.text:SetText(string.format("%d/%d", totalCompleted, totalAchievements));
	self:SetMinMaxValues(0, totalAchievements);
	self:SetValue(totalCompleted);
	self:RegisterEvent("ACHIEVEMENT_EARNED");
end

function AchievementsFrameSummaryCategory_OnHide (self)
	self:UnregisterEvent("ACHIEVEMENT_EARNED");
end

function AchievementsFrameAchievements_FindSelection()
	local _, maxVal = AchievementsFrameAchievementsContainerScrollBar:GetMinMaxValues();
	local scrollHeight = AchievementsFrameAchievementsContainer:GetHeight();
	local newHeight = 0;
	AchievementsFrameAchievementsContainerScrollBar:SetValue(0);	
	while ( not shown ) do
		for _, button in next, AchievementsFrameAchievementsContainer.buttons do
			if ( button.selected ) then
				newHeight = AchievementsFrameAchievementsContainerScrollBar:GetValue() + AchievementsFrameAchievementsContainer:GetTop() - button:GetTop();
				newHeight = min(newHeight, maxVal);
				AchievementsFrameAchievementsContainerScrollBar:SetValue(newHeight);					
				return;
			end
		end		
		if ( AchievementsFrameAchievementsContainerScrollBar:GetValue() == maxVal ) then		
			return;
		else
			newHeight = newHeight + scrollHeight;
			newHeight = min(newHeight, maxVal);
			AchievementsFrameAchievementsContainerScrollBar:SetValue(newHeight);
		end
	end
end

function AchievementsFrameAchievements_AdjustSelection()
	local selectedButton;	
	-- check if selection is visible
	for _, button in next, AchievementsFrameAchievementsContainer.buttons do
		if ( button.selected ) then
			selectedButton = button;
			break;
		end
	end	
	
	if ( not selectedButton ) then
		AchievementsFrameAchievements_FindSelection();
	else
		local newHeight;
		if ( selectedButton:GetTop() > AchievementsFrameAchievementsContainer:GetTop() ) then
			newHeight = AchievementsFrameAchievementsContainerScrollBar:GetValue() + AchievementsFrameAchievementsContainer:GetTop() - selectedButton:GetTop();
		elseif ( selectedButton:GetBottom() < AchievementsFrameAchievementsContainer:GetBottom() ) then
			if ( selectedButton:GetHeight() > AchievementsFrameAchievementsContainer:GetHeight() ) then
				newHeight = AchievementsFrameAchievementsContainerScrollBar:GetValue() + AchievementsFrameAchievementsContainer:GetTop() - selectedButton:GetTop();
			else
				newHeight = AchievementsFrameAchievementsContainerScrollBar:GetValue() + AchievementsFrameAchievementsContainer:GetBottom() - selectedButton:GetBottom();
			end
		end
		if ( newHeight ) then
			local _, maxVal = AchievementsFrameAchievementsContainerScrollBar:GetMinMaxValues();
			newHeight = min(newHeight, maxVal);
			AchievementsFrameAchievementsContainerScrollBar:SetValue(newHeight);					
		end
	end
end

function AchievementsFrameComparisonContainer_OnLoad (parent)
	AchievementsFrameComparisonContainerScrollBar.Show = 
		function (self)
			AchievementsFrameComparison:SetWidth(626);
			AchievementsFrameComparisonSummaryPlayer:SetWidth(498);
			for _, button in next, AchievementsFrameComparisonContainer.buttons do
				button:SetWidth(616);
				button.player:SetWidth(498);
			end
			getmetatable(self).__index.Show(self);
		end
		
	AchievementsFrameComparisonContainerScrollBar.Hide = 
		function (self)
			AchievementsFrameComparison:SetWidth(650);
			AchievementsFrameComparisonSummaryPlayer:SetWidth(522);
			for _, button in next, AchievementsFrameComparisonContainer.buttons do
				button:SetWidth(640);
				button.player:SetWidth(522);
			end
			getmetatable(self).__index.Hide(self);
		end
	
	AchievementsFrameComparisonContainerScrollBarBG:Show();
	AchievementsFrameComparisonContainer.update = AchievementsFrameComparison_Update;
	HybridScrollFrame_CreateButtons(AchievementsFrameComparisonContainer, "ComparisonTemplate", 0, -2);
end

function AchievementsFrameComparisonStatsContainer_OnLoad (parent)
	AchievementsFrameComparisonStatsContainerScrollBar.Show = 
		function (self)
			AchievementsFrameComparison:SetWidth(626);
			for _, button in next, AchievementsFrameComparisonStatsContainer.buttons do
				button:SetWidth(616);
			end
			getmetatable(self).__index.Show(self);
		end
		
	AchievementsFrameComparisonStatsContainerScrollBar.Hide = 
		function (self)
			AchievementsFrameComparison:SetWidth(650);
			for _, button in next, AchievementsFrameComparisonStatsContainer.buttons do
				button:SetWidth(640);
			end
			getmetatable(self).__index.Hide(self);
		end
	
	AchievementsFrameComparisonStatsContainerScrollBarBG:Show();
	AchievementsFrameComparisonStatsContainer.update = AchievementsFrameComparison_UpdateStats;
	HybridScrollFrame_CreateButtons(AchievementsFrameComparisonStatsContainer, "ComparisonStatTemplate", 0, -2);
end

function AchievementsFrameComparison_ClearSelection ()
	-- Doesn't do anything WHEE~!
end

function AchievementsFrameComparison_ForceUpdate ()
	if ( achievementFunctions == COMPARISON_ACHIEVEMENT_FUNCTIONS ) then
		local buttons = AchievementsFrameComparisonContainer.buttons;
		for i, button in next, buttons do
			button.id = nil;
		end
		
		AchievementsFrameComparison_Update();
	elseif ( achievementFunctions == COMPARISON_STAT_FUNCTIONS ) then
		AchievementsFrameComparison_UpdateStats();
	end
end

function AchievementsFrameComparison_Update ()
	local category = achievementFunctions.selectedCategory;
	if ( not category or category == "summary" or category == ACHIEVEMENT_COMPARISON_SUMMARY_ID or category == ACHIEVEMENT_COMPARISON_STATS_SUMMARY_ID ) then
		return;
	end
	local scrollFrame = AchievementsFrameComparisonContainer
	
	local offset = HybridScrollFrame_GetOffset(scrollFrame);
	local buttons = scrollFrame.buttons;
	local numAchievements, numCompleted = GetCategoryNumAchievements(category);
	local numButtons = #buttons;

	local achievementIndex;
	local buttonHeight = buttons[1]:GetHeight();
	for i = 1, numButtons do
		achievementIndex = i + offset;
		AchievementsFrameComparison_DisplayAchievement(buttons[i], category, achievementIndex);
	end
	
	HybridScrollFrame_Update(scrollFrame, buttonHeight*numAchievements, buttonHeight*numButtons);
end

ACHIEVEMENTCOMPARISON_PLAYERSHIELDFONT1 = GameFontNormal;
ACHIEVEMENTCOMPARISON_PLAYERSHIELDFONT2 = GameFontNormalSmall;
ACHIEVEMENTCOMPARISON_FRIENDSHIELDFONT1 = GameFontNormalSmall;
ACHIEVEMENTCOMPARISON_FRIENDSHIELDFONT2 = GameFontNormalSmall;

local displayStatCategoriesComparison = {};
function AchievementsFrameComparison_UpdateStats ()
	local category = achievementFunctions.selectedCategory;
	local scrollFrame = AchievementsFrameComparisonStatsContainer;
	local offset = HybridScrollFrame_GetOffset(scrollFrame);
	local buttons = scrollFrame.buttons;
	local numButtons = #buttons;
	local headerHeight = 24;
	local statHeight = 24;
	local totalHeight = 0;	
	local numStats, numCompleted = GetCategoryNumAchievements(category);

	local categories = ACHIEVEMENTUI_CATEGORIES;
	-- clear out table
	if ( achievementFunctions.lastCategory ~= category ) then
		local statCat;
		for i in next, displayStatCategoriesComparison do
			displayStatCategoriesComparison[i] = nil;
		end
		-- build a list of shown category and stat id's

		tinsert(displayStatCategoriesComparison, {id = category, header = true});
		totalHeight = totalHeight+headerHeight;

		for i=1, numStats do
			tinsert(displayStatCategoriesComparison, {id = GetAchievementInfo(category, i)});
			totalHeight = totalHeight+statHeight;
		end
		achievementFunctions.lastCategory = category;
		achievementFunctions.lastHeight = totalHeight;
	else
		totalHeight = achievementFunctions.lastHeight;
	end
	
	-- add all the subcategories and their stat id's
	for i, cat in next, categories do
		if ( cat.parent == category ) then
			tinsert(displayStatCategoriesComparison, {id = cat.id, header = true});
			totalHeight = totalHeight+headerHeight;
			numStats = GetCategoryNumAchievements(cat.id);
			for k=1, numStats do
				tinsert(displayStatCategoriesComparison, {id = GetAchievementInfo(cat.id, k)});
				totalHeight = totalHeight+statHeight;
			end
		end
	end

	-- iterate through the displayStatCategories and display them
	local statCount = #displayStatCategoriesComparison;
	local statIndex, id, button;
	local stat;
	local displayedHeight = 0;
	for i = 1, numButtons do
		button = buttons[i];
		statIndex = offset + i;
		if ( statIndex <= statCount ) then
			stat = displayStatCategoriesComparison[statIndex];
			if ( stat.header ) then
				AchievementsFrameComparisonStats_SetHeader(button, stat.id);
			else
				AchievementsFrameComparisonStats_SetStat(button, stat.id, nil, statIndex);
			end
			button:Show();
		else
			button:Hide();
		end
		displayedHeight = displayedHeight+button:GetHeight();
	end
	HybridScrollFrame_Update(scrollFrame, totalHeight, displayedHeight);
end

function AchievementsFrameComparisonStats_SetStat (button, category, index, colorIndex, isSummary)
--Remove these variables when we know for sure we don't need them
	local id, name;
	if ( not isSummary ) then
		if ( not index ) then
			id, name = GetAchievementInfo(category);
		else
			id, name = GetAchievementInfo(category, index);
		end
		
	else
		-- This is on the summary page
		id, name = GetAchievementInfoFromCriteria(category);
	end
	
	button.id = id;
	
	if ( not colorIndex ) then
		if ( not index ) then
			SetBasicMessageDialogText("Error, need a color index or index");
		end
		colorIndex = index;
	end
	
	button.background:Show();
	-- Color every other line yellow
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
	
	-- Figure out the criteria
	local numCriteria = GetAchievementNumCriteria(id);
	if ( numCriteria == 0 ) then
		-- This is no good!
	end
	-- Just show the first criteria for now
	local criteriaString, criteriaType, completed, quantityNumber, reqQuantity, charName, flags, assetID, quantity, friendQuantity;
	if ( not isSummary ) then
		friendQuantity = GetComparisonStatistic(id);
		quantity = GetStatistic(id);
	else
		criteriaString, criteriaType, completed, quantityNumber, reqQuantity, charName, flags, assetID, quantity = GetAchievementCriteriaInfo(category);
	end
	if ( not quantity ) then
		quantity = "--";
	end
	if ( not friendQuantity ) then
		friendQuantity = "--";
	end
	
	button.value:SetText(quantity);
	
	-- We're gonna use button.text here to measure string width for friendQuantity. This saves us many strings!
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
	
	button.text:SetText(name);
	button.friendValue:SetText(friendQuantity);
	
	
	-- Hide the header images
	button.title:Hide();
	button.left:Hide();
	button.middle:Hide();
	button.right:Hide();
	button.left2:Hide();
	button.middle2:Hide();
	button.right2:Hide();
	button.isHeader = false;
end

function AchievementsFrameComparisonStats_SetHeader(button, id)
	-- show header
	button.left:Show();
	button.middle:Show();
	button.right:Show();
	button.left2:Show();
	button.middle2:Show();
	button.right2:Show();
	button.title:SetText(GetCategoryInfo(id));
	button.title:Show();
	button.friendValue:SetText("");
	button.value:SetText("");
	button.text:SetText("");
	button:SetHeight(24);
	button.background:Hide();
	button.isHeader = true;
	button.id = id;
end

function AchievementFrame_IsComparison()
	return AchievementsFrame.isComparison;
end

ACHIEVEMENT_FUNCTIONS = {
	categoryAccessor = GetCategoryList,
	clearFunc = AchievementsFrameAchievements_ClearSelection,
	updateFunc = AchievementsFrameAchievements_Update,
	selectedCategory = "summary";
}

STAT_FUNCTIONS = {
	categoryAccessor = GetStatisticsCategoryList,
	clearFunc = nil,
	updateFunc = AchievementsFrameStats_Update,
	selectedCategory = "summary";
}

COMPARISON_ACHIEVEMENT_FUNCTIONS = {
	categoryAccessor = GetCategoryList,
	clearFunc = AchievementsFrameComparison_ClearSelection,
	updateFunc = AchievementsFrameComparison_Update,
	selectedCategory = -1,
}

COMPARISON_STAT_FUNCTIONS = {
	categoryAccessor = GetStatisticsCategoryList,
	clearFunc = AchievementsFrameComparison_ClearSelection,
	updateFunc = AchievementsFrameComparison_UpdateStats,
	selectedCategory = -2,
}

achievementFunctions = ACHIEVEMENT_FUNCTIONS;

function AchievementFrame_ClearTextures()
	for k, v in pairs(ACHIEVEMENT_TEXTURES_TO_LOAD) do
		_G[v.name]:SetTexture(nil);
	end
end

function AchievementFrame_LoadTextures()
	for k, v in pairs(ACHIEVEMENT_TEXTURES_TO_LOAD) do
		if ( v.file ) then
			_G[v.name]:SetTexture(v.file);
		end
	end
end

-- The achievement UI frame is intentionally named AchievementsFrame instead of
-- AchievementFrame: Blizzard's protected UpdateMicroButtons() reads the global
-- AchievementFrame during GameMenu Show/Hide, and a frame global created by an
-- insecure addon is permanently tainted, which blocks the Log Out/Exit buttons
-- (ADDON_ACTION_FORBIDDEN). With the rename that protected read cleanly sees
-- nil. The two native insecure functions below still reference the old globals
-- (which would now error), so redefine them against the bundled UI. Neither is
-- read by protected code, so overriding them is taint-safe.

-- Native alert toast click handler (AlertFrameSystems.lua); our toasts go
-- through the native AchievementAlertSystem which binds this by name.
function AchievementAlertFrame_OnClick(self, button, down)
	if ( AlertFrame_OnClick and AlertFrame_OnClick(self, button, down) ) then
		return;
	end

	local id = self.id;
	if ( not id ) then
		return;
	end

	CloseAllWindows();
	ShowUIPanel(AchievementsFrame);

	local _, _, _, achCompleted = GetAchievementInfo(id);
	if ( achCompleted and (ACHIEVEMENTUI_SELECTEDFILTER == AchievementsFrameFilters[ACHIEVEMENT_FILTER_INCOMPLETE].func) ) then
		AchievementFrame_SetFilter(ACHIEVEMENT_FILTER_ALL);
	elseif ( (not achCompleted) and (ACHIEVEMENTUI_SELECTEDFILTER == AchievementsFrameFilters[ACHIEVEMENT_FILTER_COMPLETE].func) ) then
		AchievementFrame_SetFilter(ACHIEVEMENT_FILTER_ALL);
	end

	AchievementFrame_SelectAchievement(id);
end

-- Native deep link used by guild news/rewards (UIParent.lua).
function OpenAchievementFrameToAchievement(achievementID)
	if ( not AchievementsFrame ) then
		AchievementFrame_LoadUI();
	end
	if ( not AchievementsFrame ) then
		return;
	end
	if ( not AchievementsFrame:IsShown() ) then
		AchievementFrame_ToggleAchievementFrame(false);
	end

	AchievementFrame_SelectAchievement(achievementID);
end
