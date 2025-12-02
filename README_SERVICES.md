# 🚀 HPC 클러스터 서비스 관리 - 빠른 시작 가이드

## 📦 전체 시스템 구성

```
HPC 클러스터 전체 시스템
├── Slurm 클러스터 (컴퓨팅)
│   ├── Controller (smarttwincluster)
│   │   ├── Munge (인증)
│   │   ├── MariaDB (데이터베이스)
│   │   ├── slurmdbd (DB 데몬)
│   │   └── slurmctld (컨트롤러)
│   └── Compute Nodes (node001, node002, viz-node001)
│       ├── Munge (인증)
│       └── slurmd (컴퓨트 데몬)
└── 웹 대시보드 (관리/모니터링)
    ├── Frontend (React, 포트 80/3010)
    ├── Backend API (FastAPI, 포트 5010)
    ├── Prometheus (메트릭, 포트 9090)
    └── Node Exporter (시스템, 포트 9100)
```

## ⚡ Quick Start

### 🟢 전체 시스템 시작
```bash
./start_all_services.sh
```

### 🔴 전체 시스템 정지
```bash
./stop_all_services.sh
```

### 🔄 전체 재시작
```bash
./stop_all_services.sh && sleep 5 && ./start_all_services.sh
```

## 📋 스크립트 목록

### 통합 관리 (전체 시스템)
| 스크립트 | 설명 | 포함 서비스 |
|---------|------|------------|
| `start_all_services.sh` | 전체 시스템 시작 | Slurm + 웹 대시보드 |
| `stop_all_services.sh` | 전체 시스템 정지 | Slurm + 웹 대시보드 |

### Slurm 관리 (클러스터만)
| 스크립트 | 설명 | 포함 서비스 |
|---------|------|------------|
| `start_slurm_services.sh` | Slurm 서비스 시작 | Munge, slurmdbd, slurmctld, slurmd |
| `stop_slurm_services.sh` | Slurm 서비스 정지 | 위와 동일 |

### 웹 대시보드 관리 (웹만)
| 스크립트 | 설명 | 포함 서비스 |
|---------|------|------------|
| `start.sh` | 웹 대시보드 시작 | Frontend, Backend, Prometheus |
| `start.sh --mock` | Mock 모드 시작 | 테스트 데이터로 실행 |
| `stop.sh` | 웹 대시보드 정지 | 모든 웹 서비스 |

## 🎯 사용 시나리오

### 1️⃣ 정상 운영 (모든 서비스 필요)
```bash
./start_all_services.sh       # 시작
./stop_all_services.sh        # 정지
```

### 2️⃣ Slurm만 사용 (웹 불필요)
```bash
./start_slurm_services.sh     # Slurm만 시작
./stop_slurm_services.sh      # Slurm만 정지
```

### 3️⃣ 웹 개발/테스트 (Slurm 불필요)
```bash
./start.sh --mock             # Mock 모드로 웹만 시작
./stop.sh                     # 웹만 정지
```

### 4️⃣ Slurm 유지하고 웹만 재시작
```bash
./stop.sh                     # 웹만 정지
./start.sh                    # 웹만 시작
```

### 5️⃣ 웹 유지하고 Slurm만 재시작
```bash
./stop_slurm_services.sh      # Slurm만 정지
./start_slurm_services.sh     # Slurm만 시작
```

## 🔧 고급 옵션

### start_all_services.sh 옵션
```bash
./start_all_services.sh              # 전체 시작 (기본)
./start_all_services.sh --mock       # 웹만 Mock 모드로
./start_all_services.sh --skip-slurm # Slurm 건너뛰기
./start_all_services.sh --skip-web   # 웹 건너뛰기
```

### stop_all_services.sh 옵션
```bash
./stop_all_services.sh               # 전체 정지 (확인 필요)
./stop_all_services.sh --force       # 강제 정지 (확인 없이)
./stop_all_services.sh --skip-slurm  # Slurm 건너뛰기
./stop_all_services.sh --skip-web    # 웹 건너뛰기
```

## 📊 상태 확인

### Slurm 상태
```bash
sinfo                    # 노드 상태
squeue                   # 작업 큐
scontrol show node       # 노드 상세
```

### 웹 서비스 상태
```bash
lsof -i :5010           # Backend API
lsof -i :9090           # Prometheus
lsof -i :9100           # Node Exporter
```

### 시스템 서비스 상태
```bash
sudo systemctl status slurmctld slurmdbd munge
```

## 🌐 웹 접속

### Production Mode
- **Frontend**: http://localhost (Nginx)
- **Backend API**: http://localhost:5010
- **Prometheus**: http://localhost:9090

### Development/Mock Mode
- **Frontend**: http://localhost:3010 (Vite dev server)
- **Backend API**: http://localhost:5010 (Mock data)

## 🆘 문제 해결

### 시작 안 될 때
```bash
# 로그 확인
sudo journalctl -u slurmctld -n 50
tail -f dashboard/backend_5010/logs/error.log

# 포트 충돌 확인
lsof -i -P -n | grep LISTEN
```

### 정지 안 될 때
```bash
# 강제 종료
sudo pkill -9 slurmctld slurmdbd slurmd
pkill -9 -f "python.*backend"
pkill -9 prometheus
```

## 📚 상세 문서

- **전체 시스템**: [SYSTEM_MANAGEMENT.md](SYSTEM_MANAGEMENT.md)
- **Slurm 전용**: [SLURM_SERVICE_MANAGEMENT.md](SLURM_SERVICE_MANAGEMENT.md)

## 💡 팁

1. **시스템 재부팅 후**: `./start_all_services.sh`
2. **테스트 먼저**: `./start.sh --mock`로 웹 먼저 테스트
3. **로그 모니터링**: `sudo journalctl -u slurmctld -f`
4. **긴급 정지**: `./stop_all_services.sh --force`

---

**생성된 파일**: 2025-10-24
**버전**: 1.0
