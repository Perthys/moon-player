const EncodingService = game:GetService("EncodingService")
const HttpService = game:GetService("HttpService")

const Resolver = require("./Resolver")
const Stream = require("./Stream")
const Enums = require("./Enums")

const PropertyType = Enums.PropertyType

const MARKER_TYPES = { "finish", "start" } -- do not reorder these


const Deserializer = {}

function Deserializer.new(save, flags)
	const data = HttpService:JSONDecode(save.Value)

	const overrides = flags.InstanceOverrides or {}
	const exclusions = flags.InstanceExclusions or {}

	const self = setmetatable({
		data = data,
		save = save,
		flags = data.Information.Flags,

		resolver = Resolver.new(overrides, exclusions),
		
		strings = {},
		values = {},
		objects = {},
		cframes = {},
		
		targets = {},
		targetOverrides = {},

		unresolvedInstances = {},
		
		defaults = {},

		instanceOverrides = overrides,
		playerFlags = flags,
		
		markers = {
			finish = {},
			start = {}
		}
	}, { __index = Deserializer })
	
	self:deserializeDictionaries()
	self:deserializeSequence()
	self:deserializeMarkers()
	self:deserializeHierarchy()
	self:deserializeDefaults()
	
	self.frameBuffer = self:decompressBufferFromParts(save.frames)
	
	return self 
end

function Deserializer:overrideInstance(original, new)
	for id, instance in self.targets do
		if instance == original or instance:GetFullName() == original then
			self.targetOverrides[id] = new
		end
	end
end

function Deserializer:decompressBuffer(buf)
	const decodedBuffer = EncodingService:Base64Decode(
		buffer.fromstring(buf.Value)
	)
	
	return Stream.new(
		EncodingService:DecompressBuffer(
			decodedBuffer, 
			Enum.CompressionAlgorithm.Zstd
		)
	)
end

function Deserializer:decompressBufferFromParts(holder)
	const parts = holder:GetChildren()

	const buffers = {}

	for i = 1, #parts do
		const part = holder:FindFirstChild(tostring(i))
		assert(part, `frame buffer missing part: {i}`)
		
		table.insert(buffers, buffer.fromstring(part.Value))
	end

	local totalSize = 0
	for _, buf in buffers do
		totalSize += buffer.len(buf)
	end

	const out = buffer.create(totalSize)
	local offset = 0

	for _, buf in buffers do
		const chunkSize = buffer.len(buf)

		buffer.copy(out, offset, buf, 0, chunkSize)
		offset += chunkSize
	end

	return Stream.new(
		EncodingService:DecompressBuffer(
			EncodingService:Base64Decode(out), 
			Enum.CompressionAlgorithm.Zstd
		)
	)
end

function Deserializer:deserializeGenericValue(stream, valueType)
	const valueType = valueType or stream:readu8()

	if valueType == PropertyType.Bool then
		return stream:readbool()
	elseif valueType == PropertyType.Number then
		return stream:readf64()
	elseif valueType == PropertyType.Color3 then
		return Color3.new(
			stream:readf32(),
			stream:readf32(),
			stream:readf32()
		)
	elseif valueType == PropertyType.Vector3 then
		return stream:readvector3()	
	elseif valueType == PropertyType.Nil then
		return nil
	else 
		warn("unknown value type", valueType)
	end
end

function Deserializer:deserializeValue(stream)
	const valueType = stream:readu8()

	if valueType == PropertyType.CFrame then
		const serializeMethod = self.flags.CFrameSerializeMethod

		if serializeMethod == "Attributes" then
			const cframeId = stream:readu32()
			
			return self.cframes[math.floor(cframeId / 1000)]:GetAttribute(tostring(cframeId)), cframeId
		elseif serializeMethod == "Bytes" then
			return stream:readCFrame(self.flags.CFramePosSizeT, self.flags.CFrameRotSizeT)
		end
	elseif valueType == PropertyType.String then
		return self.strings[stream:readu16()]
	elseif valueType == PropertyType.ObjectValue then
		return self.objects[stream:readu16()]
	elseif valueType == PropertyType.Value then
		return self.values[stream:readu16()]
	elseif valueType == PropertyType.ColorSequence then
		const keypoints = {}

		for _ = 1, stream:readu8() do
			const time = stream:readf16()
			const color = Color3.new(
				stream:readf32(), 
				stream:readf32(), 
				stream:readf32()
			)

			table.insert(keypoints, ColorSequenceKeypoint.new(time, color))
		end

		if #keypoints == 1 then
			return ColorSequence.new(keypoints[1].Value)
		else
			return ColorSequence.new(keypoints)
		end
	elseif valueType == PropertyType.NumberSequence then
		const keypoints = {}

		for _ = 1, stream:readu8() do
			table.insert(keypoints, NumberSequenceKeypoint.new(
				stream:readf32(),
				stream:readf32(),
				stream:readf32()
			))
		end

		if #keypoints == 1 then
			return NumberSequence.new(keypoints[1].Value)
		else 
			return NumberSequence.new(keypoints)
		end
	end

	return self:deserializeGenericValue(stream, valueType)
