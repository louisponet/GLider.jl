import GLAbstraction: Depth, DepthStencil, DepthFormat, FrameBuffer, AbstractContext
import GLAbstraction: bind, swapbuffers, clear!, free!, draw, exists_context, clear_context!, set_context!, GLOBAL_CONTEXT
import GLFW: standard_window_hints, SAMPLES, DEPTH_BITS, ALPHA_BITS, RED_BITS, GREEN_BITS, BLUE_BITS, STENCIL_BITS, AUX_BUFFERS, GetWindowSize

struct CanvasContext <: GLA.AbstractContext
	id::Int
end

mutable struct Canvas <: Singleton
    name          ::Symbol
    id            ::Int
    area          ::Area
    native_window ::GLFW.Window
    background    ::Colorant{Float32, 4}
    callbacks     ::Dict{Symbol, Any}
	context       ::CanvasContext
	function Canvas(name::Symbol, id::Int, area, nw, background, callback_dict)
		obj = new(name, id, area, nw, background, callback_dict, CanvasContext(id))
		finalizer(free!, obj)
		return obj
	end
    # framebuffer::FrameBuffer # this will become postprocessing passes. Each pp has a
end


const canvas_id_counter = Base.RefValue(0)
new_canvas_id() = (canvas_id_counter[] = mod1(canvas_id_counter[] + 1, 255); canvas_id_counter[])[]

Base.size(area::Area) = (area.w, area.h)

#TODO Framebuffer context
#TODO canvas should be able to be a drawing target too
#
"""
Standard window hints for creating a plain context without any multisampling
or extra buffers beside the color buffer
"""
function default_window_hints()
	[
		(SAMPLES,      0),
		(DEPTH_BITS,   32),

		(ALPHA_BITS,   8),
		(RED_BITS,     8),
		(GREEN_BITS,   8),
		(BLUE_BITS,    8),

		(STENCIL_BITS, 0),
		(AUX_BUFFERS,  0)
	]
end

function canvas_fbo(area::Area, depthformat::Type{<:DepthFormat} = Depth{Float32}, color = RGBA(0.0f0,0.0f0,0.0f0,1.0f0))
    fbo = FrameBuffer((area.w, area.h), (RGBA{N0f8}, depthformat))
    clear!(fbo, color)
    return fbo
end

standard_screen_resolution() =  GLFW.GetPrimaryMonitor() |> GLFW.GetMonitorPhysicalSize |> values .|> x -> div(x, 1)

function Canvas(name=:Glimpse; kwargs...)
	id = new_canvas_id() 
    defaults = mergepop!(canvas_defaults(), kwargs)

    window_hints = default_window_hints()
    context_hints = GLFW.standard_context_hints(defaults[:major], defaults[:minor])

    area = defaults[:area]
    nw = GLFW.Window(name         = string(name),
                     resolution   = (area.w, area.h),
                     debugging    = defaults[:debugging],
                     major        = defaults[:major],
                     minor        = defaults[:minor],
                     windowhints  = window_hints,
                     contexthints = context_hints,
                     visible      = defaults[:visible],
                     focus        = defaults[:focus],
                     fullscreen   = defaults[:fullscreen],
                     monitor      = defaults[:monitor])
    GLFW.SwapInterval(0) # deactivating vsync seems to make everything quite a bit smoother

    background = defaults[:background]
    if typeof(background) <: RGBA
        glClearColor(background.r, background.g, background.b, background.alpha)
    elseif typeof(background) <: RGB
        glClearColor(background.r, background.g, background.b, GLfloat(1))
        background = RGBA(background)
    end
    glClear(GL_COLOR_BUFFER_BIT)

    callbacks = defaults[:callbacks]
    callback_dict = register_callbacks(nw, callbacks)

	c = Canvas(name, id, area, nw, background, callback_dict)
	if defaults[:visible]
	    make_current(c)
    end
    return c
end

function make_current(c::Canvas)
	# if GLFW.GetCurrentContext() != c.native_window
	# end
	GLFW.SetWindowShouldClose(c.native_window, false)
	GLFW.ShowWindow(c.native_window)
    GLFW.MakeContextCurrent(c.native_window)
    set_context!(c.context)
end

function swapbuffers(c::Canvas)
    if c.native_window.handle == C_NULL
        warn("Native Window handle of canvas $(c.name) == C_NULL!")
        return
    end
    GLFW.SwapBuffers(c.native_window)
    return
end

function isopen(canvas::Canvas)
    canvas.native_window.handle == C_NULL && return false
    GLFW.GetWindowAttrib(canvas.native_window, GLFW.VISIBLE) == 1
end

#Should this clear the context?
function close(c::Canvas)
	GLFW.HideWindow(c.native_window)
	should_close!(c, false)
