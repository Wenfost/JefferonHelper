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

-- Функция для обрезки пробелов
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
                sampAddChatMessage("{FF0000}Обнаружено изменение JSON-файла! Данные сброшены.", -1)
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
    -- Обработка приглашений
    local invited_nick = text:match("([^,%s]+) принял ваше предложение вступить к вам в организацию%.")
    if invited_nick then
        invited_nick = invited_nick:gsub("{%x%x%x%x%x%x}", "")
        if not table.hasPlayer(invitedData.players, invited_nick) then
            table.insert(invitedData.players, {
                name = invited_nick,
                time = os.date("%H:%M:%S")
            })
            invitedData.count = invitedData.count + 1
            saveInvites()
            sampAddChatMessage("{00FF00}Ты пригласил игрока: " .. invited_nick .. ". Всего приглашено: " .. invitedData.count, -1)
        end
    end

    -- Обработка покупки ранга
    local rank_nick, price = text:match("Игрок ([^%(]+)%(%d+%) принял покупку ранга за $(%d+[,%d+]*)%.")
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
            sampAddChatMessage("{00FF00}Игрок " .. rank_nick .. " купил ранг за $" .. price, -1)
        end
    end

    -- Проверка на сообщение установки нормы
    local normNick, normValue = text:match("([%w_]+) установил всем замам норму в размере (%d+) инвайтов")
    if normNick and normValue then
        invitedData.inviteNorma = tonumber(normValue)
        saveInvites()
        sampAddChatMessage("{00FFAA}Установлена норма: " .. normValue, -1)
    end
end

