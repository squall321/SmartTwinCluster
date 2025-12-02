#!/usr/bin/env python3
"""
Check template config JSON in database
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
print("Check Template Config JSON")
print("=" * 60)
print()

cursor.execute("SELECT id, name, config FROM templates")
templates = cursor.fetchall()

for tpl in templates:
    tpl_id, name, config_str = tpl
    print(f"Template: {name} ({tpl_id})")
    print("-" * 60)
    
    try:
        # Try to parse JSON
        config = json.loads(config_str)
        print("✅ JSON is valid")
        print(f"   Keys: {list(config.keys())}")
    except json.JSONDecodeError as e:
        print(f"❌ JSON parsing error: {e}")
        print(f"   Position: {e.pos}")
        print(f"   Config string (first 500 chars):")
        print(f"   {config_str[:500]}")
        print()
        print(f"   Around error position:")
        start = max(0, e.pos - 50)
        end = min(len(config_str), e.pos + 50)
        print(f"   ...{config_str[start:end]}...")
    
    print()

conn.close()
