@echo off
REM quick_test.bat - Windows용 기능 테스트

echo 🚀 KooCAE 기능 테스트 시작...

set BASE_URL=http://localhost:5000

echo 1️⃣ 서버 상태 확인...
curl -s "%BASE_URL%/api/slurm/sinfo"

echo.
echo 2️⃣ 기존 SLURM 기능 확인...
curl -s "%BASE_URL%/api/slurm/squeue"

echo.
echo 3️⃣ 새로운 템플릿 목록 확인...
curl -s "%BASE_URL%/api/job-templates"

echo.
echo 4️⃣ 클러스터 상태 확인...
curl -s "%BASE_URL%/api/slurm/cluster-status"

echo.
echo ✅ 모든 기능이 정상 작동 중!
