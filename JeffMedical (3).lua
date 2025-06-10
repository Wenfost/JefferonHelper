local samp = require("samp.events")
local json = require("dkjson")
local imgui = require("mimgui")
local encoding = require("encoding")
encoding.default = "CP1251"
local u8 = encoding.UTF8
local new = imgui.new
local ffi = require("ffi")
local http = require("socket.http")
local ltn12 = require("ltn12")
local WinState = new.bool()
local savePath = "moonloader/config/invite_data.json"
local selectedTab = new.int(0)
local SALT = "unique_salt_9876543210"
local searchText = new.char[256]()
local binderDescription = new.char[256]()
local binderCommand = new.char[256]()
local binderText = new.char[256]()






local invitedData = {
    count = 0,
    players = {},
    rankPurchases = {},
    inviteNorma = 0,
    binders = {},
    lastReset = os.date("%Y-%m-%d"),
    checksum = ""
}

-- Ôóíêöèÿ äëÿ îáðåçêè ïðîáåëîâ
local function trim(str)
    return str and str:match("^%s*(.-)%s*$") or ""
end

local function calculateChecksum(data)
    local sum = tostring(data.count)
    for _, p in ipairs(data.players) do
        sum = sum .. p.name .. p.time
    end
    for _, p in ipairs(data.rankPurchases) do
        sum = sum .. p.name .. p.time .. p.price
    end
    for _, b in ipairs(data.binders or {}) do
        sum = sum .. b.description .. b.command .. (b.text or "")
    end
    sum = sum .. data.lastReset .. tostring(data.inviteNorma) .. SALT
    local checksum = 0
    for i = 1, #sum do
        checksum = checksum + string.byte(sum, i)
    end
    return tostring(checksum)
end

local function verifyData(data)
    local expectedChecksum = data.checksum or ""
    local tempChecksum = data.checksum
    data.checksum = ""
    local calculatedChecksum = calculateChecksum(data)
    data.checksum = tempChecksum
    return expectedChecksum == calculatedChecksum
end

local function formatWithCommas(number)
    local formatted = tostring(number)
    while true do
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

local function saveInvites()
    local currentDate = os.date("%Y-%m-%d")
    if invitedData.lastReset ~= currentDate then
        invitedData.players = {}
        invitedData.count = 0
        invitedData.rankPurchases = {}
        invitedData.binders = invitedData.binders or {}
        invitedData.lastReset = currentDate
    end
    invitedData.checksum = ""
    invitedData.checksum = calculateChecksum(invitedData)
    local file = io.open(savePath, "w")
    if file then
        file:write(json.encode(invitedData, { indent = true }))
        file:close()
    end
end

local function loadInvites()
    if doesFileExist(savePath) then
        local file = io.open(savePath, "r")
        local content = file:read("*a")
        file:close()
        local data = json.decode(content)
        if data then
            if verifyData(data) then
                invitedData = data
            else
                sampAddChatMessage("{FF0000}Îáíàðóæåíî èçìåíåíèå JSON-ôàéëà! Äàííûå ñáðîøåíû.", -1)
                invitedData = {
                    count = 0,
                    players = {},
                    rankPurchases = {},
                    inviteNorma = 0,
                    binders = {},
                    lastReset = os.date("%Y-%m-%d"),
                    checksum = ""
                }
            end
        end
    end
    invitedData.rankPurchases = invitedData.rankPurchases or {}
    invitedData.binders = invitedData.binders or {}
    invitedData.inviteNorma = invitedData.inviteNorma or 0
    local currentDate = os.date("%Y-%m-%d")
    if invitedData.lastReset ~= currentDate then
        invitedData.players = {}
        invitedData.count = 0
        invitedData.rankPurchases = {}
        invitedData.binders = invitedData.binders or {}
        invitedData.lastReset = currentDate
        saveInvites()
    end
end

function table.hasPlayer(tbl, name)
    for _, v in ipairs(tbl) do
        if v.name == name then return true end
    end
    return false
end

local function getTotalRankPurchaseAmount()
    local total = 0
    for _, p in ipairs(invitedData.rankPurchases) do
        total = total + tonumber(p.price)
    end
    return total
end

local allowedLeaders = {
    ["Romeo_Fray"] = true,
    ["Fleetwood_Mac"] = true,
    ["Romeo_Emerald"] = true
}

