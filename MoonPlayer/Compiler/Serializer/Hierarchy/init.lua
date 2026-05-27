local Resolver = require("../Resolver")
local StaticProps = require("../../StaticProps")
local EQ = require("@self/EQ")

local CONSTANT_INTERPS = {
	["Instance"] = true,
	["boolean"] = true,
	["string"] = true,
	["nil"] = true,
}

local VALUE_HANDLERS = {
	EnumType = function(inst, baseValue)
		return Enum[inst.Value][baseValue]
	end,

	Vector2 = function(inst, baseValue)
		return Vector2.new(baseValue.X, baseValue.Y)
	end,

	ColorSequence = function(inst, baseValue)
		return ColorSequence.new(baseValue)
	end,

	NumberSequence = function(inst, baseValue)
		return NumberSequence.new(baseValue)
	end,

	NumberRange = function(inst, baseValue)
		return NumberRange.new(baseValue)
	end
}

local function readValue(value)
	if not value:IsA("ValueBase") then
		return value:GetAttribute("Value")
	end

	local baseValue = value.Value
	for name, handler in VALUE_HANDLERS do
		local inst = value:FindFirstChild(name)

		if inst then
			return handler(inst, baseValue)
		end
	end

	return baseValue
end

local function optimizeKeyframes(frames, isStatic)
	local optimized = {}

	local idx = 1
	while idx <= #frames do
		local currentFrame = frames[idx]

		while idx <= #frames do
			local nextFrame = frames[idx + 1]
			if not nextFrame then
				break 
			end 

			local diff = nextFrame.startTime - currentFrame.startTime
			local isValueSame = EQ(nextFrame.value, currentFrame.value)

			if diff < 1 or not isValueSame or currentFrame.eases then
				break
			end 

			if nextFrame.eases then
				currentFrame.count += diff - 1
				break
			end 
			currentFrame.count += diff
			idx += 1
		end 

		table.insert(optimized, currentFrame)
		idx += 1
	end 
	
	return optimized
end

local function parseKeyframes(keyframesInst, instance, disableOptimization)
	local packs = keyframesInst:QueryDescendants(">Folder")

	local packInstances = {}
	local keyframes = {}
	
	local isStatic = StaticProps[instance.ClassName]
		and StaticProps[instance.ClassName][keyframesInst.Name]

	for _, inst in packs do
		local packId = tonumber(inst.Name)
		packInstances[packId] = inst 

		local values = assert(
			inst:FindFirstChild("Values"), 
			"keyframe pack has no values"
		)

		local eases = inst:FindFirstChild("Eases")
		local valueModifier 
		
		for name, handler in VALUE_HANDLERS do
			if values:FindFirstChild(name) then
				valueModifier = handler
			end
		end

		for _, keyframe in values:GetChildren() do
			local frameIdx =  tonumber(keyframe.Name)
			if not frameIdx then
				continue
			end

			local easeData

			if eases then 
				local ease = eases:FindFirstChild(keyframe.Name)

				if ease then
					local easeType = ease:FindFirstChild("Type")
					local easeParams = ease:FindFirstChild("Params")
					
					local params = {}

					if easeParams then
						for _, child in easeParams:GetChildren() do
							params[child.Name] = readValue(child)
						end
					end

					easeData = {
						type = easeType.Value,
						params = params
					}
				end
			end 

			local value = readValue(keyframe)
			
			if valueModifier then
				value = valueModifier(keyframe, value)
			end

			table.insert(keyframes, {
				pack = packId,
				idx = frameIdx,
				startFrame = frameIdx + packId,

				static = isStatic or CONSTANT_INTERPS[typeof(value)],
				eases = easeData,
				value = value,
				count = 1
			})
		end 
	end
	
	table.sort(keyframes, function(a, b)
		return a.pack + a.idx < b.pack + b.idx
	end)

	local frames = {}

	while true do
		local currentFrame = table.remove(keyframes, 1)
		if not currentFrame then
			break
		end

		local nextFrame = keyframes[1]
		if nextFrame then
			local diff = nextFrame.startFrame - currentFrame.startFrame
			local isValueSame = EQ(nextFrame.value, currentFrame.value)

			if not currentFrame.static then
				if diff >= 1 and currentFrame.eases and not isValueSame then
					currentFrame.eases.target = nextFrame.value
					currentFrame.count += diff - 1

				elseif diff > 1 and not currentFrame.eases and not isValueSame then
					currentFrame.eases = {
						target = nextFrame.value,
						type = "Linear",
						params = {
							Direction = "In"
						}
					}

					currentFrame.count += diff - 1
				end
			elseif isValueSame then
				table.remove(keyframes, 1)
			end
		end

		if currentFrame.eases and (not currentFrame.eases.target or currentFrame.static) then
			currentFrame.eases = nil
		end

		table.insert(frames, {
			startTime = currentFrame.startFrame,
			value = currentFrame.value,
			static = isStatic,
			count = currentFrame.count,
			ease = currentFrame.eases
		})
	end

	if disableOptimization then
		return frames 
	end 

	return optimizeKeyframes(frames)