-- Команда для установки нормы
sampRegisterChatCommand("setnorma", function(amount)
    local norm = tonumber(amount)
    if norm then
        local _, myid = sampGetPlayerIdByCharHandle(PLAYER_PED)
        local nickname = sampGetPlayerNickname(myid)
        if allowedLeaders[nickname] then
            invitedData.inviteNorma = norm
            saveInvites()
            sampSendChat(string.format("/rb %s установил всем замам норму в размере %d инвайтов", nickname, norm))
        else
            sampAddChatMessage("{FF0000}Ты не лидер и не можешь устанавливать норму!", -1)
        end
    else
        sampAddChatMessage("Используй: /setnorma [число]", 0xFF0000)
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
        imgui.SetCursorPosX(10)
        if imgui.Button(u8"Главное меню", imgui.ImVec2(150, 40)) then selectedTab[0] = 0 end
        imgui.SetCursorPosX(10)
        if imgui.Button(u8"Инвайты", imgui.ImVec2(140, 40)) then selectedTab[0] = 1 end
        imgui.SetCursorPosX(10)
        if imgui.Button(u8"Продажа ранга", imgui.ImVec2(140, 40)) then selectedTab[0] = 2 end
        imgui.SetCursorPosX(10)
        if imgui.Button(u8"Устав", imgui.ImVec2(140, 40)) then selectedTab[0] = 3 end
        imgui.SetCursorPosX(10)
        if imgui.Button(u8"Ценовая политика", imgui.ImVec2(140, 40)) then selectedTab[0] = 4 end
        imgui.SetCursorPosX(10)
        imgui.EndChild()
        imgui.SameLine()
        imgui.BeginChild("ContentPanel", imgui.ImVec2(0, 0), true)
        if selectedTab[0] == 0 then
            imgui.CenterText(u8"Информация про сотрудника")
            imgui.Separator()
            imgui.Text(u8"Имя и фамилия: "..playerName)
            imgui.Separator()
            imgui.Text(u8"Всего пригласил игроков: " .. invitedData.count .. "/" .. invitedData.inviteNorma)
            if invitedData.count >= invitedData.inviteNorma and invitedData.inviteNorma > 0 then
                imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8"Норма выполнена")
            end
            imgui.Separator()
            imgui.Text(u8"Общее кол-во проданных рангов: "..#invitedData.rankPurchases)
            imgui.Separator()
            imgui.Text(u8"Общая сумма проданных рангов: $" .. formatWithCommas(getTotalRankPurchaseAmount()))
            imgui.Separator()
        elseif selectedTab[0] == 1 then
            imgui.SetNextItemWidth(400)
            imgui.InputText(u8"Поиск игрока", searchText, 256)
            imgui.Separator()
            imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8"Всего приглашено: " .. invitedData.count)
            imgui.Separator()
            local searchQuery = u8:decode(ffi.string(searchText)):lower()
            if #invitedData.players == 0 then
                imgui.TextColored(imgui.ImVec4(1, 0.5, 0.5, 1), u8"Нет приглашённых игроков.")
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
            imgui.InputText(u8"Поиск игрока", searchText, 256)
            imgui.Separator()
            imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8"Всего покупок ранга: " .. #invitedData.rankPurchases)
            imgui.TextColored(imgui.ImVec4(0.2, 1.0, 0.2, 1.0), u8"Общая сумма: $" .. formatWithCommas(getTotalRankPurchaseAmount()))
            imgui.Separator()
            local searchQuery = u8:decode(ffi.string(searchText)):lower()
            if #invitedData.rankPurchases == 0 then
                imgui.TextColored(imgui.ImVec4(1, 0.5, 0.5, 1), u8"Нет покупок ранга.")
            else
                for i, p in ipairs(invitedData.rankPurchases) do
                    if searchQuery == "" or p.name:lower():find(searchQuery) then
                        imgui.Text(string.format("%d. [%s] %s : $%s", i, p.time, p.name, formatWithCommas(p.price)))
                        imgui.Separator()
                    end
                end
            end
        elseif selectedTab[0] == 3 then
            if imgui.CollapsingHeader(u8"1. Иерархия больницы") then
                imgui.TextWrapped(u8"Должности (от высшего к низшему):")
                imgui.BulletText(u8"Администратор")
                imgui.BulletText(u8"Владелец(ы)")
                imgui.BulletText(u8"Главный врач")
                imgui.BulletText(u8"Куратор")
                imgui.BulletText(u8"Заместители куратора")
                imgui.BulletText(u8"Заместитель больницы")
                imgui.TextWrapped(u8"1.1 Человек на низшей должности обязан подчиняться вышестоящему по должности.")
            end
            if imgui.CollapsingHeader(u8"2. Автопарк больницы") then
                imgui.TextWrapped(u8"2.1 Спавнить автомобили по просьбам 6+ ранга — обязательно.")
                imgui.TextWrapped(u8"2.2 Спавнить автомобили по просьбам 1-5 рангов — на усмотрение, но не желательно.")
                imgui.TextWrapped(u8"2.3 Смена ранга доступа к автомобилю без согласия руководства — ЗАПРЕЩЕНА.")
            end
            if imgui.CollapsingHeader(u8"4. Базовые команды руководителя") then
                imgui.BulletText(u8"/invite — принять в орг.")
                imgui.BulletText(u8"/giverank — установить ранг")
                imgui.BulletText(u8"/settag — установить тег")
                imgui.BulletText(u8"/fwarn — выдать выговор")
                imgui.BulletText(u8"/unfwarn — снятие выговора")
                imgui.BulletText(u8"/blacklist — черный список (Док-ва нарушения)")
                imgui.BulletText(u8"/unblacklist — снятие выговора")
                imgui.BulletText(u8"/fmute — выдача мута")
                imgui.BulletText(u8"/unfmute — снятие мута")
                imgui.BulletText(u8"/lmenu — лидерская информация")
                imgui.BulletText(u8"/uninvite — уволить человека")
            end
            if imgui.CollapsingHeader(u8"5. Наказания состава больницы 1-8 ранги") then
                imgui.TextWrapped(u8"5.1 ОСК. Руководящего состава. (Выговор)")
                imgui.TextWrapped(u8"5.2 Неадекватное поведение в рабочем чате (Мут 60-300 минут, вплоть до увольнения)")
                imgui.TextWrapped(u8"5.3 ОСК/упом родни (Кик с ЧС)")
                imgui.TextWrapped(u8"5.4 Неактив 5+ дней (Проверить в /lmenu, исключение — покупные ранги 15+ дней)")
            end
            if imgui.CollapsingHeader(u8"6. Обязанности Лидера/Куратора/Заместителей больницы") then
                imgui.TextWrapped(u8"Лидер:")
                imgui.BulletText(u8"6.1.1 Лидер обязан проявлять актив по улучшению больницы")
                imgui.BulletText(u8"6.1.2 Лидер не отвечает за Заместителей больницы")
                imgui.BulletText(u8"6.1.3 Лидер обязан следить за куратором больницы")
                imgui.BulletText(u8"6.1.4 Лидер — это лицо больницы, он должен быть адекватным, отзывчивым")
                imgui.BulletText(u8"6.1.5 Лидер получает 15% с проданного им ранга")
                imgui.TextWrapped(u8"Куратор:")
                imgui.BulletText(u8"6.2.1 Куратор больницы должен решать любые проблемы по мере их поступления")
                imgui.BulletText(u8"6.2.2 Куратор не подчиняется заместителям больницы")
                imgui.BulletText(u8"6.2.3 Куратор полностью отвечает за заместителей")
                imgui.BulletText(u8"6.2.4 Куратор вправе выдавать выговоры заместителям")
                imgui.BulletText(u8"6.2.5 Куратор получает 10% с проданного им ранга")
                imgui.TextWrapped(u8"Заместитель больницы:")
                imgui.BulletText(u8"6.3.1 Заместитель должен подчиняться вышестоящим по должности (Куратор, Лидер, Владелец, Администратор)")
                imgui.BulletText(u8"6.3.2 Заместитель может получить штраф от куратора и лидера по следующим причинам:")
                imgui.Indent(10)
                imgui.TextWrapped(u8"- Неподчинение вышестоящему по должности (выговор)")
                imgui.TextWrapped(u8"- Оскорбление игрока/неадекват (штраф 10-50кк (на усмотрение))")
                imgui.TextWrapped(u8"- Наказание от администрации (штраф 30кк)")
                imgui.TextWrapped(u8"- Неучастие в деятельности больницы более 2-х недель без уважительной причины (снятие)")
                imgui.Unindent(10)
            end
            if imgui.CollapsingHeader(u8"10. Увольнение и восстановление") then
                imgui.TextWrapped(u8"9.1 Человек на покупном ранге, уволенный СИСТЕМНО по причинам:")
                imgui.BulletText(u8"Отсутствие жилья")
                imgui.BulletText(u8"Варн/бан по вине игрока")
                imgui.BulletText(u8"Случайно уволился через /out")
                imgui.TextWrapped(u8"НЕ ВОССТАНАВЛИВАЕТСЯ! (Исключения: На усмотрение владельцев и лидера)")
                imgui.TextWrapped(u8"9.2 При увольнении игрока 6-го ранга по причинам:")
                imgui.BulletText(u8"Отсутствие жилья")
                imgui.BulletText(u8"Увольнение со стороны ФБР")
                imgui.BulletText(u8"Варн/бан по вине и ошибке админа")
                imgui.TextWrapped(u8"ВОССТАНАВЛИВАЕТСЯ НА ДОЛЖНОСТЬ.")
                imgui.TextWrapped(u8"9.3 Если наказание выдано по ошибке администратора и сотрудник, уволенный системой, смог это доказать — восстанавливаем.")
                imgui.TextWrapped(u8"9.4 Если по нарушению игрока он получил наказание — ранг не восстанавливается.")
            end
            if imgui.CollapsingHeader(u8"11. Наказания/штрафы 9-кам") then
                imgui.TextWrapped(u8"10.1 За неадекватное поведение: $35,000,000")
                imgui.TextWrapped(u8"10.2 Варн/бан: $35,000,000/$150,000,000")
                imgui.TextWrapped(u8"10.3 Снять выговор: $30,000,000")
                imgui.TextWrapped(u8"10.4 Мут за неадеквата: $75,000,000 (от 30 минут)")
                imgui.TextWrapped(u8"10.5 Писать в /d: $25,000,000")
                imgui.TextWrapped(u8"10.6 Неадекватное увольнение человека: $100,000,000 + извинение перед человеком")
                imgui.TextWrapped(u8"10.7 Неадекватная выдача выговора: $30,000,000")
                imgui.TextWrapped(u8"10.8 Неадекватная выдача мута: $10,000,000")
                imgui.TextWrapped(u8"10.9 Выгнал пациента из больницы не по правилам (НПБ): $5,000,000")
                imgui.TextWrapped(u8"10.10 Деморган (от 60 минут) штраф: $30,000,000")
                imgui.TextWrapped(u8"10.11 Неадекватное поведение/оскорбления в группе больницы (ТГ): $100,000,000")
                imgui.TextWrapped(u8"10.12 Отсылки на сторонние сайты, реклама чего-либо не связанного с игрой и запрещённого: $250,000,000")
                imgui.TextWrapped(u8"11. Не взятие ТГ/ДС у человека при бронировании: ВЫГОВОР + ШТРАФ 100КК")
                imgui.TextWrapped(u8"За невыплату штрафа даётся ЧС орги.")
            end
        elseif selectedTab[0] == 4 then
            if imgui.CollapsingHeader(u8"7. Ценовая политика для 6 рангов") then
                imgui.TextWrapped(u8"10 дней: $20,000,000 ($2,000,000/день); ($4,000,000 на казну орги)")
                imgui.TextWrapped(u8"20 дней: $35,000,000 ($1,750,000/день); ($7,000,000 на казну орги)")
                imgui.TextWrapped(u8"30 дней: $45,000,000 ($1,500,000/день); ($9,000,000 на казну орги)")
                imgui.TextWrapped(u8"60 дней: $75,000,000 ($1,250,000/день); ($15,000,000 на казну орги)")
            end
            if imgui.CollapsingHeader(u8"8. Ценовая политика для 7-х рангов") then
                imgui.TextWrapped(u8"10 дней: $30,000,000 ($3,000,000/день); ($9,000,000 на казну орги)")
                imgui.TextWrapped(u8"20 дней: $55,000,000 ($2,750,000/день); ($16,500,000 на казну орги)")
                imgui.TextWrapped(u8"30 дней: $75,000,000 ($2,500,000/день); ($22,500,000 на казну орги)")
                imgui.TextWrapped(u8"60 дней: $135,000,000 ($2,250,000/день); ($40,500,000 на казну орги)")
            end
            if imgui.CollapsingHeader(u8"9. Ценовая политика для 8 ранга") then
                imgui.TextWrapped(u8"30 дней: $150,000,000 ($5,000,000/день); ($60,000,000 на казну орги)")
                imgui.TextWrapped(u8"60 дней: $270,000,000 ($4,500,000/день); ($108,000,000 на казну орги)")
            end
            if imgui.CollapsingHeader(u8"3. Платные услуги") then
                imgui.TextWrapped(u8"3.1 Заместитель больницы в праве продавать услуги:")
                imgui.BulletText(u8"Рабочая виза Вайс-Сити")
                imgui.BulletText(u8"Снятие выговора")
                imgui.BulletText(u8"Снятие ЧС")
                imgui.TextWrapped(u8"3.2 Ценовая политика данных услуг:")
                imgui.BulletText(u8"Рабочая виза Вайс-Сити: $5,000,000 (Получаете 100% от продажи)")
                imgui.BulletText(u8"Снятие выговора: $10,000,000 (Получаете 50% от продажи)")
                imgui.BulletText(u8"Снятие ЧС: от $20,000,000 до $100,000,000 (смотрите на причину ЧС'а, Получаете 50%)")
                imgui.TextWrapped(u8"3.3 Любой руководитель при снятии выговора, ЧС'а должен предоставить отчет о пополнении счета организации.")
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
      sampAddChatMessage("{FFFF00}Скрипт JeffersonNorma: {00FF00}Версия 1.1", -1)
    sampAddChatMessage("{FFFF00}Скрипт JeffersonNorma: {00FF00}загружена!", -1)
    sampAddChatMessage("{FFFF00}Команда для запуска: {00FF00}/jmenu", -1)
    sampAddChatMessage("{FFFF00}Автор скрипта: {00FF00}Romeo_Fray", -1)
    sampAddChatMessage("{FFFF00}Нашли баги, обращайтесь в тг: {00FF00}@CandyLoveFanat", -1)
    wait(-1)
