import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useState } from "react";
import { Layout, Form, message } from "antd";
import DeformationModelPanel from "./Sidebar/DeformationModelPanel";
import MaterialModelPanel from "./Sidebar/MaterialModelPanel";
import GeometryPanel from "./Sidebar/GeometryPanel";
import LoadPanel from "./Sidebar/LoadPanel";
import AnalysisConditionPanel from "./Sidebar/AnalysisConditionPanel";
import SimulationControls from "./Sidebar/SimulationControls";
import LoadDeflectionChart from "./Charts/LoadDeflectionChart";
import MomentCurvatureChart from "./Charts/MomentCurvatureChart";
import UdlLoadDistributionChart from "./Charts/UdlLoadDistributionChart";
import DeflectedShapeAnimation from "./Animation/DeflectedShapeAnimation";
import ResultTable from "./DataTable/ResultTable";
import { runSimulation } from "../../utils/threepointbending/simulation";
import ModelFormulaBox from "../common/ModelFormulaBox";
const { Sider, Content } = Layout;
const ThreePointBendingApp = () => {
    const [deformationModel, setDeformationModel] = useState("Small");
    const [materialModel, setMaterialModel] = useState("LinearElastic");
    const [materialParams, setMaterialParams] = useState({
        model: "LinearElastic",
        params: { E: 200000 }
    });
    const [geometry, setGeometry] = useState({
        span: 200,
        height: 10,
        width: 10
    });
    const [loadConfig, setLoadConfig] = useState({
        maxLoad: 100,
        step: 5
    });
    const [supportCondition, setSupportCondition] = useState("SimplySupported");
    const [loadType, setLoadType] = useState("Point");
    const [loadPosition, setLoadPosition] = useState(geometry.span / 2);
    const [integrationSteps, setIntegrationSteps] = useState(100);
    const [simulationResult, setSimulationResult] = useState(null);
    const [loading, setLoading] = useState(false);
    const handleRunSimulation = () => {
        if (deformationModel === "Small" &&
            materialModel !== "LinearElastic") {
            message.error("Plasticity models are not supported for Small Deformation!");
            return;
        }
        try {
            setLoading(true);
            const analysis = {
                loadType,
                loadPosition,
                integrationSteps,
                supportCondition
            };
            const result = runSimulation(geometry, loadConfig, materialParams, deformationModel, analysis);
            setSimulationResult(result);
            message.success("Simulation completed!");
        }
        catch (error) {
            message.error(error.message);
        }
        finally {
            setLoading(false);
        }
    };
    const handleReset = () => {
        setSimulationResult(null);
    };
    return (_jsxs(Layout, { style: { height: "100vh" }, children: [_jsx(Sider, { width: 320, style: {
                    background: "#fff",
                    padding: "16px",
                    overflow: "auto",
                    borderRight: "1px solid #f0f0f0"
                }, children: _jsxs(Form, { layout: "vertical", children: [_jsx(DeformationModelPanel, { deformationModel: deformationModel, setDeformationModel: setDeformationModel }), deformationModel === "Small" && (_jsx(ModelFormulaBox, { title: "\uC18C\uBCC0\uD615 \uD574\uC11D (Small Deformation)", description: "\uC18C\uBCC0\uD615\uC5D0\uC11C\uB294 \uACE1\uB960\uACFC \uCC98\uC9D0\uC758 \uAD00\uACC4\uAC00 \uC120\uD615\uC774\uBA70, \uD0C4\uC131 \uBC94\uC704 \uB0B4 \uD574\uC11D\uC774 \uAC00\uB2A5\uD569\uB2C8\uB2E4.", formulas: [
                                "\\kappa = \\frac{d^2 w}{dx^2}",
                                "M = E \\cdot I \\cdot \\kappa",
                                "\\delta = \\frac{P \\cdot a \\cdot b (L^2 - a b)}{3 L E I}"
                            ] })), deformationModel === "Large" && (_jsx(ModelFormulaBox, { title: "\uB300\uBCC0\uD615 \uD574\uC11D (Large Deformation)", description: "\uB300\uBCC0\uD615\uC5D0\uC11C\uB294 \uACE1\uB960\uC774 \uBE44\uC120\uD615 \uAD00\uACC4\uB97C \uB530\uB974\uBA70, \uC218\uCE58 \uC801\uBD84\uC73C\uB85C \uD728 \uBAA8\uBA58\uD2B8\uB97C \uAD6C\uD569\uB2C8\uB2E4.", formulas: [
                                "\\kappa = \\frac{\\frac{d^2 w}{dx^2}}{\\sqrt{1 + \\left( \\frac{dw}{dx} \\right)^2 }}",
                                "M = \\int_{-h/2}^{h/2} \\sigma(\\varepsilon) \\cdot y \\, dy",
                                "\\varepsilon(y) = \\kappa \\cdot y"
                            ] })), _jsx(MaterialModelPanel, { materialModel: materialModel, setMaterialModel: setMaterialModel, materialParams: materialParams, setMaterialParams: setMaterialParams }), _jsx(GeometryPanel, { geometry: geometry, setGeometry: setGeometry }), _jsx(LoadPanel, { loadConfig: loadConfig, setLoadConfig: setLoadConfig }), _jsx(AnalysisConditionPanel, { loadType: loadType, setLoadType: setLoadType, loadPosition: loadPosition, setLoadPosition: setLoadPosition, integrationSteps: integrationSteps, setIntegrationSteps: setIntegrationSteps, supportCondition: supportCondition, setSupportCondition: setSupportCondition, span: geometry.span }), _jsx(SimulationControls, { onRun: handleRunSimulation, onReset: handleReset, loading: loading })] }) }), _jsx(Layout, { children: _jsx(Content, { style: {
                        padding: "24px",
                        background: "#f9f9f9",
                        height: "100vh",
                        overflow: "auto"
                    }, children: loading ? (_jsx("div", { style: {
                            textAlign: "center",
                            marginTop: "30vh"
                        }, children: "Loading..." })) : simulationResult ? (_jsxs(_Fragment, { children: [loadType === "UDL" && (_jsx(UdlLoadDistributionChart, { span: geometry.span, load: loadConfig.maxLoad })), _jsx(LoadDeflectionChart, { loads: simulationResult.loads, deflections: simulationResult.deflections }), _jsx(MomentCurvatureChart, { curvatures: simulationResult.curvatures, moments: simulationResult.moments }), _jsx(DeflectedShapeAnimation, { shapes: simulationResult.shapes, loads: simulationResult.loads }), _jsx(ResultTable, { result: simulationResult })] })) : (_jsx("div", { style: {
                            textAlign: "center",
                            marginTop: "30vh"
                        }, children: _jsx("h2", { children: "Run the simulation to see results" }) })) }) })] }));
};
export default ThreePointBendingApp;
