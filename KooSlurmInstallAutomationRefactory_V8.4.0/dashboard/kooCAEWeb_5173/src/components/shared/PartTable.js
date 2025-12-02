import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { Table, Button, Typography } from 'antd';
const PartTable = ({ parts, editable = false, onRemove, title }) => {
    const columns = [
        { title: 'ID', dataIndex: 'id', key: 'id' },
        { title: '이름', dataIndex: 'name', key: 'name' },
        ...(editable
            ? [{
                    title: '작업',
                    key: 'action',
                    render: (_, record) => (_jsx(Button, { danger: true, onClick: () => onRemove?.(record.id), children: "\uC81C\uAC70" })),
                }]
            : []),
    ];
    return (_jsxs("div", { style: { marginTop: 24 }, children: [title && _jsx(Typography.Text, { strong: true, children: title }), _jsx(Table, { dataSource: parts.map((p, i) => ({ ...p, key: i })), columns: columns, pagination: false, size: "small", bordered: true, style: { marginTop: 12 } })] }));
};
export default PartTable;
