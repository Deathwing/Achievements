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

local MODULE_WIDTH = 260;
local HEADER_HEIGHT = 25;
local FROM_HEADER_OFFSET_Y = 10;
local BLOCK_OFFSET_X = 20;
local FROM_BLOCK_OFFSET_Y = 10;
local LINE_SPACING = 4;
local MAX_CRITERIA_PER_ACHIEVEMENT = 5;

local moduleFrame;
local moduleCollapsed = false;

local function IsModernTracker()
	return ObjectiveTrackerFrame ~= nil and type(ObjectiveTrackerFrame.modules) == "table" and ObjectiveTrackerFrame.moduleSpacing ~= nil;
end

local function TrackerFont(name, fallback)
	return _G[name] and name or fallback;
end

local function TrackerColor(key, r, g, b)
	local color = OBJECTIVE_TRACKER_COLOR and OBJECTIVE_TRACKER_COLOR[key];
	if color then
		return color.r, color.g, color.b;
	end
	return r, g, b;
end

local function UpdateMinimizeButton(button)
	local suffix = moduleCollapsed and "expand" or "collapse";
	pcall(button.SetNormalAtlas, button, "ui-questtrackerbutton-secondary-" .. suffix, true);
	pcall(button.SetPushedAtlas, button, "ui-questtrackerbutton-secondary-" .. suffix .. "-pressed", true);
end

local function AnchorModuleFrame(frame)
	local container = ObjectiveTrackerFrame;
	local last;
	for _, module in ipairs(container.modules) do
		if module.GetContentsHeight and module:IsShown() and module:GetContentsHeight() > 0 then
			last = module;
		end
	end
	frame:ClearAllPoints();
	if last then
		frame:SetPoint("TOP", last, "BOTTOM", 0, -(container.moduleSpacing or 10));
	else
		frame:SetPoint("TOP", container, "TOP", 0, -(container.topModulePadding or 0));
	end
	frame:SetPoint("LEFT", container, "LEFT", 0, 0);
	if container.isCollapsed then
		frame:Hide();
	elseif frame.hasContents then
		frame:Show();
	end
end

local function EnsureModuleFrame()
	if moduleFrame then
		return moduleFrame;
	end

	local frame = CreateFrame("Frame", "AchievementsWatchFrame", UIParent);
	frame:SetSize(MODULE_WIDTH, HEADER_HEIGHT);
	frame:SetFrameStrata(ObjectiveTrackerFrame:GetFrameStrata());
	frame:SetFrameLevel(ObjectiveTrackerFrame:GetFrameLevel() + 5);
	frame.blocks = {};
	frame:Hide();

	local header = CreateFrame("Frame", nil, frame);
	header:SetSize(MODULE_WIDTH, 26);
	header:SetPoint("TOPLEFT");
	local background = header:CreateTexture(nil, "BACKGROUND");
	background:SetPoint("CENTER");
	if not pcall(background.SetAtlas, background, "UI-QuestTracker-Secondary-Objective-Header", true) then
		background:Hide();
	end
	local text = header:CreateFontString(nil, "ARTWORK", TrackerFont("ObjectiveTrackerHeaderFont", "GameFontNormal"));
	text:SetPoint("LEFT", 7, 0);
	text:SetWidth(200);
	text:SetJustifyH("LEFT");
	text:SetText(TRACKER_HEADER_ACHIEVEMENTS or "Achievements");
	local minimize = CreateFrame("Button", nil, header);
	minimize:SetSize(16, 16);
	minimize:SetPoint("RIGHT", 1, 0);
	pcall(minimize.SetHighlightAtlas, minimize, "ui-questtrackerbutton-yellow-highlight", "ADD");
	UpdateMinimizeButton(minimize);
	minimize:SetScript("OnClick", function()
		moduleCollapsed = not moduleCollapsed;
		UpdateMinimizeButton(minimize);
		Achievements.WatchFrame_Update();
	end);
	frame.Header = header;

	local function OnTrackerUpdate(container)
		if moduleFrame and container == ObjectiveTrackerFrame then
			AnchorModuleFrame(moduleFrame);
		end
	end
	if ObjectiveTrackerContainerMixin and type(ObjectiveTrackerContainerMixin.Update) == "function" then
		hooksecurefunc(ObjectiveTrackerContainerMixin, "Update", OnTrackerUpdate);
	else
		hooksecurefunc(ObjectiveTrackerFrame, "Update", OnTrackerUpdate);
	end

	moduleFrame = frame;
	return frame;
end

local function GetBlock(frame, index)
	local block = frame.blocks[index];
	if block then
		return block;
	end
	block = CreateFrame("Frame", nil, frame);
	block:SetWidth(MODULE_WIDTH - BLOCK_OFFSET_X);
	block.HeaderText = block:CreateFontString(nil, "ARTWORK", TrackerFont("ObjectiveTrackerLineFont", "GameFontHighlightSmall"));
	block.HeaderText:SetPoint("TOPLEFT");
	block.HeaderText:SetWidth(MODULE_WIDTH - BLOCK_OFFSET_X);
	block.HeaderText:SetJustifyH("LEFT");
	block.HeaderText:SetWordWrap(true);
	block.lines = {};
	frame.blocks[index] = block;
	return block;
end

