import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import '../styles/ServiceMenuPage.css';

interface Service {
  name: string;
  url: string;
  description: string;
  icon: string;
}

interface UserInfo {
  sub: string;
  email: string;
  groups: string[];
  permissions: string[];
}

const ServiceMenuPage: React.FC = () => {
  const [services, setServices] = useState<Service[]>([]);
  const [userInfo, setUserInfo] = useState<UserInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const navigate = useNavigate();

  useEffect(() => {
    const token = localStorage.getItem('jwt_token');

    if (!token) {
      navigate('/');
      return;
    }

    // Load user info from localStorage
    const storedUserInfo = localStorage.getItem('user_info');
    if (storedUserInfo) {
      setUserInfo(JSON.parse(storedUserInfo));
    }

    // Fetch available services
    fetch('/auth/services', {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    })
      .then(response => {
        if (!response.ok) {
          throw new Error('Failed to fetch services');
        }
        return response.json();
      })
      .then(data => {
        setServices(data.services);
        setLoading(false);
      })
      .catch(err => {
        console.error('Error fetching services:', err);
        setLoading(false);
        navigate('/');
      });
  }, [navigate]);

  const handleLogout = () => {
    const token = localStorage.getItem('jwt_token');

    if (token) {
      fetch('/auth/logout', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`
        }
      }).catch(console.error);
    }

    localStorage.removeItem('jwt_token');
    localStorage.removeItem('user_info');
    navigate('/');
  };

  const handleServiceClick = (service: Service) => {
    const token = localStorage.getItem('jwt_token');

    // All services use relative paths now (e.g., /dashboard, /vnc, /cae)
    // Simply redirect to the service URL with token in query string
    window.location.href = `${service.url}?token=${token}`;
  };

  const getIconGradient = (icon: string): { gradient: string; icon: string } => {
    const iconMap: Record<string, { gradient: string; icon: string }> = {
      'flow': {
        gradient: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
        icon: '🌊'
      },
      'cluster': {
        gradient: 'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)',
        icon: '⚡'
      },
      'desktop': {
        gradient: 'linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)',
        icon: '🖥️'
      }
    };
    return iconMap[icon] || { gradient: 'linear-gradient(135deg, #a8edea 0%, #fed6e3 100%)', icon: '📦' };
  };

  if (loading) {
    return (
      <div className="loading-container">
        <div className="spinner"></div>
        <p>Loading services...</p>
      </div>
    );
  }

  return (
    <div className="service-menu-container">
      <header className="service-header">
        <div className="header-content">
          <div className="header-title">
            <h1>LS-DYNA HPC Cluster</h1>
            <p className="header-subtitle">High-Performance Computing & Simulation Platform</p>
          </div>
          {userInfo && (
            <div className="user-info">
              <div className="user-details">
                <span className="user-name">{userInfo.sub}</span>
                <span className="user-email">{userInfo.email}</span>
                <div className="user-groups">
                  {userInfo.groups.map((group, idx) => (
                    <span key={idx} className="group-badge">{group}</span>
                  ))}
                </div>
              </div>
              <button className="logout-button" onClick={handleLogout}>
                Logout
              </button>
            </div>
          )}
        </div>
      </header>

      <main className="service-main">
        <div className="services-grid">
          {services.length === 0 ? (
            <div className="no-services">
              <p>No services available for your account</p>
              <p className="help-text">Contact your administrator for access</p>
            </div>
          ) : (
            services.map((service, idx) => {
              const { gradient, icon } = getIconGradient(service.icon);
              return (
                <div
                  key={idx}
                  className="service-card"
                  onClick={() => handleServiceClick(service)}
                  style={{ ['--card-gradient' as any]: gradient }}
                >
                  <div className="service-icon-wrapper" style={{ background: gradient }}>
                    <span className="service-icon-emoji">{icon}</span>
                  </div>
                  <div className="service-content">
                    <h3 className="service-name">{service.name}</h3>
                    <p className="service-description">{service.description}</p>
                  </div>
                  <div className="service-footer">
                    <button className="service-button" style={{ background: gradient }}>
                      Launch →
                    </button>
                  </div>
                </div>
              );
            })
          )}
        </div>
      </main>

      <footer className="service-footer-main">
        <p>LS-DYNA HPC Cluster - Advanced CAE Simulation & High-Performance Computing</p>
      </footer>
    </div>
  );
};

export default ServiceMenuPage;
