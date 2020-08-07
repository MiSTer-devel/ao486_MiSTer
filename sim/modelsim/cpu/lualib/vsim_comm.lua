function string:split(sep)
        local sep, fields = sep or ":", {}
        local pattern = string.format("([^%s]+)", sep)
        self:gsub(pattern, function(c) fields[#fields+1] = c end)
        return fields
end

function conv_neg(x)
   if (x < 0) then
      return (2147483647 + (2147483649 - ((x * (-1)) )))
   else
      return x
   end
end

function conv_to_neg(x)
   if (x > 2147483647) then
      return x - (2* 2147483648)
   else
      return x
   end
end

function binary_and(a,b)
  local r = 0
  local neg = 1
  if (a < 0) then
   a = a * (-1)
   neg = neg * (-1)
  end
  if (b < 0) then
   b = b * (-1)
   neg = neg * (-1)
  end
  for i = 31, 0, -1 do
    local x = 2^i
    if (a >= x and b>=x) then
      r = r + 2^i
    end
   if (a >= x) then
        a = a - x
    end
   if (b >= x) then
        b = b - x
    end
  end
  return r * neg
end

function binary_or(a,b)
  local r = 0
local neg = 1
  if (a < 0) then
   a = a * (-1)
   neg = neg * (-1)
  end
  if (b < 0) then
   b = b * (-1)
   neg = neg * (-1)
  end
  for i = 31, 0, -1 do
    local x = 2^i
    if (a >= x or b>=x) then
      r = r + 2^i
    end
   if (a >= x) then
        a = a - x
    end
   if (b >= x) then
        b = b - x
    end
  end
  return r * neg
end
--------------
-- file access
--------------

inputfile = "../input.txt"
outputfile = "../output.txt"

blockwritesize = 128
wait_on_writeblock = true

function write_one(command)

   local file = nil
   while (file == nil) do
      file=io.open(inputfile,"a+")
   end

   io.output(file)

   io.write(command)
   io.write("\n")

   io.close(file)

end

function read_one(command)

   local read_line = ""

   command = string.sub(command, 1, #command - 1)
   
   --print("#command: "..#command)
   
   if (endpointer > 1000) then
      endpointer = endpointer - 1000
   else
      endpointer = 0
   end
   
   while read_line ~= command do
   
      local file = nil
      while (file == nil) do
         file=io.open(outputfile,"r")
      end
      
      file:seek("set", endpointer)
      
      local line = file:read()
      
      while (line ~= nil) do 
                 
         local buf_line = line
      
         local ix = #command + 1
         while ix < #buf_line do
            if (string.sub(buf_line,ix,ix) == "#") then
               break
            end
            ix = ix + 1
         end
      
         result = string.sub(buf_line,ix + 2,#buf_line - 1)
         buf_line = string.sub(buf_line,0,ix - 2)
         
         --print("########")
         --print(line)
         --print(command)
         --print(buf_line)
         --print("Result:"..result)
         
         if (buf_line == command) then
            read_line = buf_line
            break;
         end
            
         line = file:read()

      end
      
      new_endpointer = file:seek("end")
      io.close(file)
      
   end
   
   endpointer = new_endpointer
   
   return result
end

-------------------
-- connect commands
-------------------

function reg_get_block_connection(reg, index, size)
   command_nr = command_nr + 1
   if (index == null) then index = 0 end
   
   block = {}
   local readindex = 0
   local dataleft = size
   while (dataleft > 0) do
   
      local blocksize = math.min(dataleft, 128)
   
      command = "get # "..command_nr.." # "..process_id.." # ".."1".." # "..blocksize.." # "..(reg[1] + index).."&"
      write_one(command)
      values = read_one(command)
      
      blockraw = values:split("#")
      for i = 1, blocksize do
         block[readindex] = tonumber(blockraw[i])
         readindex = readindex + 1
      end
      
      dataleft = dataleft - blocksize
      index    = index + blocksize
      
   end  
  
   return block
end

function reg_get_connection(reg, index)
   block = reg_get_block_connection(reg, index, 1)
   return block[0]
end

function reg_set_block_connection(values, reg, index)
   if (index == null) then index = 0 end
   command_nr = command_nr + 1
   local length = (#values + 1)
   command = "set # "..command_nr.." # "..process_id.." # ".."1".." # "..math.min(blockwritesize, length).." # "..(reg[1] + index)
   local writecount = 0
   for i = 0, #values do
      value = conv_to_neg(values[i])
      command = command.." # "..value
      writecount = writecount + 1
      if (writecount == blockwritesize) then
         command = command.."&"
         write_one(command)
         if (wait_on_writeblock) then
            read_one(command)
         end
         writecount = 0
         index = index + blockwritesize
         command_nr = command_nr + 1
         length = length - blockwritesize
         command = "set # "..command_nr.." # "..process_id.." # ".."1".." # "..math.min(blockwritesize, length).." # "..(reg[1] + index)
      end
   end
   if (length > 0) then
      command = command.."&"
      write_one(command)
      if (wait_on_writeblock) then
         read_one(command)
      end
   end
end

function reg_set_connection(value, reg, index)
   values = {}
   values[0] = value
   reg_set_block_connection(values, reg, index)
end

-----------
-- commands
-----------

function reg_filter(reg, value)

   filter = 0
   for i = reg[3], reg[2] do
      filter = filter + 2^i;
   end

   value = conv_neg(value)
   value = binary_and(value,filter);
   value = value / (2 ^ reg[3]);

   return value
   
end

function reg_get(reg, index)
   value = reg_get_connection(reg, index)
   
   value = reg_filter(reg, value)
   
   return value
end

function reg_get_block(reg, index, size)
   
   block = reg_get_block_connection(reg, index, size)
   for i = 0, size - 1 do
      value = block[i]
   
      filter = 0
      for i = reg[3], reg[2] do
         filter = filter + 2^i;
      end
   
      value = conv_neg(value)
      value = binary_and(value,filter);
      value = value / (2 ^ reg[3]);
      
      block[i] = value
   end
   
   return block
end

function reg_set_block(block, reg, index)
   reg_set_block_connection(block, reg, index)
end


function reg_set(value, reg, index)
   if (index == null) then index = 0 end
   
   if (value < 100) then
      --print ("Address "..(reg[1] + index).."["..reg[2]..".."..reg[3].."] => "..value)
   else
      --print ("Address "..(reg[1] + index).."["..reg[2]..".."..reg[3].."] => 0x"..string.format("%X", value))
   end
   
   -- find out if parameter is the only one in this register
   local singlereg = true
   local fullname = reg[6]
   local sectionname = fullname:split(".")[1]
   local secttable = _G[sectionname]
   for name, register in pairs(secttable) do
      if (register[1] == reg[1]) then
         if (register[6] ~= reg[6]) then
            singlereg = false
            break
         end
      end
   end
   
   oldval = 0
   
   if (singlereg == false) then
   
      oldval = reg_get_connection(reg, index) 
      
      --print ("oldval= "..oldval.." at "..(reg[1]+index))
      
      filter = 0
      for i = 0, reg[3] - 1 do
         filter = filter + 2^i;
      end
      for i = reg[2] + 1, 31 do
         filter = filter + 2^i;
      end
      oldval = binary_and(oldval,filter);
      
      --print ("oldval filtered= "..oldval.." at "..(reg[1]+index).." with filter "..filter)
   
   end
   
   value = value * (2 ^ reg[3])
   value = binary_or(value, oldval);
   
   reg_set_connection(value, reg, index)
end


function compare_reg(target, reg, index)
   if (index == null) then index = 0 end
   value = reg_get(reg, index)
   if (value == target) then
      if (value < 100 and target < 100) then
         print (reg[6].." -> Address "..(reg[1] + index).."["..reg[2]..".."..reg[3].."] = "..value.." - OK")
      else
         print (reg[6].." -> Address "..(reg[1] + index).."["..reg[2]..".."..reg[3].."] = 0x"..string.format("%X", value).." - OK")
      end
      return true
   else
      testerrorcount = testerrorcount + 1
      if (value < 100 and target < 100) then
         print (reg[6].." -> Address "..(reg[1] + index).."["..reg[2]..".."..reg[3].."] = "..value.." | should be = "..target.." - ERROR")
      else
         print (reg[6].." -> Address "..(reg[1] + index).."["..reg[2]..".."..reg[3].."] = 0x"..string.format("%X", tonumber(value)).." | should be = 0x"..string.format("%X", tonumber(target)).." - ERROR")
      end
      return false;
   end
end

function reg_set_file(filename, reg, index, endian)
   if (index  == null) then index = 0 end
   if (endian == null) then endian = 0 end
   command_nr = command_nr + 1
   command = "fil # "..command_nr.." # "..process_id.." # "..endian.." # "..(reg[1] + index).." # "..filename
   command = command.."&"
   write_one(command)
   if (wait_on_writeblock) then
      read_one(command)
   end
end

function wait_ns(waittime)
   command_nr = command_nr + 1
   command = "wtn # "..command_nr.." # "..process_id.." # "..waittime.."&"
   write_one(command)
   read_one(command)
end

function brk()
   command_nr = command_nr + 1
   command = "brk&"
   write_one(command)
end

function sleep(n)  -- seconds
  local t0 = os.clock()
  while os.clock() - t0 <= n do end
end

----------
-- init
----------


seed = os.time() + os.clock() * 1000
math.randomseed(seed)
process_id = math.random(2147483647)
process_id = math.random(2147483647)
process_id = math.random(2147483647)
process_id = math.random(2147483647)
process_id = math.random(2147483647)

endpointer = 0

command_nr = 0

DUMMYREG = {0,31,0,1,0,"DUMMYREG"}




