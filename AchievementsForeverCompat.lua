-- Forever: Classic-era functions mapped onto the Mainline API; file-local aliases in the addon's files pick them up.

local Compat = {};

local function define(name, fn)
	if type(fn) == "function" then
		Compat[name] = fn;
	end
end

local function guarded(fn)
	return function(...)
		local results = { pcall(fn, ...) };
		if not results[1] then
			return nil;
		end
		return unpack(results, 2);
	end;
end

if C_Item then
	define("GetItemInfo", C_Item.GetItemInfo);
	define("GetItemInfoInstant", C_Item.GetItemInfoInstant);
end

if C_Spell and C_Spell.GetSpellInfo then
	define("GetSpellInfo", guarded(function(spell)
		if not spell then
			return nil;
		end
		local info = C_Spell.GetSpellInfo(spell);
		if not info then
			return nil;
		end
		return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID, info.originalIconID;
	end));
end

if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
	local function UnpackAura(aura)
		if not aura then
			return nil;
		end
		if AuraUtil and AuraUtil.UnpackAuraData then
			return AuraUtil.UnpackAuraData(aura);
		end
		return aura.name, aura.icon, aura.applications, aura.dispelName, aura.duration, aura.expirationTime,
			aura.sourceUnit, aura.isStealable, aura.nameplateShowPersonal, aura.spellId, aura.canApplyAura,
			aura.isBossAura, aura.isFromPlayerOrPlayerPet, aura.nameplateShowAll, aura.timeMod;
	end
	define("UnitAura", guarded(function(unit, index, filter)
		return UnpackAura(C_UnitAuras.GetAuraDataByIndex(unit, index, filter));
	end));
end

if C_CurrencyInfo then
	define("GetCoinTextureString", C_CurrencyInfo.GetCoinTextureString);
end

if C_Reputation then
	local function UnpackFaction(data)
		if not data then
			return nil;
		end
		return data.name, data.description, data.reaction, data.currentReactionThreshold, data.nextReactionThreshold,
			data.currentStanding, data.atWarWith, data.canToggleAtWar, data.isHeader, data.isCollapsed,
			data.isHeaderWithRep, data.isWatched, data.isChild, data.factionID, data.hasBonusRepGain, data.canSetInactive;
	end
	define("GetNumFactions", C_Reputation.GetNumFactions);
	if C_Reputation.GetFactionDataByIndex then
		define("GetFactionInfo", guarded(function(index)
			return UnpackFaction(C_Reputation.GetFactionDataByIndex(index));
		end));
	end
	if C_Reputation.GetFactionDataByID then
		define("GetFactionInfoByID", guarded(function(factionID)
			return UnpackFaction(C_Reputation.GetFactionDataByID(factionID));
		end));
	end
	define("ExpandFactionHeader", C_Reputation.ExpandFactionHeader);
	define("CollapseFactionHeader", C_Reputation.CollapseFactionHeader);
end

if C_QuestLog then
	if C_QuestLog.GetAllCompletedQuestIDs then
		define("GetQuestsCompleted", function(target)
			local lookup = type(target) == "table" and target or {};
			local ok, questIDs = pcall(C_QuestLog.GetAllCompletedQuestIDs);
			if ok and type(questIDs) == "table" then
				for _, questID in ipairs(questIDs) do
					lookup[questID] = true;
				end
			end
			return lookup;
		end);
	end
end

if C_SkillInfo then
	define("GetNumSkillLines", C_SkillInfo.GetNumSkillLines);
	if C_SkillInfo.GetSkillLineInfo then
		define("GetSkillLineInfo", guarded(function(index)
			local info = C_SkillInfo.GetSkillLineInfo(index);
			if not info then
				return nil;
			end
			local isExpanded = info.isExpanded;
			if isExpanded == nil and info.isCollapsed ~= nil then
				isExpanded = not info.isCollapsed;
			end
			return info.name or info.skillName, info.isHeader, isExpanded, info.skillRank or info.rank,
				info.numTempPoints or info.tempSkillPoints or 0, info.skillModifier or info.modifier or 0,
				info.skillMaxRank or info.maxRank, info.isAbandonable, info.stepCost, info.rankCost, info.minLevel,
				info.skillCostType, info.skillDescription or info.description;
		end));
	end
