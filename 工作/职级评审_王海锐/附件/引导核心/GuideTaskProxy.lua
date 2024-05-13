--[[
1.该proxy纯客户端行为，不与服务端交互
2.用于更换每个GuideTask的状态
3.存储客户端当前的新手引导的全局数据
]]

---@class GuideTaskProxy:Proxy @引导执行控制类
local Class = class("GuideTaskProxy", PureMVC.Proxy.new())
---@type GuideProxy
local guideProxy = GetProxy("GuideProxy")
---@type MissionProxy
local missionProxy = GetProxy("MissionProxy")
function Class:OnRegister()
    --HarryLog("GuideTaskProxy Register")
    ---@type table<number,GuideTask> @已建立的引导任务列表, 一个引导对应一个引导任务 一个引导任务会依次执行该引导的所有步骤
    self.guideTaskList = {}

    ---已找到路径的引导Id
    self.pathFoundIdList = {}

    ---当前正在执行的引导Id
    self.curGuideId = 0

    ---是否强制貔貅跑步(引导貔貅按钮)
    self.piXiuMustRun = false

    ---是否在点击过程
    self.isClicking = false

    ---跳过检查函数
    self.skipFunc = {}
    self:RegisterSkipFunc()
    ---完成检查函数
    self.completeCheckFunc = {}
    self:RegisterCompleteCheckFunc()
    ---特殊引导处理函数
    self.specialGuideFunc = {}
    self:RegisterSpecialGuideFunc()

    -----------------------------------------神阙引导-----------------------------------------
    ---指向的目标对象
    self.mazeTargetObj = nil

    ---引导同步推后的id列表
    self.delayCloseGuideIdList = {}
    -----------------------------------------END-----------------------------------------

    --初始化引导控制
    self:InitGuideControl()
end

--region 引导控制

---创建引导任务
---@param id number @ guideId
function Class:CreateTask(id)
    if IsVerify then
        return
    end

    ---如果程序设置为忽略引导 不增加引导任务
    if not UserCenter.instance.isShowGuide then
        return
    end

    --不重复建立相同的引导任务
    if self.guideTaskList[id] ~= nil then
        --HarryRedLog("2")
        return
    end
    --HarryLog("Create Guide Task: "..id)
    if self:CheckIsValidGuideId(id) then
        self.guideTaskList[id] = {}
        local task = require("Game.Model.Guide.GuideTask").new(id)
        self.guideTaskList[id] = task
        --HarryRedLog("create guide task id: "..id)
    else
        --HarryRedLog("3")
        printError("非法的引导id 没有配置相关数据 接收的非法引导id: " .. id)
    end
end

---检查引导id是否合法
function Class:CheckIsValidGuideId(id)
    return GuideModelData[id] ~= nil and GuideStepModelData[id] ~= nil and GuideStepModelData[id][1] ~= nil
end

---添加到已发现的引导ID列表
---重复发现的引导ID会被忽略
---@param id number
function Class:AddToFoundList(id)
    --HarryRedLog("AddToFoundList id: " .. id)
    if not table.ContainsValue(self.pathFoundIdList, id) then
        table.insert(self.pathFoundIdList, id)
    end
    self:TryHandTask()
end

---@param id number
function Class:RemoveFromFoundList(id)
    if table.ContainsValue(self.pathFoundIdList, id) then
        --HarryRedLog("RemoveFromFoundList id: " .. id)
        table.removebyvalue(self.pathFoundIdList, id)
        self:TryHandTask()
    end
end

---尝试执行优先级最高的引导
function Class:TryHandTask()
    --table.sort(self.pathFoundIdList, function(a, b)
    --    return GuideModelData[a].index < GuideModelData[b].index
    --end)
    --local guideId = self.pathFoundIdList[1]
    --PrintTable("pathList: ", self.pathFoundIdList)
    for _, v in ipairs(self.pathFoundIdList) do
        ---必须放在这里 否则下面的代码可能为空
        ---先对没有创建任务的引导 创建任务
        if self.guideTaskList[v] == nil then
            self:CreateTask(v)
        end
    end

    local guideId = table.min(self.pathFoundIdList, function(a, b)
        local isSkipA = self.guideTaskList[a]:Public_CheckIsCanSkip()
        local isSkipB = self.guideTaskList[b]:Public_CheckIsCanSkip()
        if isSkipA ~= isSkipB then
            ---会直接跳过当前步骤的引导 优先级更低
            return not isSkipA
        end
        return GuideModelData[a].index < GuideModelData[b].index
    end)

    if guideId ~= nil then


        if guideId ~= self.curGuideId then
            --中止上一个引导
            if self.guideTaskList[self.curGuideId] ~= nil then
                self.guideTaskList[self.curGuideId]:StopTask()
            end

            self.curGuideId = guideId

            if self.guideTaskList[self.curGuideId] then
                self.guideTaskList[self.curGuideId]:Execute()
            else
                self.curGuideId = 0
            end
            --HarryRedLog("set curGuideId:" .. self.curGuideId)
        else
            ---没有更改引导 不做处理
        end
    else
        self.curGuideId = 0
        --HarryRedLog("set curGuideId:" .. self.curGuideId)
    end
end

--关闭任务
function Class:CloseTask(id)
    --RinsunLog("=====Guide===" .. "关闭引导" .. "  " .. id)
    if self.guideTaskList[id] == nil then
        return
    end
    --置空
    self.guideTaskList[id]:ClearBase()
    self.guideTaskList[id]:Clear()
    self.guideTaskList[id] = nil
    ---先清理任务列表 再移除发现id列表
    self:RemoveFromFoundList(id)

    --HarryRedLog("close guide task: "..id)
end

--跳过引导
function Class:SkipTask(id)
    if self.guideTaskList[id] == nil then
        return
    end
    local closeIdList = {}
    self.guideTaskList[id]:StopTask()
    --抵达引导结束点之前的跳过 才去请求SkipGuide接口
    if not self.guideTaskList[id]:GetIsClosed() then
        ---跳过引导时 先关闭其关联的跳过引导
        for _, v in ipairs(self.guideTaskList[id].skipGuideIdList) do
            if not string.isNilOrEmpty(v) then
                local guideId = tonumber(v)
                if guideId ~= id then
                    ---避免循环关闭到自己
                    if self.guideTaskList[guideId] then
                        ---判空
                        self.guideTaskList[guideId]:ReportGuide(GuideAction.Skip)
                        self:CloseTask(guideId)
                        table.insert(closeIdList, guideId)
                    end
                end
            end
        end
    end
    self.guideTaskList[id]:SetIsClose(true)
    self.guideTaskList[id]:AfterSkipTask()
    ---最后关闭这个引导
    self.guideTaskList[id]:ReportGuide(GuideAction.Skip)
    self:CloseTask(id)
    table.insert(closeIdList, id)
    guideProxy:Public_RemoveGuideIdList(closeIdList)

    ---引导触发检查
    guideProxy:Public_TryOpenNewGuide(GuideCheckRules.skip_guide, id)
    guideProxy:Public_TryOpenNewGuide(GuideCheckRules.skip_or_finish_guide, id)

    guideProxy:Public_TryCloseGuide(GuideCheckRules.skip_or_finish_guide, id)
