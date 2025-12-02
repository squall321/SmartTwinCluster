#!/usr/bin/env python3
"""
DB Migration: Add command_templates column
Date: 2025-11-10
"""

import sqlite3
import os
import sys

DB_PATH = '/home/koopark/web_services/backend/dashboard.db'

def check_column_exists(cursor, table_name, column_name):
    """Check if a column exists in a table"""
    cursor.execute(f"PRAGMA table_info({table_name})")
    columns = [row[1] for row in cursor.fetchall()]
    return column_name in columns

def run_migration():
    """Run the migration to add command_templates column"""
    print("=" * 60)
    print("DB Migration: Add command_templates column")
    print("=" * 60)

    if not os.path.exists(DB_PATH):
        print(f"❌ Error: Database not found at {DB_PATH}")
        return False

    try:
        # Connect to database
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        # Check if column already exists
        if check_column_exists(cursor, 'apptainer_images', 'command_templates'):
            print("✅ Column 'command_templates' already exists")
            print("   No migration needed")
            conn.close()
            return True

        print("📝 Adding 'command_templates' column to apptainer_images table...")

        # Add the column
        cursor.execute("""
            ALTER TABLE apptainer_images
            ADD COLUMN command_templates TEXT DEFAULT '[]'
        """)

        # Commit the changes
        conn.commit()

        # Verify the column was added
        if check_column_exists(cursor, 'apptainer_images', 'command_templates'):
            print("✅ Migration successful!")
            print("   Column 'command_templates' added to apptainer_images table")

            # Show table schema
            cursor.execute("PRAGMA table_info(apptainer_images)")
            columns = cursor.fetchall()
            print("\n📊 Current table schema:")
            for col in columns:
                print(f"   - {col[1]} ({col[2]})")

            conn.close()
            return True
        else:
            print("❌ Migration failed: Column not found after ALTER TABLE")
            conn.close()
            return False

    except sqlite3.Error as e:
        print(f"❌ Database error: {e}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

if __name__ == '__main__':
    success = run_migration()
    sys.exit(0 if success else 1)
