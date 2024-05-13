---滑动
function Class:Slide(command)
    self.canInput = false
    proxy.needCombineTimes = 0
    proxy.needMove = false
    ---设置父子关系 计算需要合并多少次
    for i = 1, 16 do
        self.cellList[i]:OnSlide(command)
    end
    ---播放滑动音效
    if proxy.needMove then
        PlaySound("common_chose_02")
    end
    ---触发移动合并
    for i = 1, 16 do
        if self.cellList[i].fill ~= nil then
            self.cellList[i].fill:MoveAndComebine()
        end
    end
end

---递归 向上滑 从上往下找
---@param curCell Cell2048
function Class:SlideUp(curCell)
    if curCell.down == nil then
        return
    end
    if curCell.fill ~= nil then
        ---当前格子有值
        local nextCell = curCell.down
        while nextCell.fill == nil and nextCell.down ~= nil do
            nextCell = nextCell.down
        end
        if nextCell.fill ~= nil then
            if nextCell.fill.id == curCell.fill.id and nextCell.fill:CanDouble() then
                ---找到了合并值
                nextCell.fill:Double()
                nextCell.fill.gameObject.transform.parent = curCell.gameObject.transform
                curCell.fill = nextCell.fill
                nextCell.fill = nil
                proxy.needMove = true
            elseif curCell.down.fill ~= nextCell.fill then
                ---有空格
                nextCell.fill.gameObject.transform.parent = curCell.down.gameObject.transform
                curCell.down.fill = nextCell.fill
                nextCell.fill = nil
                proxy.needMove = true
            end
        end
    else
        ---当前格子没值
        local nextCell = curCell.down
        while nextCell.fill == nil and nextCell.down ~= nil do
            nextCell = nextCell.down
        end
        if nextCell.fill ~= nil then
            ---找到有值的格子 移到当前空格
            nextCell.fill.gameObject.transform.parent = curCell.gameObject.transform
            curCell.fill = nextCell.fill
            nextCell.fill = nil
            proxy.needMove = true
            self:SlideUp(curCell)
        end
    end
    self:SlideUp(curCell.down)
end

function Class:MoveAndComebine()
    if self.gameObject.transform.localPosition ~= Vector3.zero then
        self.hasComebine = false
        if self.moveTween ~= nil then
            DoTweenProxy.DoKill(self.moveTween)
            self.moveTween = nil
        end
        self.moveTween = DoTweenProxy.TweenToLocalPos(self.gameObject.transform, Vector3.zero, 0.1,
                function()
                    ---移动结束后合并
                    if self.gameObject.transform.parent:GetChild(0) ~= self.gameObject.transform then
                        --self:Double()
                        SetUIActive(self.effectCombine, false)
                        SetUIActive(self.effectCombine, true)
                        SendNotification({ CMD_2048_CLEAR_FILL, self.gameObject.transform.parent:GetChild(0).gameObject })
                        proxy.needCombineTimes = proxy.needCombineTimes - 1
                        --HarryRedLog("need combine times: " .. proxy.needCombineTimes)
                    end
                    ---检查是否需要生成新方块
                    if proxy.needCombineTimes == 0 then
                        ---生成新的方块
                        --- -1标志此次滑动已经生成过
                        proxy.needCombineTimes = -1
                        SendNotification({ CMD_2048_SPAWN_NEW_FILL })
                    end
                end
        )
    end
end