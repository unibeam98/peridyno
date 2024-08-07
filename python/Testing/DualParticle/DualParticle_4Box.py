import sys

# 打印 Python 的系统路径
print(sys.path)
import os
os.environ['PATH'] = os.pathsep.join(['E:\\Program\\Simulation\\unibeam\\python\\build\\bin\\Debug', os.environ['PATH']])
import PyPeridyno as dyno

scn = dyno.SceneGraph()
scn.set_lower_bound(dyno.Vector3f([-3, -3, -3]))
scn.set_upper_bound(dyno.Vector3f([3, 3, 3]))

cube1 = dyno.CubeModel3f()
cube1.var_location().set_value(dyno.Vector3f([0.125, 0.125, 0.125]))
cube1.var_length().set_value(dyno.Vector3f([0.15, 0.15, 0.15]))
cube1.graphics_pipeline().disable()
sampler1 = dyno.CubeSampler3f()
sampler1.var_sampling_distance().set_value(0.005)
sampler1.set_visible(False)
cube1.out_cube().connect(sampler1.in_cube())
initialParticles1 = dyno.MakeParticleSystem3f()
sampler1.state_point_set().promote_output().connect(initialParticles1.in_points())

cube2 = dyno.CubeModel3f()
cube2.var_location().set_value(dyno.Vector3f([-0.125, 0.125, 0.125]))
cube2.var_length().set_value(dyno.Vector3f([0.15, 0.15, 0.15]))
cube2.graphics_pipeline().disable()
sampler2 = dyno.CubeSampler3f()
sampler2.var_sampling_distance().set_value(0.005)
sampler2.set_visible(False)
cube2.out_cube().connect(sampler2.in_cube())
initialParticles2 = dyno.MakeParticleSystem3f()
sampler2.state_point_set().promote_output().connect(initialParticles2.in_points())

cube3 = dyno.CubeModel3f()
cube3.var_location().set_value(dyno.Vector3f([0.125, 0.125, -0.125]))
cube3.var_length().set_value(dyno.Vector3f([0.15, 0.15, 0.15]))
cube3.graphics_pipeline().disable()
sampler3 = dyno.CubeSampler3f()
sampler3.var_sampling_distance().set_value(0.005)
sampler3.set_visible(False)
cube3.out_cube().connect(sampler3.in_cube())
initialParticles3 = dyno.MakeParticleSystem3f()
sampler3.state_point_set().promote_output().connect(initialParticles3.in_points())

cube4 = dyno.CubeModel3f()
cube4.var_location().set_value(dyno.Vector3f([-0.125, 0.125, -0.125]))
cube4.var_length().set_value(dyno.Vector3f([0.15, 0.15, 0.15]))
cube4.graphics_pipeline().disable()
sampler4 = dyno.CubeSampler3f()
sampler4.var_sampling_distance().set_value(0.005)
sampler4.set_visible(False)
cube4.out_cube().connect(sampler4.in_cube())
initialParticles4 = dyno.MakeParticleSystem3f()
sampler4.state_point_set().promote_output().connect(initialParticles4.in_points())

fluid = dyno.DualParticleFluidSystem3f()
fluid.var_reshuffle_particles().set_value(True)
initialParticles1.connect(fluid.import_initial_states())
initialParticles2.connect(fluid.import_initial_states())
initialParticles3.connect(fluid.import_initial_states())
initialParticles4.connect(fluid.import_initial_states())

# Create a boundary
boundary = dyno.StaticBoundary3f()
boundary.load_cube(dyno.Vector3f([-0.25, 0, -0.25]), dyno.Vector3f([0.25, 2, 0.25]), 0.02, True)
fluid.connect(boundary.import_particle_systems())

calculateNorm = dyno.CalculateNorm3f()
fluid.state_velocity().connect(calculateNorm.in_vec())
fluid.graphics_pipeline().push_module(calculateNorm)

colorMapper = dyno.ColorMapping3f()
colorMapper.var_max().set_value(5.0)
calculateNorm.out_norm().connect(colorMapper.in_scalar())
fluid.graphics_pipeline().push_module(colorMapper)

ptRender = dyno.GLPointVisualModule()
ptRender.set_color(dyno.Color(1, 0, 0))
ptRender.var_point_size().set_value(0.0035)
ptRender.set_color_map_mode(ptRender.ColorMapMode.PER_VERTEX_SHADER)
fluid.state_point_set().connect(ptRender.in_point_set())
colorMapper.out_color().connect(ptRender.in_color())
fluid.graphics_pipeline().push_module(ptRender)

# A simple color bar widget for node
colorBar = dyno.ImColorbar3f()
colorBar.var_max().set_value(5.0)
colorBar.var_field_name().set_value("Velocity")
calculateNorm.out_norm().connect(colorBar.in_scalar())
# add the widget to app
fluid.graphics_pipeline().push_module(colorBar)

vpRender = dyno.GLPointVisualModule()
vpRender.set_color(dyno.Color(1, 1, 0))
vpRender.set_color_map_mode(vpRender.ColorMapMode.PER_VERTEX_SHADER)
fluid.state_virtual_pointSet().connect(vpRender.in_point_set())
vpRender.var_point_size().set_value(0.0005)
fluid.graphics_pipeline().push_module(vpRender)

scn.add_node(cube1)
scn.add_node(sampler1)
scn.add_node(initialParticles1)

scn.add_node(cube2)
scn.add_node(sampler2)
scn.add_node(initialParticles2)

scn.add_node(cube3)
scn.add_node(sampler3)
scn.add_node(initialParticles3)

scn.add_node(cube4)
scn.add_node(sampler4)
scn.add_node(initialParticles4)

scn.add_node(fluid)
scn.add_node(boundary)

app = dyno.GlfwApp()
app.set_scenegraph(scn)
app.initialize(1920, 1080, True)
app.main_loop()
