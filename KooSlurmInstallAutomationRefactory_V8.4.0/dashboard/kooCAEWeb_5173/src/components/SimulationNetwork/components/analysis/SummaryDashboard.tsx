/**
 * 요약 대시보드 컴포넌트
 * 전체적인 분석 통계와 개요를 표시
 */

import React, { useState, useEffect } from 'react';
import { Card, Row, Col, Statistic, Progress, Table, Tag, Typography, Spin, Empty } from 'antd';
import { ContactsOutlined, BuildOutlined, AlertOutlined, CheckCircleOutlined } from '@ant-design/icons';
import { simulationAnalysisService, type BatchAnalysisResult } from '../../services/analysisService';

const { Title, Text } = Typography;

interface SummaryDashboardProps {
  selectedCases: string[];
  systemHealth?: any;
}

const SummaryDashboard: React.FC<SummaryDashboardProps> = ({ selectedCases, systemHealth }) => {
  const [loading, setLoading] = useState(false);
  const [summaryData, setSummaryData] = useState<BatchAnalysisResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  // 선택된 케이스들 분석
  useEffect(() => {
    if (selectedCases.length === 0) {
      setSummaryData(null);
      return;
    }

    const analyzeCases = async () => {
      setLoading(true);
      setError(null);
      
      try {
        const result = await simulationAnalysisService.analyzeBatch({
          case_ids: selectedCases,
          include_summary: true
        });
        setSummaryData(result);
      } catch (err) {
        setError('분석 중 오류가 발생했습니다.');
        console.error('Dashboard analysis failed:', err);
      } finally {
        setLoading(false);
      }
    };

    analyzeCases();
  }, [selectedCases]);

  // 성공률 계산
  const getSuccessRate = () => {
    if (!summaryData) return 0;
    return (summaryData.successful_analyses / summaryData.total_cases) * 100;
  };

  // 케이스별 요약 테이블 컬럼
  const caseColumns = [
    {
      title: '케이스 ID',
      dataIndex: 'case_id',
      key: 'case_id',
      render: (text: string) => <Text code>{text}</Text>
    },
    {
      title: '시나리오',
      dataIndex: ['analysis', 'basic_info', 'scenario_mode'],
      key: 'scenario_mode',
      render: (text: string) => <Tag color="blue">{text}</Tag>
    },
    {
      title: '접촉 수',
      dataIndex: ['analysis', 'contact_analysis', 'total_contacts'],
      key: 'contacts',
      render: (value: number) => (
        <Statistic 
          value={value} 
          valueStyle={{ fontSize: '14px' }}
          prefix={<ContactsOutlined />}
        />
      )
    },
    {
      title: '부품 수',
      dataIndex: ['analysis', 'parts_analysis', 'total_parts'],
      key: 'parts',
      render: (value: number) => (
        <Statistic 
          value={value} 
          valueStyle={{ fontSize: '14px' }}
          prefix={<BuildOutlined />}
        />
      )
    },
    {
      title: '연결률',
      key: 'connection_rate',
      render: (record: any) => {
        const parts = record.analysis.parts_analysis;
        const rate = parts.total_parts > 0 
          ? (parts.parts_with_contacts / parts.total_parts) * 100 
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
        {/* 전체 요약 통계 */}
        <Row gutter={16} style={{ marginBottom: '24px' }}>
          <Col span={6}>
            <Card>
              <Statistic
                title="선택된 케이스"
                value={selectedCases.length}
                prefix={<CheckCircleOutlined />}
                valueStyle={{ color: '#1890ff' }}
              />
            </Card>
          </Col>
          <Col span={6}>
            <Card>
              <Statistic
                title="분석 성공률"
                value={getSuccessRate()}
                suffix="%"
                prefix={<AlertOutlined />}
                valueStyle={{ 
                  color: getSuccessRate() > 80 ? '#52c41a' : '#faad14' 
                }}
              />
            </Card>
          </Col>
          <Col span={6}>
            <Card>
              <Statistic
                title="평균 접촉 수"
                value={summaryData?.summary_report?.contact_analysis.contact_stats.average || 0}
                precision={1}
                prefix={<ContactsOutlined />}
                valueStyle={{ color: '#722ed1' }}
              />
            </Card>
          </Col>
          <Col span={6}>
            <Card>
              <Statistic
                title="평균 부품 수"
                value={summaryData?.summary_report?.parts_analysis.parts_stats.average || 0}
                precision={1}
                prefix={<BuildOutlined />}
                valueStyle={{ color: '#13c2c2' }}
              />
            </Card>
          </Col>
        </Row>

        {/* 상세 요약 정보 */}
        {summaryData?.summary_report && (
          <Row gutter={16} style={{ marginBottom: '24px' }}>
            <Col span={12}>
              <Card title="접촉 통계" size="small">
                <Row gutter={16}>
                  <Col span={12}>
                    <Statistic 
                      title="최대" 
                      value={summaryData.summary_report.contact_analysis.contact_stats.max}
                    />
                  </Col>
                  <Col span={12}>
                    <Statistic 
                      title="최소" 
                      value={summaryData.summary_report.contact_analysis.contact_stats.min}
                    />
                  </Col>
                </Row>
              </Card>
            </Col>
            <Col span={12}>
              <Card title="부품 통계" size="small">
                <Row gutter={16}>
                  <Col span={12}>
                    <Statistic 
                      title="최대" 
                      value={summaryData.summary_report.parts_analysis.parts_stats.max}
                    />
                  </Col>
                  <Col span={12}>
                    <Statistic 
                      title="최소" 
                      value={summaryData.summary_report.parts_analysis.parts_stats.min}
                    />
                  </Col>
                </Row>
              </Card>
            </Col>
          </Row>
        )}

        {/* 시나리오 모드 분포 */}
        {summaryData?.summary_report?.summary.scenario_modes && (
          <Card title="시나리오 모드 분포" style={{ marginBottom: '24px' }} size="small">
            <Row gutter={16}>
              {Object.entries(summaryData.summary_report.summary.scenario_modes).map(([mode, count]) => (
                <Col key={mode} span={6}>
                  <Statistic 
                    title={mode} 
                    value={count}
                    valueStyle={{ fontSize: '18px' }}
                  />
                </Col>
              ))}
            </Row>
          </Card>
        )}

        {/* 개별 케이스 요약 테이블 */}
        <Card title="케이스별 요약">
          <Table
            columns={caseColumns}
            dataSource={summaryData?.analyses || []}
            rowKey="case_id"
            size="small"
            pagination={{
              pageSize: 10,
              showSizeChanger: true,
              showQuickJumper: true,
              showTotal: (total) => `총 ${total}개 케이스`
            }}
          />
        </Card>

        {/* 실패한 케이스들 */}
        {summaryData && summaryData.failed_cases.length > 0 && (
          <Card 
            title="분석 실패 케이스" 
            style={{ marginTop: '16px' }}
            headStyle={{ color: '#ff4d4f' }}
          >
            <div>
              {summaryData.failed_cases.map(caseId => (
                <Tag key={caseId} color="red" style={{ marginBottom: '8px' }}>
                  {caseId}
                </Tag>
              ))}
            </div>
          </Card>
        )}

        {error && (
          <Card 
            title="오류" 
            style={{ marginTop: '16px' }}
            headStyle={{ color: '#ff4d4f' }}
          >
            <Text type="danger">{error}</Text>
          </Card>
        )}
      </div>
    </Spin>
  );
};

export default SummaryDashboard;
