local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsWatchFrame.lua");
end

local Private = Achievements.private;
local ACHIEVEMENT_DATA = Private.data.achievements;
local trackedAchievements = Private.state.trackedAchievements;
local ACHIEVEMENT_WATCH_MAX_LINES = Private.ACHIEVEMENT_WATCH_MAX_LINES;

local achievementWatchFrame;

local function EnsureAchievementWatchFrame()
	if achievementWatchFrame then
		return achievementWatchFrame;
	end

	if not CreateFrame or not UIParent then
		return nil;
	end

	local frame = CreateFrame("Frame", "AchievementsWatchFrame", UIParent);
	frame:SetWidth(240);
	frame:SetHeight(1);
	frame:SetFrameStrata("HIGH");
	if frame.SetFrameLevel then
		frame:SetFrameLevel(20);
	end
	if frame.SetClampedToScreen then
		frame:SetClampedToScreen(true);
	end
	if frame.SetToplevel then
		frame:SetToplevel(true);
	end
	frame.lines = {};
	frame:Hide();

	achievementWatchFrame = frame;
	return frame;
end

local function AnchorBelowVisibleFrame(frame, anchor, xOffset, yOffset)
	if not anchor or (anchor.IsShown and not anchor:IsShown()) or not anchor.GetRight or not anchor:GetRight() then
		return false;
	end

	frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", xOffset or 0, yOffset or -12);
	return true;
end

local function AnchorAchievementWatchFrame(frame)
	frame:ClearAllPoints();
	if AnchorBelowVisibleFrame(frame, ObjectiveTrackerFrame, -8, -8) then
		return;
	end
	if AnchorBelowVisibleFrame(frame, QuestWatchFrame, 0, -12) then
		return;
	end
	if AnchorBelowVisibleFrame(frame, WatchFrame, 0, -12) then
		return;
	end
	if AnchorBelowVisibleFrame(frame, MinimapCluster, -8, -35) then
		return;
	end

	frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -80, -260);
end

local function GetAchievementWatchLine(frame, lineIndex)
	local line = frame.lines[lineIndex];
	if line then
		return line;
	end

	line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	line:SetJustifyH("LEFT");
	line:SetJustifyV("TOP");
	line:SetWidth(230);
	line:SetHeight(14);
	line:SetNonSpaceWrap(true);
	if line.SetShadowOffset then
		line:SetShadowOffset(1, -1);
		line:SetShadowColor(0, 0, 0, 1);
	end
	if lineIndex == 1 then
		line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0);
	else
		line:SetPoint("TOPLEFT", frame.lines[lineIndex - 1], "BOTTOMLEFT", 0, -2);
	end

	frame.lines[lineIndex] = line;
	return line;
end

local function SetAchievementWatchLine(frame, lineIndex, text, red, green, blue)
	local line = GetAchievementWatchLine(frame, lineIndex);
	line:SetText(text or "");
	line:SetTextColor(red, green, blue);
	line:Show();
	return lineIndex + 1;
end

function Achievements.WatchFrame_Update()
	local frame = EnsureAchievementWatchFrame();
	if not frame then
		return;
	end

	local trackedIDs = {};
	for achievementID in pairs(trackedAchievements) do
		if not ACHIEVEMENT_DATA[achievementID] or not Private.ShouldShowAchievementInUI(achievementID) or Private.IsAchievementCompleted(achievementID) then
			trackedAchievements[achievementID] = nil;
		else
			tinsert(trackedIDs, achievementID);
		end
	end

	table.sort(trackedIDs);
	AnchorAchievementWatchFrame(frame);

	if #trackedIDs == 0 then
		for _, line in ipairs(frame.lines) do
			line:Hide();
		end
		frame:Hide();
		return;
	end

	local lineIndex = 1;
	for _, achievementID in ipairs(trackedIDs) do
		if lineIndex > ACHIEVEMENT_WATCH_MAX_LINES then
			break;
		end

		local achievement = ACHIEVEMENT_DATA[achievementID];
		lineIndex = SetAchievementWatchLine(frame, lineIndex, achievement.name, 1, 0.82, 0);

		local numCriteria = Achievements.GetAchievementNumCriteria(achievementID);
		if numCriteria == 0 then
			lineIndex = SetAchievementWatchLine(frame, lineIndex, "  " .. (achievement.description or ""), 0.85, 0.85, 0.85);
		else
			for criteriaIndex = 1, numCriteria do
				if lineIndex >= ACHIEVEMENT_WATCH_MAX_LINES then
					lineIndex = SetAchievementWatchLine(frame, lineIndex, "  ...", 0.85, 0.85, 0.85);
					break;
				end

				local criteriaString, _, completed, quantity, requiredQuantity, _, _, _, quantityString = Achievements.GetAchievementCriteriaInfo(achievementID, criteriaIndex);
				if criteriaString and criteriaString ~= "" then
					-- Blizzard objective-tracker format: "- 93/250 Complete 250 quests."
					-- (dash prefix, current/required count first, criteria text after).
					local prefix = "- ";
					if requiredQuantity and requiredQuantity > 1 then
						if quantityString and quantityString ~= "" then
							prefix = "- " .. quantityString .. " ";
						elseif quantity then
							prefix = string.format("- %d/%d ", quantity, requiredQuantity);
						end
					end
					local text = prefix .. criteriaString;

					if completed then
						lineIndex = SetAchievementWatchLine(frame, lineIndex, text, 0.55, 0.9, 0.55);
					else
						lineIndex = SetAchievementWatchLine(frame, lineIndex, text, 1, 1, 1);
					end
				end
			end
		end

		if lineIndex <= ACHIEVEMENT_WATCH_MAX_LINES then
			lineIndex = SetAchievementWatchLine(frame, lineIndex, " ", 1, 1, 1);
		end
	end

	for index = lineIndex, #frame.lines do
		frame.lines[index]:Hide();
	end

	frame:SetHeight(math.max(1, (lineIndex - 1) * 16));
	frame:Show();
	if frame.Raise then
		frame:Raise();
	end
end
