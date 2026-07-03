const FRAME_ADVANCE_HZ = Enum.StepFrequency.Hz15


const HttpService = game:GetService("HttpService")
const RunService = game:GetService("RunService")

const Interpolator = require("./Interpolator")
const ApplyProp = require("@self/ApplyProp")
const EaseFuncs = require("./EaseFuncs")
const Compiler = require("./Compiler")
const Flags = require("./Flags")

const SequentialReader = Compiler.SequentialReader
const Deserializer = Compiler.Deserializer

const PlayingTracks = {}
const IGNORED_DEFAULTS = { "Emit", "CFrame" }

const Player = {}


function Player.new(track, flags)
	const Data = HttpService:JSONDecode(track.Value)
	local playerFlags = Flags.Player.Default

	if flags then
		playerFlags += flags
	end

	const self = setmetatable({
		Data = Data,
		Deserializer = Deserializer.new(track, playerFlags),
		Reader = nil,

		OriginalFrameRate = Data.Information.FrameRate or 60,
		FrameRate = Data.Information.FrameRate or 60,
		Length = Data.Information.Length,

		CurrentFrame = -1,
		CurrentAdvance = 0,
		TimePosition = 0,

		FrameAdvance = {},
		FrameState = {},
		
		MarkerSequence = {},
		PartAttachments = {},

		MarkerCallbacks = {},
		FinishedCallbacks = {},
		FrameCallbacks = {},
		ClassNames = {},
		JointCFrames = {},

		Flags = playerFlags,
	}, { __index = Player })

	self:_handleBaseFlags()

	return self
end

function Player:Stop()
	PlayingTracks[self] = nil
	self:_restore()
end

function Player:Resume()
	PlayingTracks[self] = true
end

function Player:Play()
	self:_restore()

	self:_buildMarkerSequence()
	self:_advance()
	self:_setClassNames()
	
	PlayingTracks[self] = true
end

function Player:SetDuration(duration)
    const originalFrameRate = self.OriginalFrameRate
    const originalLength = self.Data.Information.Length
    const originalDuration = originalLength / originalFrameRate

    self.FrameRate = originalFrameRate * (originalDuration / duration)
	self.Flags.FrameAdvance = math.max(
		self.Flags.FrameAdvance,
		self.FrameRate / originalFrameRate
	)
end

function Player:ReplaceInstance(original, new)
	return self.Deserializer:overrideInstance(original, new)
end


function Player:OnMarkerReached(name, callback)
	self.MarkerCallbacks[name] = callback
end

function Player:OnFinished(callback)
	self.FinishedCallbacks[callback] = true
end

function Player:OnFrameReached(frame, callback)
	self.FrameCallbacks[tostring(frame)] = callback
end

function Player:_buildMarkerSequence()
	const sequence = {}

	for frameId in self.Deserializer.markers do
		table.insert(sequence, tonumber(frameId))
	end

	table.sort(sequence)
	self.MarkerSequence = sequence
end


function Player:_restore()
	self.Reader = SequentialReader.new(self.Deserializer)	

	self.PartAttachments = {}
	self.FrameState = {}
	self.FrameAdvance = {}
	self.MarkerSequence = {}
	self.ClassNames = {}
	self.JointCFrames = {}

	self.CurrentAdvance = 0
	self.CurrentFrame = -1
	self.TimePosition = 0
	
	const instanceOverride = self.Deserializer.targetOverrides
	const instances = self.Deserializer.targets
	
	for instanceId, props in self.Deserializer.defaults do
		const realInstance = instanceOverride[instanceId] 
			or instances[instanceId]
		
		if not realInstance then
			if self.Flags.StrictMode then
				return error(`failed to restore track to default instance "{instanceId}" is missing`)
			end

			if self.Flags.LogUnresolvedInstances then
				warn(`failed to resolve instance: "{instanceId}"`)
			end

			continue
		end 

		if realInstance:IsA("BasePart") then
			self.JointCFrames[instanceId] = realInstance.CFrame
		end

		for name, value in props do 
			if table.find(IGNORED_DEFAULTS, name) then
				continue
			end

			ApplyProp(realInstance, realInstance.ClassName, name, value, self)
		end
	end
end

function Player:_setClassNames()
	const classNames = {}

	const instanceOverride = self.Deserializer.targetOverrides
	const instances = self.Deserializer.targets

	for id, instance in instances do
		classNames[id] = instance.ClassName
	end

	for id, instance in instanceOverride do
		classNames[id] = instance.ClassName
	end

	self.ClassNames = classNames
end

function Player:_handleBaseFlags()
	const flags = self.Flags 

	if flags.Duration ~= -1 then
		self:SetDuration(flags.Duration)
	end
end

function Player:_checkApplyPropTransformer(instanceId, name, value)
	const serializerFlags = self.Data.Information.Flags
	if serializerFlags and serializerFlags.RelativeCFrameOffset == false then
		return value
	end

	if name == "CFrame" then
		const cframe = self.JointCFrames[instanceId]
		if not cframe then
			return value
		end 

		return cframe * value
	elseif name == "Position" then
		const cframe = self.JointCFrames[instanceId]
		if not cframe then
			return value
		end 

		return value + cframe.Position
	end 

	return value
