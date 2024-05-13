---@class GuideProxy:Proxy
local Class = class("GuideProxy", PureMVC.Proxy.new())

GuideType = {
    Strong = 1, --强引导
    Weak = 2 --弱引导
}

GuideCheckRules = {
    mission_id = 1, --主线通关后
    function_open = 2, --功能开放
    fail_mission_id = 3, --主线副本战败后
    super_mission_id = 4, --精英副本通关后
    fail_super_mission_id = 5, --精英副本失败后
    finish_guide = 6, --完成引导
    skip_guide = 7, --跳过引导
    skip_or_finish_guide = 8, --跳过或者完成引导
}

function Class:OnRegister()
    --引导任务列表
    self.guideIdList = {}

    ---同步等待计时器
    self.waitTimerId = nil
    ---最多重传三次
    self.reconnectTime = 0

    ---初始化一些缓存 加快后续引导逻辑
    self:Private_InitGuideCache()

    ---是否需要再次检查引导id列表（创角后的延迟检查）
    self.needCheckGuideList = false
end

--region C2S
---更新服务器引导id列表
function Class:PushGuideIdList(guideIdList, time)
    ---组织信息
    local msg = guide_pb.PushGuideIdList()
    for _,v in ipairs(guideIdList) do
        table.insert(msg.guideIdList,v)
    end
    msg.version = time
    --HarryRedLog("PushGuideIdList")
    --print(msg)
    ---增加等待计时器 超时后重传
    if self.waitTimerId ~= nil then
        DelTimeTask(self.waitTimerId)
        self.waitTimerId = nil
    end
    self.waitTimerId = AddTimeTask(
        function()
            self.reconnectTime = self.reconnectTime + 1
            if self.reconnectTime <= 3 then
                --HarryRedLog("超时重传 PushGuideIdList")
                self:PushGuideIdList(guideIdList, time)
            end
        end,
        3000,
        1
    )

    local modId, funId = GetMSGID("guide", "PushGuideIdList")
    SendMSGToServer(modId, funId, msg)
end

--endregion

--region S2C
---登录同步开启的引导id列表
function Class:NotifyGuideIdList(pb)
    ---审核关闭引导
    if IsVerify then
        return
    end

    local msg = guide_pb.NotifyGuideIdList()
    msg:ParseFromString(pb)
    --HarryRedLog("登录同步引导id: ")
    --print(msg)
    ---未创角的时候不处理 延迟到创角后进入游戏时处理
    if playerData.playerId == 0 then
        self.tempServerGuideInfo = msg
        self.needCheckGuideList = true
        return
    end
    self:HandleServerGuideInfo(msg)
end

---通知开启引导id
function Class:NotifyGuideOpen(pb)
    local msg = guide_pb.NotifyGuideOpen()
    msg:ParseFromString(pb)
    --HarryRedLog("NotifyGuideOpen: "..msg.guideId)
    if self:Private_CheckIsGuideValid(msg.guideId) then
        self:Public_AddGuideIdList({msg.guideId})
    else
        printError("引导不满足开启条件："..msg.guideId)
    end
end

---通知关闭引导id
function Class:NotifyGuideClose(pb)
    local msg = guide_pb.NotifyGuideClose()
    msg:ParseFromString(pb)
    --HarryRedLog("NotifyGuideClose: "..msg.guideId)
    ---@type GuideTaskProxy
    local guideTaskProxy = GetProxy("GuideTaskProxy")
    --local guideTask = guideTaskProxy:GetGuideTaskById(msg.guideId)
    --if guideTask then
        --guideTask:ReportGuide(GuideAction.Close, 1)
    --end
    guideTaskProxy:CloseTask(msg.guideId)
    self:Public_RemoveGuideIdList({ msg.guideId })
end

---更新服务器引导id列表返回
function Class:PushGuideIdListReturn(pb)
    --HarryRedLog("PushGuideIdListReturn")
    local msg = guide_pb.PushGuideIdListReturn()
    msg:ParseFromString(pb)
    ProtolResultProcess(msg.resultInfo)
    self.reconnectTime = 0
    if self.waitTimerId ~= nil then
        DelTimeTask(self.waitTimerId)
        self.waitTimerId = nil
    end
