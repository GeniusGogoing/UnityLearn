--[[
每个task对应一个guideId

]]
---@class GuideTask:UIBase
local Class = class("GuideTask", UIBase)
---@type GuideTaskProxy
local proxy = GetProxy("GuideTaskProxy")
---@type GuideProxy
local guideProxy = GetProxy("GuideProxy")
local json = require("json")

---@param id number 引导id
function Class:ctor(id)
    -----------------------------------------引导状态信息-----------------------------------------
    ---guideId
    self.id = id
    ---上一步
    self.lastStep = 0
    ---当前步数
    self.curStep = 0
    ---执行步骤
    self.executeStep = 0

    ---当前引导数据
    self.curModelData = nil
    ---当前引导跳过条件表
    self.curSkipRuleList = {}
    ---当前引导特殊条件表
    self.curSpecialRuleList = {}
    ---上一步引导数据
    self.lastModelData = nil
    ---上一步引导跳过条件表
    self.lastSkipRuleList = {}
    ---上一步引导特殊条件表
    self.lastSpecialRuleList = {}
    ---正在执行的引导数据
    self.executeModelData = nil
    ---正在执行的引导跳过条件表
    self.executeSkipRuleList = {}
    ---正在执行的引导特殊条件表
    self.executeSpecialRuleList = {}

    ---当前路径是否找到过
    self.hasFoundCurPath = false
    ---上一个路径是否找到过
    self.hasFoundLastPath = false
    ---是否在执行
    self.isExecuting = false

    ---跳过步骤列表
    self.skipStepList = {}
    ---是否跳过步骤
    self.isSkip = false
    ---完成步骤检查函数
    self.checkCompleteAction = function()
        return false
    end
    ---是否是循环引导
    self.isCycle = true
    for _, v in ipairs(GuideStepModelData[self.id]) do
        if v.is_end == 1 then
            self.isCycle = false
            break
        end
    end
    ---当前引导是否已经到达完成步骤
    self.isClosed = false
    ---步骤数据更新标记(每个步骤的数据更新只做一次)
    self.hasUpdateStepData = false
    ---跳过关联引导id列表
    self.skipGuideIdList = {}
    -----------------------------------------END-----------------------------------------

    ---记录引导开始时间
    self.startTime = 0

    ---定时器
    self.checkPathTimerId = nil
    self.checkCompleteTimerId = nil

    ---每步引导只能延迟一次
    self.hasDelay = false

    ---是否抑制了新功能开启
    self.canNotShowNewFuncPanel = false

    ---当前播过语音的最新步骤
    self.curVoiceStep = 0

    ---特殊拖拽 记录需要拖拽的roleId
    self.dragRoleId = 0

    ---当前步骤是否无视网络
    self.curStepIgnoreNet = false
    ---上一步骤是否无视网络
    self.lastStepIgnoreNet = false

    self.skipGuideIdList = guideProxy:Public_GetSkipRelationList(self.id)
    self:SetCurStep(1)
    self:InitSpecial()
    self:CheckPath()
end

--region 引导状态信息
---设置上一步
function Class:SetLastStep(lastStep)
    if self.lastStep ~= lastStep then
        self.lastStep = lastStep
        if self.lastStep == 0 then
            self.lastModelData = nil
        elseif GuideStepModelData[self.id][self.lastStep] ~= nil then
            self.lastModelData = table.copy(GuideStepModelData[self.id][self.lastStep])
            self.lastSkipRuleList = self:GetSkipRuleList(self.lastModelData)
            self.lastSpecialRuleList = self:GetSpecialRuleList(self.lastModelData)
            self.lastStepIgnoreNet = self:HasSpecialRule(self.lastSpecialRuleList, GuideSpecialRule.ignore_net)
        else
            self.lastModelData = nil
            self.lastStepIgnoreNet = false
        end
    end
end

