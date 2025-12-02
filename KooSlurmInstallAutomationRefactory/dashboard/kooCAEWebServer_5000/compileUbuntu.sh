#!/bin/bash

cd build

# pybind11 설치
pip install pybind11

# 빌드
python setup.py build_ext --inplace

# 빌드 산출물 복사
cp KooCAE*.so ../app/services/

cd ..
echo "Build complete!"