end

--暂停当前引导
function Class:StopCurTask()
    --HarryRedLog("StopCurTask")
    if self.curGuideId ~= 0 and self.guideTaskList[self.curGuideId] ~= nil then
        self.guideTaskList[self.curGuideId]:StopTask()
    end
end

--执行下一步
function Class:DoNextStep(guideId, needSync)
    if guideId ~= self.curGuideId then
        return
    end
    self.guideTaskList[guideId]:DoNextStep(needSync)
end

--endregion

--region 处理函数
--注册跳过消息处理函数
function Class:RegisterSkipFunc()
    self.skipFunc = {}
    self.skipFuncMeta = {}
    setmetatable(self.skipFunc, self.skipFuncMeta)
    self.skipFuncMeta.__index = function(tab, key)
        return
        function()
            return false
        end
    end

    self.skipFunc[GuideCont.get_mu_dan] = function()
        ---遍历背包中是否有牡丹仙子
        ---@type RoleProxy
        local roleProxy = GetProxy("RoleProxy")
        for _, v in ipairs(roleProxy.subPlayerRoleIdList) do
            --HarryRedLog("role: " .. StringModelData[RoleModelData[roleProxy:GetRoleIDByPlayerRoleID(v)].name])
            if roleProxy:GetRoleIDByPlayerRoleID(v) == RoleEnum.mu_dan_xian_zi then
                return true
            end
        end
        return false
    end

    self.skipFunc[GuideCont.has_plant] = function()
        return GetProxy("FactionGardenProxy"):IsPlattingSeed()
    end

    self.skipFunc[GuideCont.points_arena_cant_challenge] = function()
        return not GetProxy("PointsArenaProxy"):CheckCanChallenge()
    end

    self.skipFunc[GuideCont.points_arena_over] = function()
        return not GetProxy("PointsArenaProxy"):CheckIntoFun()
    end

    self.skipFunc[GuideCont.no_mu_dan_xian_zi] = function()
        for _, v in pairs(playerData.roleInfoList) do
            if v.roleId == RoleEnum.mu_dan_xian_zi then
                return false
            end
        end
        return true
    end

    self.skipFunc[GuideCont.drag_to_battle_pos_1] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[1]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end

    self.skipFunc[GuideCont.drag_to_battle_pos_2] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[2]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end

    self.skipFunc[GuideCont.drag_to_battle_pos_3] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[3]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end

    self.skipFunc[GuideCont.drag_to_battle_pos_4] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[4]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end

    self.skipFunc[GuideCont.drag_to_battle_pos_5] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[5]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end

    self.skipFunc[GuideCont.drag_to_battle_pos_6] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[6]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end

    self.skipFunc[GuideCont.drag_to_battle_pos_7] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[7]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end

    self.skipFunc[GuideCont.drag_to_battle_pos_7] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[7]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end

    self.skipFunc[GuideCont.drag_to_battle_pos_7] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[7]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end

    self.skipFunc[GuideCont.drag_to_battle_pos_8] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[8]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end

    self.skipFunc[GuideCont.drag_to_battle_pos_9] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[9]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end

    self.skipFunc[GuideCont.partner_armed] = function()
        ---@type ArmsProxy
        local armsProxy = GetProxy("ArmsProxy")
        local info = armsProxy:GetArmsInfo()
        local curPlayerRoleId = GetProxy("RoleProxy").currentPlayerRoleId
        local armsDataList = info:GetArmsListByRole(curPlayerRoleId)
        local armsFormatList = ArmsDM:FormatPlayerRoleArmData(armsDataList)
        for pos, _ in ipairs(ArmsPosModelData) do
            if info:HasBetterArms(pos, armsFormatList[pos], curPlayerRoleId) then
                ---可以一件穿戴
                return false
            end
        end
        return true
    end

    self.skipFunc[GuideCont.dragon_active] = function()
        ---@type DragonBallProxy
        local proxy = GetProxy("DragonBallProxy")
        if proxy:GetInfo():IsDragonLock() then
            return false
        else
            return true
        end
    end

    self.skipFunc[GuideCont.at_main_role] = function()
        local mediator = GetMediator("MainRolePanelMediator")
        if mediator then
            return mediator.mViewComponent.activeSelf
        else
            return false
        end
    end

    self.skipFunc[GuideCont.main_role_arm] = function()
        ---@type ArmsProxy
        local armsProxy = GetProxy("ArmsProxy")
        local info = armsProxy:GetArmsInfo()
        local currentPlayerRoleId = playerData.GetKeyData(PlayerKeyData.leader_uid)
        local armsDataList = info:GetArmsListByRole(currentPlayerRoleId)
        local armsFormatList = ArmsDM:FormatPlayerRoleArmData(armsDataList)
        for pos,_ in ipairs(ArmsPosModelData) do
            if info:HasBetterArms(pos, armsFormatList[pos], currentPlayerRoleId) then
                ---可以一件穿戴
                return false
            end
        end
        return true
    end
    
    self.skipFunc[GuideCont.role_bag_2] = function()
        ---@type RoleProxy
        local roleProxy = GetProxy("RoleProxy")
        local list = roleProxy.subPlayerRoleIdList
        local count = 0
        for _, v in ipairs(list) do
            if roleProxy:GetRoleIDByPlayerRoleID(v) == RoleEnum.qing_long then
                count = count + 1
                if count > 1 then
                    return true
                end
            end
        end
        return false
    end

    self.skipFunc[GuideCont.trial_has_view_mu_biao_gai_nian] = function()
        local isNew = GetProxy("MirrorOfExploreProxy"):IsSectionNew(1)
        if isNew == nil then
            return false
        else
            return not isNew
        end
    end

    self.skipFunc[GuideCont.hu_song_tang_seng] = function()
        ---@type EscortScriptureProxy
        local proxy = GetProxy("EscortScriptureProxy")
        return proxy:IsTaskWorking(proxy:GetGlobalStaticRowIndex())
    end
        
    self.skipFunc[GuideCont.maze_view_front] = function()
        return GetProxy("Maze3dProxy").selectedAngle == Maze3dMapViewTypeEnum.front
    end

    self.skipFunc[GuideCont.maze_view_front_45] = function()
        return GetProxy("Maze3dProxy").selectedAngle == Maze3dMapViewTypeEnum.front_45
    end

    self.skipFunc[GuideCont.maze_view_right_45] = function()
        return GetProxy("Maze3dProxy").selectedAngle == Maze3dMapViewTypeEnum.right_45
    end

    self.skipFunc[GuideCont.maze_view_left_45] = function()
        return GetProxy("Maze3dProxy").selectedAngle == Maze3dMapViewTypeEnum.left_45
    end

    self.skipFunc[GuideCont.xing_yun_5] = function()
        return GetProxy("ImmortalPulseProxy").nowActiveId >= 5
    end

    self.skipFunc[GuideCont.main_role_star_2] = function()
        local mainPlayerRoleIdList = GetProxy("RoleProxy"):GetMainPlayerRoleIdList()
        for _, v in pairs(mainPlayerRoleIdList) do
            local roleInfo = playerData.GetRoleInfo(v)
            if roleInfo.star < 2 then
                return true
            end
        end
        return false
    end

    self.skipFunc[GuideCont.stage_up_no_3_jing_wei] = function()
        local count = 0
        for _, v in pairs(playerData.roleInfoList) do
            if RoleModelData[v.roleId].sign == "jing_wei" and v.star == 1 then
                count = count + 1
                if count >= 3 then
                    return false
                end
            end
        end
        return true
    end

    self.skipFunc[GuideCont.stage_up_no_2_xing_tian] = function()
        local count = 0
        for _, v in pairs(playerData.roleInfoList) do
            if RoleModelData[v.roleId].sign == "xing_tian" and v.star == 1 then
                count = count + 1
                if count >= 2 then
                    return false
                end
            end
        end
        return true
    end

    self.skipFunc[GuideCont.state_1_open] = function()
        return GetProxy("BecomeImmortalProxy").isStarted
    end

    self.skipFunc[GuideCont.state_upgrade_1] = function()
        return playerData.GetKeyData(PlayerKeyData.become_immortal_state) >= 1
    end

    self.skipFunc[GuideCont.state_upgrade_2] = function()
        return playerData.GetKeyData(PlayerKeyData.become_immortal_state) >= 2
    end

    self.skipFunc[GuideCont.sky_road_no_chest] = function()
        return GetProxy("AccessToSkyProxy"):GetLastRewardLadderIndex() == nil
    end

    self.skipFunc[GuideCont.chuan_cheng_5] = function()
        return GetProxy("LevelProxy"):HasRoleActiveOnIndex(5)
    end
    self.skipFunc[GuideCont.gua_ji_reward_has_get] = function()
        local viewData = GetProxy("TimeAwardProxy"):GetViewData()
        if viewData == nil then
            return false
        end
        return not GetProxy("TimeAwardProxy"):CanGetGuaJiAward()
    end
    self.skipFunc[GuideCont.tai_gong_zhu_zhan_has_get_award] = function()
        return not GetProxy("MissionProxy"):CheckTaiGongZhuZhanCanGet()
    end
    self.skipFunc[GuideCont.quset_main_line_can_not_get_award] = function()
        return not GetProxy("QuestProxy"):CanGetAwardMainLine()
    end
    self.skipFunc[GuideCont.faction_garden_visit_list_empty] = function()
        return GetProxy("FactionGardenProxy"):IsVisitListEmpty()
    end
    self.skipFunc[GuideCont.seven_goals_cur_day_more_than_8] = function()
        local info = GetProxy("ActivityDisplayProxy"):GetActShowDataByFunId(FunctionEnum.seven_goal)
        if info == nil then
            ---没有七日目标的数据 要么没开 要么刚刚开 都不满足跳过条件 所以返回false
            return false
        end
        return info.param1 >= 8
    end
    self.skipFunc[GuideCont.equip_star_2_at_index_1] = function()
        return GetProxy("MainRoleProxy"):HasEquipStar2()
    end
    self.skipFunc[GuideCont.seven_goals_not_day_1] = function()
        local info = GetProxy("ActivityDisplayProxy"):GetActShowDataByFunId(FunctionEnum.seven_goal)
        if info == nil then
            return true
        end
        return info.param1 ~= 1
    end
    self.skipFunc[GuideCont.qian_neng_yi_man] = function()
        return GetProxy("RoleProxy"):IsCurrentRoleSkillPointFull()
    end
    self.skipFunc[GuideCont.paint_chapter_done_6] = function()
        return GetProxy("PaintChapterProxy").donePaintChapterId >= 6
    end
    self.skipFunc[GuideCont.fast_feed_no_left_times] = function()
        return not RedPoint:GetValue(RedPointModelData.fast_time_award)
    end
    self.skipFunc[GuideCont.activity_seven_day_goal_close] = function()
        return not GetProxy("ActivityDisplayProxy"):IsActivityOpen(FunctionEnum.seven_goal)
    end
    self.skipFunc[GuideCont.no_vip_level_reward] = function()
        ---@type PlayerProxy
        local playerProxy = GetProxy("PlayerProxy")
        if playerProxy.hasGetData then
            return not playerProxy:CanGetVIPLevelReward()
        else
            ---没获得数据 执行的时候再确认是否要跳过
            return false
        end
    end
    self.skipFunc[GuideCont.fetter_role_on_155] = function()
        return GetProxy("FetterProxy"):IsRoleUnlock(155)
    end
    self.skipFunc[GuideCont.role_star_one_key_stage_up_lock] = function()
        return GetProxy("StarProxy").oneKeyStarUpCount ~= nil and not GetProxy("StarProxy"):CanOneKeyStarUp()
    end
    self.skipFunc[GuideCont.rank_xiu_xian_can_get_reward] = function()
        return GetProxy("RankProxy").canGetXiuXianReward == false
    end
    self.skipFunc[GuideCont.vip_get_reward_level_1] = function()
        return table.ContainsValue(GetProxy("PlayerProxy").vipLevelRewardList, 1)
    end
    self.skipFunc[GuideCont.cur_chapter_greater_than_1] = function()
        return GetProxy("MissionProxy").curSectionId > 1
    end
    self.skipFunc[GuideCont.cur_chapter_greater_than_2] = function()
        return GetProxy("MissionProxy").curSectionId > 2
    end
    self.skipFunc[GuideCont.cur_chapter_greater_than_3] = function()
        return GetProxy("MissionProxy").curSectionId > 3
    end
    self.skipFunc[GuideCont.cur_chapter_greater_than_4] = function()
        return GetProxy("MissionProxy").curSectionId > 4
    end
    self.skipFunc[GuideCont.cur_chapter_greater_than_5] = function()
        return GetProxy("MissionProxy").curSectionId > 5
    end
    self.skipFunc[GuideCont.cur_chapter_greater_than_6] = function()
        return GetProxy("MissionProxy").curSectionId > 6
    end
    self.skipFunc[GuideCont.cur_chapter_greater_than_7] = function()
        return GetProxy("MissionProxy").curSectionId > 7
    end
    self.skipFunc[GuideCont.dragon_ball_level_1] = function()
        return playerData.dragonLevel() >= 1
    end
    self.skipFunc[GuideCont.no_recommand_friend] = function()
        return not GetProxy("FriendProxy").hasRecommondFriend
    end
    self.skipFunc[GuideCont.jing_jie_jie_jing] = function()
        return GetProxy("BecomeImmortalProxy").nowStateId >= 4
    end
    self.skipFunc[GuideCont.jing_jie_jin_dan_1] = function()
        return GetProxy("BecomeImmortalProxy").nowStateId >= 5
    end
    self.skipFunc[GuideCont.xiu_xian_not_du_jie] = function()
        local becomeImmortalProxy = GetProxy("BecomeImmortalProxy")
        local nextStateData = BecomeImmortalStateModelData[becomeImmortalProxy.nowStateId + 1]
        if nextStateData ~= nil then
            local isInDuJie = nextStateData.challenge_monster_team_id ~= 0 and not becomeImmortalProxy.isChallenge
            return not isInDuJie
        else
            printError("最高修仙等级 不需要渡劫 引导跳过条件配置有误!")
            return false
        end
    end
    self.skipFunc[GuideCont.role_num_less_than_3] = function()
        return GetProxy("RoleProxy"):GetRoleCount() < 3
    end
    self.skipFunc[GuideCont.dragon_level_2] = function()
        return GetProxy("DragonBallProxy").info.lv >= 2
    end
    self.skipFunc[GuideCont.dragon_ball_active_shi_xue_kuang_long] = function()
        --嗜血狂龙 29
        return GetProxy("DragonBallProxy"):IsDragonBallUnlockById(29)
    end
    self.skipFunc[GuideCont.jing_jie_zhu_ji] = function()
        return GetProxy("BecomeImmortalProxy").nowStateId >= 3
    end
    self.skipFunc[GuideCont.jing_jie_lian_qi] = function()
        return GetProxy("BecomeImmortalProxy").nowStateId >= 2
    end
    self.skipFunc[GuideCont.jing_jie_fan_ren] = function()
        return GetProxy("BecomeImmortalProxy").nowStateId >= 1
    end
    self.skipFunc[GuideCont.xiu_xian_has_start] = function()
        return GetProxy("BecomeImmortalProxy").isStart
    end
    self.skipFunc[GuideCont.arena_closed] = function()
        return GetProxy("ArenaProxy"):IsArenaClose()
    end
    self.skipFunc[GuideCont.at_main_panel] = function()
        local mediator = GetMediator("MainPanelMediator")
        if mediator == nil then
            return false
        end
        return mediator.curFuncIndex ~= 0 and Enums.MainPanelBottomFunInfoList[mediator.curFuncIndex].funcId == FunctionEnum.mission
    end
    self.skipFunc[GuideCont.role_bag_no_proper_role_daobatu] = function()
        local roleIdList = GetProxy("RoleProxy"):GetPlayerRoleIdListByGetType(RoleGetType.Sub)
        for _, v in ipairs(roleIdList) do
            if RoleModelData[playerData.GetRoleIdByPlayerRoleID(v)].sign == "dao_ba_tu" then
                return false
            elseif not GetProxy("EquipProxy"):IsRoleHasEquipment(v) then
                return false
            end
        end
        return true
    end
    self.skipFunc[GuideCont.role_bag_no_proper_role_jingwei] = function()
        local roleIdList = GetProxy("RoleProxy"):GetPlayerRoleIdListByGetType(RoleGetType.Sub)
        for _, v in ipairs(roleIdList) do
            if RoleModelData[playerData.GetRoleIdByPlayerRoleID(v)].sign == "jing_wei" then
                return false
            elseif not GetProxy("EquipProxy"):IsRoleHasEquipment(v) then
                return false
            end
        end
        return true
    end
    self.skipFunc[GuideCont.role_bag_no_proper_role_xingtian] = function()
        local roleIdList = GetProxy("RoleProxy"):GetPlayerRoleIdListByGetType(RoleGetType.Sub)
        for _, v in ipairs(roleIdList) do
            if RoleModelData[playerData.GetRoleIdByPlayerRoleID(v)].sign == "xing_tian" then
                return false
            elseif not GetProxy("EquipProxy"):IsRoleHasEquipment(v) then
                return false
            end
        end
        return true
    end
    self.skipFunc[GuideCont.At_Yun_Zhong_Cheng] = function()
        local mediator = GetMediator("YunZhongChenPanelMediator")
        if mediator == nil then
            return false
        end
        return mediator.mViewComponent.activeSelf
    end
    self.skipFunc[GuideCont.star_palace_challenge_has_begun] = function()
        return GetProxy("StarsPalaceProxy").nowSectionId ~= 0
    end
    self.skipFunc[GuideCont.fei_yu_skill_level_1] = function()
        return GetProxy("StarMasterProxy").starMasterList[1].level >= 1
    end
    self.skipFunc[GuideCont.seven_goals_day_1] = function()
        return GetProxy("SevenDayGoalProxy").info.selectedDay == 1
    end
    self.skipFunc[GuideCont.has_broken_through_boundary] = function()
        return playerData.GetBecomeImmortalState() > 1
    end
    self.skipFunc[GuideCont.has_broken_through_boundary_2] = function()
        return playerData.GetBecomeImmortalState() > 2
    end
    self.skipFunc[GuideCont.has_sent_pi_xiu] = function()
        return playerData.GetPiXiuSkinId() ~= 0
    end
    self.skipFunc[GuideCont.no_more_summon_stamps] = function()
        if GetProxy("MissionProcessRewardProxy").info == nil then
            return false
        end
        return GetProxy("MissionProcessRewardProxy"):IsCanGetAllGet()
    end
    self.skipFunc[GuideCont.no_more_equip_stamps] = function()
        if GetProxy("MissionProcessEquipRewardProxy").info == nil then
            return false
        end
        return GetProxy("MissionProcessEquipRewardProxy"):IsCanGetAllGet()
    end
    self.skipFunc[GuideCont.task_1000_done] = function()
        local proxy = GetProxy("TaskProxy")
        local hasTaskInfo = false    --有任务数据
        for k, v in pairs(proxy.taskInfoList) do
            hasTaskInfo = true
            if v.taskId == 1000 then
                --找到这个任务数据 而且任务状态不处于未派遣则跳过
                return v.state ~= tonumber(OnHookTaskType.UnDispatch)
            end
        end
        if hasTaskInfo then
            --没有1000任务数据 说明已经完成过
            return true
        else
            --任务数据没有返回
            return false
        end
    end
    self.skipFunc[GuideCont.battle_num_1] = function()
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        return #mediator.readyScene:GetStageInfo() >= 1
    end
    self.skipFunc[GuideCont.battle_num_2] = function()
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        return #mediator.readyScene:GetStageInfo() >= 2
    end
    self.skipFunc[GuideCont.battle_num_3] = function()
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        return #mediator.readyScene:GetStageInfo() >= 3
    end
    self.skipFunc[GuideCont.battle_num_4] = function()
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        return #mediator.readyScene:GetStageInfo() >= 4
    end
    self.skipFunc[GuideCont.nv_wa_level_5] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 5
    end
    self.skipFunc[GuideCont.nv_wa_level_7] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 7
    end
    self.skipFunc[GuideCont.nv_wa_level_9] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 9
    end
    self.skipFunc[GuideCont.nv_wa_level_10] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 10
    end
    self.skipFunc[GuideCont.nv_wa_level_11] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 11
    end
    self.skipFunc[GuideCont.nv_wa_level_12] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 12
    end
    self.skipFunc[GuideCont.nv_wa_level_13] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 13
    end
    self.skipFunc[GuideCont.nv_wa_level_14] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 14
    end
    self.skipFunc[GuideCont.nv_wa_level_15] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 15
    end
    self.skipFunc[GuideCont.nv_wa_level_16] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 16
    end
    self.skipFunc[GuideCont.nv_wa_level_18] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 18
    end
    self.skipFunc[GuideCont.nv_wa_level_17] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 17
    end
    self.skipFunc[GuideCont.nv_wa_level_19] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 19
    end
    self.skipFunc[GuideCont.nv_wa_level_20] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 20
    end
    self.skipFunc[GuideCont.nv_wa_level_21] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 21
    end
    self.skipFunc[GuideCont.nv_wa_level_22] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 22
    end
    self.skipFunc[GuideCont.nv_wa_level_23] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 23
    end
    self.skipFunc[GuideCont.nv_wa_level_24] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 24
    end
    self.skipFunc[GuideCont.nv_wa_level_25] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 25
    end
    self.skipFunc[GuideCont.nv_wa_level_26] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 26
    end
    self.skipFunc[GuideCont.nv_wa_level_27] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 27
    end
    self.skipFunc[GuideCont.nv_wa_level_28] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 28
    end
    self.skipFunc[GuideCont.nv_wa_level_29] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 29
    end
    self.skipFunc[GuideCont.nv_wa_level_30] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 30
    end
    self.skipFunc[GuideCont.nv_wa_level_31] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 31
    end
    self.skipFunc[GuideCont.nv_wa_level_32] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 32
    end
    self.skipFunc[GuideCont.nv_wa_level_33] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 33
    end
    self.skipFunc[GuideCont.nv_wa_level_34] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 34
    end
    self.skipFunc[GuideCont.nv_wa_level_35] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 35
    end
    self.skipFunc[GuideCont.nv_wa_level_36] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 36
    end
    self.skipFunc[GuideCont.nv_wa_level_37] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 37
    end
    self.skipFunc[GuideCont.nv_wa_level_38] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 38
    end
    self.skipFunc[GuideCont.nv_wa_level_39] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 39
    end
    self.skipFunc[GuideCont.nv_wa_level_40] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 40
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_5] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 5
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_10] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 10
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_11] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 11
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_12] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 12
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_13] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 13
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_14] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 14
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_15] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 15
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_16] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 16
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_17] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 17
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_18] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 18
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_19] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 19
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_20] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 20
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_21] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 21
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_22] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 22
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_23] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 23
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_24] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 24
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_25] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 25
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_26] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 26
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_27] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 27
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_28] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 28
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_29] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 29
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_30] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 30
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_31] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 31
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_32] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 32
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_33] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 33
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_34] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 34
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_35] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 35
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_36] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 36
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_37] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 37
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_38] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 38
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_39] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 39
    end
    self.skipFunc[GuideCont.fail_nv_wa_level_40] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 40
    end
    self.skipFunc[GuideCont.cang_jie_level_2] = function()
        return playerData.keyData[PlayerKeyData.comprehend_level] >= 2
    end
    self.skipFunc[GuideCont.upgrade_num_2] = function()
        return GetProxy("LevelProxy").putNum >= 2
    end
    self.skipFunc[GuideCont.upgrade_num_3] = function()
        return GetProxy("LevelProxy").putNum >= 3
    end
    self.skipFunc[GuideCont.upgrade_num_4] = function()
        return GetProxy("LevelProxy").putNum >= 4
    end
    self.skipFunc[GuideCont.upgrade_num_5] = function()
        return GetProxy("LevelProxy").putNum >= 5
    end
    self.skipFunc[GuideCont.netherworld_open] = function()
        return GetProxy("NetherWorldProxy"):GetMapBoxInfoById(34).state ~= NetherMapBoxState.Lock
    end
    self.skipFunc[GuideCont.netherworld_zhenya] = function()
        return GetProxy("NetherWorldProxy"):GetMapBoxInfoById(26).state ~= NetherMapBoxState.Lock
    end
    self.skipFunc[GuideCont.pi_xiu_level] = function()
        return false
    end
    self.skipFunc[GuideCont.new_chapter] = function()
        return GetProxy("MissionProxy").nextSectionId == GetProxy("MissionProxy").curViewSectionId
    end
    self.skipFunc[GuideCont.hero_301_PosShadowLeft_1] = function()
        local mediator = GetMediator("WarReadyPanelMediator")
        local role
        if mediator == nil or mediator.readyScene == nil then
            return false
        else
            role = mediator.readyScene.roleSpineList[1]
        end
        return role ~= nil and playerData.GetRoleIdByPlayerRoleID(role.playerRoleId) == 301
    end
    self.skipFunc[GuideCont.listopen] = function()
        return HasMediator("MapAreaPanelMediator")
    end
    self.skipFunc[GuideCont.listclose] = function()
        return not HasMediator("MapAreaPanelMediator")
    end
    self.skipFunc[GuideCont.boxopen] = function()
        if self.curGuideId == 0 then
            return false
        end
        local go = GameObject.Find(self.guideTaskList[self.curGuideId].curModelData.trigger_object)
        if go == nil then
            return false
        else
            return go.transform:Find("Open") ~= nil and go.transform:Find("Open").gameObject.activeSelf
        end
    end
    self.skipFunc[GuideCont.boxopen_red] = function()
        if self.curGuideId == 0 then
            return false
        end
        local go = GameObject.Find(self.guideTaskList[self.curGuideId].curModelData.trigger_object)
        if go == nil then
            return false
        else
            return not (go.transform:Find("RedPoint").gameObject.activeSelf)
        end
    end
    self.skipFunc[GuideCont.jump_before] = function()
        local task = self.guideTaskList[self.curGuideId]
        if task == nil then
            return false
        else
            return task.isSkipList[task.curStep - 1]
        end
    end
    self.skipFunc[GuideCont.stage_up_complete] = function()
        if self.curGuideId == 0 then
            return false
        end
        return playerData.keyData[PlayerKeyData.total_star_up_times] > 0
    end
    self.skipFunc[GuideCont.equip_enhance_complete] = function()
        if self.curGuideId == 0 then
            return false
        end
        return GetProxy("EquipProxy"):GetIsLevelUpEquipCount() > 0
    end
    self.skipFunc[GuideCont.left_tog_already_open] = function()
        if self.curGuideId == 0 then
            return false
        end
        return GetMediator("MainPanelMediator").togChangeActiveALeft.isOn
    end
    self.skipFunc[GuideCont.right_tog_already_open] = function()
        if self.curGuideId == 0 then
            return false
        end
        return GetMediator("MainPanelMediator").togChangeActive.isOn
    end
    self.skipFunc[GuideCont.quest_list_close] = function()
        return GetMediator("QuestPanelMediator") == nil
    end
    self.skipFunc[GuideCont.received_break_through_rewards_3] = function()
        if GetProxy("BecomeImmortalProxy").hasData == false then
            return false
        end
        return not GetProxy("BecomeImmortalProxy"):CanGetRewardsByStateId(3)
    end