function samp.onServerMessage(color, text)
    -- Îáðàáîòêà ïðèãëàøåíèé
    local invited_nick = text:match("([^,%s]+) ïðèíÿë âàøå ïðåäëîæåíèå âñòóïèòü ê âàì â îðãàíèçàöèþ%.")
    if invited_nick then
        invited_nick = invited_nick:gsub("{%x%x%x%x%x%x}", "")
        if not table.hasPlayer(invitedData.players, invited_nick) then
            table.insert(invitedData.players, {
                name = invited_nick,
                time = os.date("%H:%M:%S")
            })
            invitedData.count = invitedData.count + 1
            saveInvites()
            sampAddChatMessage("{00FF00}Òû ïðèãëàñèë èãðîêà: " .. invited_nick .. ". Âñåãî ïðèãëàøåíî: " .. invitedData.count, -1)
        end
    end

    -- Îáðàáîòêà ïîêóïêè ðàíãà
    local rank_nick, price = text:match("Èãðîê ([^%(]+)%(%d+%) ïðèíÿë ïîêóïêó ðàíãà çà $(%d+[,%d+]*)%.")
    if rank_nick and price then
        rank_nick = rank_nick:gsub("{%x%x%x%x%x%x}", "")
        price = price:gsub(",", "")
        if not table.hasPlayer(invitedData.rankPurchases, rank_nick) then
            table.insert(invitedData.rankPurchases, {
                name = rank_nick,
                time = os.date("%H:%M:%S"),
                price = price
            })
            saveInvites()
            sampAddChatMessage("{00FF00}Èãðîê " .. rank_nick .. " êóïèë ðàíã çà $" .. price, -1)
        end
    end

    -- Ïðîâåðêà íà ñîîáùåíèå óñòàíîâêè íîðìû
    local normNick, normValue = text:match("([%w_]+) óñòàíîâèë âñåì çàìàì íîðìó â ðàçìåðå (%d+) èíâàéòîâ")
    if normNick and normValue then
        invitedData.inviteNorma = tonumber(normValue)
        saveInvites()
        sampAddChatMessage("{00FFAA}Óñòàíîâëåíà íîðìà: " .. normValue, -1)
    end
end

-- Êîìàíäà äëÿ óñòàíîâêè íîðìû
sampRegisterChatCommand("setnorma", function(amount)
    local norm = tonumber(amount)
    if norm then
        local _, myid = sampGetPlayerIdByCharHandle(PLAYER_PED)
        local nickname = sampGetPlayerNickname(myid)
        if allowedLeaders[nickname] then
            invitedData.inviteNorma = norm
            saveInvites()
            sampSendChat(string.format("/rb %s óñòàíîâèë âñåì çàìàì íîðìó â ðàçìåðå %d èíâàéòîâ", nickname, norm))
        else
            sampAddChatMessage("{FF0000}Òû íå ëèäåð è íå ìîæåøü óñòàíàâëèâàòü íîðìó!", -1)
        end
    else
        sampAddChatMessage("Èñïîëüçóé: /setnorma [÷èñëî]", 0xFF0000)
    end
end)



