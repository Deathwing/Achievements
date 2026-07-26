local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsUpdate.lua");
end

local Update = {};
Achievements.Update = Update;

local SOURCES = {
	{ name = "GitHub", url = "https://github.com/Deathwing/Achievements/releases/latest" },
	{ name = "CurseForge", url = "https://www.curseforge.com/wow/addons/achievements-addon" },
	{ name = "Wago", url = "https://addons.wago.io/addons/achievements" },
	{ name = "WoWInterface", url = "https://www.wowinterface.com/downloads/info27169-Achievements.html" },
};

local warnedVersions = {};
local sourceFrame;
local pendingVersion;
local retryScheduled;

local function GetVersion()
	local ok, version = pcall(C_AddOns.GetAddOnMetadata, "Achievements", "Version");
	return ok and version and tostring(version) or "unknown";
end

local function CompareVersions(left, right)
	local leftParts = {};
	local rightParts = {};
	for part in tostring(left or ""):gmatch("%d+") do
		leftParts[#leftParts + 1] = tonumber(part) or 0;
	end
	for part in tostring(right or ""):gmatch("%d+") do
		rightParts[#rightParts + 1] = tonumber(part) or 0;
	end
	for index = 1, math.max(#leftParts, #rightParts, 1) do
		local difference = (leftParts[index] or 0) - (rightParts[index] or 0);
		if difference ~= 0 then
			return difference;
		end
	end
	return 0;
end

local function Print(message)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(message);
	end
end

local function CreateSourceFrame()
	local frame = CreateFrame("Frame", "AchievementsUpdateSourcesFrame", UIParent, "BackdropTemplate");
	frame:SetSize(460, 190);
	frame:SetPoint("CENTER");
	frame:SetFrameStrata("DIALOG");
	frame:SetClampedToScreen(true);
	frame:SetMovable(true);
	frame:EnableMouse(true);
	frame:RegisterForDrag("LeftButton");
	frame:SetScript("OnDragStart", frame.StartMoving);
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing);
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	});

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton");
	close:SetPoint("TOPRIGHT", -4, -4);

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
	title:SetPoint("TOP", 0, -22);
	title:SetText("Achievements Updates");
	frame.title = title;

	local description = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	description:SetPoint("TOP", title, "BOTTOM", 0, -10);
	description:SetText("Choose an official download source, then copy the selected address.");

	local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate");
	editBox:SetSize(400, 28);
	editBox:SetPoint("BOTTOM", 0, 24);
	editBox:SetAutoFocus(false);
	editBox:SetScript("OnEscapePressed", editBox.ClearFocus);
	frame.editBox = editBox;

	local previousButton;
	for _, source in ipairs(SOURCES) do
		local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
		button:SetSize(120, 28);
		if previousButton then
			button:SetPoint("LEFT", previousButton, "RIGHT", 10, 0);
		else
			button:SetPoint("TOPLEFT", 35, -82);
		end
		button:SetText(source.name);
		button:SetScript("OnClick", function()
			editBox:SetText(source.url);
			editBox:SetFocus();
			editBox:HighlightText();
		end);
		previousButton = button;
	end

	editBox:SetText(SOURCES[1].url);
	frame:Hide();
	return frame;
end

function Update.Show(newVersion)
	if not sourceFrame then
		sourceFrame = CreateSourceFrame();
	end
	if newVersion then
		sourceFrame.title:SetText("Achievements " .. tostring(newVersion) .. " is available");
	else
		sourceFrame.title:SetText("Achievements Updates - v" .. GetVersion());
	end
	sourceFrame:Show();
	sourceFrame:Raise();
end

local TryShowPendingUpdate;

local function ScheduleRetry(delay)
	if retryScheduled then
		return;
	end
	retryScheduled = true;
	C_Timer.After(delay, function()
		TryShowPendingUpdate();
	end);
end

TryShowPendingUpdate = function()
	retryScheduled = nil;
	if not pendingVersion then
		return;
	end
	if AchievementsDB.lastUpdatePopupVersion == pendingVersion then
		pendingVersion = nil;
		return;
	end
	if InCombatLockdown() then
		return;
	end
	-- Only surface the update popup in rested areas (inns/cities). Popping it up
	-- mid-world is too intrusive, so defer and retry until the player is resting.
	if not IsResting() then
		ScheduleRetry(5);
		return;
	end
	-- Parity with Deathlog/MRP: they also defer while their changelog popup
	-- is open. Achievements has no changelog popup, so only combat/resting defer.
	local version = pendingVersion;
	pendingVersion = nil;
	AchievementsDB.lastUpdatePopupVersion = version;
	Update.Show(version);
end

local function ScheduleUpdatePopup(newVersion)
	newVersion = tostring(newVersion or "unknown");
	local detectedVersion = AchievementsDB.newestDetectedUpdateVersion;
	if detectedVersion and CompareVersions(detectedVersion, newVersion) > 0 then
		newVersion = detectedVersion;
	end
	AchievementsDB.newestDetectedUpdateVersion = newVersion;
	if AchievementsDB.lastUpdatePopupVersion and CompareVersions(newVersion, AchievementsDB.lastUpdatePopupVersion) <= 0 then
		return;
	end
	pendingVersion = newVersion;
	ScheduleRetry(3);
end

