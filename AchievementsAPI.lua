local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsAPI.lua");
end

-- IMPORTANT: never overwrite a global that the client already provides natively.
-- On TBC 2.5.6 these globals are native and are read by Blizzard's PROTECTED code
-- (e.g. UpdateMicroButtons reads HasCompletedAnyAchievement/CanShowAchievementUI
-- during GameMenu OnShow). Assigning them from this insecure addon taints the
-- native global, which propagates into the Logout callback and triggers
-- ADDON_ACTION_FORBIDDEN. On Classic Era these globals do not exist, so we define
-- them there. Guard every assignment on native absence.
-- Forever has the native achievement API; only define what the client lacks.
local FOREVER = Achievements.IS_FOREVER;
local function DefineAPI(name)
	return not FOREVER or type(rawget(_G, name)) ~= "function";
end

if not BINDING_HEADER_ACHIEVEMENTS then
	BINDING_HEADER_ACHIEVEMENTS = "Achievements";
end
if not BINDING_NAME_TOGGLEACHIEVEMENT then
	BINDING_NAME_TOGGLEACHIEVEMENT = "Toggle Achievement Frame";
end
if not BINDING_NAME_TOGGLESTATISTICS then
	BINDING_NAME_TOGGLESTATISTICS = "Toggle Statistics Frame";
end

if type(_G.CanShowAchievementUI) ~= "function" then
	function CanShowAchievementUI()
		return Achievements.CanShowAchievementUI();
	end
end

if type(_G.HasCompletedAnyAchievement) ~= "function" then
	function HasCompletedAnyAchievement()
		return Achievements.HasCompletedAnyAchievement();
	end
end

if DefineAPI("GetCategoryList") then
function GetCategoryList()
	return Achievements.GetCategoryList();
end
end

if DefineAPI("GetStatisticsCategoryList") then
function GetStatisticsCategoryList()
	return Achievements.GetStatisticsCategoryList();
end
end

if DefineAPI("GetGuildCategoryList") then
function GetGuildCategoryList()
	return Achievements.GetGuildCategoryList();
end
end

if DefineAPI("GetCategoryInfo") then
function GetCategoryInfo(categoryID)
	return Achievements.GetCategoryInfo(categoryID);
end
end

if DefineAPI("GetCategoryNumAchievements") then
function GetCategoryNumAchievements(categoryID, showAll)
	return Achievements.GetCategoryNumAchievements(categoryID, showAll);
end
end

if DefineAPI("GetNumCompletedAchievements") then
function GetNumCompletedAchievements()
	return Achievements.GetNumCompletedAchievements();
end
end

if DefineAPI("GetTotalAchievementPoints") then
function GetTotalAchievementPoints()
	return Achievements.GetTotalAchievementPoints();
end
end

if DefineAPI("GetAchievementInfo") then
function GetAchievementInfo(categoryOrAchievementID, index)
	return Achievements.GetAchievementInfo(categoryOrAchievementID, index);
end
end

if DefineAPI("GetAchievementCategory") then
function GetAchievementCategory(achievementID)
	return Achievements.GetAchievementCategory(achievementID);
end
end

if DefineAPI("GetAchievementInstance") then
function GetAchievementInstance(achievementID)
	return Achievements.GetAchievementInstance(achievementID);
end
end

if DefineAPI("GetAchievementsByInstance") then
function GetAchievementsByInstance(instanceID)
	return Achievements.GetAchievementsByInstance(instanceID);
end
end

if DefineAPI("GetPreviousAchievement") then
function GetPreviousAchievement(achievementID)
	return Achievements.GetPreviousAchievement(achievementID);
end
end

if DefineAPI("GetNextAchievement") then
function GetNextAchievement(achievementID)
	return Achievements.GetNextAchievement(achievementID);
end
end

if DefineAPI("GetAchievementNumCriteria") then
function GetAchievementNumCriteria(achievementID)
	return Achievements.GetAchievementNumCriteria(achievementID);
end
end

if DefineAPI("GetAchievementCriteriaInfo") then
function GetAchievementCriteriaInfo(achievementID, criteriaIndex)
	return Achievements.GetAchievementCriteriaInfo(achievementID, criteriaIndex);
end
end

if DefineAPI("GetAchievementInfoFromCriteria") then
function GetAchievementInfoFromCriteria(criteriaID)
	return Achievements.GetAchievementInfoFromCriteria(criteriaID);
end
end

if DefineAPI("GetLatestCompletedAchievements") then
function GetLatestCompletedAchievements()
	return Achievements.GetLatestCompletedAchievements();
end
end

if DefineAPI("GetLatestUpdatedStats") then
function GetLatestUpdatedStats()
	return Achievements.GetLatestUpdatedStats();
