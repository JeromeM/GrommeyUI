-- Money of the character, shared by the bag and the info bar.

Grommey.Money = {};

local function Call(object, method)
    if (object == nil or object[method] == nil) then return nil; end
    local ok, a, b, c = pcall(object[method], object);
    if (ok) then return a, b, c; end
    return nil;
end

-- All the money of the character in copper (1 gold = 1000 silver = 100000 copper), nil if unknown
function Grommey.Money.Total()
    local attributes = Call(Turbine.Gameplay.LocalPlayer.GetInstance(), "GetAttributes");
    local copper = Call(attributes, "GetMoney");
    if (copper ~= nil) then return copper; end
    local silver, gold;
    copper, silver, gold = Call(attributes, "GetMoneyComponents");
    if (gold == nil) then return nil; end
    return gold * 100000 + silver * 100 + copper;
end

-- 123456 -> "1 g 234 s 56 c" in the coin colours (markup), only gold with goldOnly
function Grommey.Money.Text(total, goldOnly)
    local gold = math.floor(total / 100000);
    local silver = math.floor(total / 100) % 1000;
    local copper = total % 100;
    if (goldOnly) then return "<rgb=#E8C45C>" .. gold .. L(" g") .. "</rgb>"; end
    local text = "";
    if (gold > 0) then text = "<rgb=#E8C45C>" .. gold .. L(" g") .. "</rgb> "; end
    if (gold > 0 or silver > 0) then text = text .. "<rgb=#C8CCD2>" .. silver .. L(" s") .. "</rgb> "; end
    return text .. "<rgb=#C88A52>" .. copper .. L(" c") .. "</rgb>";
end