end

--注册完成条件检查函数
function Class:RegisterCompleteCheckFunc()
    self.completeCheckFunc = {}
    self.completeCheckFuncMeta = {}
    setmetatable(self.completeCheckFunc, self.completeCheckFuncMeta)
    self.completeCheckFuncMeta.__index = function(tab, key)
        return
        function()
            return false
        end
    end

    self.completeCheckFunc[GuideCont.get_mu_dan] = function()
        ---遍历背包中是否有牡丹仙子
        ---@type RoleProxy
        local roleProxy = GetProxy("RoleProxy")
        for _, v in ipairs(roleProxy.subPlayerRoleIdList) do
            if roleProxy:GetRoleIDByPlayerRoleID(v) == RoleEnum.mu_dan_xian_zi then
                return true
            end
        end
        return false
    end

    self.completeCheckFunc[GuideCont.open_special_level] = function()
        return GetMediator("NvWaSpecialLevelPanelMediator") ~= nil
    end

    self.completeCheckFunc[GuideCont.maze_action_over_item] = function()
        --HarryRedLog("check complete target: " .. self.mazeTargetObj.name .. " now at ground: " .. Maze3d.instance.mapManager.player.playerMove.onGround.gameObject.name)
        return self.mazeTargetObj == nil or (self.mazeTargetObj ~= nil and self.mazeTargetObj.activeSelf == false)
    end

    self.completeCheckFunc[GuideCont.maze_action_over_empty] = function()
        if self.mazeTargetObj == nil
                or Maze3d.instance.mapManager.player.playerMove.onGround == nil
                or Maze3d.instance.mapManager.player.playerMove.onGround.gameObject == nil
        then
            return false
        end
        --HarryRedLog("check complete target: " .. self.mazeTargetObj.name .. " now at ground: " .. Maze3d.instance.mapManager.player.playerMove.onGround.gameObject.name)
        return self.mazeTargetObj.gameObject == Maze3d.instance.mapManager.player.playerMove.onGround.gameObject
    end

    self.completeCheckFunc[GuideCont.xing_yun_5] = function()
        return GetProxy("ImmortalPulseProxy").nowActiveId >= 5
    end

    self.completeCheckFunc[GuideCont.state_1_open] = function()
        return GetProxy("BecomeImmortalProxy").isStarted
    end

    self.completeCheckFunc[GuideCont.state_upgrade_1] = function()
        return playerData.GetKeyData(PlayerKeyData.become_immortal_state) >= 1
    end

    self.completeCheckFunc[GuideCont.state_upgrade_2] = function()
        return playerData.GetKeyData(PlayerKeyData.become_immortal_state) >= 2
    end

    self.completeCheckFunc[GuideCont.dragon_ball_level_1] = function()
        return playerData.dragonLevel() >= 1
    end
    self.completeCheckFunc[GuideCont.nvwa_level_up_clicked] = function()
        return HasMediator("NvWaSpecialLevelPanelMediator")
    end
    self.completeCheckFunc[GuideCont.battle_num_1] = function()
        local mediator = GetMediator("WarReadyPanelMediator")
        return mediator ~= nil and #mediator.readyScene:GetStageInfo() >= 1
    end
    self.completeCheckFunc[GuideCont.battle_num_2] = function()
        local mediator = GetMediator("WarReadyPanelMediator")
        return mediator ~= nil and #mediator.readyScene:GetStageInfo() >= 2
    end
    self.completeCheckFunc[GuideCont.battle_num_3] = function()
        local mediator = GetMediator("WarReadyPanelMediator")
        return mediator ~= nil and #mediator.readyScene:GetStageInfo() >= 3
    end
    self.completeCheckFunc[GuideCont.battle_num_4] = function()
        local mediator = GetMediator("WarReadyPanelMediator")
        return mediator ~= nil and #mediator.readyScene:GetStageInfo() >= 4
    end
    self.completeCheckFunc[GuideCont.battle_num_5] = function()
        local mediator = GetMediator("WarReadyPanelMediator")
        return mediator ~= nil and #mediator.readyScene:GetStageInfo() >= 5
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_5] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 5
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_7] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 7
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_9] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 9
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_10] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 10
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_11] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 11
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_12] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 12
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_13] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 13
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_14] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 14
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_15] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 15
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_16] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 16
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_18] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 18
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_17] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 17
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_19] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 19
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_20] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 20
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_21] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 21
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_22] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 22
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_23] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 23
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_24] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 24
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_25] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 25
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_26] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 26
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_27] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 27
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_28] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 28
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_29] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 29
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_30] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 30
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_31] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 31
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_32] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 32
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_33] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 33
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_34] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 34
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_35] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 35
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_36] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 36
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_37] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 37
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_38] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 38
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_39] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 39
    end
    self.completeCheckFunc[GuideCont.nv_wa_level_40] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 40
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_5] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 5
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_10] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 10
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_11] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 11
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_12] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 12
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_13] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 13
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_14] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 14
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_15] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 15
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_16] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 16
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_17] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 17
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_18] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 18
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_19] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 19
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_20] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 20
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_21] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 21
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_22] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 22
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_23] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 23
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_24] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 24
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_25] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 25
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_26] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 26
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_27] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 27
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_28] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 28
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_29] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 29
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_30] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 30
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_31] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 31
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_32] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 32
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_33] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 33
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_34] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 34
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_35] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 35
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_36] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 36
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_37] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 37
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_38] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 38
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_39] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 39
    end
    self.completeCheckFunc[GuideCont.fail_nv_wa_level_40] = function()
        return playerData.keyData[PlayerKeyData.role_level] >= 40
    end
    self.completeCheckFunc[GuideCont.cang_jie_level_2] = function()
        return playerData.keyData[PlayerKeyData.comprehend_level] >= 2
    end
    self.completeCheckFunc[GuideCont.new_chapter] = function()
        return GetProxy("MissionProxy").nextSectionId == GetProxy("MissionProxy").curViewSectionId
    end
    self.completeCheckFunc[GuideCont.nv_wa_upgrade] = function()
        local level = playerData.keyData[PlayerKeyData.role_level]                --当前女娲等级
        local curGuideTask = self:GetCurTask()
        if curGuideTask == nil then
            return false
        end
        local originRoleLevel = curGuideTask.roleLevel    --引导任务创建时的女娲等级
        if originRoleLevel == 0 or originRoleLevel >= level then
            return false
        end
        return true
    end
    self.completeCheckFunc[GuideCont.hero_301_PosShadowLeft_1] = function()
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            printError("引导完成检查 没有找到战斗布局界面!")
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[1]
        return role ~= nil and playerData.GetRoleIdByPlayerRoleID(role.playerRoleId) == 301
    end
    self.completeCheckFunc[GuideCont.drag_to_battle_pos_1] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            printError("引导完成检查 没有找到战斗布局界面!")
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[1]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end
    self.completeCheckFunc[GuideCont.drag_to_battle_pos_2] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            printError("引导完成检查 没有找到战斗布局界面!")
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[2]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end
    self.completeCheckFunc[GuideCont.drag_to_battle_pos_3] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            printError("引导完成检查 没有找到战斗布局界面!")
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[3]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end
    self.completeCheckFunc[GuideCont.drag_to_battle_pos_4] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            printError("引导完成检查 没有找到战斗布局界面!")
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[4]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end
    self.completeCheckFunc[GuideCont.drag_to_battle_pos_5] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            printError("引导完成检查 没有找到战斗布局界面!")
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[5]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end
    self.completeCheckFunc[GuideCont.drag_to_battle_pos_6] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            printError("引导完成检查 没有找到战斗布局界面!")
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[6]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end
    self.completeCheckFunc[GuideCont.drag_to_battle_pos_7] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            printError("引导完成检查 没有找到战斗布局界面!")
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[7]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end
    self.completeCheckFunc[GuideCont.drag_to_battle_pos_8] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            printError("引导完成检查 没有找到战斗布局界面!")
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[8]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end
    self.completeCheckFunc[GuideCont.drag_to_battle_pos_9] = function(guideTask)
        local mediator = GetMediator("WarReadyPanelMediator")
        if mediator == nil then
            printError("引导完成检查 没有找到战斗布局界面!")
            return false
        end
        if mediator.readyScene == nil then
            return false
        end
        local role = mediator.readyScene.roleSpineList[9]
        return role and DeployDM:GetRoleIdByPlayerRoleId(role.playerRoleId, nil, mediator.readyScene.warType) == guideTask.dragRoleId or false
    end
    self.completeCheckFunc[GuideCont.quest_list_close] = function()
        return GetMediator("QuestPanelMediator") == nil
    end
