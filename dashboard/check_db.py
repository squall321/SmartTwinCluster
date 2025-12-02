#!/usr/bin/env python3
"""
Check database contents
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
print("Database Contents Check")
print("=" * 60)
print()

# Check templates table
cursor.execute("SELECT COUNT(*) FROM templates")
count = cursor.fetchone()[0]
print(f"Total templates in database: {count}")
print()

if count > 0:
    cursor.execute("SELECT id, name, category, shared FROM templates ORDER BY id")
    templates = cursor.fetchall()
    
    print("Templates:")
    print("-" * 60)
    for tpl in templates:
        print(f"  ID: {tpl[0]}")
        print(f"  Name: {tpl[1]}")
        print(f"  Category: {tpl[2]}")
        print(f"  Shared: {bool(tpl[3])}")
        print("-" * 60)
else:
    print("⚠️  No templates found in database!")

conn.close()