---设置当前步骤
function Class:SetCurStep(curStep)
    if self.curStep ~= curStep then
        --HarryRedLog("SetCurStepTo: " .. self.id .. " " .. curStep)
        self.curStep = curStep
        if GuideStepModelData[self.id][self.curStep] ~= nil then
            self.curModelData = table.copy(GuideStepModelData[self.id][self.curStep])
            self.curSkipRuleList = self:GetSkipRuleList(self.curModelData)
            self.curSpecialRuleList = self:GetSpecialRuleList(self.curModelData)
            self.curStepIgnoreNet = self:HasSpecialRule(self.curSpecialRuleList, GuideSpecialRule.ignore_net)
        else
            self.curModelData = nil
            self.curSkipRuleList = nil
            self.curSpecialRuleList = nil
            self.curStepIgnoreNet = false
        end
    end

    if self.curModelData then
        ---计算特殊拖拽角色id
        local curSpecialDragRule = self:HasSpecialRulesInCurRules(self.curSpecialRuleList, SpecialDragFrom)
        if curSpecialDragRule then
            ---布阵拖拽
            local start, index = string.find(curSpecialDragRule, "pos_")
            local posId = tonumber(string.sub(curSpecialDragRule, index + 1))
            local mediator = GetMediator("WarReadyPanelMediator")
            if mediator then
                if mediator.readyScene then
                    if mediator.readyScene.roleSpineList[posId] then
                        self.dragRoleId = DeployDM:GetRoleIdByPlayerRoleId(mediator.readyScene.roleSpineList[posId].playerRoleId, nil, mediator.readyScene.warType)
                        --HarryRedLog("dragRole: " .. StringModelData[RoleModelData[self.dragRoleId].name])
                    else
                        printError("无法计算特殊拖拽角色id")
                    end
                else
                    printError("无法计算特殊拖拽角色id")
                end
            else
                printError("无法计算特殊拖拽角色id")
            end
        elseif table.ContainsValue(SpecialDrag, self.curModelData.finish_rule) then
            ---卡牌拖拽
            local index = string.find(self.curModelData.trigger_object, "_")
            self.dragRoleId = tonumber(string.sub(self.curModelData.trigger_object, index + 1))
            --HarryRedLog("dragRole: " .. StringModelData[RoleModelData[self.dragRoleId].name])
        end
    end
end

---设置执行步骤
---@param isCur boolean 是否是当前引导 true使用当前引导数据 false使用上一步数据
function Class:SetExecuteStep(isCur)
    --HarryRedLog("guide " .. self.id .. " set execute step")
    if isCur then
        if self.executeStep ~= self.curStep then
            self.executeStep = self.curStep
            --HarryRedLog("exeStep: " .. self.executeStep)
            self.executeModelData = table.copy(self.curModelData)
            self.executeSkipRuleList = table.copy(self.curSkipRuleList)
            self.executeSpecialRuleList = table.copy(self.curSpecialRuleList)
        end
    else
        if self.executeStep ~= self.lastStep then
            self.executeStep = self.lastStep
            --HarryRedLog("exeStep: " .. self.executeStep)
            self.executeModelData = table.copy(self.lastModelData)
            self.executeSkipRuleList = table.copy(self.lastSkipRuleList)
            self.executeSpecialRuleList = table.copy(self.lastSpecialRuleList)
        end
    end


end

---获取跳过条件表
function Class:GetSkipRuleList(modelData)
    return string.split(modelData.skip_rule, "|")
end

---获取特殊条件表
function Class:GetSpecialRuleList(modelData)
    return string.split(modelData.special_rule, "|")
end
--endregion


--region 任务流程
---初始化时的一些特殊处理
function Class:InitSpecial()
    ---特殊处理
    ---修改了notifyPanelManager的stopShow
    self.hasModifyStopShow = false

    ---主角升级条件特殊处理
    self.roleLevel = 0                                                --女娲等级
    if self.curModelData.finish_rule == GuideCont.nv_wa_upgrade then
        self.roleLevel = playerData.keyData[PlayerKeyData.role_level]
    end

    ---动态路径修改标记(每步只检查一次)
    self.hasModifyPath = false

    if self:HasSpecialRule(self.curSpecialRuleList, GuideSpecialRule.can_not_show_new_func_panel) then
        ---抑制新功能开启
        NotifyPanelManager.AddCantShowType(MainNotifyTypeEnum.NEW_FUNC)
        NotifyPanelManager.AddCantShowType(MainNotifyTypeEnum.NEW_HUAN_JING)
        self.canNotShowNewFuncPanel = true
    end

    ---如果是友情召唤引导 提前请求推荐好友数据
    if self.id == GuideSign.guide_function_you_qing_zhao_huan then
        GetProxy("FriendProxy"):GetRecommendFriend()
    end
