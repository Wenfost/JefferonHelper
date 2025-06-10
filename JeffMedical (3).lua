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

-- ������� ��� ������� ��������
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
                sampAddChatMessage("{FF0000}���������� ��������� JSON-�����! ������ ��������.", -1)
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
    -- ��������� �����������
    local invited_nick = text:match("([^,%s]+) ������ ���� ����������� �������� � ��� � �����������%.")
    if invited_nick then
        invited_nick = invited_nick:gsub("{%x%x%x%x%x%x}", "")
        if not table.hasPlayer(invitedData.players, invited_nick) then
            table.insert(invitedData.players, {
                name = invited_nick,
                time = os.date("%H:%M:%S")
            })
            invitedData.count = invitedData.count + 1
            saveInvites()
            sampAddChatMessage("{00FF00}�� ��������� ������: " .. invited_nick .. ". ����� ����������: " .. invitedData.count, -1)
        end
    end

    -- ��������� ������� �����
    local rank_nick, price = text:match("����� ([^%(]+)%(%d+%) ������ ������� ����� �� $(%d+[,%d+]*)%.")
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
            sampAddChatMessage("{00FF00}����� " .. rank_nick .. " ����� ���� �� $" .. price, -1)
        end
    end

    -- �������� �� ��������� ��������� �����
    local normNick, normValue = text:match("([%w_]+) ��������� ���� ����� ����� � ������� (%d+) ��������")
    if normNick and normValue then
        invitedData.inviteNorma = tonumber(normValue)
        saveInvites()
        sampAddChatMessage("{00FFAA}����������� �����: " .. normValue, -1)
    end
end

