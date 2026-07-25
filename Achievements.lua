local ADDON_NAME = ...;

local characterDBBeforeLoad = type(AchievementsCharacterDB) == "table" and AchievementsCharacterDB or nil;
local characterDBPreviouslyInitialized = characterDBBeforeLoad and characterDBBeforeLoad.addonInitialized == true;
local characterInitialGrantCompleted = characterDBBeforeLoad and characterDBBeforeLoad.initialGrantCompleted;
local suppressFirstLoginAchievementNotifications = not characterDBPreviouslyInitialized or characterInitialGrantCompleted == false;
AchievementsDB = AchievementsDB or {};
AchievementsCharacterDB = AchievementsCharacterDB or {};
AchievementsCharacterDB.addonInitialized = true;
if characterDBPreviouslyInitialized and characterInitialGrantCompleted == nil then
	AchievementsCharacterDB.initialGrantCompleted = true;
elseif suppressFirstLoginAchievementNotifications then
	AchievementsCharacterDB.initialGrantCompleted = false;
end
if not AchievementsCharacterDB.statisticsStartedAt then
	AchievementsCharacterDB.statisticsStartedAt = time();
end

local Achievements = _G.Achievements or {};
_G.Achievements = Achievements;

local Private = Achievements.private or {};
Achievements.private = Private;

local DEBUG = false;
DEBUG = true; -- ACHIEVEMENTS_REMOVE_LINE
Private.DEBUG = DEBUG == true;

local ACHIEVEMENTS_DATA = _G.AchievementsData;
if not ACHIEVEMENTS_DATA then
	error("Achievements: client generated data must load before Achievements.lua");
end

for _, key in ipairs({ "categoryOrder", "statisticsCategoryOrder", "categories", "titles", "achievements", "achievementsByCategory", "achievementsByInstance", "areas", "uiMaps", "worldMapOverlays", "spellNames", "skillLines", "skillLineAbilities", "factions", "items", "emotes", "questSorts", "quests", "questAreaQuests", "questSortQuests", "criteria", "criteriaTrees", "criteriaTreeChildren", "modifierTrees", "modifierTreeChildren", "criteriaByAchievement", "achievementByCriteria", "supercededBy" }) do
	if type(ACHIEVEMENTS_DATA[key]) ~= "table" then
		error("Achievements: generated data is missing table " .. key);
	end
end

local LOCALIZED_DATA_TABLES = {
	achievements = true,
	categories = true,
	titles = true,
	criteriaTrees = true,
	areas = true,
	creatures = true,
	uiMaps = true,
	spellNames = true,
	skillLines = true,
	factions = true,
	items = true,
	questSorts = true,
};

local availableDisplayLocaleByLower = {
	enus = "enUS",
};
if type(ACHIEVEMENTS_DATA.localizations) == "table" then
	for locale, localeData in pairs(ACHIEVEMENTS_DATA.localizations) do
		if type(locale) == "string" and type(localeData) == "table" then
			local lowerLocale = string.lower(locale);
			if lowerLocale ~= "enus" and lowerLocale ~= "auto" then
				availableDisplayLocaleByLower[lowerLocale] = locale;
			end
		end
	end
end