end

if C_Bank and C_Bank.FetchNumPurchasedBankTabs then
	define("GetNumBankSlots", guarded(function()
		local bankType = Enum and Enum.BankType and Enum.BankType.Character or 0;
		local purchased = C_Bank.FetchNumPurchasedBankTabs(bankType);
		return tonumber(purchased) or 0, true;
	end));
end

if GetNumGroupMembers then
	define("GetNumRaidMembers", function()
		return IsInRaid() and GetNumGroupMembers() or 0;
	end);
	define("GetNumPartyMembers", function()
		if IsInRaid() or not IsInGroup() then
			return 0;
		end
		return math.max(GetNumGroupMembers() - 1, 0);
	end);
end
if IsMounted then
	define("UnitIsMounted", function(unit)
		if unit == "player" then
			return IsMounted() and true or false;
		end
		return nil;
	end);
end

define("SetPortraitToTexture", function(texture, path)
	if type(texture) == "string" then
		texture = _G[texture];
	end
	if not texture or not texture.SetTexture then
		return;
	end
	texture:SetTexture(path);
	if texture.SetTexCoord then
		texture:SetTexCoord(0, 1, 0, 1);
	end
end);

-- Forever binds Y to the Legacy window; move shipped defaults up one modifier.
local FOREVER_DEFAULT_BINDINGS = {
	{ action = "TOGGLEACHIEVEMENT", shippedDefault = "Y", foreverDefault = "SHIFT-Y" },
	{ action = "TOGGLESTATISTICS", shippedDefault = "SHIFT-Y", foreverDefault = "CTRL-Y" },
};
local LEGACY_BINDING_ACTION = "TOGGLELEGACYSYSTEM";

local function BindingMigrationDB()
	local characterSet = GetCurrentBindingSet and GetCurrentBindingSet() == (CHARACTER_BINDINGS or 2);
	local db = rawget(_G, characterSet and "AchievementsCharacterDB" or "AchievementsDB");
	return type(db) == "table" and db or nil;
end

local function BindingsMigrated()
	local db = BindingMigrationDB();
	return db ~= nil and db.foreverBindingsMigrated == true;
end

local function MarkBindingsMigrated()
	local db = BindingMigrationDB();
	if db then
		db.foreverBindingsMigrated = true;
	end
end

local function ApplyForeverDefaultBindings()
	if not GetBindingKey or not SetBinding or not GetBindingAction or BindingsMigrated() then
		return true;
	end
	if InCombatLockdown() then
		return false;
	end
	if GetBindingKey(LEGACY_BINDING_ACTION) ~= nil then
		return true;
	end
	for _, binding in ipairs(FOREVER_DEFAULT_BINDINGS) do
		local key1, key2 = GetBindingKey(binding.action);
		if key1 ~= binding.shippedDefault or key2 ~= nil then
			return true;
		end
	end
	if (GetBindingAction("CTRL-Y") or "") ~= "" then
		return true;
	end

	for index = #FOREVER_DEFAULT_BINDINGS, 1, -1 do
		local binding = FOREVER_DEFAULT_BINDINGS[index];
		SetBinding(binding.shippedDefault, nil);
		SetBinding(binding.foreverDefault, binding.action);
	end
	SetBinding("Y", LEGACY_BINDING_ACTION);
	MarkBindingsMigrated();

	if SaveBindings and GetCurrentBindingSet then
		pcall(SaveBindings, GetCurrentBindingSet());
	end
	return true;
end

local bindingFrame = CreateFrame("Frame");
bindingFrame:RegisterEvent("PLAYER_LOGIN");
bindingFrame:SetScript("OnEvent", function(self)
	local ok, done = pcall(ApplyForeverDefaultBindings);
	if ok and done == false then
		self:RegisterEvent("PLAYER_REGEN_ENABLED");
		return;
	end
	self:UnregisterAllEvents();
end);

if rawget(_G, "MAX_TRACKED_ACHIEVEMENTS") == nil then
	MAX_TRACKED_ACHIEVEMENTS = 10;
end
if rawget(_G, "ACHIEVEMENT_WATCH_TOO_MANY") == nil then
	ACHIEVEMENT_WATCH_TOO_MANY = "You may only track %d achievements at a time.";
