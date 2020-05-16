# __precompile__(true)
module Glimpse
using Reexport
@reexport using ColorTypes

@reexport using Overseer
@reexport using GeometryTypes
using GeometryTypes.StaticArrays
using Overseer: update

import AbstractPlotting # I'd like to get away from this
const AP = AbstractPlotting

using ModernGL
using Quaternions
Base.length(::Type{<:RGBA}) = 4

using GLAbstraction
const GLA = GLAbstraction

using LinearAlgebra
using GLFW
using Observables
using Parameters

using CImGui
using CImGui.GLFWBackend
using CImGui.OpenGLBackend
using ThreadPools
const Gui = CImGui

using TimerOutputs
const to = TimerOutput()


include("extensions.jl")
include("types.jl")
include("entities.jl")
include("maths/matrices.jl")
include("maths/vecmath.jl")
include("callbacks.jl")
include("shader.jl")
include("geometries.jl")
include("marching_cubes.jl")

export RGBAf0

#package exports, types & enums
export Diorama
export expose, center_camera!
# For now only one context allowed, could change later I guess
const GLFW_context = Ref{GLFW.Window}()

#package exports, default geometries
end # module
