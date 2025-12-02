import os
import time
import random

# MOCK 환경 여부 결정
MOCK_MODE = os.environ.get("MOCK_SLURM") == "1"

# MOCK 노드 리스트 (3개의 랙, 각 9개 노드 → 총 27개)
MOCK_NODES = [f"R{str(rack).zfill(2)}N{str(n).zfill(2)}" for rack in range(1, 4) for n in range(1, 10)]

# 가상 job 저장소
MOCK_RUNNING = []
MOCK_COMPLETED = []

CORE_OPTIONS = [16, 32, 64, 128]
#DURATION_MAP = {16: 960, 32: 480, 64: 240, 128: 120}  # 초 단위: 16분, 8분, 4분, 2분
DURATION_MAP = {16: 30, 32: 20, 64: 10, 128: 5}  # 초 단위

def now(): return int(time.time())

def run_command(cmd):
    if not MOCK_MODE:
        import subprocess
        return subprocess.check_output(cmd, shell=True, text=True).strip()
    return f"[MOCK] {cmd}"

def _simulate_job_activity():
    global MOCK_RUNNING, MOCK_COMPLETED
    current = now()

    # 완료된 job 제거
    MOCK_RUNNING = [job for job in MOCK_RUNNING if not _complete_job(job, current)]

    # 전체 job 수 제한
    MAX_RUNNING = 100
    if len(MOCK_RUNNING) >= MAX_RUNNING:
        return

    # 가용 노드 리스트 생성
    available_nodes = []
    for node in MOCK_NODES:
        used = sum(j["cpus"] for j in MOCK_RUNNING if j["node"] == node)
        if used < 128:
            available_nodes.append((node, 128 - used))

    MOCK_USERS = [
        "박국진", "최윤형", "홍원선", "이태일", "유주헌", "손정한", "권경업", "김동석",
        "박세혁", "김도훈", "이동현", "곽민석", "최윤형", "김병준", "이지형", "라재연",
        "진경민", "송차규", "박창규", "김상범", "이상일", "이시훈"
    ]

    # 이름 가중치 분포 (일부 인원에 편중)
    WEIGHTED_USERS = [
        "박국진", "최윤형", "유주헌", "김도훈", "김동석", "최윤형", "박세혁", "박국진", "최윤형",
        "홍원선", "손정한", "진경민", "김병준", "유주헌", "김동석", "김동석", "김도훈", "김도훈"
    ] + MOCK_USERS  # 추가로 전체 이름도 넣음

    for node, free_cores in random.sample(available_nodes, k=min(3, len(available_nodes))):
        possible_cores = [c for c in CORE_OPTIONS if c <= free_cores]
        if not possible_cores:
            continue  # 여유가 없어 skip
        cores = random.choice(possible_cores)

        job = {
            "id": str(random.randint(10000, 99999)),
            "name": f"lsdyna_{cores}",
            "user": random.choice(WEIGHTED_USERS),
            "state": "RUNNING",
            "cpus": cores,
            "submit_time": current,
            "start_time": current,
            "duration": DURATION_MAP[cores],
            "node": node
        }
        MOCK_RUNNING.append(job)

def _complete_job(job, current_time):
    if current_time - job["start_time"] >= job["duration"]:
        job["state"] = "COMPLETED"
        job["end_time"] = current_time
        MOCK_COMPLETED.append(job)
        return True
    return False

def get_sinfo():
    if not MOCK_MODE:
        return run_command("sinfo -o '%P %A %l %D %C %m %G %T %N'")

    _simulate_job_activity()
    total_nodes = len(MOCK_NODES)

    # 각 노드별 total/used/idle 계산
    cpu_lines = []
    for node in MOCK_NODES:
        jobs = [j for j in MOCK_RUNNING if j["node"] == node]
        alloc = sum(j["cpus"] for j in jobs)
        total = 128
        idle = total - alloc
        cpu_str = f"{alloc}/{idle}/{total}/0"  # match format: alloc/idle/total/other
        cpu_lines.append(f"mock* up infinite 1 {cpu_str} - - idle {node}")

    header = "PARTITION AVAIL TIMELIMIT NODES CPU MEMORY GRES STATE NODELIST"
    return header + "\n" + "\n".join(cpu_lines)

def get_squeue():
    if not MOCK_MODE:
        return run_command("squeue -o '%i|%u|%j|%T|%C|%M|%N'")

    _simulate_job_activity()
    header = "JOBID|USER|NAME|STATE|CPUS|TIME|NODELIST"
    rows = []

    def format_time(job):
        sec = now() - job["start_time"]
        return f"{sec//3600:02}:{(sec%3600)//60:02}:{sec%60:02}"

    for job in MOCK_RUNNING + MOCK_COMPLETED[-10:]:
        rows.append(f"{job['id']}|{job['user']}|{job['name']}|{job['state']}|{job['cpus']}|{format_time(job)}|{job['node']}")
    return f"{header}\n" + "\n".join(rows)

def submit_job(script_content: str):
    if MOCK_MODE:
        return "[MOCK] Job submitted."
    with open("/tmp/job_script.sh", "w") as f:
        f.write(script_content)
    return run_command("sbatch /tmp/job_script.sh")

def cancel_job(job_id: str):
    if MOCK_MODE:
        global MOCK_RUNNING
        for job in MOCK_RUNNING:
            if job["id"] == job_id:
                job["state"] = "CANCELLED"
                job["end_time"] = now()
                MOCK_COMPLETED.append(job)
        MOCK_RUNNING = [j for j in MOCK_RUNNING if j["id"] != job_id]
        return f"[MOCK] Job {job_id} cancelled."
    return run_command(f"scancel {job_id}")

def get_lsdyna_core_usage():
    _simulate_job_activity()
    return sum(j["cpus"] for j in MOCK_RUNNING if "lsdyna" in j["name"].lower())

def get_job_stats():
    _simulate_job_activity()
    stats = {}
    for job in MOCK_COMPLETED:
        name = job["name"]
        runtime = job.get("end_time", now()) - job["start_time"]
        if name not in stats:
            stats[name] = {
                "count": 0,
                "total_runtime": 0,
                "min_runtime_sec": float('inf'),
                "max_runtime_sec": 0,
            }
        s = stats[name]
        s["count"] += 1
        s["total_runtime"] += runtime
        s["min_runtime_sec"] = min(s["min_runtime_sec"], runtime)
        s["max_runtime_sec"] = max(s["max_runtime_sec"], runtime)

    for s in stats.values():
        s["average_runtime_sec"] = round(s["total_runtime"] / s["count"], 2)
        del s["total_runtime"]

    return stats
