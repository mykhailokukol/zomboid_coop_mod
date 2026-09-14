--
-- CO-OP - shared helpers for the mod as a whole.
--
-- Feature modules keep their own prefixes (BAH_* for the "books at home" list);
-- anything used by more than one feature belongs here.
--

COOP = COOP or {}

function COOP.log(_msg)
    print("[CO-OP] " .. tostring(_msg))
end
