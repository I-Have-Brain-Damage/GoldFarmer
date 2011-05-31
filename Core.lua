if not AucAdvanced then return end
local print,decode,_,_,replicate,empty,get,set,default,debugPrint,fill, _TRANS = AucAdvanced.GetModuleLocals()

if not BankStack then return end

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


lib:RegisterChatCommand("bstest", "BankStackTest")
function lib:BankStackTest(input)
    
	if BankStack.running then
		BankStack.announce(0, L.already_running, 1, 0, 0)
		return
	end
	
    local empty = {}
    local items = {}
    
    for i, bag, slot in BankStack.IterateBags({0, 1, 2, 3, 4}, nil, "both") do
		--(you need withdraw *and* deposit permissions in the guild bank to move items within it)
		local bagslot = BankStack.encode_bagslot(bag, slot)
        local link = GetContainerItemLink(bag, slot)
		if link then
		    table.insert(items, bagslot)
	    else
	        table.insert(empty, bagslot)
        end
	end
	
	for i, source in ipairs(items) do
	    if #empty == 0 then break end
	    local empty_i = math.random(1, #empty)
	    local dest = empty[empty_i]
	    table.remove(empty, empty_i)
	    lib:Print('move ' .. source .. ' to ' .. dest)
	    BankStack.AddMove(source, dest)
    end
    
	BankStack.StartStacking()
	
end