end
--endregion

--region private
---检查是否需要重新同步
function Class:Recheck()
    if self.needCheckGuideList then
        self.needCheckGuideList = false
        self:HandleServerGuideInfo(self.tempServerGuideInfo)
    end
end

---处理服务端登录同步的引导id列表
function Class:HandleServerGuideInfo(msg)
    local useGuideIdList = {}
    ---首先取出本地引导id列表数据
    local localGuideInfo = self:Private_GetLocalGuideInfo()
    if localGuideInfo == nil then
        ---没有本地数据 使用服务端数据
        useGuideIdList = msg.guideIdList
    else
        ---有本地数据 对比服务端数据 选取新版本数据
        local localVersion = localGuideInfo.version
        local serverVersion = msg.version
        ---选新版本数据 时间戳相等选择本地数据
        if localVersion >= serverVersion then
            useGuideIdList = localGuideInfo.guideIdList
        else
            useGuideIdList = msg.guideIdList
        end
    end
    ---合法性检查
    self.guideIdList = self:Private_CheckGuideIdList(useGuideIdList)
    ---更新本地并同步到服务端
    self:Private_SaveGuideIdListToLocal()
    ---开启引导
    ---@type GuideTaskProxy
    local guideTaskProxy = GetProxy("GuideTaskProxy")
    for _,v in ipairs(self.guideIdList) do
        guideTaskProxy:CreateTask(v)
    end
end

---当前的引导id列表存到本地设备
function Class:Private_SaveGuideIdListToLocal()
    local key = "GuideData_"
        .. playerData.playerId
    local res = ""
    for k, v in ipairs(self.guideIdList) do
        if k == 1 then
            res = res  .. v
        else
            res = res .."_".. v
        end
    end
    local version = playerData.GetServerTime()
    res = res .. "|" .. version
    PlayerPrefs.SetString(key, res)
    --HarryRedLog("save str key "..key.." res: "..res)
    self:PushGuideIdList(self.guideIdList,version)
end

---获取当前设备本地的引导信息
---nil表示没有设置过值
function Class:Private_GetLocalGuideInfo()
    local key = "GuideData_" .. playerData.playerId
    local res = {}
    local localValue = PlayerPrefs.GetString(key, "NoValue")
    if localValue == "NoValue" then
        return nil
    else
        local str = string.split(localValue, "|")
        ---引导id
        local idStr = string.split(str[1], "_")
        --TODO 测一下 空引导id表加上时间戳的数据 是否符合预期
        local idList = {}
        for _, v in ipairs(idStr) do
            if not string.isNilOrEmpty(v) then
                table.insert(idList, tonumber(v))
            end
        end
        ---时间戳
        local version = tonumber(str[2])

        res.version = version
        res.guideIdList = idList
        --PrintTable("get local guideInfo: " , res)
        return res
    end
end

---检查引导列表 返回合法的引导id列表
function Class:Private_CheckGuideIdList(guideIdList)
    local inValidGuideIdList = {}
    for _, v in ipairs(guideIdList) do
        if not self:Private_CheckIsGuideValid(v) then
            table.insert(inValidGuideIdList, v)
        end
    end
    return self:Private_CloseInvalidGuideList(guideIdList, inValidGuideIdList)
end

