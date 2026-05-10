local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsCriteria.lua");
end

local Private = Achievements.private;
local data = Private.data;
local ACHIEVEMENT_DATA = data.achievements;
local CRITERIA_DATA = data.criteria;
local CRITERIA_TREE_DATA = data.criteriaTrees;
local CRITERIA_TREE_CHILDREN = data.criteriaTreeChildren;
local CRITERIA_BY_ACHIEVEMENT = data.criteriaByAchievement;
local ACHIEVEMENT_BY_CRITERIA = data.achievementByCriteria;

local CRITERIA_TYPE_REACH_LEVEL = Achievements.criteriaResolvers.criteriaTypes.REACH_LEVEL;
local CRITERIA_TREE_FLAGS = Achievements.criteriaResolvers.criteriaTreeFlags;
local CRITERIA_TREE_FLAG_DO_NOT_DISPLAY = CRITERIA_TREE_FLAGS.DO_NOT_DISPLAY;
local CRITERIA_TREE_FLAG_IS_DATE = CRITERIA_TREE_FLAGS.IS_DATE;
local CRITERIA_TREE_FLAG_IS_MONEY = CRITERIA_TREE_FLAGS.IS_MONEY;

local CRITERIA_TREE_OPERATOR = {
	SINGLE = 0,
	SINGLE_NOT_COMPLETED = 1,
	ALL = 4,
	SUM_CHILDREN = 5,
	MAX_CHILD = 6,
	COUNT_DIRECT_CHILDREN = 7,
	ANY = 8,
	SUM_CHILDREN_WEIGHT = 9,
};

local ACHIEVEMENT_FLAGS = Private.ACHIEVEMENT_FLAGS or {
	MAX_USED = 0x10,
	AVERAGE = 0x40,
	PROGRESS_BAR = 0x80,
};

local evaluatingAchievements = {};
local pendingCriteriaRefresh;
local pendingCriteriaRefreshFull;
local pendingCriteriaRefreshShowAlerts;
local pendingCriteriaRefreshReasons = {};
local pendingCriteriaRefreshTypes;
local runningScheduledCriteriaRefresh;
local allAchievementIDs;
local achievementCriteriaTypeCache;

local function GetDebugMilliseconds()
	return debugprofilestop();
end

local function DebugCriteria(message)
	if Private and Private.DebugMessage then
		Private.DebugMessage("criteria: " .. tostring(message));
	end
end

