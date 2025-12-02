import React from "react";
import { Table } from "antd";
import { SimulationResult } from "../../../types/threepointbending";

interface Props {
  result: SimulationResult;
}

const ResultTable: React.FC<Props> = ({ result }) => {
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

  return (
    <div style={{ marginTop: 24 }}>
      <Table
        dataSource={dataSource}
        columns={columns}
        pagination={false}
        size="small"
        bordered
      />
    </div>
  );
};

export default ResultTable;
