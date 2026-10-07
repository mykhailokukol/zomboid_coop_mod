--
-- CO-OP - digging a well: the sacks of dirt the digging leaves behind.
--
-- The well itself is vanilla's Base.Well with a build recipe added
-- (scripts/entity_coop_well.txt). A build recipe has no outputs, so the three sacks
-- that went in empty come back full from here: this is the recipe's OnCreate, which
-- ISBuildIsoEntity:create calls once per build as (craftRecipeData, character).
--
-- The build runs where the object is created - on the server in multiplayer, on the
-- one machine in single player - and the items are added there and sent to the
-- client, as vanilla's own OnCreate code does. The function is defined on a
-- multiplayer client as well, so a call there finds it, but hands out nothing: the
-- server's sacks are the real ones.
--

COOPWell = COOPWell or {}

COOPWell.DIRT = "Base.Dirtbag"
COOPWell.DIRT_COUNT = 3

function COOPWell.onBuilt(_craftRecipeData, _character)
    if isClient() then return end
    if _character == nil then return end

    local inventory = _character:getInventory()
    if inventory == nil then return end

    for _ = 1, COOPWell.DIRT_COUNT do
        local item = inventory:AddItem(COOPWell.DIRT)
        if item == nil then break end
        sendAddItemToContainer(inventory, item)
    end
end
