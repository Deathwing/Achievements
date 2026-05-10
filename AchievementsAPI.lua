local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsAPI.lua");
end

BINDING_HEADER_ACHIEVEMENTS = "Achievements";
BINDING_NAME_TOGGLEACHIEVEMENT = "Toggle Achievement Frame";
BINDING_NAME_TOGGLESTATISTICS = "Toggle Statistics Frame";

function CanShowAchievementUI()
	return Achievements.CanShowAchievementUI();
end

function HasCompletedAnyAchievement()
	return Achievements.HasCompletedAnyAchievement();
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

local originalWatchFrame_Update = WatchFrame_Update;
function WatchFrame_Update(...)
	if originalWatchFrame_Update then
		originalWatchFrame_Update(...);
	end

	return Achievements.WatchFrame_Update();
end

local originalQuestWatch_Update = QuestWatch_Update;
if originalQuestWatch_Update then
	function QuestWatch_Update(...)
		local result = originalQuestWatch_Update(...);
		Achievements.WatchFrame_Update();
		return result;
	end
end
