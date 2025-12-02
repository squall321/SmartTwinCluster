#!/bin/bash
# 실행 권한 부여 스크립트

echo "실행 권한 부여 중..."

chmod +x pre_install_check.sh
chmod +x verify_munge.sh
chmod +x install_slurm.py
chmod +x generate_config.py
chmod +x validate_config.py
chmod +x test_connection.py
chmod +x setup_venv.sh
chmod +x make_executable.sh

echo "✅ 완료!"