end

---检查是否可执行引导步骤
function Class:CheckPath()
    if self.checkPathTimerId ~= nil then
        DelFrameTask(self.checkPathTimerId)
    end
    --每一帧都查找触发路径
    self.checkPathTimerId = AddFrameTask(
        function()
            if proxy:CanShowGuide() then
                self:CheckIsFound()
            elseif self.isExecuting then
                self:StopTask()
            end
        end,
        1,
        0)
end

---每帧执行
function Class:CheckIsFound()
    ---动态路径实现(每步只做一次)
    self:CheckDynamicPath(self.curSpecialRuleList, self.curModelData)
    ---当前步骤有优先权 如果此时自己的上一步正在执行 要将其替代
    local isCurTop = false
    isCurTop = self.curModelData.panel_name == ""
            or PanelManager.CheckIsTopPanelIgnoreGuidePanel(self.curModelData.panel_name)
    local curGo = GameObject.Find(self.curModelData.trigger_object)
    local curTarget = GameObject.Find(self.curModelData.target_object)

    ---trigger找到了会触发 但是target如果没找到 也不能执行引导(不然GuidePanel会显示错误 点击后也会报错)
    local foundCurPath = curGo ~= nil and curGo.activeInHierarchy and curTarget ~= nil and curTarget.activeInHierarchy
    --and IsInScreen(curGo.transform.position)

    local isLastTop = false
    local lastGo = nil
    local lastTarget = nil
    local foundLastPath = false

    if self.lastModelData ~= nil then
        ---动态路径实现
        self:CheckDynamicPath(self.lastSpecialRuleList, self.lastModelData)
        isLastTop = self.lastModelData.panel_name == "" or PanelManager.CheckIsTopPanelIgnoreGuidePanel(self.lastModelData.panel_name)
        lastGo = GameObject.Find(self.lastModelData.trigger_object)
        lastTarget = GameObject.Find(self.lastModelData.target_object)
        foundLastPath = lastGo ~= nil and lastGo.activeInHierarchy and lastTarget ~= nil and lastTarget.activeInHierarchy
        --and IsInScreen(lastGo.transform.position)
    end

    self:SetDynamicPathFlag(true)

    ---网络请求中 不做引导（这时候很有可能要开其他的面板 此时执行 会引起闪烁问题）

    local canExecuteCurStep = foundCurPath and not self.hasFoundCurPath and isCurTop and (self.curStepIgnoreNet or not GameDefine.inProcess)
    local shouldStopCurStep = (not foundCurPath or not isCurTop or (not self.curStepIgnoreNet and GameDefine.inProcess)) and self.hasFoundCurPath

    local canExecuteLastStep = foundLastPath and not self.hasFoundLastPath and isLastTop and not canExecuteCurStep and (self.lastStepIgnoreNet or not GameDefine.inProcess)
    local shouldStopLastStep = (not foundLastPath or canExecuteCurStep or (not self.lastStepIgnoreNet and GameDefine.inProcess)) and self.hasFoundLastPath
    if canExecuteLastStep then
        ---找到了上一步 执行上一步
        self.hasFoundLastPath = true
        self:SetExecuteStep(false)
        --HarryRedLog("Add To List Last. id: " .. self.id .. " executeStep: " .. self.executeStep)
        proxy:AddToFoundList(self.id)
    elseif shouldStopLastStep then
        ---上一步本来在执行 但是现在找不到上一步路径或者引导受到抑制 中断引导
        self.hasFoundLastPath = false
        --HarryRedLog("Remove From List . Last.id: " .. self.id .. " executeStep: " .. self.executeStep)
        self:RemoveFromFoundList()
    end

    if canExecuteCurStep then
        ---找到当前步骤 执行当前步骤
        self.hasFoundCurPath = true
        self:SetLastStep(0)
        self:SetExecuteStep(true)
        --HarryRedLog("findPath?: " .. tostring(foundCurPath)
        --        .. " foundPath?: " .. tostring(self.hasFoundCurPath)
        --        .. " isCurTop?: " .. tostring(isCurTop)
        --        .. " ignoreNet?: " .. tostring(self.curStepIgnoreNet)
        --        .. " inProcess?: " .. tostring(GameDefine.inProcess)
        --)
        --HarryRedLog("Add To List Cur. id: " .. self.id .. " executeStep: " .. self.executeStep)
        proxy:AddToFoundList(self.id)
    elseif shouldStopCurStep then
        ---当前步骤本来在执行 但是路径不再能找到或者被抑制 中断引导
        self.hasFoundCurPath = false
        --HarryRedLog("findPath?: " .. tostring(foundCurPath)
        --        .. " foundPath?: " .. tostring(self.hasFoundCurPath)
        --        .. " isCurTop?: " .. tostring(isCurTop)
        --        .. " ignoreNet?: " .. tostring(self.curStepIgnoreNet)
        --        .. " inProcess?: " .. tostring(GameDefine.inProcess)
        --)
        --HarryRedLog("Remove From List. Cur.id: " .. self.id .. " executeStep: " .. self.executeStep)
        self:RemoveFromFoundList()
    end
