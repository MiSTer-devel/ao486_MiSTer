package.path = package.path .. ";./../lualib/?.lua"
package.path = package.path .. ";./../luatools/?.lua"
require("vsim_comm")

listing = {}
labelcount = 0

for i = 0, 50 do
   listing[#listing + 1] = "mov EAX, 0"
   listing[#listing + 1] = "mov EBX, "..i
   listing[#listing + 1] = "mov ECX, 0"
   listing[#listing + 1] = "mov EDX, 0"
   listing[#listing + 1] = "inc byte ptr setvalue"..i.."+1"
   for j = 1, i do
      listing[#listing + 1] = "inc cl"
   end
   listing[#listing + 1] = "setvalue"..i..":"
   listing[#listing + 1] = "mov al, 0"
   listing[#listing + 1] = "dec byte ptr setvalue"..i.."+1"
   listing[#listing + 1] = "sub bl, cl"
   listing[#listing + 1] = "jz noerror"..i
   listing[#listing + 1] = "mov EDX, 1"
   listing[#listing + 1] = "noerror"..i..":"
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
wait_ns(250000)