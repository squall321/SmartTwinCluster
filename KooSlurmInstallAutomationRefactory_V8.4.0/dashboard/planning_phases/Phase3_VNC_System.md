# Phase 3: VNC 시각화 시스템 개발

**기간**: 2주 (10일)
**목표**: Apptainer 기반 GPU VNC 원격 데스크톱 시스템 구축
**선행 조건**: Phase 0, 2 완료
**담당자**: Backend 개발자 + DevOps + Frontend 개발자

---

## 📋 목차

1. [개요](#개요)
2. [Week 1: Apptainer 이미지 및 Slurm 통합](#week-1-apptainer-이미지-및-slurm-통합)
3. [Week 2: VNC API 및 Frontend 구현](#week-2-vnc-api-및-frontend-구현)
4. [검증 체크리스트](#검증-체크리스트)
5. [트러블슈팅](#트러블슈팅)

---

## 개요

### 아키텍처
```
User → ServiceMenu → VNC 선택
    ↓
VncSessions 페이지 (frontend_3010/vnc)
    ↓
POST /api/vnc/sessions (backend_5010)
    ↓
Sandbox 복사 + Slurm Job 제출
    ↓
Job Running → VNC 서버 시작
    ↓
noVNC WebSocket → VNC 서버
```

---

## Week 1: Apptainer 이미지 및 Slurm 통합

### Day 1-3: VNC 이미지 정의 및 빌드

#### 목표
TurboVNC + VirtualGL + GPU 지원 Apptainer 이미지 생성

#### ubuntu_vnc_gpu.def 작성
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/apptainers

cat > ubuntu_vnc_gpu.def << 'EOF'
Bootstrap: docker
From: ubuntu:22.04

%post
    # 기본 패키지
    apt-get update && apt-get install -y \
        wget curl vim git \
        xfce4 xfce4-goodies \
        firefox tigervnc-standalone-server \
        websockify python3-numpy \
        mesa-utils \
        && apt-get clean

    # TurboVNC 설치
    wget https://sourceforge.net/projects/turbovnc/files/3.1/turbovnc_3.1_amd64.deb
    dpkg -i turbovnc_3.1_amd64.deb || apt-get -f install -y
    rm turbovnc_3.1_amd64.deb

    # VirtualGL 설치
    wget https://sourceforge.net/projects/virtualgl/files/3.1/virtualgl_3.1_amd64.deb
    dpkg -i virtualgl_3.1_amd64.deb || apt-get -f install -y
    rm virtualgl_3.1_amd64.deb

    # noVNC 설치
    git clone https://github.com/novnc/noVNC.git /opt/noVNC
    git clone https://github.com/novnc/websockify /opt/noVNC/utils/websockify

%environment
    export PATH=/opt/TurboVNC/bin:$PATH
    export VGL_DISPLAY=:0

%runscript
    exec /bin/bash "$@"
EOF
```

#### 이미지 빌드
```bash
sudo apptainer build ubuntu_vnc_gpu.sif ubuntu_vnc_gpu.def

# 템플릿 샌드박스 생성
sudo apptainer build --sandbox \
  /scratch/apptainer_sandboxes/vnc_template \
  ubuntu_vnc_gpu.sif

sudo chown -R slurm:slurm /scratch/apptainer_sandboxes/vnc_template
```

---

### Day 4-5: Slurm Job 스크립트

#### VNC Job 템플릿
```bash
# backend_5010/templates/vnc_job.sh
cat > templates/vnc_job_template.sh << 'EOF'
#!/bin/bash
#SBATCH --job-name=vnc_{{SESSION_ID}}
#SBATCH --partition=vnc
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem={{MEMORY_GB}}G
#SBATCH --time={{TIME_HOURS}}:00:00
#SBATCH --output={{LOG_PATH}}/vnc_%j.out
#SBATCH --error={{LOG_PATH}}/vnc_%j.err

SANDBOX_PATH="{{SANDBOX_PATH}}"
VNC_PORT={{VNC_PORT}}
WS_PORT={{WS_PORT}}
VNC_PASSWORD="{{VNC_PASSWORD}}"
RESOLUTION="{{RESOLUTION}}"

cd $SANDBOX_PATH

# VNC 패스워드 설정
mkdir -p .vnc
echo "$VNC_PASSWORD" | vncpasswd -f > .vnc/passwd
chmod 600 .vnc/passwd

# VNC 서버 시작
apptainer exec --nv --writable . \
  vncserver :1 -geometry $RESOLUTION -SecurityTypes VncAuth

# WebSockify 시작
apptainer exec --writable . \
  websockify --web /opt/noVNC $WS_PORT localhost:$((5900 + 1)) &

# 무한 대기
while true; do sleep 60; done
EOF
```

---

## Week 2: VNC API 및 Frontend 구현

### Day 6-8: VNC 세션 API (backend_5010)

#### VNC 매니저 모듈
```python
# backend_5010/vnc_manager.py
import os
import subprocess
import redis
import json
from datetime import datetime
import secrets

class VNCManager:
    def __init__(self, redis_client):
        self.redis = redis_client
        self.sandbox_base = "/scratch/apptainer_sandboxes"
        self.template = f"{self.sandbox_base}/vnc_template"

    def create_session(self, user, gpu_count=1, memory_gb=8, time_hours=8, resolution="1920x1080"):
        # 세션 ID 생성
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        session_id = f"vnc_{user}_{timestamp}"

        # Sandbox 복사
        sandbox_path = f"{self.sandbox_base}/{session_id}"
        subprocess.run(["cp", "-r", self.template, sandbox_path], check=True)

        # VNC 포트 할당
        vnc_port = self._allocate_port(5900, 6000)
        ws_port = self._allocate_port(6000, 6100)

        # VNC 패스워드 생성
        vnc_password = secrets.token_urlsafe(12)

        # Job 스크립트 생성
        job_script = self._generate_job_script(
            session_id, sandbox_path, vnc_port, ws_port,
            vnc_password, memory_gb, time_hours, resolution
        )

        # Slurm Job 제출
        job_id = self._submit_job(job_script)

        # Redis에 세션 저장
        session_data = {
            "session_id": session_id,
            "user": user,
            "slurm_job_id": job_id,
            "sandbox_path": sandbox_path,
            "vnc_port": vnc_port,
            "websocket_port": ws_port,
            "vnc_password": vnc_password,
            "status": "pending",
            "created_at": datetime.utcnow().isoformat()
        }
        self.redis.setex(
            f"vnc:session:{session_id}",
            86400,  # 24시간 TTL
            json.dumps(session_data)
        )

        return session_data

    def _submit_job(self, job_script_path):
        result = subprocess.run(
            ["sbatch", job_script_path],
            capture_output=True, text=True, check=True
        )
        job_id = result.stdout.strip().split()[-1]
        return job_id
```

#### API 엔드포인트
```python
# backend_5010/routes/vnc.py
from flask import Blueprint, request, jsonify, g
from middleware.jwt_middleware import jwt_required, permission_required
from vnc_manager import VNCManager

vnc_bp = Blueprint('vnc', __name__)
vnc_manager = VNCManager(redis_client)

@vnc_bp.route('/api/vnc/sessions', methods=['GET'])
@jwt_required
@permission_required(['vnc.create'])
def get_sessions():
    user = g.user['username']
    # Redis에서 사용자 세션 조회
    sessions = vnc_manager.get_user_sessions(user)
    return jsonify({'sessions': sessions})

@vnc_bp.route('/api/vnc/sessions', methods=['POST'])
@jwt_required
@permission_required(['vnc.create'])
def create_session():
    user = g.user['username']
    data = request.json

    session = vnc_manager.create_session(
        user=user,
        gpu_count=data.get('gpu_count', 1),
        memory_gb=data.get('memory_gb', 8),
        time_hours=data.get('time_hours', 8),
        resolution=data.get('resolution', '1920x1080')
    )

    return jsonify(session), 201
```

---

### Day 9-10: VNC Frontend (frontend_3010)

#### VncSessions.tsx
```typescript
// src/pages/VncSessions.tsx
import { useState, useEffect } from 'react';
import apiClient from '../api/client';

const VncSessions = () => {
  const [sessions, setSessions] = useState([]);

  const createSession = async () => {
    const response = await apiClient.post('/vnc/sessions', {
      gpu_count: 1,
      memory_gb: 8,
      time_hours: 8,
      resolution: '1920x1080'
    });
    setSessions([...sessions, response.data]);
  };

  return (
    <div>
      <button onClick={createSession}>새 VNC 세션</button>
      {sessions.map(session => (
        <div key={session.session_id}>
          <h3>{session.session_id}</h3>
          <p>Status: {session.status}</p>
          <a href={`/vnc/${session.session_id}`}>Connect</a>
        </div>
      ))}
    </div>
  );
};
```

---

## 검증 체크리스트

- [ ] Apptainer VNC 이미지 빌드 성공
- [ ] VNC 서버 GPU 접근 확인
- [ ] Slurm Job 제출 성공
- [ ] VNC 세션 생성 API 동작
- [ ] noVNC WebSocket 연결 성공
- [ ] 데스크톱에서 nvidia-smi 실행

---

**Phase 3 완료!** 다음: Phase 4