end

local function insertMarker(markers, frame, identifier, name, kfMarkers)
	local markerData = markers[frame]
	if not markerData then
		markerData = {}
		markers[frame] = markerData
	end

	if not markerData[identifier] then
		markerData[identifier] = {
			[name] = kfMarkers
		}
	else 
		markerData[identifier] = kfMarkers
	end
end

local function parseKFMarkers(track)
	local kf = track:FindFirstChild("KFMarkers")
	local markers = {}
	
	if kf then
		for _, val in kf:QueryDescendants("StringValue > StringValue#Val") do
			local name = val.Parent.Value
			local val = val.Value 
			
			markers[name] = val
		end
	end

	return markers
end

local function ParseHierarchy(data, save, disableOptimization)
	local frameBuffer = {}
	local defaults = {}
	local tree = {}
	
	local markers = {
		start = {},
		finish = {}
	}
	
	for idx, item in data.Items do
		local identifier = item.Identifier
		local itemData = {
			Identifier = identifier
		}
		
		local frame = save:FindFirstChild(idx)
		
		local rig = frame:FindFirstChild("Rig")
		local markerTrack = frame:FindFirstChild("MarkerTrack")

		local realInstance = Resolver.resolveAnimPath(item.Path)
		if not realInstance then
			return error("failed to resolve: " .. table.concat(item.Path.InstanceNames, "."))
		end

		if rig and item.Path.ItemType == "Rig" then
			local jointsHier, findJointSmart = Resolver.resolveJoints(realInstance)
			
			local joints = rig:QueryDescendants(">#_joint")
			local jointData = {}
		
			for _, joint in joints do
				local jointId = joint:GetAttribute("Identifier")
				
				local hier = joint:FindFirstChild("_hier").Value
				local default = joint:FindFirstChild("default")
				local keyframes = joint:FindFirstChild("_keyframes")

				if default then
					default = readValue(default)
					
					defaults[tostring(jointId)] = {
						Transform = default
					}
				end
				
				if keyframes then
					local joint = jointsHier[hier] or (findJointSmart and findJointSmart(hier)) or nil
					if not joint or not joint.Joint then
						return error(`failed to resolve: {hier}`)
					end
					
					local isMotor6D = joint.Joint:IsA("Motor6D")
					for _, keyframe in parseKeyframes(keyframes, joint.Joint, disableOptimization) do
						local value = keyframe.value
						local frameData = frameBuffer[tostring(keyframe.startTime)]
						
						if not frameData then
							frameData = {}
							frameBuffer[tostring(keyframe.startTime)] = frameData
						end
						
						if isMotor6D then
							value = value:Inverse() * default

							if keyframe.ease then
								keyframe.ease.target = keyframe.ease.target:Inverse() * default
							end
						end
						
						frameData[tostring(jointId)] = {
							{
								props = {
									Transform = {
										value = value,
										ease = keyframe.ease,
									}
								},
								
								propCount = 1,
								count = keyframe.count	
							}
						}
					end
				end
				
				jointData[tostring(jointId)] = {
					hier = hier,
					default = default
				}
			end
			
			itemData.JointCount = #joints
			itemData.Joints = jointData
		else 
			for _, child in frame:QueryDescendants(">Folder:not(#MarkerTrack)") do
				local default = child:FindFirstChild("default")
				if default then
					local instDefaults = defaults[tostring(identifier)]
					if not instDefaults then
						instDefaults = {}
						defaults[tostring(identifier)] = instDefaults
					end
					
					instDefaults[child.Name] = readValue(default)
				end

				for _, keyframe in parseKeyframes(child, realInstance, disableOptimization) do
					local frameData = frameBuffer[tostring(keyframe.startTime)]
					if not frameData then
						frameData = {}
						frameBuffer[tostring(keyframe.startTime)] = frameData
					end
					
					local existingFrameData = frameData[tostring(identifier)]
					if not existingFrameData then
						existingFrameData = {}
						frameData[tostring(identifier)] = existingFrameData
					end
					
					local prop = {
						props = {
							[child.Name] = {
								value = keyframe.value,
								ease = keyframe.ease,
							}
						},

						propCount = 1,
						count = keyframe.count	
					}
					
					table.insert(existingFrameData, prop)
				end
				
			end
		end
		
		if markerTrack then
			for _, track in markerTrack:GetChildren() do
				local startFrame = assert(tonumber(track.Name))
				local width = assert(track:FindFirstChild("width")).Value
				local name = assert(track:FindFirstChild("name")).Value
				local kfMarkers = parseKFMarkers(track)

				insertMarker(markers.start, startFrame, identifier, name, kfMarkers)
				
				if width > 0 then
					local finishFrame = math.min(startFrame + width, data.Information.Length)

					insertMarker(markers.finish, finishFrame, identifier, name, kfMarkers)
				end
			end
		end
		
		tree[tostring(identifier)] = itemData
	end
	
	return {
		markers = markers,
		defaults = defaults,
		frameBuffer = frameBuffer,
		tree = tree
	}
end

return ParseHierarchy
