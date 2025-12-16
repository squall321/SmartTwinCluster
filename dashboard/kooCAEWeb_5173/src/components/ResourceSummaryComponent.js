import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// components/ResourceSummary.tsx
import { useEffect, useState } from 'react';
import { Card, Statistic, Row, Col } from 'antd';
import { api } from '../api/axiosClient';
const ResourceSummary = () => {
    const [summary, setSummary] = useState({
        total_cores: 0,
        used_cores: 0,
        lsdyna_cores: 0
    });
    const fetchCoreUsage = async () => {
        try {
            const [sinfoRes, lsdynaRes] = await Promise.all([
                api.get(`/api/slurm/sinfo`),
                api.get(`/api/slurm/lsdyna-core-usage`)
            ]);
            const sinfoLines = sinfoRes.data.output.split("\n").slice(1);
            let totalCores = 0;
            let usedCores = 0;
            sinfoLines.forEach((line) => {
                const cols = line.trim().split(/\s+/);
                const coreInfo = cols[4]; // format: 'used/idle/total/0'
                if (coreInfo && coreInfo.includes("/")) {
                    const [alloc, idle, total] = coreInfo.split("/").map(Number);
                    if (!isNaN(alloc) && !isNaN(total)) {
                        usedCores += alloc;
                        totalCores += total;
                    }
                }
            });
            setSummary({
                total_cores: totalCores,
                used_cores: usedCores,
                lsdyna_cores: lsdynaRes.data.lsdyna_cores || 0
            });
        }
        catch (error) {
            console.error("코어 사용량을 가져오는 데 실패했습니다:", error);
        }
    };
    useEffect(() => {
        fetchCoreUsage();
        const interval = setInterval(fetchCoreUsage, 1000);
        return () => clearInterval(interval);
    }, []);
    return (_jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 8, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uC804\uCCB4 \uCF54\uC5B4 \uC218", value: summary.total_cores || 0 }) }) }), _jsx(Col, { span: 8, children: _jsx(Card, { children: _jsx(Statistic, { title: "\uC0AC\uC6A9 \uC911\uC778 \uCF54\uC5B4", value: summary.used_cores || 0 }) }) }), _jsx(Col, { span: 8, children: _jsx(Card, { children: _jsx(Statistic, { title: "LSDYNA \uCF54\uC5B4 \uC0AC\uC6A9\uB7C9", value: summary.lsdyna_cores || 0 }) }) })] }));
};
export default ResourceSummary;
