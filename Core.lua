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


local function GetIDFromLink(link)
	if link then
		return tonumber(link:match("item:(%d+)"))
	end
end

local function GetStackCount(link)
    local sName, sLink, iRarity, iLevel, iMinLevel, sType, sSubType, iStackCount = GetItemInfo(link)
    return iStackCount
end

local function GetCounts(link)
    local character = DataStore:GetCharacter() or 'nil'
    local item_id = GetIDFromLink(link) or 'nil'
    local auc_count = DataStore:GetAuctionHouseItemCount(character, item_id) or 'nil'
    local bag_count, bank_count = DataStore:GetContainerItemCount(character, item_id)
    -- lib:Print('GetCounts -> ' .. bag_count .. ', ' .. bank_count .. ', ' .. auc_count)
    return bag_count, bank_count, auc_count
end




lib.STATE_NO_COMPETITION = 'no competition'
lib.STATE_CANNOT_UNDERCUT = 'cannot undercut'
lib.STATE_ABOVE_MARKET = 'competition above market'
lib.STATE_UNDERCUTTING = 'undercutting competition'


function lib:GetAucData(link)
    
    -- lib:Print('GetAucData(' .. link .. ')')
    
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
    market = market or 0
    
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

local ALL_BAGS = {BANK_CONTAINER, 0}
for i = 1,NUM_BAG_SLOTS+NUM_BANKBAGSLOTS do table.insert(ALL_BAGS, i) end



lib:RegisterChatCommand("mmtest", "MMTest")
function lib:MMTest(input)
    
    local i, bag, slot
    for i, bag, slot in BankStack.IterateBags(BankStack.player_bags, nil, "both") do

        local link = GetContainerItemLink(bag, slot)
        if link then
            
            local item_id = GetIDFromLink(link)
            local iStackCount = GetStackCount(link)
            local bag_count, bank_count, auc_count = GetCounts(link)
            
            lib:Print(link .. ' -> ' .. item_id .. ' bag=' .. bag_count .. ', bank=' .. bank_count .. ', auc=' .. auc_count .. ' stack=' .. iStackCount)
        
        end
    end
    
end

