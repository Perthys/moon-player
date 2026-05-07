-- stolen from moonlite


local function toPath(path: MoonAnimPath): string
	return table.concat(path.InstanceNames, ".")
end

local function _canon(s: string): string
	s = tostring(s or "")
	s = s:gsub("[\226\128\152\226\128\153]", "'")
	s = s:gsub("%s+", " ")
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	return s:lower()
end

local function _compact(s: string): string
	s = _canon(s)
	s = s:gsub("[^%w]+", "")
	return s
end

local function _findChildSmart(parent: Instance, childName: string): Instance?
	local direct = parent:FindFirstChild(childName)
	if direct then
		return direct
	end

	local wantCanon = _canon(childName)
	local wantCompact = _compact(childName)

	for _, c in ipairs(parent:GetChildren()) do
		if _canon(c.Name) == wantCanon then
			return c
		end
	end

	for _, c in ipairs(parent:GetChildren()) do
		if _compact(c.Name) == wantCompact then
			return c
		end
	end

	local deepExact = parent:FindFirstChild(childName, true)
	if deepExact then
		return deepExact
	end

	for _, d in ipairs(parent:GetDescendants()) do
		if _canon(d.Name) == wantCanon then
			return d
		end
	end

	for _, d in ipairs(parent:GetDescendants()) do
		if _compact(d.Name) == wantCompact then
			return d
		end
	end

	return nil
end

local function _getServiceSmart(name: string): Instance?
	local ok, svc = pcall(function()
		return game:GetService(name)
	end)
	if ok and typeof(svc) == "Instance" then
		return svc
	end
	return nil
end

local function resolveAnimPath(path: MoonAnimPath?, root: Instance?): Instance?
	if not path then
		return nil
	end

	local names = path.InstanceNames
	local types = path.InstanceTypes
	local current: Instance = root or game

	local ok, result = pcall(function(): Instance?
		local i = 2
		while i <= #names do
			local name = names[i]
			local expectedClass = types[i]
			local nextInst: Instance? = nil

			if current == game then
				nextInst = _getServiceSmart(name) or _findChildSmart(current, name)
			else
				if current:IsA("Workspace") and name == "CurrentCamera" then
					nextInst = (current :: Workspace).CurrentCamera
				else
					nextInst = _findChildSmart(current, name)
				end
			end

			if not nextInst then
				local combined = name
				local j = i + 1
				while j <= #names do
					combined ..= "." .. names[j]
					local cand = _findChildSmart(current, combined)
					if cand then
						nextInst = cand
						i = j
						expectedClass = types[i]
						break
					end
					j += 1
				end
			end

			if not nextInst then
				return nil
			end

			if expectedClass and nextInst.ClassName ~= expectedClass then
				return nil
			end

			current = nextInst :: Instance
			i += 1
		end

		return current
	end)

	if not ok then
		return nil
	end
	return result
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
			if p0 then addKey(p0.Name .. "." .. m.Name, info) end
			if p1 then addKey(p1.Name .. "." .. m.Name, info) end
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
		if jointsByHier[tree] then return jointsByHier[tree] end
		local c = canon(tree)
		if byCanon[c] then return byCanon[c] end

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


return {
	resolveJoints = resolveJoints,
	resolveAnimPath = resolveAnimPath
}