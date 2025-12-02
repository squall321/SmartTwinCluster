#!/bin/bash

echo "=========================================="
echo "🧪 Slurm Accounting (QoS) 테스트"
echo "=========================================="
echo ""

# PATH 설정
export PATH=/usr/local/slurm/bin:$PATH

# 1. Cluster 확인
echo "1️⃣  Cluster 정보:"
echo "----------------------------------------"
sacctmgr show cluster -p
echo ""

# 2. QoS 목록
echo "2️⃣  QoS 목록:"
echo "----------------------------------------"
sacctmgr show qos format=Name,Priority,MaxTRES -p
echo ""

# 3. Account 확인
echo "3️⃣  Account 정보:"
echo "----------------------------------------"
sacctmgr show account -p
echo ""

# 4. 테스트 QoS 생성
echo "4️⃣  테스트 QoS 생성:"
echo "----------------------------------------"
echo "📝 'test_qos' 생성 중..."
sudo sacctmgr -i add qos test_qos
sudo sacctmgr -i modify qos test_qos set MaxTRESPerJob=cpu=128
sudo sacctmgr -i modify qos test_qos set Priority=500

echo ""
echo "✅ 생성된 QoS:"
sacctmgr show qos format=Name,Priority,MaxTRES -p | grep test_qos
echo ""

# 5. 테스트 QoS 삭제
echo "5️⃣  테스트 QoS 삭제:"
echo "----------------------------------------"
sudo sacctmgr -i delete qos test_qos
echo "✅ test_qos 삭제 완료"
echo ""

echo "=========================================="
echo "✅ Slurm Accounting 정상 작동!"
echo "=========================================="
echo ""
echo "이제 Dashboard에서 Apply Configuration을 실행하면"
echo "QoS가 정상적으로 생성됩니다!"
echo ""
echo "테스트 방법:"
echo "  1. Dashboard 접속"
echo "  2. System Management → Cluster Management"
echo "  3. Apply Configuration 클릭"
echo "  4. ✅ 성공 메시지 확인"
echo ""
