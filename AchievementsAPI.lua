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

function GetCategoryList()
	return Achievements.GetCategoryList();
end

function GetStatisticsCategoryList()
	return Achievements.GetStatisticsCategoryList();
end

function GetGuildCategoryList()
	return Achievements.GetGuildCategoryList();
end

function GetCategoryInfo(categoryID)
	return Achievements.GetCategoryInfo(categoryID);
end

function GetCategoryNumAchievements(categoryID, showAll)
	return Achievements.GetCategoryNumAchievements(categoryID, showAll);
end

function GetNumCompletedAchievements()
	return Achievements.GetNumCompletedAchievements();
end

function GetTotalAchievementPoints()
	return Achievements.GetTotalAchievementPoints();
end

function GetAchievementInfo(categoryOrAchievementID, index)
	return Achievements.GetAchievementInfo(categoryOrAchievementID, index);
end

function GetAchievementCategory(achievementID)
	return Achievements.GetAchievementCategory(achievementID);
end

function GetAchievementInstance(achievementID)
	return Achievements.GetAchievementInstance(achievementID);
end

function GetAchievementsByInstance(instanceID)
	return Achievements.GetAchievementsByInstance(instanceID);
end

function GetPreviousAchievement(achievementID)
	return Achievements.GetPreviousAchievement(achievementID);
end

function GetNextAchievement(achievementID)
	return Achievements.GetNextAchievement(achievementID);
end

function GetAchievementNumCriteria(achievementID)
	return Achievements.GetAchievementNumCriteria(achievementID);
end

function GetAchievementCriteriaInfo(achievementID, criteriaIndex)
	return Achievements.GetAchievementCriteriaInfo(achievementID, criteriaIndex);
end

function GetAchievementInfoFromCriteria(criteriaID)
	return Achievements.GetAchievementInfoFromCriteria(criteriaID);
end

function GetLatestCompletedAchievements()
	return Achievements.GetLatestCompletedAchievements();
end

function GetLatestUpdatedStats()
	return Achievements.GetLatestUpdatedStats();
end

function GetLatestCompletedComparisonAchievements()
	return Achievements.GetLatestCompletedComparisonAchievements();
end

function GetStatistic(categoryOrStatisticID, index)
	return Achievements.GetStatistic(categoryOrStatisticID, index);
end

function GetAchievementLink(achievementID)
	return Achievements.GetAchievementLink(achievementID);
end

function GetTrackedAchievements()
	return Achievements.GetTrackedAchievements();
end

function GetNumTrackedAchievements()
	return Achievements.GetNumTrackedAchievements();
end

function AddTrackedAchievement(achievementID)
	return Achievements.AddTrackedAchievement(achievementID);
end

function RemoveTrackedAchievement(achievementID)
	return Achievements.RemoveTrackedAchievement(achievementID);
end

function IsTrackedAchievement(achievementID)
	return Achievements.IsTrackedAchievement(achievementID);
end

function SetAchievementComparisonUnit(unit)
	return Achievements.SetAchievementComparisonUnit(unit);
end

function ClearAchievementComparisonUnit()
	return Achievements.ClearAchievementComparisonUnit();
end

function GetComparisonAchievementPoints()
	return Achievements.GetComparisonAchievementPoints();
end

function GetAchievementComparisonInfo(achievementID)
	return Achievements.GetAchievementComparisonInfo(achievementID);
end

function GetComparisonCategoryNumAchievements(categoryID)
	return Achievements.GetComparisonCategoryNumAchievements(categoryID);
end

function GetComparisonStatistic(categoryOrStatisticID, index)
	return Achievements.GetComparisonStatistic(categoryOrStatisticID, index);
end

function GetAchievementGuildRep(achievementID)
	return Achievements.GetAchievementGuildRep(achievementID);
end

function GetGuildAchievementNumMembers(achievementID)
	return Achievements.GetGuildAchievementNumMembers(achievementID);
end

function GetGuildAchievementMembers(achievementID)
	return Achievements.GetGuildAchievementMembers(achievementID);
end

function GetGuildAchievementMemberInfo(achievementID, index)
	return Achievements.GetGuildAchievementMemberInfo(achievementID, index);
end

function AchievementFrame_LoadUI()
	return Achievements.AchievementFrame_LoadUI();
end

function ToggleAchievementFrame(showStats)
	return Achievements.ToggleAchievementFrame(showStats);
end

function AchievementMicroButton_Update()
	return Achievements.AchievementMicroButton_Update();
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
else
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