end

--注册特殊引导处理函数
function Class:RegisterSpecialGuideFunc()
    self.specialGuideFunc = {}
    self.specialGuideFuncMeta = {}
    setmetatable(self.specialGuideFunc, self.specialGuideFuncMeta)
    self.specialGuideFuncMeta.__index = function(tab, key)
        return
        function()

        end
    end

    self.specialGuideFunc[GuideSpecialRule.no_gua_ji_award] = function()
        if not GetProxy("TimeAwardProxy"):CanGetGuaJiAward() then
            AddFrameTask(
                function()
                    self.guideTaskList[self.curGuideId]:SpecialSkipStep()
                end,
                1,
                1
            )
        end
    end

    self.specialGuideFunc[GuideSpecialRule.stop_show_notify_panel] = function()
        self:GetCurTask().hasModifyStopShow = true
        NotifyPanelManager.stopShow = true
    end
    self.specialGuideFunc[GuideSpecialRule.stop_auto_war] = function()
        StopAutoWar()
    end
    self.specialGuideFunc[GuideSpecialRule.stop_auto_war_in_war_panel] = function()
        SendNotification({CMD_CANCEL_AUTO_WAR_IN_WAR_PANEL})
    end
    self.specialGuideFunc[GuideSpecialRule.guide_pi_xiu_click_area] = function()
        self.piXiuMustRun = true
        SendNotification({ CMD_GUIDE_PI_XIU_CLICK_AREA })
    end
    self.specialGuideFunc[GuideSpecialRule.seven_goal] = function()
        SendNotification({ CMD_GUIDE_ACTIVITY_SEVEN_DAYS, FunctionEnum.seven_goal })
    end
    self.specialGuideFunc[GuideSpecialRule.battle_pause] = function()
        SendNotification({ CMD_PAUSE_WAR_SCENE, true })
    end
    self.specialGuideFunc[GuideSpecialRule.herolist_nonequip] = function()
        SendNotification({ CMD_GUIDE_NONE_EQUIP })
    end
    self.specialGuideFunc[GuideSpecialRule.herolist_xingtian] = function()
        SendNotification({CMD_GUIDE_REFRESH_ROLE_BAG_PANEL})
    end
    self.specialGuideFunc[GuideSpecialRule.herolist_jingwei] = function()
        SendNotification({CMD_GUIDE_REFRESH_ROLE_BAG_PANEL})
    end
    self.specialGuideFunc[GuideSpecialRule.herolist_chuchu] = function()
        SendNotification({CMD_GUIDE_REFRESH_ROLE_BAG_PANEL})
    end
    self.specialGuideFunc[GuideSpecialRule.nvwa_up_first_time] = function()
        SendNotification({CMD_GUIDE_FIND_ROLE_NVWA_UP_FIRST_TIME})
    end
    self.specialGuideFunc[GuideSpecialRule.nvwa_up_second_time] = function()
        SendNotification({CMD_GUIDE_FIND_ROLE_NVWA_UP_SECOND_TIME})
    end
    self.specialGuideFunc[GuideSpecialRule.activity_panel_stage_path] = function()
        SendNotification({CMD_GUIDE_ADVANCE_ROAD})
    end
