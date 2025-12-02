import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
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
    return (_jsx(MaterialCacheProvider, { children: _jsx(DndProvider, { backend: HTML5Backend, children: _jsx(BrowserRouter, { basename: "/cae", children: _jsxs(Routes, { children: [_jsx(Route, { path: "/", element: _jsx(Dashboard, {}) }), _jsx(Route, { path: "/login", element: _jsx(LoginPage, { onLogin: () => { } }) }), _jsx(Route, { path: "/signup", element: _jsx(SignupPage, {}) }), _jsx(Route, { path: "/abd-calculator", element: _jsx(ABDCalculator, {}) }), _jsx(Route, { path: "/full-angle-drops", element: _jsx(FullAngleDrop, {}) }), _jsx(Route, { path: "/full-angle-drops-mdb", element: _jsx(FullAngleDropsMBDPage, {}) }), _jsx(Route, { path: "/drop-attitude-generator", element: _jsx(DropAttitudeGenerator, {}) }), _jsx(Route, { path: "/advanced-display-builder", element: _jsx(AdvancedDisplayBuilder, {}) }), _jsx(Route, { path: "/advanced-battery-builder", element: _jsx(AdvancedBatteryBuilder, {}) }), _jsx(Route, { path: "/elastic-to-rigid-builder", element: _jsx(ElastictoRigidBuilder, {}) }), _jsx(Route, { path: "/box-morph", element: _jsx(BoxMorph, {}) }), _jsx(Route, { path: "/warp-to-stress", element: _jsx(WarpToStress, {}) }), _jsx(Route, { path: "/drop-weight-impact-test-generator", element: _jsx(DropWeightImpactTestGenerator, {}) }), _jsx(Route, { path: "/all-points-drop-weight-impact-generator", element: _jsx(AllPointsDropWeightImpactGenerator, {}) }), _jsx(Route, { path: "/mesh-modifier", element: _jsx(MeshModifier, {}) }), _jsx(Route, { path: "/automated-modeller", element: _jsx(AutomatedModeller, {}) }), _jsx(Route, { path: "/slurm-status", element: _jsx(SlurmStatusPage, {}) }), _jsx(Route, { path: "/slurm-job-submit-dashboard", element: _jsx(SlurmJobDashboard, {}) }), _jsx(Route, { path: "/submit-lsdyna", element: _jsx(SubmitLsdynaPage, {}) }), _jsx(Route, { path: "/component-test", element: _jsx(ComponentTest, {}) }), _jsx(Route, { path: "/component-test-mesh-viewer", element: _jsx(ComponentTestMeshViewer, {}) }), _jsx(Route, { path: "/component-test-sub-component", element: _jsx(ComponentTestSubComponent, {}) }), _jsx(Route, { path: "/component-test-drawing", element: _jsx(ComponentTestDrawing, {}) }), _jsx(Route, { path: "/component-test-automation", element: _jsx(ComponentTestAutomation, {}) }), _jsx(Route, { path: "/motor-level-simulation", element: _jsx(MotorLevelSimulationPage, {}) }), _jsx(Route, { path: "/pwm-generator", element: _jsx(PWMGeneratorPage, {}) }), _jsx(Route, { path: "/ramberg-osgood", element: _jsx(RambergOsgoodPage, {}) }), _jsx(Route, { path: "/viscoelastic-visualizer", element: _jsx(ViscoelasticVisualizerPage, {}) }), _jsx(Route, { path: "/contact-stiffness-demo", element: _jsx(ContactStiffnessDemoPage, {}) }), _jsx(Route, { path: "/three-point-bending", element: _jsx(ThreePointBendingPage, {}) }), _jsx(Route, { path: "/mck-editor", element: _jsx(MckEditorPage, {}) }), _jsx(Route, { path: "/fem-structural-analysis", element: _jsx(FEMStructuralAnalysisPage, {}) }), _jsx(Route, { path: "/pde-fem", element: _jsx(PDEFEMPage, {}) }), _jsx(Route, { path: "/package-generator", element: _jsx(PackageGeneratorPage, {}) }), _jsx(Route, { path: "/auto-submit-lsdyna", element: _jsx(AutoSubmitLsdynaPage, {}) }), _jsx(Route, { path: "/submit-bullet", element: _jsx(SubmitBulletPage, {}) }), _jsx(Route, { path: "/tools/stream-runner", element: _jsx(StreamRunnerPage, {}) }), _jsx(Route, { path: "/dimensional-tolerance", element: _jsx(DimensionalTolerance, {}) }), _jsx(Route, { path: "/post-full-angle-drops", element: _jsx(PostFullAngleDropsPage, {}) }), _jsx(Route, { path: "/component-test-meta-data", element: _jsx(ComponentTestMetaDataPage, {}) }), _jsx(Route, { path: "/simulation-automation", element: _jsx(SimulationAutomationPage, {}) })] }) }) }) }));
}
export default App;
