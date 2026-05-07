export type Deserializer = {
	new: (MoonSave: StringValue) -> Deserializer,
}

export type Serializer = {
	new: (MoonSave: StringValue) -> Serializer,
	
	Build: (Serializer) -> StringValue
}

export type Compiler = {
	Deserializer: Deserializer,
	Serializer: Serializer
}

export type AnimationPlayer = {
	new: (
		MoonSave: StringValue, 
		Overrides: { [string]: Instance }?
	) -> AnimationPlayer,
	
	Play: (AnimationPlayer) -> (),
	Stop: (AnimationPlayer) -> (),
	Resume: (AnimationPlayer) -> (),
	
	OnFinished: (AnimationPlayer, Callback: () -> any) -> (),
	
	ReplaceInstance: (
		AnimationPlayer, 
		Original: Instance | string,
		New: Instance
	) -> (),
	
	RegisterMarker: (
		AnimationPlayer, 
		MarkerName: string, 
		Callback: (target: Instance, isFinished: boolean) -> ()
	) -> ()
}

export type MoonPlayer = {
	Compiler: Compiler,	
	Player: AnimationPlayer
}

return {}