end

---执行引导
function Class:Execute()
    --HarryRedLog("Execute guide id: " .. self.id .. " step: " .. self.executeStep)

    ---记录引导开始执行时间点
    if self.executeStep == 1 then
        self.startTime = playerData.GetServerTime()
    end

    ---执行时 先检查是否跳过
    if self:CheckIsCanSkip(self.executeStep, self.executeSkipRuleList, self.executeSpecialRuleList) then
        self.isSkip = true
        self:DoNextStep(false, self.executeStep)
        self:ReportGuide(GuideAction.Skip)
        return
    end

    ---数据上报
    self:ReportGuide(GuideAction.Execute)

    --某些引导要做特殊处理
    self:CheckSpecialGuide()

    ---秦时明月特殊处理
    if self:HasSpecialRule(self.curSpecialRuleList, GuideSpecialRule.maze_act)
            and GetProxy("Maze3dProxy"):GetCurFunctionId() ~= FunctionEnum.maze_3d_act then
        self:StopTask()
        return
    end

    SendNotification({ CMD_GUIDE_PANEL_RESET })
    SendNotification({ CMD_DO_GUIDE_TASK, self.id, self.executeStep, self.executeModelData })
    self.isExecuting = true

    --更新检测函数
    self:UpdateCheckCompleteAction()
    --创建完成计时器
    self:CheckIsComplete()
end

---检查某步是否可以跳过
function Class:CheckIsCanSkip(step, skipRuleList, specialRuleList)
    if not proxy:CanShowGuide() or self:HasSpecialRule(specialRuleList, GuideSpecialRule.not_open) then
        return false
    end
    for k, v in ipairs(skipRuleList) do
        local rule = v
        local isTrue = false
        --特殊处理jump_before 特殊性在于 这个条件检查时 可能不能找到这个引导触发的路径 curGuideId就会是0
        if rule == GuideCont.jump_before then
            isTrue = self.skipStepList[step - 1]
        else
            isTrue = not string.isNilOrEmpty(rule) and proxy.skipFunc[rule](self)
        end
        if isTrue then
            self.skipStepList[step] = true
            --HarryRedLog("skip step: " .. step)
            return true
        end
    end
    self.skipStepList[step] = false
    return false
end

---外部使用 检查某步是否可以跳过
function Class:Public_CheckIsCanSkip()
    local modelData = table.copy(GuideStepModelData[self.id][self.curStep])
    local skipRuleList = self:GetSkipRuleList(modelData)
    local curSpecialRuleList = self:GetSpecialRuleList(modelData)
    local canSkip = self:CheckIsCanSkip(self.curStep, skipRuleList, curSpecialRuleList)

    ---特殊情况这一步不允许执行
    local specialCantExecute = false
    if self:HasSpecialRule(curSpecialRuleList, GuideSpecialRule.maze_act) then
        if GetProxy("Maze3dProxy"):GetCurFunctionId() ~= FunctionEnum.maze_3d_act then
            specialCantExecute = true
        end
    end
    return canSkip or specialCantExecute
end

---更新完成条件检查方法
function Class:UpdateCheckCompleteAction()
    local rule = self.executeModelData.finish_rule or ""
    self.checkCompleteAction = proxy.completeCheckFunc[rule]
end

