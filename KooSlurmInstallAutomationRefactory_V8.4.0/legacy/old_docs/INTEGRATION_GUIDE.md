# 🎉 Slurm 클러스터 관리 시스템 완전 통합 가이드

## 전체 시스템 구성

```
KooSlurmInstallAutomation/
├── src/                          # Python 설치 자동화
│   ├── slurm_installer.py
│   ├── slurm_cleanup.py
│   └── container_support.py
├── dashboard/                    # React 관리 대시보드
│   ├── src/
│   │   ├── components/
│   │   ├── store/
│   │   └── data/
│   └── backend/
│       └── app.py               # Flask API
└── docs/                        # 문서
    ├── SLURM_SCHEDULER_GROUPS.md
    └── INTEGRATION_GUIDE.md
```

## 🚀 빠른 시작 (5분 안에!)

```bash
# 1. Slurm 설치 (370 노드)
./install_slurm.py -c examples/370node_cluster.yaml --stage all

# 2. 대시보드 설치
cd dashboard && ./setup.sh

# 3. 대시보드 실행
./run.sh

# 4. 브라우저 접속
# http://localhost:3000
```

## 📊 시스템 특징

✅ **370개 노드 자동 구성**
✅ **6개 그룹으로 분할**  
✅ **드래그 앤 드롭 UI**
✅ **실시간 Slurm 반영**
✅ **코어 제한 관리**
✅ **백업 및 롤백**

자세한 내용은 각 섹션을 참조하세요!