end


local function checkUpdate()
    local currentVersion = "1.0" -- Текущая версия скрипта (нужно задать вручную)
    local repoUrl = "https://raw.githubusercontent.com/ваш_пользователь/ваш_репозиторий/main/JeffersonHelper.lua"
    local versionUrl = "https://raw.githubusercontent.com/ваш_пользователь/ваш_репозиторий/main/version.txt"

    -- Получаем версию с GitHub
    local response = {}
    local _, status = http.request{
        url = versionUrl,
        sink = ltn12.sink.table(response)
    }
    if status == 200 then
        local latestVersion = table.concat(response)
        if latestVersion > currentVersion then
            sampAddChatMessage("{FFFF00}Найдена новая версия скрипта: " .. latestVersion, -1)
            -- Скачиваем обновление
            local file = io.open("JeffersonNorma_new.lua", "w")
            if file then
                http.request{
                    url = repoUrl,
                    sink = ltn12.sink.file(file)
                }
                file:close()
                -- Перемещаем новый файл и перезапускаем
                os.rename("JeffersonNorma_new.lua", "JeffersonNorma.lua")
                sampAddChatMessage("{00FF00}Скрипт обновлён. Перезапуск...", -1)
                -- Здесь нужен механизм перезапуска (зависит от среды MoonLoader)
                os.exit() -- Пример, требует доработки
            end
        else
            sampAddChatMessage("{00FFAA}Скрипт уже актуален.", -1)
        end
    end
