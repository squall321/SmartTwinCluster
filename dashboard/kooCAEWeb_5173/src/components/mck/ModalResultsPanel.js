import { jsx as _jsx } from "react/jsx-runtime";
import { Table, Card } from 'antd';
const ModalResultsPanel = ({ modalResults }) => {
    const columns = [
        { title: 'Mode', dataIndex: 'mode', width: 80 },
        { title: 'Frequency (Hz)', dataIndex: 'frequency', width: 150 },
        { title: 'Damping Ratio (%)', dataIndex: 'damping', width: 150 }
    ];
    const data = modalResults?.frequencies.map((f, i) => ({
        key: i,
        mode: i + 1,
        frequency: f.toFixed(3),
        damping: (modalResults.dampingRatios[i] * 100).toFixed(3),
    })) || [];
    return (_jsx(Card, { title: "Modal Analysis Results", size: "small", style: { marginTop: 16 }, children: _jsx(Table, { columns: columns, dataSource: data, pagination: false, locale: { emptyText: "No modal results." }, size: "small" }) }));
};
export default ModalResultsPanel;