function Update.Notify(newVersion)
	newVersion = tostring(newVersion or "unknown");
	ScheduleUpdatePopup(newVersion);
	if warnedVersions[newVersion] then
		return;
	end
	warnedVersions[newVersion] = true;
	Print("|cffffff00Achievements:|r A newer version (v" .. newVersion .. ") is available; you are running v" .. GetVersion() .. ". Type |cffffffff/ach update|r for official GitHub, CurseForge, and Wago downloads.");
end

--- Print the versions of Achievements and its bundled sub-addons to chat,
--- noting if a newer version has been detected from other players.
function Update.PrintVersions()
	Print("|cffffd200Achievements versions|r");

	local mainVersion = GetVersion();
	Print("  Achievements: |cffffffff" .. mainVersion .. "|r");

	-- Optional data companion. GetAddOnMetadata reads the on-disk TOC, so it
	-- returns a version even when AchievementsData is installed but DISABLED
	-- (unchecked) — misleading because a disabled companion contributes nothing
	-- at runtime. Report the loaded state: skip when not installed, mark it
	-- (disabled) when installed but not loaded.
	local dataOk, dataVersion = pcall(C_AddOns.GetAddOnMetadata, "AchievementsData", "Version");
	if dataOk and dataVersion then
		local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded;
		if isLoaded and isLoaded("AchievementsData") then
			Print("  AchievementsData: |cffffffff" .. tostring(dataVersion) .. "|r");
		else
			Print("  AchievementsData: |cffffffff" .. tostring(dataVersion) .. "|r |cff999999(installed, disabled)|r");
		end
	end

	-- Note a known newer version, if one has been detected from other players.
	local detected = AchievementsDB and AchievementsDB.newestDetectedUpdateVersion;
	if detected and CompareVersions(detected, mainVersion) > 0 then
		Print("|cffff5555Update available:|r Achievements v" .. tostring(detected)
			.. " has been seen from other players. Type |cffffffff/ach update|r for download sources.");
	else
		Print("|cff55ff55You're up to date|r as far as Achievements can tell.");
	end
end

SLASH_ACHIEVEMENTSUPDATES1 = "/ach-update";
SLASH_ACHIEVEMENTSUPDATES2 = "/achievements-update";
SlashCmdList["ACHIEVEMENTSUPDATES"] = function()
	Update.Show();
end

local function GetAvailableDisplayLocaleText()
	local locales = Achievements.GetAvailableDisplayLocales();
	table.insert(locales, 1, "auto");
	return table.concat(locales, ", ");
end

local function PrintDisplayLocaleStatus()
	local selectedLocale, effectiveLocale = Achievements.GetDisplayLocale();
	Print("|cffffd200Achievements display locale:|r selected: " .. selectedLocale .. "; effective: " .. effectiveLocale .. ".");
	Print("Available display locales: " .. GetAvailableDisplayLocaleText() .. ".");
	if Achievements.IsDisplayLocaleOverridingClientLocale and Achievements.IsDisplayLocaleOverridingClientLocale() then
		Print("Achievement content is shown in " .. effectiveLocale .. " while the game client runs in " .. GetLocale() .. ". Blizzard-owned labels stay in the client language.");
	end
end

local function PrintDroppedDisplayLocaleWarning()
	local droppedLocale = Achievements.GetDroppedDisplayLocale and Achievements.GetDroppedDisplayLocale();
	if not droppedLocale then
		return;
	end
	Print("|cffff2020Achievements:|r display locale '" .. droppedLocale .. "' is not available in the installed AchievementsData package; falling back to auto.");
	Print("Available display locales: " .. GetAvailableDisplayLocaleText() .. ".");
end

local function HandleDisplayLocaleCommand(argument)
	if argument == "" then
		PrintDisplayLocaleStatus();
		return;
	end

	local canonicalLocale, changed = Achievements.SetDisplayLocale(argument);
	if not canonicalLocale then
		Print("|cffff2020Achievements:|r Unknown display locale '" .. tostring(argument) .. "'.");
		Print("Available display locales: " .. GetAvailableDisplayLocaleText() .. ".");
		return;
	end
	if not changed then
		Print("|cffffd200Achievements:|r display locale " .. canonicalLocale .. " is already selected.");
		return;
	end

	Print("|cffffd200Achievements:|r display locale set to " .. canonicalLocale .. ". Reloading interface.");
	ReloadUI();
end

-- Main slash command, mirroring Deathlog (/dl update) and MRP (/mrp update).
-- Without a subcommand it toggles the achievement frame.
SLASH_ACHIEVEMENTS1 = "/ach";
SLASH_ACHIEVEMENTS2 = "/achievements";
SlashCmdList["ACHIEVEMENTS"] = function(msg)
	local command, argument = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$");
	command = string.lower(command or "");
	if command == "update" or command == "updates" then
		Update.Show();
		return;
	elseif command == "version" or command == "versions" then
		Update.PrintVersions();
		return;
	elseif command == "locale" then
		HandleDisplayLocaleCommand(argument);
		return;
	end
	Achievements.ToggleAchievementFrame();
end

local eventFrame = CreateFrame("Frame");
eventFrame:RegisterEvent("PLAYER_LOGIN");
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED");
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		PrintDroppedDisplayLocaleWarning();
		local detectedVersion = AchievementsDB.newestDetectedUpdateVersion;
		if detectedVersion and CompareVersions(detectedVersion, GetVersion()) > 0 then
			ScheduleUpdatePopup(detectedVersion);
		else
			AchievementsDB.newestDetectedUpdateVersion = nil;
		end
		return;
	end
	TryShowPendingUpdate();
end);
