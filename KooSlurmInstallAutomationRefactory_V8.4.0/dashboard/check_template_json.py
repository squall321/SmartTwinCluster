#!/usr/bin/env python3
"""
Check template JSON in database
"""
import sqlite3
import json
import os

db_path = 'backend_5010/database/dashboard.db'

if not os.path.exists(db_path):
    print(f"❌ Database not found: {db_path}")
    exit(1)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

print("=" * 60)
print("Template JSON Check")
print("=" * 60)
print()

cursor.execute("SELECT id, name, config FROM templates")
templates = cursor.fetchall()

for tpl_id, name, config_str in templates:
    print(f"Template: {name} ({tpl_id})")
    print(f"Raw JSON length: {len(config_str)}")
    print(f"First 300 chars: {config_str[:300]}")
    print()
    
    try:
        config = json.loads(config_str)
        print(f"✅ Valid JSON")
        print(f"   Partition: {config.get('partition')}")
        print(f"   CPUs: {config.get('cpus')}")
    except json.JSONDecodeError as e:
        print(f"❌ JSON Parse Error: {e}")
        print(f"   Error at position: {e.pos}")
        if e.pos < len(config_str):
            start = max(0, e.pos - 20)
            end = min(len(config_str), e.pos + 20)
            print(f"   Context: ...{config_str[start:end]}...")
    
    print("-" * 60)
    print()

conn.close()