---引导合法性检查
---返回是否合法
function Class:Private_CheckIsGuideValid(guideId)
    if GuideModelData[guideId] == nil then
        ---非法的guideId值
        return false
    end
    ---检查出现条件 通过检查才可以存在
    local openRule = GuideModelData[guideId].open_type
    local openParam = GuideModelData[guideId].open_value
    local canOpenCheck = true
    if openRule == 0 then
        ---没有开启规则默认合法
        canOpenCheck = true
    elseif openRule == GuideCheckRules.mission_id then
        ---检查主线进度是否已经达到
        ---@type MissionProxy
        local missionProxy = GetProxy("MissionProxy")
        canOpenCheck = missionProxy.curMissionId >= openParam
    elseif openRule == GuideCheckRules.super_mission_id then
        ---@type SuperMissionProxy
        local superMissionProxy = GetProxy("SuperMissionProxy")
        canOpenCheck = superMissionProxy:IsSuperMissionIdPassed(openParam)
    elseif openRule == GuideCheckRules.function_open then
        canOpenCheck = table.ContainsValue(playerData.openFunctionList, openParam)
    end
    ---没有通过开启条件检查
    if not canOpenCheck then
        return false
    end
    ---检查消失条件
    local closeRule = GuideModelData[guideId].close_type
    local closeParam = GuideModelData[guideId].close_value
    local shouldCloseCheck = false
    if closeRule == 0 then
        ---没有消失条件 默认合法
        shouldCloseCheck = false
    elseif closeRule == GuideCheckRules.super_mission_id then
        ---@type SuperMissionProxy
        local superMissionProxy = GetProxy("SuperMissionProxy")
        shouldCloseCheck = superMissionProxy:IsSuperMissionIdPassed(closeParam)
    elseif closeRule == GuideCheckRules.mission_id then
        ---@type MissionProxy
        local missionProxy = GetProxy("MissionProxy")
        shouldCloseCheck = missionProxy.curMissionId >= closeParam
    end
    ---如果应该消失
    if shouldCloseCheck then
        return false
    end

    ---通过合法性检查
    return true
end

---检查到不合法的引导id 要关闭与其相关的引导 返回剩下的合法列表
---@param curGuideIdList @  当前合法列表
---@param invalidGuideIdList @ 当前要剔除的非法列表
function Class:Private_CloseInvalidGuideList(curGuideIdList, invalidGuideIdList)
    ---空表的情况
    if next(invalidGuideIdList) == nil then
        return curGuideIdList
    end

    ---当前合法列表
    local _curGuideIdList = {}
    for _, v in ipairs(curGuideIdList) do
        table.insert(_curGuideIdList, v)
    end
    --PrintTable("筛选前: ", _curGuideIdList)

    ---当前要剔除的非法列表
    local curInvalidGuideIdList = table.copy(invalidGuideIdList)

    --PrintTable("当前合法：", _curGuideIdList)
    --PrintTable("当前非法：", curInvalidGuideIdList)

    ---直到非法id列表为空
    ---在当前待筛选列表中找到需要关闭的引导 重新得到一份待筛选列表和非法id列表 继续相同操作
    while (next(curInvalidGuideIdList) ~= nil) do
        ---筛选得到当前的合法列表
        local guideIdList = table.copy(_curGuideIdList)
        _curGuideIdList = {}
        for _, v in ipairs(guideIdList) do
            if not table.ContainsValue(curInvalidGuideIdList, v) then
                table.insert(_curGuideIdList, v)
            end
        end
        --PrintTable("当前合法：", _curGuideIdList)
        ---找到所有的要关闭的关联引导
        local invalidList = table.copy(curInvalidGuideIdList)
        curInvalidGuideIdList = {}
        for _, v in ipairs(invalidList) do
            ---待筛选的列表
            ---获取非法id要关闭的列表
            local closeList = self:GetInvalidGuideCloseList(v)
            for k, id in ipairs(closeList) do
                if not table.ContainsValue(curInvalidGuideIdList, id)
                    and table.ContainsValue(_curGuideIdList, id)
                then
                    table.insert(curInvalidGuideIdList, id)
                end
            end
        end
        --PrintTable("当前非法：", curInvalidGuideIdList)
    end
    --PrintTable("筛选后: ", _curGuideIdList)
    return _curGuideIdList
end

