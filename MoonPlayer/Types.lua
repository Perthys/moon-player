const Flags = require("./Flags")

export type Serializer = {
	new: (
		MoonSave: StringValue,
		Flags: Flags.Flag?
	) -> Serializer,
	
	Build: (Serializer) -> StringValue,
}

export type Compiler = {
	Serializer: Serializer,

	Flags: Flags.SerializerFlags
}

export type AnimationPlayer = {
	new: (
		MoonSave: StringValue,
		Flags: Flags.Flag?
	) -> AnimationPlayer,
	
	Play: (AnimationPlayer) -> (),
	Stop: (AnimationPlayer) -> (),
	Resume: (AnimationPlayer) -> (),
	SetDuration: (AnimationPlayer, Duration: number) -> (),
	
	ReplaceInstance: (
		AnimationPlayer, 
		Original: Instance | string,
		New: Instance
	) -> (),

	OnFinished: (AnimationPlayer, Callback: () -> any) -> (),

	OnFrameReached: (
		AnimationPlayer, 
		Frame: number, 
		Callback: () -> any
	) -> (),

	OnMarkerReached: (
		AnimationPlayer, 
		MarkerName: string, 
		Callback: (
			Target: Instance, 
			IsFinished: boolean,
			KFMarkers: { [string]: string }
		) -> ()
	) -> ()
}

export type MoonPlayer = {
	Compiler: Compiler,
	Player: AnimationPlayer,
	Flags: Flags.Flags
}

return {}