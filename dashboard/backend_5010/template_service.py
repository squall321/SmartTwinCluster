"""
Template Service for Apptainer Command Template Integration

Provides API endpoints for saving and loading job templates
that include Apptainer command template configurations.

Features:
- Save job templates with Apptainer template references
- Load templates with full command template details
- Update template usage count
- List user templates
"""

from flask import Blueprint, request, jsonify
import sqlite3
import json
import uuid
from datetime import datetime
from pathlib import Path

# Blueprint setup
template_bp = Blueprint('template', __name__, url_prefix='/api/templates')

# Database path
DB_PATH = Path(__file__).parent / 'database' / 'dashboard.db'


def get_db_connection():
    """Get SQLite database connection"""
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    return conn


@template_bp.route('/', methods=['GET'])
def list_templates():
    """
    List all job templates

    Query params:
    - category: Filter by category (optional)
    - shared: Filter by shared status (optional)
    - user_id: Filter by user (optional)
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Build query based on filters
        query = "SELECT * FROM templates WHERE 1=1"
        params = []

        if 'category' in request.args:
            query += " AND category = ?"
            params.append(request.args['category'])

        if 'shared' in request.args:
            shared = 1 if request.args['shared'].lower() == 'true' else 0
            query += " AND shared = ?"
            params.append(shared)

        if 'user_id' in request.args:
            query += " AND created_by = ?"
            params.append(request.args['user_id'])

        query += " ORDER BY usage_count DESC, updated_at DESC"

        cursor.execute(query, params)
        rows = cursor.fetchall()

        templates = []
        for row in rows:
            template_dict = dict(row)

            # Parse JSON fields
            if template_dict.get('config'):
                try:
                    template_dict['config'] = json.loads(template_dict['config'])
                except:
                    pass

            if template_dict.get('custom_values'):
                try:
                    template_dict['custom_values'] = json.loads(template_dict['custom_values'])
                except:
                    pass

            templates.append(template_dict)

        conn.close()

        return jsonify({
            'success': True,
            'templates': templates,
            'count': len(templates)
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@template_bp.route('/<template_id>', methods=['GET'])
def get_template(template_id):
    """
    Get a specific template by ID

    If template has Apptainer references, includes full command template details
    """
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Get template
        cursor.execute("SELECT * FROM templates WHERE id = ?", (template_id,))
        row = cursor.fetchone()

        if not row:
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Template not found'
            }), 404

        template = dict(row)

        # Parse JSON fields
        if template.get('config'):
            try:
                template['config'] = json.loads(template['config'])
            except:
                pass

        if template.get('custom_values'):
            try:
                template['custom_values'] = json.loads(template['custom_values'])
            except:
                pass

        # If has Apptainer references, get full details
        if template.get('apptainer_image_id'):
            cursor.execute(
                "SELECT * FROM apptainer_images WHERE id = ?",
                (template['apptainer_image_id'],)
            )
            image_row = cursor.fetchone()

            if image_row:
                image_dict = dict(image_row)

                # Parse command_templates
                if image_dict.get('command_templates'):
                    try:
                        command_templates = json.loads(image_dict['command_templates'])
                        image_dict['command_templates'] = command_templates

                        # Find the specific template
                        if template.get('apptainer_template_id'):
                            for cmd_template in command_templates:
                                if cmd_template.get('template_id') == template['apptainer_template_id']:
                                    template['apptainer_command_template'] = cmd_template
                                    break
                    except:
                        pass

                template['apptainer_image'] = image_dict

        conn.close()

        return jsonify({
            'success': True,
            'template': template
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@template_bp.route('/', methods=['POST'])
def create_template():
    """
    Create a new job template

    Request body:
    {
        "name": "My Template",
        "description": "Description",
        "category": "simulation",
        "shared": false,
        "config": {...},  # Job configuration
        "created_by": "user_id",
        "apptainer_template_id": "template_id",  # Optional
        "apptainer_image_id": "image_id",  # Optional
        "custom_values": {...}  # Optional custom variable values
    }
    """
    try:
        data = request.json

        # Validate required fields
        if not data.get('name'):
            return jsonify({
                'success': False,
                'error': 'Name is required'
            }), 400

        if not data.get('config'):
            return jsonify({
                'success': False,
                'error': 'Config is required'
            }), 400

        # Generate ID
        template_id = f"tpl-{uuid.uuid4().hex[:12]}"

        # Prepare data
        config_json = json.dumps(data['config'])
        custom_values_json = json.dumps(data.get('custom_values', {})) if data.get('custom_values') else None

        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("""
            INSERT INTO templates (
                id, name, description, category, shared, config,
                created_by, apptainer_template_id, apptainer_image_id,
                custom_values, created_at, updated_at, usage_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            template_id,
            data['name'],
            data.get('description', ''),
            data.get('category', 'custom'),
            1 if data.get('shared') else 0,
            config_json,
            data.get('created_by', 'unknown'),
            data.get('apptainer_template_id'),
            data.get('apptainer_image_id'),
            custom_values_json,
            datetime.now().isoformat(),
            datetime.now().isoformat(),
            0
        ))

        conn.commit()
        conn.close()

        return jsonify({
            'success': True,
            'template_id': template_id,
            'message': 'Template created successfully'
        }), 201

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@template_bp.route('/<template_id>', methods=['PUT'])
def update_template(template_id):
    """
    Update an existing template

    Request body: Same as create_template
    """
    try:
        data = request.json

        conn = get_db_connection()
        cursor = conn.cursor()

        # Check if template exists
        cursor.execute("SELECT id FROM templates WHERE id = ?", (template_id,))
        if not cursor.fetchone():
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Template not found'
            }), 404

        # Build update query
        update_fields = []
        params = []

        if 'name' in data:
            update_fields.append("name = ?")
            params.append(data['name'])

        if 'description' in data:
            update_fields.append("description = ?")
            params.append(data['description'])

        if 'category' in data:
            update_fields.append("category = ?")
            params.append(data['category'])

        if 'shared' in data:
            update_fields.append("shared = ?")
            params.append(1 if data['shared'] else 0)

        if 'config' in data:
            update_fields.append("config = ?")
            params.append(json.dumps(data['config']))

        if 'apptainer_template_id' in data:
            update_fields.append("apptainer_template_id = ?")
            params.append(data['apptainer_template_id'])

        if 'apptainer_image_id' in data:
            update_fields.append("apptainer_image_id = ?")
            params.append(data['apptainer_image_id'])

        if 'custom_values' in data:
            update_fields.append("custom_values = ?")
            params.append(json.dumps(data['custom_values']))

        # Always update updated_at
        update_fields.append("updated_at = ?")
        params.append(datetime.now().isoformat())

        # Add template_id to params
        params.append(template_id)

        query = f"UPDATE templates SET {', '.join(update_fields)} WHERE id = ?"
        cursor.execute(query, params)

        conn.commit()
        conn.close()

        return jsonify({
            'success': True,
            'message': 'Template updated successfully'
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@template_bp.route('/<template_id>', methods=['DELETE'])
def delete_template(template_id):
    """Delete a template"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute("DELETE FROM templates WHERE id = ?", (template_id,))

        if cursor.rowcount == 0:
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Template not found'
            }), 404

        conn.commit()
        conn.close()

        return jsonify({
            'success': True,
            'message': 'Template deleted successfully'
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


@template_bp.route('/<template_id>/use', methods=['POST'])
def increment_usage(template_id):
    """Increment template usage count"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        cursor.execute(
            "UPDATE templates SET usage_count = usage_count + 1 WHERE id = ?",
            (template_id,)
        )

        if cursor.rowcount == 0:
            conn.close()
            return jsonify({
                'success': False,
                'error': 'Template not found'
            }), 404

        conn.commit()
        conn.close()

        return jsonify({
            'success': True,
            'message': 'Usage count incremented'
        })

    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500


def register_blueprint(app):
    """Register blueprint with Flask app"""
    app.register_blueprint(template_bp)
