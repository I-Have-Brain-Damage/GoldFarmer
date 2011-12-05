if not AucAdvanced then return end
local print,decode,_,_,replicate,empty,get,set,default,debugPrint,fill, _TRANS = AucAdvanced.GetModuleLocals()

if not BankStack then return end

GoldFarmer = LibStub("AceAddon-3.0"):NewAddon("GoldFarmer", "AceConsole-3.0")
local lib = GoldFarmer

local Appraiser = AucAdvanced.GetModule("Util", "Appraiser")
local Suggest = AucAdvanced.GetModule("Util", "ItemSuggest")
local Undercut = AucAdvanced.GetModule("Match", "Undercut")

local SigFromLink = AucAdvanced.API.GetSigFromLink



local function GetItemID(link)
    if type(link) == "number" then return link end
    if link then
        return tonumber(link:match("item:(%d+)"))
    end
end

local function GetItemInfoTable(item)
    local name, link, rarity, level, minLevel, type, subType, stackCount = GetItemInfo(item)
    return {
        name=name,
        link=link,
        rarity=rarity,
        level=level,
        minLevel=minLevel,
        type=type,
        subType=subType,
        stackCount=stackCount,
    }
end

local function GetSlotInfoTable(bag, slot)
    if bag > 50 then
        local tab = bag - 50
        local texture, count, locked = GetGuildBankItemInfo(tab, slot)
        local link = GetGuildBankItemLink(tab, slot)
        return {
            texture=texture,
            count=count,
            locked=locked,
            quality=nil,
            readable=nil,
            lootable=nil,
            link=link,
        }
    
    else
        local texture, count, locked, quality, readable, lootable, link = BankStack.GetItemInfo(bag, slot)
        return {
            texture=texture,
            count=count,
            locked=locked,
            quality=quality,
            readable=readable,
            lootable=lootable,
            link=link,
        }
    end
end

local function GetCounts(link)
    local character = DataStore:GetCharacter() or 'nil'
    local item_id = GetItemID(link) or 'nil'
    local auc_count = DataStore:GetAuctionHouseItemCount(character, item_id) or 'nil'
    local bag_count, bank_count = DataStore:GetContainerItemCount(character, item_id)
    -- lib:Print('GetCounts -> ' .. bag_count .. ', ' .. bank_count .. ', ' .. auc_count)
    return bag_count, bank_count, auc_count
end


local type_to_ideal_auction_count = {
    ["Armor"]= 1,
    ["Gem"]= 4,
    ["Recipe"]= 1,
    ["Weapon"]= 1,
    ["Trade Goods"]= 20 * 9,
}

local function GetIdealAuctionCount(item)
    
    local info = GetItemInfoTable(item)

    -- Lookup appraiser stack sizes and counts.
    local sig = SigFromLink(info.link)
    local count = get('util.appraiser.item.' .. sig .. ".number") 
    if count then
        local stack = get('util.appraiser.item.' .. sig .. ".stack") or info.stackCount
        return count * stack
    end
    
    -- If the item isn't stackable, assume only one.
    if info.stackCount == 1 then
        return 1
    end

    -- Some hardcoded defaults based on item type.
    local count = type_to_ideal_auction_count[info.type]
    if count then
        return count
    end


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
    elseif data.Result == "NoMatch" then
        data.state = lib.STATE_CANNOT_UNDERCUT
    elseif data.Result:find("Lowe") then -- "Lowest" or "LowerBid"
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
            local item_id = GetItemID(link)
            local info = GetItemInfoTable(link)
            local data = lib:GetAucData(link)
            lib:Print(link .. ': ' .. data.Result)
        end
    end
    
end



lib:RegisterChatCommand("stopsort", "StopSort")
function lib:StopSort(input)
    BankStack.StopStacking()
end



