"""
Database Management Module
SQLite database initialization and management
"""

import sqlite3
import os
import json
from datetime import datetime
from typing import Optional, List, Dict, Any
from contextlib import contextmanager

# Database path
DB_PATH = os.path.join(os.path.dirname(__file__), '..', 'database', 'dashboard.db')
SCHEMA_PATH = os.path.join(os.path.dirname(__file__), '..', 'database', 'schema.sql')

@contextmanager
def get_db_connection():
    """Get database connection with context manager"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row  # Return rows as dictionaries
    try:
        yield conn
        conn.commit()
    except Exception as e:
        conn.rollback()
        raise e
    finally:
        conn.close()

def init_database():
    """Initialize database with schema"""
    # Create database directory if not exists
    db_dir = os.path.dirname(DB_PATH)
    if not os.path.exists(db_dir):
        os.makedirs(db_dir)
    
    # Read and execute schema
    if os.path.exists(SCHEMA_PATH):
        with open(SCHEMA_PATH, 'r') as f:
            schema_sql = f.read()
        
        with get_db_connection() as conn:
            conn.executescript(schema_sql)
        
        print(f"✅ Database initialized at {DB_PATH}")
    else:
        print(f"❌ Schema file not found: {SCHEMA_PATH}")

def reset_database():
    """Reset database (delete and recreate)"""
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
        print(f"🗑️  Deleted existing database")
    
    init_database()

# ============================================
# Notifications CRUD
# ============================================

def create_notification(
    notif_type: str,
    title: str,
    message: str,
    data: Optional[Dict] = None
) -> str:
    """Create a new notification"""
    notif_id = f"notif-{int(datetime.now().timestamp() * 1000)}"
    
    with get_db_connection() as conn:
        conn.execute("""
            INSERT INTO notifications (id, type, title, message, data)
            VALUES (?, ?, ?, ?, ?)
        """, (notif_id, notif_type, title, message, json.dumps(data) if data else None))
    
    return notif_id

def get_notifications(
    limit: int = 50,
    unread_only: bool = False
) -> List[Dict]:
    """Get notifications"""
    with get_db_connection() as conn:
        query = "SELECT * FROM notifications"
        if unread_only:
            query += " WHERE read = 0"
        query += " ORDER BY timestamp DESC LIMIT ?"
        
        cursor = conn.execute(query, (limit,))
        rows = cursor.fetchall()
        
        notifications = []
        for row in rows:
            notif = dict(row)
            # Parse JSON data
            if notif['data']:
                notif['data'] = json.loads(notif['data'])
            notifications.append(notif)
        
        return notifications

def mark_notification_read(notif_id: str) -> bool:
    """Mark notification as read"""
    with get_db_connection() as conn:
        cursor = conn.execute("""
            UPDATE notifications SET read = 1 WHERE id = ?
        """, (notif_id,))
        return cursor.rowcount > 0

def mark_all_notifications_read() -> int:
    """Mark all notifications as read"""
    with get_db_connection() as conn:
        cursor = conn.execute("UPDATE notifications SET read = 1 WHERE read = 0")
        return cursor.rowcount

def delete_notification(notif_id: str) -> bool:
    """Delete a notification"""
    with get_db_connection() as conn:
        cursor = conn.execute("DELETE FROM notifications WHERE id = ?", (notif_id,))
        return cursor.rowcount > 0

def get_unread_count() -> int:
    """Get count of unread notifications"""
    with get_db_connection() as conn:
        cursor = conn.execute("SELECT COUNT(*) FROM notifications WHERE read = 0")
        return cursor.fetchone()[0]

# ============================================
# Templates CRUD
# ============================================

def create_template(
    name: str,
    description: str,
    category: str,
    config: Dict,
    shared: bool = False,
    created_by: Optional[str] = None
) -> str:
    """Create a new job template"""
    tpl_id = f"tpl-{int(datetime.now().timestamp() * 1000)}"
    
    with get_db_connection() as conn:
        conn.execute("""
            INSERT INTO templates (id, name, description, category, config, shared, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (tpl_id, name, description, category, json.dumps(config), shared, created_by))
    
    return tpl_id

def get_templates(category: Optional[str] = None) -> List[Dict]:
    """Get templates, optionally filtered by category"""
    with get_db_connection() as conn:
        if category and category != 'all':
            cursor = conn.execute("""
                SELECT * FROM templates WHERE category = ? ORDER BY usage_count DESC
            """, (category,))
        else:
            cursor = conn.execute("SELECT * FROM templates ORDER BY usage_count DESC")
        
        rows = cursor.fetchall()
        
        templates = []
        for row in rows:
            tpl = dict(row)
            tpl['config'] = json.loads(tpl['config'])
            templates.append(tpl)
        
        return templates

