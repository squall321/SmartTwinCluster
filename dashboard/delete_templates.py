#!/usr/bin/env python3
"""
Job Template 강제 삭제 도구 (Python 버전)
"""

import sqlite3
import sys
from pathlib import Path

# Color codes
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'

DB_PATH = Path(__file__).parent / "backend_5010/database/dashboard.db"

def print_header():
    print(f"{BLUE}{'=' * 63}{NC}")
    print(f"{BLUE}         Job Template 강제 삭제 도구                        {NC}")
    print(f"{BLUE}{'=' * 63}{NC}")
    print()

def check_db():
    if not DB_PATH.exists():
        print(f"{RED}✗{NC} 데이터베이스를 찾을 수 없습니다: {DB_PATH}")
        sys.exit(1)
    print(f"{GREEN}✓{NC} SQLite DB 발견: {DB_PATH}")
    print()

def list_templates():
    """옵션 1: 모든 템플릿 목록 보기"""
    print()
    print(f"{YELLOW}현재 저장된 템플릿:{NC}")
    print()

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id, name, created_by, shared, created_at
        FROM templates
        ORDER BY created_at DESC
    """)

    rows = cursor.fetchall()

    if not rows:
        print(f"{YELLOW}⚠{NC} 저장된 템플릿이 없습니다")
    else:
        # Header
        print(f"{'ID':<40} {'Name':<30} {'Created By':<15} {'Shared':<7} {'Created At':<20}")
        print("-" * 120)

        # Data
        for row in rows:
            id_val, name, created_by, shared, created_at = row
            shared_str = "Yes" if shared else "No"
            print(f"{id_val:<40} {name:<30} {created_by or 'N/A':<15} {shared_str:<7} {created_at:<20}")

        print()
        print(f"총 {len(rows)}개의 템플릿")

    conn.close()

def delete_template_by_id():
    """옵션 2: 특정 템플릿 삭제 (ID로)"""
    template_id = input("삭제할 템플릿 ID: ").strip()

    if not template_id:
        print(f"{RED}✗{NC} 템플릿 ID를 입력해주세요")
        return

    print()
    confirm = input(f"정말로 템플릿 '{template_id}'를 삭제하시겠습니까? (yes/no): ").strip()

    if confirm != "yes":
        print("취소되었습니다")
        return

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("DELETE FROM templates WHERE id = ?", (template_id,))
    affected = cursor.rowcount

    conn.commit()
    conn.close()

    if affected > 0:
        print(f"{GREEN}✓{NC} 템플릿이 삭제되었습니다")
    else:
        print(f"{YELLOW}⚠{NC} 템플릿을 찾을 수 없습니다")

def delete_all_templates():
    """옵션 3: 모든 템플릿 삭제 (위험!)"""
    print()
    print(f"{RED}⚠ 경고: 모든 템플릿이 삭제됩니다!{NC}")
    confirm = input("정말로 모든 템플릿을 삭제하시겠습니까? (DELETE-ALL 입력): ").strip()

    if confirm != "DELETE-ALL":
        print("취소되었습니다")
        return

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT COUNT(*) FROM templates")
    count = cursor.fetchone()[0]

    cursor.execute("DELETE FROM templates")

    conn.commit()
    conn.close()

    print(f"{GREEN}✓{NC} {count}개의 템플릿이 삭제되었습니다")

def delete_by_user():
    """옵션 4: 특정 사용자의 템플릿 삭제"""
    username = input("삭제할 사용자 이름 (created_by): ").strip()

    if not username:
        print(f"{RED}✗{NC} 사용자 이름을 입력해주세요")
        return

    print()
    print(f"{YELLOW}해당 사용자의 템플릿:{NC}")

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT id, name, created_at
        FROM templates
        WHERE created_by = ?
        ORDER BY created_at DESC
    """, (username,))

    rows = cursor.fetchall()

    if not rows:
        print(f"{YELLOW}⚠{NC} 해당 사용자의 템플릿이 없습니다")
        conn.close()
        return

    # Header
    print(f"{'ID':<40} {'Name':<30} {'Created At':<20}")
    print("-" * 90)

    # Data
    for row in rows:
        id_val, name, created_at = row
        print(f"{id_val:<40} {name:<30} {created_at:<20}")

    print()
    print(f"총 {len(rows)}개의 템플릿")
    confirm = input("모두 삭제하시겠습니까? (yes/no): ").strip()

    if confirm != "yes":
        print("취소되었습니다")
        conn.close()
        return

    cursor.execute("DELETE FROM templates WHERE created_by = ?", (username,))

    conn.commit()
    conn.close()

    print(f"{GREEN}✓{NC} {len(rows)}개의 템플릿이 삭제되었습니다")

def main():
    print_header()
    check_db()

    print("삭제 옵션:")
    print("  1) 모든 템플릿 목록 보기")
    print("  2) 특정 템플릿 삭제 (ID로)")
    print("  3) 모든 템플릿 삭제 (위험!)")
    print("  4) 특정 사용자의 템플릿 삭제")
    print()

    choice = input("선택 (1-4): ").strip()

    try:
        if choice == "1":
            list_templates()
        elif choice == "2":
            delete_template_by_id()
        elif choice == "3":
            delete_all_templates()
        elif choice == "4":
            delete_by_user()
        else:
            print(f"{RED}✗{NC} 잘못된 선택입니다")
            sys.exit(1)

        print()
        print(f"{GREEN}완료!{NC}")

    except Exception as e:
        print(f"{RED}✗{NC} 오류 발생: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
