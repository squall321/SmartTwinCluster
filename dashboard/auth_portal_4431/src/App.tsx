import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import LoginPage from './pages/LoginPage';
import CallbackPage from './pages/CallbackPage';
import ServiceMenuPage from './pages/ServiceMenuPage';
import VNCPage from './pages/VNCPage';
import './App.css';

function App() {
  return (
    <Router>
      <Routes>
        <Route path="/" element={<LoginPage />} />
        <Route path="/auth/callback" element={<CallbackPage />} />
        <Route path="/services" element={<ServiceMenuPage />} />
        <Route path="/vnc" element={<VNCPage />} />
      </Routes>
    </Router>
  );
}

export default App;
