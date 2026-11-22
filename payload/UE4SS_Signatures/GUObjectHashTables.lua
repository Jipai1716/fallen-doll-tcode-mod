-- Fallen Doll 0.9.1 rehost build (exe sha256 85EB598D...)
-- FUObjectHashTables::Get() at image RVA 0x15E8630 (verified unique in .text)
function Register()
    return "40 53 48 83 EC 20 8B 0D 74 53 B1 09 65 48 8B 04"
end

function OnMatchFound(MatchAddress)
    return MatchAddress
end