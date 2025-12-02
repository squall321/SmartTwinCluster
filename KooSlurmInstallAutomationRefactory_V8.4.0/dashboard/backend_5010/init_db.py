#!/usr/bin/env python3
"""
데이터베이스 초기화 스크립트
"""

import sys
import os

# 현재 디렉토리를 Python path에 추가
sys.path.insert(0, os.path.dirname(__file__))

from database import init_database, DB_PATH

if __name__ == "__main__":
    print("=" * 60)
    print("Database Initialization")
    print("=" * 60)
    print(f"Database path: {DB_PATH}")
    print("")
    
    # 데이터베이스 파일이 이미 존재하는지 확인
    if os.path.exists(DB_PATH):
        response = input("Database already exists. Reset? (y/N): ")
        if response.lower() == 'y':
            os.remove(DB_PATH)
            print("✅ Existing database removed")
    
    # 초기화
    init_database()
    
    print("")
    print("=" * 60)
    print("Database initialized successfully!")
    print("=" * 60)