---获取某个不合法引导的关联关闭引导
function Class:GetInvalidGuideCloseList(guideId)
    local closeList = {}
    ---检查跳过关联引导
    local relationIdList = self:Public_GetSkipRelationList(guideId)
    for k, id in ipairs(relationIdList) do
        if not table.ContainsValue(closeList, id) then
            table.insert(closeList, id)
        end
    end
    ---检查跳过此引导的消失条件（当前没这个检查）
    --local skipIdList = self:Private_GetCloseIdList(GuideCheckRules.skip_guide, guideId)
    --for k, id in ipairs(skipIdList) do
    --    if not table.ContainsValue(closeList, id) then
    --        table.insert(closeList, id)
    --    end
    --end
    ---检查关闭此引导的消失条件
    local closeIdList = self:Private_GetCloseIdList(GuideCheckRules.finish_guide, guideId)
    for k, id in ipairs(closeIdList) do
        if not table.ContainsValue(closeList, id) then
            table.insert(closeList, id)
        end
    end
    ---检查跳过或关闭此引导的消失条件
    local skipOrCloseIdList = self:Private_GetCloseIdList(GuideCheckRules.skip_or_finish_guide, guideId)
    for k, id in ipairs(skipOrCloseIdList) do
        if not table.ContainsValue(closeList, id) then
            table.insert(closeList, id)
        end
    end
    return closeList
end

---初始化引导逻辑需要的缓存
function Class:Private_InitGuideCache()
    ---规则 --》 开启的引导列表
    self.openGuideCheck = {}
    self.openGuideCheck[GuideCheckRules.mission_id] = {}
    self.openGuideCheck[GuideCheckRules.super_mission_id] = {}
    self.openGuideCheck[GuideCheckRules.fail_mission_id] = {}
    self.openGuideCheck[GuideCheckRules.fail_super_mission_id] = {}
    self.openGuideCheck[GuideCheckRules.function_open] = {}
    self.openGuideCheck[GuideCheckRules.finish_guide] = {}
    self.openGuideCheck[GuideCheckRules.skip_guide] = {}
    self.openGuideCheck[GuideCheckRules.skip_or_finish_guide] = {}

    ---规则 --》 消失的引导列表
    self.closeGuideCheck = {}
    self.closeGuideCheck[GuideCheckRules.mission_id] = {}
    self.closeGuideCheck[GuideCheckRules.super_mission_id] = {}
    self.closeGuideCheck[GuideCheckRules.finish_guide] = {}
    self.closeGuideCheck[GuideCheckRules.skip_or_finish_guide] = {}

    for _, v in pairs(GuideModelData) do
        ---开启规则
        local rule = v.open_type
        local ruleChecker = self.openGuideCheck[rule]
        if ruleChecker == nil  then
            if rule ~= 0 then
                printError("没有定义的引导开启检查规则！ rule: " .. rule)
            end
        else
            if ruleChecker[v.open_value] == nil then
                ruleChecker[v.open_value] = {}
            end
            table.insert(ruleChecker[v.open_value], v.id)
        end

        ---关闭规则
        local closeRule = v.close_type
        local closeRuleChecker = self.closeGuideCheck[closeRule]
        if closeRuleChecker == nil  then
            if closeRule ~= 0 then
                printError("没有定义的引导关闭检查规则！rule: " .. closeRule)
            end
        else
            if closeRuleChecker[v.close_value] == nil then
                closeRuleChecker[v.close_value] = {}
            end
            table.insert(closeRuleChecker[v.close_value], v.id)
        end
    end

    --PrintTable("openRuleChecker: ", self.openGuideCheck)
    --PrintTable("closeRuleChecker: ", self.closeGuideCheck)
end



---获取指定规则和参数开启的引导id列表
---@param checkRule number 检查的规则
---@param param number 检查的规则参数
---@return number[] 开启的引导id列表
function Class:Private_GetOpenIdList(checkRule, param)
    local res = {}
    if self.openGuideCheck[checkRule] == nil then
        printError("没有定义引导开启规则： " .. checkRule)
        return res
    end
    if self.openGuideCheck[checkRule][param] == nil then
        return res
    end
    res = self.openGuideCheck[checkRule][param]
    return res
end

---获取指定规则和参数关闭的引导id列表
function Class:Private_GetCloseIdList(checkRule, param)
    local res = {}
    if self.closeGuideCheck[checkRule] == nil then
        printError("没有定义引导关闭规则： " .. checkRule)
        return res
    end
    if self.closeGuideCheck[checkRule][param] == nil then
        return res
    end
    res = self.closeGuideCheck[checkRule][param]
    return res
end
--endregion

