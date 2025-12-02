#!/bin/bash
################################################################################
# 새로 생성된 스크립트들에 실행 권한 부여
################################################################################

echo "🔧 실행 권한 설정 중..."

# Python 스크립트들
chmod +x fix_config.py
chmod +x install_mpi.py
chmod +x sync_apptainer_images.py
chmod +x manage_images.py

# Bash 스크립트들
chmod +x setup_cluster_full.sh
chmod +x job_templates/submit_mpi_apptainer.sh

echo "✅ 실행 권한 설정 완료!"
echo ""
echo "📋 실행 가능한 스크립트:"
echo "   - fix_config.py              (설정 파일 자동 수정)"
echo "   - install_mpi.py             (MPI 자동 설치)"
echo "   - sync_apptainer_images.py   (이미지 동기화)"
echo "   - manage_images.py           (이미지 관리)"
echo "   - setup_cluster_full.sh      (전체 자동 설치)"
echo "   - job_templates/submit_mpi_apptainer.sh  (Job 제출)"
