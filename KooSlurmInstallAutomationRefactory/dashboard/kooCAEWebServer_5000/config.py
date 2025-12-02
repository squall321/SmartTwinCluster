import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

BASE_DIR = os.path.abspath(os.path.dirname(__file__))

class Config:
    SQLALCHEMY_DATABASE_URI = f"sqlite:///{os.path.join(BASE_DIR, 'db', 'users.db')}"
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    UPLOAD_ROOT = os.path.join(BASE_DIR, 'uploads')
    CORS_ORIGINS = [
        "http://localhost:5173",
        "http://localhost:5174",
        "http://110.15.177.120:5174",
        "http://219.250.247.155:5173",
        "http://219.250.247.155:5174"
    ]
    BACKEND_MAP = {
        "automation": "http://localhost:5001"        
    }
