#!/usr/bin/env python3
"""
Viz 노드 이미지 추가 스크립트
"""
import sqlite3
import os
from datetime import datetime

DB_PATH = '/home/koopark/web_services/backend/dashboard.db'

def add_viz_images():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # viz 이미지 정보
    viz_images = [
        {
            'id': 'viz001',
            'name': 'vnc_gnome.sif',
            'path': '/opt/apptainers/vnc_gnome.sif',
            'node': 'viz-node001',
            'partition': 'viz',
            'type': 'viz',
            'size': 841 * 1024 * 1024,  # 841MB
            'version': '1.0.0',
            'description': 'VNC 데스크톱 환경 (GNOME)',
            'labels': '{"display": "required", "vnc": "true"}',
            'apps': '["vncserver", "gnome-session"]',
            'runscript': '#!/bin/bash\\nvncserver :1\\n',
            'env_vars': '{"DISPLAY": ":1"}',
        },
        {
            'id': 'viz002',
            'name': 'vnc_gnome_lsprepost.sif',
            'path': '/opt/apptainers/vnc_gnome_lsprepost.sif',
            'node': 'viz-node001',
            'partition': 'viz',
            'type': 'viz',
            'size': 1300 * 1024 * 1024,  # 1.3GB
            'version': '1.0.0',
            'description': 'VNC + LS-PrePost (구조해석 후처리)',
            'labels': '{"display": "required", "vnc": "true", "fea": "true"}',
            'apps': '["vncserver", "gnome-session", "lsprepost"]',
            'runscript': '#!/bin/bash\\nvncserver :1\\n',
            'env_vars': '{"DISPLAY": ":1"}',
        },
        {
            'id': 'viz003',
            'name': 'vnc_desktop.sif',
            'path': '/opt/apptainers/vnc_desktop.sif',
            'node': 'viz-node001',
            'partition': 'viz',
            'type': 'viz',
            'size': 511 * 1024 * 1024,  # 511MB
            'version': '1.0.0',
            'description': 'VNC 데스크톱 환경 (경량)',
            'labels': '{"display": "required", "vnc": "true"}',
            'apps': '["vncserver"]',
            'runscript': '#!/bin/bash\\nvncserver :1\\n',
            'env_vars': '{"DISPLAY": ":1"}',
        }
    ]

    now = datetime.now().isoformat()

    for img in viz_images:
        cursor.execute('''
            INSERT OR REPLACE INTO apptainer_images (
                id, name, path, node, partition, type, size, version,
                description, labels, apps, runscript, env_vars,
                created_at, updated_at, last_scanned, is_active
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            img['id'], img['name'], img['path'], img['node'], img['partition'],
            img['type'], img['size'], img['version'], img['description'],
            img['labels'], img['apps'], img['runscript'], img['env_vars'],
            now, now, now, 1
        ))
        print(f"✅ 추가: {img['name']} ({img['description']})")

    conn.commit()

    # 결과 확인
    cursor.execute("SELECT id, name, description, partition FROM apptainer_images ORDER BY partition, id")
    all_images = cursor.fetchall()

    print("\n=== 전체 이미지 목록 ===")
    for img_id, name, desc, partition in all_images:
        print(f"  [{partition}] {name}")
        print(f"      {desc}")

    conn.close()
    print("\n✅ Viz 이미지 추가 완료!")

if __name__ == "__main__":
    add_viz_images()
