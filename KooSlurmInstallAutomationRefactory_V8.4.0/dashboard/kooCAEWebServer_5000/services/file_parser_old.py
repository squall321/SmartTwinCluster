import os 
import re

def parse_filename(filename):
    """
    Parse LS-DYNA filename into parameter dict.
    - Extract Number before DA_
    - Parse key-value pairs after DA_
    """
    name, ext = os.path.splitext(filename)
    result = {}

    # (1) Number 찾기
    # 예: ..._001_DA_
    number_match = re.search(r'_(\d+)_DA_', name)
    if number_match:
        result["Number"] = number_match.group(1)

    # (2) DA_ 뒤 파싱
    da_match = re.search(r'DA_(.+)$', name)
    if not da_match:
        return result

    param_string = da_match.group(1)
    tokens = param_string.split('_')

    for i in range(0, len(tokens) - 1, 2):
        key = tokens[i]
        try:
            val = float(tokens[i + 1])
        except ValueError:
            val = tokens[i + 1]
        result[key] = val

    return result


def parse_dyna_file_pid(text: str):
    lines = text.splitlines()
    result = []
    i = 0
    while i < len(lines):
        if lines[i].strip().lower() == '*part':
            name = ''
            pid = None
            cursor = i + 1

            while cursor < len(lines) and lines[cursor].strip().startswith('$'):
                cursor += 1
            if cursor < len(lines) and not lines[cursor].strip().startswith('*'):
                name = lines[cursor].strip()
                cursor += 1

            while cursor < len(lines) and lines[cursor].strip().startswith('$'):
                cursor += 1
            if cursor < len(lines):
                id_text = lines[cursor][:10].strip()
                try:
                    pid = int(id_text)
                except:
                    pass

            if pid is not None:
                result.append({'id': str(pid), 'name': name or 'Unnamed'})
            i = cursor
        else:
            i += 1
    return result

def parse_kfile_nodes(filepath):
    nodes = {} 
    with open(filepath, 'r') as f:
        lines = f.readlines()
        
    i = 0 
    reading_nodes = False
    while i < len(lines):
        line = lines[i].rstrip()
        if line.startswith('*NODE'):
            reading_nodes = True
            i += 1
            continue
        elif line.startswith('*'):
            reading_nodes = False
            i += 1
            continue
        elif line.startswith('$'):
            i += 1
            continue
        if reading_nodes and len(line) >= 56:        
            node_id = int(line[0:8])
            x = float(line[8:24])
            y = float(line[24:40])
            z = float(line[40:56])
            nodes[node_id] = [x, y, z]
        i += 1
    
    return nodes
    
def parse_kfile_elements_of_partid_and_nodes(filepath, target_partid):
    elements = {}
  
     
    current_elem_type = None
    reading_elements = False
    with open(filepath, 'r') as f:
        lines = f.readlines()
        
    i = 0 
    while i < len(lines):
        line = lines[i].rstrip()
        if line.startswith('*ELEMENT_'):
            reading_elements = True            
            i += 1
            continue 
        elif line.startswith('*'):
            reading_elements = False
            i += 1
            continue
        elif line.startswith('$'):
            i += 1
            continue
        
        if reading_elements:
            try:
                eid = int(line[0:8])
                pid = line[8:16].strip()
                fields = [line[j:j+8].strip() for j in range(16, len(line), 8)]
            except:
                i += 1
                continue
            
            conn = [] 
            if len(fields) == 0 or all(f.isdigit() == False for f in fields):
                i += 1
                while i < len(lines):
                    next_line = lines[i].rstrip()
                    if next_line.startswith('*'):
                        i += 1
                        break
                    elif next_line.startswith('$'):
                        i += 1
                        continue
                    conn += [int(next_line[j:j+8].strip()) for j in range(0, len(next_line), 8)
                            if next_line[j:j+8].strip().isdigit()]
                    i += 1
                    if len(conn) <8:
                        break 
            else:
                conn = [int(f) for f in fields if f.isdigit()]
                i += 1
                
            if pid == target_partid:               
                elements[eid] = conn
                
        i += 1
        
    return elements
                

