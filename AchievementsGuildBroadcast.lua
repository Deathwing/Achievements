local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsGuildBroadcast.lua");
end

local Private = Achievements.private;

local ADDON_PREFIX = "ACHV";
local MESSAGE_VERSION = "2";

local prefixRegistered;
local listenerFrame;
local hookedSetItemRef;

local function RegisterPrefix()
	if prefixRegistered then
		return;
	end
	local ok = pcall(C_ChatInfo.RegisterAddonMessagePrefix, ADDON_PREFIX);
	if ok then
		prefixRegistered = true;
	end
end

local function SendAchievementAddonMessage(message, channel, target)
	return C_ChatInfo.SendAddonMessage(ADDON_PREFIX, message, channel, target);
end

local function NormaliseCompletionTimestamp(timestamp)
	timestamp = tonumber(timestamp);
	if not timestamp or timestamp <= 0 then
		return 0;
	end
	return math.floor(timestamp);
end

local function GetCompletionDateFromTimestamp(timestamp)
	timestamp = NormaliseCompletionTimestamp(timestamp);
	if timestamp == 1 then
		return 0, 0, 0;
	end
	if timestamp > 0 then
		local currentDate = date("*t", timestamp);
		if currentDate then
			return currentDate.month or 0, currentDate.day or 0, currentDate.year or 0;
		end
	end
	return 0, 0, 0;
end

local function GetCompletionTimestampFromDate(month, day, year)
	month = tonumber(month) or 0;
	day = tonumber(day) or 0;
	year = tonumber(year) or 0;
	if month <= 0 or day <= 0 or year <= 0 then
		return 0;
	end
	if year < 1000 then
		year = 2000 + year;
	end
	local ok, timestamp = pcall(time, { year = year, month = month, day = day, hour = 12 });
	if ok then
		return NormaliseCompletionTimestamp(timestamp);
	end
	return 0;
end

local function GetSavedCompletionTimestamp(achievementID)
	if not Private or not Private.GetSavedCompletions or not Private.GetSavedCompletionTimestamp then
		return 0;
	end
	local savedCompletions = Private.GetSavedCompletions(achievementID);
	local savedState = savedCompletions and savedCompletions[achievementID];
	return NormaliseCompletionTimestamp(Private.GetSavedCompletionTimestamp(savedState));
end

local function ResolveCompletionTimestamp(achievementID, completed, month, day, year)
	if not completed then
		return 0;
	end
	local savedTimestamp = GetSavedCompletionTimestamp(achievementID);
	if savedTimestamp > 0 then
		return savedTimestamp;
	end
	local timestamp = GetCompletionTimestampFromDate(month, day, year);
	if timestamp > 0 then
		return timestamp;
	end
	return 1;
end

-- Sends an addon-message on `channel` and immediately prints the formatted
-- message to the local player's own chat in the channel-appropriate colour.
-- SAY   → white in DEFAULT_CHAT_FRAME
-- GUILD → green in the guild-subscribed chat tab
local function Broadcast(achievementID, channel)
	local id = tonumber(achievementID);
	if not id then return end
	local playerName = UnitName("player") or "";
	local _, classFile = UnitClass("player");
	classFile = classFile or "";
	local _, _, _, completed, month, day, year = Achievements.GetAchievementInfo(id);
	local guid = UnitGUID("player") or "";
	local completionTimestamp = ResolveCompletionTimestamp(id, completed == true, month, day, year);
	RegisterPrefix();
	local payload = string.format("%s\t%d\t%s\t%s\t%d", MESSAGE_VERSION, id, classFile, guid, completionTimestamp);
	if Private.FormatAchievementBroadcast then
		local msg = Private.FormatAchievementBroadcast(playerName, classFile ~= "" and classFile or nil, id, completionTimestamp, guid);
		if channel == "SAY" then
			DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 1, 1);
		elseif channel == "GUILD" and Private.PrintToGuildOnly then
			Private.PrintToGuildOnly(msg);
		end
	end
	pcall(SendAchievementAddonMessage, payload, channel);
end

function Achievements.AnnounceAchievementToSay(achievementID)
	Broadcast(achievementID, "SAY");
	return true;
end

function Achievements.AnnounceAchievementToGuild(achievementID)
	if IsInGuild() then
		Broadcast(achievementID, "GUILD");
		return true;
	end
	return false;
end

