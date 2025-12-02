import { jsx as _jsx } from "react/jsx-runtime";
import { Table } from "antd";
const ResultTable = ({ result }) => {
    const dataSource = result.loads.map((load, i) => ({
        key: i,
        load: load.toFixed(2),
        deflection: result.deflections[i].toFixed(5),
        curvature: result.curvatures[i].toExponential(3),
        moment: result.moments[i].toFixed(3)
    }));
    const columns = [
        {
            title: "Load (N)",
            dataIndex: "load",
            key: "load"
        },
        {
            title: "Deflection (mm)",
            dataIndex: "deflection",
            key: "deflection"
        },
        {
            title: "Curvature (rad/m)",
            dataIndex: "curvature",
            key: "curvature"
        },
        {
            title: "Moment (Nm)",
            dataIndex: "moment",
            key: "moment"
        }
    ];
    return (_jsx("div", { style: { marginTop: 24 }, children: _jsx(Table, { dataSource: dataSource, columns: columns, pagination: false, size: "small", bordered: true }) }));
};
export default ResultTable;