-- ������� ��� ��������� �����
sampRegisterChatCommand("setnorma", function(amount)
    local norm = tonumber(amount)
    if norm then
        local _, myid = sampGetPlayerIdByCharHandle(PLAYER_PED)
        local nickname = sampGetPlayerNickname(myid)
        if allowedLeaders[nickname] then
            invitedData.inviteNorma = norm
            saveInvites()
            sampSendChat(string.format("/rb %s ��������� ���� ����� ����� � ������� %d ��������", nickname, norm))
        else
            sampAddChatMessage("{FF0000}�� �� ����� � �� ������ ������������� �����!", -1)
        end
    else
        sampAddChatMessage("���������: /setnorma [�����]", 0xFF0000)
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
        if imgui.Button(u8"������� ����", imgui.ImVec2(130, 40)) then selectedTab[0] = 0 end
        imgui.SetCursorPosX(12)
        if imgui.Button(u8"�������", imgui.ImVec2(130, 40)) then selectedTab[0] = 1 end
        imgui.SetCursorPosX(12)
        if imgui.Button(u8"������� �����", imgui.ImVec2(130, 40)) then selectedTab[0] = 2 end
        imgui.SetCursorPosX(12)
        if imgui.Button(u8"�����", imgui.ImVec2(130, 40)) then selectedTab[0] = 3 end
        imgui.SetCursorPosX(12)
        if imgui.Button(u8"������� ��������", imgui.ImVec2(130, 40)) then selectedTab[0] = 4 end
        imgui.SetCursorPosX(12)
        imgui.EndChild()
        imgui.SameLine()
        imgui.BeginChild("ContentPanel", imgui.ImVec2(0, 0), true)
        if selectedTab[0] == 0 then
            imgui.CenterText(u8"���������� ��� ����������")
            imgui.Separator()
            imgui.Text(u8"��� � �������: "..playerName)
            imgui.Separator()
            imgui.Text(u8"����� ��������� �������: " .. invitedData.count .. "/" .. invitedData.inviteNorma)
            if invitedData.count >= invitedData.inviteNorma and invitedData.inviteNorma > 0 then
                imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8"����� ���������")
            end
            imgui.Separator()
            imgui.Text(u8"����� ���-�� ��������� ������: "..#invitedData.rankPurchases)
            imgui.Separator()
            imgui.Text(u8"����� ����� ��������� ������: $" .. formatWithCommas(getTotalRankPurchaseAmount()))
            imgui.Separator()
        elseif selectedTab[0] == 1 then
            imgui.SetNextItemWidth(400)
            imgui.InputText(u8"����� ������", searchText, 256)
            imgui.Separator()
            imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8"����� ����������: " .. invitedData.count)
            imgui.Separator()
            local searchQuery = u8:decode(ffi.string(searchText)):lower()
            if #invitedData.players == 0 then
                imgui.TextColored(imgui.ImVec4(1, 0.5, 0.5, 1), u8"��� ������������ �������.")
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
            imgui.InputText(u8"����� ������", searchText, 256)
            imgui.Separator()
            imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8"����� ������� �����: " .. #invitedData.rankPurchases)
            imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8"����� �����: $" .. formatWithCommas(getTotalRankPurchaseAmount()))
            imgui.Separator()
            local searchQuery = u8:decode(ffi.string(searchText)):lower()
            if #invitedData.rankPurchases == 0 then
                imgui.TextColored(imgui.ImVec4(1, 0.5, 0.5, 1), u8"��� ������� �����.")
            else
                for i, p in ipairs(invitedData.rankPurchases) do
                    if searchQuery == "" or p.name:lower():find(searchQuery) then
                        imgui.Text(string.format("%d. [%s] %s : $%s", i, p.time, p.name, formatWithCommas(p.price)))
                        imgui.Separator()
                    end
                end
            end
        elseif selectedTab[0] == 3 then
            if imgui.CollapsingHeader(u8"1. �������� ��������") then
                imgui.TextWrapped(u8"��������� (�� ������� � �������):")
                imgui.BulletText(u8"�������������")
                imgui.BulletText(u8"��������(�)")
                imgui.BulletText(u8"������� ����")
                imgui.BulletText(u8"�������")
                imgui.BulletText(u8"����������� ��������")
                imgui.BulletText(u8"����������� ��������")
                imgui.TextWrapped(u8"1.1 ������� �� ������ ��������� ������ ����������� ������������ �� ���������.")
            end
            if imgui.CollapsingHeader(u8"2. �������� ��������") then
                imgui.TextWrapped(u8"2.1 �������� ���������� �� �������� 6+ ����� � �����������.")
                imgui.TextWrapped(u8"2.2 �������� ���������� �� �������� 1-5 ������ � �� ����������, �� �� ����������.")
                imgui.TextWrapped(u8"2.3 ����� ����� ������� � ���������� ��� �������� ����������� � ���������.")
            end
            if imgui.CollapsingHeader(u8"4. ������� ������� ������������") then
                imgui.BulletText(u8"/invite � ������� � ���.")
                imgui.BulletText(u8"/giverank � ���������� ����")
                imgui.BulletText(u8"/settag � ���������� ���")
                imgui.BulletText(u8"/fwarn � ������ �������")
                imgui.BulletText(u8"/unfwarn � ������ ��������")
                imgui.BulletText(u8"/blacklist � ������ ������ (���-�� ���������)")
                imgui.BulletText(u8"/unblacklist � ������ ��������")
                imgui.BulletText(u8"/fmute � ������ ����")
                imgui.BulletText(u8"/unfmute � ������ ����")
                imgui.BulletText(u8"/lmenu � ��������� ����������")
                imgui.BulletText(u8"/uninvite � ������� ��������")
            end
            if imgui.CollapsingHeader(u8"5. ��������� ������� �������� 1-8 �����") then
                imgui.TextWrapped(u8"5.1 ���. ������������ �������. (�������)")
                imgui.TextWrapped(u8"5.2 ������������ ��������� � ������� ���� (��� 60-300 �����, ������ �� ����������)")
                imgui.TextWrapped(u8"5.3 ���/���� ����� (��� � ��)")
                imgui.TextWrapped(u8"5.4 ������� 5+ ���� (��������� � /lmenu, ���������� � �������� ����� 15+ ����)")
            end
            if imgui.CollapsingHeader(u8"6. ����������� ������/��������/������������ ��������") then
                imgui.TextWrapped(u8"�����:")
                imgui.BulletText(u8"6.1.1 ����� ������ ��������� ����� �� ��������� ��������")
                imgui.BulletText(u8"6.1.2 ����� �� �������� �� ������������ ��������")
                imgui.BulletText(u8"6.1.3 ����� ������ ������� �� ��������� ��������")
                imgui.BulletText(u8"6.1.4 ����� � ��� ���� ��������, �� ������ ���� ����������, ����������")
                imgui.BulletText(u8"6.1.5 ����� �������� 15% � ���������� �� �����")
                imgui.TextWrapped(u8"�������:")
                imgui.BulletText(u8"6.2.1 ������� �������� ������ ������ ����� �������� �� ���� �� �����������")
                imgui.BulletText(u8"6.2.2 ������� �� ����������� ������������ ��������")
                imgui.BulletText(u8"6.2.3 ������� ��������� �������� �� ������������")
                imgui.BulletText(u8"6.2.4 ������� ������ �������� �������� ������������")
                imgui.BulletText(u8"6.2.5 ������� �������� 10% � ���������� �� �����")
                imgui.TextWrapped(u8"����������� ��������:")
                imgui.BulletText(u8"6.3.1 ����������� ������ ����������� ����������� �� ��������� (�������, �����, ��������, �������������)")
                imgui.BulletText(u8"6.3.2 ����������� ����� �������� ����� �� �������� � ������ �� ��������� ��������:")
                imgui.Indent(10)
                imgui.TextWrapped(u8"- ������������ ������������ �� ��������� (�������)")
                imgui.TextWrapped(u8"- ����������� ������/��������� (����� 10-50�� (�� ����������))")
                imgui.TextWrapped(u8"- ��������� �� ������������� (����� 30��)")
                imgui.TextWrapped(u8"- ��������� � ������������ �������� ����� 2-� ������ ��� ������������ ������� (������)")
                imgui.Unindent(10)
            end
            if imgui.CollapsingHeader(u8"10. ���������� � ��������������") then
                imgui.TextWrapped(u8"9.1 ������� �� �������� �����, ��������� �������� �� ��������:")
                imgui.BulletText(u8"���������� �����")
                imgui.BulletText(u8"����/��� �� ���� ������")
                imgui.BulletText(u8"�������� �������� ����� /out")
                imgui.TextWrapped(u8"�� �����������������! (����������: �� ���������� ���������� � ������)")
                imgui.TextWrapped(u8"9.2 ��� ���������� ������ 6-�� ����� �� ��������:")
                imgui.BulletText(u8"���������� �����")
                imgui.BulletText(u8"���������� �� ������� ���")
                imgui.BulletText(u8"����/��� �� ���� � ������ ������")
                imgui.TextWrapped(u8"����������������� �� ���������.")
                imgui.TextWrapped(u8"9.3 ���� ��������� ������ �� ������ �������������� � ���������, ��������� ��������, ���� ��� �������� � ���������������.")
                imgui.TextWrapped(u8"9.4 ���� �� ��������� ������ �� ������� ��������� � ���� �� �����������������.")
            end
            if imgui.CollapsingHeader(u8"11. ���������/������ 9-���") then
                imgui.TextWrapped(u8"10.1 �� ������������ ���������: $35,000,000")
                imgui.TextWrapped(u8"10.2 ����/���: $35,000,000/$150,000,000")
                imgui.TextWrapped(u8"10.3 ����� �������: $30,000,000")
                imgui.TextWrapped(u8"10.4 ��� �� ����������: $75,000,000 (�� 30 �����)")
                imgui.TextWrapped(u8"10.5 ������ � /d: $25,000,000")
                imgui.TextWrapped(u8"10.6 ������������ ���������� ��������: $100,000,000 + ��������� ����� ���������")
                imgui.TextWrapped(u8"10.7 ������������ ������ ��������: $30,000,000")
                imgui.TextWrapped(u8"10.8 ������������ ������ ����: $10,000,000")
                imgui.TextWrapped(u8"10.9 ������ �������� �� �������� �� �� �������� (���): $5,000,000")
                imgui.TextWrapped(u8"10.10 �������� (�� 60 �����) �����: $30,000,000")
                imgui.TextWrapped(u8"10.11 ������������ ���������/����������� � ������ �������� (��): $100,000,000")
                imgui.TextWrapped(u8"10.12 ������� �� ��������� �����, ������� ����-���� �� ���������� � ����� � ������������: $250,000,000")
                imgui.TextWrapped(u8"11. �� ������ ��/�� � �������� ��� ������������: ������� + ����� 100��")
                imgui.TextWrapped(u8"�� ��������� ������ ����� �� ����.")
            end
        elseif selectedTab[0] == 4 then
            if imgui.CollapsingHeader(u8"7. ������� �������� ��� 6 ������") then
                imgui.TextWrapped(u8"10 ����: $20,000,000 ($2,000,000/����); ($4,000,000 �� ����� ����)")
                imgui.TextWrapped(u8"20 ����: $35,000,000 ($1,750,000/����); ($7,000,000 �� ����� ����)")
                imgui.TextWrapped(u8"30 ����: $45,000,000 ($1,500,000/����); ($9,000,000 �� ����� ����)")
                imgui.TextWrapped(u8"60 ����: $75,000,000 ($1,250,000/����); ($15,000,000 �� ����� ����)")
            end
            if imgui.CollapsingHeader(u8"8. ������� �������� ��� 7-� ������") then
                imgui.TextWrapped(u8"10 ����: $30,000,000 ($3,000,000/����); ($9,000,000 �� ����� ����)")
                imgui.TextWrapped(u8"20 ����: $55,000,000 ($2,750,000/����); ($16,500,000 �� ����� ����)")
                imgui.TextWrapped(u8"30 ����: $75,000,000 ($2,500,000/����); ($22,500,000 �� ����� ����)")
                imgui.TextWrapped(u8"60 ����: $135,000,000 ($2,250,000/����); ($40,500,000 �� ����� ����)")
            end
            if imgui.CollapsingHeader(u8"9. ������� �������� ��� 8 �����") then
                imgui.TextWrapped(u8"30 ����: $150,000,000 ($5,000,000/����); ($60,000,000 �� ����� ����)")
                imgui.TextWrapped(u8"60 ����: $270,000,000 ($4,500,000/����); ($108,000,000 �� ����� ����)")
            end
            if imgui.CollapsingHeader(u8"3. ������� ������") then
                imgui.TextWrapped(u8"3.1 ����������� �������� � ����� ��������� ������:")
                imgui.BulletText(u8"������� ���� ����-����")
                imgui.BulletText(u8"������ ��������")
                imgui.BulletText(u8"������ ��")
                imgui.TextWrapped(u8"3.2 ������� �������� ������ �����:")
                imgui.BulletText(u8"������� ���� ����-����: $5,000,000 (��������� 100% �� �������)")
                imgui.BulletText(u8"������ ��������: $10,000,000 (��������� 50% �� �������)")
                imgui.BulletText(u8"������ ��: �� $20,000,000 �� $100,000,000 (�������� �� ������� ��'�, ��������� 50%)")
                imgui.TextWrapped(u8"3.3 ����� ������������ ��� ������ ��������, ��'� ������ ������������ ����� � ���������� ����� �����������.")
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
    
    sampAddChatMessage("{FFFF00}������ JeffersonNorma: {00FF00}���������!", -1)
    sampAddChatMessage("{FFFF00}������� ��� �������: {00FF00}/jmenu", -1)
    sampAddChatMessage("{FFFF00}����� �������: {00FF00}Romeo_Fray", -1)
    sampAddChatMessage("{FFFF00}����� ����, ����������� � ��: {00FF00}@CandyLoveFanat", -1)
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