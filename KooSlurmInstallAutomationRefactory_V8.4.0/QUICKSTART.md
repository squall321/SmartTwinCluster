# Multi-Head HPC Cluster - Quick Start Guide

빠르게 클러스터를 구축하고 테스트하기 위한 간단한 가이드입니다.

## 5분 요약

```bash
# 1. 프로젝트 복사 (모든 노드)
rsync -avz . root@node:/path/

# 2. 설정 작성
vim my_multihead_cluster.yaml

# 3. 환경변수
export DB_ROOT_PASSWORD='pass'

# 4. 구축
sudo -E ./cluster/start_multihead.sh

# 5. 테스트
./cluster/test_cluster.sh
```

자세한 내용은 [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) 참조
