#!/usr/bin/env python3
"""
DB 정리 스크립트 - 실제 존재하는 이미지만 남기기
"""
import sqlite3
import os

DB_PATH = '/home/koopark/web_services/backend/dashboard.db'

def cleanup_database():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # 현재 이미지 조회
    cursor.execute("SELECT id, name, path FROM apptainer_images")
    images = cursor.fetchall()

    print("=== 현재 DB의 이미지 목록 ===")
    for img_id, name, path in images:
        print(f"  {img_id}: {name} -> {path}")

    # 더미/테스트 이미지 삭제
    to_delete = ['compute002', 'viz001', 'viz002', 'alpine_latest', 'python_3.11']

    print("\n=== 삭제할 이미지 ===")
    for img_id in to_delete:
        print(f"  - {img_id}")

    cursor.execute(f"DELETE FROM apptainer_images WHERE id IN ({','.join(['?']*len(to_delete))})", to_delete)

    # KooSimulationPython313 업데이트 (설명 변경)
    cursor.execute("""
        UPDATE apptainer_images
        SET description = '전각도 낙하 시뮬레이션 자동화',
            partition = 'compute',
            type = 'compute'
        WHERE id = 'compute001'
    """)

    conn.commit()

    # 결과 확인
    cursor.execute("SELECT id, name, description, partition FROM apptainer_images")
    remaining = cursor.fetchall()

    print("\n=== 남은 이미지 ===")
    for img_id, name, desc, partition in remaining:
        print(f"  {img_id}: {name} ({partition})")
        print(f"    설명: {desc}")

    conn.close()
    print("\n✅ DB 정리 완료!")

if __name__ == "__main__":
    cleanup_database()
