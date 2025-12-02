from .auth_routes import auth_bp
from .upload_routes import upload_bp
from .sim_routes import sim_bp
from .convert_routes import convert_bp
from .download_routes import download_bp
from .proxy import proxy_bp
from .slurm import slurm_bp
from .rack import rack_bp
from .job_template_routes import job_template_bp
from .app_routes import app_bp

def register_routes(app):
    app.register_blueprint(auth_bp)
    app.register_blueprint(upload_bp)
    app.register_blueprint(sim_bp)
    app.register_blueprint(convert_bp)
    app.register_blueprint(download_bp)
    app.register_blueprint(proxy_bp)
    app.register_blueprint(slurm_bp)
    app.register_blueprint(rack_bp)
    app.register_blueprint(job_template_bp)
    app.register_blueprint(app_bp)
    