def parse_kfile(filepath, target_partid):
    nodes = {}
    elements = {}
    types = {}

    current_elem_type = None
    reading_nodes = False
    reading_elements = False

    with open(filepath, 'r') as f:
        lines = f.readlines()

    i = 0
    while i < len(lines):
        line = lines[i].rstrip()

        # SECTION: Keyword 시작
        if line.startswith('*NODE'):
            reading_nodes = True
            reading_elements = False
            i += 1
            continue
        elif line.startswith('*ELEMENT_'):
            current_elem_type = line.replace('*ELEMENT_', '').lower()
            reading_elements = True
            reading_nodes = False
            i += 1
            continue
        elif line.startswith('*'):
            reading_nodes = False
            reading_elements = False
            i += 1
            continue

        # SECTION: NODE 파싱
        if reading_nodes and len(line) >= 56:
            try:
                node_id = int(line[0:8])
                x = float(line[8:24])
                y = float(line[24:40])
                z = float(line[40:56])
                nodes[node_id] = [x, y, z]
                #print(f"node_id: {node_id}, x: {x}, y: {y}, z: {z}")
            except:
                pass
            i += 1
            continue

        # SECTION: ELEMENT 파싱
        if reading_elements:
            try:
                eid = int(line[0:8])
                pid = line[8:16].strip()
                fields = [line[j:j+8].strip() for j in range(16, len(line), 8)]
            except:
                i += 1
                continue

            conn = []

            if len(fields) == 0 or all(f.isdigit() == False for f in fields):
                # CASE 1: 첫 줄에는 EID, PID만 있음 → 다음 줄부터 노드
                i += 1
                while i < len(lines):
                    next_line = lines[i].rstrip()
                    if next_line.startswith('*'):                        
                        i += 1
                        break
                    elif next_line.startswith('$'):
                        i += 1
                        continue
                    conn += [int(next_line[j:j+8].strip()) for j in range(0, len(next_line), 8)
                            if next_line[j:j+8].strip().isdigit()]
                    i += 1
                    # 다음 줄을 더 읽을지 판단 → 80칸 기준, 마지막 10 칸 데이터가 채워졌다면 계속
                    if len(conn) <8:
                        break 
                                    
            else:             
                # CASE 2: 한 줄에 노드가 일부라도 있음 → 이 줄만 처리
                conn = [int(f) for f in fields if f.isdigit()]
                i += 1
                

            if pid == target_partid:
                if current_elem_type == 'solid':
                    if len(conn) == 4 or conn[3] == conn[4]:
                        types[eid] = 'tet4' 
                    elif len(conn) == 8:
                        types[eid] = 'hexa8'
                    else:
                        types[eid] = 'solid'
                elif current_elem_type == 'shell':
                    if len(conn) == 4:
                        types[eid] = 'quad4'
                    elif len(conn) == 3:
                        types[eid] = 'tri3'
                    else:
                        types[eid] = 'shell'
                                            
                elements[eid] = conn
                
            continue

        i += 1

    return nodes, elements, types

def get_boundary_box_of_given_partid_and_nodes(filepath, target_partid, nodes):
    elements = parse_kfile_elements_of_partid_and_nodes(filepath, target_partid)
    nodesofPart = {}
    for element in elements:
        for node in elements[element]:
            nodesofPart[node] = nodes[node]
            
    min_x = min(nodesofPart[node][0] for node in nodesofPart)
    max_x = max(nodesofPart[node][0] for node in nodesofPart)
    min_y = min(nodesofPart[node][1] for node in nodesofPart)
    max_y = max(nodesofPart[node][1] for node in nodesofPart)
    min_z = min(nodesofPart[node][2] for node in nodesofPart)
    max_z = max(nodesofPart[node][2] for node in nodesofPart)
    
    return min_x, max_x, min_y, max_y, min_z, max_z

def get_boundary_box_of_given_partid(filepath, target_partid):
    nodes, elements, types = parse_kfile(filepath, target_partid)
    nodesofPart = {}
    for element in elements:
        for node in elements[element]:
            nodesofPart[node] = nodes[node]

    min_x = min(nodesofPart[node][0] for node in nodesofPart)
    max_x = max(nodesofPart[node][0] for node in nodesofPart)
    min_y = min(nodesofPart[node][1] for node in nodesofPart)
    max_y = max(nodesofPart[node][1] for node in nodesofPart)
    min_z = min(nodesofPart[node][2] for node in nodesofPart)
    max_z = max(nodesofPart[node][2] for node in nodesofPart)

    return min_x, max_x, min_y, max_y, min_z, max_z



if __name__ == "__main__":
    current_dir = os.path.dirname(os.path.abspath(__file__))
    fileName = os.path.join(current_dir, "test_001_DA_A_4_B_3.k")
    parsed = parse_filename(fileName)
    parsed = parse_kfile(fileName, "1")
    filesText = open(fileName, "r").read()
    parsed = parse_dyna_file_pid(filesText)
    
    parsed = parse_kfile_elements_of_partid_and_nodes(fileName, "1")
    nodes = parse_kfile_nodes(fileName)
    parsed = get_boundary_box_of_given_partid_and_nodes(fileName, "1", nodes)
    parsed = get_boundary_box_of_given_partid(fileName, "1")
    print(parsed)
    