local availableDisplayLocales = {};
for _, locale in pairs(availableDisplayLocaleByLower) do
	availableDisplayLocales[#availableDisplayLocales + 1] = locale;
end
table.sort(availableDisplayLocales);

local function NormalizeDisplayLocale(locale)
	if type(locale) ~= "string" then
		return nil;
	end
	local lowerLocale = string.lower(locale);
	if lowerLocale == "auto" then
		return "auto";
	end
	return availableDisplayLocaleByLower[lowerLocale];
end

local savedDisplayLocale = AchievementsDB.displayLocale;
local selectedDisplayLocale = NormalizeDisplayLocale(savedDisplayLocale) or "auto";
if savedDisplayLocale ~= nil then
	AchievementsDB.displayLocale = selectedDisplayLocale;
end

local requestedDisplayLocale = selectedDisplayLocale == "auto" and GetLocale() or selectedDisplayLocale;
local effectiveDisplayLocale = NormalizeDisplayLocale(requestedDisplayLocale);
if effectiveDisplayLocale == "auto" or not effectiveDisplayLocale then
	effectiveDisplayLocale = "enUS";
end

function Achievements.GetDisplayLocale()
	return selectedDisplayLocale, effectiveDisplayLocale;
end

function Achievements.GetAvailableDisplayLocales()
	local locales = {};
	for index, locale in ipairs(availableDisplayLocales) do
		locales[index] = locale;
	end
	return locales;
end

function Achievements.SetDisplayLocale(locale)
	local normalizedLocale = NormalizeDisplayLocale(locale);
	if not normalizedLocale then
		return nil, false;
	end
	if normalizedLocale == selectedDisplayLocale then
		return normalizedLocale, false;
	end
	AchievementsDB.displayLocale = normalizedLocale;
	selectedDisplayLocale = normalizedLocale;
	return normalizedLocale, true;
end

local function ApplyGeneratedLocalizations()
	local localizations = ACHIEVEMENTS_DATA.localizations;
	if type(localizations) ~= "table" then
		return;
	end

	if effectiveDisplayLocale == "enUS" then
		return;
	end

	local localeData = localizations[effectiveDisplayLocale];
	if type(localeData) ~= "table" then
		return;
	end

	for tableName, records in pairs(localeData) do
		local targetTable = LOCALIZED_DATA_TABLES[tableName] and ACHIEVEMENTS_DATA[tableName];
		if type(targetTable) == "table" and type(records) == "table" then
			for recordID, fields in pairs(records) do
				local targetRecord = targetTable[recordID];
				if type(targetRecord) == "table" and type(fields) == "table" then
					for fieldName, value in pairs(fields) do
						if type(value) == "string" and value ~= "" then
							rawset(targetRecord, fieldName, value);
						end
					end
				end
			end
		end
	end
end

ApplyGeneratedLocalizations();

local DEFAULT_ACHIEVEMENT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark";
local ACHIEVEMENT_EARNED_SOUND_FILE = "Interface\\AddOns\\" .. tostring(ADDON_NAME or "Achievements") .. "\\Media\\AchievementEarned.ogg";
local ACHIEVEMENT_EARNED_SOUND_MIN_INTERVAL = 5;
local STATISTICS_ROOT_CATEGORY_ID = 1;
local STATISTICS_SUMMARY_CATEGORY_ID = -2;
local FEAT_OF_STRENGTH_CATEGORY_ID = 81;
local ACHIEVEMENT_WATCH_MAX_LINES = 30;
local LEGACY_MICRO_BUTTON_SCALE = 0.925;
local LEGACY_MICRO_BUTTON_SPACING = -4;
local ACHIEVEMENT_FACTION_BOTH = -1;
local ACHIEVEMENT_FACTION_HORDE = 0;
local ACHIEVEMENT_FACTION_ALLIANCE = 1;

local ACHIEVEMENT_FLAGS = {
	COUNTER = 0x1,
	HIDDEN = 0x2,
	PLAY_NO_VISUAL = 0x4,
	SUM = 0x8,
	MAX_USED = 0x10,
	REQ_COUNT = 0x20,
	AVERAGE = 0x40,
	PROGRESS_BAR = 0x80,
	REALM_FIRST_REACH = 0x100,
	REALM_FIRST_KILL = 0x200,
	UNK3 = 0x400,
	HIDE_INCOMPLETE = 0x800,
	SHOW_IN_GUILD_NEWS = 0x1000,
	SHOW_IN_GUILD_HEADER = 0x2000,
	GUILD = 0x4000,
	SHOW_GUILD_MEMBERS = 0x8000,
	SHOW_CRITERIA_MEMBERS = 0x10000,
	ACCOUNT_WIDE = 0x20000,
	UNK5 = 0x40000,
	HIDE_ZERO_COUNTER = 0x80000,
	TRACKING_FLAG = 0x100000,
};
Private.ACHIEVEMENT_FLAGS = ACHIEVEMENT_FLAGS;

ACHIEVEMENT_FLAGS_HAS_PROGRESS_BAR = ACHIEVEMENT_FLAGS_HAS_PROGRESS_BAR or ACHIEVEMENT_FLAGS.PROGRESS_BAR;
ACHIEVEMENT_FLAGS_GUILD = ACHIEVEMENT_FLAGS_GUILD or ACHIEVEMENT_FLAGS.GUILD;
ACHIEVEMENT_FLAGS_SHOW_GUILD_MEMBERS = ACHIEVEMENT_FLAGS_SHOW_GUILD_MEMBERS or ACHIEVEMENT_FLAGS.SHOW_GUILD_MEMBERS;
ACHIEVEMENT_FLAGS_SHOW_CRITERIA_MEMBERS = ACHIEVEMENT_FLAGS_SHOW_CRITERIA_MEMBERS or ACHIEVEMENT_FLAGS.SHOW_CRITERIA_MEMBERS;
ACHIEVEMENT_FLAGS_ACCOUNT = ACHIEVEMENT_FLAGS_ACCOUNT or ACHIEVEMENT_FLAGS.ACCOUNT_WIDE;

local CATEGORY_ORDER = ACHIEVEMENTS_DATA.categoryOrder;
local STATISTICS_CATEGORY_ORDER = ACHIEVEMENTS_DATA.statisticsCategoryOrder;
local CATEGORY_DATA = ACHIEVEMENTS_DATA.categories;
local TITLE_DATA = ACHIEVEMENTS_DATA.titles;
local ACHIEVEMENT_DATA = ACHIEVEMENTS_DATA.achievements;
local ACHIEVEMENTS_BY_CATEGORY = ACHIEVEMENTS_DATA.achievementsByCategory;
local ACHIEVEMENTS_BY_INSTANCE = ACHIEVEMENTS_DATA.achievementsByInstance;
local AREA_DATA = ACHIEVEMENTS_DATA.areas;
local UI_MAP_DATA = ACHIEVEMENTS_DATA.uiMaps;
local WORLD_MAP_OVERLAY_DATA = ACHIEVEMENTS_DATA.worldMapOverlays;
local SPELL_NAME_DATA = ACHIEVEMENTS_DATA.spellNames;
local SKILL_LINE_DATA = ACHIEVEMENTS_DATA.skillLines;
local SKILL_LINE_ABILITY_DATA = ACHIEVEMENTS_DATA.skillLineAbilities;
local FACTION_DATA = ACHIEVEMENTS_DATA.factions;
local ITEM_DATA = ACHIEVEMENTS_DATA.items;
local EMOTE_DATA = ACHIEVEMENTS_DATA.emotes;
local QUEST_SORT_DATA = ACHIEVEMENTS_DATA.questSorts;
local QUEST_DATA = ACHIEVEMENTS_DATA.quests;
local QUEST_AREA_QUESTS = ACHIEVEMENTS_DATA.questAreaQuests;
local QUEST_SORT_QUESTS = ACHIEVEMENTS_DATA.questSortQuests;
local CRITERIA_DATA = ACHIEVEMENTS_DATA.criteria;
local CRITERIA_TREE_DATA = ACHIEVEMENTS_DATA.criteriaTrees;
local CRITERIA_TREE_CHILDREN = ACHIEVEMENTS_DATA.criteriaTreeChildren;
local MODIFIER_TREE_DATA = ACHIEVEMENTS_DATA.modifierTrees;
local MODIFIER_TREE_CHILDREN = ACHIEVEMENTS_DATA.modifierTreeChildren;
local CRITERIA_BY_ACHIEVEMENT = ACHIEVEMENTS_DATA.criteriaByAchievement;
local ACHIEVEMENT_BY_CRITERIA = ACHIEVEMENTS_DATA.achievementByCriteria;
local SUPERCEDED_BY = ACHIEVEMENTS_DATA.supercededBy;
local ICON_ASSET_OVERRIDES = _G.AchievementsIconAssets or {};

for achievementID, achievement in pairs(ACHIEVEMENT_DATA) do
	local previousAchievementID = achievement.supercedes or 0;
	if previousAchievementID ~= 0 and ACHIEVEMENT_DATA[previousAchievementID] and not SUPERCEDED_BY[previousAchievementID] then
		SUPERCEDED_BY[previousAchievementID] = achievementID;
	end
end

local function GetTrackedAchievements()
	AchievementsCharacterDB.tracked = AchievementsCharacterDB.tracked or {};
	return AchievementsCharacterDB.tracked;
end

local trackedAchievements = GetTrackedAchievements();
local comparisonUnit;
local achievementUICache = {};

local function InvalidateAchievementUICache()
	achievementUICache = {};
end

Private.DEFAULT_ACHIEVEMENT_ICON = DEFAULT_ACHIEVEMENT_ICON;
Private.ACHIEVEMENT_EARNED_SOUND_FILE = ACHIEVEMENT_EARNED_SOUND_FILE;
Private.ACHIEVEMENT_EARNED_SOUND_MIN_INTERVAL = ACHIEVEMENT_EARNED_SOUND_MIN_INTERVAL;
Private.ACHIEVEMENT_WATCH_MAX_LINES = ACHIEVEMENT_WATCH_MAX_LINES;
Private.LEGACY_MICRO_BUTTON_SCALE = LEGACY_MICRO_BUTTON_SCALE;
Private.LEGACY_MICRO_BUTTON_SPACING = LEGACY_MICRO_BUTTON_SPACING;
Private.dataVersion = ACHIEVEMENTS_DATA.version;
Private.data = {
	version = ACHIEVEMENTS_DATA.version,
	-- Export the UI order tables by reference. Extension addons (e.g.
	-- AchievementsPlus) must mutate the same tables GetCategoryList() returns;
	-- reading them from _G.AchievementsData is not safe because a standalone
	-- AchievementsData addon can replace that global after this addon loaded.
	categoryOrder = CATEGORY_ORDER,
	statisticsCategoryOrder = STATISTICS_CATEGORY_ORDER,
	categories = CATEGORY_DATA,
	titles = TITLE_DATA,
	achievements = ACHIEVEMENT_DATA,
	achievementsByCategory = ACHIEVEMENTS_BY_CATEGORY,
	achievementsByInstance = ACHIEVEMENTS_BY_INSTANCE,
	areas = AREA_DATA,
	uiMaps = UI_MAP_DATA,
	worldMapOverlays = WORLD_MAP_OVERLAY_DATA,
	spellNames = SPELL_NAME_DATA,
	skillLines = SKILL_LINE_DATA,
	skillLineAbilities = SKILL_LINE_ABILITY_DATA,
	factions = FACTION_DATA,
	items = ITEM_DATA,
	emotes = EMOTE_DATA,
	questSorts = QUEST_SORT_DATA,
	quests = QUEST_DATA,
	questAreaQuests = QUEST_AREA_QUESTS,
	questSortQuests = QUEST_SORT_QUESTS,
	criteria = CRITERIA_DATA,
	criteriaTrees = CRITERIA_TREE_DATA,
	criteriaTreeChildren = CRITERIA_TREE_CHILDREN,
	modifierTrees = MODIFIER_TREE_DATA,
	modifierTreeChildren = MODIFIER_TREE_CHILDREN,
	criteriaByAchievement = CRITERIA_BY_ACHIEVEMENT,
	achievementByCriteria = ACHIEVEMENT_BY_CRITERIA,
	supercededBy = SUPERCEDED_BY,
};
Private.state = Private.state or {};
Private.state.trackedAchievements = trackedAchievements;
Private.state.knownPlayerFullNames = Private.state.knownPlayerFullNames or {};
Private.suppressFirstLoginAchievementNotifications = suppressFirstLoginAchievementNotifications;

local function StripPlayerRealmSuffix(name)
	if type(name) ~= "string" or name == "" then
		return nil;
	end
	return name:match("^([^%-]+)") or name;
end

local function PlayerNameIncludesRealm(name)
	return type(name) == "string" and name:find("%-") ~= nil;
end

local function NormalisePlayerName(name, preserveRealm)
	if type(name) ~= "string" or name == "" then
		return nil;
	end
	if preserveRealm then
		local ambiguousName = Ambiguate(name, "none");
		if ambiguousName and ambiguousName ~= "" and PlayerNameIncludesRealm(ambiguousName) then
			return ambiguousName;
		end
		return name;
	end
	local ambiguousName = Ambiguate(name, "short");
	if ambiguousName and ambiguousName ~= "" then
		return StripPlayerRealmSuffix(ambiguousName);
	end
	return StripPlayerRealmSuffix(name);
end

local function GetPlayerNameCacheKey(name)
	if type(name) ~= "string" or name == "" then
		return nil;
	end
	return string.lower(name);
end

local function GetComparisonTargetKey(name)
	if type(name) ~= "string" or name == "" then
		return nil;
	end
	local preserveRealm = PlayerNameIncludesRealm(name);
	local normalised = NormalisePlayerName(name, preserveRealm);
	if not normalised then
		return nil;
	end
	return string.lower(normalised);
end

function Achievements.RememberKnownPlayerName(name)
	local fullName = NormalisePlayerName(name, true);
	if not fullName or not PlayerNameIncludesRealm(fullName) then
		return nil;
	end
	local shortName = NormalisePlayerName(fullName, false);
	if not shortName then
		return nil;
	end
	Private.state.knownPlayerFullNames[shortName] = fullName;
	local cacheKey = GetPlayerNameCacheKey(shortName);
	if cacheKey then
		Private.state.knownPlayerFullNames[cacheKey] = fullName;
	end
	return fullName;
end

function Achievements.GetKnownPlayerFullName(name)
	if type(name) ~= "string" or name == "" then
		return nil, false;
	end
	local shortName = NormalisePlayerName(name, false);
	local cacheKey = GetPlayerNameCacheKey(shortName);
	local knownFullName = shortName and (Private.state.knownPlayerFullNames[shortName] or (cacheKey and Private.state.knownPlayerFullNames[cacheKey]));
	if knownFullName then
		return knownFullName, true;
	end
	if PlayerNameIncludesRealm(name) then
		local fullName = NormalisePlayerName(name, true);
		return fullName, true;
	end
	return shortName or name, false;
end

-- Achievements with the ACCOUNT_WIDE flag are shared between every
-- character on the account; everything else is per-character. The two DBs
-- are persisted independently (account-wide in AchievementsDB.completed,
-- per-character in AchievementsCharacterDB.completed).
local function IsAccountWideAchievement(achievementID)
	local achievement = ACHIEVEMENT_DATA[achievementID];
	if not achievement then
		return false;
	end
	local flags = achievement.flags or 0;
	return bit.band(flags, ACHIEVEMENT_FLAGS.ACCOUNT_WIDE) == ACHIEVEMENT_FLAGS.ACCOUNT_WIDE;
end
Private.IsAccountWideAchievement = IsAccountWideAchievement;

local SAVED_RECORD_INTEGRITY_VERSION = 1;
local SAVED_RECORD_INTEGRITY_SECRET = "AchievementsSavedState:1";

local function NormalizeIntegrityValue(value)
	if value == nil then
		return "nil";
	end
	if value == true then
		return "true";
	end
	if value == false then
		return "false";
	end
	if type(value) == "number" then
		return tostring(value);
	end
	return tostring(value);
end

-- Legacy owner string used by the 1.0.0-1.0.3 seal. It was derived from
-- UnitFullName("player")/GetRealmName(), but those return values are not stable
-- across the login lifecycle (realm comes back normalized vs spaced, and is
-- sometimes unavailable early), so a record sealed mid-session would fail to
-- validate on the next login and progress was wrongly discarded. Kept only so
-- existing sealed records still validate (and then get re-sealed with the new,
-- stable format). New seals no longer include any owner component: per-character
-- data already lives in SavedVariablesPerCharacter, and the seal is only a
-- tamper-evidence marker, not a security boundary.
local function GetLegacySavedRecordOwner(accountWide)
	if accountWide then
		return "account";
	end

	local playerName, realmName;
	playerName, realmName = UnitFullName("player");
	if not playerName or playerName == "" then
		playerName = UnitName("player") or "UnknownPlayer";
	end
	if not realmName or realmName == "" then
		realmName = GetRealmName() or "UnknownRealm";
	end
	return tostring(playerName) .. "-" .. tostring(realmName);
end

local function HashSavedRecordPayload(payload)
	local hash = 5381;
	for index = 1, string.len(payload) do
		hash = math.fmod((hash * 33) + string.byte(payload, index) + index, 4294967291);
	end
	return tostring(math.floor(hash));
end

local function BuildSavedRecordPayload(record, namespace, key, ownerComponent, ...)
	local payload = {
		SAVED_RECORD_INTEGRITY_SECRET,
		tostring(SAVED_RECORD_INTEGRITY_VERSION),
		tostring(namespace or ""),
		tostring(key or ""),
	};
	if ownerComponent ~= nil then
		payload[#payload + 1] = ownerComponent;
	end
	for index = 1, select("#", ...) do
		local fieldName = select(index, ...);
		payload[#payload + 1] = tostring(fieldName) .. "=" .. NormalizeIntegrityValue(record and record[fieldName]);
	end
	return table.concat(payload, "|");
end

local function ComputeSavedRecordIntegrity(record, namespace, key, ...)
	return tostring(SAVED_RECORD_INTEGRITY_VERSION) .. ":" .. HashSavedRecordPayload(BuildSavedRecordPayload(record, namespace, key, nil, ...));
end

local function ComputeLegacySavedRecordIntegrity(record, namespace, key, accountWide, ...)
	return tostring(SAVED_RECORD_INTEGRITY_VERSION) .. ":" .. HashSavedRecordPayload(BuildSavedRecordPayload(record, namespace, key, GetLegacySavedRecordOwner(accountWide), ...));
end

function Private.SealSavedRecord(record, namespace, key, accountWide, ...)
	if type(record) ~= "table" then
		return nil;
	end
	record._integrity = ComputeSavedRecordIntegrity(record, namespace, key, ...);
	return record._integrity;
end

function Private.ValidateSavedRecord(record, namespace, key, accountWide, ...)
	if type(record) ~= "table" then
		return false;
	end
	if record._integrity == ComputeSavedRecordIntegrity(record, namespace, key, ...) then
		return true;
	end
	-- Accept records sealed by the older owner-based format so existing progress
	-- is preserved across the upgrade; callers re-seal with the new format on the
	-- next write.
	return record._integrity == ComputeLegacySavedRecordIntegrity(record, namespace, key, accountWide, ...);
end

function Private.ReportSavedIntegrityFailure(namespace)
	Private.savedIntegrityWarnings = Private.savedIntegrityWarnings or {};
	namespace = tostring(namespace or "saved state");
	if Private.savedIntegrityWarnings[namespace] then
		return;
	end
	Private.savedIntegrityWarnings[namespace] = true;
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cffffd200Achievements:|r ignored modified " .. namespace .. " saved data.");
	end
end

local function NormalizeCompletionTimestamp(timestamp)
	timestamp = tonumber(timestamp);
	if not timestamp or timestamp <= 0 then
		return nil;
	end
	return math.floor(timestamp);
end

local function GetCurrentCompletionTimestamp()
	local timestamp = NormalizeCompletionTimestamp(time());
	if timestamp then
		return timestamp;
	end
	return 1;
end

local function GetSavedCompletionTimestamp(savedState)
	if type(savedState) ~= "table" then
		return nil;
	end
	return NormalizeCompletionTimestamp(savedState.ts);
end

local function GetSavedCompletionDate(savedState)
	local timestamp = GetSavedCompletionTimestamp(savedState);
	if timestamp then
		local currentDate = date("*t", timestamp);
		if currentDate then
			return currentDate.month, currentDate.day, currentDate.year;
		end
	end
	return nil, nil, nil;
end

local function IsSavedCompletionComplete(savedState)
	return GetSavedCompletionTimestamp(savedState) ~= nil;
end

local function SealSavedCompletion(achievementID, savedState)
	if type(savedState) ~= "table" then
		return nil;
	end
	savedState._i = ComputeSavedRecordIntegrity(savedState, "completion", achievementID, "ts");
	return savedState._i;
end

local function WriteSavedCompletion(achievementID, savedState, timestamp)
	timestamp = NormalizeCompletionTimestamp(timestamp);
	if not timestamp then
		return nil;
	end
	savedState.ts = timestamp;
	savedState.completed, savedState.month, savedState.day, savedState.year, savedState._integrity = nil, nil, nil, nil, nil;
	SealSavedCompletion(achievementID, savedState);
	return savedState;
end

local function ValidateSavedCompletion(achievementID, savedState, savedCompletions)
	if type(savedState) ~= "table" then
		return nil;
	end

	local timestamp = NormalizeCompletionTimestamp(savedState.ts);
	if timestamp then
		savedState.ts = timestamp;
		local accountWide = IsAccountWideAchievement(achievementID);
		if savedState._i == ComputeSavedRecordIntegrity(savedState, "completion", achievementID, "ts")
			or savedState._i == ComputeLegacySavedRecordIntegrity(savedState, "completion", achievementID, accountWide, "ts") then
			-- Re-seal legacy/owner-based records with the new stable format.
			savedState._i = ComputeSavedRecordIntegrity(savedState, "completion", achievementID, "ts");
			return savedState;
		end
	end

	if savedCompletions then
		savedCompletions[achievementID] = nil;
	end
	InvalidateAchievementUICache();
	Private.ReportSavedIntegrityFailure("achievement completion");
	return nil;
end

local function GetAccountCompletions()
	AchievementsDB.completed = AchievementsDB.completed or {};
	return AchievementsDB.completed;
end

local function GetCharacterCompletions()
	AchievementsCharacterDB.completed = AchievementsCharacterDB.completed or {};
	return AchievementsCharacterDB.completed;
end

-- Returns the table that owns persisted state for `achievementID`. Unknown ids
-- default to per-character storage.
local function GetSavedCompletions(achievementID)
	local savedCompletions;
	if achievementID and IsAccountWideAchievement(achievementID) then
		savedCompletions = GetAccountCompletions();
	else
		savedCompletions = GetCharacterCompletions();
	end
	if achievementID then
		ValidateSavedCompletion(achievementID, savedCompletions[achievementID], savedCompletions);
	end
	return savedCompletions;
end

local function GetPlayerLevel()
	return UnitLevel("player") or 1;
end

local function PrintMessage(message)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(message);
	end
end

local debugLogFrame;
local debugLogEditBox;
local debugLogScrollFrame;

local function StripChatColorCodes(message)
	message = tostring(message or "");
	message = string.gsub(message, "|c%x%x%x%x%x%x%x%x", "");
	message = string.gsub(message, "|r", "");
	return message;
end

local function GetDebugLogLines()
	Private.debugLogLines = Private.debugLogLines or {};
	return Private.debugLogLines;
end

local function RefreshDebugLogFrame()
	if not debugLogEditBox then
		return;
	end

	local text = table.concat(GetDebugLogLines(), "\n");
	debugLogEditBox:SetText(text);
	if debugLogEditBox.GetStringHeight and debugLogScrollFrame and debugLogScrollFrame.GetHeight then
		debugLogEditBox:SetHeight(math.max(debugLogScrollFrame:GetHeight(), debugLogEditBox:GetStringHeight() + 20));
	end
	debugLogEditBox:SetCursorPosition(string.len(text));
	if debugLogScrollFrame and debugLogScrollFrame.GetVerticalScrollRange then
		debugLogScrollFrame:SetVerticalScroll(debugLogScrollFrame:GetVerticalScrollRange() or 0);
	end
end

local function AppendDebugLogLine(message)
	local timestamp = date("%H:%M:%S") or "--:--:--";
	local line = "[" .. timestamp .. "] " .. StripChatColorCodes(message);
	tinsert(GetDebugLogLines(), line);
	if debugLogFrame and debugLogFrame:IsShown() then
		RefreshDebugLogFrame();
	end
end

local function SelectDebugLogText()
	if not debugLogEditBox then
		return;
	end
	debugLogEditBox:SetFocus();
	debugLogEditBox:HighlightText();
end

local function ClearDebugLog()
	Private.debugLogLines = {};
	RefreshDebugLogFrame();
end

local function CreateDebugLogFrame()
	if debugLogFrame then
		return debugLogFrame;
	end
	if not UIParent then
		return nil;
	end

	local frame = CreateFrame("Frame", "AchievementsDebugLogFrame", UIParent);
	frame:SetWidth(720);
	frame:SetHeight(430);
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
	frame:SetFrameStrata("DIALOG");
	frame:EnableMouse(true);
	frame:SetMovable(true);
	frame:RegisterForDrag("LeftButton");
	frame:SetScript("OnDragStart", frame.StartMoving);
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing);

	local background = frame:CreateTexture(nil, "BACKGROUND");
	background:SetAllPoints(frame);
	if background.SetColorTexture then
		background:SetColorTexture(0, 0, 0, 0.88);
	else
		background:SetTexture(0, 0, 0, 0.88);
	end

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14);
	title:SetText("Achievements Debug Log");

	local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
	closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4);
	closeButton:SetScript("OnClick", function()
		frame:Hide();
	end);

	local selectButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
	selectButton:SetWidth(96);
	selectButton:SetHeight(22);
	selectButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14);
	selectButton:SetText("Select All");
	selectButton:SetScript("OnClick", SelectDebugLogText);

	local clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
	clearButton:SetWidth(70);
	clearButton:SetHeight(22);
	clearButton:SetPoint("LEFT", selectButton, "RIGHT", 8, 0);
	clearButton:SetText("Clear");
	clearButton:SetScript("OnClick", function()
		ClearDebugLog();
		Private.debugMessages = {};
	end);

	local scrollFrame = CreateFrame("ScrollFrame", "AchievementsDebugLogScrollFrame", frame, "UIPanelScrollFrameTemplate");
	scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -44);
	scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 44);

	local editBox = CreateFrame("EditBox", "AchievementsDebugLogEditBox", scrollFrame);
	editBox:SetMultiLine(true);
	editBox:SetAutoFocus(false);
	editBox:EnableMouse(true);
	editBox:SetWidth(660);
	editBox:SetHeight(1);
	if editBox.SetTextInsets then
		editBox:SetTextInsets(4, 4, 4, 4);
	end
	if editBox.SetFontObject then
		editBox:SetFontObject(ChatFontNormal or GameFontHighlightSmall);
	end
	editBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus();
	end);
	scrollFrame:SetScrollChild(editBox);

	debugLogFrame = frame;
	debugLogEditBox = editBox;
	debugLogScrollFrame = scrollFrame;
	frame:Hide();
	return frame;
