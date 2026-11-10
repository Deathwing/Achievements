-- This file is executed at the end of addon load

function AchievementsFrameSummary_LocalizeButton (button)

end

function AchievementsButton_LocalizeMiniAchievement (frame)

end

function AchievementsButton_LocalizeProgressBar (frame)

end

function AchievementsButton_LocalizeMetaAchievement (frame)

end

function AchievementsFrame_LocalizeCriteria (frame)

end

function AchievementsCategoryButton_Localize(button)

end

local l10nTable = {
	deDE = {},
	enGB = {},
	enUS = {},
	esES = {},
	esMX = {},
	frFR = {},
	itIT = {},
	koKR = {},
	ptBR = {},
	ptPT = {},
	ruRU = {},
	zhCN = {},
	zhTW = {
		localize = function()
			AchievementsFrameSummary_LocalizeButton = function(button)
				button.label:SetPoint("TOP", 0, -4);
				button.description:SetPoint("TOP", 0, -27);
				button.description:SetFontObject("AchievementFont_Small");
				button.shield.points:SetPoint("CENTER", -1, 4);
			end

			AchievementsButton_LocalizeMiniAchievement = function(frame)
				frame.points:SetFontObject("GameFontWhite");
			end

			AchievementsButton_LocalizeProgressBar = function(frame)
				frame.text:SetPoint("TOP", 0, 1);
			end

			AchievementsButton_LocalizeMetaAchievement = function(frame)
				frame.label:SetFontObject("AchievementFont_Small");
			end

			AchievementsFrame_LocalizeCriteria = function(frame)
				frame.name:SetFontObject("AchievementFont_Small");
			end

			AchievementsButton_Localize = function(button)
				button.description:SetFontObject("AchievementFont_Small");
				button.hiddenDescription:SetFontObject("AchievementFont_Small");
				button.shield:SetPoint("TOPRIGHT", -10, 0);
			end

			ACHIEVEMENTSCOMPARISON_FRIENDSHIELDFONT1 = GameFontBlack;
			ACHIEVEMENTSCOMPARISON_FRIENDSHIELDFONT2 = GameFontBlack;

			AchievementsComparisonButton_Localize = function(button)
				button.player.label:SetPoint("TOP", 0, -4);
				button.player.description:SetPoint("TOP", 0, -27);
				button.player.description:SetFontObject("AchievementFont_Small");
				button.friend.status:SetFontObject("GameFontBlack");
				button.friend.status:SetPoint("BOTTOM", 20, 4);
				button.friend.shield.points:SetFontObject("GameFontBlack");
			end

			for _, button in next, AchievementsFrameAchievementsContainer.buttons do
				AchievementsButton_Localize(button);
			end

			for _, button in next, AchievementsFrameComparisonContainer.buttons do
				AchievementsComparisonButton_Localize(button);
			end
		end,
	},
};

-- Not SetupLocalization: Blizzard replays it inside VARIABLES_LOADED and taints the handler.
do
	local entry = l10nTable[GetLocale()];
	if entry and type(entry.localize) == "function" then
		local ok, message = pcall(entry.localize);
		if not ok and DEFAULT_CHAT_FRAME then
			DEFAULT_CHAT_FRAME:AddMessage("Achievements: localization failed: " .. tostring(message));
		end
	end
end