end

---引导存在合法性检查
function Class:IsGuideValid(guideId)
    ---根据消失类型 匹配不同的检查方法
    --if then
    --
    --end
end

---检查关卡进度是否抵达消失参数
---@param vanishProgressValue number @消失参数
function Class:HasReachVanishMissionProgress(vanishProgressValue)
    return missionProxy.curMissionId >= vanishProgressValue
end

---引导抵达结束步骤时 检查关联引导开启和结束情况
function Class:CheckRelatedGuide(guideId)
    guideProxy:Public_TryOpenNewGuide(GuideCheckRules.finish_guide, guideId)
    guideProxy:Public_TryOpenNewGuide(GuideCheckRules.skip_or_finish_guide, guideId)
    ---关闭检查
    guideProxy:Public_TryCloseGuide(GuideCheckRules.finish_guide, guideId)
    guideProxy:Public_TryCloseGuide(GuideCheckRules.skip_or_finish_guide, guideId)
    ---引导完成 从开启引导id表中移除（这时候还不会移除正在执行的引导）
    guideProxy:Public_RemoveGuideIdList({ guideId })
end

---检查功能是否已经开启
--endregion

--region 引导抑制
---author wanghairui
---初始化引导控制
function Class:InitGuideControl()
    ---@type table<number,boolean> @若表为空 则引导可以执行
    self.noGuideList = {}
    ---记录表的长度
    self.noGuideListCount = 0