lib:RegisterChatCommand("marketsort", "MarketSort")
function lib:MarketSort(input)
    
    local bag, slot, bagslot
    
    -- Copypasta from the front of the BankStack sorters; required for
    -- operation.
    if BankStack.running then
        BankStack.announce(0, BankStack.L.already_running, 1, 0, 0)
        return
    end
    BankStack.ScanBags()
    
    if not (BankStack.bank_open or BankStack.guild_bank_open) then
        lib:Print('must be at bank or guild bank')
        return
    end
    
    -- The bags to store items to sell.
    local selling = BankStack.player_bags
    
    -- The bags into which we will store non-selling items.
    local storage
    if BankStack.bank_open then
        storage = BankStack.bank_bags
    else
        storage = BankStack.guild
    end
    
    -- Tables to contain the bagslots to move.
    local empty_selling = {}
    local empty_storage = {}
    local selling_to_storage = {}
    local storage_to_selling = {}
    
    -- Scan the selling bags.
    for i, bag, slot in BankStack.IterateBags(selling, nil, "both") do
        bagslot = BankStack.encode_bagslot(bag, slot)
        local link = GetContainerItemLink(bag, slot)
        if not link then
            table.insert(empty_selling, bagslot)
        else
            local data = lib:GetAucData(link)
            if data.state == lib.STATE_CANNOT_UNDERCUT then
                table.insert(selling_to_storage, bagslot)
                -- lib:Print('<<< ' .. link)
            end
        end
    end
    
    -- Scan the storage bags.
    for i, bag, slot in BankStack.IterateBags(storage, nil, "both") do
        local bagslot = BankStack.encode_bagslot(bag, slot)
        local link = GetContainerItemLink(bag, slot)
        if not link then
            table.insert(empty_storage, bagslot)
        else
            local data = lib:GetAucData(link)
            if data.state ~= lib.STATE_CANNOT_UNDERCUT then
                table.insert(storage_to_selling, bagslot)
                -- lib:Print('>>> ' .. link)
            end
        end
    end    
    
    local did_move = true
    
    while did_move and (#selling_to_storage > 0 or #storage_to_selling > 0) do
        
        -- lib:Print(#selling_to_storage .. ' ' .. #storage_to_selling)
        
        did_move = false
        
        while #selling_to_storage > 0 and #empty_storage > 0 do
            source = table.remove(selling_to_storage)
            dest   = table.remove(empty_storage)
            BankStack.AddMove(source, dest)
            table.insert(empty_selling, source)
            did_move = true
        end
        
        while #storage_to_selling > 0 and #empty_selling > 0 do
            source = table.remove(storage_to_selling)
            dest   = table.remove(empty_selling)
            BankStack.AddMove(source, dest)
            table.insert(empty_storage, source)
            did_move = true
        end
    end
    
    if #selling_to_storage > 0 then
        lib:Print(#selling_to_storage .. ' more items to move into bank')
    end
    if #storage_to_selling > 0 then
        lib:Print(#storage_to_selling .. ' more items to move into bags')
    end
    
    
    BankStack.StartStacking()
    
end



lib:RegisterChatCommand("aucsort", "AuctionSort")
function lib:AuctionSort(input)
    
    local bag, slot, bagslot
    
    -- Copypasta from the front of the BankStack sorters; required for
    -- operation.
    if BankStack.running then
        BankStack.announce(0, BankStack.L.already_running, 1, 0, 0)
        return
    end
    BankStack.ScanBags()
    
    if not (BankStack.bank_open or BankStack.guild_bank_open) then
        lib:Print('must be at bank or guild bank')
        return
    end
    
    -- The bags to store items to sell.
    local selling = BankStack.player_bags
    
    -- The bags into which we will store non-selling items.
    local storage
    if BankStack.bank_open then
        storage = BankStack.bank_bags
    else
        storage = BankStack.guild
    end
    
    local sale_counts = {}
    local function AddToSaleCounts(item, qty)
        sale_counts[item] = (sale_counts[item] or 0) + qty
        lib:Print('sale_counts[' .. item .. '] = ' .. sale_counts[item])
    end
    
    local function AddSlotToSaleCounts(bag, slot)
        local link = GetContainerItemLink(bag, slot)
        local stack_size = GetStackCount(link)
        if stack_size ~= 1 then return end
        local item = GetIDFromLink(link)
        AddToSaleCounts(item, 1)
    end
    
    lib:Print('how many are for sale')
    
    -- How many are already up for sale?
    for i, bag, slot in BankStack.IterateBags(BankStack.all_bags, nil, "both") do
        lib:Print('(' .. bag .. ', ' .. slot .. ')')
        local link = BankStack.GetItemLink(bag, slot)
        lib:Print(link)
        if link then
            local bag_count, bank_count, auc_count = GetCounts(link)
            if auc_count > 0 then 
                AddToSaleCounts(GetIDFromLink(link), auc_count)
            end
        end
    end
    
        
    local function DoSell(link)
        local item = GetIDFromLink(link)
        local stack_size = GetStackCount(link)
        if stack_size == 1 then
            local sale_count = sale_counts[item]
            if sale_count then
                return false
            end
        end
        local data = lib:GetAucData(link)
        return data.state ~= lib.STATE_CANNOT_UNDERCUT
    end
        
    -- Tables to contain the bagslots to move.
    local empty_selling = {}
    local empty_storage = {}
    local selling_to_storage = {}
    local storage_to_selling = {}
    
    lib:Print('start scanning')
    
    -- Scan the selling bags.
    for i, bag, slot in BankStack.IterateBags(selling, nil, "both") do
        bagslot = BankStack.encode_bagslot(bag, slot)
        local link = GetContainerItemLink(bag, slot)
        if not link then
            table.insert(empty_selling, bagslot)
        else
            if not DoSell(link) then
                table.insert(selling_to_storage, bagslot)
                lib:Print('<<< ' .. link)
            else
                AddSlotToSaleCounts(bag, slot)
            end
        end
    end
    
    -- Scan the storage bags.
    for i, bag, slot in BankStack.IterateBags(storage, nil, "both") do
        local bagslot = BankStack.encode_bagslot(bag, slot)
        local link = GetContainerItemLink(bag, slot)
        if not link then
            table.insert(empty_storage, bagslot)
        else
            if DoSell(link) then
                table.insert(storage_to_selling, bagslot)
                lib:Print('>>> ' .. link)
                AddSlotToSaleCounts(bag, slot)
            end
        end
    end    
    
    local did_move = true
    
    while did_move and (#selling_to_storage > 0 or #storage_to_selling > 0) do
        
        -- lib:Print(#selling_to_storage .. ' ' .. #storage_to_selling)
        
        did_move = false
        
        while #selling_to_storage > 0 and #empty_storage > 0 do
            source = table.remove(selling_to_storage)
            dest   = table.remove(empty_storage)
            BankStack.AddMove(source, dest)
            table.insert(empty_selling, source)
            did_move = true
        end
        
        while #storage_to_selling > 0 and #empty_selling > 0 do
            source = table.remove(storage_to_selling)
            dest   = table.remove(empty_selling)
            BankStack.AddMove(source, dest)
            table.insert(empty_storage, source)
            did_move = true
        end
    end
    
    if #selling_to_storage > 0 then
        lib:Print(#selling_to_storage .. ' more items to move into bank')
    end
    if #storage_to_selling > 0 then
        lib:Print(#storage_to_selling .. ' more items to move into bags')
    end
    
    
    BankStack.StartStacking()
    
end