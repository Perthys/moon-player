# MoonPlayer

MoonPlayer is an experimental Moon Animator save player
Due to its experimental state expect bugs

## Features

- Compiles MoonSave into compressed binary format
- Uses a frame buffer to avoid having the entire track loaded into memory

## Installation

```powershell
aftman install
rojo serve place.project.json
```

`place.project.json` syncs the package to `ReplicatedStorage.MoonPlayer`.

## Module Surface

```lua
local MoonPlayer = require(path.to.MoonPlayer)

MoonPlayer.Compiler
MoonPlayer.Player
```

The root module returns:

- `MoonPlayer.Compiler`
- `MoonPlayer.Player`

## Runtime Usage

`Player.new(track, instanceOverrides?)` expects a compiled MoonSave

Example:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoonPlayer = require(ReplicatedStorage.MoonPlayer)
local track = ReplicatedStorage.Animations.Wave

local player = MoonPlayer.Player.new(track, {
	["Workspace.Dummy"] = workspace.Dummy,
})

player:RegisterMarker("Footstep", function(target, isFinished)
	print("marker", target, isFinished)
end)

player:OnFinished(function()
	print("finished")
end)

player:Play()
```

Main methods:

- `Play()` rewinds the track, restores default values, and starts playback.
- `Stop()` stops playback and restores defaults.
- `Resume()` continues playback without rewinding.
- `RegisterMarker(name, callback)` runs `callback(targetInstance, isFinishedMarker)` when a named marker is reached.
- `OnFinished(callback)` runs the callback when the track ends.

## Compiling a Track

The compilation process should only be done once in studio before publishing to avoid having to store the entire MoonSave in game

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MoonPlayer = require(ReplicatedStorage.Packages.MoonPlayer)
local sourceSave = workspace.MoonSave

local compiledTrack = MoonPlayer.Compiler.Serializer.new(sourceSave):Build()
compiledTrack.Name = "Wave"
compiledTrack.Parent = ReplicatedStorage.Animations
```
