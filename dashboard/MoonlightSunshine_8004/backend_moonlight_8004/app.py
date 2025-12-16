"""
Moonlight/Sunshine Backend Server (Port 8004)
완전히 독립된 Flask 애플리케이션
"""

from flask import Flask, jsonify
from flask_cors import CORS
import os

# Import Moonlight API blueprint
from moonlight_api import moonlight_bp

# Create Flask app
app = Flask(__name__)
CORS(app, resources={
    r"/api/*": {
        "origins": "*",
        "methods": ["GET", "POST", "DELETE", "OPTIONS"],
        "allow_headers": ["Content-Type", "Authorization"]
    }
})

# Register blueprints
app.register_blueprint(moonlight_bp)

# Health check endpoint (both /health and /api/moonlight/health)
@app.route('/health', methods=['GET'])
@app.route('/api/moonlight/health', methods=['GET'])
def health_check():
    """Health check endpoint for monitoring"""
    return jsonify({
        'status': 'healthy',
        'service': 'moonlight_backend',
        'port': 8004
    }), 200

@app.route('/', methods=['GET'])
def index():
    """Root endpoint"""
    return jsonify({
        'service': 'Moonlight/Sunshine Backend',
        'version': '1.0.0',
        'api_prefix': '/api/moonlight',
        'endpoints': {
            'health': '/health',
            'sessions': '/api/moonlight/sessions',
            'images': '/api/moonlight/images'
        }
    }), 200

if __name__ == '__main__':
    # Development server (use Gunicorn in production)
    app.run(
        host='127.0.0.1',
        port=8004,
        debug=False
    )
