local SpecialProps do
	const ModelInstance = Instance.new("Model")
	const ParticleEmitterInstance = Instance.new("ParticleEmitter")

	SpecialProps = {
		Camera = {
			Advanced = {
				AttachToPart = function(inst, value, player)
					player.PartAttachments[inst] = value
				end
			}
		},

		Motor6D = {
			Simple = {
				Transform = function(inst, value)
					inst.Transform = value * inst.C1
				end
			}
		},

		ParticleEmitter = {
			Simple = {
				Clear = ParticleEmitterInstance.Clear,
				Emit = ParticleEmitterInstance.Emit,
			}
		},

		Model = {
			Simple = {
				Scale = ModelInstance.ScaleTo,
				CFrame = ModelInstance.PivotTo,
			},
		},
	}
end

const function ApplyProp(inst, className, name, value, player)
	const className = className or inst.ClassName
	const specialClass = SpecialProps[className]

	if not specialClass then
		inst[name] = value
		return
	end

	if specialClass.Simple then
		const simpleHandler = specialClass.Simple[name]

		if simpleHandler then
			return simpleHandler(inst, value)
		end
	end

	if specialClass.Advanced then
		const advancedHandler = specialClass.Advanced[name]

		if advancedHandler then
			return advancedHandler(inst, value, player)
		end
	end

	inst[name] = value
end

return ApplyProp