end

local function ShowDebugLogFrame(selectAll)
	local frame = CreateDebugLogFrame();
	if not frame then
		return false;
	end
	RefreshDebugLogFrame();
	frame:Show();
	if selectAll then
		SelectDebugLogText();
	end
	return true;
end

local function TrimWhitespace(value)
	value = tostring(value or "");
	value = string.gsub(value, "^%s+", "");
	value = string.gsub(value, "%s+$", "");
	return value;
end

local function TrimSlashArg(value)
	value = TrimWhitespace(value);
	return string.lower(value);
end

local function IsDebugBuild()
	return DEBUG == true;
end

local function IsDebugEnabled()
	return IsDebugBuild() and ((Private.debugForceDepth or 0) > 0 or AchievementsDB.debug == true or _G.ACHIEVEMENTS_DEBUG == true);
end

local function DebugMessage(message, onceKey)
	if not IsDebugEnabled() then
		return false;
	end

	if onceKey then
		Private.debugMessages = Private.debugMessages or {};
		if Private.debugMessages[onceKey] then
			return false;
		end
		Private.debugMessages[onceKey] = true;
	end

	AppendDebugLogLine(message);
	PrintMessage("|cffffd200Achievements debug:|r " .. tostring(message));
	return true;
end

local function DebugWarning(onceKey, message)
	return DebugMessage("|cffff8080" .. tostring(message) .. "|r", onceKey);
end

local function WithDebugLogging(callback)
	if type(callback) ~= "function" then
		return nil;
	end
	if not IsDebugBuild() then
		return callback();
	end

	Private.debugForceDepth = (Private.debugForceDepth or 0) + 1;
	local ok, result = pcall(callback);
	Private.debugForceDepth = math.max(0, (Private.debugForceDepth or 1) - 1);
	if not ok then
		error(result);
	end
	return result;
end

-- Prints to every chat frame subscribed to CHAT_MSG_GUILD (e.g. a dedicated
-- Guild tab) using the guild-green colour, AND to DEFAULT_CHAT_FRAME so the
-- message is always visible even when the player is not watching a guild tab.
-- If DEFAULT_CHAT_FRAME is itself subscribed to guild chat it is only printed
-- to once (avoiding a duplicate line).
local function GetGuildChatColor()
	local r, g, b = 0.25, 1.0, 0.25;
	if ChatTypeInfo and ChatTypeInfo["GUILD"] then
		r = ChatTypeInfo["GUILD"].r or r;
		g = ChatTypeInfo["GUILD"].g or g;
		b = ChatTypeInfo["GUILD"].b or b;
	end
	return r, g, b;
end

-- Prints in guild colour to every chat frame subscribed to CHAT_MSG_GUILD.
-- Use for incoming broadcasts from other players (guild tab only).
local function PrintToGuildOnly(message)
	local r, g, b = GetGuildChatColor();
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i];
		if frame and frame.IsEventRegistered and frame:IsEventRegistered("CHAT_MSG_GUILD") then
			frame:AddMessage(message, r, g, b);
		end
	end
end

-- Prints in guild colour to guild-subscribed frames AND in plain white to the
-- default chat frame. Use for the local player's own achievement so it is
-- visible in both the guild tab (green) and general chat (white).
local function PrintToGuildChatFrames(message)
	local r, g, b = GetGuildChatColor();
	local covered = {};
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local frame = _G["ChatFrame" .. i];
		if frame and frame.IsEventRegistered and frame:IsEventRegistered("CHAT_MSG_GUILD") then
			frame:AddMessage(message, r, g, b);
			covered[frame] = true;
		end
	end
	-- Also show in white in the default frame so it is never missed even
	-- when the player is not watching the guild tab.
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(message, 1, 1, 1);
	end
end

