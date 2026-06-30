local DATAMODEL_TOKENS = {
	game = true,
	Game = true,
	DataModel = true,
}

local function splitPath(dotPath: string): { string }
	local segments = {}
	for segment in string.gmatch(dotPath, "[^.]+") do
		table.insert(segments, segment)
	end
	return segments
end

local function stripLeadingRoot(segments: { string }): { string }
	if segments[1] and DATAMODEL_TOKENS[segments[1]] then
		return { unpack(segments, 2) }
	end
	return segments
end

local function walkFrom(root: Instance, names: { string }, types: { string }, startIndex: number): Instance?
	if startIndex > #names then
		return root
	end

	local current: Instance = root
	local success = pcall(function()
		for i = startIndex, #names do
			local nextInst = (current :: any)[names[i]]

			assert(typeof(nextInst) == "Instance")
			assert(nextInst.ClassName == types[i])

			current = nextInst
		end
	end)

	if success then
		return current
	end

	local tbl = {}
	for i = startIndex, #names do
		table.insert(tbl, `{types[i]}[Name = "{names[i]}"]`)
	end

	local data
	success, data = pcall(function()
		return root:QueryDescendants(table.concat(tbl, " > "))[1]
	end)

	if success and typeof(data) == "Instance" then
		return data
	end

	return nil
end

local function matchOverride(names: { string }, overrides: { [string]: Instance }?): (Instance?, number?)
	if not overrides then
		return nil
	end

	local bestInstance: Instance? = nil
	local bestLen: number? = nil

	for key, instance in overrides do
		local segments = stripLeadingRoot(splitPath(key))
		local len = #segments

		if len > 0 and len <= #names and (not bestLen or len > bestLen) then
			local matches = true
			for j = 1, len do
				if segments[j] ~= names[j] then
					matches = false
					break
				end
			end

			if matches then
				bestInstance = instance
				bestLen = len
			end
		end
	end

	return bestInstance, bestLen
end

-- stolen from moonlite
local function fastResolvePath(path: MoonAnimPath, root)
	local tbl = {}

	for i = 2, #path.InstanceNames do
		local class = path.InstanceTypes[i]
		local name = path.InstanceNames[i]

		table.insert(tbl, `{class}[Name = "{name}"]`)
	end

	return root:QueryDescendants(table.concat(tbl, " > "))[1]
end

local function resolveAnimPath(path: MoonAnimPath?, root: Instance?): Instance?
	if not path then
		return nil
	end

	local numSteps = #path.InstanceNames
	local current: Instance = root or game

	local success = pcall(function()
		for i = 2, numSteps do
			local name = path.InstanceNames[i]
			local class = path.InstanceTypes[i]

			local nextInst = (current :: any)[name]
			assert(typeof(nextInst) == "Instance")
			assert(nextInst.ClassName == class)

			current = nextInst
		end
	end)

	if success then
		return current
	end

	local data
	success, data = pcall(fastResolvePath, path, game)

	if success and typeof(data) == "Instance" then
		return data
	end

	return nil
end

