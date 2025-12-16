import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Table, Button, Typography, Upload, InputNumber, Space, Tag } from 'antd';
import { UploadOutlined, EyeOutlined, DeleteOutlined } from '@ant-design/icons';
const PartWarpageTable = ({ parts, editable = false, onRemove, title, onUploadDat, onViewPart, datStatusMap = {}, warpageMap, onParamChange, }) => {
    const columns = [
        { title: 'ID', dataIndex: 'id', key: 'id' },
        { title: '이름', dataIndex: 'name', key: 'name' },
        {
            title: 'DAT 상태',
            key: 'dat',
            render: (_, record) => datStatusMap[record.id] ? _jsx(Tag, { color: "green", children: "\uC5C5\uB85C\uB4DC\uB428" }) : _jsx(Tag, { color: "red", children: "\uC5C6\uC74C" })
        },
        {
            title: 'X', key: 'xLength',
            render: (_, record) => (_jsx(InputNumber, { min: 0, step: 0.1, value: warpageMap[record.id]?.xLength ?? 1, onChange: (val) => onParamChange(record.id, { xLength: val ?? 0 }) }))
        },
        {
            title: 'Y', key: 'yLength',
            render: (_, record) => (_jsx(InputNumber, { min: 0, step: 0.1, value: warpageMap[record.id]?.yLength ?? 1, onChange: (val) => onParamChange(record.id, { yLength: val ?? 0 }) }))
        },
        {
            title: 'Scale', key: 'scaleFactor',
            render: (_, record) => (_jsx(InputNumber, { min: 0, step: 0.1, value: warpageMap[record.id]?.scaleFactor ?? 1, onChange: (val) => onParamChange(record.id, { scaleFactor: val ?? 1 }) }))
        },
        {
            title: '작업',
            key: 'actions',
            render: (_, record) => (_jsxs(Space, { children: [_jsx(Upload, { accept: ".dat,.txt", beforeUpload: (file) => {
                            onUploadDat?.(record.id, file);
                            return false;
                        }, showUploadList: false, children: _jsx(Button, { size: "small", icon: _jsx(UploadOutlined, {}), children: "\uC5C5\uB85C\uB4DC" }) }), _jsx(Button, { size: "small", icon: _jsx(EyeOutlined, {}), onClick: () => onViewPart?.(record.id), disabled: !datStatusMap[record.id], children: "\uBCF4\uAE30" }), editable && (_jsx(Button, { danger: true, size: "small", icon: _jsx(DeleteOutlined, {}), onClick: () => onRemove?.(record.id), children: "\uC81C\uAC70" }))] }))
        }
    ];
    return (_jsxs("div", { style: { marginTop: 24 }, children: [title && _jsx(Typography.Text, { strong: true, children: title }), _jsx(Table, { dataSource: parts.map((p, i) => ({ ...p, key: i })), columns: columns, pagination: false, size: "small", bordered: true, style: { marginTop: 12 } })] }));
};
export default PartWarpageTable;