local function HasAchievementFlag(achievement, flag)
	local flags = achievement and achievement.flags or 0;
	return bit.band(flags, flag) == flag;
end

local function BitOr(left, right)
	left = left or 0;
	right = right or 0;
	return bit.bor(left, right);
end

local function ShouldPlayAchievementVisual(achievement)
	return achievement ~= nil
		and not HasAchievementFlag(achievement, ACHIEVEMENT_FLAGS.PLAY_NO_VISUAL)
		and not HasAchievementFlag(achievement, ACHIEVEMENT_FLAGS.HIDDEN)
		and not HasAchievementFlag(achievement, ACHIEVEMENT_FLAGS.TRACKING_FLAG);
end

local function IsInternalAchievement(achievement)
	return HasAchievementFlag(achievement, ACHIEVEMENT_FLAGS.HIDDEN)
		or HasAchievementFlag(achievement, ACHIEVEMENT_FLAGS.TRACKING_FLAG);
end

local function DispatchFrameEvent(frame, event, ...)
	if not frame or not frame.GetScript then
		return;
	end

	local eventHandler = frame:GetScript("OnEvent");
	if eventHandler then
		eventHandler(frame, event, ...);
	end
end

local function RefreshAchievementFrameTracking()
	if not AchievementsFrame or type(AchievementsFrame.trackedAchievements) ~= "table" then
		return;
	end

	for achievementID in pairs(AchievementsFrame.trackedAchievements) do
		AchievementsFrame.trackedAchievements[achievementID] = nil;
	end

	if AchievementFrame_UpdateTrackedAchievements then
		AchievementFrame_UpdateTrackedAchievements(Achievements.GetTrackedAchievements());
	else
		for achievementID in pairs(trackedAchievements) do
			AchievementsFrame.trackedAchievements[achievementID] = true;
		end
	end
end

local function NotifyTrackedAchievementsChanged()
	RefreshAchievementFrameTracking();
	DispatchFrameEvent(AchievementsFrameAchievements, "TRACKED_ACHIEVEMENT_LIST_CHANGED");

	if AchievementsFrameAchievements and AchievementsFrameAchievements:IsVisible() and AchievementsFrameAchievements_ForceUpdate then
		AchievementsFrameAchievements_ForceUpdate();
	end

	if Achievements.WatchFrame_Update then
		Achievements.WatchFrame_Update();
	end
end

local function EnsureAchievementUIForNotification()
	if AchievementsFrame and AchievementShield_SetPoints then
		return;
	end

	if Achievements.AchievementFrame_LoadUI then
		Achievements.AchievementFrame_LoadUI();
	end
end

local function QueueAchievementAlert(achievementID)
	EnsureAchievementUIForNotification();

	if AchievementAlertSystem and AchievementAlertSystem.AddAlert then
		AchievementAlertSystem:AddAlert(achievementID);
		return;
	end

	DispatchFrameEvent(AlertFrame, "ACHIEVEMENT_EARNED", achievementID);
end

local lastAchievementEarnedSoundTime = -ACHIEVEMENT_EARNED_SOUND_MIN_INTERVAL;

local function PlayAchievementEarnedSound()
	local currentTime = GetTime();
	if currentTime - lastAchievementEarnedSoundTime < ACHIEVEMENT_EARNED_SOUND_MIN_INTERVAL then
		return;
	end

	local willPlay = PlaySoundFile(ACHIEVEMENT_EARNED_SOUND_FILE, "SFX");
	if willPlay ~= false then
		lastAchievementEarnedSoundTime = currentTime;
	end
end

local function NotifyAchievementEarned(achievementID, showAlert)
	local achievement = ACHIEVEMENT_DATA[achievementID];
	if Achievements.ensureAchievementMicroButton then
		Achievements.ensureAchievementMicroButton();
	end

	if showAlert and ShouldPlayAchievementVisual(achievement) then
		PlayAchievementEarnedSound();
		QueueAchievementAlert(achievementID);
	end

	DispatchFrameEvent(AchievementsFrameAchievements, "ACHIEVEMENT_EARNED", achievementID);
	DispatchFrameEvent(AchievementsFrameStats, "CRITERIA_UPDATE");
	DispatchFrameEvent(AchievementsFrameComparison, "ACHIEVEMENT_EARNED", achievementID);

	-- Only refresh the summary frame on user-visible completions. Silent state-sync
	-- (e.g. GetAchievementState lazily marking previously-earned achievements) must
	-- never trigger a summary update because the summary itself iterates achievements
	-- via GetAchievementState and would re-enter this function recursively.
	if showAlert and AchievementsFrameSummary and AchievementsFrameSummary:IsShown() and AchievementsFrameSummary_Update then
		AchievementsFrameSummary_Update();
	end
end

local BuildAchievementLink;

local function BuildAchievementLinkForPlayer(achievementID, playerName, completionTimestamp, guid)
	local achievement = ACHIEVEMENT_DATA[achievementID];
	if not achievement then
		return nil;
	end
	local timestamp = NormalizeCompletionTimestamp(completionTimestamp) or 0;
	local ownerSuffix = playerName and playerName ~= "" and (":" .. tostring(playerName)) or "";
	return string.format("|cffffff00|Hachievement:%d:%s:%d%s|h[%s]|h|r", achievementID, tostring(guid or ""), timestamp, ownerSuffix, achievement.name);
end

local function GetClassColorHex(classFile)
	if not classFile then
		return nil;
	end
	local color = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFile]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]);
	if not color then
		return nil;
	end
	if color.colorStr then
		return color.colorStr;
	end
	return string.format("ff%02x%02x%02x", math.floor((color.r or 1) * 255), math.floor((color.g or 1) * 255), math.floor((color.b or 1) * 255));
end

local function BuildPlayerChatLink(playerName, classFile)
	if not playerName then
		return "";
	end
	local hex = GetClassColorHex(classFile);
	if hex then
		return string.format("|c%s|Hplayer:%s|h[%s]|h|r", hex, playerName, playerName);
	end
	return string.format("|Hplayer:%s|h[%s]|h", playerName, playerName);
end

-- Builds the localized "<player> has earned the achievement <link>!" string.
-- Used both for the local player's chat broadcast and for incoming guild
-- addon broadcasts so that all clients render consistently.
local function FormatAchievementBroadcast(playerName, classFile, achievementID, completionTimestamp, guid)
	local achievement = ACHIEVEMENT_DATA[achievementID];
	local link = (completionTimestamp ~= nil and BuildAchievementLinkForPlayer(achievementID, playerName, completionTimestamp, guid))
		or BuildAchievementLink(achievementID)
		or (achievement and ("[" .. achievement.name .. "]"))
		or ("[" .. tostring(achievementID) .. "]");
	local playerLink = BuildPlayerChatLink(playerName, classFile);
	local msg;
	if type(PLAYER_BROADCAST_ACHIEVEMENT) == "string" then
		-- "|Hplayer:%s|h[%s]|h has earned the achievement $a!"
		-- We replace the entire bare player link with our class-colored one
		-- after substitution so the player name appears in their class color.
		msg = string.format(PLAYER_BROADCAST_ACHIEVEMENT, playerName, playerName);
		msg = msg:gsub("|Hplayer:" .. playerName .. "|h%[" .. playerName .. "%]|h", playerLink);
	elseif type(BROADCAST_ACHIEVEMENT) == "string" then
		-- "%s has earned the achievement $a!"
		msg = string.format(BROADCAST_ACHIEVEMENT, playerLink);
	else
		msg = string.format("%s has earned the achievement %s!", playerLink, link);
	end
	msg = msg:gsub("%$a", function() return link; end);
	return msg;
end

-- ---------------------------------------------------------------------------
-- Own-achievement broadcast queue.
--
-- When an achievement is earned in the first few seconds after login the
-- player is typically not yet joined to the guild chat channel. The SAY/local
-- print is immediate; only the guild leg queues until the guild chat channel
-- is observed to be ready.

local guildAnnouncementsReady = false;
local pendingGuildAnnouncements = {};
local FIRST_LOGIN_INITIAL_GRANT_SETTLE_SECONDS = 10;

local function EmitOwnAchievementSayNow(achievementID)
	-- All sending and local-chat printing is owned by AchievementsGuildBroadcast.lua.
	if Achievements.AnnounceAchievementToSay then
		Achievements.AnnounceAchievementToSay(achievementID);
		return true;
	end
	if Achievements.AnnounceAchievement then
		Achievements.AnnounceAchievement(achievementID);
	end
	return false;
end

local function EmitOwnAchievementGuildNow(achievementID)
	if Achievements.AnnounceAchievementToGuild then
		Achievements.AnnounceAchievementToGuild(achievementID);
	end
end

function Achievements.QueueOrEmitOwnAchievementBroadcast(achievementID)
	if not EmitOwnAchievementSayNow(achievementID) then
		return;
	end
	if guildAnnouncementsReady then
		EmitOwnAchievementGuildNow(achievementID);
		return;
	end
	tinsert(pendingGuildAnnouncements, achievementID);
end

function Achievements.MarkGuildAnnouncementsReady()
	if guildAnnouncementsReady then
		return;
	end
	guildAnnouncementsReady = true;
	while #pendingGuildAnnouncements > 0 do
		local id = tremove(pendingGuildAnnouncements, 1);
		EmitOwnAchievementGuildNow(id);
	end
end

local function IsSilentBackfillActive()
	return (Private.silentBackfillDepth or 0) > 0;
end

local function FinishFirstLoginInitialGrant()
	if IsSilentBackfillActive() then
		return false;
	end
	Private.suppressFirstLoginAchievementNotifications = false;
	AchievementsCharacterDB.initialGrantCompleted = true;
	return true;
end

local function IsFirstLoginInitialGrantActive()
	return Private.suppressFirstLoginAchievementNotifications == true;
end

local function ShouldSuppressAchievementEarnedNotification()
	return IsFirstLoginInitialGrantActive();
end

function Achievements.BeginSilentBackfill()
	Private.silentBackfillDepth = (Private.silentBackfillDepth or 0) + 1;
end

function Achievements.ScheduleEndFirstLoginInitialGrant(delaySeconds)
	if Private.suppressFirstLoginAchievementNotifications ~= true then
		return;
	end
	local delay = tonumber(delaySeconds) or FIRST_LOGIN_INITIAL_GRANT_SETTLE_SECONDS;
	Private.firstLoginInitialGrantToken = (Private.firstLoginInitialGrantToken or 0) + 1;
	local token = Private.firstLoginInitialGrantToken;
	C_Timer.After(delay, function()
		if Private.firstLoginInitialGrantToken ~= token then
			return;
		end
		if not FinishFirstLoginInitialGrant() then
			Achievements.ScheduleEndFirstLoginInitialGrant(delay);
		end
	end);
end

function Achievements.EndSilentBackfill()
	Private.silentBackfillDepth = math.max(0, (Private.silentBackfillDepth or 0) - 1);
	if Private.silentBackfillDepth == 0 and Private.suppressFirstLoginAchievementNotifications == true then
		Achievements.ScheduleEndFirstLoginInitialGrant();
	end
end

