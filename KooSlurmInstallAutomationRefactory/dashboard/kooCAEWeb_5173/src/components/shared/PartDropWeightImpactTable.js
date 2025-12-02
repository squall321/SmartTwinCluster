import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { Table, Button, Select, InputNumber, Space } from 'antd';
import { DeleteOutlined } from '@ant-design/icons';
import DotIcon from '../../Icons/DotIcon';
const { Option } = Select;
const dotPatterns = [
    '1x1', '1x2', '2x1', '2x2', '1x3', '3x1', '3x3'
];
const heightOptions = Array.from({ length: 10 }, (_, i) => 50 * (i + 1)); // 50~500
const diameterOptions = [8, 15];
const weightOptions = [200, 400, 500];
const impactorTypes = ['cylinder', 'sphere'];
const PartDropWeightImpactTable = ({ parts, onRemove, onPatternChange, onHeightChange, onImpactorChange, onVelocityVectorChange, }) => {
    const columns = [
        { title: 'ID', dataIndex: 'id', key: 'id' },
        { title: '이름', dataIndex: 'name', key: 'name' },
        {
            title: '충격 위치',
            key: 'impactPattern',
            render: (_, record) => (_jsxs("div", { style: { display: 'flex', alignItems: 'center', gap: 8 }, children: [_jsx(Select, { value: record.impactPattern || '1x1', onChange: (value) => onPatternChange(record.id, value), style: { width: 80 }, children: dotPatterns.map((pattern) => (_jsx(Option, { value: pattern, children: pattern }, pattern))) }), _jsx(DotIcon, { pattern: record.impactPattern || '1x1', size: 32 })] })),
        },
        {
            title: '충격 높이 (mm)',
            key: 'impactHeight',
            render: (_, record) => (_jsx(Select, { style: { width: 120 }, value: record.impactHeight ?? 200, onChange: (value) => onHeightChange(record.id, value), options: heightOptions.map(h => ({ value: h, label: `${h} mm` })), dropdownRender: menu => (_jsxs(_Fragment, { children: [menu, _jsx("div", { style: { padding: '8px', display: 'flex', gap: 8 }, children: _jsx("input", { type: "number", min: 0, defaultValue: record.impactHeight ?? 200, style: {
                                    width: '100%',
                                    padding: '4px 8px',
                                    border: '1px solid #d9d9d9',
                                    borderRadius: '4px',
                                    color: '#000',
                                    backgroundColor: '#fff'
                                }, onBlur: (e) => {
                                    const val = parseInt(e.target.value);
                                    if (!isNaN(val))
                                        onHeightChange(record.id, val);
                                } }) })] })) }))
        },
        {
            title: '충격 속도 (m/s)',
            key: 'impactVelocityVector',
            render: (_, record) => (_jsxs(Space, { children: [_jsx(InputNumber, { value: record.impactVelocityVector[0], onChange: (v) => onVelocityVectorChange(record.id, [
                            v ?? 0,
                            record.impactVelocityVector[1],
                            record.impactVelocityVector[2]
                        ]), placeholder: "X" }), _jsx(InputNumber, { value: record.impactVelocityVector[1], onChange: (v) => onVelocityVectorChange(record.id, [
                            record.impactVelocityVector[0],
                            v ?? 0,
                            record.impactVelocityVector[2]
                        ]), placeholder: "Y" }), _jsx(InputNumber, { value: record.impactVelocityVector[2], onChange: (v) => onVelocityVectorChange(record.id, [
                            record.impactVelocityVector[0],
                            record.impactVelocityVector[1],
                            v ?? 0
                        ]), placeholder: "Z" })] }))
        },
        {
            title: '삭제',
            key: 'remove',
            render: (_, record) => (_jsx(Button, { type: "link", icon: _jsx(DeleteOutlined, {}), onClick: () => onRemove(record.id) })),
        },
    ];
    return (_jsx("div", { style: { marginTop: 24 }, children: _jsx(Table, { dataSource: parts, columns: columns, rowKey: "id", pagination: false, size: "small", bordered: true, scroll: { x: 'max-content' }, style: { marginTop: 12 } }) }));
};
export default PartDropWeightImpactTable;
