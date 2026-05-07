local Stream = {};

local BUFFER_SIZE = 65535;
function Stream.new(buf: buffer | string, allocationSize: number?)
	if typeof(buf) == "string" then
		buf = buffer.fromstring(buf);
	end

	local len = buf and buffer.len(buf) or 0;
	local buf = buf or buffer.create(allocationSize or BUFFER_SIZE);

	return setmetatable(
		{
			buf = buf,
			capacity = buffer.len(buf),
			read = 0,
			write = 0,
			size = len,
			alloc_size = allocationSize or BUFFER_SIZE,
			markers = {}
		},
		{ __index = Stream }
	);
end

function Stream:addBytesAndReallocate(bytes)
	local size = buffer.len(self.buf);
	local newBuf = buffer.create(size + bytes);

	buffer.copy(newBuf, 0, self.buf, 0, size);
	self.buf = newBuf;
	self.capacity = size + bytes;
end

function Stream:appendStream(other)	
	self:writebytes(other:tobuffer())
end

function Stream:writebytes(buf)
	local len = buffer.len(buf)

	if self.write + len > self.capacity - 1 then
		self:addBytesAndReallocate(len + 1);
	end

	buffer.copy(self.buf, self.write, buf, 0)
	
	if self.write == self.size then
		self.size  += len;
	end
	self.write += len;
end

function Stream:len()
	return self.size;
end

local sizet = { 1, 2, 4 };
for index, size in sizet do
	local bits = size * 8;

	local u = "u" .. bits;
	local i = "i" .. bits;

	local wun = "write" .. u;
	local win = "write" .. i;

	local wuf = buffer[wun];
	local wif = buffer[win];

	Stream[wun] = function(self, num)
		if self.write + size > self.capacity - 1 then
			self:addBytesAndReallocate(self.alloc_size);
		end

		wuf(self.buf, self.write, num);
		
		if self.write == self.size then
			self.size  += size;
		end
		self.write += size;
	end

	Stream[win] = function(self, num)
		if self.write + size > self.capacity - 1 then
			self:addBytesAndReallocate(self.alloc_size);
		end

		wif(self.buf, self.write, num);
		
		if self.write == self.size then
			self.size  += size;
		end
		self.write += size;
	end

	local run = "read" .. u;
	local rin = "read" .. i;

	local ruf = buffer[run];
	local rif = buffer[rin];

	Stream[run] = function(self, num)
		if self.read + size > self.size then
			error(string.format("attempt to read out of bounds"));	
		end

		local int = ruf(self.buf, self.read);
		self.read += size;

		return int;
	end

	Stream[rin] = function(self, num)
		if self.read + size > self.size then
			error(string.format("attempt to read out of bounds"));	
		end

		local int = ruf(self.buf, self.read);
		self.read += size;

		return int;
	end
end

function Stream:createMarker(name, size)
	local pos = self.write
	local buf = buffer.create(size)
	
	self:writebytes(buf)
	self.markers[name] = pos
end

function Stream:seekMarker(name)
	local pos = self.markers[name]
	
	if not pos then
		return warn("no pos found for marker", name)
	end
	
	self.write = pos
end

function Stream:clearMarkers()
	self.markers = {}
end

function Stream:resume()
	self.write = self.size
end

function Stream:writebool(bool)
	self:writeu8(bool and 0x01 or 0x00);
end

function Stream:readbool()
	return self:readu8() == 0x01;
end

function Stream:writeu64(num)
	if self.write + 8 > self.capacity - 1 then
		self:addBytesAndReallocate(self.alloc_size);
	end

	buffer.writestring(
		self.buf,
		self.write,
		string.pack("<I8", num),
		8
	);
	
	if self.write == self.size then
		self.size  += 8;
	end
	self.write += 8;
end

function Stream:readu64()
	if self.read + 8 > self.size then
		error(string.format("attempt to read out of bounds"));	
	end

	local str = buffer.readstring(self.buf, self.read, 8);
	self.read += 8;

	local num = string.unpack("<I8", str);
	return num;
end

function Stream:writei64(num)
	if self.write + 8 > self.capacity - 1 then
		self:addBytesAndReallocate(self.alloc_size);
	end

	buffer.writestring(
		self.buf,
		self.write,
		string.pack("<i8", num),
		8
	);
	
	if self.write == self.size then
		self.size  += 8;
	end
	self.write += 8;
end

function Stream:readi64()
	if self.read + 8 > self.size then
		error(string.format("attempt to read out of bounds"));	
	end

	local str = buffer.readstring(self.buf, self.read, 8);
	self.read += 8;

	local num = string.unpack("<i8", str);
	return num;
end

function Stream:readf32()
	if self.read + 4 > self.size then
		error(string.format("attempt to read out of bounds"));	
	end

	local int = buffer.readf32(self.buf, self.read);
	self.read += 4;

	return int;
end

function Stream:readf64()
	if self.read + 8 > self.size then
		error(string.format("attempt to read out of bounds"));	
	end

	local int = buffer.readf64(self.buf, self.read);
	self.read += 8;

	return int;
end

function Stream:writef32(f)
	if self.write + 4 > self.capacity - 1 then
		self:addBytesAndReallocate(self.alloc_size);
	end

	buffer.writef32(self.buf, self.write, f);
	
	if self.write == self.size then
		self.size  += 4;
	end
	self.write += 4;
end

function Stream:writef64(f)
	if self.write + 8 > self.capacity - 1 then
		self:addBytesAndReallocate(self.alloc_size);
	end

	buffer.writef64(self.buf, self.write, f);
	
	if self.write == self.size then
		self.size  += 8;
	end
	self.write += 8;
end

function Stream:writestring(str, sizeT)
	sizeT = sizeT or 32;

	local len = str:len();
	if self.write + (sizeT / 8) + len > self.capacity - 1 then
		self:addBytesAndReallocate(math.max(
			self.alloc_size, 
			(sizeT / 8) + len
		))
	end

	self["writeu" .. sizeT](self, len);
	buffer.writestring(self.buf, self.write, str, len);
	
	if self.write == self.size then
		self.size  += len;
	end
	self.write += len;
end

function Stream:readstring(sizeT)
	sizeT = sizeT or 32;

	local len = self["readu" .. sizeT](self);
	local str = buffer.readstring(self.buf, self.read, len);
	self.read += len;

	return str;
end

function Stream:writevector3(vec)
	self:writef32(vec.X);
	self:writef32(vec.Y);
	self:writef32(vec.Z);
end

function Stream:readvector3()
	return Vector3.new(
		self:readf32(),
		self:readf32(),
		self:readf32()
	)
end

function Stream:tobuffer()
	local buf = buffer.create(self.size);
	buffer.copy(buf, 0, self.buf, 0, self.size);

	return buf;
end

function Stream:tostring()
	return buffer.tostring(self:tobuffer())
end



return Stream