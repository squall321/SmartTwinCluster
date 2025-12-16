import { jsx as _jsx } from "react/jsx-runtime";
// components/JobStatsComponent.tsx
import { useEffect, useState } from 'react';
import { Table } from 'antd';
import { getJobStats } from '../services/slurmapi';
const JobStatsComponent = () => {
    const [stats, setStats] = useState({
        running: 0,
        pending: 0,
        failed: 0,
        completed: 0,
        others: 0,
    });
    useEffect(() => {
        getJobStats().then(setStats);
    }, []);
    const dataSource = Object.entries(stats).map(([name, data]) => ({
        key: name,
        name,
        ...data,
    }));
    const columns = [
        { title: 'Job Name', dataIndex: 'name' },
        { title: 'Count', dataIndex: 'count' },
        { title: 'Avg Runtime (s)', dataIndex: 'average_runtime_sec' },
        { title: 'Min Runtime (s)', dataIndex: 'min_runtime_sec' },
        { title: 'Max Runtime (s)', dataIndex: 'max_runtime_sec' },
    ];
    return _jsx(Table, { dataSource: dataSource, columns: columns, pagination: false });
};
export default JobStatsComponent;