lib:RegisterChatCommand("aucsort", "AuctionSort")
function lib:AuctionSort(input)
    
    local bag, slot, bagslot
    
    if BankStack.running then
        BankStack.StopStacking()
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
        -- lib:Print('sale_counts[' .. item .. '] = ' .. sale_counts[item])
    end
    
    local function AddSlotToSaleCounts(bag, slot)
        local info = GetSlotInfoTable(bag, slot)
        AddToSaleCounts(GetItemID(info.link), info.count)
    end
    
    -- lib:Print('how many are for sale')
    
    -- How many are already up for sale?
    for i, bag, slot in BankStack.IterateBags(BankStack.all_bags_with_guild, nil, "both") do
        local link = BankStack.GetItemLink(bag, slot)
        if link then
            local bag_count, bank_count, auc_count = GetCounts(link)
            AddToSaleCounts(GetItemID(link), auc_count)
        end
    end
    
        
    local function DoSell(link)
        local item = GetItemID(link)
        local sale_count = sale_counts[item] or 0
        local ideal_count = GetIdealAuctionCount(item)
        -- lib:Print('DoSell(' .. link .. '): sale_count=' .. sale_count .. ', ideal_count=' .. (ideal_count or 'nil'))
        if ideal_count and ((sale_count or 0) >= ideal_count) then
            return false
        end
        local data = lib:GetAucData(link)
        return data.state ~= lib.STATE_CANNOT_UNDERCUT
    end
        
    -- Tables to contain the bagslots to move.
    local empty_selling = {}
    local empty_storage = {}
    local selling_to_storage = {}
    local storage_to_selling = {}
    
    -- lib:Print('start scanning')
    
    -- Scan the selling bags.
    for i, bag, slot in BankStack.IterateBags(selling, nil, "both") do
        bagslot = BankStack.encode_bagslot(bag, slot)
        local link = BankStack.GetItemLink(bag, slot)
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
        local link = BankStack.GetItemLink(bag, slot)
        if not link then
            table.insert(empty_storage, bagslot)
        else
            -- lib:Print(bag .. ' ' .. slot .. ' ' .. link)
            if DoSell(link) then
                table.insert(storage_to_selling, bagslot)
                lib:Print('>>> ' .. link)
                AddSlotToSaleCounts(bag, slot)
            end
        end
    end    
    
    if input == 'dryrun' then
        return
    end

    local did_move = true
    
    while did_move and (#selling_to_storage > 0 or #storage_to_selling > 0) do
        
        -- lib:Print(#selling_to_storage .. ' ' .. #storage_to_selling)
        
        did_move = false
        
        while #selling_to_storage > 0 and #empty_storage > 0 do
            source = table.remove(selling_to_storage, 1)
            dest   = table.remove(empty_storage, 1)
            BankStack.AddMove(source, dest)
            table.insert(empty_selling, source)
            did_move = true
        end
        
        while #storage_to_selling > 0 and #empty_selling > 0 do
            source = table.remove(storage_to_selling, 1)
            dest   = table.remove(empty_selling, 1)
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











local function default_can_move() return true end
function lib.Stash(source_bags, target_bags, can_move)
    
    local bag, slot, bagslot
    
    if BankStack.running then
        BankStack.StopStacking()
    end
    BankStack.ScanBags()    
    
    local empty_dest = {}
    for i, bag, slot in BankStack.IterateBags(target_bags, nil, "deposit") do
        local bagslot = BankStack.encode_bagslot(bag, slot)
        local link = BankStack.GetItemLink(bag, slot)
        if not link then
            table.insert(empty_dest, bagslot)
        end
    end    
    
    
    for i, bag, slot in BankStack.IterateBags(source_bags, nil, "withdraw") do
        local bagslot = BankStack.encode_bagslot(bag, slot)
        local link = BankStack.GetItemLink(bag, slot)
        if link and #empty_dest > 0 then
            local dest_slot = table.remove(empty_dest)
            BankStack.AddMove(bagslot, dest_slot)
        end
    end
    
    BankStack.StartStacking()
    
end


SlashCmdList["STASH"] = BankStack.CommandDecorator(lib.Stash, "bags bank")
SLASH_STASH1 = "/stash"
SlashCmdList["UNSTASH"] = BankStack.CommandDecorator(lib.Stash, "bank bags")
SLASH_UNSTASH1 = "/unstash"