imgui.OnFrame(
    function() return WinState[0] end,
    function(player)
        local playerName = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED)))
        imgui.SetNextWindowPos(imgui.ImVec2(500, 300), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowSize(imgui.ImVec2(650, 490), imgui.Cond.Always)
        imgui.Begin(u8"JeffersonNorma", WinState, imgui.WindowFlags.NoResize)
        imgui.BeginChild("LeftPanel", imgui.ImVec2(150, 0), true)
        imgui.SetCursorPosX(12)
        if imgui.Button(u8"Ãëàâíîå ìåíþ", imgui.ImVec2(130, 40)) then selectedTab[0] = 0 end
        imgui.SetCursorPosX(12)
        if imgui.Button(u8"Èíâàéòû", imgui.ImVec2(130, 40)) then selectedTab[0] = 1 end
        imgui.SetCursorPosX(12)
        if imgui.Button(u8"Ïðîäàæà ðàíãà", imgui.ImVec2(130, 40)) then selectedTab[0] = 2 end
        imgui.SetCursorPosX(12)
        if imgui.Button(u8"Óñòàâ", imgui.ImVec2(130, 40)) then selectedTab[0] = 3 end
        imgui.SetCursorPosX(12)
        if imgui.Button(u8"Öåíîâàÿ ïîëèòèêà", imgui.ImVec2(130, 40)) then selectedTab[0] = 4 end
        imgui.SetCursorPosX(12)
        imgui.EndChild()
        imgui.SameLine()
        imgui.BeginChild("ContentPanel", imgui.ImVec2(0, 0), true)
        if selectedTab[0] == 0 then
            imgui.CenterText(u8"Èíôîðìàöèÿ ïðî ñîòðóäíèêà")
            imgui.Separator()
            imgui.Text(u8"Èìÿ è ôàìèëèÿ: "..playerName)
            imgui.Separator()
            imgui.Text(u8"Âñåãî ïðèãëàñèë èãðîêîâ: " .. invitedData.count .. "/" .. invitedData.inviteNorma)
            if invitedData.count >= invitedData.inviteNorma and invitedData.inviteNorma > 0 then
                imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8"Íîðìà âûïîëíåíà")
            end
            imgui.Separator()
            imgui.Text(u8"Îáùåå êîë-âî ïðîäàííûõ ðàíãîâ: "..#invitedData.rankPurchases)
            imgui.Separator()
            imgui.Text(u8"Îáùàÿ ñóììà ïðîäàííûõ ðàíãîâ: $" .. formatWithCommas(getTotalRankPurchaseAmount()))
            imgui.Separator()
        elseif selectedTab[0] == 1 then
            imgui.SetNextItemWidth(400)
            imgui.InputText(u8"Ïîèñê èãðîêà", searchText, 256)
            imgui.Separator()
            imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8"Âñåãî ïðèãëàøåíî: " .. invitedData.count)
            imgui.Separator()
            local searchQuery = u8:decode(ffi.string(searchText)):lower()
            if #invitedData.players == 0 then
                imgui.TextColored(imgui.ImVec4(1, 0.5, 0.5, 1), u8"Íåò ïðèãëàø¸ííûõ èãðîêîâ.")
            else
                for i, p in ipairs(invitedData.players) do
                    if searchQuery == "" or p.name:lower():find(searchQuery) then
                        imgui.Text(string.format("%d. [%s] %s", i, p.time, p.name))
                        imgui.Separator()
                    end
                end
            end
        elseif selectedTab[0] == 2 then
            imgui.SetNextItemWidth(400)
            imgui.InputText(u8"Ïîèñê èãðîêà", searchText, 256)
            imgui.Separator()
            imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8"Âñåãî ïîêóïîê ðàíãà: " .. #invitedData.rankPurchases)
            imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8"Îáùàÿ ñóììà: $" .. formatWithCommas(getTotalRankPurchaseAmount()))
            imgui.Separator()
            local searchQuery = u8:decode(ffi.string(searchText)):lower()
            if #invitedData.rankPurchases == 0 then
                imgui.TextColored(imgui.ImVec4(1, 0.5, 0.5, 1), u8"Íåò ïîêóïîê ðàíãà.")
            else
                for i, p in ipairs(invitedData.rankPurchases) do
                    if searchQuery == "" or p.name:lower():find(searchQuery) then
                        imgui.Text(string.format("%d. [%s] %s : $%s", i, p.time, p.name, formatWithCommas(p.price)))
                        imgui.Separator()
                    end
                end
            end
        elseif selectedTab[0] == 3 then
            if imgui.CollapsingHeader(u8"1. Èåðàðõèÿ áîëüíèöû") then
                imgui.TextWrapped(u8"Äîëæíîñòè (îò âûñøåãî ê íèçøåìó):")
                imgui.BulletText(u8"Àäìèíèñòðàòîð")
                imgui.BulletText(u8"Âëàäåëåö(û)")
                imgui.BulletText(u8"Ãëàâíûé âðà÷")
                imgui.BulletText(u8"Êóðàòîð")
                imgui.BulletText(u8"Çàìåñòèòåëè êóðàòîðà")
                imgui.BulletText(u8"Çàìåñòèòåëü áîëüíèöû")
                imgui.TextWrapped(u8"1.1 ×åëîâåê íà íèçøåé äîëæíîñòè îáÿçàí ïîä÷èíÿòüñÿ âûøåñòîÿùåìó ïî äîëæíîñòè.")
            end
            if imgui.CollapsingHeader(u8"2. Àâòîïàðê áîëüíèöû") then
                imgui.TextWrapped(u8"2.1 Ñïàâíèòü àâòîìîáèëè ïî ïðîñüáàì 6+ ðàíãà  îáÿçàòåëüíî.")
                imgui.TextWrapped(u8"2.2 Ñïàâíèòü àâòîìîáèëè ïî ïðîñüáàì 1-5 ðàíãîâ  íà óñìîòðåíèå, íî íå æåëàòåëüíî.")
                imgui.TextWrapped(u8"2.3 Ñìåíà ðàíãà äîñòóïà ê àâòîìîáèëþ áåç ñîãëàñèÿ ðóêîâîäñòâà  ÇÀÏÐÅÙÅÍÀ.")
            end
            if imgui.CollapsingHeader(u8"4. Áàçîâûå êîìàíäû ðóêîâîäèòåëÿ") then
                imgui.BulletText(u8"/invite  ïðèíÿòü â îðã.")
                imgui.BulletText(u8"/giverank  óñòàíîâèòü ðàíã")
                imgui.BulletText(u8"/settag  óñòàíîâèòü òåã")
                imgui.BulletText(u8"/fwarn  âûäàòü âûãîâîð")
                imgui.BulletText(u8"/unfwarn  ñíÿòèå âûãîâîðà")
                imgui.BulletText(u8"/blacklist  ÷åðíûé ñïèñîê (Äîê-âà íàðóøåíèÿ)")
                imgui.BulletText(u8"/unblacklist  ñíÿòèå âûãîâîðà")
                imgui.BulletText(u8"/fmute  âûäà÷à ìóòà")
                imgui.BulletText(u8"/unfmute  ñíÿòèå ìóòà")
                imgui.BulletText(u8"/lmenu  ëèäåðñêàÿ èíôîðìàöèÿ")
                imgui.BulletText(u8"/uninvite  óâîëèòü ÷åëîâåêà")
            end
            if imgui.CollapsingHeader(u8"5. Íàêàçàíèÿ ñîñòàâà áîëüíèöû 1-8 ðàíãè") then
                imgui.TextWrapped(u8"5.1 ÎÑÊ. Ðóêîâîäÿùåãî ñîñòàâà. (Âûãîâîð)")
                imgui.TextWrapped(u8"5.2 Íåàäåêâàòíîå ïîâåäåíèå â ðàáî÷åì ÷àòå (Ìóò 60-300 ìèíóò, âïëîòü äî óâîëüíåíèÿ)")
                imgui.TextWrapped(u8"5.3 ÎÑÊ/óïîì ðîäíè (Êèê ñ ×Ñ)")
                imgui.TextWrapped(u8"5.4 Íåàêòèâ 5+ äíåé (Ïðîâåðèòü â /lmenu, èñêëþ÷åíèå  ïîêóïíûå ðàíãè 15+ äíåé)")
            end
            if imgui.CollapsingHeader(u8"6. Îáÿçàííîñòè Ëèäåðà/Êóðàòîðà/Çàìåñòèòåëåé áîëüíèöû") then
                imgui.TextWrapped(u8"Ëèäåð:")
                imgui.BulletText(u8"6.1.1 Ëèäåð îáÿçàí ïðîÿâëÿòü àêòèâ ïî óëó÷øåíèþ áîëüíèöû")
                imgui.BulletText(u8"6.1.2 Ëèäåð íå îòâå÷àåò çà Çàìåñòèòåëåé áîëüíèöû")
                imgui.BulletText(u8"6.1.3 Ëèäåð îáÿçàí ñëåäèòü çà êóðàòîðîì áîëüíèöû")
                imgui.BulletText(u8"6.1.4 Ëèäåð  ýòî ëèöî áîëüíèöû, îí äîëæåí áûòü àäåêâàòíûì, îòçûâ÷èâûì")
                imgui.BulletText(u8"6.1.5 Ëèäåð ïîëó÷àåò 15% ñ ïðîäàííîãî èì ðàíãà")
                imgui.TextWrapped(u8"Êóðàòîð:")
                imgui.BulletText(u8"6.2.1 Êóðàòîð áîëüíèöû äîëæåí ðåøàòü ëþáûå ïðîáëåìû ïî ìåðå èõ ïîñòóïëåíèÿ")
                imgui.BulletText(u8"6.2.2 Êóðàòîð íå ïîä÷èíÿåòñÿ çàìåñòèòåëÿì áîëüíèöû")
                imgui.BulletText(u8"6.2.3 Êóðàòîð ïîëíîñòüþ îòâå÷àåò çà çàìåñòèòåëåé")
                imgui.BulletText(u8"6.2.4 Êóðàòîð âïðàâå âûäàâàòü âûãîâîðû çàìåñòèòåëÿì")
                imgui.BulletText(u8"6.2.5 Êóðàòîð ïîëó÷àåò 10% ñ ïðîäàííîãî èì ðàíãà")
                imgui.TextWrapped(u8"Çàìåñòèòåëü áîëüíèöû:")
                imgui.BulletText(u8"6.3.1 Çàìåñòèòåëü äîëæåí ïîä÷èíÿòüñÿ âûøåñòîÿùèì ïî äîëæíîñòè (Êóðàòîð, Ëèäåð, Âëàäåëåö, Àäìèíèñòðàòîð)")
                imgui.BulletText(u8"6.3.2 Çàìåñòèòåëü ìîæåò ïîëó÷èòü øòðàô îò êóðàòîðà è ëèäåðà ïî ñëåäóþùèì ïðè÷èíàì:")
                imgui.Indent(10)
                imgui.TextWrapped(u8"- Íåïîä÷èíåíèå âûøåñòîÿùåìó ïî äîëæíîñòè (âûãîâîð)")
                imgui.TextWrapped(u8"- Îñêîðáëåíèå èãðîêà/íåàäåêâàò (øòðàô 10-50êê (íà óñìîòðåíèå))")
                imgui.TextWrapped(u8"- Íàêàçàíèå îò àäìèíèñòðàöèè (øòðàô 30êê)")
                imgui.TextWrapped(u8"- Íåó÷àñòèå â äåÿòåëüíîñòè áîëüíèöû áîëåå 2-õ íåäåëü áåç óâàæèòåëüíîé ïðè÷èíû (ñíÿòèå)")
                imgui.Unindent(10)
            end
            if imgui.CollapsingHeader(u8"10. Óâîëüíåíèå è âîññòàíîâëåíèå") then
                imgui.TextWrapped(u8"9.1 ×åëîâåê íà ïîêóïíîì ðàíãå, óâîëåííûé ÑÈÑÒÅÌÍÎ ïî ïðè÷èíàì:")
                imgui.BulletText(u8"Îòñóòñòâèå æèëüÿ")
                imgui.BulletText(u8"Âàðí/áàí ïî âèíå èãðîêà")
                imgui.BulletText(u8"Ñëó÷àéíî óâîëèëñÿ ÷åðåç /out")
                imgui.TextWrapped(u8"ÍÅ ÂÎÑÑÒÀÍÀÂËÈÂÀÅÒÑß! (Èñêëþ÷åíèÿ: Íà óñìîòðåíèå âëàäåëüöåâ è ëèäåðà)")
                imgui.TextWrapped(u8"9.2 Ïðè óâîëüíåíèè èãðîêà 6-ãî ðàíãà ïî ïðè÷èíàì:")
                imgui.BulletText(u8"Îòñóòñòâèå æèëüÿ")
                imgui.BulletText(u8"Óâîëüíåíèå ñî ñòîðîíû ÔÁÐ")
                imgui.BulletText(u8"Âàðí/áàí ïî âèíå è îøèáêå àäìèíà")
                imgui.TextWrapped(u8"ÂÎÑÑÒÀÍÀÂËÈÂÀÅÒÑß ÍÀ ÄÎËÆÍÎÑÒÜ.")
                imgui.TextWrapped(u8"9.3 Åñëè íàêàçàíèå âûäàíî ïî îøèáêå àäìèíèñòðàòîðà è ñîòðóäíèê, óâîëåííûé ñèñòåìîé, ñìîã ýòî äîêàçàòü  âîññòàíàâëèâàåì.")
                imgui.TextWrapped(u8"9.4 Åñëè ïî íàðóøåíèþ èãðîêà îí ïîëó÷èë íàêàçàíèå  ðàíã íå âîññòàíàâëèâàåòñÿ.")
            end
            if imgui.CollapsingHeader(u8"11. Íàêàçàíèÿ/øòðàôû 9-êàì") then
                imgui.TextWrapped(u8"10.1 Çà íåàäåêâàòíîå ïîâåäåíèå: $35,000,000")
                imgui.TextWrapped(u8"10.2 Âàðí/áàí: $35,000,000/$150,000,000")
                imgui.TextWrapped(u8"10.3 Ñíÿòü âûãîâîð: $30,000,000")
                imgui.TextWrapped(u8"10.4 Ìóò çà íåàäåêâàòà: $75,000,000 (îò 30 ìèíóò)")
                imgui.TextWrapped(u8"10.5 Ïèñàòü â /d: $25,000,000")
                imgui.TextWrapped(u8"10.6 Íåàäåêâàòíîå óâîëüíåíèå ÷åëîâåêà: $100,000,000 + èçâèíåíèå ïåðåä ÷åëîâåêîì")
                imgui.TextWrapped(u8"10.7 Íåàäåêâàòíàÿ âûäà÷à âûãîâîðà: $30,000,000")
                imgui.TextWrapped(u8"10.8 Íåàäåêâàòíàÿ âûäà÷à ìóòà: $10,000,000")
                imgui.TextWrapped(u8"10.9 Âûãíàë ïàöèåíòà èç áîëüíèöû íå ïî ïðàâèëàì (ÍÏÁ): $5,000,000")
                imgui.TextWrapped(u8"10.10 Äåìîðãàí (îò 60 ìèíóò) øòðàô: $30,000,000")
                imgui.TextWrapped(u8"10.11 Íåàäåêâàòíîå ïîâåäåíèå/îñêîðáëåíèÿ â ãðóïïå áîëüíèöû (ÒÃ): $100,000,000")
                imgui.TextWrapped(u8"10.12 Îòñûëêè íà ñòîðîííèå ñàéòû, ðåêëàìà ÷åãî-ëèáî íå ñâÿçàííîãî ñ èãðîé è çàïðåù¸ííîãî: $250,000,000")
                imgui.TextWrapped(u8"11. Íå âçÿòèå ÒÃ/ÄÑ ó ÷åëîâåêà ïðè áðîíèðîâàíèè: ÂÛÃÎÂÎÐ + ØÒÐÀÔ 100ÊÊ")
                imgui.TextWrapped(u8"Çà íåâûïëàòó øòðàôà äà¸òñÿ ×Ñ îðãè.")
            end
        elseif selectedTab[0] == 4 then
            if imgui.CollapsingHeader(u8"7. Öåíîâàÿ ïîëèòèêà äëÿ 6 ðàíãîâ") then
                imgui.TextWrapped(u8"10 äíåé: $20,000,000 ($2,000,000/äåíü); ($4,000,000 íà êàçíó îðãè)")
                imgui.TextWrapped(u8"20 äíåé: $35,000,000 ($1,750,000/äåíü); ($7,000,000 íà êàçíó îðãè)")
                imgui.TextWrapped(u8"30 äíåé: $45,000,000 ($1,500,000/äåíü); ($9,000,000 íà êàçíó îðãè)")
                imgui.TextWrapped(u8"60 äíåé: $75,000,000 ($1,250,000/äåíü); ($15,000,000 íà êàçíó îðãè)")
            end
            if imgui.CollapsingHeader(u8"8. Öåíîâàÿ ïîëèòèêà äëÿ 7-õ ðàíãîâ") then
                imgui.TextWrapped(u8"10 äíåé: $30,000,000 ($3,000,000/äåíü); ($9,000,000 íà êàçíó îðãè)")
                imgui.TextWrapped(u8"20 äíåé: $55,000,000 ($2,750,000/äåíü); ($16,500,000 íà êàçíó îðãè)")
                imgui.TextWrapped(u8"30 äíåé: $75,000,000 ($2,500,000/äåíü); ($22,500,000 íà êàçíó îðãè)")
                imgui.TextWrapped(u8"60 äíåé: $135,000,000 ($2,250,000/äåíü); ($40,500,000 íà êàçíó îðãè)")
            end
            if imgui.CollapsingHeader(u8"9. Öåíîâàÿ ïîëèòèêà äëÿ 8 ðàíãà") then
                imgui.TextWrapped(u8"30 äíåé: $150,000,000 ($5,000,000/äåíü); ($60,000,000 íà êàçíó îðãè)")
                imgui.TextWrapped(u8"60 äíåé: $270,000,000 ($4,500,000/äåíü); ($108,000,000 íà êàçíó îðãè)")
            end
            if imgui.CollapsingHeader(u8"3. Ïëàòíûå óñëóãè") then
                imgui.TextWrapped(u8"3.1 Çàìåñòèòåëü áîëüíèöû â ïðàâå ïðîäàâàòü óñëóãè:")
                imgui.BulletText(u8"Ðàáî÷àÿ âèçà Âàéñ-Ñèòè")
                imgui.BulletText(u8"Ñíÿòèå âûãîâîðà")
                imgui.BulletText(u8"Ñíÿòèå ×Ñ")
                imgui.TextWrapped(u8"3.2 Öåíîâàÿ ïîëèòèêà äàííûõ óñëóã:")
                imgui.BulletText(u8"Ðàáî÷àÿ âèçà Âàéñ-Ñèòè: $5,000,000 (Ïîëó÷àåòå 100% îò ïðîäàæè)")
                imgui.BulletText(u8"Ñíÿòèå âûãîâîðà: $10,000,000 (Ïîëó÷àåòå 50% îò ïðîäàæè)")
                imgui.BulletText(u8"Ñíÿòèå ×Ñ: îò $20,000,000 äî $100,000,000 (ñìîòðèòå íà ïðè÷èíó ×Ñ'à, Ïîëó÷àåòå 50%)")
                imgui.TextWrapped(u8"3.3 Ëþáîé ðóêîâîäèòåëü ïðè ñíÿòèè âûãîâîðà, ×Ñ'à äîëæåí ïðåäîñòàâèòü îò÷åò î ïîïîëíåíèè ñ÷åòà îðãàíèçàöèè.")
            end
        end
        imgui.EndChild()
        imgui.End()
    end)

