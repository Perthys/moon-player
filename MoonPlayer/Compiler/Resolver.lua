local __index do
	xpcall(function(...)
		return game.MoonPlayer
	end, function(...)
		__index = debug.info(2, "f")
	end)
end

local function mergePath(path, start, finish)
	return table.concat(path.InstanceNames, ".", start, finish)
end

local function fastResolvePath(path, root)
	local tbl = {}

	for i = 2, #path.InstanceNames do
		local class = path.InstanceTypes[i]
		local name = path.InstanceNames[i]

		table.insert(tbl, `{class}[Name = "{name}"]`)
	end

	return root:QueryDescendants(table.concat(tbl, " > "))[1]
end


local Resolver = {}

function Resolver.new(overrides, excluded)
	local self = {
		cache = {},
		internalCache = {},
		excluded = excluded,
	}

	for name, inst in overrides do
		self.cache[name] = inst
		self.internalCache[name] = inst
	end 

	return setmetatable(self, {
		__index = Resolver
	})
end

function Resolver:resolveJoints(hier)
	local joints = {}

	for _, inst in hier:QueryDescendants("Motor6D[Active = true]") do
		local part1 = inst.Part1 
		local name = part1 and part1.Name

		if not name then
			continue
		end 

		joints[name] = {
			inst = inst,
			children = {}
		}
	end

	for name, data in joints do
		local joint = data.inst

		local part0 = joint.part0
		if not part0 then
			continue
		end 

		local data0 = joints[part0.Name]
		if not data0 then
			continue
		end 

		data0.children[name] = data
	end

	for _, inst in hier:QueryDescendants("Bone") do
		joints[inst.Name] = {
			inst = inst,
			children = {}
		}
	end

	return function(hier)
		local parts = string.split(hier, ".")

		local name = table.remove(parts, 1)
		local data = rawget(joints, name)

		while data and #parts > 0 do
			data = data.children[table.remove(parts, 1)]
		end

		return data and data.inst
	end
end 

function Resolver:resolveInstance(path, root)
	root = root or game

	if tostring(path.InstanceNames[1]):lower() == "game" then
		table.remove(path.InstanceNames, 1)
		table.remove(path.InstanceTypes, 1)
	end 

	local key = mergePath(path, 1, #path.InstanceNames)
	local cachedInstance = self.cache[key]

	if self.excluded[key] then
		return 
	end 

	if cachedInstance then
		return cachedInstance
	end

	local names = path.InstanceNames
	local types = path.InstanceTypes
	
	local suffixTypes = { types[#names] }
	local suffixNames = { names[#names] }

	local parentInst = root
	local startIdx = 1

	for i = #names - 1, 1, -1 do
		local mergedPath = mergePath(path, 1, i)
		local cachedInst = self.internalCache[mergedPath]

		if cachedInst then
			parentInst = cachedInst
			startIdx = i + 1
			break
		end

		table.insert(suffixTypes, 1, types[i])
		table.insert(suffixNames, 1, names[i])
	end

	local outputInst
	local suffixCount = #suffixNames

	for i = 1, suffixCount do
		local name = suffixNames[i]
		local type = suffixTypes[i]
		
		local success, inst = pcall(__index, parentInst, name)
		if not success or typeof(inst) ~= "Instance" or inst.ClassName ~= type then
			break
		end

		local instKey = mergePath(path, 1, startIdx + i - 1)

		self.internalCache[instKey] = inst
		parentInst = inst
		
		if i == suffixCount then
			outputInst = inst
		end
	end

	if not outputInst then
		local success, data = pcall(fastResolvePath, path, root)

		if success and typeof(data) == "Instance" then
			outputInst = data
		end
	end

	if outputInst then
		self.cache[key] = outputInst
	end

	return outputInst
end

return Resolver