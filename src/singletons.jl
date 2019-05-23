import GLAbstraction: bind, unbind, draw

struct CanvasContext <: GLA.AbstractContext
	id::Int
end

#TODO think about contexts
mutable struct Canvas <: Singleton
    name          ::Symbol
    id            ::Int
    area          ::Area
    native_window ::GLFW.Window
    imgui_context ::UInt
    background    ::Colorant{Float32, 4}
    callbacks     ::Dict{Symbol, Any}
	context       ::CanvasContext
	function Canvas(name::Symbol, id::Int, area, nw, background, callbacks)

		ctx = convert(UInt, CImGui.GetCurrentContext())
		if ctx == 0
			ctx = convert(UInt, CImGui.CreateContext())
		else
			CImGui.DestroyContext(CImGui.GetCurrentContext())
			ctx = convert(UInt, CImGui.CreateContext())
		end
		ImGui_ImplGlfw_InitForOpenGL(nw, true)
		ImGui_ImplOpenGL3_Init(420)

	    callback_dict = register_callbacks(nw, callbacks)

		obj = new(name, id, area, nw, ctx, background, callback_dict, CanvasContext(id))

		finalizer(free!, obj)
		return obj
	end
    # framebuffer::FrameBuffer # this will become postprocessing passes. Each pp has a
end

const canvas_id_counter = Base.RefValue(0)

new_canvas_id() = (canvas_id_counter[] = mod1(canvas_id_counter[] + 1, 255); canvas_id_counter[])[]

Base.size(area::Area) = (area.w, area.h)

function Canvas(name=:Glimpse; kwargs...)
	id = new_canvas_id() 
    defaults = mergepop!(canvas_defaults(), kwargs)

    window_hints  = GLFW_DEFAULT_WINDOW_HINTS
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

    callbacks  = defaults[:callbacks]

	c = Canvas(name, id, area, nw, background, callbacks)
	if defaults[:visible]
	    make_current(c)
    end
    return c
end

function make_current(c::Canvas)
	GLFW.SetWindowShouldClose(c.native_window, false)
	GLFW.ShowWindow(c.native_window)
    GLFW.MakeContextCurrent(c.native_window)
    GLA.set_context!(c.context)
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

function GLA.free!(c::Canvas)
	if GLA.is_current_context(c)
		GLFW.DestroyWindow(c.native_window)
        clear_context!()
    end
end

bind(c::Canvas, target=GL_FRAMEBUFFER)  = glBindFramebuffer(target, 0)

draw(c::Canvas) = nothing

nativewindow(c::Canvas) = c.native_window

Base.size(canvas::Canvas)  = size(canvas.area)

function Base.resize!(c::Canvas, wh::NTuple{2, Int}, resize_window=false)
	resize!(GLA.context_framebuffer(), wh)
	c.area = Area(0.0, 0.0, Float64.(wh)...)
end

callback_value(c::Canvas, cb::Symbol) = c.callbacks[cb][]

callback(c::Canvas, cb::Symbol) = c.callbacks[cb]

windowsize(canvas::Canvas) = GLFW.GetWindowSize(nativewindow(canvas))

set_background_color!(canvas::Canvas, color::Colorant) = canvas.background = convert(RGBA{Float32}, color)
set_background_color!(canvas::Canvas, color::NTuple)   = canvas.background = convert(RGBA{Float32}, color)


#---------------------DEFAULTS-------------------#

canvas_defaults() = SymAnyDict(:area       => Area(0, 0, glfw_standard_screen_resolution()...),
                           	   :background => RGBA(1.0f0),
                           	   :depth      => GLA.Depth{Float32},
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

struct FullscreenVao <: Singleton
	vao::VertexArray
end

FullscreenVao() =
	FullscreenVao(VertexArray([BufferAttachmentInfo(:position,
                                                    GLint(0),
                                                    Buffer(fullscreen_pos),
                                                    GEOMETRY_DIVISOR),
                               BufferAttachmentInfo(:uv,
                                                    GLint(1),
                                                    Buffer(fullscreen_uv),
                                                    GEOMETRY_DIVISOR)], GL_TRIANGLE_STRIP))

bind(v::FullscreenVao)   = bind(v.vao)

draw(v::FullscreenVao)   = draw(v.vao)

unbind(v::FullscreenVao) = unbind(v.vao)

# I'm not sure this is nice design idk
struct IOTarget <: RenderTargetKind end

struct RenderTarget{R <: RenderTargetKind} <: Singleton
	target     ::Union{FrameBuffer, Canvas}
	background ::RGBAf0
end

bind(r::RenderTarget, args...) = bind(r.target, args...)

draw(r::RenderTarget) = draw(r.target)

clear!(r::RenderTarget, c=r.background) = clear!(r.target, c)

Base.size(r::RenderTarget) = size(r.target)

GLA.depth_attachment(r::RenderTarget, args...) = GLA.depth_attachment(r.target, args...)

GLA.color_attachment(r::RenderTarget, args...) = GLA.color_attachment(r.target, args...)

GLA.free!(r::RenderTarget) = free!(r.target)

Base.resize!(r::RenderTarget, args...) = resize!(r.target, args...)

mutable struct TimingData <: Singleton
	time          ::Float64
	dtime         ::Float64
	frames        ::Int
	preferred_fps ::Float64
	reversed      ::Bool
end

struct RenderProgram{P <: ProgramKind} <: Singleton
	program::GLA.Program	
end

bind(p::RenderProgram) = bind(p.program)

unbind(p::RenderProgram) = unbind(p.program)

GLA.set_uniform(p::RenderProgram, args...) = GLA.set_uniform(p.program, args...)

struct UpdatedComponents <: Singleton
	components::Vector{DataType}
end

Base.empty!(uc::UpdatedComponents) = empty!(uc.components)

Base.iterate(uc::UpdatedComponents, r...) = iterate(uc.components, r...)

Base.push!(uc::UpdatedComponents, t::T) where {T<:ComponentData} = push!(uc.components, T)
Base.push!(uc::UpdatedComponents, t::DataType)                   = push!(uc.components, t)

function update_component!(uc::UpdatedComponents, ::Type{T}) where {T<:ComponentData}
	if !in(T, uc.components)
		push!(uc, T)
	end
end

struct FontStorage <: Singleton
	atlas       ::AP.TextureAtlas
	storage_fbo ::GLA.FrameBuffer #All Glyphs should be stored in the first color attachment
end

function FontStorage()
	atlas = AP.get_texture_atlas()
	fbo   = GLA.FrameBuffer(size(atlas.data), (eltype(atlas.data), ), [atlas.data])
	return FontStorage(atlas, fbo)
end