end

---author wanghairui
---@param id number @固定的枚举 便于查bug
function Class:AddGuideControl(id)
    if table.ContainsKey(self.noGuideList, id) then
        --printError("引导开关控制逻辑冗余 开启 id: " .. id)
    else
        self.noGuideList[id] = true
        self.noGuideListCount = self.noGuideListCount + 1
    end
end

---author wanghairui
---@param id number
function Class:RemoveGuideControl(id)
    if table.ContainsKey(self.noGuideList, id) then
        self.noGuideList[id] = nil
        self.noGuideListCount = self.noGuideListCount - 1
    else
        --printError("引导开关控制逻辑冗余 关闭 id: " .. id)
    end
end

---author wanghairui
---@return string @当前引导控制列表
function Class:GetCurGuideControls()
    local res = ""
    for k, v in pairs(self.noGuideList) do
        res = res .. k .. "\n"
    end
    return res
end

---引导是否被抑制 true为没有被抑制
---@return boolean
function Class:CanShowGuide()
    return self.noGuideListCount <= 0
end
--endregion

--region getters
---当前引导是否为强引导
function Class:IsCurForceGuide()
    if GetMediator("GuidePanelMediator") ~= nil and self.guideTaskList[self.curGuideId] ~= nil then
        return self.guideTaskList[self.curGuideId]:IsForceGuide()
    else
        return false
    end
