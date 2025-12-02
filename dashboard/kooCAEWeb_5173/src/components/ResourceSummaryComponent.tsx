// components/ResourceSummary.tsx
import React, { useEffect, useState } from 'react';
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

      sinfoLines.forEach((line: string) => {
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
    } catch (error) {
      console.error("코어 사용량을 가져오는 데 실패했습니다:", error);
    }
  };

  useEffect(() => {
    fetchCoreUsage();
    const interval = setInterval(fetchCoreUsage, 1000);
    return () => clearInterval(interval);
  }, []);

  return (
    <Row gutter={16}>
      <Col span={8}>
        <Card>
          <Statistic title="전체 코어 수" value={summary.total_cores || 0} />
        </Card>
      </Col>
      <Col span={8}>
        <Card>
          <Statistic title="사용 중인 코어" value={summary.used_cores || 0} />
        </Card>
      </Col>
      <Col span={8}>
        <Card>
          <Statistic title="LSDYNA 코어 사용량" value={summary.lsdyna_cores || 0} />
        </Card>
      </Col>
    </Row>
  );
};

export default ResourceSummary;