local function resolveJoints(target: Instance)
	local jointsByHier = {} :: { [string]: MoonJointInfo }
	local byCanon = {} :: { [string]: MoonJointInfo }

	local function canon(s: string): string
		s = tostring(s or "")
		s = s:gsub("[\226\128\152\226\128\153]", "'")
		s = s:gsub("%s+", " ")
		s = s:gsub("^%s+", ""):gsub("%s+$", "")
		return s:lower()
	end

	local function addKey(key: string, info: MoonJointInfo)
		jointsByHier[key] = info
		byCanon[canon(key)] = info
	end

	local list = {} :: { MoonJointInfo }

	for _, d: Instance in ipairs(target:GetDescendants()) do
		if d:IsA("Motor6D") then
			local j = d :: Motor6D
			local info: MoonJointInfo = { Name = j.Name, Joint = j, Children = {} }
			table.insert(list, info)
		elseif d:IsA("Bone") then
			local b = d :: Bone
			local info: MoonJointInfo = { Name = b.Name, Joint = b, Children = {} }
			table.insert(list, info)
		end
	end

	local jointToInfo = {} :: { [Instance]: MoonJointInfo }
	for _, info in ipairs(list) do
		jointToInfo[info.Joint] = info
	end

	for _, info in ipairs(list) do
		local joint = info.Joint
		if joint:IsA("Motor6D") then
			local p0 = (joint :: Motor6D).Part0
			if p0 then
				for _, other in ipairs(list) do
					local oj = other.Joint
					if oj:IsA("Motor6D") then
						local op1 = (oj :: Motor6D).Part1
						if op1 == p0 then
							other.Children[info.Name] = info
							info.Parent = other
							break
						end
					elseif oj:IsA("Bone") then
						if (oj :: Bone).Parent == p0 then
							other.Children[info.Name] = info
							info.Parent = other
							break
						end
					end
				end
			end
		elseif joint:IsA("Bone") then
			local parent = (joint :: Bone).Parent
			if parent then
				local parentInfo = jointToInfo[parent]
				if parentInfo then
					parentInfo.Children[info.Name] = info
					info.Parent = parentInfo
				end
			end
		end
	end

	for _, info in ipairs(list) do
		local j = info.Joint
		if j:IsA("Motor6D") then
			local m = j :: Motor6D
			local p0 = m.Part0
			local p1 = m.Part1

			if p0 then
				addKey(p0.Name .. "." .. m.Name, info)
			end

			if p1 then
				addKey(p1.Name .. "." .. m.Name, info)
			end

			addKey(m.Name, info)
			if p0 and p1 then
				addKey(p0.Name .. "." .. p1.Name, info)
				addKey(p0.Name .. "." .. m.Name .. "." .. p1.Name, info)
			end
		else
			local b = j :: Bone
			addKey(b.Name, info)
			local hier = b.Name
			local cur = b.Parent
			while cur and cur ~= target do
				hier = cur.Name .. "." .. hier
				cur = cur.Parent
			end
			addKey(hier, info)
		end
	end

	local function findSmart(tree: string): MoonJointInfo?
		if jointsByHier[tree] then
			return jointsByHier[tree]
		end

		local c = canon(tree)
		if byCanon[c] then
			return byCanon[c]
		end

		for k, v in pairs(jointsByHier) do
			if k:sub(-#tree) == tree or tree:sub(-#k) == k then
				return v
			end
		end

		for k, v in pairs(byCanon) do
			if k:sub(-#c) == c or c:sub(-#k) == k then
				return v
			end
		end

		return nil
	end

	return jointsByHier, findSmart
end

local function resolveAnimPathWithOverrides(path: MoonAnimPath?, overrides: { [string]: Instance }?): Instance?
	if not path then
		return nil
	end

	if overrides then
		local names = { unpack(path.InstanceNames, 2) }
		local types = { unpack(path.InstanceTypes, 2) }

		local overrideInstance, matchedLen = matchOverride(names, overrides)
		if overrideInstance and matchedLen then
			if matchedLen == #names then
				return overrideInstance
			end

			local resolved = walkFrom(overrideInstance, names, types, matchedLen + 1)
			if resolved then
				return resolved
			end
		end
	end

	return resolveAnimPath(path)
end

local function parseObjectQuery(query: string): ({ string }, { string })
	local names = {}
	local types = {}

	for class, name in string.gmatch(query, '([%w_]+)%[Name="(.-)"%]') do
		table.insert(types, class)
		table.insert(names, name)
	end

	return names, types
end

local function resolveObjectWithOverrides(query: string, overrides: { [string]: Instance }?): Instance?
	local names, types = parseObjectQuery(query)

	if #names > 0 then
		local overrideInstance, matchedLen = matchOverride(names, overrides)
		if overrideInstance and matchedLen then
			if matchedLen == #names then
				return overrideInstance
			end

			local resolved = walkFrom(overrideInstance, names, types, matchedLen + 1)
			if resolved then
				return resolved
			end
		end
	end

	local success, inst = pcall(function()
		return game:QueryDescendants(query)[1]
	end)

	if success and typeof(inst) == "Instance" then
		return inst
	end

	if #names > 0 then
		local tbl = {}
		for i = 1, #names do
			table.insert(tbl, `{types[i]}[Name = "{names[i]}"]`)
		end

		success, inst = pcall(function()
			return game:QueryDescendants(table.concat(tbl, " "))[1]
		end)

		if success and typeof(inst) == "Instance" then
			return inst
		end
	end

	return nil
end

return {
	resolveJoints = resolveJoints,
	resolveAnimPath = resolveAnimPath,
	resolveAnimPathWithOverrides = resolveAnimPathWithOverrides,
	resolveObjectWithOverrides = resolveObjectWithOverrides,
}