--region public
----------------------------------引导逻辑----------------------------------
---增加引导id
function Class:Public_AddGuideIdList(guideIdList)


    if #guideIdList ~= 0 then
        local hasAdd = false
        for _, guideId in ipairs(guideIdList) do
            ---去重
            if not table.ContainsValue(self.guideIdList, guideId) then
                hasAdd = true
                table.insert(self.guideIdList, guideId)
                ---创建引导任务
                ---@type GuideTaskProxy
                local guideTaskProxy = GetProxy("GuideTaskProxy")
                guideTaskProxy:CreateTask(guideId)
            end
        end
        if hasAdd then
            self:Private_SaveGuideIdListToLocal()
        end
    end
end

---移除一个引导id
---@param
---@return
function Class:Public_RemoveGuideIdList(guideIdList)
    if #guideIdList ~= 0 then
        for _,guideId in ipairs(guideIdList) do
            table.removebyvalue(self.guideIdList, guideId)
        end
        self:Private_SaveGuideIdListToLocal()
    end
end

---尝试开启新的引导
---@param checkRule number @引导触发条件
---@param param number @引导触发参数
function Class:Public_TryOpenNewGuide(checkRule, param)
    ---审核关闭引导
    if IsVerify then
        return
    end
    ---@type GuideTaskProxy
    local guideTaskProxy = GetProxy("GuideTaskProxy")
    local openGuideIdList = self:Private_GetOpenIdList(checkRule, param)
    if #openGuideIdList ~= 0 then
        self:Public_AddGuideIdList(openGuideIdList)
    end
end

---尝试关闭引导（不满足引导存在条件的）
---@param checkRule number @引导消失条件
---@param param number @引导消失参数
function Class:Public_TryCloseGuide(checkRule, param)
    ---审核关闭引导
    if IsVerify then
        return
    end
    ---@type GuideTaskProxy
    local guideTaskProxy = GetProxy("GuideTaskProxy")
    ---初次筛选 得到应该关闭的引导id列表
    local firstCloseGuideIdList = self:Private_GetCloseIdList(checkRule, param)
    ---第二次筛选 根据要关闭的引导id 关闭其关联的所有引导id
    ---当前存在的引导id列表
    local nowGuideIdList = guideTaskProxy:GetNowGuideIdList()
    ---筛选后剩下的合法引导id列表
    local validGuideIdList = self:Private_CloseInvalidGuideList(nowGuideIdList, firstCloseGuideIdList)
    ---要清除的引导id列表
    local closeGuideIdList = {}
    for _, v in ipairs(nowGuideIdList) do
        if not table.ContainsValue(validGuideIdList, v) then
            --local guideTask = guideTaskProxy:GetGuideTaskById(v)
            --if guideTask then
                --guideTask:ReportGuide(GuideAction.Close, 3)
            --end
            guideTaskProxy:CloseTask(v)
            table.insert(closeGuideIdList, v)
        end
    end
    ---更新引导id记录
    self:Public_RemoveGuideIdList(closeGuideIdList)
end

---获得这个引导的关联跳过引导id列表
function Class:Public_GetSkipRelationList(guideId)
    local res = {}
    if GuideModelData[guideId] == nil then
        printError("存在不存在模板数据的引导id 尝试GM清理引导")
        return res
    end
    res = string.split(GuideModelData[guideId].skip_relation_guide, "|")
    table.removebyvalue(res, "-1")
    table.removebyvalue(res, tostring(guideId))
    return res
    --PrintTable("ctor id: " .. self.id .. " skipList: ", res)
end

---添加新号初始引导
function Class:InitNewPlayerGuide()
    --HarryRedLog("init new player guide")
    local allOpenIdList = {}
    for _, v in ipairs(playerData.openFunctionList) do
        local openIdList = self:Private_GetOpenIdList(GuideCheckRules.function_open, v)
        for _, v in ipairs(openIdList) do
            table.insert(allOpenIdList, v)
        end
    end
    self:Public_AddGuideIdList(allOpenIdList)
end
--------------------------------引导逻辑 END--------------------------------


--endregion

function Class:OnRemove()
    if self.waitTimerId ~= nil then
        DelTimeTask(self.waitTimerId)
        self.waitTimerId = nil
    end
end

return Class
