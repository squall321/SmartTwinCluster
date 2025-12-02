/**
 * 시뮬레이션 분석 메인 패널
 * 분석 기능들을 통합한 메인 컴포넌트
 */

import React, { useState, useEffect } from 'react';
import { Tabs, Card, Button, Select, Space, Alert, Spin, Typography, Row, Col, Statistic } from 'antd';
import { BarChartOutlined, PieChartOutlined, TableOutlined, DashboardOutlined, ReloadOutlined } from '@ant-design/icons';
import { simulationAnalysisService } from '../../services/analysisService';
import { useSimulationNetworkStore } from '../../store/simulationnetworkStore';
import ContactAnalysisView from './ContactAnalysisView';
import PartsAnalysisView from './PartsAnalysisView';
import CaseAnalysisView from './CaseAnalysisView.js';
import SummaryDashboard from './SummaryDashboard';
import { SimulationNode } from '../../types/simulationnetwork';

const { Title, Text } = Typography;
const { Option } = Select;

const AnalysisPanel: React.FC = () => {
  const nodes = useSimulationNetworkStore((state: ReturnType<typeof useSimulationNetworkStore.getState>) => state.nodes);
  const selectedNode = useSimulationNetworkStore((state: ReturnType<typeof useSimulationNetworkStore.getState>) => state.selectedNode);
  
  // 상태 관리
  const [activeTab, setActiveTab] = useState('dashboard');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [systemHealth, setSystemHealth] = useState<any>(null);
  const [selectedCases, setSelectedCases] = useState<string[]>([]);
  const [analysisMode, setAnalysisMode] = useState<'single' | 'batch'>('single');

  // 케이스 목록 (노드에서 추출)
  const availableCases: Array<{ id: string; label: string; status: SimulationNode['status'] }> = nodes.map((node: SimulationNode) => ({
    id: node.id,
    label: node.label || node.id,
    status: node.status
  }));

  // 시스템 상태 확인
  useEffect(() => {
    const checkHealth = async () => {
      try {
        const health = await simulationAnalysisService.checkSystemHealth();
        setSystemHealth(health);
      } catch (error) {
        console.error('Health check failed:', error);
      }
    };

    checkHealth();
  }, []);

  // 선택된 노드가 변경되면 단일 케이스 모드로 설정
  useEffect(() => {
    if (selectedNode) {
      setSelectedCases([selectedNode.id]);
      setAnalysisMode('single');
    }
  }, [selectedNode]);

  // 전체 새로고침
  const handleRefresh = async () => {
    setLoading(true);
    setError(null);
    
    try {
      const health = await simulationAnalysisService.checkSystemHealth();
      setSystemHealth(health);
    } catch (err) {
      setError('시스템 상태 확인에 실패했습니다.');
    } finally {
      setLoading(false);
    }
  };

  // 케이스 선택 변경
  const handleCaseSelection = (caseIds: string[]) => {
    setSelectedCases(caseIds);
    setAnalysisMode(caseIds.length === 1 ? 'single' : 'batch');
  };

  // 탭 아이템 구성
  const tabItems = [
    {
      key: 'dashboard',
      label: (
        <span>
          <DashboardOutlined />
          대시보드
        </span>
      ),
      children: (
        <SummaryDashboard 
          selectedCases={selectedCases}
          systemHealth={systemHealth}
        />
      )
    },
    {
      key: 'case-analysis',
      label: (
        <span>
          <TableOutlined />
          케이스 분석
        </span>
      ),
      children: (
        <CaseAnalysisView 
          selectedCases={selectedCases}
          analysisMode={analysisMode}
        />
      )
    },
    {
      key: 'contact-analysis',
      label: (
        <span>
          <PieChartOutlined />
          접촉 분석
        </span>
      ),
      children: (
        <ContactAnalysisView 
          selectedCases={selectedCases}
        />
      )
    },
    {
      key: 'parts-analysis',
      label: (
        <span>
          <BarChartOutlined />
          부품 분석
        </span>
      ),
      children: (
        <PartsAnalysisView 
          selectedCases={selectedCases}
        />
      )
    }
  ];

  return (
    <div style={{ padding: '16px', backgroundColor: '#f5f5f5', minHeight: '100vh' }}>
      {/* 헤더 섹션 */}
      <Card style={{ marginBottom: '16px' }}>
        <Row justify="space-between" align="middle">
          <Col>
            <Title level={3} style={{ margin: 0 }}>
              <DashboardOutlined style={{ color: '#1890ff', marginRight: '8px' }} />
              시뮬레이션 분석
            </Title>
            <Text type="secondary">
              DropSet.json 데이터를 분석하여 접촉, 부품, 품질 정보를 제공합니다
            </Text>
          </Col>
          <Col>
            <Space>
              <Button 
                icon={<ReloadOutlined />} 
                onClick={handleRefresh}
                loading={loading}
              >
                새로고침
              </Button>
            </Space>
          </Col>
        </Row>

        {/* 시스템 상태 표시 */}
        {systemHealth && (
          <Row gutter={16} style={{ marginTop: '16px' }}>
            <Col span={6}>
              <Statistic 
                title="사용 가능한 케이스" 
                value={systemHealth.available_cases}
                prefix={<TableOutlined />}
              />
            </Col>
            <Col span={6}>
              <Statistic 
                title="분석 가능한 케이스" 
                value={systemHealth.analyzable_cases}
                prefix={<DashboardOutlined />}
                valueStyle={{ 
                  color: systemHealth.analyzable_cases > 0 ? '#52c41a' : '#ff4d4f' 
                }}
              />
            </Col>
            <Col span={6}>
              <Statistic 
                title="선택된 케이스" 
                value={selectedCases.length}
                prefix={<PieChartOutlined />}
              />
            </Col>
            <Col span={6}>
              <Statistic 
                title="분석 모드" 
                value={analysisMode === 'single' ? '단일' : '일괄'}
                prefix={<BarChartOutlined />}
              />
            </Col>
          </Row>
        )}
      </Card>

      {/* 케이스 선택 섹션 */}
      <Card style={{ marginBottom: '16px' }} title="분석 대상 선택">
        <Row gutter={16} align="middle">
          <Col flex="auto">
            <Select
              mode="multiple"
              placeholder="분석할 케이스를 선택하세요"
              value={selectedCases}
              onChange={handleCaseSelection}
              style={{ width: '100%' }}
              showSearch
              filterOption={(input, option) =>
                option?.children?.toString().toLowerCase().includes(input.toLowerCase()) ?? false
              }
            >
              {availableCases.map(case_ => (
                <Option key={case_.id} value={case_.id}>
                  <Space>
                    <span>{case_.label}</span>
                    <Text type="secondary">({case_.status})</Text>
                  </Space>
                </Option>
              ))}
            </Select>
          </Col>
          <Col>
            <Text type="secondary">
              {selectedCases.length > 0 
                ? `${selectedCases.length}개 케이스 선택됨`
                : '케이스를 선택해주세요'
              }
            </Text>
          </Col>
        </Row>

        {/* 선택된 노드 정보 */}
        {selectedNode && (
          <Alert
            style={{ marginTop: '12px' }}
            message={`현재 선택된 노드: ${selectedNode.label || selectedNode.id}`}
            description="그래프에서 노드를 선택하면 해당 케이스가 자동으로 분석 대상으로 설정됩니다."
            type="info"
            showIcon
            closable
            onClose={() => setSelectedCases([])}
          />
        )}
      </Card>

      {/* 에러 메시지 */}
      {error && (
        <Alert 
          message="오류 발생" 
          description={error} 
          type="error" 
          closable 
          onClose={() => setError(null)}
          style={{ marginBottom: '16px' }}
        />
      )}

      {/* 메인 분석 탭 */}
      <Spin spinning={loading}>
        <Tabs
          activeKey={activeTab}
          onChange={setActiveTab}
          items={tabItems}
          size="large"
        />
      </Spin>
    </div>
  );
};

export default AnalysisPanel;
