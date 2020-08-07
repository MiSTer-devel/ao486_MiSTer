package.path = package.path .. ";./../lualib/?.lua"
package.path = package.path .. ";./../luatools/?.lua"
require("vsim_comm")

function get_reg8()
   rnd = math.random(0, 7)
   if     (rnd == 0) then return "AL"
   elseif (rnd == 1) then return "CL"
   elseif (rnd == 2) then return "DL"
   elseif (rnd == 3) then return "BL"
   elseif (rnd == 4) then return "AH"
   elseif (rnd == 5) then return "CH"
   elseif (rnd == 6) then return "DH"
   elseif (rnd == 7) then return "BH"
   end
end

function get_reg16()
   rnd = math.random(0, 7)
   if     (rnd == 0) then return "AX"
   elseif (rnd == 1) then return "CX"
   elseif (rnd == 2) then return "DX"
   elseif (rnd == 3) then return "BX"
   elseif (rnd == 4) then return "SP"
   elseif (rnd == 5) then return "BP"
   elseif (rnd == 6) then return "SI"
   elseif (rnd == 7) then return "DI"
   end
end

function get_reg32()
   return "E"..get_reg16()
end

function get_immi8()
   return "0x"..string.format("%X", math.random(0, 255))
end
function get_immi16()
   return "0x"..string.format("%X", math.random(0, 0xFFFF))
end
function get_immi32()
   return "0x"..string.format("%X", math.random(0, 0xFFFF))..string.format("%X", math.random(0, 0xFFFF))
end

function get_regany()
   return get_reg8()
end

function opcode_reg_immi(opcode)
   rnd = math.random(0, 5)
   if     (rnd == 0) then listing[#listing + 1] = opcode.." "..get_reg8()..", "..get_immi8()
   elseif (rnd == 1) then listing[#listing + 1] = opcode.." "..get_reg16()..", "..get_immi16()
   elseif (rnd == 2) then listing[#listing + 1] = opcode.." "..get_reg32()..", "..get_immi32()
   elseif (rnd == 3) then listing[#listing + 1] = opcode.." "..get_reg8()..", "..get_reg8()
   elseif (rnd == 4) then listing[#listing + 1] = opcode.." "..get_reg16()..", "..get_reg16()
   elseif (rnd == 5) then listing[#listing + 1] = opcode.." "..get_reg32()..", "..get_reg32()
   end
end

function jump_forward_random(opcode)
   listing[#listing + 1] = opcode.." Label"..labelcount
   distance = math.random(1, 5)
   for i = 1, distance do
      listing[#listing + 1] = "nop"
   end
   listing[#listing + 1] = "Label"..labelcount..":"
   labelcount = labelcount + 1
end


listing = {}
labelcount = 0
math.randomseed(1)
while (#listing < 1000) do
   rnd = math.random(0, 100)
   if     (rnd < 10) then opcode_reg_immi("MOV")
   
   elseif (rnd == 30) then jump_forward_random("JMP")
   
   elseif (rnd == 50) then opcode_reg_immi("OR")
   elseif (rnd == 51) then opcode_reg_immi("AND")
   
   elseif (rnd == 70) then opcode_reg_immi("ADD")
   elseif (rnd == 71) then opcode_reg_immi("SUB")
   
   
   elseif (rnd == 98) then
      listing[#listing + 1] = "mov EAX, 0x" .. string.format("%X", math.random(0, 0xFFFF))
      listing[#listing + 1] = "mov EBX, 0x" .. string.format("%X", math.random(0, 0xFFFF))
      listing[#listing + 1] = "mov ECX,[EAX]"
      listing[#listing + 1] = "mov EDX,[EBX]"
   
   elseif (rnd == 99) then
      listing[#listing + 1] = "mov EAX, "..math.random(0, 7)
      listing[#listing + 1] = "mov ECX, "..math.random(0, 7)
      listing[#listing + 1] = "mov EBX,0x12345678"
      listing[#listing + 1] = "mov [EAX],EBX"
      listing[#listing + 1] = "mov [ECX],EBX"
   
   end
end
listing[#listing + 1] = "JMP 0"


local outfile=io.open("listing.txt","w")
for i = 1, #listing do 
   outfile:write(listing[i].."\n")
end
io.close(outfile)

os.execute("FASM.EXE listing.txt")

reg_set_file("boot0.rom", DUMMYREG, 0xF0000, 0)
reg_set_file("lua_tests/listing.bin", DUMMYREG, 0, 0)

reg_set_connection(0 + 1, DUMMYREG)
wait_ns(10000)
reg_set_connection(0 + 0, DUMMYREG)
wait_ns(50000)

reg_set_connection(2 + 1, DUMMYREG)
wait_ns(10000)
reg_set_connection(2 + 0, DUMMYREG)
wait_ns(50000)