local function MarkAchievementComplete(achievementID, showAlert)
	local achievement = ACHIEVEMENT_DATA[achievementID];
	if not achievement then
		return false;
	end
	if achievementID == 15332 or achievementID == 16437 then
		return false;
	end
	local suppressEarnedNotification = ShouldSuppressAchievementEarnedNotification();

	local savedCompletions = GetSavedCompletions(achievementID);
	local savedState = savedCompletions[achievementID];
	local wasAlreadyCompleted = IsSavedCompletionComplete(savedState);

	if not wasAlreadyCompleted then
		savedState = savedState or {};
		WriteSavedCompletion(achievementID, savedState, GetCurrentCompletionTimestamp());
		savedCompletions[achievementID] = savedState;
		InvalidateAchievementUICache();
		if trackedAchievements[achievementID] then
			trackedAchievements[achievementID] = nil;
			NotifyTrackedAchievementsChanged();
		end
	end

	-- Announce on the first visible transition into "completed". The first
	-- login backfill for a character saves initial state without firing
	-- earned-frame events, toasts, guild prints, or rebroadcasts. After that,
	-- every newly earned user-visible achievement should behave like a real
	-- earned achievement even if it was found by a background sweep.
	-- wasAlreadyCompleted is persisted to SavedVariables so it is the sole
	-- idempotency gate; the separate "announced" flag is not needed and only
	-- silently blocked retries when the first attempt failed.
	local playEarnedVisual = not suppressEarnedNotification and ShouldPlayAchievementVisual(achievement);
	if not wasAlreadyCompleted and suppressEarnedNotification and Achievements.ScheduleEndFirstLoginInitialGrant then
		Achievements.ScheduleEndFirstLoginInitialGrant();
	end

	if not wasAlreadyCompleted and playEarnedVisual then
		Achievements.QueueOrEmitOwnAchievementBroadcast(achievementID);
	end

	if not wasAlreadyCompleted and not suppressEarnedNotification then
		NotifyAchievementEarned(achievementID, playEarnedVisual);
	end

	return not wasAlreadyCompleted;
end

local GetAchievementState;
GetAchievementState = function(achievementID)
	local savedState = GetSavedCompletions(achievementID)[achievementID];
	if IsSavedCompletionComplete(savedState) then
		local month, day, year = GetSavedCompletionDate(savedState);
		return true, month, day, year, 1, 1;
	end

	if Achievements.EvaluateAchievementCriteriaState then
		local completed, month, day, year, quantity, requiredQuantity = Achievements.EvaluateAchievementCriteriaState(achievementID);
		if completed then
			MarkAchievementComplete(achievementID, false);
			savedState = GetSavedCompletions(achievementID)[achievementID];
			local savedMonth, savedDay, savedYear = GetSavedCompletionDate(savedState);
			return true, savedMonth, savedDay, savedYear, quantity, requiredQuantity;
		elseif completed ~= nil then
			return completed, month, day, year, quantity, requiredQuantity;
		end
	end

	return false, nil, nil, nil, 0, 1;
end

local function IsAchievementCompleted(achievementID)
	return GetAchievementState(achievementID) == true;
end

local function GetPlayerAchievementFaction()
	local factionGroup = UnitFactionGroup("player");
	if factionGroup == "Horde" then
		return ACHIEVEMENT_FACTION_HORDE;
	elseif factionGroup == "Alliance" then
		return ACHIEVEMENT_FACTION_ALLIANCE;
	end

	return ACHIEVEMENT_FACTION_BOTH;
end

local function IsAchievementForPlayerFaction(achievement)
	if not achievement then
		return false;
	end

	local faction = achievement.faction or ACHIEVEMENT_FACTION_BOTH;
	return faction == ACHIEVEMENT_FACTION_BOTH or faction == GetPlayerAchievementFaction();
end

local function GetPreviousAchievementID(achievementID)
	local achievement = ACHIEVEMENT_DATA[achievementID];
	local previousAchievementID = achievement and achievement.supercedes or 0;
	if previousAchievementID ~= 0 and ACHIEVEMENT_DATA[previousAchievementID] and IsAchievementForPlayerFaction(ACHIEVEMENT_DATA[previousAchievementID]) then
		return previousAchievementID;
	end

	return nil;
end

local function GetNextAchievementID(achievementID)
	local nextAchievementID = SUPERCEDED_BY[achievementID];
	if nextAchievementID and ACHIEVEMENT_DATA[nextAchievementID] and IsAchievementForPlayerFaction(ACHIEVEMENT_DATA[nextAchievementID]) then
		return nextAchievementID;
	end

	return nil;
end

local function ShouldDisplaySupercedeStage(achievementID)
	local achievement = ACHIEVEMENT_DATA[achievementID];
	if not achievement then
		return false;
	end

	local previousAchievementID = GetPreviousAchievementID(achievementID);
	local nextAchievementID = GetNextAchievementID(achievementID);
	local isCompleted = IsAchievementCompleted(achievementID);

	if isCompleted then
		-- Show as the latest-completed stage only when the next stage isn't completed yet (or doesn't exist).
		return not nextAchievementID or not IsAchievementCompleted(nextAchievementID);
	end

	-- Show as the next-available stage only when the previous stage is completed (or there is no previous stage).
	return not previousAchievementID or IsAchievementCompleted(previousAchievementID);
end

local function IsCategoryDescendantOf(categoryID, ancestorID)
	local currentCategoryID = categoryID;
	local seenCategories = {};
	while CATEGORY_DATA[currentCategoryID] and not seenCategories[currentCategoryID] do
		if currentCategoryID == ancestorID then
			return true;
		end

		seenCategories[currentCategoryID] = true;
		local parentID = CATEGORY_DATA[currentCategoryID].parent;
		if parentID == -1 then
			return false;
		end

		currentCategoryID = parentID;
	end

	return false;
end

local function IsStatisticAchievement(achievement)
	return achievement and (HasAchievementFlag(achievement, ACHIEVEMENT_FLAGS.COUNTER) or IsCategoryDescendantOf(achievement.category, STATISTICS_ROOT_CATEGORY_ID));
end

local function IsFeatOfStrengthAchievement(achievement)
	return achievement and IsCategoryDescendantOf(achievement.category, FEAT_OF_STRENGTH_CATEGORY_ID);
end

local function ShouldShowAchievementInUI(achievementID)
	local achievement = ACHIEVEMENT_DATA[achievementID];
	if not achievement then
		return false;
	end

	if IsInternalAchievement(achievement) then
		return false;
	end

	if not IsAchievementForPlayerFaction(achievement) or not ShouldDisplaySupercedeStage(achievementID) then
		return false;
	end

	if IsAchievementCompleted(achievementID) then
		return true;
	end

	if IsFeatOfStrengthAchievement(achievement) then
		return false;
	end

	return not HasAchievementFlag(achievement, ACHIEVEMENT_FLAGS.HIDE_INCOMPLETE);
end

local function ResolveAchievementIcon(achievement)
	local icon = achievement and achievement.icon;
	if type(icon) == "string" and icon ~= "" then
		return ICON_ASSET_OVERRIDES[icon] or icon;
	end
	return DEFAULT_ACHIEVEMENT_ICON;
end

local function IsCountableAchievement(achievementID, achievement, includeFeatOfStrength)
	achievement = achievement or ACHIEVEMENT_DATA[achievementID];
	if not achievement then
		return false;
	end
	if not IsAchievementForPlayerFaction(achievement) then
		return false;
	end
	if IsInternalAchievement(achievement) then
		return false;
	end
	if IsStatisticAchievement(achievement) then
		return false;
	end
	if not includeFeatOfStrength and IsFeatOfStrengthAchievement(achievement) then
		return false;
	end
	-- Count every stage of a superceded chain individually so progress totals
	-- reflect the real number of achievements rather than collapsing chains.
	if IsAchievementCompleted(achievementID) then
		return true;
	end
	return not HasAchievementFlag(achievement, ACHIEVEMENT_FLAGS.HIDE_INCOMPLETE);
end

local function CountDisplayAchievements()
	if achievementUICache.displayCount then
		return achievementUICache.displayCount.total, achievementUICache.displayCount.completed;
	end

	local totalCount = 0;
	local completedCount = 0;
	for achievementID, achievement in pairs(ACHIEVEMENT_DATA) do
		if IsCountableAchievement(achievementID, achievement) then
			totalCount = totalCount + 1;
			if IsAchievementCompleted(achievementID) then
				completedCount = completedCount + 1;
			end
		end
	end

	achievementUICache.displayCount = { total = totalCount, completed = completedCount };
	return totalCount, completedCount;
end

