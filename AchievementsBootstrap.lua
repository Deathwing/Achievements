local Achievements = _G.Achievements;
if not Achievements then
	error("Achievements: Achievements.lua must load before AchievementsBootstrap.lua");
end

Achievements.ensureAchievementMicroButton();
Achievements.hookUpdateMicroButtons();
Achievements.hookAchievementChatLinks();
if Achievements.hookAchievementGuildBroadcast then
	Achievements.hookAchievementGuildBroadcast();
end
if Achievements.hookAddonTitles then
	Achievements.hookAddonTitles();
end
Achievements.hookItemUseCriteria();
Achievements.hookEmoteCriteria();
if Achievements.hookSimpleActionCriteria then
	Achievements.hookSimpleActionCriteria();
end

local eventFrame = CreateFrame("Frame");
eventFrame:RegisterEvent("ADDON_LOADED");
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
eventFrame:RegisterEvent("PLAYER_LEVEL_UP");
eventFrame:RegisterEvent("QUEST_ACCEPTED");
eventFrame:RegisterEvent("QUEST_TURNED_IN");
eventFrame:RegisterEvent("QUEST_LOG_UPDATE");
eventFrame:RegisterEvent("MAP_EXPLORATION_UPDATED");
eventFrame:RegisterEvent("SPELLS_CHANGED");
pcall(eventFrame.RegisterEvent, eventFrame, "LEARNED_SPELL_IN_TAB");
pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_TALENT_UPDATE");
pcall(eventFrame.RegisterEvent, eventFrame, "ACTIVE_TALENT_GROUP_CHANGED");
-- UNIT_AURA / UNIT_SPELLCAST_SUCCEEDED fire for every visible unit (target,
-- focus, party/raid members, nameplates). In raids that is a constant stream of
-- dispatches that all get discarded because the handlers only act on "player".
-- Filter them to the player unit so the OnEvent handler is never even entered
-- for other units. Fall back to the unfiltered registration on the rare client
-- that lacks RegisterUnitEvent.
if eventFrame.RegisterUnitEvent then
	eventFrame:RegisterUnitEvent("UNIT_AURA", "player");
	eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player");
else
	eventFrame:RegisterEvent("UNIT_AURA");
	eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED");
