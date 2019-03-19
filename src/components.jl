
Component(id, ::Type{T}) where {T <: ComponentData}       = Component(id, GappedVector([T[]], Int[]))
SharedComponent(id, ::Type{T}) where {T <: ComponentData} = SharedComponent(id, GappedVector([Int[]], Int[]), T[])

data(component::AbstractComponent) = component.data

Base.length(::ComponentData)         = 1
Base.iterate(t::ComponentData)       = (t, nothing)

Base.isempty(c::AbstractComponent)   = isempty(c.data)
Base.empty!(c::AbstractComponent)    = empty!(c.data)

Base.length(c::AbstractComponent)    = length(c.data)
Base.size(c::AbstractComponent)      = size(c.data)
Base.lastindex(c::AbstractComponent) = lastindex(c.data)

Base.getindex(c::Component, i)       = getindex(c.data, i)
Base.getindex(c::SharedComponent, i) = c.shared[getindex(c.data, i)]

Base.setindex!(c::Component, v, i)   = setindex!(c.data, v, i)

function Base.setindex!(c::SharedComponent,v, i)
	id = findfirst(isequal(v), c.shared)
	if id == nothing
		id = length(c.shared) + 1
		push!(c.shared, v)
	end
	c.data[i] = id
end

valid_entities(c::AbstractComponent)     = Iterators.flatten(ranges(c.data))
valid_entities(cs::AbstractComponent...) = Iterators.flatten(ranges(data.(cs)...))
has_entity(c::AbstractComponent, entity) = has_index(c.data, entity)

function shared_entities(c::SharedComponent{T}, dat::T) where T
	ids = Int[]
	id = findfirst(x -> x == dat, c.shared)
	for i in c.data
		if i == id
			push!(ids, i)
		end
	end
	return ids
end

# DEFAULT COMPONENTS
struct Spatial <: ComponentData
	position::Vec3f0
	velocity::Vec3f0
end
SpatialComponent(id) = Component(id, Spatial) 

struct Geometry <: ComponentData
	mesh
end
GeometryComponent(id)       = Component(id, Geometry)
GeometrySharedComponent(id) = SharedComponent(id, Geometry)

struct Vao{RP <: RenderPassKind} <: ComponentData
	vertexarray::VertexArray
end
VaoComponent(id)       = Component(id, Vao)
VaoSharedComponent(id) = SharedComponent(id, Vao)

mutable struct Upload{RP <: RenderPassKind} <: ComponentData
	is_instanced::Bool
	is_visible  ::Bool
end

DefaultUploadComponent(id)      = Component(id, Upload{DefaultPass})
DepthPeelingUploadComponent(id) = Component(id, Upload{DepthPeelingPass})

is_instanced(data::Upload) = data.is_instanced
kind(::Type{Upload{Kind}}) where Kind = Kind

struct Material <: ComponentData
	specpow ::Float32
	specint ::Float32
	color   ::RGBf0
end

MaterialComponent(id) = Component(id, Material)

struct Shape <: ComponentData
	scale::Float32
end

ShapeComponent(id) = Component(id, Shape)

struct PointLight <: ComponentData
    position::Vec3f0
    diffuse ::Float32
    specular::Float32
    ambient ::Float32
    color   ::RGBf0
end

PointLightComponent(id) = Component(id, PointLight)

struct DirectionLight <: ComponentData
	direction::Vec3f0
    diffuse  ::Float32
    specular ::Float32
    ambient  ::Float32
    color    ::RGBf0	
end

DirectionLightComponent(id) = Component(id, PointLight)

mutable struct Camera3D <: ComponentData
    lookat ::Vec3f0
    up     ::Vec3f0
    right  ::Vec3f0
    fov    ::Float32
    near   ::Float32
    far    ::Float32
    view   ::Mat4f0
    proj        ::Mat4f0
    projview    ::Mat4f0
    rotation_speed    ::Float32
    translation_speed ::Float32
    mouse_pos         ::Vec2f0
    scroll_dx         ::Float32
    scroll_dy         ::Float32
end

CameraComponent3D(id) = Component(id, Camera3D)