end

function Player:_advance()
	const state = self.FrameState
	const advance = self.FrameAdvance 
	const reader = self.Reader
	
	while self.CurrentAdvance ~= self.CurrentFrame + self.Flags.FrameAdvance do
		const currentFrame = self.CurrentAdvance

		const newPoints = reader:requestFrame()
		if newPoints then
			for inst, props in newPoints do
				if not state[inst] then
					state[inst] = {}
				end

				for _, propData in props do
					for _, prop in propData.props do
						const entry = {
							duration = propData.duration,
							prop = prop
						}

						if prop.ease then
							entry.originalDuration = propData.duration	
						end

						state[inst][prop.name] = entry
					end
				end
			end	
		end

		const frameBuffer = {}
		
		for instanceId, props in state do 
			if table.find(self.Deserializer.unresolvedInstances, instanceId) then
				continue
			end 
			
			const instanceEntry = {}

			for name, valueData in props do
				const prop = valueData.prop
				const ease = prop.ease 
				const value = self:_checkApplyPropTransformer(instanceId, name, prop.value)

				if ease then
					const easeFunc = EaseFuncs.Get({
						Type = ease.type,
						Params = ease.params
					})

					const progress = (valueData.originalDuration - valueData.duration)
					const delta = easeFunc(progress / valueData.originalDuration)
					const target = self:_checkApplyPropTransformer(instanceId, name, ease.target)

					const interpolate = Interpolator.get(target)

					instanceEntry[name] = interpolate(value, target, delta)
				else 
					instanceEntry[name] = value
				end

				valueData.duration -= 1
				if valueData.duration == 0 then
					props[name] = nil
				end
			end

			frameBuffer[instanceId] = instanceEntry
		end

		advance[tostring(currentFrame)] = frameBuffer
		self.CurrentAdvance += 1
	end
end

const function emitMarkers(track, frameId)
	const markers = track.Deserializer.markers[frameId]
	if not markers then
		return 
	end

	const instanceOverride = track.Deserializer.targetOverrides
	const instances = track.Deserializer.targets

	for markerType, markers in markers do
		for instanceId, markerList in markers do
			const realInstance = instanceOverride[instanceId] 
				or instances[instanceId]
			
			for marker, kfMarkers in markerList do
				const callback = track.MarkerCallbacks[marker]
				
				if callback then
					task.spawn(
						callback,
						realInstance,
						markerType == "finish",
						kfMarkers
					)
				end
			end
		end
	end
end

const function update(delta)
	for track in PlayingTracks do
		const currentFrame = math.floor(track.TimePosition * track.FrameRate)
		const lastFrame = track.CurrentFrame

		delta = math.min(delta, 1 / track.OriginalFrameRate)

		if currentFrame > track.Length then
			for callback in track.FinishedCallbacks do
				task.defer(callback)
			end
			
			PlayingTracks[track] = nil
			continue
		end
		
		if lastFrame == currentFrame then
			track.TimePosition += delta
			continue
		end

		const frameId = tostring(currentFrame)
		const instanceOverride = track.Deserializer.targetOverrides
		const classNames = track.ClassNames
		const instances = track.Deserializer.targets
		
		for frameNum = lastFrame + 1, currentFrame do
			const currentFrameId = tostring(frameNum)
			const frame = track.FrameAdvance[currentFrameId]

			if not frame then
				continue
			end

			for instanceId, props in frame do
				const realInstance = instanceOverride[instanceId] 
					or instances[instanceId]

				if realInstance then
					const className = classNames[instanceId]

					for name, value in props do
						ApplyProp(
							realInstance, 
							className,
							name, 
							value, 
							track
						)
					end
				else
					warn("failed to play track, unknown instance", instanceId)
					PlayingTracks[track] = nil
				end
			end

			track.FrameAdvance[currentFrameId] = nil
		end 
	
		const frameCallback = track.FrameCallbacks[frameId]
		if frameCallback then
			task.defer(frameCallback)
		end
		
		while true do
			const marker = track.MarkerSequence[1]

			if typeof(marker) ~= "number" or currentFrame < marker then
				break
			end

			task.defer(emitMarkers, track, tostring(marker))
			table.remove(track.MarkerSequence, 1)
		end

		track.CurrentFrame = currentFrame
		track.TimePosition += delta
	end
end

const function updateAttachments()
	for track in PlayingTracks do
		for inst, attach in track.PartAttachments do
			inst.CFrame = attach.CFrame
		end
	end
end 

const function framePregen(delta)
	for track in PlayingTracks do
		if track.CurrentAdvance == track.CurrentFrame + track.Flags.FrameAdvance then
			continue
		end

		track:_advance()
	end
end

RunService.PreAnimation:Connect(update)
RunService:BindToRenderStep("UPDATE_MOON_ATTACHMENTS", Enum.RenderPriority.Camera.Value + 1, updateAttachments)
RunService:BindToSimulation(framePregen, FRAME_ADVANCE_HZ, Enum.RenderPriority.Last.Value)

return Player