end

---当前引导是否允许离开当前面板
function Class:CanNotEscapeCurPanel()
    return self:IsCurForceGuide() or self:IsCurGuideNotExit()
end

---当前引导是否为not_exit
function Class:IsCurGuideNotExit()
    if GetMediator("GuidePanelMediator") ~= nil and self.guideTaskList[self.curGuideId] ~= nil then
        return self.guideTaskList[self.curGuideId]:IsNotExit()
    else
        return false
    end
end

---获取当前正在执行的引导任务
function Class:GetCurTask()
    if self.curGuideId == 0 then
        return nil
    end
    return self.guideTaskList[self.curGuideId]
end

---引导是否在执行
function Class:IsGuideExecuting(guideId)
    return self.curGuideId == guideId
end

---设置引导当前查询和目标路径
function Class:SetGuidePath(guideId, triggerPath, targetPath)
    ---@type GuideTask
    local guideTask = self.guideTaskList[guideId]
    if guideTask == nil then
        return
    end
    guideTask:SetPath(triggerPath, targetPath)
end

---正在执行的引导是否为指定引导
function Class:IsCurTaskWithId(guideId)
    -- 判断当前引导任务
    local taskInfo = self:GetCurTask()
    if taskInfo ~= nil then
        return taskInfo.id == guideId
    else
        return false
    end