end


function Deserializer:deserializeDictionaries()
	const strings = {}
	const values = {}
	const objects = {}
	const cframes = {}
	
	const stream = self:decompressBuffer(self.save.dict)


	for _, child in self.save.cframes:GetChildren() do
		cframes[tonumber(child.Name)] = child
	end
	
	for _ = 1, stream:readu16() do
		const id = stream:readu16()
		
		strings[id] = stream:readstring(16)
	end
	
	for _ = 1, stream:readu16() do
		const id = stream:readu16()
		const value = self:deserializeGenericValue(stream)
		
		values[id] = value
	end
	
	for _ = 1, stream:readu16() do
		const id = stream:readu16()
		const path = { 
			InstanceNames = {},
			InstanceTypes = {}
		}
		
		for _ = 1, stream:readu8() do
			table.insert(path.InstanceNames, 1, stream:readstring(8))
			table.insert(path.InstanceTypes, 1, stream:readstring(8))
		end

		print(path)
		const inst = self.resolver:resolveInstance(path)
		if not inst then
			warn("fail to resolve object", table.concat(path.InstanceNames, "."))
			continue
		end
		
		objects[id] = inst
	end
	
	self.objects = objects
	self.cframes = cframes
	self.strings = strings
	self.values = values
end

function Deserializer:deserializeSequence()
	const stream = self:decompressBuffer(self.save.sequence)
	
	const sequence = {}
	for _ = 1, stream:readu16() do
		table.insert(sequence, stream:readu16())
	end
	
	self.sequence = sequence
end

function Deserializer:deserializeDefaults()
	const stream = self:decompressBuffer(self.save.defaults)
	const defaults = {}
	
	for _ = 1, stream:readu16() do
		const instanceId = stream:readu16()
		const props = {}
		
		for _=  1, stream:readu8() do
			const name = self.strings[stream:readu16()]
			const value = self:deserializeValue(stream)
			
			props[name] = value
		end
		
		defaults[tostring(instanceId)] = props
	end
	
	self.defaults = defaults
end

function Deserializer:deserializeMarkers()
	const stream = self:decompressBuffer(self.save.markers)

	const markers = {}
	for _, markerType in MARKER_TYPES do
		for _ = 1, stream:readu16() do
			const frameId = stream:readu16()
			local frame = markers[tostring(frameId)]

			if not frame then
				frame = {}
				markers[tostring(frameId)] = frame
			end

			local markerData = frame[markerType]
			if not markerData then
				markerData = {}
				frame[markerType] = markerData
			end

			for _ =  1, stream:readu16() do
				const id = stream:readu16()
				const data = {}

				for _ = 1, stream:readu16() do
					const name = stream:readstring(8)
					const kfMarkers = {}

					for _ = 1, stream:readu8() do
						const kfMarkerName = stream:readstring(8)	
						const kfMarkerValue = stream:readstring(16)

						kfMarkers[kfMarkerName] = kfMarkerValue
					end

					data[name] = kfMarkers
				end

				markerData[tostring(id)] = data
			end
		end		
	end

	self.markers = markers
end

function Deserializer:throwResolverError(path, identifier)
	if self.playerFlags.StrictMode then
		error(`failed to resolve "{path}"`)
	end 

	if self.playerFlags.LogUnresolvedInstances then
		warn(`failed to resolve "{path}"`)
	end 

	table.insert(self.unresolvedInstances, identifier)
end 

function Deserializer:deserializeHierarchy()
	const stream = self:decompressBuffer(self.save.hierarchy)
	
	const targets = {}
	for _, item in self.data.Items do
		const concatPath = table.concat(item.Path.InstanceNames, ".")
		local overridenInstance = self.instanceOverrides[concatPath]
		const identifier = tostring(item.Identifier)
		
		if not overridenInstance then
			overridenInstance = self.resolver:resolveInstance(item.Path)
		end

		if not overridenInstance then
			self:throwResolverError(concatPath, identifier)
		end
		
		targets[identifier] = overridenInstance
	end
	
	for _ = 1, stream:readu16() do
		const rootId = stream:readu16()
		const root = targets[tostring(rootId)]

		const jointCount = stream:readu16()
		if jointCount > 0 then 
			local joints
			if root then
				joints = self.resolver:resolveJoints(root)
			end
			
			for _ = 1, jointCount do
				const jointId = stream:readu16()
				const hier = stream:readstring(16)
				const jointIdentifier = tostring(jointId)

				if not root then
					self:throwResolverError(hier, jointIdentifier)
					continue
				end
		
				const joint = joints[hier]
				if joint then
					targets[jointIdentifier] = joint
				else 
					self:throwResolverError(hier, jointIdentifier)
				end
			end
		end
	end
	
	self.targets = targets
end

return Deserializer