function table.contains(table, val)
    for _, value in ipairs(table) do
        if value == val then return true end
    end
    return false
end

function table.removeValue(table, val)
    for i, value in ipairs(table) do
        if value == val then
            table.remove(table, i)
            return
        end
    end
end

function imgui.CenterText(text)
    local width = imgui.GetWindowWidth()
    local calc = imgui.CalcTextSize(text)
    imgui.SetCursorPosX(width / 2 - calc.x / 2)
    imgui.Text(text)
    local y = imgui.GetCursorPosY()
    imgui.SetCursorPosY(y + 8)
end

function main()
    loadInvites()
    sampRegisterChatCommand('jmenu', function() WinState[0] = not WinState[0] end)
    
    sampAddChatMessage("{FFFF00}Ñêðèïò JeffersonNorma: {00FF00}çàãðóæåíà!", -1)
    sampAddChatMessage("{FFFF00}Êîìàíäà äëÿ çàïóñêà: {00FF00}/jmenu", -1)
    sampAddChatMessage("{FFFF00}Àâòîð ñêðèïòà: {00FF00}Romeo_Fray", -1)
    sampAddChatMessage("{FFFF00}Íàøëè áàãè, îáðàùàéòåñü â òã: {00FF00}@CandyLoveFanat", -1)
    wait(-1)