---创建完成条件检查计时器
function Class:CheckIsComplete()
    if self.checkCompleteTimerId ~= nil then
        DelFrameTask(self.checkCompleteTimerId)
        self.checkCompleteTimerId = nil
    end

    self.checkCompleteTimerId = AddFrameTask(
        function()
            if self.isClear then
                if self.checkCompleteTimerId ~= nil then
                    DelFrameTask(self.checkCompleteTimerId)
                end
                return
            end
            if self.checkCompleteAction(self) then
                self:DoNextStep(true, self.executeStep)
            end
        end
    , 0, 0)
end

---检查特殊处理(引导步骤开始执行前)
function Class:CheckSpecialGuide()
    local rules = string.split(self.executeModelData.special_rule, "|")
    for _, v in ipairs(rules) do
        proxy.specialGuideFunc[v]()
    end
end

---进入下一步前的收尾工作
function Class:BeforeDoNextStep()
    --某些引导完成时要做特殊处理
    ---清理完成检查计时器
    if self.checkCompleteTimerId ~= nil then
        DelFrameTask(self.checkCompleteTimerId)
        self.checkCompleteTimerId = nil
    end

    if self.isSkip then
        ---跳过条件生效 如果有skip_guide特殊条件 跳过整个引导
        if self:HasSpecialRule(self.executeSpecialRuleList, GuideSpecialRule.skip_guide) then
            proxy:SkipTask(self.id)
        end
    else
        self:CheckDelay()
    end

    ---如果是引导终结步骤 告诉服务器关闭这个引导
    if GetBool(self.curModelData.is_end) then
        self.isClosed = true
        ---主角升级特殊处理
        if self:SpecialFailNvWaLevelSkip(self.executeSpecialRuleList) then
            GetProxy("GuideTaskProxy"):SkipTask(self.id)
        else
            ---引导完成
            if self:HasSpecialRule(self.executeSpecialRuleList, GuideSpecialRule.delay_guide_close) then
                ---标记为延迟同步关闭引导
                proxy:AddDelayCloseGuide({ self.id })
            else
                proxy:CheckRelatedGuide(self.id)
            end
        end
    end
    ---完成引导时的特殊处理
    self:CheckSpecialGuideComplete()
    ---清除引导标记
    self.hasFoundCurPath = false
    self.hasFoundLastPath = false

    ---重置引导面板
    SendNotification({ CMD_GUIDE_PANEL_RESET })

    ---关闭面板 是为了在下一步时OpenPanel增加GuidePanel的层级 保持在最顶层
    self:RemoveFromFoundList()
end


---执行下一步(执行完成 以及 跳过 都会走这里)
---needSync 引导需要同步(需要上一步和最新的步骤同时查找)
function Class:DoNextStep(needSync, curStep)
    ---默认传入当前执行步骤
    curStep = curStep or self.executeStep
    --HarryRedLog("DoNextStep: " .. curStep + 1)

    ---结束步骤收尾
    self:BeforeDoNextStep()

    ---上一步数据不再需要
    self:SetLastStep(0)
    ---更新当前步骤
    self:SetCurStep(curStep + 1)

    ---跳过标记重置
    self.isSkip = false
    ---延迟标记重置
    self.hasDelay = false
    ---动态路径修改标记重置
    self:SetDynamicPathFlag(false)
    if GuideStepModelData[self.id][self.curStep] == nil then
        ---已经是最后一步
        if self.isCycle then
            ---循环引导回到开头
            --HarryRedLog("cycle guide")
            self:SetCurStep(1)
            ---重置语音
            self.curVoiceStep = 0
        else
            ---普通引导则关闭引导
            self:ReportGuide(GuideAction.Finish)
            proxy:CloseTask(self.id)
        end
    else
        ---还有步骤可以执行
        if needSync then
            ---需要和上一步一起查找
            self:SetLastStep(curStep)
        end
        ---直接检查下一步的跳过条件(此时不确定有没有找到下一步路径)
        if self:CheckIsCanSkip(self.curStep, self.curSkipRuleList, self.curSpecialRuleList) then
            self.isSkip = true
            self:DoNextStep(false, self.curStep)
            self:ReportGuide(GuideAction.Skip)
        else
            ---传承升级特殊处理
            if self.curModelData.finish_rule == GuideCont.nv_wa_upgrade then
                self.roleLevel = playerData.keyData[PlayerKeyData.role_level]
            end
            ---更新了步骤数据后 会在下一帧CheckIsFound 然后执行下一步
        end
    end


