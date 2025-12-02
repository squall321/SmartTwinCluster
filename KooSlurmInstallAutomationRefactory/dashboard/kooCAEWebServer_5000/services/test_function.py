from KooCAE import ElementShellManager, NodeManager, ElementManager, ElementSolidManager, BoundaryManager, PartManager

nodeManager = NodeManager()
boundaryManager = BoundaryManager()
partManager = PartManager()

mode = "BASIC"
mode = "BATTERY"


if mode == "BATTERY":
    elementManager = ElementSolidManager()
 

    elementManager.generate_fillet_hexa_grid(0,0,0,10,10,10,10,10,10,nodeManager, 2)
    
if mode == "BASIC":
    elementManager = ElementShellManager()


    N1 = nodeManager.add_node_with_id(1, 0, 0, 0)
    N2 = nodeManager.add_node_with_id(2, 1, 0, 0)
    N3 = nodeManager.add_node_with_id(3, 0, 1, 0)
    N4 = nodeManager.add_node_with_id(4, 0, 0, 1)

    

    E1 = elementManager.add_tri3(1, [N1, N2, N3])
    E2 = elementManager.add_tri3(2, [N1, N2, N4])
    E3 = elementManager.add_tri3(3, [N1, N3, N4])
    E4 = elementManager.add_tri3(4, [N2, N3, N4])
    

    B1 = boundaryManager.add_node_boundary(1, [1, 2, 3, 4])
    B1.set_nodes(nodeManager)

    P1 = partManager.add_part(1, "Part1", 1, 1)
    P1.set_nodeManager(nodeManager)
    P1.set_elementManager(elementManager)
    P1.set_boundaryManager(boundaryManager)

    print(nodeManager.write_ls_dyna())
    print(E1.write_ls_dyna_as_string(1))
    #print(elementManager.write_ls_dyna(1))