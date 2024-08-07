import PyPeridyno as dyno

scn = dyno.SceneGraph()

rigid = dyno.RigidBodySystem3f()

newBox = oldBox = dyno.BoxInfo()
rigidBody = dyno.RigidBodyInfo()
rigidBody.linear_velocity = dyno.Vector3f([1, 0.0, 1.0])

oldBox.center = dyno.Vector3f([0, 0.1, 0])
oldBox.half_length = dyno.Vector3f([0.02, 0.02, 0.02])
oldBoxActor = rigid.add_box(oldBox, rigidBody)

rigidBody.linear_velocity = dyno.Vector3f([0, 0, 0])

for i in range(10):
    newBox.center = oldBox.center + dyno.Vector3f([0.0, 0.05, 0.0])
    newBox.half_length = oldBox.half_length
    newBoxActor = rigid.add_box(newBox, rigidBody)
    fixedJoint = rigid.create_fixed_joint(oldBoxActor, newBoxActor)
    fixedJoint.set_anchor_point((oldBox.center + newBox.center) / 2)
    oldBox = newBox
    oldBoxActor = newBoxActor

mapper = dyno.DiscreteElementsToTriangleSet3f()
rigid.state_topology().connect(mapper.in_discrete_elements())
rigid.graphics_pipeline().push_module(mapper)

sRender = dyno.GLSurfaceVisualModule()
sRender.set_color(dyno.Color(1, 1, 0))
sRender.set_alpha(1.0)
mapper.out_triangle_set().connect(sRender.in_triangle_set())
rigid.graphics_pipeline().push_module(sRender)

elementQuery = dyno.NeighborElementQuery3f()
rigid.state_topology().connect(elementQuery.in_discrete_elements())
rigid.state_collision_mask().connect(elementQuery.in_collision_mask())
rigid.graphics_pipeline().push_module(elementQuery)

contactMapper = dyno.ContactsToEdgeSet3f()
elementQuery.out_contacts().connect(contactMapper.in_contacts())
contactMapper.var_scale().set_value(0.02)
rigid.graphics_pipeline().push_module(contactMapper)

wireRender = dyno.GLWireframeVisualModule()
wireRender.set_color(dyno.Color(0, 0, 1))
contactMapper.out_edge_set().connect(wireRender.in_edge_set())
rigid.graphics_pipeline().push_module(wireRender)

contactPointMapper = dyno.ContactsToPointSet3f()
elementQuery.out_contacts().connect(contactPointMapper.in_contacts())
rigid.graphics_pipeline().push_module(contactPointMapper)

pointRender = dyno.GLPointVisualModule()
pointRender.set_color(dyno.Color(1, 0, 0))
pointRender.var_point_size().set_value(0.003)
contactPointMapper.out_point_set().connect(pointRender.in_point_set())
rigid.graphics_pipeline().push_module(pointRender)

scn.add_node(rigid)

app = dyno.GlfwApp()
app.set_scenegraph(scn)
app.initialize(1920, 1080, True)
app.set_window_title("Empty GUI")
app.main_loop()