local function AddCriteriaRefreshReason(reason)
	if type(reason) == "string" and reason ~= "" then
		pendingCriteriaRefreshReasons[#pendingCriteriaRefreshReasons + 1] = reason;
	end
end

local function HasCriteriaTreeFlag(criteriaTree, flag)
	local flags = criteriaTree and criteriaTree.flags or 0;
	return bit.band(flags, flag) == flag;
end

local function HasAchievementFlag(achievement, flag)
	local flags = achievement and achievement.flags or 0;
	return bit.band(flags, flag) == flag;
end

local function AddFlag(flags, flag)
	flags = flags or 0;
	if HasAchievementFlag({ flags = flags }, flag) then
		return flags;
	end
	return bit.bor(flags, flag);
end

local function CriteriaTreeHasFlag(criteriaTreeID, flag)
	local criteriaTree = criteriaTreeID and CRITERIA_TREE_DATA[criteriaTreeID];
	if not criteriaTree then
		return false;
	end
	if HasCriteriaTreeFlag(criteriaTree, flag) then
		return true;
	end
	for _, childID in ipairs(CRITERIA_TREE_CHILDREN[criteriaTreeID] or {}) do
		if CriteriaTreeHasFlag(childID, flag) then
			return true;
		end
	end
	return false;
end

local function FormatStatisticInteger(quantity)
	return tostring(math.floor((tonumber(quantity) or 0) + 0.5));
end

local function FormatStatisticDecimal(quantity)
	local formatted = string.format("%.2f", quantity or 0);
	formatted = string.gsub(formatted, "0+$", "");
	formatted = string.gsub(formatted, "%.$", "");
	if formatted == "-0" then
		return "0";
	end
	return formatted;
end

local function HexEncodeTransport(value)
	return (tostring(value or ""):gsub(".", function(character)
		return string.format("%02X", string.byte(character));
	end));
end

local function HexDecodeTransport(value)
	if type(value) ~= "string" or value == "" then
		return nil;
	end
	return (value:gsub("(%x%x)", function(hex)
		return string.char(tonumber(hex, 16));
	end));
end

local function GetSavedCompletionTimestamp(savedState)
	if Private.GetSavedCompletionTimestamp then
		return Private.GetSavedCompletionTimestamp(savedState);
	end
	return tonumber(savedState and savedState.ts);
end

local function GetStatisticElapsedDays()
	local db = rawget(_G, "AchievementsCharacterDB");
	local timeFunction = rawget(_G, "time");
	if type(db) ~= "table" or type(timeFunction) ~= "function" then
		return nil;
	end

	local now = timeFunction();
	if type(now) ~= "number" or now <= 0 then
		return nil;
	end

	local startedAt = tonumber(db.statisticsStartedAt) or now;
	db.statisticsStartedAt = startedAt;

	if type(db.completed) == "table" then
		for _, savedState in pairs(db.completed) do
			local completedAt = GetSavedCompletionTimestamp(savedState);
			if completedAt and completedAt < startedAt then
				startedAt = completedAt;
			end
		end
	end

	if startedAt > now then
		startedAt = now;
	end
	if startedAt < db.statisticsStartedAt then
		db.statisticsStartedAt = startedAt;
	end

	local days = (now - startedAt) / 86400;
	if days < 1 then
		return 1;
	end
	return days;
end

local function GetDisplayableCriteriaIndices(achievementID)
	local criteria = CRITERIA_BY_ACHIEVEMENT[achievementID];
	if not criteria then return nil; end
	local result = {};
	for i, criteriaTreeID in ipairs(criteria) do
		local criteriaTree = CRITERIA_TREE_DATA[criteriaTreeID];
		if not criteriaTree or not HasCriteriaTreeFlag(criteriaTree, CRITERIA_TREE_FLAG_DO_NOT_DISPLAY) then
			tinsert(result, i);
		end
	end
	return result;
end

local function GetRequiredQuantity(criteriaTree)
	local requiredQuantity = criteriaTree and criteriaTree.amount or 0;
	if requiredQuantity <= 0 then
		return 1;
	end

	return requiredQuantity;
end

local function GetCriteriaDescription(achievementID, criteriaTree)
	local criteriaString = criteriaTree and criteriaTree.description;
	if criteriaString and criteriaString ~= "" then
		return criteriaString;
	end

	local achievement = ACHIEVEMENT_DATA[achievementID];
	return achievement and achievement.description or "";
end

local function BuildQuantityString(quantity, requiredQuantity, criteriaTree)
	quantity = quantity or 0;
	requiredQuantity = requiredQuantity or 1;

	if HasCriteriaTreeFlag(criteriaTree, CRITERIA_TREE_FLAGS.IS_MONEY) and GetCoinTextureString then
		return GetCoinTextureString(quantity);
	end

	if HasCriteriaTreeFlag(criteriaTree, CRITERIA_TREE_FLAGS.IS_DATE) and quantity > 0 and date then
		return date("%m/%d/%y", quantity);
	end

	return string.format("%d / %d", quantity, requiredQuantity);
end

local function BuildStatisticQuantityString(statistic, quantity, criteriaTreeID, statLabel)
	quantity = tonumber(quantity) or 0;
	if quantity <= 0 then
		return "--";
	end

	local getCoinTextureString = rawget(_G, "GetCoinTextureString");
	if CriteriaTreeHasFlag(criteriaTreeID, CRITERIA_TREE_FLAG_IS_MONEY) and getCoinTextureString then
		return getCoinTextureString(quantity);
	end

	local dateFunction = rawget(_G, "date");
	if CriteriaTreeHasFlag(criteriaTreeID, CRITERIA_TREE_FLAG_IS_DATE) and quantity > 0 and dateFunction then
		return dateFunction("%m/%d/%y", quantity);
	end

	if HasAchievementFlag(statistic, ACHIEVEMENT_FLAGS.AVERAGE) then
		local elapsedDays = GetStatisticElapsedDays();
		if not elapsedDays or elapsedDays <= 0 then
			return "--";
		end
		return FormatStatisticDecimal(quantity / elapsedDays);
	end

	if HasAchievementFlag(statistic, ACHIEVEMENT_FLAGS.MAX_USED) and statLabel and statLabel ~= "" then
		return FormatStatisticInteger(quantity) .. " (" .. statLabel .. ")";
	end

	return FormatStatisticInteger(quantity);
end

local function GetAchievementCriteriaRootID(achievement)
	if not achievement then
		return nil;
	end

	if achievement.criteriaTree and achievement.criteriaTree ~= 0 then
		return achievement.criteriaTree;
	end

	local sharedAchievement = achievement.sharesCriteria and ACHIEVEMENT_DATA[achievement.sharesCriteria];
	if sharedAchievement and sharedAchievement.criteriaTree and sharedAchievement.criteriaTree ~= 0 then
		return sharedAchievement.criteriaTree;
	end

	return nil;
end

local function GetAllAchievementIDs()
	if allAchievementIDs then
		return allAchievementIDs;
	end
	allAchievementIDs = {};
	for achievementID in pairs(ACHIEVEMENT_DATA) do
		tinsert(allAchievementIDs, achievementID);
	end
	table.sort(allAchievementIDs);
	return allAchievementIDs;
end

local function AddCriteriaTreeTypes(criteriaTreeID, criteriaTypes, seenTrees)
	criteriaTreeID = tonumber(criteriaTreeID);
	if not criteriaTreeID or seenTrees[criteriaTreeID] then
		return;
	end
	seenTrees[criteriaTreeID] = true;

	local criteriaTree = CRITERIA_TREE_DATA[criteriaTreeID];
	local criteria = criteriaTree and CRITERIA_DATA[criteriaTree.criteriaID];
	local criteriaType = criteria and tonumber(criteria.type);
	if criteriaType then
		criteriaTypes[criteriaType] = true;
	end

	for _, childID in ipairs(CRITERIA_TREE_CHILDREN[criteriaTreeID] or {}) do
		AddCriteriaTreeTypes(childID, criteriaTypes, seenTrees);
	end
end

local function AddAchievementCriteriaTypes(achievementID, criteriaTypes)
	local achievement = ACHIEVEMENT_DATA[achievementID];
	local seenTrees = {};
	local rootID = GetAchievementCriteriaRootID(achievement);
	if rootID then
		AddCriteriaTreeTypes(rootID, criteriaTypes, seenTrees);
	end
	for _, criteriaTreeID in ipairs(CRITERIA_BY_ACHIEVEMENT[achievementID] or {}) do
		AddCriteriaTreeTypes(criteriaTreeID, criteriaTypes, seenTrees);
	end
end

local function GetAchievementCriteriaTypeCache()
	if achievementCriteriaTypeCache then
		return achievementCriteriaTypeCache;
	end
	achievementCriteriaTypeCache = {};
	for achievementID in pairs(ACHIEVEMENT_DATA) do
		local criteriaTypes = {};
		AddAchievementCriteriaTypes(achievementID, criteriaTypes);
		for criteriaType in pairs(criteriaTypes) do
			achievementCriteriaTypeCache[criteriaType] = achievementCriteriaTypeCache[criteriaType] or {};
			achievementCriteriaTypeCache[criteriaType][achievementID] = true;
		end
	end
	return achievementCriteriaTypeCache;
end

local function AddCriteriaRefreshTypes(criteriaTypes)
	if criteriaTypes == nil then
		return;
	end
	pendingCriteriaRefreshTypes = pendingCriteriaRefreshTypes or {};
	if type(criteriaTypes) == "table" then
		for key, value in pairs(criteriaTypes) do
			local criteriaType = tonumber(value) or (value == true and tonumber(key));
			if criteriaType then
				pendingCriteriaRefreshTypes[criteriaType] = true;
			end
		end
		return;
	end
	criteriaTypes = tonumber(criteriaTypes);
	if criteriaTypes then
		pendingCriteriaRefreshTypes[criteriaTypes] = true;
	end
end

local function BuildAchievementIDListForCriteriaTypes(criteriaTypes)
	local cache = GetAchievementCriteriaTypeCache();
	local seen = {};
	local achievementIDs = {};
	for criteriaType in pairs(criteriaTypes or {}) do
		for achievementID in pairs(cache[criteriaType] or {}) do
			if not seen[achievementID] then
				seen[achievementID] = true;
				tinsert(achievementIDs, achievementID);
			end
		end
	end
	table.sort(achievementIDs);
	return achievementIDs;
end

local function GetResultQuantity(result)
	return result and (result.rawQuantity or result.quantity) or 0;
end

local function ResolveStatisticChildResult(achievementID, criteriaTreeID)
	if not Achievements.ResolveCriteriaTree then
		return nil;
	end
	return Achievements.ResolveCriteriaTree(criteriaTreeID, achievementID);
end

local function ResolveStatisticQuantity(achievementID, criteriaTreeID)
	local criteriaTree = criteriaTreeID and CRITERIA_TREE_DATA[criteriaTreeID];
	if not criteriaTree then
		return 0, 1;
	end

	local childIDs = CRITERIA_TREE_CHILDREN[criteriaTreeID];
	if not childIDs or #childIDs == 0 then
		local result = ResolveStatisticChildResult(achievementID, criteriaTreeID);
		return GetResultQuantity(result), (result and result.requiredQuantity) or GetRequiredQuantity(criteriaTree), result and result.statLabel;
	end

	local operator = criteriaTree.operator or CRITERIA_TREE_OPERATOR.SINGLE;
	local quantity = 0;
	local requiredQuantity = criteriaTree.amount or 0;
	local statLabel;

	if operator == CRITERIA_TREE_OPERATOR.COUNT_DIRECT_CHILDREN then
		for _, childID in ipairs(childIDs) do
			local result = ResolveStatisticChildResult(achievementID, childID);
			if result and result.completed then
				quantity = quantity + 1;
			end
		end
		if requiredQuantity <= 0 then
			requiredQuantity = #childIDs;
		end
		return quantity, requiredQuantity;
	end

	if operator == CRITERIA_TREE_OPERATOR.SUM_CHILDREN or operator == CRITERIA_TREE_OPERATOR.SUM_CHILDREN_WEIGHT then
		for _, childID in ipairs(childIDs) do
			quantity = quantity + GetResultQuantity(ResolveStatisticChildResult(achievementID, childID));
		end
		return quantity, requiredQuantity > 0 and requiredQuantity or 1;
	end

	for _, childID in ipairs(childIDs) do
		local childResult = ResolveStatisticChildResult(achievementID, childID);
		local childQuantity = GetResultQuantity(childResult);
		if childQuantity > quantity then
			quantity = childQuantity;
			local childTree = CRITERIA_TREE_DATA[childID];
			statLabel = (childResult and childResult.statLabel) or (childTree and childTree.description);
			if statLabel == "" then
				statLabel = nil;
			end
		end
	end
	return quantity, requiredQuantity > 0 and requiredQuantity or 1, statLabel;
end

local function GetCriteriaInfoRecord(achievementID, criteriaIndex, criteriaTreeIDOverride, forceProgressBar)
	criteriaIndex = criteriaIndex or 1;
	local criteriaTreeID = criteriaTreeIDOverride or (CRITERIA_BY_ACHIEVEMENT[achievementID] and CRITERIA_BY_ACHIEVEMENT[achievementID][criteriaIndex]);
	local criteriaTree = criteriaTreeID and CRITERIA_TREE_DATA[criteriaTreeID];
	if not criteriaTree then
		return nil;
	end

	local criteria = CRITERIA_DATA[criteriaTree.criteriaID] or {
		id = criteriaTree.criteriaID or 0,
		type = 0,
		asset = 0,
		flags = 0,
	};
	local criteriaResult = Achievements.ResolveCriteriaTree(criteriaTreeID, achievementID) or {};
	local requiredQuantity = criteriaResult.requiredQuantity or GetRequiredQuantity(criteriaTree);
	local quantity = criteriaResult.quantity or 0;
	local flags = criteriaTree.flags or 0;
	if forceProgressBar then
		flags = AddFlag(flags, CRITERIA_TREE_FLAGS.PROGRESS_BAR);
	end

	return {
		criteriaString = GetCriteriaDescription(achievementID, criteriaTree),
		criteriaType = criteria.type or 0,
		completed = criteriaResult.completed == true,
		quantity = quantity,
		requiredQuantity = requiredQuantity,
		characterName = criteriaResult.characterName,
		flags = flags,
		assetID = criteria.asset or 0,
		quantityString = BuildQuantityString(quantity, requiredQuantity, criteriaTree),
		criteriaID = criteriaTree.criteriaID or 0,
		eligible = criteriaResult.eligible ~= false,
	};
end

function Achievements.EvaluateAchievementCriteriaState(achievementID)
	if evaluatingAchievements[achievementID] then
		return nil;
	end

	local achievement = ACHIEVEMENT_DATA[achievementID];
	local criteriaTreeID = GetAchievementCriteriaRootID(achievement);
	if not achievement then
		return nil;
	end
	if Achievements.ResolveSpecialAchievementState then
		local completed, quantity, requiredQuantity = Achievements.ResolveSpecialAchievementState(achievementID);
		if completed ~= nil then
			return completed == true, nil, nil, nil, quantity or (completed and 1 or 0), requiredQuantity or 1;
		end
	end
	if not criteriaTreeID then
		return nil;
	end

	evaluatingAchievements[achievementID] = true;
	local criteriaResult = Achievements.ResolveCriteriaTree(criteriaTreeID, achievementID);
	evaluatingAchievements[achievementID] = nil;
	if not criteriaResult then
		return nil;
	end
	if Private.IsStatisticAchievement(achievement) then
		return false, nil, nil, nil, criteriaResult.rawQuantity or criteriaResult.quantity or 0, criteriaResult.requiredQuantity or 1;
	end

	return criteriaResult.completed == true, nil, nil, nil, criteriaResult.quantity or 0, criteriaResult.requiredQuantity or 1;
end

function Achievements.GetStatisticQuantityValue(statisticID)
	local statistic = statisticID and ACHIEVEMENT_DATA[statisticID];
	if not statistic or not Private.IsStatisticAchievement(statistic) then
		return nil;
	end

	local criteriaTreeID = GetAchievementCriteriaRootID(statistic);
	if not criteriaTreeID then
		return 0;
	end

	local quantity, _, statLabel = ResolveStatisticQuantity(statisticID, criteriaTreeID);
	return quantity or 0, statLabel;
end

function Achievements.FormatStatisticQuantityString(statisticID, quantity, statLabel)
	local statistic = statisticID and ACHIEVEMENT_DATA[statisticID];
	if not statistic or not Private.IsStatisticAchievement(statistic) then
		return nil;
	end

	local criteriaTreeID = GetAchievementCriteriaRootID(statistic);
	if not criteriaTreeID then
		return "--";
	end

	return BuildStatisticQuantityString(statistic, quantity, criteriaTreeID, statLabel);
end

function Achievements.GetStatisticQuantityString(statisticID)
	local quantity, statLabel = Achievements.GetStatisticQuantityValue(statisticID);
	if quantity == nil then
		return nil;
	end
	return Achievements.FormatStatisticQuantityString(statisticID, quantity, statLabel);
end

function Achievements.GetStatisticTransportString(statisticID)
	local statistic = statisticID and ACHIEVEMENT_DATA[statisticID];
	if not statistic or not Private.IsStatisticAchievement(statistic) then
		return nil;
	end

	local quantity, statLabel = Achievements.GetStatisticQuantityValue(statisticID);
	if quantity == nil then
		return nil;
	end

	if HasAchievementFlag(statistic, ACHIEVEMENT_FLAGS.AVERAGE) then
		return "s" .. HexEncodeTransport(Achievements.FormatStatisticQuantityString(statisticID, quantity, statLabel));
	end

	local text = "n" .. tostring(math.floor(tonumber(quantity) or 0));
	if statLabel and statLabel ~= "" then
		text = text .. ":" .. HexEncodeTransport(statLabel);
	end
	return text;
end

function Achievements.FormatStatisticTransportString(statisticID, transportValue)
	if type(transportValue) ~= "string" or transportValue == "" then
		return "--";
	end

	local mode = string.sub(transportValue, 1, 1);
	local payload = string.sub(transportValue, 2);
	if mode == "s" then
		return HexDecodeTransport(payload) or "--";
	elseif mode == "n" then
		local quantityText, statLabelHex = payload:match("^(%-?%d+):?(%x*)$");
		local statLabel = HexDecodeTransport(statLabelHex);
		return Achievements.FormatStatisticQuantityString(statisticID, tonumber(quantityText) or 0, statLabel) or "--";
	end

	return "--";
end

function Achievements.GetAchievementNumCriteria(achievementID)
	local achievement = achievementID and ACHIEVEMENT_DATA[achievementID];
	if HasAchievementFlag(achievement, ACHIEVEMENT_FLAGS.PROGRESS_BAR) and GetAchievementCriteriaRootID(achievement) then
		return 1;
	end

	local indices = GetDisplayableCriteriaIndices(achievementID);
	return indices and #indices or 0;
end

function Achievements.GetAchievementCriteriaInfo(achievementID, criteriaIndex)
	if not achievementID then
		return nil;
	end

	if not ACHIEVEMENT_DATA[achievementID] and ACHIEVEMENT_BY_CRITERIA[achievementID] then
		achievementID = ACHIEVEMENT_BY_CRITERIA[achievementID];
	end

	local achievement = ACHIEVEMENT_DATA[achievementID];
	if not achievement or not Private.IsAchievementForPlayerFaction(achievement) then
		return nil;
	end

	if HasAchievementFlag(achievement, ACHIEVEMENT_FLAGS.PROGRESS_BAR) then
		local criteriaInfo = GetCriteriaInfoRecord(achievementID, 1, GetAchievementCriteriaRootID(achievement), true);
		if not criteriaInfo then
			return nil;
		end

		return criteriaInfo.criteriaString,
			criteriaInfo.criteriaType,
			criteriaInfo.completed,
			criteriaInfo.quantity,
			criteriaInfo.requiredQuantity,
			criteriaInfo.characterName,
			criteriaInfo.flags,
			criteriaInfo.assetID,
			criteriaInfo.quantityString,
			criteriaInfo.criteriaID,
			criteriaInfo.eligible;
	end

	local indices = GetDisplayableCriteriaIndices(achievementID);
	local rawIndex = indices and indices[criteriaIndex];
	local criteriaInfo = rawIndex and GetCriteriaInfoRecord(achievementID, rawIndex);
	if not criteriaInfo then
		return nil;
	end

	return criteriaInfo.criteriaString,
		criteriaInfo.criteriaType,
		criteriaInfo.completed,
		criteriaInfo.quantity,
		criteriaInfo.requiredQuantity,
		criteriaInfo.characterName,
		criteriaInfo.flags,
		criteriaInfo.assetID,
		criteriaInfo.quantityString,
		criteriaInfo.criteriaID,
		criteriaInfo.eligible;
end

function Achievements.GetAchievementCriteriaProgressPayload(achievementID)
	local numCriteria = Achievements.GetAchievementNumCriteria and Achievements.GetAchievementNumCriteria(achievementID) or 0;
	if numCriteria <= 0 then
		return "";
	end

	local payload = { "b" };
	for i = 1, numCriteria do
		local _, _, completed = Achievements.GetAchievementCriteriaInfo(achievementID, i);
		payload[#payload + 1] = completed and "1" or "0";
	end
	return table.concat(payload);
end

function Achievements.GetAchievementInfoFromCriteria(criteriaID)
	local achievementID = ACHIEVEMENT_BY_CRITERIA[criteriaID];
	if achievementID then
		local achievement = ACHIEVEMENT_DATA[achievementID];
		if achievement and Private.IsAchievementForPlayerFaction(achievement) then
			return achievement.id, achievement.name;
		end
	end

	return nil;
end

local function RefreshCriteriaAchievementIDs(achievementIDs, showAlerts, scope)
	local startedAt = GetDebugMilliseconds();
	local evaluatedCount = 0;
	local completedCount = 0;

	for _, achievementID in ipairs(achievementIDs) do
		local achievement = ACHIEVEMENT_DATA[achievementID];
		local savedState = Private.GetSavedCompletions(achievementID)[achievementID];
		if achievement and not Private.IsStatisticAchievement(achievement) and not Private.IsSavedCompletionComplete(savedState) then
			evaluatedCount = evaluatedCount + 1;
			local completed = Achievements.EvaluateAchievementCriteriaState(achievementID);
			if completed then
				if Achievements.markAchievementComplete(achievementID, showAlerts) then
					completedCount = completedCount + 1;
				end
			end
		end
	end

	if Private.DispatchFrameEvent then
		Private.DispatchFrameEvent(rawget(_G, "AchievementFrameAchievements"), "CRITERIA_UPDATE");
		Private.DispatchFrameEvent(rawget(_G, "AchievementFrameStats"), "CRITERIA_UPDATE");
	end
	if Achievements.WatchFrame_Update then
		Achievements.WatchFrame_Update();
	end
	DebugCriteria("refresh showAlerts=" .. tostring(showAlerts == true) .. " scope=" .. tostring(scope or "all") .. " evaluated=" .. tostring(evaluatedCount) .. " completed=" .. tostring(completedCount) .. " ms=" .. string.format("%.1f", GetDebugMilliseconds() - startedAt));
end

function Achievements.RefreshCriteriaAchievements(showAlerts)
	if not runningScheduledCriteriaRefresh then
		Achievements.ScheduleCriteriaRefresh(showAlerts, 0.15, "direct");
		return;
	end
	RefreshCriteriaAchievementIDs(GetAllAchievementIDs(), showAlerts, "all");
end

function Achievements.RefreshCriteriaAchievementsForCriteriaTypes(criteriaTypes, showAlerts)
	if not runningScheduledCriteriaRefresh then
		Achievements.ScheduleCriteriaTypeRefresh(criteriaTypes, showAlerts, 0.15, "criteria-type");
		return;
	end
	local normalizedTypes = {};
	if type(criteriaTypes) == "table" then
		for key, value in pairs(criteriaTypes) do
			local criteriaType = tonumber(value) or (value == true and tonumber(key));
			if criteriaType then
				normalizedTypes[criteriaType] = true;
			end
		end
	else
		criteriaTypes = tonumber(criteriaTypes);
		if criteriaTypes then
			normalizedTypes[criteriaTypes] = true;
		end
	end
	RefreshCriteriaAchievementIDs(BuildAchievementIDListForCriteriaTypes(normalizedTypes), showAlerts, "criteria-types");
end

function Achievements.ScheduleCriteriaRefresh(showAlerts, delay, reason)
	if showAlerts then
		pendingCriteriaRefreshShowAlerts = true;
	end
	pendingCriteriaRefreshFull = true;
	AddCriteriaRefreshReason(reason);
	if pendingCriteriaRefresh then
		DebugCriteria("refresh coalesced reason=" .. tostring(reason or "?") .. " showAlerts=" .. tostring(showAlerts == true));
		return;
	end
	pendingCriteriaRefresh = true;
	local function RunScheduledCriteriaRefresh()
		local scheduledShowAlerts = pendingCriteriaRefreshShowAlerts == true;
		local scheduledFull = pendingCriteriaRefreshFull == true;
		local scheduledTypes = pendingCriteriaRefreshTypes;
		local reasons = table.concat(pendingCriteriaRefreshReasons, ",");
		pendingCriteriaRefresh = nil;
		pendingCriteriaRefreshFull = nil;
		pendingCriteriaRefreshShowAlerts = nil;
		pendingCriteriaRefreshReasons = {};
		pendingCriteriaRefreshTypes = nil;
		DebugCriteria("scheduled refresh run showAlerts=" .. tostring(scheduledShowAlerts) .. " reasons=" .. tostring(reasons));
		runningScheduledCriteriaRefresh = true;
		if scheduledFull or not scheduledTypes then
			Achievements.RefreshCriteriaAchievements(scheduledShowAlerts);
		else
			Achievements.RefreshCriteriaAchievementsForCriteriaTypes(scheduledTypes, scheduledShowAlerts);
		end
		runningScheduledCriteriaRefresh = nil;
	end
	C_Timer.After(delay or 0.15, RunScheduledCriteriaRefresh);
end

function Achievements.ScheduleCriteriaTypeRefresh(criteriaTypes, showAlerts, delay, reason)
	if showAlerts then
		pendingCriteriaRefreshShowAlerts = true;
	end
	AddCriteriaRefreshTypes(criteriaTypes);
	AddCriteriaRefreshReason(reason);
	if pendingCriteriaRefresh then
		DebugCriteria("refresh coalesced reason=" .. tostring(reason or "?") .. " showAlerts=" .. tostring(showAlerts == true));
		return;
	end
	pendingCriteriaRefresh = true;
	local function RunScheduledCriteriaRefresh()
		local scheduledShowAlerts = pendingCriteriaRefreshShowAlerts == true;
		local scheduledFull = pendingCriteriaRefreshFull == true;
		local scheduledTypes = pendingCriteriaRefreshTypes;
		local reasons = table.concat(pendingCriteriaRefreshReasons, ",");
		pendingCriteriaRefresh = nil;
		pendingCriteriaRefreshFull = nil;
		pendingCriteriaRefreshShowAlerts = nil;
		pendingCriteriaRefreshReasons = {};
		pendingCriteriaRefreshTypes = nil;
		DebugCriteria("scheduled refresh run showAlerts=" .. tostring(scheduledShowAlerts) .. " reasons=" .. tostring(reasons));
		runningScheduledCriteriaRefresh = true;
		if scheduledFull or not scheduledTypes then
			Achievements.RefreshCriteriaAchievements(scheduledShowAlerts);
		else
			Achievements.RefreshCriteriaAchievementsForCriteriaTypes(scheduledTypes, scheduledShowAlerts);
		end
		runningScheduledCriteriaRefresh = nil;
	end
	C_Timer.After(delay or 0.15, RunScheduledCriteriaRefresh);
end

function Achievements.GetSummaryAchievementIDs()
	local summaryAchievementIDs = {};
	for achievementID, achievement in pairs(ACHIEVEMENT_DATA) do
		local criteriaTreeIDs = CRITERIA_BY_ACHIEVEMENT[achievementID];
		if criteriaTreeIDs and #criteriaTreeIDs == 1 and not Private.IsFeatOfStrengthAchievement(achievement) and not Private.IsStatisticAchievement(achievement) and Private.ShouldShowAchievementInUI(achievementID) then
			local criteriaTree = CRITERIA_TREE_DATA[criteriaTreeIDs[1]];
			local criteria = criteriaTree and CRITERIA_DATA[criteriaTree.criteriaID];
			if criteria and criteria.type == CRITERIA_TYPE_REACH_LEVEL and Private.IsAchievementForPlayerFaction(achievement) then
				tinsert(summaryAchievementIDs, achievementID);
			end
		end
	end

	table.sort(summaryAchievementIDs, function(leftID, rightID)
		local left = ACHIEVEMENT_DATA[leftID];
		local right = ACHIEVEMENT_DATA[rightID];
		return (left.sort or leftID) < (right.sort or rightID);
	end);

	while #summaryAchievementIDs > 5 do
		tremove(summaryAchievementIDs);
	end

	return summaryAchievementIDs;
end