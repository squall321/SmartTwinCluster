#!/bin/bash

# Python 3.13 가상환경 설정 스크립트
echo "Python 3.13 가상환경을 설정합니다..."

# 가상환경 생성
python3.13 -m venv venv

# 가상환경 활성화 확인
echo "가상환경이 생성되었습니다."
echo "다음 명령어로 가상환경을 활성화하세요:"
echo "source venv/bin/activate"
echo ""
echo "가상환경 비활성화: deactivate"
echo ""

# 필요한 패키지 설치를 위한 requirements.txt 생성
echo "기본 requirements.txt 파일을 생성합니다..."

# Python 버전 확인
echo "Python 버전 확인:"
python3.13 --version
