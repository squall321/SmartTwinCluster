import sys
import os

# 현재 파일 기준 상대경로로 services 추가
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
import KooCAE as cpp_parser


def parse_filename(filename: str):
    """
    Parse LS-DYNA filename into parameter dict.
    - Extract Number before DA_
    - Parse key-value pairs after DA_
    """
    return cpp_parser.parse_filename(filename)

def parse_dyna_file_pid(text: str):
    """
    Parse *PART blocks in the k-file to extract PID and names.
    """
    return cpp_parser.parse_dyna_file_pid(text)


def parse_kfile_all(data: str):
    """
    Parse LS-DYNA k file for all nodes, elements, types, and bounding box.
    """
    return cpp_parser.parse_kfile_all(data)

def parse_kfile(data: str, target_pid: str):
    """
    Parse LS-DYNA k file for nodes, elements, types, and bounding box.
    """
    return cpp_parser.parse_kfile(data, target_pid)

def parse_kfile_nodes(data: str):
    return cpp_parser.parse_kfile_nodes(data)


def parse_kfile_elements_of_partid_and_nodes(data: str, target_pid: str):
    return cpp_parser.parse_kfile_elements_of_partid_and_nodes(data, target_pid)




def get_boundary_box_of_given_partid_and_nodes(data: str, target_pid: str, nodes: dict):
    return cpp_parser.get_boundary_box_of_given_partid_and_nodes(data, target_pid, nodes)


def get_boundary_box_of_given_partid(data: str, target_pid: str):
    return cpp_parser.get_boundary_box_of_given_partid(data, target_pid)


def calculate_bbox_from_elements(elements: dict, nodes: dict):
    min_x, min_y, min_z = float('inf'), float('inf'), float('inf')
    max_x, max_y, max_z = float('-inf'), float('-inf'), float('-inf')

    for conn in elements.values():
        for nid in conn:
            coord = nodes.get(nid)
            if coord is None:
                continue
            x, y, z = coord
            min_x = min(min_x, x)
            max_x = max(max_x, x)
            min_y = min(min_y, y)
            max_y = max(max_y, y)
            min_z = min(min_z, z)
            max_z = max(max_z, z)

    return {
        "min_x": min_x,
        "max_x": max_x,
        "min_y": min_y,
        "max_y": max_y,
        "min_z": min_z,
        "max_z": max_z
    }

def extract_surface_triangles(elements: dict, types: dict):
    """
    C++ optimized triangle extraction from solids.
    Return: list of triangle [n1, n2, n3]
    """
    return cpp_parser.extract_surface_triangles_cpp(elements, types)


if __name__ == "__main__":
    current_dir = os.path.dirname(os.path.abspath(__file__))
    #fileName = os.path.join(current_dir, "test_001_DA_A_4_B_3.k")
    fileName = os.path.join(current_dir, "MiddleModel.k")
    parsed = parse_filename(fileName)
    parsed = parse_kfile(fileName, "1")
    nodes = parse_kfile_nodes(fileName)
    parsed = parse_kfile_elements_of_partid_and_nodes(fileName, "1")
    parsed = get_boundary_box_of_given_partid_and_nodes(fileName, "1", nodes)
    parsed = get_boundary_box_of_given_partid(fileName, "1")



    filesText = open(fileName, "r").read()
    parsed = parse_dyna_file_pid(filesText)
    
    print(parsed)