-- Called from Achievements.lua when the local player earns a new achievement.
-- Broadcasts via SAY (all nearby players regardless of guild) and via GUILD
-- (remote guild members). Each Broadcast() call also self-prints in the
-- channel-appropriate colour so the earner sees it immediately.
function Achievements.AnnounceAchievement(achievementID)
	Achievements.AnnounceAchievementToSay(achievementID);
	Achievements.AnnounceAchievementToGuild(achievementID);
end

local function HandleIncomingBroadcast(payload, sender, channel)
	if type(payload) ~= "string" then
		return;
	end
	local version, idText, classFile, guid, completionTimestampText = strsplit("\t", payload);
	if version ~= MESSAGE_VERSION then
		return;
	end
	local id = tonumber(idText);
	if not id then
		return;
	end
	local completionTimestamp = NormaliseCompletionTimestamp(completionTimestampText);
	if completionTimestamp <= 0 then
		completionTimestamp = 1;
	end
	local displayName = Ambiguate(sender or "", "none") or sender or "";

	-- Don't echo our own broadcast back to ourselves; the local PrintMessage
	-- already handled it from MarkAchievementComplete.
	local localName = UnitName("player");
	local shortDisplayName = displayName;
	if shortDisplayName then
		shortDisplayName = Ambiguate(shortDisplayName, "none");
	end
	if localName and shortDisplayName and string.lower(shortDisplayName) == string.lower(localName) then
		return;
	end

	if not Private.FormatAchievementBroadcast then
		return;
	end
	local msg = Private.FormatAchievementBroadcast(displayName, classFile ~= "" and classFile or nil, id, completionTimestamp, guid or "");
	-- Route to the channel-appropriate colour.
	-- SAY broadcast   → white in default chat (same feel as a normal SAY message).
	-- GUILD broadcast → green in the guild-subscribed chat tab.
	if channel == "SAY" then
		DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 1, 1);
	else
		if Private.PrintToGuildOnly then
			Private.PrintToGuildOnly(msg);
		elseif Private.PrintToGuildChatFrames then
			Private.PrintToGuildChatFrames(msg);
		end
	end
end

local function EnsureListener()
	if listenerFrame then
		return;
	end
	listenerFrame = CreateFrame("Frame");
	listenerFrame:RegisterEvent("CHAT_MSG_ADDON");
	-- Used to drain the own-achievement queue once the guild channel is live.
	listenerFrame:RegisterEvent("CHAT_MSG_GUILD");
	listenerFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
	listenerFrame:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
		if event == "CHAT_MSG_GUILD" or event == "PLAYER_ENTERING_WORLD" then
			-- Unregister immediately so subsequent guild messages / zone changes
			-- don't keep firing (MarkGuildAnnouncementsReady is idempotent anyway).
			listenerFrame:UnregisterEvent("CHAT_MSG_GUILD");
			listenerFrame:UnregisterEvent("PLAYER_ENTERING_WORLD");
			local function drain()
				if Achievements.MarkGuildAnnouncementsReady then
					Achievements.MarkGuildAnnouncementsReady();
				end
			end
			if event == "CHAT_MSG_GUILD" then
				-- A real guild message arrived — channel is definitely ready.
				drain();
			else
				-- PLAYER_ENTERING_WORLD fires before the guild channel joins;
				-- wait a few seconds so PrintToGuildChatFrames lands correctly.
				C_Timer.After(5, drain);
			end
			return;
		end
		if event ~= "CHAT_MSG_ADDON" or prefix ~= ADDON_PREFIX then
			return;
		end
		if channel ~= "GUILD" and channel ~= "SAY" then
			return;
		end
		HandleIncomingBroadcast(message, sender, channel);
	end);
end

-- SetItemRef hook: route clicks on |Hachievement:...|h links to the
-- ItemRefTooltip popup (matching retail behaviour) instead of letting the
-- default handler raise "Unknown link type" or opening the full UI.