end

should_close!(c::Canvas, b) = GLFW.SetWindowShouldClose(c.native_window, b)
should_close(c::Canvas) = GLFW.WindowShouldClose(c.native_window)

function clear!(c::Canvas, color=c.background)
    glClearColor(color.r, color.g, color.b, color.alpha)
    # glClearColor(1,1,1,1)
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)
end

pollevents(c::Canvas) = GLFW.PollEvents()
waitevents(c::Canvas) = GLFW.WaitEvents()

function free!(c::Canvas)
	if GLA.is_current_context(c)
		GLFW.DestroyWindow(c.native_window)
        clear_context!()
    end
end
bind(c::Canvas, target=GL_FRAMEBUFFER)  = glBindFramebuffer(target, 0)
draw(c::Canvas)         = nothing
nativewindow(c::Canvas) = c.native_window

Base.size(canvas::Canvas)  = size(canvas.area)
function Base.resize!(c::Canvas, wh::NTuple{2, Int}, resize_window=false)
	resize!(context_framebuffer(), wh)
    # nw = c.native_window
    # area = c.area
	# w, h = wh
    # f = scaling_factor(c)
    # There was some performance issue with round.(Int, SVector) - not sure if resolved.
    # wf, hf = Int.(round.(f .* Vec(w, h)))
    # c.area = Area(area.x, area.y, wf, hf)
    # if resize_window
        # GLFW.SetWindowSize(c.native_window, wf, hf)
    # end
    # return c.area
end

"""
On OSX retina screens, the window size is different from the
pixel size of the actual framebuffer. With this function we
can find out the scaling factor.
"""
function scaling_factor(window::Vec{2, Int}, fb::Vec{2, Int})
    (window[1] == 0 || window[2] == 0) && return Vec{2, Float64}(1.0)
    Vec{2, Float64}(fb) ./ Vec{2, Float64}(window)
end
function scaling_factor(c::Canvas)
    w, fb = GLFW.GetWindowSize(c.native_window), GLFW.GetFramebufferSize(c.native_window)
    scaling_factor(Vec{2, Int}(w...), Vec{2, Int}(fb...))
end

"""
Correct OSX scaling issue and move the 0,0 coordinate to left bottom.
"""
function corrected_coordinates(
        window_size::Vec{2,Int},
        framebuffer_width::Vec{2,Int},
        mouse_position::Vec{2,Float64}
    )
    s = scaling_factor(window_size.value, framebuffer_width.value)
    Vec{2,Float64}(mouse_position[1], window_size.value[2] - mouse_position[2]) .* s
end

callback_value(c::Canvas, cb::Symbol) = c.callbacks[cb][]
callback(c::Canvas, cb::Symbol)       = c.callbacks[cb]

windowsize(canvas::Canvas) = GetWindowSize(nativewindow(canvas))

set_background_color!(canvas::Canvas, color::Colorant)  = canvas.background = convert(RGBA{Float32}, color)
set_background_color!(canvas::Canvas, color::NTuple)    = canvas.background = convert(RGBA{Float32}, color)


#---------------------DEFAULTS-------------------#

canvas_defaults() = SymAnyDict(:area       => Area(0, 0, standard_screen_resolution()...),
                           	   :background => RGBA(1.0f0),
                           	   :depth      => Depth{Float32},
                           	   :callbacks  => standard_callbacks(),
                           	   :debugging  => false,
                           	   :major      => 3,
                           	   :minor      => 3,
                           	   :clear      => true,
                           	   :hidden     => false,
                           	   :visible    => true,
                           	   :focus      => false,
                           	   :fullscreen => false,
                           	   :monitor    => nothing)

import GLAbstraction: Program, Shader, FrameBuffer, Float24
import GLAbstraction: context_framebuffer, free!, bind, shadertype, uniform_names, separate, clear!, gluniform, set_uniform, depth_attachment, color_attachment, id, current_context
#Do we really need the context if it is already in frambuffer and program?

struct FullscreenVao <: Singleton
	vao::VertexArray
end

FullscreenVao()          = FullscreenVao(fullscreen_vertexarray())
bind(v::FullscreenVao)   = bind(v.vao)
draw(v::FullscreenVao)   = draw(v.vao)
unbind(v::FullscreenVao) = unbind(v.vao)

const ProgramDict = Dict{Symbol, Program}


struct IOTarget         <: RenderTargetKind end
struct ColorBlendTarget <: RenderTargetKind end
struct PeelTarget       <: RenderTargetKind end

struct RenderTarget{R <: RenderTargetKind} <: Singleton
	target::Union{FrameBuffer, Canvas}
	background::RGBAf0
