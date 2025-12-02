from flask import Blueprint, jsonify
import subprocess, re, os
import utils.slurm_utils as slurm_utils  # ✅ 전체 모듈을 import

rack_bp = Blueprint("rack", __name__)

def parse_nodes():
    if slurm_utils.MOCK_MODE:
        slurm_utils._simulate_job_activity()
        nodes = []
        for node_name in slurm_utils.MOCK_NODES:
            rack = node_name[:3]
            total = 128
            running_jobs = [j for j in slurm_utils.MOCK_RUNNING if j["node"] == node_name]
            used = sum(j["cpus"] for j in running_jobs)
            nodes.append({
                "name": node_name,
                "rack": rack,
                "total": total,
                "load": float(used)
            })
        return nodes

    # 실 Slurm 환경
    result = subprocess.check_output("scontrol show node", shell=True, text=True)
    nodes = []
    for block in result.split('\n\n'):
        name_match = re.search(r'NodeName=(\S+)', block)
        cpus_match = re.search(r'CPUTot=(\d+)', block)
        load_match = re.search(r'CPULoad=(\d+\.\d+)', block)

        if name_match and cpus_match:
            name = name_match.group(1)
            rack = name[:3]
            node = {
                "name": name,
                "rack": rack,
                "total": int(cpus_match.group(1)),
                "load": float(load_match.group(1)) if load_match else 0.0
            }
            nodes.append(node)
    return nodes


@rack_bp.route("/api/rack-status", methods=["GET"])
def rack_status():
    nodes = parse_nodes()
    racks = {}
    for node in nodes:
        rack = node["rack"]
        if rack not in racks:
            racks[rack] = []
        racks[rack].append(node)
    return jsonify(racks)
