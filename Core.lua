if not AucAdvanced then return end
local print,decode,_,_,replicate,empty,get,set,default,debugPrint,fill, _TRANS = AucAdvanced.GetModuleLocals()


MoneyMaker = LibStub("AceAddon-3.0"):NewAddon("MoneyMaker", "AceConsole-3.0")
local lib = MoneyMaker

local Appraiser = AucAdvanced.GetModule("Util", "Appraiser")
local Suggest = AucAdvanced.GetModule("Util", "ItemSuggest")
local Undercut = AucAdvanced.GetModule("Match", "Undercut")

function lib:OnInitialize()
    --
end

function lib:OnEnable()
    lib:Print("loaded")
end

function lib:OnDisable()
    --
end

lib:RegisterChatCommand("xxx", "DumpPrices")
function lib:DumpPrices(input)
    -- local stat = AucAdvanced.GetModule("Stat", "Simple")
    local stat = AucAdvanced.GetModule("Util", "Appraiser")
    local suggest = AucAdvanced.GetModule("Util", "ItemSuggest")
    for bag = 0,4 do
        for slot = 1,GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                
                local dayAverage, avg3, avg7, avg14, minBuyout, avgmins, _, dayTotal, dayCount, seenDays, seenCount, mean, variance = stat.GetPrice(link)
                lib:Print(bag .. "," .. slot .. ": " .. link .. " -> " .. GetCoinTextureString(dayAverage))
                
                local midpoint, seen, nPdfList = AucAdvanced.API.GetMarketValue(link)
                lib:Print('market value ' .. GetCoinTextureString(midpoint) .. ' (seen ' .. seen .. ')')
                
                local suggestion, value = suggest.Suggest(link)
                lib:Print('suggestion ' .. suggestion .. ' for ' .. GetCoinTextureString(value))
            end
        end
    end
end


lib.STATE_NO_COMPETITION = 'no competition'
lib.STATE_CANNOT_UNDERCUT = 'cannot undercut'
lib.STATE_ABOVE_MARKET = 'competition above market'
lib.STATE_UNDERCUTTING = 'undercutting competition'


function lib:GetAucData(link)
    
    local model = get("match.undercut.model")
    if not model then
        lib:Print('could no get undercut model')
        return
    end
    
    local market
    
    if model == "market" then
        market = AucAdvanced.API.GetMarketValue(link)
    else
        market = AucAdvanced.API.GetAlgorithmValue(model, link)
    end
    
    local data = Undercut.GetMatchArray(link, market)
    data = replicate(data)
    data.market = market
    
    if data.competing == 0 then
        data.state = lib.STATE_NO_COMPETITION
    elseif data.returnstring:find("Can not match") then
        data.state = lib.STATE_CANNOT_UNDERCUT
    elseif data.returnstring:find("Lowest") then
        if data.value >= market then
            data.state = lib.STATE_ABOVE_MARKET
        else
            data.state = lib.STATE_UNDERCUTTING
        end
    end
    
    return data
        
end

lib:RegisterChatCommand("price", "DumpPricesTwo")
function lib:DumpPricesTwo(input)
    
    
    
    for bag = 0,4 do for slot = 1,GetContainerNumSlots(bag) do
        local link = GetContainerItemLink(bag, slot)
        if link then
        
            local data = lib:GetAucData(link)
            
            if data.state == lib.STATE_CANNOT_UNDERCUT then
                lib:Print(link .. ': ' .. data.state)
            else
                lib:Print(link .. ': ' .. GetCoinTextureString(data.value))
            end
       end 
    end end
end




lib:RegisterChatCommand("dumplink", "SlashDumpLink")
function lib:SlashDumpLink(input)
    for bag = 0,4 do
        for slot = 1,GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local printable = gsub(link, "|", "||")
                lib:Print(bag .. "," .. slot .. ": " .. printable)
            end
            -- local _, _, Color, Ltype, Id, Enchant, Gem1, Gem2, Gem3, Gem4, Suffix, Unique, LinkLvl, Name = string.find(link, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*)|?h?%[?([^%[%]]*)%]?|?h?|?r?")
            -- lib:Print("SlashDumpLink " .. Name .. " " .. Unique)
        end
    end
end