end
bind(r::RenderTarget, args...)   = bind(r.target, args...)
draw(r::RenderTarget)   = draw(r.target)
clear!(r::RenderTarget, c=r.background) = clear!(r.target, c)
Base.size(r::RenderTarget)   = size(r.target)
depth_attachment(r::RenderTarget, args...) = depth_attachment(r.target, args...)
color_attachment(r::RenderTarget, args...) = color_attachment(r.target, args...)
GLA.free!(r::RenderTarget) = free!(r.target)

const RenderTargetDict  = Dict{Symbol, RenderTarget}

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

struct DefaultPass      <: RenderPassKind end
struct DepthPeelingPass <: RenderPassKind end
struct FinalPass        <: RenderPassKind end

RenderPass{name}(programs::ProgramDict, targets::RenderTargetDict; options...) where name =
    RenderPass{name}(programs, targets, options.data)

RenderPass{name}(shaderdict::Dict{Symbol, Vector{Shader}}, targets::RenderTargetDict; options...) where name =
    RenderPass{name}(Dict([sym => Program(shaders) for (sym, shaders) in shaderdict]), targets; options...)

RenderPass(name::RenderPassKind, args...; options...) =
    RenderPass{name}(args...; options...)

valid_uniforms(rp::RenderPass) = [uniform_names(p) for p in values(rp.programs)]

default_renderpass() = context_renderpass(DefaultPass, Dict{Symbol, Vector{Shader}}())

context_renderpass(::Type{Kind}, shaderdict::Dict{Symbol, Vector{Shader}}) where {Kind <: RenderPassKind} =
    RenderPass{Kind}(shaderdict, RenderTargetDict())

name(::RenderPass{n}) where n = n
main_program(rp::RenderPass) = rp.programs[:main]
main_instanced_program(rp::RenderPass) = rp.programs[:main_instanced]

function free!(rp::RenderPass)
    free!.(values(rp.programs))
    free!.(filter(t-> t != current_context(), collect(values(rp.targets))))
end

function register_callbacks(rp::RenderPass, context=current_context())
    on(wh -> resize_targets(rp, Tuple(wh)),
        callback(context, :framebuffer_size))
end

resize_targets(rp::RenderPass, wh) =
    resize!.(getfield.(values(rp.targets), :target), (wh,))


function create_transparancy_pass(wh, background, npasses)
    peel_comp_prog      = Program(peeling_compositing_shaders())
    comp_prog           = Program(compositing_shaders())
    blend_prog          = Program(blending_shaders())

    color_blender, peel1, peel2 =
        [FrameBuffer(wh, (RGBA{Float32}, Depth{Float32}), true) for i= 1:3]
    targets = RenderTargetDict(:colorblender => RenderTarget{ColorBlendTarget}(color_blender, background),
                               :peel1        => RenderTarget{PeelTarget}(peel1, background),
                               :peel2        => RenderTarget{PeelTarget}(peel2, background))
    return RenderPass{DepthPeelingPass}(ProgramDict(:blending => blend_prog, :composite => comp_prog, :peel_comp => peel_comp_prog),  targets, num_passes=npasses)
end

function final_pass()
    comp_prog = Program(compositing_shaders())
    RenderPass{FinalPass}(ProgramDict(:main => comp_prog), RenderTargetDict())
end


mutable struct TimingData <: Singleton
	time  ::Float64
	dtime ::Float64
	frames::Int
	preferred_fps::Float64
	reversed ::Bool
end

struct RenderProgram{P <: ProgramKind} <: Singleton
	program::GLA.Program	
end

GLA.bind(p::RenderProgram) = bind(p.program)
GLA.set_uniform(p::RenderProgram, args...) = set_uniform(p.program, args...)

struct UpdatedComponents <: Singleton
	components::Vector{DataType}
end

Base.empty!(uc::UpdatedComponents) = empty!(uc.components)
Base.push!(uc::UpdatedComponents, t::T) where {T<:ComponentData} = push!(uc.components, T)
Base.push!(uc::UpdatedComponents, t::DataType) = push!(uc.components, t)
Base.iterate(uc::UpdatedComponents, r...) = iterate(uc.components, r...)

function update_component!(uc::UpdatedComponents, ::Type{T}) where {T<:ComponentData}
	if !in(T, uc.components)
		push!(uc, T)
	end
end


struct TextPass <: RenderPassKind end

struct FontStorage <: Singleton
	atlas       ::AP.TextureAtlas
	storage_fbo ::GLA.FrameBuffer #All Glyphs should be stored in the first color attachment
end

function FontStorage()
	atlas = AP.get_texture_atlas()
	fbo   = GLA.FrameBuffer(size(atlas.data), (eltype(atlas.data), ), [atlas.data])
	return FontStorage(atlas, fbo)
end
