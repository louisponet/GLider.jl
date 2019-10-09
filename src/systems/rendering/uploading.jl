struct Uploader{P <: ProgramKind} <: System end

requested_components(::Uploader{P}) where {P<:Union{DefaultProgram,PeelingProgram,LineProgram}} =
	(Mesh, BufferColor, Vao{P}, ProgramTag{P}, RenderProgram{P})

requested_components(::Uploader{P}) where {P<:Union{InstancedDefaultProgram,InstancedPeelingProgram}} =
	(Mesh, UniformColor, ModelMat, Material, Vao{P}, ProgramTag{P}, RenderProgram{P})

shaders(::Type{DefaultProgram}) = default_shaders()
shaders(::Type{PeelingProgram}) = peeling_shaders()

function ECS.prepare(::Uploader{P}, dio::Diorama) where {P<:Union{DefaultProgram,PeelingProgram,LineProgram}}
	if isempty(dio[RenderProgram{P}])
		Entity(dio, RenderProgram{P}(Program(shaders(P))))
	end
end

function update(::Uploader{P}, m::Manager) where {P<:Union{DefaultProgram,PeelingProgram,LineProgram}}

	mesh, bcolor, vao, progtag, prog = m[Mesh], m[BufferColor], m[Vao{P}], m[ProgramTag{P}], m[RenderProgram{P}][1].program

	set_vao = (e, buffers, e_mesh) -> begin
	    if P == LineProgram
            vao[e] = Vao{P}(VertexArray(buffers, 11), true)
	    else
		    vao[e] = Vao{P}(VertexArray(buffers, faces(e_mesh.mesh) .- GLint(1)), true)
	    end
    end
	for e in entities(mesh, progtag, exclude=(vao, bcolor))
    	e_mesh = mesh[e] 
		buffers = generate_buffers(prog, e_mesh.mesh)
		set_vao(e, buffers, e_mesh)
	end

	for e in entities(mesh, progtag, bcolor, exclude=(vao,))
    	e_mesh = mesh[e] 
		buffers = [generate_buffers(prog, e_mesh.mesh);
	               generate_buffers(prog, GEOMETRY_DIVISOR, color=bcolor[e].color)]
		set_vao(e, buffers, e_mesh)
	end
end

shaders(::Type{InstancedDefaultProgram}) = instanced_default_shaders()
shaders(::Type{InstancedPeelingProgram}) = instanced_peeling_shaders()


function ECS.prepare(::Uploader{P}, dio::Diorama) where {P<:Union{InstancedDefaultProgram, InstancedPeelingProgram}}
	if isempty(dio[RenderProgram{P}])
		Entity(dio, RenderProgram{P}(Program(shaders(P))))
	end
end

function update(::Uploader{P}, m::Manager) where {P <: Union{InstancedDefaultProgram, InstancedPeelingProgram}}
	prog = m[RenderProgram{P}][1].program	
	vao  = m[Vao{P}]
	mesh = m[Mesh]
	it   = entities(mesh, m[UniformColor], m[ModelMat], m[Material], m[ProgramTag{P}], exclude=(vao,))
	if isempty(mesh)
		return
	end
	stor = ECS.storage(vao)
	ucolor = m[UniformColor]
	modelmat = m[ModelMat]
	material = m[Material]
	for tmesh in mesh.shared
		modelmats = Mat4f0[]
		ucolors   = RGBAf0[]
		specints  = Float32[]
		specpows  = Float32[]
		ids  = Int[]
		for e in it
            e_mesh, e_color, e_modelmat, e_material = mesh[e], ucolor[e], modelmat[e],  material[e]
			if e_mesh.mesh === tmesh.mesh
				push!(modelmats, e_modelmat.modelmat)
				push!(ucolors, e_color.color)
				push!(specints, e_material.specint)
				push!(specpows, e_material.specpow)
				push!(ids, ECS.id(e))
			end
		end
		if !isempty(ids)
			tvao = Vao{P}(VertexArray([generate_buffers(prog, tmesh.mesh); generate_buffers(prog, GLint(1), color=ucolors, modelmat=modelmats, specint=specints, specpow=specpows)], tmesh.mesh.faces .- GLint(1), length(ids)), true)
			push!(vao.shared, tvao)
			id = length(vao.shared)
			for i in ids
				stor[i, ECS.Reverse()] = id
			end
		end
	end
end

struct UniformUploader{P<:ProgramKind} <: System end

requested_components(::UniformUploader{P}) where {P}= (Vao{P}, ModelMat, Selectable, UniformColor, UpdatedComponents)

# function find_contiguous_bounds(indices)
# 	ranges = UnitRange[]
# 	i = 1
# 	cur_start = indices[1]
# 	while i <= length(indices) - 1
# 		id = indices[i]
# 		id_1 = indices[i + 1]
# 		if id_1 - id != 1
# 			push!(ranges, cur_start:id)
# 			cur_start = id_1
# 		end
# 		i += 1
# 	end
# 	push!(ranges, cur_start:indices[end])
# 	return ranges
# end
function ECS.prepare(::UniformUploader, dio::Diorama)
	if isempty(dio[UpdatedComponents])
		Entity(dio, UpdatedComponents())
	end
end

function update(::UniformUploader{P}, m::Manager) where {P<:ProgramKind}
	uc = m[UpdatedComponents][1]
	vao = m[Vao{P}]

	mat = m[ModelMat]
	matsize = sizeof(eltype(mat))
	if ModelMat in uc
    	it1 = entities(vao, mat)
		for tvao in vao.shared
			modelmats = Mat4f0[]

			for e  in it1
                e_vao, e_modelmat = vao[e], mat[e]
				if e_vao === tvao
					push!(modelmats, e_modelmat.modelmat)
				end
			end
			if !isempty(modelmats)
				binfo = GLA.bufferinfo(tvao.vertexarray, :modelmat)
				if binfo != nothing
					GLA.bind(binfo.buffer)
					s = length(modelmats) * matsize
					glBufferSubData(binfo.buffer.buffertype, 0, s, pointer(modelmats, 1))
					GLA.unbind(binfo.buffer)
				end
			end
		end
	end
    ucolor = m[UniformColor]
	if UniformColor in uc.components
    	colsize = sizeof(RGBAf0)
    	it2 = entities(vao, m[UniformColor], m[Selectable])
		for tvao in vao.shared
			colors = RGBAf0[]
			for e in it2
    			e_val, e_color, = vao[e], ucolor[e]
				if e_vao === tvao
					push!(colors, e_color.color)
				end
			end
			if !isempty(colors)
				binfo = GLA.bufferinfo(tvao.vertexarray, :color)
				if binfo != nothing
					GLA.bind(binfo.buffer)
					s = length(colors) * colsize
					glBufferSubData(binfo.buffer.buffertype, 0, s, pointer(colors, 1))
					GLA.unbind(binfo.buffer)
				end
			end
		end
	end
end
