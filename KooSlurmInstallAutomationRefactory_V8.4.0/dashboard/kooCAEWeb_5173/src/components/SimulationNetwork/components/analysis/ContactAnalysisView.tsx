/**
 * 접촉 분석 뷰 컴포넌트
 * 접촉 타입, 면적, 통계를 시각화
 */

import React, { useState, useEffect } from 'react';
import { Card, Row, Col, Table, Tag, Statistic, Progress, Typography, Spin, Empty } from 'antd';
import { Pie, Bar } from '@ant-design/charts';
import { ContactsOutlined, AreaChartOutlined, PieChartOutlined } from '@ant-design/icons';
import { simulationAnalysisService, type ContactAnalysis } from '../../services/analysisService';

const { Title, Text } = Typography;

interface ContactAnalysisViewProps {
  selectedCases: string[];
}

const ContactAnalysisView: React.FC<ContactAnalysisViewProps> = ({ selectedCases }) => {
  const [loading, setLoading] = useState(false);
  const [contactData, setContactData] = useState<ContactAnalysis[]>([]);
  const [aggregatedStats, setAggregatedStats] = useState<any>(null);

  useEffect(() => {
    if (selectedCases.length === 0) {
      setContactData([]);
      setAggregatedStats(null);
      return;
    }

    const analyzeContacts = async () => {
      setLoading(true);
      
      try {
        const results = await Promise.all(
          selectedCases.map(async (caseId) => {
            try {
              const result = await simulationAnalysisService.analyzeSingleCase(caseId);
              return {
                caseId,
                ...result.analysis.contact_analysis
              };
            } catch (error) {
              console.error(`Failed to analyze case ${caseId}:`, error);
              return null;
            }
          })
        );

        const validResults = results.filter(Boolean) as (ContactAnalysis & { caseId: string })[];
        setContactData(validResults);

        // 집계 통계 계산
        if (validResults.length > 0) {
          const totalContacts = validResults.reduce((sum, data) => sum + data.total_contacts, 0);
          const allTypes: Record<string, number> = {};
          
          validResults.forEach(data => {
            Object.entries(data.contact_types).forEach(([type, count]) => {
              allTypes[type] = (allTypes[type] || 0) + count;
            });
          });

          setAggregatedStats({
            totalCases: validResults.length,
            totalContacts,
            averageContacts: totalContacts / validResults.length,
            contactTypes: allTypes
          });
        }
      } catch (error) {
        console.error('Contact analysis failed:', error);
      } finally {
        setLoading(false);
      }
    };

    analyzeContacts();
  }, [selectedCases]);

  // 접촉 타입 파이 차트 데이터
  const pieData = aggregatedStats ? Object.entries(aggregatedStats.contactTypes).map(([type, count]) => ({
    type: type.replace('KooContact', '').replace('SurfacetoSurface', 'S2S'),
    value: count,
    percentage: ((count as number / aggregatedStats.totalContacts) * 100).toFixed(1)
  })) : [];

  // 케이스별 접촉 수 바 차트 데이터
  const barData = contactData.map(data => ({
    case: (data as ContactAnalysis & { caseId: string }).caseId,
    contacts: data.total_contacts
  }));

  // 접촉 타입별 상세 테이블 컬럼
  const contactTypeColumns = [
    {
      title: '접촉 타입',
      dataIndex: 'type',
      key: 'type',
      render: (text: string) => (
        <Tag color="blue">{text.replace('KooContact', '').replace('SurfacetoSurface', 'S2S')}</Tag>
      )
    },
    {
      title: '총 개수',
      dataIndex: 'count',
      key: 'count',
      sorter: (a: any, b: any) => a.count - b.count,
      render: (value: number) => <Text strong>{value}</Text>
    },
    {
      title: '비율',
      dataIndex: 'percentage',
      key: 'percentage',
      render: (value: string) => (
        <Progress 
          percent={parseFloat(value)} 
          size="small" 
          format={percent => `${percent}%`}
        />
      )
    }
  ];

  const contactTypeTableData = aggregatedStats ? Object.entries(aggregatedStats.contactTypes).map(([type, count]) => ({
    key: type,
    type,
    count: count as number,
    percentage: ((count as number / aggregatedStats.totalContacts) * 100).toFixed(1)
  })) : [];

  // 케이스별 상세 정보 테이블 컬럼
  const caseDetailColumns = [
    {
      title: '케이스 ID',
      dataIndex: 'caseId',
      key: 'caseId',
      render: (text: string) => <Text code>{text}</Text>
    },
    {
      title: '총 접촉 수',
      dataIndex: 'total_contacts',
      key: 'total_contacts',
      sorter: (a: any, b: any) => a.total_contacts - b.total_contacts,
      render: (value: number) => (
        <Statistic 
          value={value} 
          valueStyle={{ fontSize: '14px' }} 
          prefix={<ContactsOutlined />}
        />
      )
    },
    {
      title: '총 면적',
      dataIndex: ['area_stats', 'total_area'],
      key: 'total_area',
      render: (value: number) => value ? `${value.toFixed(1)}` : 'N/A'
    },
    {
      title: '평균 면적',
      dataIndex: ['area_stats', 'average_area'],
      key: 'average_area',
      render: (value: number) => value ? `${value.toFixed(1)}` : 'N/A'
    },
    {
      title: '최대 접촉',
      dataIndex: ['largest_contact', 'total_area'],
      key: 'largest_contact',
      render: (value: number) => value ? `${value.toFixed(1)}` : 'N/A'
    }
  ];

  if (selectedCases.length === 0) {
    return (
      <Card>
        <Empty 
          description="분석할 케이스를 선택해주세요"
          image={Empty.PRESENTED_IMAGE_SIMPLE}
        />
      </Card>
    );
  }

  return (
    <Spin spinning={loading}>
      <div>
        {/* 전체 통계 */}
        {aggregatedStats && (
          <Row gutter={16} style={{ marginBottom: '24px' }}>
            <Col span={6}>
              <Card>
                <Statistic
                  title="총 케이스 수"
                  value={aggregatedStats.totalCases}
                  prefix={<ContactsOutlined />}
                />
              </Card>
            </Col>
            <Col span={6}>
              <Card>
                <Statistic
                  title="총 접촉 수"
                  value={aggregatedStats.totalContacts}
                  prefix={<ContactsOutlined />}
                  valueStyle={{ color: '#1890ff' }}
                />
              </Card>
            </Col>
            <Col span={6}>
              <Card>
                <Statistic
                  title="평균 접촉 수"
                  value={aggregatedStats.averageContacts}
                  precision={1}
                  prefix={<AreaChartOutlined />}
                  valueStyle={{ color: '#52c41a' }}
                />
              </Card>
            </Col>
            <Col span={6}>
              <Card>
                <Statistic
                  title="접촉 타입 수"
                  value={Object.keys(aggregatedStats.contactTypes).length}
                  prefix={<PieChartOutlined />}
                  valueStyle={{ color: '#722ed1' }}
                />
              </Card>
            </Col>
          </Row>
        )}

        {/* 차트 섹션 */}
        <Row gutter={16} style={{ marginBottom: '24px' }}>
          <Col span={12}>
            <Card title="접촉 타입 분포" size="small">
              {pieData.length > 0 ? (
                <Pie
                  data={pieData}
                  angleField="value"
                  colorField="type"
                  radius={0.8}
                  label={{
                    type: 'outer',
                    content: '{name}: {percentage}%'
                  }}
                  height={300}
                />
              ) : (
                <Empty description="데이터 없음" />
              )}
            </Card>
          </Col>
          <Col span={12}>
            <Card title="케이스별 접촉 수" size="small">
              {barData.length > 0 ? (
                <Bar
                  data={barData}
                  xField="contacts"
                  yField="case"
                  seriesField="case"
                  height={300}
                  color="#1890ff"
                />
              ) : (
                <Empty description="데이터 없음" />
              )}
            </Card>
          </Col>
        </Row>

        {/* 접촉 타입별 상세 테이블 */}
        <Card title="접촉 타입별 통계" style={{ marginBottom: '24px' }}>
          <Table
            columns={contactTypeColumns}
            dataSource={contactTypeTableData}
            size="small"
            pagination={false}
          />
        </Card>

        {/* 케이스별 상세 정보 */}
        <Card title="케이스별 접촉 분석">
          <Table
            columns={caseDetailColumns}
            dataSource={contactData}
            rowKey="caseId"
            size="small"
            pagination={{
              pageSize: 10,
              showSizeChanger: true
            }}
          />
        </Card>
      </div>
    </Spin>
  );
};

export default ContactAnalysisView;