local function BuildVisibleAchievementList(categoryID)
	achievementUICache.visibleLists = achievementUICache.visibleLists or {};
	local cached = achievementUICache.visibleLists[categoryID];
	if cached then
		return cached.ids, cached.completed;
	end

	local completedIDs = {};
	local incompleteIDs = {};
	for _, achievementID in ipairs(ACHIEVEMENTS_BY_CATEGORY[categoryID] or {}) do
		if ShouldShowAchievementInUI(achievementID) then
			if IsAchievementCompleted(achievementID) then
				tinsert(completedIDs, achievementID);
			else
				tinsert(incompleteIDs, achievementID);
			end
		end
	end

	local ids = {};
	for _, achievementID in ipairs(completedIDs) do
		tinsert(ids, achievementID);
	end
	for _, achievementID in ipairs(incompleteIDs) do
		tinsert(ids, achievementID);
	end

	cached = { ids = ids, completed = #completedIDs };
	achievementUICache.visibleLists[categoryID] = cached;
	return cached.ids, cached.completed;
end

local function CountCategoryVisibleAchievements(categoryID)
	local ids, completedCount = BuildVisibleAchievementList(categoryID);
	return #ids, completedCount;
end

local function CountCategoryAllAchievements(categoryID)
	achievementUICache.categoryAllCounts = achievementUICache.categoryAllCounts or {};
	local cached = achievementUICache.categoryAllCounts[categoryID];
	if cached then
		return cached.total, cached.completed;
	end

	local totalCount = 0;
	local completedCount = 0;
	for _, achievementID in ipairs(ACHIEVEMENTS_BY_CATEGORY[categoryID] or {}) do
		local achievement = ACHIEVEMENT_DATA[achievementID];
		if IsCountableAchievement(achievementID, achievement) then
			totalCount = totalCount + 1;
			if IsAchievementCompleted(achievementID) then
				completedCount = completedCount + 1;
			end
		end
	end

	cached = { total = totalCount, completed = completedCount };
	achievementUICache.categoryAllCounts[categoryID] = cached;
	return totalCount, completedCount;
end

local function IsDisplayableStatistic(achievementID, achievement)
	return IsStatisticAchievement(achievement) and IsAchievementForPlayerFaction(achievement) and ShouldShowAchievementInUI(achievementID);
end

local function BuildAllStatisticsList()
	achievementUICache.allStatisticsList = achievementUICache.allStatisticsList or {};
	local cached = achievementUICache.allStatisticsList;
	if cached.ids then
		return cached.ids;
	end

	local ids = {};
	local seen = {};
	for _, categoryID in ipairs(STATISTICS_CATEGORY_ORDER) do
		for _, achievementID in ipairs(ACHIEVEMENTS_BY_CATEGORY[categoryID] or {}) do
			local achievement = ACHIEVEMENT_DATA[achievementID];
			if not seen[achievementID] and IsDisplayableStatistic(achievementID, achievement) then
				seen[achievementID] = true;
				tinsert(ids, achievementID);
			end
		end
	end

	local fallbackIDs = {};
	for achievementID, achievement in pairs(ACHIEVEMENT_DATA) do
		if not seen[achievementID] and IsDisplayableStatistic(achievementID, achievement) then
			tinsert(fallbackIDs, achievementID);
		end
	end
	table.sort(fallbackIDs, function(leftID, rightID)
		local left = ACHIEVEMENT_DATA[leftID];
		local right = ACHIEVEMENT_DATA[rightID];
		local leftCategory = left and left.category or 0;
		local rightCategory = right and right.category or 0;
		if leftCategory ~= rightCategory then
			return leftCategory < rightCategory;
		end
		local leftSort = left and left.sort or leftID;
		local rightSort = right and right.sort or rightID;
		if leftSort ~= rightSort then
			return leftSort < rightSort;
		end
		return leftID < rightID;
	end);
	for _, achievementID in ipairs(fallbackIDs) do
		tinsert(ids, achievementID);
	end

	cached.ids = ids;
	return ids;
end

local function CountAllStatistics()
	return #BuildAllStatisticsList(), 0;
end

local function GetCompletedAchievementPoints()
	local points = 0;
	for achievementID, achievement in pairs(ACHIEVEMENT_DATA) do
		if not IsInternalAchievement(achievement) and not IsStatisticAchievement(achievement) and not IsFeatOfStrengthAchievement(achievement) and IsAchievementCompleted(achievementID) then
			points = points + (achievement.points or 0);
		end
	end

	return points;
end

local function ResolveAchievementID(categoryOrAchievementID, index, includeHidden)
	if index then
		if categoryOrAchievementID == STATISTICS_SUMMARY_CATEGORY_ID then
			return BuildAllStatisticsList()[index];
		end

		if not includeHidden then
			local ids = BuildVisibleAchievementList(categoryOrAchievementID);
			return ids[index];
		end

		local visibleIndex = 0;
		for _, achievementID in ipairs(ACHIEVEMENTS_BY_CATEGORY[categoryOrAchievementID] or {}) do
			if includeHidden or ShouldShowAchievementInUI(achievementID) then
				visibleIndex = visibleIndex + 1;
				if visibleIndex == index then
					return achievementID;
				end
			end
		end

		return nil;
	end

	return categoryOrAchievementID;
end

local function BuildAchievementLinkImpl(achievementID)
	local achievement = ACHIEVEMENT_DATA[achievementID];
	if not achievement then
		return nil;
	end

	local completed = GetAchievementState(achievementID) == true;
	local savedState = completed and GetSavedCompletions(achievementID)[achievementID] or nil;
	local timestamp = completed and (GetSavedCompletionTimestamp(savedState) or 1) or 0;
	return string.format("|cffffff00|Hachievement:%d:%s:%d|h[%s]|h|r", achievementID, UnitGUID("player") or "Player-0-00000000", timestamp, achievement.name);
end
BuildAchievementLink = BuildAchievementLinkImpl;

function Achievements.CanShowAchievementUI()
	return true;
end

function Achievements.HasCompletedAnyAchievement()
	local _, completedCount = CountDisplayAchievements();
	return completedCount > 0;
end

function Achievements.GetCategoryList()
	return CATEGORY_ORDER;
end

function Achievements.GetStatisticsCategoryList()
	return STATISTICS_CATEGORY_ORDER;
end

function Achievements.GetGuildCategoryList()
	return {};
end

function Achievements.GetCategoryInfo(categoryID)
	local category = CATEGORY_DATA[categoryID];
	if not category then
		return nil, -1, 0;
	end

	return category.name, category.parent, 0;
end

function Achievements.GetCategoryNumAchievements(categoryID, includeAllStages)
	-- Summary IDs (-1 = achievements, -2 = stats) have no real category row;
	-- return the overall totals so comparison status bars display correctly.
	if categoryID == -1 then
		return CountDisplayAchievements();
	end
	if categoryID == STATISTICS_SUMMARY_CATEGORY_ID then
		return CountAllStatistics();
	end
	if includeAllStages then
		return CountCategoryAllAchievements(categoryID);
	end
	return CountCategoryVisibleAchievements(categoryID);
end

function Achievements.GetNumCompletedAchievements()
	return CountDisplayAchievements();
end

function Achievements.GetTotalAchievementPoints()
	return GetCompletedAchievementPoints();
end

function Achievements.GetAchievementInfo(categoryOrAchievementID, index)
	local achievementID = ResolveAchievementID(categoryOrAchievementID, index);
	local achievement = ACHIEVEMENT_DATA[achievementID];
	if not achievement then
		return nil;
	end

	local completed, month, day, year = GetAchievementState(achievementID);
	local icon = ResolveAchievementIcon(achievement);

	return achievement.id, achievement.name, achievement.points or 0, completed, month, day, year, achievement.description or "", achievement.flags or 0, icon, achievement.reward or "";
end

function Achievements.GetAchievementCategory(achievementID)
	local achievement = ACHIEVEMENT_DATA[achievementID];
	return achievement and achievement.category;
end

function Achievements.GetAchievementInstance(achievementID)
	local achievement = ACHIEVEMENT_DATA[achievementID];
	return achievement and achievement.instance;
end

function Achievements.GetAchievementsByInstance(instanceID)
	local achievementIDs = {};
	for _, achievementID in ipairs(ACHIEVEMENTS_BY_INSTANCE[instanceID] or {}) do
		if ShouldShowAchievementInUI(achievementID) then
			tinsert(achievementIDs, achievementID);
		end
	end

	return unpack(achievementIDs);
end

function Achievements.GetPreviousAchievement(achievementID)
	return GetPreviousAchievementID(achievementID);
end

function Achievements.GetNextAchievement(achievementID)
	local nextAchievementID = GetNextAchievementID(achievementID);
	if not nextAchievementID then
		return nil;
	end

	local completed, month, day, year = GetAchievementState(nextAchievementID);
	return nextAchievementID, completed, month, day, year;
end

function Achievements.GetLatestCompletedAchievements()
	local completedAchievements = {};
	for achievementID, achievement in pairs(ACHIEVEMENT_DATA) do
		local savedState = GetSavedCompletions(achievementID)[achievementID];
		local timestamp = GetSavedCompletionTimestamp(savedState);
		if timestamp and not IsStatisticAchievement(achievement) and ShouldShowAchievementInUI(achievementID) then
			table.insert(completedAchievements, { id = achievementID, ts = timestamp });
		end
	end

	table.sort(completedAchievements, function(left, right)
		if left.ts ~= right.ts then
			return left.ts > right.ts;
		end
		return left.id < right.id;
	end);

	local completedAchievementIDs = {};
	for index, entry in ipairs(completedAchievements) do
		completedAchievementIDs[index] = entry.id;
	end
	return unpack(completedAchievementIDs);
end

function Achievements.GetLatestUpdatedStats()
	return unpack(BuildAllStatisticsList());
end

-- Returns a curated list of incomplete achievement IDs to suggest in the
-- Recent Achievements summary when the player hasn't earned enough to fill
-- the panel. Excludes Statistics, Feats of Strength, hidden, and faction-
-- mismatched entries. Sorted by points (lowest first) so simple intro
-- achievements appear before harder ones.
function Achievements.GetSuggestedAchievements()
	local candidates = {};
	for achievementID, achievement in pairs(ACHIEVEMENT_DATA) do
		if not IsStatisticAchievement(achievement)
			and not IsFeatOfStrengthAchievement(achievement)
			and IsAchievementForPlayerFaction(achievement)
			and not HasAchievementFlag(achievement, ACHIEVEMENT_FLAGS.HIDE_INCOMPLETE)
			and not IsAchievementCompleted(achievementID)
			and ShouldShowAchievementInUI(achievementID) then
			tinsert(candidates, achievementID);
		end
	end

	table.sort(candidates, function(a, b)
		local pa = (ACHIEVEMENT_DATA[a].points or 0);
		local pb = (ACHIEVEMENT_DATA[b].points or 0);
		if pa ~= pb then
			return pa < pb;
		end
		return a < b;
	end);

	return candidates;
end

function Achievements.GetLatestCompletedComparisonAchievements()
end

function Achievements.GetStatistic(categoryOrStatisticID, index)
	local statisticID = ResolveAchievementID(categoryOrStatisticID, index);
	local statistic = ACHIEVEMENT_DATA[statisticID];
	if not statistic or not IsDisplayableStatistic(statisticID, statistic) then
		return nil, true, nil;
	end

	local quantity = Achievements.GetStatisticQuantityString and Achievements.GetStatisticQuantityString(statisticID) or nil;
	return quantity or "--", false, statisticID;
end

function Achievements.GetAchievementLink(achievementID)
	return BuildAchievementLink(achievementID);
end

function Achievements.GetTrackedAchievements()
	local trackedList = {};
	for achievementID in pairs(trackedAchievements) do
		if ShouldShowAchievementInUI(achievementID) and not IsAchievementCompleted(achievementID) then
			tinsert(trackedList, achievementID);
		else
			trackedAchievements[achievementID] = nil;
		end
	end

	return unpack(trackedList);
end

function Achievements.GetNumTrackedAchievements()
	local trackedCount = 0;
	for achievementID in pairs(trackedAchievements) do
		if ShouldShowAchievementInUI(achievementID) and not IsAchievementCompleted(achievementID) then
			trackedCount = trackedCount + 1;
		else
			trackedAchievements[achievementID] = nil;
		end
	end

	return trackedCount;
end

function Achievements.AddTrackedAchievement(achievementID)
	if ACHIEVEMENT_DATA[achievementID] and ShouldShowAchievementInUI(achievementID) and not IsAchievementCompleted(achievementID) and not trackedAchievements[achievementID] then
		trackedAchievements[achievementID] = true;
		if AchievementsFrame and AchievementsFrame.trackedAchievements then
			AchievementsFrame.trackedAchievements[achievementID] = true;
		end
		NotifyTrackedAchievementsChanged();
	end
end

function Achievements.RemoveTrackedAchievement(achievementID)
	if trackedAchievements[achievementID] then
		trackedAchievements[achievementID] = nil;
		if AchievementsFrame and AchievementsFrame.trackedAchievements then
			AchievementsFrame.trackedAchievements[achievementID] = nil;
		end
		NotifyTrackedAchievementsChanged();
	end
end

function Achievements.IsTrackedAchievement(achievementID)
	return trackedAchievements[achievementID] == true and ShouldShowAchievementInUI(achievementID) and not IsAchievementCompleted(achievementID);
end

function Achievements.SetAchievementComparisonUnit(unit)
	comparisonUnit = unit;
end

function Achievements.ClearAchievementComparisonUnit()
	comparisonUnit = nil;
	Achievements.comparisonState = nil;
end

function Achievements.GetComparisonAchievementPoints()
	local state = Achievements.comparisonState;
	return (state and state.points) or 0;
end

function Achievements.GetAchievementComparisonInfo(achievementID)
	local state = Achievements.comparisonState;
	if not state or not state.completed then
		return false, nil, nil, nil;
	end
	local entry = state.completed[achievementID];
	if not entry then
		return false, nil, nil, nil;
	end
	local month, day, year = GetSavedCompletionDate(entry);
	return true, month or 0, day or 0, year or 0;
end

function Achievements.GetComparisonCategoryNumAchievements(categoryID)
	local state = Achievements.comparisonState;
	if not state or not state.completed then
		return 0, 0;
	end
	local achievementsByCategory = Private.data and Private.data.achievementsByCategory;
	local list = achievementsByCategory and achievementsByCategory[categoryID];
	if not list then
		-- Summary or unknown category: count everything they have.
		local count = 0;
		for _ in pairs(state.completed) do
			count = count + 1;
		end
		return count, 0;
	end
	local completed = 0;
	for _, achievement in ipairs(list) do
		local id = type(achievement) == "table" and achievement.id or achievement;
		if id and state.completed[id] then
			completed = completed + 1;
		end
	end
	return completed, 0;
end

-- Opens the Blizzard AchievementsFrame in comparison mode for the given player.
-- Call immediately when a comparison is requested — shows the frame with
-- whatever data is available now. Call RefreshComparisonData when the real
-- data arrives to update in place without resetting the selected category.
function Achievements.OpenComparisonForName(targetName, points, completed, unit, statistics)
	local displayName = StripPlayerRealmSuffix(targetName) or targetName;
	Achievements.comparisonState = {
		name = displayName,
		targetKey = GetComparisonTargetKey(targetName),
		points = tonumber(points) or 0,
		completed = completed or {},
		statistics = statistics or {},
		unit = unit,
	};
	if Achievements.invalidateAchievementStatsUICache then
		Achievements.invalidateAchievementStatsUICache();
	end

	if not AchievementsFrame then
		if Achievements.AchievementFrame_LoadUI then
			Achievements.AchievementFrame_LoadUI();
		elseif AchievementFrame_LoadUI then
			AchievementFrame_LoadUI();
		end
	end
	if not AchievementsFrame then
		return;
	end

	AchievementsFrame.wasShown = nil;
	AchievementsFrame.isComparison = true;
	if AchievementsFrameComparisonTab_OnClick then
		AchievementsFrameTab_OnClick = AchievementsFrameComparisonTab_OnClick;
		AchievementsFrameTab_OnClick(1);
	end
	ShowUIPanel(AchievementsFrame);

	if AchievementsFrameComparisonHeaderName then
		AchievementsFrameComparisonHeaderName:SetText(displayName or "");
	end
	if AchievementsFrameComparisonHeaderPoints then
		AchievementsFrameComparisonHeaderPoints:SetText(tostring(tonumber(points) or 0));
	end
	if AchievementsFrameComparisonHeaderPortrait then
		if unit and UnitIsConnected(unit) then
			SetPortraitTexture(AchievementsFrameComparisonHeaderPortrait, unit);
			AchievementsFrameComparisonHeaderPortrait.unit = unit;
		else
			SetPortraitToTexture(AchievementsFrameComparisonHeaderPortrait, "Interface\\ICONS\\INV_Misc_QuestionMark");
			AchievementsFrameComparisonHeaderPortrait.unit = nil;
		end
	end

	if AchievementsFrameComparison_ForceUpdate then
		-- Auto-select the first real category so the list isn't empty on open.
		-- (Summary is always [1]; the first numeric entry is the first real category.)
		if ACHIEVEMENTUI_CATEGORIES and COMPARISON_ACHIEVEMENT_FUNCTIONS then
			for _, cat in next, ACHIEVEMENTUI_CATEGORIES do
				if type(cat.id) == "number" then
					COMPARISON_ACHIEVEMENT_FUNCTIONS.selectedCategory = cat.id;
					if AchievementsFrameComparison_UpdateStatusBars then
						AchievementsFrameComparison_UpdateStatusBars(cat.id);
					end
					break;
				end
			end
		end
		AchievementsFrameComparison_ForceUpdate();
	end
end

-- Updates comparison data in an already-open comparison frame.  Called when
-- the full response arrives (CMP_END) so the UI refreshes in place without
-- resetting the selected category or re-showing the panel.
function Achievements.RefreshComparisonData(targetName, points, completed, unit, statistics)
	local state = Achievements.comparisonState;
	if not state then
		return;
	end
	local targetKey = GetComparisonTargetKey(targetName);
	if state.targetKey and targetKey and state.targetKey ~= targetKey then
		return;
	end

	state.points = tonumber(points) or 0;
	state.completed = completed or {};
	state.statistics = statistics or {};
	if Achievements.invalidateAchievementStatsUICache then
		Achievements.invalidateAchievementStatsUICache();
	end
	if unit then
		state.unit = unit;
	end

	if AchievementsFrameComparisonHeaderPoints then
		AchievementsFrameComparisonHeaderPoints:SetText(tostring(tonumber(points) or 0));
	end
	if AchievementsFrameComparisonHeaderPortrait then
		local u = state.unit;
		if u and UnitIsConnected(u) then
			SetPortraitTexture(AchievementsFrameComparisonHeaderPortrait, u);
			AchievementsFrameComparisonHeaderPortrait.unit = u;
		end
	end

	if AchievementsFrameComparison_UpdateStatusBars and achievementFunctions == COMPARISON_ACHIEVEMENT_FUNCTIONS then
		local category = achievementFunctions.selectedCategory;
		if not category or category == "summary" or category == ACHIEVEMENT_COMPARISON_STATS_SUMMARY_ID then
			category = ACHIEVEMENT_COMPARISON_SUMMARY_ID;
		end
		AchievementsFrameComparison_UpdateStatusBars(category);
	end

	if AchievementsFrameComparison_ForceUpdate then
		AchievementsFrameComparison_ForceUpdate();
	end
end

function Achievements.GetComparisonStatistic(categoryOrStatisticID, index)
	local statisticID = ResolveAchievementID(categoryOrStatisticID, index);
	local statistic = ACHIEVEMENT_DATA[statisticID];
	if not statistic or not IsDisplayableStatistic(statisticID, statistic) then
		return nil, true, nil;
	end

	local state = Achievements.comparisonState;
	local statistics = state and state.statistics;
	return (statistics and statistics[statisticID]) or "--", false, statisticID;
end

function Achievements.GetAchievementGuildRep()
	return nil;
end

function Achievements.GetGuildAchievementNumMembers()
	return 0;
end

function Achievements.GetGuildAchievementMembers()
	return nil;
end

function Achievements.GetGuildAchievementMemberInfo()
	return nil;
end

Achievements.addonName = ADDON_NAME;
Achievements.markAchievementComplete = MarkAchievementComplete;
Achievements.notifyAchievementEarned = NotifyAchievementEarned;
Achievements.InvalidateAchievementUICache = InvalidateAchievementUICache;

Private.GetSavedCompletions = GetSavedCompletions;
Private.GetPlayerLevel = GetPlayerLevel;
Private.PrintMessage = PrintMessage;
Private.IsDebugBuild = IsDebugBuild;
Private.IsDebugEnabled = IsDebugEnabled;
Private.DebugMessage = DebugMessage;
Private.DebugWarning = DebugWarning;
Private.WithDebugLogging = WithDebugLogging;
Private.PrintToGuildChatFrames = PrintToGuildChatFrames;
Private.PrintToGuildOnly = PrintToGuildOnly;
Private.DispatchFrameEvent = DispatchFrameEvent;
Private.BitOr = BitOr;
Private.HasAchievementFlag = HasAchievementFlag;
Private.GetSavedCompletionTimestamp = GetSavedCompletionTimestamp;
Private.GetSavedCompletionDate = GetSavedCompletionDate;
Private.IsSavedCompletionComplete = IsSavedCompletionComplete;
Private.ShouldPlayAchievementVisual = ShouldPlayAchievementVisual;
Private.IsAchievementForPlayerFaction = IsAchievementForPlayerFaction;
Private.IsStatisticAchievement = IsStatisticAchievement;
Private.IsFeatOfStrengthAchievement = IsFeatOfStrengthAchievement;
Private.ShouldShowAchievementInUI = ShouldShowAchievementInUI;
Private.IsAchievementCompleted = IsAchievementCompleted;
Private.GetAchievementState = GetAchievementState;
Private.InvalidateAchievementUICache = InvalidateAchievementUICache;
Private.FormatAchievementBroadcast = FormatAchievementBroadcast;
Private.GetClassColorHex = GetClassColorHex;

if DEBUG then
-- add a temporary slash command to wipe the whole database for testing purposes
SLASH_ACHIEVEMENTSTEST1 = "/ach-clear";
SlashCmdList["ACHIEVEMENTSTEST"] = function()
	-- clear both the account-wide and per-character databases.
	for key in pairs(AchievementsDB) do
		AchievementsDB[key] = nil;
	end
	for key in pairs(AchievementsCharacterDB) do
		AchievementsCharacterDB[key] = nil;
	end
	Private.PrintMessage("AchievementsDB and AchievementsCharacterDB wiped.");
end

local textureProbeFrame;
local textureProbeTexture;
local textureProbePath;
local textureProbeResult;
local textureProbeScanState;
local TEXTURE_PROBE_SENTINEL = "Interface\\Icons\\INV_Misc_QuestionMark";
local TEXTURE_PROBE_MIN_WAIT_SECONDS = 0.03;
local TEXTURE_PROBE_TIMEOUT_SECONDS = 0.25;
local TEXTURE_PROBE_PROGRESS_INTERVAL = 100;

local function RoundTextureSize(value)
	return math.floor((value or 0) + 0.5);
end

local function IsMissingTextureSize(width, height)
	local roundedWidth = RoundTextureSize(width);
	local roundedHeight = RoundTextureSize(height);
	return (roundedWidth == 8 and roundedHeight == 8) or (roundedWidth == 1 and roundedHeight == 1);
end

local function IsMissingTextureProbe(width, height, textureValue)
	if textureValue == nil or textureValue == "" or textureValue == TEXTURE_PROBE_SENTINEL then
		return true;
	end
	return IsMissingTextureSize(width, height);
end

local function GetProbeTextureSize(frame, texture)
	local width = texture and texture.GetWidth and texture:GetWidth() or nil;
	local height = texture and texture.GetHeight and texture:GetHeight() or nil;
	if (not width or width == 0) and frame and frame.GetWidth then
		width = frame:GetWidth();
	end
	if (not height or height == 0) and frame and frame.GetHeight then
		height = frame:GetHeight();
	end
	return RoundTextureSize(width), RoundTextureSize(height);
end

local function BuildTextureProbeResult(path, frame, texture)
	local width, height = GetProbeTextureSize(frame, texture);
	local textureValue = texture and texture.GetTexture and texture:GetTexture() or nil;
	local textureFileID = texture and texture.GetTextureFileID and texture:GetTextureFileID() or nil;
	return {
		path = path,
		width = width,
		height = height,
		texture = textureValue,
		textureFileID = textureFileID,
		exists = not IsMissingTextureProbe(width, height, textureValue),
	};
end

local function EnsureTextureProbe()
	if textureProbeFrame and textureProbeTexture then
		return textureProbeFrame, textureProbeTexture;
	end
	local parent = UIParent or WorldFrame;
	textureProbeFrame = CreateFrame("Frame", "AchievementsTextureProbeFrame", parent);
	textureProbeFrame:Hide();
	textureProbeTexture = textureProbeFrame:CreateTexture(nil, "BACKGROUND");
	textureProbeTexture:SetAlpha(0);
	textureProbeTexture:SetPoint("CENTER", parent or textureProbeFrame, "CENTER", 0, 0);
	textureProbeFrame:ClearAllPoints();
	textureProbeFrame:SetAllPoints(textureProbeTexture);
	textureProbeFrame:SetScript("OnSizeChanged", function(_, width, height)
		if not textureProbePath then
			return;
		end
		textureProbeResult = BuildTextureProbeResult(textureProbePath, textureProbeFrame, textureProbeTexture);
		textureProbeResult.width = RoundTextureSize(width);
		textureProbeResult.height = RoundTextureSize(height);
		textureProbeResult.exists = not IsMissingTextureProbe(textureProbeResult.width, textureProbeResult.height, textureProbeResult.texture);
	end);
	textureProbeFrame:Show();
	textureProbeTexture:Show();
	return textureProbeFrame, textureProbeTexture;
end

local function BeginTextureProbe(path)
	local frame, texture = EnsureTextureProbe();
	if not frame or not texture then
		return nil, nil, "texture probe unavailable";
	end

	textureProbePath = nil;
	textureProbeResult = nil;
	texture:SetTexture(TEXTURE_PROBE_SENTINEL);
	texture:SetSize(16, 16);
	textureProbePath = path;
	texture:SetTexture(path);
	texture:SetSize(0, 0);
	return frame, texture;
end

local function ProbeTexture(path)
	path = TrimWhitespace(path);
	if path == "" then
		return false, 0, 0, "empty path";
	end

	local frame, texture, reason = BeginTextureProbe(path);
	if not frame or not texture then
		return false, 0, 0, reason;
	end
	textureProbePath = nil;

	local result = textureProbeResult;
	if not result then
		result = BuildTextureProbeResult(path, frame, texture);
	end

	return result.exists, result.width, result.height;
end

local function FormatAchievementIDList(ids)
	table.sort(ids);
	local parts = {};
	for _, achievementID in ipairs(ids) do
		local achievement = ACHIEVEMENT_DATA[achievementID];
		local label = tostring(achievementID);
		if achievement and achievement.name then
			label = label .. " " .. achievement.name;
		end
		tinsert(parts, label);
	end
	return table.concat(parts, ", ");
end

local function GetTextureReportClientLabel()
	local client = ACHIEVEMENTS_DATA.client or "unknown";
	local version, build = GetBuildInfo();
	if version and build then
		return client .. " / " .. tostring(version) .. " (" .. tostring(build) .. ")";
	end
	return client;
end

local function AppendIconScanReportLine(line)
	AppendDebugLogLine(line);
end

local StartNextQueuedIconProbe;

local function FinishQueuedIconScan(state)
	if textureProbeFrame then
		textureProbeFrame:SetScript("OnUpdate", nil);
	end
	textureProbePath = nil;
	textureProbeResult = nil;
	textureProbeScanState = nil;

	AppendIconScanReportLine("Achievements missing icon scan");
	AppendIconScanReportLine("Client: " .. GetTextureReportClientLabel());
	AppendIconScanReportLine("Data client: " .. tostring(ACHIEVEMENTS_DATA.client or "unknown") .. "; source: " .. tostring(ACHIEVEMENTS_DATA.source or "unknown"));
	AppendIconScanReportLine("Probe: queued one texture per frame; waited at least " .. tostring(TEXTURE_PROBE_MIN_WAIT_SECONDS) .. "s and up to " .. tostring(TEXTURE_PROBE_TIMEOUT_SECONDS) .. "s for uncached textures.");
	AppendIconScanReportLine("Checked " .. tostring(#state.paths) .. " unique icon paths across " .. tostring(state.achievementsWithIcons) .. " achievement/stat records.");
	if #state.achievementsWithoutIconData > 0 then
		AppendIconScanReportLine("Records without icon data: " .. FormatAchievementIDList(state.achievementsWithoutIconData));
	end
	AppendIconScanReportLine("Missing unique icon paths: " .. tostring(#state.missing));
	for _, entry in ipairs(state.missing) do
		AppendIconScanReportLine("MISSING " .. entry.path .. " (probe " .. tostring(entry.width) .. "x" .. tostring(entry.height) .. ", texture=" .. tostring(entry.texture or "nil") .. ", fileID=" .. tostring(entry.textureFileID or "nil") .. ") | " .. FormatAchievementIDList(entry.ids));
	end
	if #state.missing == 0 and #state.achievementsWithoutIconData == 0 then
		AppendIconScanReportLine("No missing icon textures were detected by the queued client texture probe.");
	end

	ShowDebugLogFrame(true);
	Private.PrintMessage("Achievements missing icon scan complete: " .. tostring(#state.missing) .. " missing unique paths. The report is selected in the debug log.");
end

local function RecordQueuedIconProbeResult(state, result)
	local path = state.currentPath;
	if not result.exists then
		local entry = state.iconsByPath[path];
		entry.path = path;
		entry.width = result.width;
		entry.height = result.height;
		entry.texture = result.texture;
		entry.textureFileID = result.textureFileID;
		tinsert(state.missing, entry);
	end

	state.completed = state.completed + 1;
	if state.completed % TEXTURE_PROBE_PROGRESS_INTERVAL == 0 then
		Private.PrintMessage("Achievements missing icon scan: " .. tostring(state.completed) .. "/" .. tostring(#state.paths) .. " paths checked...");
	end
	StartNextQueuedIconProbe(state);
end

local function TextureProbeQueue_OnUpdate(_, elapsed)
	local state = textureProbeScanState;
	if not state then
		if textureProbeFrame then
			textureProbeFrame:SetScript("OnUpdate", nil);
		end
		return;
	end

	state.currentElapsed = (state.currentElapsed or 0) + (elapsed or 0);
	local result = textureProbeResult;
	if result and result.path == state.currentPath and state.currentElapsed >= TEXTURE_PROBE_MIN_WAIT_SECONDS then
		textureProbePath = nil;
		textureProbeResult = nil;
		RecordQueuedIconProbeResult(state, result);
	elseif state.currentElapsed >= TEXTURE_PROBE_TIMEOUT_SECONDS then
		local timeoutResult = BuildTextureProbeResult(state.currentPath, textureProbeFrame, textureProbeTexture);
		textureProbePath = nil;
		textureProbeResult = nil;
		RecordQueuedIconProbeResult(state, timeoutResult);
	end
end

StartNextQueuedIconProbe = function(state)
	if state.nextIndex > #state.paths then
		FinishQueuedIconScan(state);
		return;
	end

	local path = state.paths[state.nextIndex];
	state.nextIndex = state.nextIndex + 1;
	state.currentPath = path;
	state.currentElapsed = 0;

	local frame, texture, reason = BeginTextureProbe(path);
	if not frame or not texture then
		AppendIconScanReportLine("Texture probe unavailable: " .. tostring(reason or "unknown error"));
		FinishQueuedIconScan(state);
		return;
	end
	frame:SetScript("OnUpdate", TextureProbeQueue_OnUpdate);
end

function TextureExists(path, quiet)
	local exists, width, height, reason = ProbeTexture(path);
	local textureValue = textureProbeResult and textureProbeResult.texture or textureProbeTexture and textureProbeTexture.GetTexture and textureProbeTexture:GetTexture() or nil;
	local textureFileID = textureProbeResult and textureProbeResult.textureFileID or textureProbeTexture and textureProbeTexture.GetTextureFileID and textureProbeTexture:GetTextureFileID() or nil;
	local message;
	if exists then
		message = tostring(path) .. " exists (" .. tostring(width) .. "x" .. tostring(height) .. ", texture=" .. tostring(textureValue or "nil") .. ", fileID=" .. tostring(textureFileID or "nil") .. ")";
	else
		message = tostring(path) .. " is missing";
		if reason then
			message = message .. " (" .. reason .. ")";
		else
			message = message .. " (" .. tostring(width) .. "x" .. tostring(height) .. ", texture=" .. tostring(textureValue or "nil") .. ", fileID=" .. tostring(textureFileID or "nil") .. ")";
		end
	end
	if not quiet then
		Private.PrintMessage(message);
		AppendDebugLogLine(message);
	end
	return exists, width, height;
end

function Achievements.LogMissingIcons(options)
	options = options or {};
	if textureProbeScanState and textureProbeFrame then
		textureProbeFrame:SetScript("OnUpdate", nil);
		textureProbeScanState = nil;
	end
	if options.clearLog ~= false then
		ClearDebugLog();
	end

	local iconsByPath = {};
	local paths = {};
	local achievementsWithIcons = 0;
	local achievementsWithoutIconData = {};
	for achievementID, achievement in pairs(ACHIEVEMENT_DATA) do
		local icon = achievement and achievement.icon;
		icon = ICON_ASSET_OVERRIDES[icon] or icon
		if icon and icon ~= "" then
			achievementsWithIcons = achievementsWithIcons + 1;
			if not iconsByPath[icon] then
				iconsByPath[icon] = { ids = {} };
				tinsert(paths, icon);
			end
			tinsert(iconsByPath[icon].ids, achievementID);
		else
			tinsert(achievementsWithoutIconData, achievementID);
		end
	end
	table.sort(paths);
	table.sort(achievementsWithoutIconData);

	local state = {
		iconsByPath = iconsByPath,
		paths = paths,
		achievementsWithIcons = achievementsWithIcons,
		achievementsWithoutIconData = achievementsWithoutIconData,
		missing = {},
		nextIndex = 1,
		completed = 0,
	};
	textureProbeScanState = state;
	Private.PrintMessage("Achievements missing icon scan started: " .. tostring(#paths) .. " unique paths queued.");
	StartNextQueuedIconProbe(state);
	return state;
end

Achievements.TextureExists = TextureExists;

SLASH_ACHIEVEMENTSDEBUG1 = "/ach-debug";
SlashCmdList["ACHIEVEMENTSDEBUG"] = function(arg)
	local rawArg = TrimWhitespace(arg);
	local arg = string.lower(rawArg);
	if arg == "" or arg == "show" or arg == "open" then
		ShowDebugLogFrame(false);
		Private.PrintMessage("Achievements debug log opened. Logging is " .. (IsDebugEnabled() and "enabled" or "disabled") .. ".");
		return;
	elseif arg == "on" or arg == "1" or arg == "true" then
		AchievementsDB.debug = true;
	elseif arg == "copy" or arg == "select" then
		ShowDebugLogFrame(true);
		Private.PrintMessage("Achievements debug log selected. Press your copy shortcut to copy it.");
		return;
	elseif arg == "hide" or arg == "close" then
		if debugLogFrame then
			debugLogFrame:Hide();
		end
		return;
	elseif arg == "clear" then
		ClearDebugLog();
		Private.debugMessages = {};
		Private.PrintMessage("Achievements debug log cleared.");
		return;
	elseif arg == "scan" or arg == "all" or arg == "evaluate" then
		if not Achievements.DebugEvaluateAllAchievements then
			Private.PrintMessage("Achievements debug scan is not available yet.");
			return;
		end
		local report = Achievements.DebugEvaluateAllAchievements({ resetWarningCache = true, forceLogging = true });
		Private.PrintMessage("Achievements " .. (report and report.summary or "debug scan complete") .. ". Use /ach-debug copy to copy the log.");
		return;
	elseif arg == "off" or arg == "0" or arg == "false" then
		AchievementsDB.debug = nil;
		Private.debugMessages = {};
	elseif arg == "reset" then
		Private.debugMessages = {};
		Private.PrintMessage("Achievements debug warning cache reset.");
		return;
	elseif arg == "icons" or arg == "missing-icons" or arg == "scan-icons" then
		Achievements.LogMissingIcons({ clearLog = true });
		return;
	elseif arg == "texture" or arg:sub(1, 8) == "texture " then
		local path = TrimWhitespace(rawArg:sub(9));
		if path == "" then
			Private.PrintMessage("Usage: /ach-debug texture <path>");
			return;
		end
		TextureExists(path);
		return;
	else
		Private.PrintMessage("Achievements debug commands: /ach-debug, /ach-debug copy, /ach-debug scan, /ach-debug missing-icons, /ach-debug clear, /ach-debug reset, /ach-debug on, /ach-debug off, /ach-debug hide, /ach-debug show, /ach-debug watch, /ach-debug texture <path>");
		return;
	end

	Private.PrintMessage("Achievements debug logging " .. (IsDebugEnabled() and "enabled" or "disabled") .. ".");
end
end