end
eventFrame:RegisterEvent("SKILL_LINES_CHANGED");
eventFrame:RegisterEvent("UPDATE_FACTION");
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED");
eventFrame:RegisterEvent("ITEM_PUSH");
eventFrame:RegisterEvent("LOOT_OPENED");
eventFrame:RegisterEvent("CHAT_MSG_LOOT");
eventFrame:RegisterEvent("CHAT_MSG_MONEY");
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED");
eventFrame:RegisterEvent("PLAYER_MONEY");
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
eventFrame:RegisterEvent("PLAYER_DEAD");
eventFrame:RegisterEvent("PLAYER_PVP_RANK_CHANGED");
eventFrame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS");
pcall(eventFrame.RegisterEvent, eventFrame, "UPDATE_BATTLEFIELD_SCORE");
pcall(eventFrame.RegisterEvent, eventFrame, "BATTLEGROUND_POINTS_UPDATE");
pcall(eventFrame.RegisterEvent, eventFrame, "PVP_WORLDSTATE_UPDATE");
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM");
pcall(eventFrame.RegisterEvent, eventFrame, "CHAT_MSG_BG_SYSTEM_ALLIANCE");
pcall(eventFrame.RegisterEvent, eventFrame, "CHAT_MSG_BG_SYSTEM_HORDE");
pcall(eventFrame.RegisterEvent, eventFrame, "CHAT_MSG_BG_SYSTEM_NEUTRAL");
eventFrame:RegisterEvent("CHAT_MSG_TEXT_EMOTE");
pcall(eventFrame.RegisterEvent, eventFrame, "GROUP_ROSTER_UPDATE");
-- Used to detect when guild chat is actually joined so own-achievement
-- broadcasts that fire during the early-login window can wait until they'll
-- be visible in the player's guild chat tab.
pcall(eventFrame.RegisterEvent, eventFrame, "GUILD_ROSTER_UPDATE");
pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_GUILD_UPDATE");
pcall(eventFrame.RegisterEvent, eventFrame, "CHAT_MSG_GUILD");
-- World-state events differ by client (Era vs TBC vs later); RegisterEvent
-- raises on unknown event names so guard with pcall.
pcall(eventFrame.RegisterEvent, eventFrame, "UPDATE_WORLD_STATES");
pcall(eventFrame.RegisterEvent, eventFrame, "UPDATE_UI_WIDGET");
pcall(eventFrame.RegisterEvent, eventFrame, "UPDATE_ALL_UI_WIDGETS");
pcall(eventFrame.RegisterEvent, eventFrame, "AREA_POIS_UPDATED");
pcall(eventFrame.RegisterEvent, eventFrame, "CALENDAR_UPDATE_EVENT");
pcall(eventFrame.RegisterEvent, eventFrame, "CALENDAR_UPDATE_EVENT_LIST");
pcall(eventFrame.RegisterEvent, eventFrame, "CURRENCY_DISPLAY_UPDATE");
pcall(eventFrame.RegisterEvent, eventFrame, "ITEM_TEXT_BEGIN");
pcall(eventFrame.RegisterEvent, eventFrame, "ITEM_TEXT_READY");
pcall(eventFrame.RegisterEvent, eventFrame, "GAME_OBJECT_ACTIVATED");
pcall(eventFrame.RegisterEvent, eventFrame, "BARBER_SHOP_SUCCESS");
pcall(eventFrame.RegisterEvent, eventFrame, "MAIL_SHOW");
pcall(eventFrame.RegisterEvent, eventFrame, "MAIL_INBOX_UPDATE");
pcall(eventFrame.RegisterEvent, eventFrame, "BOSS_KILL");
pcall(eventFrame.RegisterEvent, eventFrame, "ENCOUNTER_END");
pcall(eventFrame.RegisterEvent, eventFrame, "LFG_UPDATE");
pcall(eventFrame.RegisterEvent, eventFrame, "LFG_QUEUE_STATUS_UPDATE");
pcall(eventFrame.RegisterEvent, eventFrame, "LFG_PROPOSAL_SHOW");
pcall(eventFrame.RegisterEvent, eventFrame, "LFG_PROPOSAL_UPDATE");
pcall(eventFrame.RegisterEvent, eventFrame, "LFG_PROPOSAL_FAILED");

local function ScheduleCriteriaRefresh(showAlerts, delay, reason)
	if Achievements.ScheduleCriteriaRefresh then
		Achievements.ScheduleCriteriaRefresh(showAlerts, delay, reason);
	elseif Achievements.RefreshCriteriaAchievements then
		Achievements.RefreshCriteriaAchievements(showAlerts);
	end
end

local CRITERIA_TYPES = Achievements.criteriaResolvers and Achievements.criteriaResolvers.criteriaTypes or {};

local function ScheduleCriteriaTypeRefresh(criteriaTypes, showAlerts, delay, reason)
	if Achievements.ScheduleCriteriaTypeRefresh then
		Achievements.ScheduleCriteriaTypeRefresh(criteriaTypes, showAlerts, delay, reason);
	else
		ScheduleCriteriaRefresh(showAlerts, delay, reason);
	end
end

eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4, arg5)
	if event == "ADDON_LOADED" then
		if arg1 == "Achievements" or arg1 == "Blizzard_AchievementUI" then
			Achievements.applyAchievementShieldTexturePatch();
			Achievements.applyAchievementPlusMinusTexturePatch();
			Achievements.applyAchievementCategoryListPatch();
			Achievements.applyAchievementStatsUIPatch();
			Achievements.applyAchievementSummaryUIPatch();
			Achievements.applyAchievementComparisonUIPatch();
		end
		return;
	end

	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		if Achievements.HandleCombatLogCriteria then
			Achievements.HandleCombatLogCriteria();
		end
		return;
	end

	if event == "PLAYER_DEAD" then
		if Achievements.RecordPlayerDeath then
			Achievements.RecordPlayerDeath();
		end
		return;
	end

	if event == "CHAT_MSG_SYSTEM" then
		if Achievements.RecordDuelOutcomeFromSystemMessage then
			Achievements.RecordDuelOutcomeFromSystemMessage(arg1);
		end
		return;
	end

	if event == "CHAT_MSG_MONEY" then
		if Achievements.RecordMoneyChatCriteria then
			Achievements.RecordMoneyChatCriteria(arg1);
		end
		return;
	end

	if event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
		if Achievements.RecordMailboxAuctionCriteria then
			Achievements.RecordMailboxAuctionCriteria();
		end
		Achievements.RefreshCriteriaAchievements(false);
		return;
	end

	if event == "BOSS_KILL" then
		if Achievements.RecordEncounterDefeat then
			Achievements.RecordEncounterDefeat(arg1, true);
		end
		return;
	end

	if event == "ENCOUNTER_END" then
		if Achievements.RecordEncounterDefeat then
			Achievements.RecordEncounterDefeat(arg1, arg5);
		end
		return;
	end

	if event == "CHAT_MSG_TEXT_EMOTE" then
		-- Incoming text emote chat doesn't carry the original token, so we
		-- only re-fire the gated path when the local player has a target.
		-- Self-issued /emote commands are already covered by the DoEmote hook.
		return;
	end

	if event == "PLAYER_EQUIPMENT_CHANGED" then
		if Achievements.ClearCharacterScanCache then
			Achievements.ClearCharacterScanCache();
		end
		if Achievements.RecordEquippedItemSlot then
			Achievements.RecordEquippedItemSlot(arg1);
		end
		Achievements.RefreshCriteriaAchievements(true);
		return;
	end

	if event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
		if Achievements.ClearCharacterScanCache then
			Achievements.ClearCharacterScanCache();
		end
		if Achievements.RecordDualTalentSpecializationCriteria then
			Achievements.RecordDualTalentSpecializationCriteria();
		end
		Achievements.RefreshCriteriaAchievements(true);
		return;
	end

	if event == "UNIT_AURA" then
		if Achievements.RecordPlayerAuraCriteria then
			Achievements.RecordPlayerAuraCriteria(arg1);
		end
		return;
	end

	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if Achievements.RecordPlayerSpellcast then
			Achievements.RecordPlayerSpellcast(arg1, arg2, arg3);
		end
		return;
	end

	if event == "LOOT_OPENED" or event == "CHAT_MSG_LOOT" then
		if Achievements.RecordLootAcquisitionCriteria then
			Achievements.RecordLootAcquisitionCriteria(arg1);
		end
		return;
	end

	if event == "ITEM_TEXT_BEGIN" or event == "ITEM_TEXT_READY" or event == "GAME_OBJECT_ACTIVATED" then
		if Achievements.RecordGameObjectTextCriteria then
			Achievements.RecordGameObjectTextCriteria();
		end
		return;
	end

	if event == "UPDATE_WORLD_STATES" or event == "UPDATE_UI_WIDGET" or event == "UPDATE_ALL_UI_WIDGETS" or event == "AREA_POIS_UPDATED" or event == "UPDATE_BATTLEFIELD_SCORE" or event == "BATTLEGROUND_POINTS_UPDATE" or event == "PVP_WORLDSTATE_UPDATE" then
		if Achievements.RecordWorldStateScan then
			Achievements.RecordWorldStateScan();
		end
		Achievements.RefreshCriteriaAchievements(false);
		return;
	end

	if event == "CHAT_MSG_BG_SYSTEM_ALLIANCE" or event == "CHAT_MSG_BG_SYSTEM_HORDE" or event == "CHAT_MSG_BG_SYSTEM_NEUTRAL" then
		if Achievements.RecordBattlegroundWorldStateMessage then
			Achievements.RecordBattlegroundWorldStateMessage(arg1);
		end
		if Achievements.RecordWorldStateScan then
			Achievements.RecordWorldStateScan();
		end
		Achievements.RefreshCriteriaAchievements(false);
		return;
	end

	if event == "CALENDAR_UPDATE_EVENT" or event == "CALENDAR_UPDATE_EVENT_LIST" then
		Achievements.RefreshCriteriaAchievements(false);
		return;
	end

	if event == "LFG_UPDATE" or event == "LFG_QUEUE_STATUS_UPDATE" or event == "LFG_PROPOSAL_SHOW" or event == "LFG_PROPOSAL_UPDATE" or event == "LFG_PROPOSAL_FAILED" then
		if Achievements.RecordLFGState then
			Achievements.RecordLFGState(event);
		end
		Achievements.RefreshCriteriaAchievements(false);
		return;
	end

	if event == "GROUP_ROSTER_UPDATE" then
		if Achievements.RecordCriteriaFail and Achievements.criteriaResolvers and Achievements.criteriaResolvers.criteriaFailEvents then
			Achievements.RecordCriteriaFail(Achievements.criteriaResolvers.criteriaFailEvents.MODIFY_PARTY_STATUS, 0);
		end
		Achievements.RefreshCriteriaAchievements(false);
		return;
	end

	if event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" or event == "CHAT_MSG_GUILD" then
		if Achievements.MarkGuildAnnouncementsReady then
			C_Timer.After(2, Achievements.MarkGuildAnnouncementsReady);
		end
		return;
	end

	if event == "PLAYER_LEVEL_UP" and arg1 then
		if Achievements.RecordCriteriaStart and Achievements.criteriaResolvers and Achievements.criteriaResolvers.criteriaStartEvents then
			Achievements.RecordCriteriaStart(Achievements.criteriaResolvers.criteriaStartEvents.REACH_LEVEL, arg1);
		end
		ScheduleCriteriaTypeRefresh({ CRITERIA_TYPES.REACH_LEVEL, CRITERIA_TYPES.GAIN_LEVELS }, true, 0.75, "level-up");
		return;
	end

	if event == "BAG_UPDATE_DELAYED" or event == "ITEM_PUSH" or event == "PLAYERBANKSLOTS_CHANGED" then
		if Achievements.ClearCharacterScanCache then
			Achievements.ClearCharacterScanCache();
		end
		ScheduleCriteriaRefresh(true, 0.35, event);
		return;
	end

	if event == "PLAYER_MONEY" then
		if Achievements.RecordPlayerMoneySnapshot then
			Achievements.RecordPlayerMoneySnapshot();
		end
		ScheduleCriteriaRefresh(false, 0.15, "player-money");
		return;
	end

	if Achievements.ClearQuestCompletionCache then
		Achievements.ClearQuestCompletionCache();
	end
	if Achievements.ClearExplorationCache then
		Achievements.ClearExplorationCache();
	end
	if Achievements.ClearCharacterScanCache then
		Achievements.ClearCharacterScanCache();
	end

	Achievements.ensureAchievementMicroButton();
	Achievements.hookUpdateMicroButtons();
	Achievements.hookAchievementChatLinks();
	if Achievements.hookAchievementGuildBroadcast then
		Achievements.hookAchievementGuildBroadcast();
	end
	if Achievements.hookAddonTitles then
		Achievements.hookAddonTitles();
	end
	Achievements.hookItemUseCriteria();
	Achievements.hookEmoteCriteria();
	if Achievements.hookSimpleActionCriteria then
		Achievements.hookSimpleActionCriteria();
	end
	Achievements.applyAchievementShieldTexturePatch();
	Achievements.applyAchievementSummaryUIPatch();
	Achievements.WatchFrame_Update();

	if event == "PLAYER_LEVEL_UP" and arg1 then
		if Achievements.RecordCriteriaStart and Achievements.criteriaResolvers and Achievements.criteriaResolvers.criteriaStartEvents then
			Achievements.RecordCriteriaStart(Achievements.criteriaResolvers.criteriaStartEvents.REACH_LEVEL, arg1);
		end
		ScheduleCriteriaTypeRefresh({ CRITERIA_TYPES.REACH_LEVEL, CRITERIA_TYPES.GAIN_LEVELS }, true, 0.75, "level-up");
	elseif event == "QUEST_ACCEPTED" then
		if Achievements.RecordQuestAccepted then
			Achievements.RecordQuestAccepted(arg1);
		end
		Achievements.RefreshCriteriaAchievements(false);
	elseif event == "QUEST_TURNED_IN" then
		if Achievements.RecordQuestTurnedIn then
			Achievements.RecordQuestTurnedIn(arg1, arg3);
		end
		if Achievements.RecordDailyQuestResetCheck then
			Achievements.RecordDailyQuestResetCheck();
		end
		Achievements.RefreshCriteriaAchievements(true);
	elseif event == "QUEST_LOG_UPDATE" then
		if Achievements.RecordDailyQuestResetCheck then
			Achievements.RecordDailyQuestResetCheck();
		end
		Achievements.RefreshCriteriaAchievements(false);
	elseif event == "MAP_EXPLORATION_UPDATED" then
		Achievements.RefreshCriteriaAchievements(true);
	elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
		if Achievements.RecordDualTalentSpecializationCriteria then
			Achievements.RecordDualTalentSpecializationCriteria();
		end
		ScheduleCriteriaTypeRefresh({ CRITERIA_TYPES.LEARN_OR_KNOW_SPELL, CRITERIA_TYPES.LEARN_SPELL_FROM_SKILL_LINE }, true, 0.35, event);
	elseif event == "SKILL_LINES_CHANGED" then
		ScheduleCriteriaTypeRefresh({ CRITERIA_TYPES.SKILL_RAISED, CRITERIA_TYPES.SKILL_STEP, CRITERIA_TYPES.LEARN_SPELL_FROM_SKILL_LINE, CRITERIA_TYPES.LEARN_TRADESKILL_SKILL_LINE }, true, 0.35, event);
	elseif event == "UPDATE_FACTION" then
		ScheduleCriteriaTypeRefresh({ CRITERIA_TYPES.REPUTATION_GAINED, CRITERIA_TYPES.TOTAL_EXALTED_FACTIONS, CRITERIA_TYPES.TOTAL_REVERED_FACTIONS, CRITERIA_TYPES.TOTAL_HONORED_FACTIONS, CRITERIA_TYPES.TOTAL_FACTIONS_ENCOUNTERED }, true, 0.35, event);
	elseif event == "CURRENCY_DISPLAY_UPDATE" then
		if Achievements.RecordCurrencyScan then
			Achievements.RecordCurrencyScan();
		end
		ScheduleCriteriaTypeRefresh(CRITERIA_TYPES.CURRENCY_GAINED, true, 0.35, event);
	elseif event == "PLAYER_MONEY" then
		if Achievements.RecordPlayerMoneySnapshot then
			Achievements.RecordPlayerMoneySnapshot();
		end
		Achievements.RefreshCriteriaAchievements(false);
	elseif event == "BARBER_SHOP_SUCCESS" then
		if Achievements.RecordBarberShopCriteria then
			Achievements.RecordBarberShopCriteria();
		end
		Achievements.RefreshCriteriaAchievements(true);
	elseif event == "BAG_UPDATE_DELAYED" or event == "ITEM_PUSH" or event == "PLAYERBANKSLOTS_CHANGED" then
		Achievements.RefreshCriteriaAchievements(true);
	elseif event == "PLAYER_PVP_RANK_CHANGED" then
		Achievements.RefreshCriteriaAchievements(true);
	elseif event == "PLAYER_ENTERING_WORLD" then
		if Achievements.RecordWorldStateScan then
			Achievements.RecordWorldStateScan();
		end
		if Achievements.BackfillCurrentState then
			Achievements.BackfillCurrentState();
		else
			Achievements.RefreshCriteriaAchievements(false);
		end
		if Achievements.ScheduleEndFirstLoginInitialGrant then
			Achievements.ScheduleEndFirstLoginInitialGrant();
		end
		-- Safety net: even if no guild events fire (player not in a guild,
		-- or events were missed) drain the queue 15s after entering world.
		if Achievements.MarkGuildAnnouncementsReady then
			C_Timer.After(15, Achievements.MarkGuildAnnouncementsReady);
		end
	elseif event == "ZONE_CHANGED_NEW_AREA" then
		if Achievements.RecordWorldStateScan then
			Achievements.RecordWorldStateScan();
		end
		Achievements.RefreshCriteriaAchievements(false);
	elseif event == "UPDATE_BATTLEFIELD_STATUS" then
		if Achievements.RecordWorldStateScan then
			Achievements.RecordWorldStateScan();
		end
		if Achievements.RecordBattlegroundWin then
			Achievements.RecordBattlegroundWin();
		end
		if Achievements.RecordArenaParticipation then
			Achievements.RecordArenaParticipation();
		end
		if Achievements.RecordArenaWin then
			Achievements.RecordArenaWin();
		end
		Achievements.RefreshCriteriaAchievements(false);
	end
end);