local function GetLine(block, index)
	local line = block.lines[index];
	if line then
		return line;
	end
	line = CreateFrame("Frame", nil, block);
	line:SetWidth(MODULE_WIDTH - BLOCK_OFFSET_X);
	local font = TrackerFont("ObjectiveTrackerLineFont", "GameFontHighlightSmall");
	line.Dash = line:CreateFontString(nil, "ARTWORK", font);
	line.Dash:SetPoint("TOPLEFT", 0, 1);
	line.Dash:SetText(QUEST_DASH or "- ");
	line.Text = line:CreateFontString(nil, "ARTWORK", font);
	line.Text:SetPoint("TOPLEFT", line.Dash, "TOPRIGHT", 0, -1);
	line.Text:SetWidth(MODULE_WIDTH - BLOCK_OFFSET_X - line.Dash:GetStringWidth());
	line.Text:SetJustifyH("LEFT");
	line.Text:SetWordWrap(true);
	block.lines[index] = line;
	return line;
end

local function AddLine(block, lineIndex, anchor, text, completed)
	local line = GetLine(block, lineIndex);
	line:ClearAllPoints();
	line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -LINE_SPACING);
	line.Text:SetText(text);
	local r, g, b;
	if completed then
		r, g, b = TrackerColor("Complete", 0.6, 0.6, 0.6);
	else
		r, g, b = TrackerColor("Normal", 0.8, 0.8, 0.8);
	end
	line.Text:SetTextColor(r, g, b);
	line.Dash:SetTextColor(r, g, b);
	local height = math.max(line.Text:GetStringHeight(), line.Dash:GetStringHeight());
	line:SetHeight(height);
	line:Show();
	return line, height + LINE_SPACING;
end

local function CriteriaText(achievementID, criteriaIndex)
	local criteriaString, _, completed, quantity, requiredQuantity, _, _, _, quantityString = Achievements.GetAchievementCriteriaInfo(achievementID, criteriaIndex);
	if not criteriaString or criteriaString == "" then
		return nil;
	end
	if requiredQuantity and requiredQuantity > 1 then
		if quantityString and quantityString ~= "" then
			criteriaString = string.gsub(quantityString, " / ", "/") .. " " .. criteriaString;
		elseif quantity then
			criteriaString = string.format("%d/%d %s", quantity, requiredQuantity, criteriaString);
		end
	end
	return criteriaString, completed;
end

local function UpdateModuleFrame(trackedIDs)
	local frame = EnsureModuleFrame();
	frame.hasContents = #trackedIDs > 0;
	if not frame.hasContents then
		frame:Hide();
		return;
	end

	local y = HEADER_HEIGHT;
	local blockIndex = 0;
	if not moduleCollapsed then
		y = y + FROM_HEADER_OFFSET_Y;
		for _, achievementID in ipairs(trackedIDs) do
			blockIndex = blockIndex + 1;
			local achievement = ACHIEVEMENT_DATA[achievementID];
			local block = GetBlock(frame, blockIndex);
			block:ClearAllPoints();
			block:SetPoint("TOPLEFT", frame, "TOPLEFT", BLOCK_OFFSET_X, -y);
			block.HeaderText:SetText(achievement.name or "");
			block.HeaderText:SetTextColor(TrackerColor("Header", 1, 0.82, 0));
			local blockHeight = block.HeaderText:GetStringHeight();
			local anchor = block.HeaderText;
			local lineIndex = 0;

			local numCriteria = Achievements.GetAchievementNumCriteria(achievementID);
			if numCriteria == 0 then
				lineIndex = lineIndex + 1;
				local line, used = AddLine(block, lineIndex, anchor, achievement.description or "", false);
				anchor = line;
				blockHeight = blockHeight + used;
			else
				for criteriaIndex = 1, numCriteria do
					if lineIndex >= MAX_CRITERIA_PER_ACHIEVEMENT then
						lineIndex = lineIndex + 1;
						local line, used = AddLine(block, lineIndex, anchor, "...", false);
						anchor = line;
						blockHeight = blockHeight + used;
						break;
					end
					local text, completed = CriteriaText(achievementID, criteriaIndex);
					if text then
						lineIndex = lineIndex + 1;
						local line, used = AddLine(block, lineIndex, anchor, text, completed);
						anchor = line;
						blockHeight = blockHeight + used;
					end
				end
			end

			for index = lineIndex + 1, #block.lines do
				block.lines[index]:Hide();
			end
			block:SetHeight(blockHeight);
			block:Show();
			y = y + blockHeight + FROM_BLOCK_OFFSET_Y;
		end
		y = y - FROM_BLOCK_OFFSET_Y;
	end

	for index = blockIndex + 1, #frame.blocks do
		frame.blocks[index]:Hide();
	end
	frame:SetHeight(y);
	AnchorModuleFrame(frame);
end

local function CollectTrackedIDs()
	local trackedIDs = {};
	for achievementID in pairs(trackedAchievements) do
		if not ACHIEVEMENT_DATA[achievementID] or not Private.ShouldShowAchievementInUI(achievementID) or Private.IsAchievementCompleted(achievementID) then
			trackedAchievements[achievementID] = nil;
		else
			tinsert(trackedIDs, achievementID);
		end
	end
	table.sort(trackedIDs);
	return trackedIDs;
end

function Achievements.WatchFrame_Update()
	local trackedIDs = CollectTrackedIDs();
	if IsModernTracker() then
		UpdateModuleFrame(trackedIDs);
		return;
	end

	local frame = EnsureAchievementWatchFrame();
	if not frame then
		return;
	end
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