end
end

if DefineAPI("GetLatestCompletedComparisonAchievements") then
function GetLatestCompletedComparisonAchievements()
	return Achievements.GetLatestCompletedComparisonAchievements();
end
end

if DefineAPI("GetStatistic") then
function GetStatistic(categoryOrStatisticID, index)
	return Achievements.GetStatistic(categoryOrStatisticID, index);
end
end

if DefineAPI("GetAchievementLink") then
function GetAchievementLink(achievementID)
	return Achievements.GetAchievementLink(achievementID);
end
end

if DefineAPI("GetTrackedAchievements") then
function GetTrackedAchievements()
	return Achievements.GetTrackedAchievements();
end
end

if DefineAPI("GetNumTrackedAchievements") then
function GetNumTrackedAchievements()
	return Achievements.GetNumTrackedAchievements();
end
end

if DefineAPI("AddTrackedAchievement") then
function AddTrackedAchievement(achievementID)
	return Achievements.AddTrackedAchievement(achievementID);
end
end

if DefineAPI("RemoveTrackedAchievement") then
function RemoveTrackedAchievement(achievementID)
	return Achievements.RemoveTrackedAchievement(achievementID);
end
end

if DefineAPI("IsTrackedAchievement") then
function IsTrackedAchievement(achievementID)
	return Achievements.IsTrackedAchievement(achievementID);
end
end

if DefineAPI("SetAchievementComparisonUnit") then
function SetAchievementComparisonUnit(unit)
	return Achievements.SetAchievementComparisonUnit(unit);
end
end

if DefineAPI("ClearAchievementComparisonUnit") then
function ClearAchievementComparisonUnit()
	return Achievements.ClearAchievementComparisonUnit();
end
end

if DefineAPI("GetComparisonAchievementPoints") then
function GetComparisonAchievementPoints()
	return Achievements.GetComparisonAchievementPoints();
end
end

if DefineAPI("GetAchievementComparisonInfo") then
function GetAchievementComparisonInfo(achievementID)
	return Achievements.GetAchievementComparisonInfo(achievementID);
end
end

if DefineAPI("GetComparisonCategoryNumAchievements") then
function GetComparisonCategoryNumAchievements(categoryID)
	return Achievements.GetComparisonCategoryNumAchievements(categoryID);
end
end

if DefineAPI("GetComparisonStatistic") then
function GetComparisonStatistic(categoryOrStatisticID, index)
	return Achievements.GetComparisonStatistic(categoryOrStatisticID, index);
end
end

if DefineAPI("GetAchievementGuildRep") then
function GetAchievementGuildRep(achievementID)
	return Achievements.GetAchievementGuildRep(achievementID);
end
end

if DefineAPI("GetGuildAchievementNumMembers") then
function GetGuildAchievementNumMembers(achievementID)
	return Achievements.GetGuildAchievementNumMembers(achievementID);
end
end

if DefineAPI("GetGuildAchievementMembers") then
function GetGuildAchievementMembers(achievementID)
	return Achievements.GetGuildAchievementMembers(achievementID);
end
end

if DefineAPI("GetGuildAchievementMemberInfo") then
function GetGuildAchievementMemberInfo(achievementID, index)
	return Achievements.GetGuildAchievementMemberInfo(achievementID, index);
end
end

if DefineAPI("AchievementFrame_LoadUI") then
function AchievementFrame_LoadUI()
	return Achievements.AchievementFrame_LoadUI();
end
end

if DefineAPI("ToggleAchievementFrame") then
function ToggleAchievementFrame(showStats)
	return Achievements.ToggleAchievementFrame(showStats);
end
end

if DefineAPI("AchievementMicroButton_Update") then
function AchievementMicroButton_Update()
	return Achievements.AchievementMicroButton_Update();
end
end

-- WatchFrame_Update / QuestWatch_Update are native on TBC and read by Blizzard's
-- protected code. Replacing the global would taint the native and break logout, so
-- append via hooksecurefunc when the native exists (taint-free). On Era, where the
-- native may be absent, fall back to defining/replacing the global.
local secureHook = rawget(_G, "hooksecurefunc");
if type(_G.WatchFrame_Update) == "function" and secureHook then
	secureHook("WatchFrame_Update", function()
		Achievements.WatchFrame_Update();
	end);
elseif not FOREVER then
	local originalWatchFrame_Update = WatchFrame_Update;
	function WatchFrame_Update(...)
		if originalWatchFrame_Update then
			originalWatchFrame_Update(...);
		end

		return Achievements.WatchFrame_Update();
	end
end

if type(_G.QuestWatch_Update) == "function" and secureHook then
	secureHook("QuestWatch_Update", function()
		Achievements.WatchFrame_Update();
	end);
end