end

---检查是否延时(一定时间内 不允许玩家点击)
function Class:CheckDelay()
    if self.isSkip then
        ---跳过条件生效 如果有skip_guide特殊条件 跳过整个引导
        if self:HasSpecialRule(self.curSpecialRuleList, GuideSpecialRule.skip_guide) then
            proxy:SkipTask(self.id)
        end
        return false
    elseif self.curModelData.delay > 0 then
        self:Delay(self.curModelData.delay)
        return true
    else
        return false
    end
end

---延时
---@param durationMs number @持续时间，毫秒
function Class:Delay(durationMs)
    if durationMs == nil or durationMs == 0 then
        return
    end
    --print("durationMs:" .. tostring(durationMs))
    --HarryRedLog("delay seconds: " .. durationMs)
    self.hasDelay = true
    proxy:AddGuideControl(GuideControlId.DELAY)
    Block(BlockCause.Guide, durationMs, function()
        proxy:RemoveGuideControl(GuideControlId.DELAY)
    end)
end

---中断任务
function Class:StopTask()
    --HarryRedLog("stop task id: " .. self.id)
    self.hasFoundCurPath = false
    self.hasFoundLastPath = false
    self:RemoveFromFoundList()
end

---从发现列表中移除
function Class:RemoveFromFoundList()
    proxy:RemoveFromFoundList(self.id)
    if self.isExecuting then
        PanelManager.ClosePanel("GuidePanel")
    end
    self.isExecuting = false
end

---特殊处理(引导步骤完成后)
function Class:CheckSpecialGuideComplete()
    local rules = string.split(self.executeModelData.special_rule, "|")
    for _, v in ipairs(rules) do
        if v == GuideSpecialRule.battle_pause then
            SendNotification({ CMD_PAUSE_WAR_SCENE, false })
        elseif v == GuideSpecialRule.guide_pi_xiu_click_area then
            proxy.piXiuMustRun = false
        elseif v == GuideSpecialRule.sky_road_refresh then
            SendNotification({ ON_ACCESS_TO_SKY_GUIDE_FINISH })
        elseif v == GuideSpecialRule.open_pi_xiu_save_panel then
            OpenPanel("PiXiuUnlockPanel", PanelManager.mainCanvas, "Guide", CMD_SAVE_PI_XIU_GUIDE_ID, self.id)
        elseif v == GuideSpecialRule.open_scroll_panel then
            OpenPanel("ScrollOpenPanel", PanelManager.mainCanvas, "Guide", CMD_SAVE_PI_XIU_GUIDE_ID, self.id)
        elseif v == GuideSpecialRule.open_one_draw_panel then
            OpenPanel("HuanJingUnlockPanel", PanelManager.mainCanvas, "Guide", CMD_SAVE_PI_XIU_GUIDE_ID, self.id)
        end
    end

    if table.ContainsValue(SpecialDrag, self.executeModelData.finish_rule) then
        ---需要刷新头像列表
        SendNotification({ CMD_ROLE_DRAG_ON_STAGE_END })
    end
end

---特殊处理(引导任务被跳过后)
function Class:AfterSkipTask()
    for _, v in ipairs(self.executeSpecialRuleList) do
        if v == GuideSpecialRule.battle_pause then
            SendNotification({CMD_PAUSE_WAR_SCENE, false})
        elseif v == GuideSpecialRule.guide_pi_xiu_click_area then
            proxy.piXiuMustRun = true
        end
    end

    if GuideSign.guide_function_access_to_sky_1 == self.id
        or GuideSign.guide_activity_access_to_sky == self.id then
        --HarryRedLog("send ON_ACCESS_TO_SKY_GUIDE_FINISH")
        SendNotification({ON_ACCESS_TO_SKY_GUIDE_FINISH})
    end
end

---特殊处理(clear时)
function Class:ClearSpecial()
    ---第六章弹窗流程 让剧情对话先出来
    if self.hasModifyStopShow then
        NotifyPanelManager.stopShow = false
        NotifyPanelManager.TryShowNotifyPanel()
    end
end
--endregion


--region 特殊处理
---检查特殊规则
function Class:HasSpecialRule(ruleList, rule)
    return table.ContainsValue(ruleList, rule)
