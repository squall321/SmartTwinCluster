#!/usr/bin/env python3
"""
Database Migration Runner
DB 마이그레이션 스크립트를 실행하는 유틸리티

Usage:
    python run_migrations.py
    python run_migrations.py --db-path /custom/path/dashboard.db
"""

import sqlite3
import os
import sys
import argparse
from pathlib import Path
from datetime import datetime


def log_info(message):
    print(f"[INFO] {message}")


def log_success(message):
    print(f"[SUCCESS] ✅ {message}")


def log_error(message):
    print(f"[ERROR] ❌ {message}")


def log_warning(message):
    print(f"[WARNING] ⚠️  {message}")


def get_applied_migrations(conn):
    """
    적용된 마이그레이션 목록 조회

    Returns:
        set: 적용된 마이그레이션 버전 집합
    """
    cursor = conn.cursor()

    # schema_migrations 테이블 존재 확인
    cursor.execute("""
        SELECT name FROM sqlite_master
        WHERE type='table' AND name='schema_migrations'
    """)

    if not cursor.fetchone():
        # 테이블이 없으면 생성
        cursor.execute("""
            CREATE TABLE schema_migrations (
                version TEXT PRIMARY KEY,
                applied_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                description TEXT
            )
        """)
        conn.commit()
        log_info("Created schema_migrations table")
        return set()

    # 적용된 마이그레이션 조회
    cursor.execute("SELECT version FROM schema_migrations")
    return {row[0] for row in cursor.fetchall()}


def apply_migration(conn, migration_file: Path):
    """
    마이그레이션 파일 실행

    Args:
        conn: DB 연결
        migration_file: 마이그레이션 SQL 파일 경로

    Returns:
        bool: 성공 여부
    """
    version = migration_file.stem  # 파일명 (확장자 제외)

    try:
        log_info(f"Applying migration: {version}")

        # SQL 파일 읽기
        with open(migration_file, 'r', encoding='utf-8') as f:
            sql = f.read()

        # SQL 실행 (여러 statement 실행)
        cursor = conn.cursor()
        cursor.executescript(sql)
        conn.commit()

        log_success(f"Migration {version} applied successfully")
        return True

    except Exception as e:
        log_error(f"Failed to apply migration {version}: {e}")
        conn.rollback()
        return False


def run_migrations(db_path: str, migrations_dir: str):
    """
    모든 마이그레이션 실행

    Args:
        db_path: SQLite DB 파일 경로
        migrations_dir: 마이그레이션 디렉토리 경로

    Returns:
        bool: 성공 여부
    """
    log_info(f"Database: {db_path}")
    log_info(f"Migrations directory: {migrations_dir}")

    # DB 경로의 디렉토리 존재 확인 및 생성
    db_dir = os.path.dirname(db_path)
    if db_dir and not os.path.exists(db_dir):
        os.makedirs(db_dir, exist_ok=True)
        log_info(f"Created directory: {db_dir}")

    # DB 연결
    try:
        conn = sqlite3.connect(db_path)
        log_info("Connected to database")
    except Exception as e:
        log_error(f"Failed to connect to database: {e}")
        return False

    try:
        # 적용된 마이그레이션 목록 조회
        applied = get_applied_migrations(conn)
        log_info(f"Applied migrations: {len(applied)}")

        # 마이그레이션 파일 목록
        migrations_path = Path(migrations_dir)
        if not migrations_path.exists():
            log_error(f"Migrations directory not found: {migrations_dir}")
            return False

        migration_files = sorted(migrations_path.glob("v*.sql"))

        if not migration_files:
            log_warning("No migration files found")
            return True

        log_info(f"Found {len(migration_files)} migration files")

        # 각 마이그레이션 실행
        applied_count = 0
        skipped_count = 0

        for migration_file in migration_files:
            version = migration_file.stem

            if version in applied:
                log_info(f"Skipping {version} (already applied)")
                skipped_count += 1
                continue

            # 마이그레이션 실행
            if apply_migration(conn, migration_file):
                applied_count += 1
            else:
                log_error(f"Migration failed: {version}")
                return False

        # 결과 출력
        print("\n" + "="*60)
        log_success("Migration completed!")
        log_info(f"Applied: {applied_count} migrations")
        log_info(f"Skipped: {skipped_count} migrations")
        print("="*60)

        return True

    except Exception as e:
        log_error(f"Migration error: {e}")
        return False

    finally:
        conn.close()
        log_info("Database connection closed")


def main():
    parser = argparse.ArgumentParser(description='Run database migrations')
    parser.add_argument(
        '--db-path',
        default=os.getenv('DATABASE_PATH', '/home/koopark/web_services/backend/dashboard.db'),
        help='Path to SQLite database file'
    )
    parser.add_argument(
        '--migrations-dir',
        default=os.path.join(os.path.dirname(__file__), 'migrations'),
        help='Path to migrations directory'
    )

    args = parser.parse_args()

    print("\n" + "="*60)
    print(" Database Migration Runner")
    print(" Dashboard v4.1.0 - Phase 1: Apptainer Discovery")
    print("="*60 + "\n")

    success = run_migrations(args.db_path, args.migrations_dir)

    if success:
        log_success("All migrations completed successfully!")
        sys.exit(0)
    else:
        log_error("Migration failed!")
        sys.exit(1)


if __name__ == '__main__':
    main()