def get_template(tpl_id: str) -> Optional[Dict]:
    """Get a single template"""
    with get_db_connection() as conn:
        cursor = conn.execute("SELECT * FROM templates WHERE id = ?", (tpl_id,))
        row = cursor.fetchone()
        
        if row:
            tpl = dict(row)
            tpl['config'] = json.loads(tpl['config'])
            return tpl
        return None

def update_template(tpl_id: str, **kwargs) -> bool:
    """Update a template"""
    allowed_fields = ['name', 'description', 'category', 'config', 'shared']
    updates = []
    values = []
    
    for key, value in kwargs.items():
        if key in allowed_fields:
            if key == 'config':
                value = json.dumps(value)
            updates.append(f"{key} = ?")
            values.append(value)
    
    if not updates:
        return False
    
    updates.append("updated_at = CURRENT_TIMESTAMP")
    values.append(tpl_id)
    
    with get_db_connection() as conn:
        query = f"UPDATE templates SET {', '.join(updates)} WHERE id = ?"
        cursor = conn.execute(query, values)
        return cursor.rowcount > 0

def delete_template(tpl_id: str) -> bool:
    """Delete a template"""
    with get_db_connection() as conn:
        cursor = conn.execute("DELETE FROM templates WHERE id = ?", (tpl_id,))
        return cursor.rowcount > 0

def increment_template_usage(tpl_id: str):
    """Increment template usage count"""
    with get_db_connection() as conn:
        conn.execute("""
            UPDATE templates SET usage_count = usage_count + 1 WHERE id = ?
        """, (tpl_id,))

# ============================================
# Alert Rules CRUD
# ============================================

def create_alert_rule(
    name: str,
    query: str,
    duration: str,
    severity: str,
    threshold: float,
    annotations: Dict,
    labels: Optional[Dict] = None
) -> str:
    """Create a new alert rule"""
    rule_id = f"rule-{int(datetime.now().timestamp() * 1000)}"
    
    with get_db_connection() as conn:
        conn.execute("""
            INSERT INTO alert_rules (id, name, query, duration, severity, threshold, annotations, labels)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            rule_id, name, query, duration, severity, threshold,
            json.dumps(annotations), json.dumps(labels) if labels else None
        ))
    
    return rule_id

def get_alert_rules(enabled_only: bool = False) -> List[Dict]:
    """Get alert rules"""
    with get_db_connection() as conn:
        query = "SELECT * FROM alert_rules"
        if enabled_only:
            query += " WHERE enabled = 1"
        query += " ORDER BY severity, name"
        
        cursor = conn.execute(query)
        rows = cursor.fetchall()
        
        rules = []
        for row in rows:
            rule = dict(row)
            rule['annotations'] = json.loads(rule['annotations'])
            if rule['labels']:
                rule['labels'] = json.loads(rule['labels'])
            rules.append(rule)
        
        return rules

def update_alert_rule(rule_id: str, **kwargs) -> bool:
    """Update an alert rule"""
    allowed_fields = ['name', 'query', 'duration', 'severity', 'threshold', 'enabled', 'annotations', 'labels']
    updates = []
    values = []
    
    for key, value in kwargs.items():
        if key in allowed_fields:
            if key in ['annotations', 'labels'] and isinstance(value, dict):
                value = json.dumps(value)
            updates.append(f"{key} = ?")
            values.append(value)
    
    if not updates:
        return False
    
    updates.append("updated_at = CURRENT_TIMESTAMP")
    values.append(rule_id)
    
    with get_db_connection() as conn:
        query = f"UPDATE alert_rules SET {', '.join(updates)} WHERE id = ?"
        cursor = conn.execute(query, values)
        return cursor.rowcount > 0

def delete_alert_rule(rule_id: str) -> bool:
    """Delete an alert rule"""
    with get_db_connection() as conn:
        cursor = conn.execute("DELETE FROM alert_rules WHERE id = ?", (rule_id,))
        return cursor.rowcount > 0

# ============================================
# Initialize on import
# ============================================

if __name__ == "__main__":
    # Initialize database
    print("Initializing database...")
    init_database()
    print("Done!")
else:
    # Auto-initialize if database doesn't exist
    if not os.path.exists(DB_PATH):
        init_database()