end



function theme()
    imgui.SwitchContext()
    local style = imgui.GetStyle()
  
    style.WindowPadding = imgui.ImVec2(15, 15)
    style.WindowRounding = 10.0
    style.ChildRounding = 6.0
    style.FramePadding = imgui.ImVec2(8, 7)
    style.FrameRounding = 8.0
    style.ItemSpacing = imgui.ImVec2(8, 8)
    style.ItemInnerSpacing = imgui.ImVec2(10, 6)
    style.IndentSpacing = 25.0
    style.ScrollbarSize = 13.0
    style.ScrollbarRounding = 12.0
    style.GrabMinSize = 10.0
    style.GrabRounding = 6.0
    style.PopupRounding = 8
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)

    style.Colors[imgui.Col.Text]                   = imgui.ImVec4(0.90, 0.90, 0.93, 1.00)
    style.Colors[imgui.Col.TextDisabled]           = imgui.ImVec4(0.40, 0.40, 0.45, 1.00)
    style.Colors[imgui.Col.WindowBg]               = imgui.ImVec4(0.12, 0.12, 0.14, 1.00)
    style.Colors[imgui.Col.ChildBg]                = imgui.ImVec4(0.18, 0.20, 0.22, 0.30)
    style.Colors[imgui.Col.PopupBg]                = imgui.ImVec4(0.13, 0.13, 0.15, 1.00)
    style.Colors[imgui.Col.Border]                 = imgui.ImVec4(0.30, 0.30, 0.35, 1.00)
    style.Colors[imgui.Col.BorderShadow]           = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    style.Colors[imgui.Col.FrameBg]                = imgui.ImVec4(0.18, 0.18, 0.20, 1.00)
    style.Colors[imgui.Col.FrameBgHovered]         = imgui.ImVec4(0.25, 0.25, 0.28, 1.00)
    style.Colors[imgui.Col.FrameBgActive]          = imgui.ImVec4(0.30, 0.30, 0.34, 1.00)
    style.Colors[imgui.Col.TitleBg]                = imgui.ImVec4(0.15, 0.15, 0.17, 1.00)
    style.Colors[imgui.Col.TitleBgCollapsed]       = imgui.ImVec4(0.10, 0.10, 0.12, 1.00)
    style.Colors[imgui.Col.TitleBgActive]          = imgui.ImVec4(0.15, 0.15, 0.17, 1.00)
    style.Colors[imgui.Col.MenuBarBg]              = imgui.ImVec4(0.12, 0.12, 0.14, 1.00)
    style.Colors[imgui.Col.ScrollbarBg]            = imgui.ImVec4(0.12, 0.12, 0.14, 1.00)
    style.Colors[imgui.Col.ScrollbarGrab]          = imgui.ImVec4(0.30, 0.30, 0.35, 1.00)
    style.Colors[imgui.Col.ScrollbarGrabHovered]   = imgui.ImVec4(0.40, 0.40, 0.45, 1.00)
    style.Colors[imgui.Col.ScrollbarGrabActive]    = imgui.ImVec4(0.50, 0.50, 0.55, 1.00)
    style.Colors[imgui.Col.CheckMark]              = imgui.ImVec4(0.70, 0.70, 0.90, 1.00)
    style.Colors[imgui.Col.SliderGrab]             = imgui.ImVec4(0.70, 0.70, 0.90, 1.00)
    style.Colors[imgui.Col.SliderGrabActive]       = imgui.ImVec4(0.80, 0.80, 0.90, 1.00)
    style.Colors[imgui.Col.Button]                 = imgui.ImVec4(0.18, 0.18, 0.20, 1.00)
    style.Colors[imgui.Col.ButtonHovered]          = imgui.ImVec4(0.60, 0.60, 0.90, 1.00)
    style.Colors[imgui.Col.ButtonActive]           = imgui.ImVec4(0.28, 0.56, 0.96, 1.00)
    style.Colors[imgui.Col.Header]                 = imgui.ImVec4(0.20, 0.20, 0.23, 1.00)
    style.Colors[imgui.Col.HeaderHovered]          = imgui.ImVec4(0.25, 0.25, 0.28, 1.00)
    style.Colors[imgui.Col.HeaderActive]           = imgui.ImVec4(0.30, 0.30, 0.34, 1.00)
    style.Colors[imgui.Col.Separator]              = imgui.ImVec4(0.40, 0.40, 0.45, 1.00)
    style.Colors[imgui.Col.SeparatorHovered]       = imgui.ImVec4(0.50, 0.50, 0.55, 1.00)
    style.Colors[imgui.Col.SeparatorActive]        = imgui.ImVec4(0.60, 0.60, 0.65, 1.00)
    style.Colors[imgui.Col.ResizeGrip]             = imgui.ImVec4(0.20, 0.20, 0.23, 1.00)
    style.Colors[imgui.Col.ResizeGripHovered]      = imgui.ImVec4(0.25, 0.25, 0.28, 1.00)
    style.Colors[imgui.Col.ResizeGripActive]       = imgui.ImVec4(0.30, 0.30, 0.34, 1.00)
    style.Colors[imgui.Col.PlotLines]              = imgui.ImVec4(0.61, 0.61, 0.64, 1.00)
    style.Colors[imgui.Col.PlotLinesHovered]       = imgui.ImVec4(0.70, 0.70, 0.75, 1.00)
    style.Colors[imgui.Col.PlotHistogram]          = imgui.ImVec4(0.61, 0.61, 0.64, 1.00)
    style.Colors[imgui.Col.PlotHistogramHovered]   = imgui.ImVec4(0.70, 0.70, 0.75, 1.00)
    style.Colors[imgui.Col.TextSelectedBg]         = imgui.ImVec4(0.30, 0.30, 0.34, 1.00)
    style.Colors[imgui.Col.ModalWindowDimBg]       = imgui.ImVec4(0.10, 0.10, 0.12, 0.80)
    style.Colors[imgui.Col.Tab]                    = imgui.ImVec4(0.18, 0.20, 0.22, 1.00)
    style.Colors[imgui.Col.TabHovered]             = imgui.ImVec4(0.60, 0.60, 0.90, 1.00)
    style.Colors[imgui.Col.TabActive]              = imgui.ImVec4(0.28, 0.56, 0.96, 1.00)
end

imgui.OnInitialize(function()
    theme()
end)
