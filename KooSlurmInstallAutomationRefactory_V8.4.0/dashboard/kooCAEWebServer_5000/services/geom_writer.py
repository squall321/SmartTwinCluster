import numpy as np
import trimesh
from stl import mesh
from typing import Any
from file_parser import extract_surface_triangles

def extract_surface_triangles_old(elements, types):
    face_map = {
        'hexa8': [
            (0, 3, 2, 1),  # bottom (외부에서 보면 반시계)
            (4, 5, 6, 7),  # top
            (0, 1, 5, 4),  # front
            (1, 2, 6, 5),  # right
            (2, 3, 7, 6),  # back
            (3, 0, 4, 7),  # left
        ],
        'tet4': [
            (0, 2, 1),  # face opposite node 3
            (0, 1, 3),  # face opposite node 2
            (1, 2, 3),  # face opposite node 0
            (2, 0, 3),  # face opposite node 1
        ]
    }

    face_dict = {}  # key: frozenset(face_nodes), value: [original_winding]

    for eid, conn in elements.items():
        etype = types[eid]
        face_defs = face_map.get(etype)
        if not face_defs:
            continue

        for face in face_defs:
            face_nodes = tuple(conn[i] for i in face)
            key = frozenset(face_nodes)  # ignore winding for comparison
            if key in face_dict:
                face_dict[key].append(face_nodes)
            else:
                face_dict[key] = [face_nodes]

    # 결과: 외곽 삼각형만 추출
    triangles = []
    for faces in face_dict.values():
        if len(faces) == 1:
            face = faces[0]
            if len(face) == 4:
                # quad → 2개 triangle
                triangles.append((face[0], face[1], face[2]))
                triangles.append((face[0], face[2], face[3]))
            elif len(face) == 3:
                triangles.append(face)
    return triangles




def write_stl_from_elements(nodes, elements, types, out_path):
    triangles = []

    for eid, conn in elements.items():
        etype = types[eid]
        if etype in ['tri', 'tria3']:
            triangles.append([nodes[n] for n in conn[:3]])
        elif etype in ['quad', 'quad4']:
            pts = [nodes[n] for n in conn[:4]]
            triangles.append([pts[0], pts[1], pts[2]])
            triangles.append([pts[0], pts[2], pts[3]])

    if any(types[eid] in ['solid', 'hex', 'hexa8', 'tet4'] for eid in elements):
        tri_faces = extract_surface_triangles(elements, types)
        for tri in tri_faces:
            triangles.append([nodes[n] for n in tri])

    data = np.zeros(len(triangles), dtype=mesh.Mesh.dtype)
    for i, tri in enumerate(triangles):
        data["vectors"][i] = np.array(tri)    
    m: Any = mesh.Mesh(data)
    m.save(out_path)

def write_glb_from_elements(nodes, elements, types, out_path):
    import numpy as np
    import trimesh

    # STEP 1: 표면 삼각형만 추출
    faces = []
    used_node_ids = set()

    if any(types[eid] in ['solid', 'hex', 'hexa8', 'tet4'] for eid in elements):
        tri_faces = extract_surface_triangles_old(elements, types)
        for tri in tri_faces:
            faces.append(tri)
            used_node_ids.update(tri)
    else:
        for eid, conn in elements.items():
            etype = types[eid].lower()
            if etype in ['tri', 'tria3']:
                tri = conn[:3]
                faces.append(tri)
                used_node_ids.update(tri)
            elif etype in ['quad', 'quad4']:
                quad = conn[:4]
                faces.append([quad[0], quad[1], quad[2]])
                faces.append([quad[0], quad[2], quad[3]])
                used_node_ids.update(quad)

    # STEP 2: 고유 노드만 추출해서 인덱스 재배열
    used_node_ids = sorted(used_node_ids)
    node_index_map = {nid: idx for idx, nid in enumerate(used_node_ids)}
    vertices = [nodes[nid] for nid in used_node_ids]

    # STEP 3: face 재구성
    indexed_faces = [[node_index_map[nid] for nid in face] for face in faces]

    vertices_array = np.array(vertices)
    faces_array = np.array(indexed_faces)

    mesh = trimesh.Trimesh(vertices=vertices_array, faces=faces_array, process=False)
    mesh.export(out_path, file_type='glb')


def write_glb_from_elements_prev(nodes, elements, types, out_path):
    vertices: list = []
    faces = []
    node_index_map = {}

    def get_index(node_id):
        if node_id not in node_index_map:
            node_index_map[node_id] = len(vertices)
            vertices.append(nodes[node_id])
        return node_index_map[node_id]

    for eid, conn in elements.items():
        etype = types[eid].lower()
        if etype in ['tri', 'tria3']:
            idx = [get_index(nid) for nid in conn[:3]]
            faces.append(idx)
        elif etype in ['quad', 'quad4']:
            idx = [get_index(nid) for nid in conn[:4]]
            faces.append([idx[0], idx[1], idx[2]])
            faces.append([idx[0], idx[2], idx[3]])

    # solid 요소 표면 추출
    if any(types[eid] in ['solid', 'hex', 'hexa8', 'tet4'] for eid in elements):
        tri_faces = extract_surface_triangles_old(elements, types)
        for tri in tri_faces:
            idx = [get_index(nid) for nid in tri]
            faces.append(idx)

    vertices_array = np.array(vertices)
    faces_array = np.array(faces)

    mesh = trimesh.Trimesh(vertices=vertices_array, faces=faces_array, process=False)
    mesh.export(out_path, file_type='glb')
    
if __name__ == "__main__":
    elements = {1: [1,2,3,4] , 2: [2,3,4,5]}
    types = {1: 'tet4', 2: 'tet4'}
    extract_surface_triangles(elements, types)