end

--是否有引导在寻找中
function Class:GetIsInGuide()
    return self.curGuideId ~= 0
end

--是否正在执行一个引导
function Class:GetIsExecutingGuide()
    return self.curGuideId ~= 0 or self.isClicking
end

---是否存在某个引导任务
function Class:HasGuideTask(guideId)
    return table.ContainsKey(self.guideTaskList, guideId)
end

---根据引导id获取引导任务
function Class:GetGuideTaskById(guideId)
    if self:HasGuideTask(guideId) then
        return self.guideTaskList[guideId]
    else
        return nil
    end
end

--获取该id的End Step
function Class:GetEndStepByGuideId(guideId)
    --RinsunLog("GetEndStepByGuideId==>"..guideId)
    for k, v in ipairs(GuideStepModelData[guideId]) do
        if GetBool(v.is_end) then
            return k
        end
    end
    return 0
end

---指定引导是否已结束
function Class:IsClosedGuide(guideId)
    if self.guideTaskList[guideId] == nil then
        return true
    else
        return self.guideTaskList[guideId]:GetIsClosed()
    end
end

---获取当前存在的引导任务id列表
function Class:GetNowGuideIdList()
    return table.keys(self.guideTaskList)
end

--endregion

--region 引导关闭时 将同步服务器推后的特殊情况
function Class:AddDelayCloseGuide(guideIdList)
    for _, v in ipairs(guideIdList) do
        --HarryRedLog("add delay: " .. v)
        table.TryInsert(self.delayCloseGuideIdList, v)
    end
end

function Class:CloseDelayedGuide(guideId)
    --HarryRedLog("close id: " .. guideId)
    if table.ContainsValue(self.delayCloseGuideIdList, guideId) then
        table.removebyvalue(self.delayCloseGuideIdList, guideId)
        self:CheckRelatedGuide(guideId)
    end
end
--endregion

function Class:OnRemove()
    --HarryLog("GuideTaskProxy OnRemove")
    for k, v in pairs(self.guideTaskList) do
        v:ClearBase()
        v:Clear()
    end
    self.isClear = true
    self.guideTaskList = {}
    self.curGuideId = 0
    self.pathFoundIdList = {}
end

return Class

---@class GuideStepModelData @ 引导步骤表
---@field guide_id number @ 引导Id
---@field step number @引导步骤
---@field is_force number @是否强引导（1是，0否）
---@field is_end number @是否引导完成
---@field audio string @语音
---@field text number @文本
---@field action_type number @引导行为(点击、拖动、提示)
---@field mask_type number @遮罩类型
---@field mask_length number @遮罩长
---@field mask_width number @遮罩宽
---@field offset_x number @偏移量X
---@field offset_y number @偏移量Y
---@field mask_transparency number @遮罩透明度
---@field target_object string @控件
---@field trigger_object string @触发控件
---@field special_rule string @特殊条件
---@field skip_rule string @跳过条件
---@field finish_rule string @完成条件
---@field is_mirror number @是否镜像
---@field text_box_adaptation number @文本框适配锚点
---@field halo_offset_x number @ 光圈偏移X
---@field halo_offset_y number @ 光圈偏移Y
---@field is_plot number @是否剧情对话
---@field plot_role_id number @剧情角色
---@field plot_role_scale number @引导形象缩放大小
---@field is_plot_role_mirror number @引导形象是否翻转
---@field panel_name string @面板名称
---@field delay number @延时（毫秒）