end

---检查当前正在执行步骤的特殊规则是否含有一系列规则之一
function Class:HasSpecialRuleInRules(ruleList)
    for _, v in pairs(ruleList) do
        if self:HasSpecialRule(self.executeSpecialRuleList, v) then
            return v
        end
    end
    return false
end

function Class:HasSpecialRulesInCurRules(useRuleList, ruleList)
    for _, v in pairs(ruleList) do
        if table.ContainsValue(useRuleList, v) then
            return v
        end
    end
    return false
end

---特殊处理 动态路径修改
function Class:CheckDynamicPath(specialRuleList, modelData)
    if self.hasModifyPath then
        return
    end
    if self:HasSpecialRule(specialRuleList, GuideSpecialRule.drag_main_role) then
        modelData.trigger_object = "CanvasContainers/MainCanvas/WarReadyPanel/Center/Bottom/BuZhenPanel/SelectArea/Viewport/Content/RoleItem_" .. playerData.keyData[PlayerKeyData.main_role_id]
    elseif self:HasSpecialRule(specialRuleList, GuideSpecialRule.main_role_qi_shi_tiao) then
        --modelData.trigger_object = "WarSceneMission_kai_tian_pi_di(Clone)/name" .. playerData.keyData[PlayerKeyData.main_role_id] .. "/RoleWarUI(Clone)/Root/Top/Effect_qishitiao"
        --modelData.target_object = "WarSceneMission_kai_tian_pi_di(Clone)/name" .. playerData.keyData[PlayerKeyData.main_role_id] .. "/RoleWarUI(Clone)/Root/Top/Effect_qishitiao"
    elseif self:HasSpecialRule(specialRuleList, GuideSpecialRule.sky_road_chest) then
        local chestIndex = GetProxy("AccessToSkyProxy"):GetLastRewardLadderIndex()
        if chestIndex ~= nil then
            modelData.target_object = string.gsub(modelData.target_object, "199", chestIndex)
        end
    elseif self:HasSpecialRule(specialRuleList, GuideSpecialRule.samsara_vice_tower) then
        local proxy = GetProxy("SamsaraTowerProxy")
        local openViceTowerId = proxy:GetAnOpenViceTowerId()
        if openViceTowerId == nil then
            printError("副塔开启id查找失败 没有开启的副塔id 引导配置特殊条件位置错误 此时没有数据!")
        else
            modelData.trigger_object = "CanvasContainers/MainCanvas/SamsaraMainPanel/Content/Center/" .. proxy.viceTowerPath[openViceTowerId] .. "/Button"
            modelData.target_object = "CanvasContainers/MainCanvas/SamsaraMainPanel/Content/Center/" .. proxy.viceTowerPath[openViceTowerId] .. "/Button"
        end
    elseif self:HasSpecialRule(specialRuleList, GuideSpecialRule.secret_script_first_level_up) then
        -- 法天象地修炼引导
        local scriptId, nodeId = SecretScriptProxy:GetCurViewScriptFirstCanLevelUpNode()
        if scriptId == 0 or nodeId == 0 then
            printError("没有找到可升级的nodeId!")
        else
            local treeMark = SecretScriptModelData[scriptId].node_mark
            modelData.trigger_object = "CanvasContainers/MainCanvas/SecretScriptDetailPanel/XiuLianPanel/NotMoveContent/trNodeList/" .. treeMark .. "(Clone)/ScrollView/Viewport/Content/Node_" .. nodeId .. "/NodeIcon/Click"
            modelData.target_object = "CanvasContainers/MainCanvas/SecretScriptDetailPanel/XiuLianPanel/NotMoveContent/trNodeList/" .. treeMark .. "(Clone)/ScrollView/Viewport/Content/Node_" .. nodeId .. "/NodeIcon/Click"
        end
    elseif self:HasSpecialRule(specialRuleList, GuideSpecialRule.secret_script_first_not_level_up) then
        -- 法天象地修炼引导
        local scriptId, nodeId = SecretScriptProxy:GetCurViewScriptFirstCantLevelUpNode()
        if scriptId == 0 or nodeId == 0 then
            printError("没有找到可升级的nodeId!")
        else
            local treeMark = SecretScriptModelData[scriptId].node_mark
            modelData.trigger_object = "CanvasContainers/MainCanvas/SecretScriptDetailPanel/XiuLianPanel/NotMoveContent/trNodeList/" .. treeMark .. "(Clone)/ScrollView/Viewport/Content/Node_" .. nodeId .. "/NodeIcon/Click"
            modelData.target_object = "CanvasContainers/MainCanvas/SecretScriptDetailPanel/XiuLianPanel/NotMoveContent/trNodeList/" .. treeMark .. "(Clone)/ScrollView/Viewport/Content/Node_" .. nodeId .. "/NodeIcon/Click"
        end
    end
