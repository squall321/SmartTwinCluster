/**
 * 부품 분석 뷰 컴포넌트
 * 부품 카테고리, 연결성, 고립된 부품을 분석
 */

import React, { useState, useEffect } from 'react';
import { Card, Row, Col, Table, Tag, Statistic, List, Typography, Spin, Empty, Progress } from 'antd';
import { Column, Pie } from '@ant-design/charts';
import { BuildOutlined, DisconnectOutlined, NodeIndexOutlined, WarningOutlined } from '@ant-design/icons';
import { simulationAnalysisService, type PartsAnalysis } from '../../services/analysisService';

const { Title, Text } = Typography;

interface PartsAnalysisViewProps {
  selectedCases: string[];
}

const PartsAnalysisView: React.FC<PartsAnalysisViewProps> = ({ selectedCases }) => {
  const [loading, setLoading] = useState(false);
  const [partsData, setPartsData] = useState<(PartsAnalysis & { caseId: string })[]>([]);
  const [aggregatedStats, setAggregatedStats] = useState<any>(null);

  useEffect(() => {
    if (selectedCases.length === 0) {
      setPartsData([]);
      setAggregatedStats(null);
      return;
    }

    const analyzeParts = async () => {
      setLoading(true);
      
      try {
        const results = await Promise.all(
          selectedCases.map(async (caseId) => {
            try {
              const result = await simulationAnalysisService.analyzeSingleCase(caseId);
              return {
                caseId,
                ...result.analysis.parts_analysis
              };
            } catch (error) {
              console.error(`Failed to analyze parts for case ${caseId}:`, error);
              return null;
            }
          })
        );

        const validResults = results.filter(Boolean) as (PartsAnalysis & { caseId: string })[];
        setPartsData(validResults);

        // 집계 통계 계산
        if (validResults.length > 0) {
          const totalParts = validResults.reduce((sum, data) => sum + data.total_parts, 0);
          const totalConnectedParts = validResults.reduce((sum, data) => sum + data.parts_with_contacts, 0);
          const allCategories: Record<string, number> = {};
          const allIsolatedParts: string[] = [];
          
          validResults.forEach(data => {
            Object.entries(data.part_categories).forEach(([category, count]) => {
              allCategories[category] = (allCategories[category] || 0) + count;
            });
            allIsolatedParts.push(...data.isolated_parts);
          });

          setAggregatedStats({
            totalCases: validResults.length,
            totalParts,
            totalConnectedParts,
            averageParts: totalParts / validResults.length,
            connectionRate: totalParts > 0 ? (totalConnectedParts / totalParts) * 100 : 0,
            partCategories: allCategories,
            totalIsolatedParts: allIsolatedParts.length
          });
        }
      } catch (error) {
        console.error('Parts analysis failed:', error);
      } finally {
        setLoading(false);
      }
    };

    analyzeParts();
  }, [selectedCases]);

  // 부품 카테고리 파이 차트 데이터
  const categoryPieData = aggregatedStats ? Object.entries(aggregatedStats.partCategories).map(([category, count]) => ({
    type: category,
    value: count as number,
    percentage: ((count as number / aggregatedStats.totalParts) * 100).toFixed(1)
  })) : [];

  // 케이스별 부품 수 컬럼 차트 데이터
  const partsColumnData = partsData.map(data => ({
    case: (data as PartsAnalysis & { caseId: string }).caseId,
    total: data.total_parts,
    connected: data.parts_with_contacts,
    isolated: data.total_parts - data.parts_with_contacts
  }));

  // 부품 카테고리별 테이블 컬럼
  const categoryColumns = [
    {
      title: '부품 카테고리',
      dataIndex: 'category',
      key: 'category',
      render: (text: string) => <Tag color="green">{text}</Tag>
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

  const categoryTableData = aggregatedStats ? Object.entries(aggregatedStats.partCategories).map(([category, count]) => ({
    key: category,
    category,
    count: count as number,
    percentage: ((count as number / aggregatedStats.totalParts) * 100).toFixed(1)
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
      title: '총 부품 수',
      dataIndex: 'total_parts',
      key: 'total_parts',
      sorter: (a: any, b: any) => a.total_parts - b.total_parts,
      render: (value: number) => (
        <Statistic 
          value={value} 
          valueStyle={{ fontSize: '14px' }} 
          prefix={<BuildOutlined />}
        />
      )
    },
    {
      title: '연결된 부품',
      dataIndex: 'parts_with_contacts',
      key: 'parts_with_contacts',
      render: (value: number) => (
        <Statistic 
          value={value} 
          valueStyle={{ fontSize: '14px', color: '#52c41a' }} 
          prefix={<NodeIndexOutlined />}
        />
      )
    },
    {
      title: '고립된 부품',
      dataIndex: 'isolated_parts',
      key: 'isolated_parts',
      render: (parts: string[]) => (
        <Statistic 
          value={parts.length} 
          valueStyle={{ 
            fontSize: '14px', 
            color: parts.length > 0 ? '#ff4d4f' : '#52c41a' 
          }} 
          prefix={<DisconnectOutlined />}
        />
      )
    },
    {
      title: '연결률',
      key: 'connection_rate',
      render: (record: any) => {
        const rate = record.total_parts > 0 
          ? (record.parts_with_contacts / record.total_parts) * 100 
          : 0;
        
        return (
          <Progress 
            percent={Math.round(rate)} 
            size="small" 
            status={rate > 80 ? 'success' : rate > 50 ? 'normal' : 'exception'}
          />
        );
      }
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
                  title="총 부품 수"
                  value={aggregatedStats.totalParts}
                  prefix={<BuildOutlined />}
                  valueStyle={{ color: '#1890ff' }}
                />
              </Card>
            </Col>
            <Col span={6}>
              <Card>
                <Statistic
                  title="평균 부품 수"
                  value={aggregatedStats.averageParts}
                  precision={1}
                  prefix={<BuildOutlined />}
                  valueStyle={{ color: '#52c41a' }}
                />
              </Card>
            </Col>
            <Col span={6}>
              <Card>
                <Statistic
                  title="전체 연결률"
                  value={aggregatedStats.connectionRate}
                  precision={1}
                  suffix="%"
                  prefix={<NodeIndexOutlined />}
                  valueStyle={{ 
                    color: aggregatedStats.connectionRate > 80 ? '#52c41a' : '#faad14' 
                  }}
                />
              </Card>
            </Col>
            <Col span={6}>
              <Card>
                <Statistic
                  title="고립된 부품"
                  value={aggregatedStats.totalIsolatedParts}
                  prefix={<WarningOutlined />}
                  valueStyle={{ 
                    color: aggregatedStats.totalIsolatedParts > 0 ? '#ff4d4f' : '#52c41a' 
                  }}
                />
              </Card>
            </Col>
          </Row>
        )}

        {/* 차트 섹션 */}
        <Row gutter={16} style={{ marginBottom: '24px' }}>
          <Col span={12}>
            <Card title="부품 카테고리 분포" size="small">
              {categoryPieData.length > 0 ? (
                <Pie
                  data={categoryPieData}
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
            <Card title="케이스별 부품 연결성" size="small">
              {partsColumnData.length > 0 ? (
                <Column
                  data={partsColumnData.flatMap(item => [
                    { case: item.case, type: '연결된 부품', value: item.connected },
                    { case: item.case, type: '고립된 부품', value: item.isolated }
                  ])}
                  xField="case"
                  yField="value"
                  seriesField="type"
                  isStack={true}
                  height={300}
                  color={['#52c41a', '#ff4d4f']}
                />
              ) : (
                <Empty description="데이터 없음" />
              )}
            </Card>
          </Col>
        </Row>

        {/* 부품 카테고리별 상세 테이블 */}
        <Card title="부품 카테고리별 통계" style={{ marginBottom: '24px' }}>
          <Table
            columns={categoryColumns}
            dataSource={categoryTableData}
            size="small"
            pagination={false}
          />
        </Card>

        {/* 케이스별 상세 정보 */}
        <Row gutter={16}>
          <Col span={16}>
            <Card title="케이스별 부품 분석">
              <Table
                columns={caseDetailColumns}
                dataSource={partsData}
                rowKey="caseId"
                size="small"
                pagination={{
                  pageSize: 10,
                  showSizeChanger: true
                }}
              />
            </Card>
          </Col>
          <Col span={8}>
            <Card title="고립된 부품 목록" size="small">
              {partsData.length > 0 ? (
                <List
                  size="small"
                  dataSource={partsData.filter(data => data.isolated_parts.length > 0)}
                  renderItem={(data) => (
                    <List.Item>
                      <div style={{ width: '100%' }}>
                        <Text strong>{data.caseId}</Text>
                        <div style={{ marginTop: '4px' }}>
                          {data.isolated_parts.slice(0, 3).map((part, index) => (
                            <Tag key={index} color="red" style={{ margin: '2px' }}>
                              {part.length > 20 ? `${part.substring(0, 20)}...` : part}
                            </Tag>
                          ))}
                          {data.isolated_parts.length > 3 && (
                            <Tag color="orange">
                              +{data.isolated_parts.length - 3} 더
                            </Tag>
                          )}
                        </div>
                      </div>
                    </List.Item>
                  )}
                  locale={{ emptyText: '고립된 부품이 없습니다' }}
                />
              ) : (
                <Empty description="데이터 없음" />
              )}
            </Card>
          </Col>
        </Row>
      </div>
    </Spin>
  );
};

export default PartsAnalysisView;
