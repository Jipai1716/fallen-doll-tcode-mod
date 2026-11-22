-- Fallen Doll 0.9.1 rehost build (exe sha256 85EB598D...)
-- GNatives (RVA 0xAB0C6D0) is a .data pointer table whose entries are all
-- relocated at load time, so a data byte pattern cannot match the mapped image.
-- Anchor on the first relocation-free block inside the table (+0x7F8) and step back.
function Register()
    return "40 42 0F 00 00 00 80 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"
end

function OnMatchFound(MatchAddress)
    return MatchAddress - 0x7F8
end