import os
import yaml
from dotenv import load_dotenv
from pathlib import Path

# Load environment variables from .env file
load_dotenv()

BASE_DIR = os.path.abspath(os.path.dirname(__file__))

# Load public URL from YAML for CORS configuration
def _load_public_url():
    yaml_path = Path(BASE_DIR).parent.parent / 'my_multihead_cluster.yaml'
    try:
        if yaml_path.exists():
            with open(yaml_path) as f:
                config = yaml.safe_load(f)
                public_url = config.get('web', {}).get('public_url', 'localhost')
                sso_enabled = config.get('sso', {}).get('enabled', True)
                protocol = 'https' if sso_enabled else 'http'
                return public_url, protocol
    except Exception:
        pass
    return 'localhost', 'http'

PUBLIC_URL, PROTOCOL = _load_public_url()

class Config:
    SQLALCHEMY_DATABASE_URI = f"sqlite:///{os.path.join(BASE_DIR, 'db', 'users.db')}"
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    UPLOAD_ROOT = os.path.join(BASE_DIR, 'uploads')

    # CORS origins - dynamically loaded from YAML
    CORS_ORIGINS = [
        "http://localhost:5173",
        "http://localhost:5174",
        f"{PROTOCOL}://{PUBLIC_URL}:5173",
        f"{PROTOCOL}://{PUBLIC_URL}:5174",
        f"{PROTOCOL}://{PUBLIC_URL}"
    ]

    BACKEND_MAP = {
        "automation": "http://localhost:5001"
    }
