#TypeDefs
const UniformDict     = Dict{Symbol, Any}
const SymAnyDict      = Dict{Symbol, Any}
const EmptyNamedTuple = NamedTuple{(), Tuple{}}
const Area            = SimpleRectangle
const RGBAf0          = RGBA{Float32}
const RGBf0           = RGB{Float32}
@enum CamKind pixel orthographic perspective

abstract type AbstractComponent end
abstract type Singleton <: AbstractComponent end

abstract type ComponentData end

struct Component{T <: ComponentData} <: AbstractComponent
	id   ::Int
	data ::Vector{T}
end
Base.eltype(::Component{T}) where { T<:ComponentData } = T

struct DataID{T <: ComponentData}
	id     ::Int
end
Base.eltype(::DataID{T}) where {T} = T
#Should I use DataFrames/Tables?
struct Entity #we will create a name component #maybe it's not so bad that these are not contiguous?
	id       ::Int
	data_ids ::Vector{DataID}
end


abstract type SystemKind end

struct System{Kind <: SystemKind, DT} #DT has the components datatypes 
	components
end


abstract type AbstractGlimpseMesh end

const INSTANCED_MESHES = Dict{Type, AbstractGlimpseMesh}()

struct BasicMesh{D, T, FD, FT} <: AbstractGlimpseMesh
    vertices ::Vector{Point{D, T}}
    faces    ::Vector{Face{FD, FT}}
    normals  ::Vector{Point{D, T}}
end

struct AttributeMesh{AT<:NamedTuple, BM <: BasicMesh} <: AbstractGlimpseMesh
    attributes ::AT
    basic      ::BM
end

mutable struct Canvas <: GLA.AbstractContext
    name          ::Symbol
    id            ::Int
    area          ::Area
    native_window ::GLFW.Window
    background    ::Colorant{Float32, 4}
    callbacks     ::Dict{Symbol, Any}
	fullscreenvao ::VertexArray
	function Canvas(name::Symbol, id::Int, area, nw, background, callback_dict)
		obj = new(name, id, area, nw, background, callback_dict)
		finalizer(free!, obj)
		return obj
	end
    # framebuffer::FrameBuffer # this will become postprocessing passes. Each pp has a
end

const RenderTarget     = Union{FrameBuffer, Canvas}
const RenderTargetDict = Dict{Symbol, RenderTarget}
const ProgramDict      = Dict{Symbol, Program}

mutable struct Screen
    name      ::Symbol
    id        ::Int
    area      ::Area
    canvas    ::Union{Canvas, Nothing}
    background::Colorant
    parent    ::Union{Screen, Nothing}
    children  ::Vector{Screen}
    hidden    ::Bool # if window is hidden. Will not render
    function Screen(name      ::Symbol,
                    area      ::Area,
                    canvas    ::Canvas,
                    background::Colorant,
                    parent    ::Union{Screen, Nothing},
                    children  ::Vector{Screen},
                    hidden    ::Bool)
        id = new_screen_id()
        canvas.id = id
        obj = new(name, id, area, canvas,background, parent, children, hidden)
        finalizer(free!, obj)
        return obj
    end
end

abstract type RenderPassKind end

mutable struct RenderPass{RenderPassKind, NT <: NamedTuple} <: Singleton
    programs::ProgramDict
    targets ::RenderTargetDict
    options ::NT
    function RenderPass{name}(programs::ProgramDict, fbs::RenderTargetDict, options::NT) where {name, NT <: NamedTuple}
        obj = new{name, NT}(programs, fbs, options)
        finalizer(free!, obj)
        return obj
    end
end

kind(::Type{RenderPass{Kind}}) where Kind = Kind
kind(::RenderPass{Kind}) where Kind = Kind

mutable struct SimData
	time  ::Float64
	dtime ::Float64
	frames::Int
end


mutable struct Diorama
    name       ::Symbol

    entities   ::Vector{Entity}
    components ::Vector{Component}
    singletons ::Vector{Singleton}
    systems    ::Vector{System}

    screen     ::Union{Screen, Nothing}
    loop       ::Union{Task, Nothing}
    reupload   ::Bool
    simdata    ::SimData
    function Diorama(name, entities, components,  singletons, systems, screen; interactive=false, kwargs...)
        dio = new(name, entities, components, singletons, systems, screen, nothing, true, SimData(time(),0.0, 0))
        makecurrentdio(dio)
        expose(dio; kwargs...)
        finalizer(free!, dio)
        return dio
    end
end
include("components.jl")
include("meshes.jl")
include("camera.jl")
include("canvas.jl")
include("screen.jl")
include("renderpass.jl")
include("diorama.jl")



