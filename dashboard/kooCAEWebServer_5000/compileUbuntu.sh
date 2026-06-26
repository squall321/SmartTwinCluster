#!/bin/bash
# KooCAE 웹서버 Ubuntu 빌드 스크립트

cd build

# pybind11 설치
pip install pybind11

# 빌드
python setup.py build_ext --inplace

# 빌드 산출물 복사
cp KooCAE*.so ../app/services/

cd ..
echo "Build complete!"
