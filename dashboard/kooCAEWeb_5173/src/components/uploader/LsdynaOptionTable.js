import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { Table, Select, Space, Tooltip } from 'antd';
import { DeleteOutlined } from '@ant-design/icons';
const { Option } = Select;
const coreOptions = [16, 32, 64, 128];
const precisionOptions = ['single', 'double'];
const versionOptions = ['R15', 'R14'];
const modeOptions = ['SMP', 'MPP'];
const LsdynaOptionTable = ({ data, onUpdateAll, onUpdateRow, onDeleteRow }) => {
    const columns = [
        {
            title: '파일명',
            dataIndex: 'filename',
            key: 'filename',
            width: 200,
            ellipsis: true,
            render: (text) => (_jsx(Tooltip, { title: text, children: _jsx("div", { style: {
                        display: 'inline-block',
                        maxWidth: 180,
                        whiteSpace: 'nowrap',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                    }, children: text }) })),
        },
        {
            title: 'Core 수',
            dataIndex: 'cores',
            key: 'cores',
            width: 120,
            render: (value, row) => (_jsx(Select, { value: value, size: "small", style: { width: 100 }, onChange: (val) => onUpdateRow(row.key, 'cores', val), children: coreOptions.map((opt) => (_jsx(Option, { value: opt, children: opt }, opt))) })),
        },
        {
            title: 'Precision',
            dataIndex: 'precision',
            key: 'precision',
            width: 120,
            render: (value, row) => (_jsx(Select, { value: value, size: "small", style: { width: 100 }, onChange: (val) => onUpdateRow(row.key, 'precision', val), children: precisionOptions.map((opt) => (_jsx(Option, { value: opt, children: opt }, opt))) })),
        },
        {
            title: 'Version',
            dataIndex: 'version',
            key: 'version',
            width: 120,
            render: (value, row) => (_jsx(Select, { value: value, size: "small", style: { width: 100 }, onChange: (val) => onUpdateRow(row.key, 'version', val), children: versionOptions.map((opt) => (_jsx(Option, { value: opt, children: opt }, opt))) })),
        },
        {
            title: 'Mode',
            dataIndex: 'mode',
            key: 'mode',
            width: 120,
            render: (value, row) => (_jsx(Select, { value: value, size: "small", style: { width: 100 }, onChange: (val) => onUpdateRow(row.key, 'mode', val), children: modeOptions.map((opt) => (_jsx(Option, { value: opt, children: opt }, opt))) })),
        },
        {
            title: '삭제',
            key: 'delete',
            width: 60,
            render: (_, row) => (_jsx(DeleteOutlined, { onClick: () => onDeleteRow(row.key), style: { color: 'red', cursor: 'pointer' } })),
        },
    ];
    return (_jsxs(_Fragment, { children: [_jsx(Table, { bordered: true, columns: columns, dataSource: data, pagination: false, scroll: { x: 'max-content' }, size: "small", rowKey: "key" }), _jsxs(Space, { style: {
                    marginTop: '1rem',
                    padding: '8px',
                    borderTop: '1px dashed #ddd',
                    display: 'flex',
                    flexWrap: 'wrap',
                    alignItems: 'center',
                    gap: '0.5rem',
                }, children: [_jsx("span", { style: { fontWeight: 500 }, children: "\uC804\uCCB4 \uBCC0\uACBD:" }), _jsx(Select, { size: "small", style: { width: 100 }, onChange: (val) => onUpdateAll('cores', val), defaultValue: 16, children: coreOptions.map((opt) => (_jsx(Option, { value: opt, children: opt }, opt))) }), _jsx(Select, { size: "small", style: { width: 100 }, onChange: (val) => onUpdateAll('precision', val), defaultValue: "single", children: precisionOptions.map((opt) => (_jsx(Option, { value: opt, children: opt }, opt))) }), _jsx(Select, { size: "small", style: { width: 100 }, onChange: (val) => onUpdateAll('version', val), defaultValue: "R15", children: versionOptions.map((opt) => (_jsx(Option, { value: opt, children: opt }, opt))) }), _jsx(Select, { size: "small", style: { width: 100 }, onChange: (val) => onUpdateAll('mode', val), defaultValue: "SMP", children: modeOptions.map((opt) => (_jsx(Option, { value: opt, children: opt }, opt))) })] })] }));
};
export default LsdynaOptionTable;
