import GLAbstraction: set_uniform

struct UniformCalculator <: System end

Overseer.requested_components(::UniformCalculator) = (Spatial, Shape, ModelMat, Dynamic, Camera3D, UpdatedComponents, Rotation)

function Overseer.update(::UniformCalculator, m::AbstractLedger)
	uc        = singleton(m, UpdatedComponents)
	m_updated = false
	modelmat  = m[ModelMat]
	dyn       = m[Dynamic]
	camera    = m[Camera3D]
	spatial   = m[Spatial]
	shape     = m[Shape]
	rotation  = m[Rotation]

	for e in @entities_in(spatial)
		if !in(e, modelmat) || in(e, dyn) || in(e, camera) || in(Spatial, uc) || in(Rotation, uc)
			m_updated = true

    		tmat = translmat(spatial[e].position)
            if in(e, rotation)
                tmat = tmat * Mat4f0(rotation[e].q)
            end

			if in(e, shape)
                tmat = tmat * scalemat(shape[e].scale)
            end
			modelmat[e] = ModelMat(tmat)
		end
	end
	if m_updated
		push!(uc, ModelMat)
	end
end

# function Overseer.update(::UniformCalculator, m::AbstractLedger)
# 	uc        = m[UpdatedComponents][1]
# 	m_updated = false
# 	modelmat  = m[ModelMat]
# 	dyn       = m[Dynamic]
# 	camera    = m[Camera3D]
# 	spatial   = m[Spatial]
# 	shape     = m[Shape]
# 	g1 = group(m, ModelMat, Spatial, Shape)
# 	g2 = group(m, ModelMat, Spatial)
# 	if length(g1) == 0
#     	for e in @entities_in(spatial && shape)
#     		g1[e] = ModelMat(translmat(spatial[e].position) * scalemat(Vec3f0(shape[e].scale)))
#     	end
#     	for e in @entities_in(spatial && !shape)
#     		g2[e] = ModelMat(translmat(spatial[e].position))
#     	end
# 	else
#         @inbounds for i = 1:length(g2)
#             modelmat.data[i] = ModelMat(translmat(spatial[i].position))
#         end
#         @inbounds for i = 1:length(g1)
#             modelmat.data[i] = ModelMat(modelmat[i].modelmat * scalemat(Vec3f0(shape[i].scale)))
#         end
#     end
# 	push!(uc, ModelMat)
# end


function set_entity_uniforms_func(render_program::Union{DefaultProgram, PeelingProgram, LineProgram}, system::System)
    prog = render_program.program
    material = component(system, Material)
    modelmat = component(system, ModelMat)
    ucolor   = component(system, UniformColor)
	return e -> begin
		set_uniform(prog, :material, Vec2(material[e].specpow, material[e].specint))
		set_uniform(prog, :modelmat, modelmat[e].modelmat)
		if has_entity(ucolor, e)
			set_uniform(prog, :uniform_color, ucolor[e].color)
			set_uniform(prog, :is_uniform, true)
		else
			set_uniform(prog, :is_uniform, false)
			set_uniform(prog, :specpow, material[e].specpow)
		end
	end
end

function set_uniform(program::GLA.Program, spatial, camera::Camera3D)
    set_uniform(program, :projview, camera.projview)
    set_uniform(program, :campos,   spatial.position)
end

function set_uniform(program::GLA.Program, pointlight::PointLight, color::UniformColor, spatial::Spatial)
    set_uniform(program, Symbol("plight.color"),              RGB(color.color))
    set_uniform(program, Symbol("plight.position"),           spatial.position)
    set_uniform(program, Symbol("plight.amb_intensity"),      pointlight.ambient)
    set_uniform(program, Symbol("plight.specular_intensity"), pointlight.specular)
    set_uniform(program, Symbol("plight.diff_intensity"),     pointlight.diffuse)
end