end

---手动修改路径
function Class:SetPath(triggerPath, targetPath)
    self.curModelData.trigger_object = triggerPath
    self.curModelData.target_object = targetPath
    --HarryRedLog("set path complete")
end

---设置动态路径修改标记
function Class:SetDynamicPathFlag(flag)
    self.hasModifyPath = flag
end

---特殊条件触发的跳过步骤
function Class:SpecialSkipStep()
    --HarryRedLog("特殊跳过")
    self.skipStepList[self.executeStep] = true
    self.isSkip = true
    self:DoNextStep(false, self.executeStep)
    self:ReportGuide(GuideAction.Skip)
end

---主角升级引导特殊跳过方式
function Class:SpecialFailNvWaLevelSkip(skipRuleList)
    for _, v in ipairs(skipRuleList) do
        if table.ContainsValue(FailNvWaLevel, v) then
            return true
        end
    end
    return false
end
--endregion


--region getters
---正在执行步骤是否为强制引导
function Class:IsForceGuide()
    return self.executeModelData.is_force == 1
end

---正在执行步骤是否含特殊条件not_exit
function Class:IsNotExit()
    return self:HasSpecialRule(self.executeSpecialRuleList, GuideSpecialRule.not_exit)
end

---引导是否已抵达结束步骤
function Class:GetIsClosed()
    return self.isClosed
end

---引导设置为结束
function Class:SetIsClose(flag)
    self.isClosed = flag
end

---是否可以播放语音
function Class:CanPlayVoice()
    ---避免重复播放 每段语音只播一次
    return self.executeStep > self.curVoiceStep
end

function Class:TryPlayVoice()
    if self:CanPlayVoice() then
        self.curVoiceStep = self.executeStep
        AudioController.PlayRoleVoice(self.executeModelData.audio)
    end
end


--endregion

--region 清理
function Class:ClearAllTimers()
    if self.checkCompleteTimerId ~= nil then
        DelFrameTask(self.checkCompleteTimerId)
        self.checkCompleteTimerId = nil
    end
    if self.checkPathTimerId ~= nil then
        DelFrameTask(self.checkPathTimerId)
        self.checkPathTimerId = nil
    end
end

function Class:Clear()
    if self.canNotShowNewFuncPanel then
        ---解除抑制新功能开启
        NotifyPanelManager.RemoveCantShowType(MainNotifyTypeEnum.NEW_FUNC)
        NotifyPanelManager.RemoveCantShowType(MainNotifyTypeEnum.NEW_HUAN_JING)
        self.canNotShowNewFuncPanel = false
    end

    ---关闭的这个任务如果在执行 也要关闭GuidePanel
    if self.isExecuting then
        ClosePanel("GuidePanel")
    end

    ---清除计时器
    self:ClearAllTimers()

    self:ClearSpecial()
    self.checkCompleteAction = nil
    self.isClear = true
end
--endregion

--region 数据上报

GuideAction = {
    Execute = 1, --执行步骤
    Finish = 2, --完成引导（非跳过）
    Skip = 3, -- 跳过引导
}

---上报引导
function Class:ReportGuide(action)
    if self.startTime == 0 then
        self.startTime = playerData.GetServerTime()
    end
    local duringTime = playerData.GetServerTime() - self.startTime
    local tab = C_ThinkingAnalyticsManager:GetDicStringAndObject()
    tab.tutorial_id = self.id
    tab.sub_tutorial_id = self.curStep
    tab.tutorial_name = StringModelData[GuideModelData[self.id].name]
    tab.sub_tutorial_name = ""
    tab.action = action
    tab.duration = math.ceil(duringTime)

    C_ThinkingAnalyticsManager:Track("oss_tutorial_flow", tab)
end
--endregion

return Class
