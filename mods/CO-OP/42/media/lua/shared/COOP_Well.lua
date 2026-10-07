--
-- CO-OP - digging a well: the sandbox switch.
--
-- The well is vanilla's Base.Well with a build recipe added (scripts/
-- entity_coop_well.txt); the sacks of dirt it gives back are in
-- server/COOP_WellServer.lua. Turning the option off only hides the recipe from the
-- Build window, through the recipe's OnAddToMenu: the wells already dug are ordinary
-- vanilla wells and stay as they are.
--

require "COOP_Common"

COOPWell = COOPWell or {}

function COOPWell.isEnabled()
    return COOP.featureEnabled(COOP.F_WELL)
end

-- OnAddToMenu is looked up by callLuaBool with a raw get on the global table, so it
-- has to be a plain global name - "COOPWell.inMenu" would never be found.
function COOP_WellInMenu(_params)
    return COOPWell.isEnabled()
end