end
if rawget(_G, "ERR_ACHIEVEMENT_WATCH_COMPLETED") == nil then
	ERR_ACHIEVEMENT_WATCH_COMPLETED = "You can't track completed achievements.";
end

-- BEGIN GENERATED UI GLOBAL NAME MAP
AchievementsForeverUIGlobalNames = {
	["ACHIEVEMENTBUTTON_COLLAPSEDHEIGHT"] = "ACHIEVEMENTSBUTTON_COLLAPSEDHEIGHT",
	["ACHIEVEMENTBUTTON_CRITERIAROWHEIGHT"] = "ACHIEVEMENTSBUTTON_CRITERIAROWHEIGHT",
	["ACHIEVEMENTBUTTON_DESCRIPTIONHEIGHT"] = "ACHIEVEMENTSBUTTON_DESCRIPTIONHEIGHT",
	["ACHIEVEMENTBUTTON_LABELWIDTH"] = "ACHIEVEMENTSBUTTON_LABELWIDTH",
	["ACHIEVEMENTBUTTON_MAXHEIGHT"] = "ACHIEVEMENTSBUTTON_MAXHEIGHT",
	["ACHIEVEMENTBUTTON_METAROWHEIGHT"] = "ACHIEVEMENTSBUTTON_METAROWHEIGHT",
	["ACHIEVEMENTBUTTON_TEXTUREHEIGHT"] = "ACHIEVEMENTSBUTTON_TEXTUREHEIGHT",
	["ACHIEVEMENTCOMPARISON_FRIENDSHIELDFONT1"] = "ACHIEVEMENTSCOMPARISON_FRIENDSHIELDFONT1",
	["ACHIEVEMENTCOMPARISON_FRIENDSHIELDFONT2"] = "ACHIEVEMENTSCOMPARISON_FRIENDSHIELDFONT2",
	["ACHIEVEMENTCOMPARISON_PLAYERSHIELDFONT1"] = "ACHIEVEMENTSCOMPARISON_PLAYERSHIELDFONT1",
	["ACHIEVEMENTCOMPARISON_PLAYERSHIELDFONT2"] = "ACHIEVEMENTSCOMPARISON_PLAYERSHIELDFONT2",
	["ACHIEVEMENTFRAME_SUBFRAMES"] = "ACHIEVEMENTSFRAME_SUBFRAMES",
	["ACHIEVEMENTUI_CATEGORIES"] = "ACHIEVEMENTSUI_CATEGORIES",
	["ACHIEVEMENTUI_CATEGORIESWIDTH"] = "ACHIEVEMENTSUI_CATEGORIESWIDTH",
	["ACHIEVEMENTUI_DEFAULTSUMMARYACHIEVEMENTS"] = "ACHIEVEMENTSUI_DEFAULTSUMMARYACHIEVEMENTS",
	["ACHIEVEMENTUI_FONTHEIGHT"] = "ACHIEVEMENTSUI_FONTHEIGHT",
	["ACHIEVEMENTUI_GOLDBORDER_A"] = "ACHIEVEMENTSUI_GOLDBORDER_A",
	["ACHIEVEMENTUI_GOLDBORDER_B"] = "ACHIEVEMENTSUI_GOLDBORDER_B",
	["ACHIEVEMENTUI_GOLDBORDER_G"] = "ACHIEVEMENTSUI_GOLDBORDER_G",
	["ACHIEVEMENTUI_GOLDBORDER_R"] = "ACHIEVEMENTSUI_GOLDBORDER_R",
	["ACHIEVEMENTUI_MAXCONTENTWIDTH"] = "ACHIEVEMENTSUI_MAXCONTENTWIDTH",
	["ACHIEVEMENTUI_MAX_LINES_COLLAPSED"] = "ACHIEVEMENTSUI_MAX_LINES_COLLAPSED",
	["ACHIEVEMENTUI_MAX_SUMMARY_ACHIEVEMENTS"] = "ACHIEVEMENTSUI_MAX_SUMMARY_ACHIEVEMENTS",
	["ACHIEVEMENTUI_PROGRESSIVEHEIGHT"] = "ACHIEVEMENTSUI_PROGRESSIVEHEIGHT",
	["ACHIEVEMENTUI_PROGRESSIVEWIDTH"] = "ACHIEVEMENTSUI_PROGRESSIVEWIDTH",
	["ACHIEVEMENTUI_REDBORDER_A"] = "ACHIEVEMENTSUI_REDBORDER_A",
	["ACHIEVEMENTUI_REDBORDER_B"] = "ACHIEVEMENTSUI_REDBORDER_B",
	["ACHIEVEMENTUI_REDBORDER_G"] = "ACHIEVEMENTSUI_REDBORDER_G",
	["ACHIEVEMENTUI_REDBORDER_R"] = "ACHIEVEMENTSUI_REDBORDER_R",
	["ACHIEVEMENTUI_SELECTEDFILTER"] = "ACHIEVEMENTSUI_SELECTEDFILTER",
	["ACHIEVEMENT_BLUE_BORDER_COLOR"] = "ACHIEVEMENTS_BLUE_BORDER_COLOR",
	["ACHIEVEMENT_CATEGORY_HIGHLIGHT_A"] = "ACHIEVEMENTS_CATEGORY_HIGHLIGHT_A",
	["ACHIEVEMENT_CATEGORY_HIGHLIGHT_B"] = "ACHIEVEMENTS_CATEGORY_HIGHLIGHT_B",
	["ACHIEVEMENT_CATEGORY_HIGHLIGHT_G"] = "ACHIEVEMENTS_CATEGORY_HIGHLIGHT_G",
	["ACHIEVEMENT_CATEGORY_HIGHLIGHT_R"] = "ACHIEVEMENTS_CATEGORY_HIGHLIGHT_R",
	["ACHIEVEMENT_CATEGORY_NORMAL_A"] = "ACHIEVEMENTS_CATEGORY_NORMAL_A",
	["ACHIEVEMENT_CATEGORY_NORMAL_B"] = "ACHIEVEMENTS_CATEGORY_NORMAL_B",
	["ACHIEVEMENT_CATEGORY_NORMAL_G"] = "ACHIEVEMENTS_CATEGORY_NORMAL_G",
	["ACHIEVEMENT_CATEGORY_NORMAL_R"] = "ACHIEVEMENTS_CATEGORY_NORMAL_R",
	["ACHIEVEMENT_COMPARISON_STATS_SUMMARY_ID"] = "ACHIEVEMENTS_COMPARISON_STATS_SUMMARY_ID",
	["ACHIEVEMENT_COMPARISON_SUMMARY_ID"] = "ACHIEVEMENTS_COMPARISON_SUMMARY_ID",
	["ACHIEVEMENT_FILTER_ALL"] = "ACHIEVEMENTS_FILTER_ALL",
	["ACHIEVEMENT_FILTER_COMPLETE"] = "ACHIEVEMENTS_FILTER_COMPLETE",
	["ACHIEVEMENT_FILTER_INCOMPLETE"] = "ACHIEVEMENTS_FILTER_INCOMPLETE",
	["ACHIEVEMENT_FUNCTIONS"] = "ACHIEVEMENTS_FUNCTIONS",
	["ACHIEVEMENT_GOLD_BORDER_COLOR"] = "ACHIEVEMENTS_GOLD_BORDER_COLOR",
	["ACHIEVEMENT_RED_BORDER_COLOR"] = "ACHIEVEMENTS_RED_BORDER_COLOR",
	["ACHIEVEMENT_TEXTURES_TO_LOAD"] = "ACHIEVEMENTS_TEXTURES_TO_LOAD",
	["AchievementAlertFrame_OnClick"] = "AchievementsAlertFrame_OnClick",
	["AchievementButton_Collapse"] = "AchievementsButton_Collapse",
	["AchievementButton_Desaturate"] = "AchievementsButton_Desaturate",
	["AchievementButton_DisplayAchievement"] = "AchievementsButton_DisplayAchievement",
	["AchievementButton_DisplayObjectives"] = "AchievementsButton_DisplayObjectives",
	["AchievementButton_Expand"] = "AchievementsButton_Expand",
	["AchievementButton_GetCriteria"] = "AchievementsButton_GetCriteria",
	["AchievementButton_GetMeta"] = "AchievementsButton_GetMeta",
	["AchievementButton_GetMiniAchievement"] = "AchievementsButton_GetMiniAchievement",
	["AchievementButton_GetProgressBar"] = "AchievementsButton_GetProgressBar",
	["AchievementButton_GetProgressivePoints"] = "AchievementsButton_GetProgressivePoints",
	["AchievementButton_Localize"] = "AchievementsButton_Localize",
	["AchievementButton_LocalizeMetaAchievement"] = "AchievementsButton_LocalizeMetaAchievement",
	["AchievementButton_LocalizeMiniAchievement"] = "AchievementsButton_LocalizeMiniAchievement",
	["AchievementButton_LocalizeProgressBar"] = "AchievementsButton_LocalizeProgressBar",
	["AchievementButton_OnClick"] = "AchievementsButton_OnClick",
	["AchievementButton_OnLoad"] = "AchievementsButton_OnLoad",
	["AchievementButton_ResetCriteria"] = "AchievementsButton_ResetCriteria",
	["AchievementButton_ResetMetas"] = "AchievementsButton_ResetMetas",
	["AchievementButton_ResetMiniAchievements"] = "AchievementsButton_ResetMiniAchievements",
	["AchievementButton_ResetObjectives"] = "AchievementsButton_ResetObjectives",
	["AchievementButton_ResetProgressBars"] = "AchievementsButton_ResetProgressBars",
	["AchievementButton_ResetTable"] = "AchievementsButton_ResetTable",
	["AchievementButton_Saturate"] = "AchievementsButton_Saturate",
	["AchievementButton_ToggleTracking"] = "AchievementsButton_ToggleTracking",
	["AchievementButton_UpdatePlusMinusTexture"] = "AchievementsButton_UpdatePlusMinusTexture",
	["AchievementCategoryButton_Localize"] = "AchievementsCategoryButton_Localize",
	["AchievementCategoryButton_OnClick"] = "AchievementsCategoryButton_OnClick",
	["AchievementCategoryButton_OnLoad"] = "AchievementsCategoryButton_OnLoad",
	["AchievementCategoryTemplate"] = "AchievementsCategoryTemplate",
	["AchievementCheckButtonTemplate"] = "AchievementsCheckButtonTemplate",
	["AchievementComparisonButton_Localize"] = "AchievementsComparisonButton_Localize",
	["AchievementComparisonFriendButton_Desaturate"] = "AchievementsComparisonFriendButton_Desaturate",
	["AchievementComparisonFriendButton_OnLoad"] = "AchievementsComparisonFriendButton_OnLoad",
	["AchievementComparisonFriendButton_Saturate"] = "AchievementsComparisonFriendButton_Saturate",
	["AchievementComparisonPlayerButton_Desaturate"] = "AchievementsComparisonPlayerButton_Desaturate",
	["AchievementComparisonPlayerButton_OnLoad"] = "AchievementsComparisonPlayerButton_OnLoad",
	["AchievementComparisonPlayerButton_Saturate"] = "AchievementsComparisonPlayerButton_Saturate",
	["AchievementCriteriaTemplate"] = "AchievementsCriteriaTemplate",
	["AchievementFrame_ClearTextures"] = "AchievementsFrame_ClearTextures",
	["AchievementFrame_DisplayComparison"] = "AchievementsFrame_DisplayComparison",
	["AchievementFrame_ForceUpdate"] = "AchievementsFrame_ForceUpdate",
	["AchievementFrame_GetCategoryNumAchievements_All"] = "AchievementsFrame_GetCategoryNumAchievements_All",
	["AchievementFrame_GetCategoryNumAchievements_Complete"] = "AchievementsFrame_GetCategoryNumAchievements_Complete",
	["AchievementFrame_GetCategoryNumAchievements_Incomplete"] = "AchievementsFrame_GetCategoryNumAchievements_Incomplete",
	["AchievementFrame_GetCategoryTotalNumAchievements"] = "AchievementsFrame_GetCategoryTotalNumAchievements",
	["AchievementFrame_IsComparison"] = "AchievementsFrame_IsComparison",
	["AchievementFrame_IsFeatOfStrength"] = "AchievementsFrame_IsFeatOfStrength",
	["AchievementFrame_LoadTextures"] = "AchievementsFrame_LoadTextures",
	["AchievementFrame_LocalizeCriteria"] = "AchievementsFrame_LocalizeCriteria",
	["AchievementFrame_OnHide"] = "AchievementsFrame_OnHide",
	["AchievementFrame_OnLoad"] = "AchievementsFrame_OnLoad",
	["AchievementFrame_OnShow"] = "AchievementsFrame_OnShow",
	["AchievementFrame_SelectAchievement"] = "AchievementsFrame_SelectAchievement",
	["AchievementFrame_SelectSummaryStatistic"] = "AchievementsFrame_SelectSummaryStatistic",
	["AchievementFrame_SetFilter"] = "AchievementsFrame_SetFilter",
	["AchievementFrame_ShowSubFrame"] = "AchievementsFrame_ShowSubFrame",
	["AchievementFrame_ToggleAchievementFrame"] = "AchievementsFrame_ToggleAchievementFrame",
	["AchievementFrame_UpdateTrackedAchievements"] = "AchievementsFrame_UpdateTrackedAchievements",
	["AchievementHeaderStatusBarTemplate"] = "AchievementsHeaderStatusBarTemplate",
	["AchievementIconFrameTemplate"] = "AchievementsIconFrameTemplate",
	["AchievementIcon_Desaturate"] = "AchievementsIcon_Desaturate",
	["AchievementIcon_OnLoad"] = "AchievementsIcon_OnLoad",
	["AchievementIcon_Saturate"] = "AchievementsIcon_Saturate",
	["AchievementObjectives_DisplayCriteria"] = "AchievementsObjectives_DisplayCriteria",
	["AchievementObjectives_DisplayProgressiveAchievement"] = "AchievementsObjectives_DisplayProgressiveAchievement",
	["AchievementProgressBarTemplate"] = "AchievementsProgressBarTemplate",
	["AchievementShield_Desaturate"] = "AchievementsShield_Desaturate",
	["AchievementShield_OnLoad"] = "AchievementsShield_OnLoad",
	["AchievementShield_Saturate"] = "AchievementsShield_Saturate",
	["AchievementShield_SetPoints"] = "AchievementsShield_SetPoints",
	["AchievementStatButton_OnClick"] = "AchievementsStatButton_OnClick",
	["AchievementStatButton_OnEnter"] = "AchievementsStatButton_OnEnter",
	["AchievementStatButton_OnLoad"] = "AchievementsStatButton_OnLoad",
	["AchievementTemplate"] = "AchievementsAchievementTemplate",
	["AchivementGoldBorderBackdrop"] = "AchievementsGoldBorderBackdrop",
	["COMPARISON_ACHIEVEMENT_FUNCTIONS"] = "ACHIEVEMENTS_COMPARISON_ACHIEVEMENT_FUNCTIONS",
	["COMPARISON_STAT_FUNCTIONS"] = "ACHIEVEMENTS_COMPARISON_STAT_FUNCTIONS",
	["ComparisonPlayerTemplate"] = "AchievementsComparisonPlayerTemplate",
	["ComparisonStatTemplate"] = "AchievementsComparisonStatTemplate",
	["ComparisonTemplate"] = "AchievementsComparisonTemplate",
	["FEAT_OF_STRENGTH_ID"] = "ACHIEVEMENTS_FEAT_OF_STRENGTH_ID",
	["MetaCriteriaTemplate"] = "AchievementsMetaCriteriaTemplate",
	["MiniAchievementTemplate"] = "AchievementsMiniAchievementTemplate",
	["OpenAchievementFrameToAchievement"] = "AchievementsOpenAchievementFrameToAchievement",
	["STAT_FUNCTIONS"] = "ACHIEVEMENTS_STAT_FUNCTIONS",
	["StatTemplate"] = "AchievementsStatTemplate",
	["SummaryAchievementTemplate"] = "AchievementsSummaryAchievementTemplate",
	["SummaryStatTemplate"] = "AchievementsSummaryStatTemplate",
	["achievementFunctions"] = "achievementsFunctions",
};
-- END GENERATED UI GLOBAL NAME MAP

AchievementsForeverCompat = Compat;
