import { useEffect } from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { HTML5Backend } from 'react-dnd-html5-backend';
import { DndProvider } from 'react-dnd';
import { MaterialCacheProvider } from './components/MaterialCacheContext';


import LoginPage from '@pages/Login';
import SignupPage from '@pages/Signup';
import Dashboard from '@pages/Dashboard';
import ABDCalculator from '@pages/ABDCalculator';
import FullAngleDrop from '@pages/FullAngleDrops';
import FullAngleDropsMBDPage from '@pages/FullAngleDropsMBDPage';
import DropAttitudeGenerator from '@pages/DropAttitudeGenerator';
import AdvancedDisplayBuilder from '@pages/AdvancedDisplayBuilder';
import ElastictoRigidBuilder from '@pages/ElastictoRigidBuilder';
import BoxMorph from '@pages/BoxMorph';
import WarpToStress from '@pages/WarpToStress';
import DropWeightImpactTestGenerator from '@pages/DropWeightImpactTestGenerator';
import MeshModifier from '@pages/MeshModifier';
import AutomatedModeller from '@pages/AutomatedModeller';
import ComponentTest from '@pages/ComponentTest';
import ComponentTestAutomation from '@pages/ComponentTestAutomation';
import ComponentTestMeshViewer from '@pages/ComponentTestMeshViewer';
import ComponentTestDrawing from '@pages/ComponentTestDrawing';
import SlurmStatusPage from '@pages/SlurmStatusPage';
import SlurmJobDashboard from '@pages/SlurmJobDashboard';
import SubmitLsdynaPage from '@pages/SubmitLsdynaPage';
import ComponentTestSubComponent from '@pages/ComponentTestSubComponent';
import MotorLevelSimulationPage from '@pages/MotorLevelSimulationPage';
import PWMGeneratorPage from '@pages/PWMGenerator';
import RambergOsgoodPage from '@pages/RambergOsgoodPage';
import ViscoelasticVisualizerPage from '@pages/ViscoelasticVisualizerPage';
import ContactStiffnessDemoPage from '@pages/ContactStiffnessDemoPage';
import MckEditorPage from '@pages/mck/MckEditorPage';
import ThreePointBendingPage from '@pages/ThreePointBendingPage';
import FEMStructuralAnalysisPage from '@pages/Theories/FEMStructuralAnalysisPage';
import PDEFEMPage from '@pages/Theories/PDEFEMPage';
import PackageGeneratorPage from '@pages/ModuleGenerator/PackageGeneratorPage';
import AutoSubmitLsdynaPage from '@pages/AutoSubmitLsdynaPage';
import SubmitBulletPage from '@pages/SubmitBulletPage';
import StreamRunnerPage from '@pages/StreamRunnerPage';
import AllPointsDropWeightImpactGenerator from '@pages/AllPointsDropWeightImpactGenerator';
import AdvancedBatteryBuilder from '@pages/AdvancedBatteryBuillder';
import DimensionalTolerance from '@pages/DimensionalTolerance';
import PostFullAngleDropsPage from '@pages/PostFullAngleDrops';
import ComponentTestMetaDataPage from '@pages/ComponentTestMetaData';
import SimulationAutomationPage from '@pages/SimulationAutomationPage';

function App() {
  useEffect(() => {
    // Extract JWT token from URL query parameters (from Auth Portal)
    const urlParams = new URLSearchParams(window.location.search);
    const token = urlParams.get('token');

    if (token) {
      console.log('[CAE Auth] JWT token received from URL, storing in localStorage');
      localStorage.setItem('jwt_token', token);

      // Remove token from URL for security (prevent token exposure in browser history)
      window.history.replaceState({}, document.title, window.location.pathname);

      // Reload to apply authentication
      window.location.reload();
    }
  }, []);

  return (
    <MaterialCacheProvider>
      <DndProvider backend={HTML5Backend}>
      <BrowserRouter basename="/cae">
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/login" element={<LoginPage onLogin={() => {}} />} />
          <Route path="/signup" element={<SignupPage />} />
          <Route path="/abd-calculator" element={<ABDCalculator />} />
          <Route path="/full-angle-drops" element={<FullAngleDrop />} />
          <Route path="/full-angle-drops-mdb" element={<FullAngleDropsMBDPage />} />
          <Route path="/drop-attitude-generator" element={<DropAttitudeGenerator />} />
          <Route path="/advanced-display-builder" element={<AdvancedDisplayBuilder />} />
          <Route path="/advanced-battery-builder" element={<AdvancedBatteryBuilder />} />
          <Route path="/elastic-to-rigid-builder" element={<ElastictoRigidBuilder />} />
          <Route path="/box-morph" element={<BoxMorph />} />
          <Route path="/warp-to-stress" element={<WarpToStress />} />
          <Route path="/drop-weight-impact-test-generator" element={<DropWeightImpactTestGenerator />} />
          <Route path="/all-points-drop-weight-impact-generator" element={<AllPointsDropWeightImpactGenerator />} />
          <Route path="/mesh-modifier" element={<MeshModifier />} />
          <Route path="/automated-modeller" element={<AutomatedModeller />} />
          <Route path="/slurm-status" element={<SlurmStatusPage />} />        
          <Route path="/slurm-job-submit-dashboard" element={<SlurmJobDashboard />} />
          <Route path="/submit-lsdyna" element={<SubmitLsdynaPage />} />
          <Route path="/component-test" element={<ComponentTest />} />
          <Route path="/component-test-mesh-viewer" element={<ComponentTestMeshViewer />} />
          <Route path="/component-test-sub-component" element={<ComponentTestSubComponent />} />
          <Route path="/component-test-drawing" element={<ComponentTestDrawing />} />
          <Route path="/component-test-automation" element={<ComponentTestAutomation />} />
          <Route path="/motor-level-simulation" element={<MotorLevelSimulationPage />} />
          <Route path="/pwm-generator" element={<PWMGeneratorPage />} />
          <Route path="/ramberg-osgood" element={<RambergOsgoodPage />} />
          <Route path="/viscoelastic-visualizer" element={<ViscoelasticVisualizerPage />} />
          <Route path="/contact-stiffness-demo" element={<ContactStiffnessDemoPage />} />
          <Route path="/three-point-bending" element={<ThreePointBendingPage />} />
          <Route path="/mck-editor" element={<MckEditorPage />} />
          <Route path="/fem-structural-analysis" element={<FEMStructuralAnalysisPage />} />
          <Route path="/pde-fem" element={<PDEFEMPage />} />
          <Route path="/package-generator" element={<PackageGeneratorPage />} />
          <Route path="/auto-submit-lsdyna" element={<AutoSubmitLsdynaPage />} />
          <Route path="/submit-bullet" element={<SubmitBulletPage />} />
          <Route path="/tools/stream-runner" element={<StreamRunnerPage />} />
          <Route path="/dimensional-tolerance" element={<DimensionalTolerance />} />
          <Route path="/post-full-angle-drops" element={<PostFullAngleDropsPage />} />
          <Route path="/component-test-meta-data" element={<ComponentTestMetaDataPage />} />
          <Route path="/simulation-automation" element={<SimulationAutomationPage />} />
        </Routes>
      </BrowserRouter>
      </DndProvider>
    </MaterialCacheProvider>
  );
}

export default App;
