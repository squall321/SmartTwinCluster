import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useState } from 'react';
import { api } from '../../api/axiosClient';
import { Select, Spin, Typography, Button, Input, Space, List } from 'antd';
import { DeleteOutlined } from '@ant-design/icons';
import StlViewerComponent from '../StlViewerComponent';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';
const { Option } = Select;
const { Title } = Typography;
function formatImpactorName(fileName) {
    const cleanName = fileName.replace('.stl', '');
    const parts = cleanName.split('_');
    if (parts.length === 3) {
        const [piPart, weightPart, shapePart] = parts;
        const piText = piPart.replace('pi', 'π');
        const shapeText = shapePart.charAt(0).toUpperCase() + shapePart.slice(1);
        return `${shapeText} (${weightPart}, ${piText})`;
    }
    return fileName;
}
const ImpactorSelectorComponent = ({ onChange, targetBoundingBox }) => {
    const [files, setFiles] = useState([]);
    const [selectedUrl, setSelectedUrl] = useState(null);
    const [loading, setLoading] = useState(true);
    const [impactPoints, setImpactPoints] = useState([]);
    const [size, setSize] = useState(null);
    const [centerOffset, setCenterOffset] = useState(null);
    useEffect(() => {
        const fetchImpactors = async () => {
            try {
                const response = await api.post(`/api/impactors`);
                const data = response.data;
                if (data.success) {
                    setFiles(data.files);
                }
            }
            catch (err) {
                console.error('서버 요청 실패:', err);
            }
            finally {
                setLoading(false);
            }
        };
        fetchImpactors();
    }, []);
    useEffect(() => {
        if (selectedUrl && onChange) {
            if (centerOffset) {
                const corrected = impactPoints.map(pt => ({
                    dx: pt.dx + centerOffset.x,
                    dy: pt.dy + centerOffset.y,
                    dz: centerOffset.z,
                }));
                onChange(selectedUrl, corrected);
            }
            else {
                onChange(selectedUrl, impactPoints);
            }
        }
    }, [selectedUrl, impactPoints, centerOffset]);
    const handleSelect = async (value) => {
        setSelectedUrl(value);
        setImpactPoints([]);
        const engine = new BABYLON.NullEngine();
        const scene = new BABYLON.Scene(engine);
        try {
            const result = await BABYLON.SceneLoader.ImportMeshAsync(null, '', value, scene, undefined, '.stl');
            const mesh = result.meshes[0];
            mesh.forceSharedVertices();
            mesh.convertToFlatShadedMesh();
            mesh.computeWorldMatrix(true);
            mesh.refreshBoundingInfo();
            const boundingBox = mesh.getBoundingInfo().boundingBox;
            const min = boundingBox.minimumWorld;
            const max = boundingBox.maximumWorld;
            const center = max.add(min).scale(0.5);
            const sizeVec = max.subtract(min);
            setSize(sizeVec);
            setCenterOffset(center);
        }
        catch (e) {
            console.error('❌ STL 불러오기 실패:', e);
        }
    };
    const addCenterPoint = () => {
        if (!centerOffset)
            return;
        setImpactPoints((prev) => [...prev, { dx: -centerOffset.x, dy: -centerOffset.y, dz: -centerOffset.z }]);
    };
    const addCornerPoints = () => {
        if (!targetBoundingBox || !centerOffset)
            return;
        const { min, max } = targetBoundingBox;
        const corners = [
            new BABYLON.Vector3(min.x, 0, min.z),
            new BABYLON.Vector3(max.x, 0, min.z),
            new BABYLON.Vector3(max.x, 0, max.z),
            new BABYLON.Vector3(min.x, 0, max.z),
        ];
        const relative = corners.map((corner) => ({
            dx: corner.x - centerOffset.x,
            dy: corner.z - centerOffset.y,
            dz: 0,
        }));
        setImpactPoints(relative);
    };
    const addSidePoints = () => {
        if (!targetBoundingBox || !centerOffset)
            return;
        const { min, max } = targetBoundingBox;
        const midX = (min.x + max.x) / 2;
        const midZ = (min.z + max.z) / 2;
        const sidePoints = [
            new BABYLON.Vector3(min.x, 0, midZ), // 왼쪽
            new BABYLON.Vector3(max.x, 0, midZ), // 오른쪽
            new BABYLON.Vector3(midX, 0, min.z), // 앞
            new BABYLON.Vector3(midX, 0, max.z), // 뒤
        ];
        const relative = sidePoints.map((pt) => ({
            dx: pt.x - centerOffset.x,
            dy: pt.z - centerOffset.y,
            dz: 0,
        }));
        setImpactPoints((prev) => [...prev, ...relative]);
    };
    const addLongSidePoints = () => {
        if (!targetBoundingBox || !centerOffset)
            return;
        const { min, max } = targetBoundingBox;
        const lengthX = Math.abs(max.x - min.x);
        const lengthZ = Math.abs(max.z - min.z);
        const midX = (min.x + max.x) / 2;
        const midZ = (min.z + max.z) / 2;
        let longSidePoints = [];
        if (lengthX >= lengthZ) {
            // 장축이 X: 좌/우 중점
            longSidePoints = [
                new BABYLON.Vector3(min.x, 0, midZ),
                new BABYLON.Vector3(max.x, 0, midZ),
            ];
        }
        else {
            // 장축이 Z: 앞/뒤 중점
            longSidePoints = [
                new BABYLON.Vector3(midX, 0, min.z),
                new BABYLON.Vector3(midX, 0, max.z),
            ];
        }
        const relative = longSidePoints.map((pt) => ({
            dx: pt.x - centerOffset.x,
            dy: pt.z - centerOffset.y,
            dz: 0,
        }));
        setImpactPoints((prev) => [...prev, ...relative]);
    };
    const updateImpactPoint = (index, field, value) => {
        const parsed = parseFloat(value);
        if (isNaN(parsed))
            return;
        setImpactPoints((prev) => prev.map((pt, i) => (i === index ? { ...pt, [field]: parsed } : pt)));
    };
    const deleteImpactPoint = (index) => {
        setImpactPoints((prev) => prev.filter((_, i) => i !== index));
    };
    const clearAllPoints = () => {
        setImpactPoints([]);
    };
    return (_jsxs("div", { style: { padding: '2rem' }, children: [_jsx(Title, { level: 4, children: "\uD83D\uDCE6 \uCDA9\uACA9\uC790 STL \uC120\uD0DD" }), loading ? (_jsx(Spin, { size: "large" })) : (_jsx(Select, { showSearch: true, placeholder: "STL \uD30C\uC77C \uC120\uD0DD...", optionFilterProp: "children", onChange: handleSelect, style: { width: 300, marginBottom: '1.5rem' }, children: files.map((file) => (_jsx(Option, { value: file.url, children: formatImpactorName(file.name) }, file.url))) })), selectedUrl && (_jsxs("div", { style: { marginTop: '1.5rem' }, children: [_jsx(StlViewerComponent, { url: selectedUrl }), _jsxs("div", { style: { marginTop: 16 }, children: [_jsx(Button, { onClick: addCenterPoint, style: { marginRight: 8 }, children: "\uD83D\uDD35 \uC911\uC2EC\uC810" }), _jsx(Button, { onClick: addCornerPoints, style: { marginRight: 8 }, children: "\uD83D\uDCD0 \uAF2D\uC9D3\uC810" }), _jsx(Button, { onClick: addSidePoints, style: { marginRight: 8 }, children: "\uD83D\uDCCF \uC0AC\uC774\uB4DC" }), _jsx(Button, { onClick: addLongSidePoints, style: { marginRight: 8 }, children: "\uD83D\uDCCF \uC7A5\uCD95 \uC0AC\uC774\uB4DC" }), _jsx(Button, { onClick: clearAllPoints, danger: true, children: "\u274C \uC804\uCCB4 \uC0AD\uC81C" })] }), _jsx(List, { size: "small", header: _jsx("div", { children: "\uD83D\uDCA5 \uCDA9\uACA9 \uC704\uCE58 \uB9AC\uC2A4\uD2B8 (x-y \uD3C9\uBA74, \uD3B8\uC9D1 \uAC00\uB2A5)" }), bordered: true, dataSource: impactPoints, style: { marginTop: 16 }, renderItem: (item, idx) => (_jsx(List.Item, { actions: [
                                _jsx(Button, { type: "text", icon: _jsx(DeleteOutlined, {}), danger: true, onClick: () => deleteImpactPoint(idx) }),
                            ], children: _jsxs(Space, { children: ["#", idx + 1, "dx:", _jsx(Input, { value: item.dx, style: { width: 100 }, onChange: (e) => updateImpactPoint(idx, 'dx', e.target.value) }), "dy:", _jsx(Input, { value: item.dy, style: { width: 100 }, onChange: (e) => updateImpactPoint(idx, 'dy', e.target.value) })] }) })) })] }))] }));
};
export default ImpactorSelectorComponent;