end

-- Вызов проверки при запуске
checkUpdate()


function theme()
    local style = imgui.GetStyle()
    local colors = style.Colors
    style.Alpha = 1
    style.WindowPadding = imgui.ImVec2(15.00, 15.00)
    style.WindowRounding = 0
    style.WindowBorderSize = 1
    style.WindowMinSize = imgui.ImVec2(32.00, 32.00)
    style.WindowTitleAlign = imgui.ImVec2(0.50, 0.50)
    style.ChildRounding = 0
    style.ChildBorderSize = 1
    style.PopupRounding = 0
    style.PopupBorderSize = 1
    style.FramePadding = imgui.ImVec2(8.00, 7.00)
    style.FrameRounding = 0
    style.FrameBorderSize = 0
    style.ItemSpacing = imgui.ImVec2(8.00, 8.00)
    style.ItemInnerSpacing = imgui.ImVec2(10.00, 6.00)
    style.IndentSpacing = 25
    style.ScrollbarSize = 13
    style.ScrollbarRounding = 0
    style.GrabMinSize = 6
    style.GrabRounding = 0
    style.TabRounding = 0
    style.ButtonTextAlign = imgui.ImVec2(0.50, 0.50)
    style.SelectableTextAlign = imgui.ImVec2(0.00, 0.00)
    colors[imgui.Col.Text] = imgui.ImVec4(1.00, 1.00, 1.00, 1.00)
    colors[imgui.Col.TextDisabled] = imgui.ImVec4(0.60, 0.56, 0.56, 1.00)
    colors[imgui.Col.WindowBg] = imgui.ImVec4(0.16, 0.16, 0.16, 1.00)
    colors[imgui.Col.ChildBg] = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[imgui.Col.PopupBg] = imgui.ImVec4(0.26, 0.26, 0.26, 1.00)
    colors[imgui.Col.Border] = imgui.ImVec4(0.43, 0.43, 0.50, 0.50)
    colors[imgui.Col.BorderShadow] = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[imgui.Col.FrameBg] = imgui.ImVec4(0.20, 0.20, 0.20, 1.00)
    colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.33, 0.32, 0.32, 1.00)
    colors[imgui.Col.FrameBgActive] = imgui.ImVec4(0.38, 0.38, 0.38, 1.00)
    colors[imgui.Col.TitleBg] = imgui.ImVec4(0.22, 0.22, 0.22, 1.00)
    colors[imgui.Col.TitleBgActive] = imgui.ImVec4(0.23, 0.23, 0.23, 1.00)
    colors[imgui.Col.TitleBgCollapsed] = imgui.ImVec4(0.00, 0.00, 0.00, 0.51)
    colors[imgui.Col.MenuBarBg] = imgui.ImVec4(0.14, 0.14, 0.14, 1.00)
    colors[imgui.Col.ScrollbarBg] = imgui.ImVec4(0.19, 0.19, 0.19, 1.00)
    colors[imgui.Col.ScrollbarGrab] = imgui.ImVec4(0.23, 0.23, 0.23, 1.00)
    colors[imgui.Col.ScrollbarGrabHovered] = imgui.ImVec4(0.41, 0.41, 0.41, 1.00)
    colors[imgui.Col.ScrollbarGrabActive] = imgui.ImVec4(0.51, 0.51, 0.51, 1.00)
    colors[imgui.Col.CheckMark] = imgui.ImVec4(0.42, 0.43, 0.43, 1.00)
    colors[imgui.Col.SliderGrab] = imgui.ImVec4(0.42, 0.43, 0.43, 1.00)
    colors[imgui.Col.SliderGrabActive] = imgui.ImVec4(0.51, 0.51, 0.51, 1.00)
    colors[imgui.Col.Button] = imgui.ImVec4(0.26, 0.26, 0.26, 1.00)
    colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.32, 0.32, 0.32, 1.00)
    colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.38, 0.38, 0.38, 1.00)
    colors[imgui.Col.Header] = imgui.ImVec4(0.26, 0.26, 0.26, 1.00)
    colors[imgui.Col.HeaderHovered] = imgui.ImVec4(0.33, 0.32, 0.32, 1.00)
    colors[imgui.Col.HeaderActive] = imgui.ImVec4(0.38, 0.38, 0.38, 1.00)
    colors[imgui.Col.Separator] = imgui.ImVec4(0.38, 0.38, 0.38, 1.00)
    colors[imgui.Col.SeparatorHovered] = imgui.ImVec4(0.38, 0.38, 0.38, 1.00)
    colors[imgui.Col.SeparatorActive] = imgui.ImVec4(0.38, 0.38, 0.38, 1.00)
    colors[imgui.Col.ResizeGrip] = imgui.ImVec4(0.22, 0.22, 0.22, 1.00)
    colors[imgui.Col.ResizeGripHovered] = imgui.ImVec4(0.22, 0.22, 0.22, 1.00)
    colors[imgui.Col.ResizeGripActive] = imgui.ImVec4(0.33, 0.32, 0.32, 1.00)
    colors[imgui.Col.Tab] = imgui.ImVec4(0.26, 0.26, 0.26, 1.00)
    colors[imgui.Col.TabHovered] = imgui.ImVec4(0.33, 0.32, 0.32, 1.00)
    colors[imgui.Col.TabActive] = imgui.ImVec4(0.38, 0.38, 0.38, 1.00)
    colors[imgui.Col.TabUnfocused] = imgui.ImVec4(0.26, 0.26, 0.26, 1.00)
    colors[imgui.Col.TabUnfocusedActive] = imgui.ImVec4(0.38, 0.38, 0.38, 1.00)
    colors[imgui.Col.PlotLines] = imgui.ImVec4(0.61, 0.61, 0.61, 1.00)
    colors[imgui.Col.PlotLinesHovered] = imgui.ImVec4(1.00, 0.43, 0.35, 1.00)
    colors[imgui.Col.PlotHistogram] = imgui.ImVec4(0.90, 0.70, 0.00, 1.00)
    colors[imgui.Col.PlotHistogramHovered] = imgui.ImVec4(1.00, 0.60, 0.00, 1.00)
    colors[imgui.Col.TextSelectedBg] = imgui.ImVec4(0.33, 0.33, 0.33, 0.50)
    colors[imgui.Col.DragDropTarget] = imgui.ImVec4(1.00, 1.00, 0.00, 0.90)
    colors[imgui.Col.NavHighlight] = imgui.ImVec4(0.26, 0.59, 0.98, 1.00)
    colors[imgui.Col.NavWindowingHighlight] = imgui.ImVec4(1.00, 1.00, 1.00, 0.70)
    colors[imgui.Col.NavWindowingDimBg] = imgui.ImVec4(0.80, 0.80, 0.80, 0.20)
    colors[imgui.Col.ModalWindowDimBg] = imgui.ImVec4(0.80, 0.80, 0.80, 0.35)
end

imgui.OnInitialize(function()
    theme()
end)
