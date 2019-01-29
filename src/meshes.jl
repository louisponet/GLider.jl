import GeometryTypes: vertices, normals, faces, decompose, normals
import GLAbstraction: INVALID_ATTRIBUTE, attribute_location, GEOMETRY_DIVISOR


abstract type AbstractGlimpseMesh end

const INSTANCED_MESHES = Dict{Type, AbstractGlimpseMesh}()

struct BasicMesh{D, T, FD, FT} <: AbstractGlimpseMesh
    vertices ::Vector{Point{D, T}}
    faces    ::Vector{Face{FD, FT}}
    normals  ::Vector{Point{D, T}}
end

BasicMesh(geometry::T, ft=Face{3, Glint}) where T =
    error("Please implement a `BasicMesh` constructor for type $T.")

function BasicMesh(geometry::AbstractGeometry{D, T}, ft=Face{3, GLint}) where {D, T}
    vertices = decompose(Point{D, T}, geometry)
    faces    = decompose(ft, geometry)
    norms    = normals(vertices, faces)
    return BasicMesh(vertices, faces, norms)
end

function BasicMesh(geometry::HyperSphere, complexity=2)
    vertices, normals, faces = generate_sphere(complexity)
    return BasicMesh(vertices, faces, normals)
end
Base.eltype(::Type{BasicMesh{D, T, FD, FT}}) where {D, T, FD, FT} = (D, T, FD, FT)
Base.eltype(mesh::BM) where {BM <: BasicMesh} = eltype(BM)

basicmesh(mesh::BasicMesh)          = mesh
vertices(mesh::AbstractGlimpseMesh) = basicmesh(mesh).vertices
normals(mesh::AbstractGlimpseMesh)  = basicmesh(mesh).normals
faces(mesh::AbstractGlimpseMesh)    = basicmesh(mesh).faces

facelength(mesh::AbstractGlimpseMesh)  = facelength(basicmesh(mesh))
facelength(mesh::BasicMesh{D, T, FD, FT} where {D, T, FD}) where FT = length(FT)

Base.length(mesh::AbstractGlimpseMesh) = length(vertices(mesh))


struct AttributeMesh{AT<:NamedTuple, BM <: BasicMesh} <: AbstractGlimpseMesh
    attributes ::AT
    basic      ::BM
end

AttributeMesh(attributes, args...) =
    AttributeMesh(attributes, BasicMesh(args...))
AttributeMesh(args...; attributes...) =
    AttributeMesh(NamedTuple{keys(attributes)}(values(attributes)), BasicMesh(args...))

Base.eltype(::Type{AttributeMesh{AT, BM}}) where {AT, BM} = (AT, eltype(BM)...)
Base.eltype(mesh::AM) where {AM <: AttributeMesh} = eltype(AM)

basicmesh(mesh::AttributeMesh) = mesh.basic

function generate_buffers(mesh::BasicMesh, program::Program)
    buffers = BufferAttachmentInfo[]
    for n in (:vertices, :normals)
        loc = attribute_location(program, n)
        if loc != INVALID_ATTRIBUTE
            push!(buffers, BufferAttachmentInfo(loc, Buffer(getfield(mesh, n)), GEOMETRY_DIVISOR))
        end
    end
    return buffers
end

function generate_buffers(mesh::AttributeMesh{AT}, program::Program) where AT
    buffers = generate_buffers(basicmesh(mesh), program)
    buflen  = length(mesh)
    for (name, val) in pairs(mesh.attributes)
        loc = attribute_location(program, name)
        if loc != INVALID_ATTRIBUTE
            vallen = length(val)
            if vallen == buflen
                push!(buffers, BufferAttachmentInfo(loc, Buffer(val), GEOMETRY_DIVISOR))
            elseif !isa(val, Vector)
                push!(buffers, BufferAttachmentInfo(loc, Buffer(fill(val, buflen)), GEOMETRY_DIVISOR))
            end
        end
    end
    return buffers
end

VertexArray(mesh::AbstractGlimpseMesh, program::Program) =
    VertexArray(generate_buffers(mesh, program), faces(mesh) .- GLint(1))