local function SplitAchievementLinkFields(fullLink)
	local linkData = type(fullLink) == "string" and (fullLink:match("|Hachievement:([^|]+)|h") or fullLink:match("^achievement:(.+)$"));
	if not linkData then
		return nil;
	end
	local fields = {};
	for field in (linkData .. ":"):gmatch("([^:]*):") do
		fields[#fields + 1] = field;
	end
	return fields;
end

-- Parse the per-link payload appended after the achievement id. Format:
--   |Hachievement:ID:GUID:completionTimestamp[:playerName[:criteriaProgress]]|h
-- Returns playerName, completed (bool), month, day, year (4-digit), hasPayload, criteriaProgress.
local function ParseAchievementLinkPayload(fullLink)
	local fields = SplitAchievementLinkFields(fullLink);
	if not fields then
		return nil;
	end
	local guid, completionTimestampText = fields[2], fields[3];
	if not completionTimestampText then
		return nil;
	end
	local playerName = fields[4];
	local criteriaProgress = fields[5];
	if playerName == "" then
		playerName = nil;
	end
	if guid and guid ~= "" and guid ~= "0" then
		local ok, name = pcall(function()
			return select(6, GetPlayerInfoByGUID(guid));
		end);
		if ok and type(name) == "string" and name ~= "" then
			playerName = name;
		end
	end
	local completionTimestamp = NormaliseCompletionTimestamp(completionTimestampText);
	local month, day, year = GetCompletionDateFromTimestamp(completionTimestamp);
	return playerName, completionTimestamp > 0, month, day, year, true, criteriaProgress;
end

local function GetShortPlayerName(name)
	if type(name) ~= "string" or name == "" then
		return nil;
	end
	local shortName = Ambiguate(name, "short");
	if shortName and shortName ~= "" then
		return shortName;
	end
	return name:match("^([^%-]+)") or name;
end

local function IsLocalPlayerName(name)
	local localName = UnitName("player");
	local shortName = GetShortPlayerName(name);
	return localName and shortName and string.lower(localName) == string.lower(shortName);
end

local function AddCompletedByLine(tooltip, playerName, month, day, year)
	local fmt = _G.ACHIEVEMENT_TOOLTIP_COMPLETE
		or "Achievement earned by %1$s on %2$d/%3$02d/20%4$02d";
	tooltip:AddLine(format(fmt, playerName, month or 0, day or 0, (year or 0) % 100), 0, 1, 0);
end

local function AddCompletedByLineWithoutDate(tooltip, playerName)
	tooltip:AddLine("Achievement earned by " .. tostring(playerName or ""), 0, 1, 0);
end

local function AddLocalComparisonLine(tooltip, completed, month, day, year)
	if completed then
		local fmt = _G.ACHIEVEMENT_COMPARISON_COMPLETED
			or "|A:achievementcompare-GreenCheckmark:0:0|a You completed this on %1$d/%2$02d/20%3$02d";
		tooltip:AddLine(format(fmt, month or 0, day or 0, (year or 0) % 100), 0, 1, 0);
	else
		tooltip:AddLine(_G.ACHIEVEMENT_COMPARISON_NOT_COMPLETED or "You have not completed this achievement", 0.6, 0.6, 0.6);
	end
end

local function GetCriteriaProgressPayloadValue(criteriaProgress, criteriaIndex)
	if type(criteriaProgress) ~= "string" or criteriaProgress == "" then
		return nil;
	end
	local offset = criteriaProgress:sub(1, 1) == "b" and 1 or 0;
	local value = criteriaProgress:sub(criteriaIndex + offset, criteriaIndex + offset);
	if value == "1" then
		return true;
	elseif value == "0" then
		return false;
	end
	return nil;
end

local function IsCriteriaProgressPayloadComplete(criteriaProgress, expectedCount)
	if type(criteriaProgress) ~= "string" or criteriaProgress == "" or not expectedCount or expectedCount <= 0 then
		return nil;
	end
	local offset = criteriaProgress:sub(1, 1) == "b" and 1 or 0;
	if criteriaProgress:len() < expectedCount + offset then
		return nil;
	end
	for i = 1, expectedCount do
		local value = criteriaProgress:sub(i + offset, i + offset);
		if value == "0" then
			return false;
		elseif value ~= "1" then
			return nil;
		end
	end
	return true;
end

local YOUR_PROGRESS_CHECKMARK = "|TInterface\\Buttons\\UI-CheckBox-Check:0|t";
local CRITERIA_COLUMN_THRESHOLD = 14;

local function AddYourProgressHeader(tooltip)
	tooltip:AddLine(YOUR_PROGRESS_CHECKMARK .. " " .. (_G.YOUR_PROGRESS or "Your progress"), 1, 0.82, 0);
end

local function GetCriteriaRowColor(completed)
	if completed then
		return 0, 1, 0;
	end
	return 0.6, 0.6, 0.6;
end

local function RenderCriteriaRows(tooltip, rows)
	if not rows or #rows == 0 then
		return;
	end
	if #rows < CRITERIA_COLUMN_THRESHOLD then
		for _, row in ipairs(rows) do
			tooltip:AddLine(row.text, GetCriteriaRowColor(row.completed));
		end
		return;
	end

	local leftCount = math.ceil(#rows / 2);
	for i = 1, leftCount do
		local left = rows[i];
		local right = rows[i + leftCount];
		if right then
			local leftR, leftG, leftB = GetCriteriaRowColor(left.completed);
			local rightR, rightG, rightB = GetCriteriaRowColor(right.completed);
			tooltip:AddDoubleLine(left.text, right.text, leftR, leftG, leftB, rightR, rightG, rightB);
		elseif left then
			tooltip:AddLine(left.text, GetCriteriaRowColor(left.completed));
		end
	end
end

local function AddCriteriaProgressLines(tooltip, achievementID, completedResolver, showQuantity, localProgressSuffix)
	local numCriteria = Achievements.GetAchievementNumCriteria
		and Achievements.GetAchievementNumCriteria(achievementID) or 0;
	if numCriteria <= 0 then
		return false, false;
	end

	local added = false;
	local markedLocalProgress = false;
	local rows = {};
	for i = 1, numCriteria do
		local criteriaString, _, localCriteriaCompleted, _, _, _, _, _, quantityString = Achievements.GetAchievementCriteriaInfo(achievementID, i);
		if criteriaString and criteriaString ~= "" then
			local criteriaCompleted = localCriteriaCompleted;
			if completedResolver then
				local resolvedCompleted = completedResolver(i, localCriteriaCompleted);
				if resolvedCompleted ~= nil then
					criteriaCompleted = resolvedCompleted;
				end
			end
			local line = criteriaString;
			if showQuantity and quantityString and quantityString ~= "" then
				line = quantityString .. " " .. line;
			end
			if localProgressSuffix and localProgressSuffix ~= "" and localCriteriaCompleted then
				line = line .. " " .. localProgressSuffix;
				markedLocalProgress = true;
			end
			rows[#rows + 1] = {
				text = line,
				completed = criteriaCompleted == true,
			};
			added = true;
		end
	end
	RenderCriteriaRows(tooltip, rows);
	return added, markedLocalProgress;
end

local function ShowAchievementRefTooltip(achievementID, fullLink)
	if not ItemRefTooltip then
		return;
	end
	local _, name, _, localCompleted, localMonth, localDay, localYear, description = Achievements.GetAchievementInfo(achievementID);
	if not name then
		return;
	end

	local linkPlayer, linkCompleted, linkMonth, linkDay, linkYear, hasLinkPayload, criteriaProgress = ParseAchievementLinkPayload(fullLink);

	local localName = UnitName("player");
	local isOtherPlayerLink = linkPlayer and not IsLocalPlayerName(linkPlayer);
	local displayName = linkPlayer or localName or "";
	local ownerCriteriaCount = Achievements.GetAchievementNumCriteria
		and Achievements.GetAchievementNumCriteria(achievementID) or 0;
	if hasLinkPayload and linkCompleted ~= true and IsCriteriaProgressPayloadComplete(criteriaProgress, ownerCriteriaCount) == true then
		linkCompleted = true;
		linkMonth, linkDay, linkYear = 0, 0, 0;
	end
	local completed, month, day, year = linkCompleted, linkMonth, linkDay, linkYear;
	if not hasLinkPayload or not isOtherPlayerLink then
		completed, month, day, year = localCompleted, localMonth, localDay, localYear;
	end

	ShowUIPanel(ItemRefTooltip);
	if not ItemRefTooltip:IsShown() then
		ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE");
	end
	ItemRefTooltip:ClearLines();
	ItemRefTooltip:AddLine(name, 1, 1, 1);

	local addedStatusLine = false;
	if completed then
		ItemRefTooltip:AddLine(" ");
		if month and day and year and year ~= 0 then
			AddCompletedByLine(ItemRefTooltip, displayName, month, day, year);
		else
			AddCompletedByLineWithoutDate(ItemRefTooltip, displayName);
		end
		addedStatusLine = true;
	elseif displayName ~= "" then
		ItemRefTooltip:AddLine(" ");
		local fmt = _G.ACHIEVEMENT_TOOLTIP_IN_PROGRESS or "Achievement in progress by %s";
		ItemRefTooltip:AddLine(format(fmt, displayName), 0, 1, 0);
		addedStatusLine = true;
	end

	if description and description ~= "" then
		if addedStatusLine then
			ItemRefTooltip:AddLine(" ");
		end
		ItemRefTooltip:AddLine(description, 1, 1, 1, true);
	end

	local addedOwnerCriteria = false;
	local markedLocalProgress = false;
	if ownerCriteriaCount > 0 then
		ItemRefTooltip:AddLine(" ");
		addedOwnerCriteria, markedLocalProgress = AddCriteriaProgressLines(ItemRefTooltip, achievementID, function(criteriaIndex, localCriteriaCompleted)
			if isOtherPlayerLink then
				local payloadCompleted = GetCriteriaProgressPayloadValue(criteriaProgress, criteriaIndex);
				if payloadCompleted ~= nil then
					return payloadCompleted;
				end
				return completed == true;
			end
			return localCriteriaCompleted;
		end, false, (isOtherPlayerLink and localCompleted ~= true) and YOUR_PROGRESS_CHECKMARK or nil);
	end

	if isOtherPlayerLink and localCompleted == true then
		ItemRefTooltip:AddLine(" ");
		AddLocalComparisonLine(ItemRefTooltip, true, localMonth, localDay, localYear);
	elseif isOtherPlayerLink and markedLocalProgress then
		ItemRefTooltip:AddLine(" ");
		AddYourProgressHeader(ItemRefTooltip);
	elseif isOtherPlayerLink and not addedOwnerCriteria then
		ItemRefTooltip:AddLine(" ");
		AddLocalComparisonLine(ItemRefTooltip, localCompleted == true, localMonth, localDay, localYear);
	end

	ItemRefTooltip:Show();
end

local function HandleAchievementLinkClick(link, fullLink, button)
	if type(link) ~= "string" then
		return false;
	end
	local idText = link:match("^achievement:(%d+)");
	if not idText then
		return false;
	end
	local id = tonumber(idText);
	if not id then
		return false;
	end

	-- Shift-click inserts the link into the focused chat editbox,
	-- matching default behaviour for item/spell links.
	if IsModifiedClick("CHATLINK") then
		if ChatEdit_InsertLink(fullLink or link) then
			return true;
		end
	end

	ShowAchievementRefTooltip(id, fullLink);
	return true;
end

local function HookSetItemRef()
	if hookedSetItemRef then
		return;
	end
	-- Replace SetItemRef rather than post-hooking it: the default
	-- implementation in Classic raises "Unknown link type" on
	-- |Hachievement:...| links before any hooksecurefunc callback runs,
	-- so we must intercept before delegating to the original.
	local original = _G.SetItemRef;
	_G.SetItemRef = function(linkData, fullLink, button, chatFrame, ...)
		if HandleAchievementLinkClick(linkData, fullLink, button) then
			return;
		end
		return original(linkData, fullLink, button, chatFrame, ...);
	end;
	hookedSetItemRef = true;
end

function Achievements.hookAchievementGuildBroadcast()
	RegisterPrefix();
	EnsureListener();
	HookSetItemRef();
end

-- Test helper: simulates receiving a guild achievement broadcast from another
-- player. Call from chat with:
--   /run Achievements.TestIncomingBroadcast(6, "Thrall", "SHAMAN")
-- achievementID  – any valid achievement id (default: 6)
-- playerName     – display name of the fake sender (default: "Testplayer")
-- classFile      – uppercase class token, e.g. "WARRIOR" (default: "WARRIOR")
function Achievements.TestIncomingBroadcast(achievementID, playerName, classFile)
	achievementID = tostring(achievementID or 6);
	playerName    = playerName or "Testplayer";
	classFile     = classFile  or "WARRIOR";
	local completionTimestamp = time();
	local payload = string.format("%s\t%s\t%s\t%s\t%d", MESSAGE_VERSION, achievementID, classFile, "", completionTimestamp);
	-- Use a fake server-qualified sender distinct from the local player so
	-- the self-echo guard inside HandleIncomingBroadcast doesn't skip it.
	local fakeSender = playerName .. "-TestRealm";
	HandleIncomingBroadcast(payload, fakeSender, "GUILD");
end

Achievements.hookAchievementGuildBroadcast();
