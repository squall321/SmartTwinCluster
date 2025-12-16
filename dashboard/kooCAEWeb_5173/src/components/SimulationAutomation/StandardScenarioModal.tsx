/**
 * Standard Scenario Modal Component
 * 표준 규격 시나리오 선택 모달
 */

import React, { useState, useEffect } from 'react';
import { Modal, Card, Button, Tag, Spin, Alert, Tabs, Descriptions, Empty } from 'antd';
import {
  ExperimentOutlined,
  FallOutlined,
  ThunderboltOutlined,
  RotateRightOutlined,
  SafetyOutlined,
  CheckCircleOutlined
} from '@ant-design/icons';
import type { StandardScenarioSummary, StandardScenario, CategoryInfo } from '../../types/standardScenario';
import axios from 'axios';

const { TabPane } = Tabs;

interface StandardScenarioModalProps {
  visible: boolean;
  onClose: () => void;
  onSelect: (scenario: StandardScenario) => void;
}

const StandardScenarioModal: React.FC<StandardScenarioModalProps> = ({
  visible,
  onClose,
  onSelect
}) => {
  const [scenarios, setScenarios] = useState<StandardScenarioSummary[]>([]);
  const [categories, setCategories] = useState<CategoryInfo[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [selectedScenario, setSelectedScenario] = useState<StandardScenarioSummary | null>(null);
  const [scenarioDetail, setScenarioDetail] = useState<StandardScenario | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [detailLoading, setDetailLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // 시나리오 목록 로드
  useEffect(() => {
    if (visible) {
      fetchScenarios();
      fetchCategories();
    }
  }, [visible]);

  // 선택된 시나리오 상세 정보 로드
  useEffect(() => {
    if (selectedScenario) {
      fetchScenarioDetail(selectedScenario.id);
    }
  }, [selectedScenario]);

  const fetchScenarios = async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await axios.get('/cae/api/standard-scenarios/');
      setScenarios(response.data.scenarios || []);
    } catch (err: any) {
      setError(err?.response?.data?.error || '시나리오 목록을 불러오는데 실패했습니다.');
      console.error('Error fetching scenarios:', err);
    } finally {
      setLoading(false);
    }
  };

  const fetchCategories = async () => {
    try {
      const response = await axios.get('/cae/api/standard-scenarios/categories');
      setCategories([{ id: 'all', name: '전체' }, ...(response.data.categories || [])]);
    } catch (err) {
      console.error('Error fetching categories:', err);
    }
  };

  const fetchScenarioDetail = async (scenarioId: string) => {
    setDetailLoading(true);
    try {
      const response = await axios.get(`/cae/api/standard-scenarios/${scenarioId}`);
      setScenarioDetail(response.data.scenario);
    } catch (err: any) {
      console.error('Error fetching scenario detail:', err);
      setScenarioDetail(null);
    } finally {
      setDetailLoading(false);
    }
  };

  const handleScenarioClick = (scenario: StandardScenarioSummary) => {
    setSelectedScenario(scenario);
  };

  const handleAddScenario = () => {
    if (scenarioDetail) {
      onSelect(scenarioDetail);
      handleClose();
    }
  };

  const handleClose = () => {
    setSelectedScenario(null);
    setScenarioDetail(null);
    setSelectedCategory('all');
    onClose();
  };

  // 카테고리 필터링
  const filteredScenarios = scenarios.filter(
    s => selectedCategory === 'all' || s.category === selectedCategory
  );

  // 카테고리 아이콘
  const getCategoryIcon = (category: string) => {
    switch (category) {
      case 'fall_test':
        return <FallOutlined />;
      case 'cumulative_test':
        return <ThunderboltOutlined />;
      case 'impact_test':
        return <ExperimentOutlined />;
      case 'rotation_test':
        return <RotateRightOutlined />;
      case 'attitude_test':
        return <SafetyOutlined />;
      default:
        return <ExperimentOutlined />;
    }
  };

  // 카테고리 색상
  const getCategoryColor = (category: string) => {
    switch (category) {
      case 'fall_test':
        return 'blue';
      case 'cumulative_test':
        return 'orange';
      case 'impact_test':
        return 'red';
      case 'rotation_test':
        return 'purple';
      case 'attitude_test':
        return 'green';
      default:
        return 'default';
    }
  };

  return (
    <Modal
      title="규격 시나리오 선택"
      open={visible}
      onCancel={handleClose}
      width={1000}
      footer={[
        <Button key="cancel" onClick={handleClose}>
          취소
        </Button>,
        <Button
          key="submit"
          type="primary"
          disabled={!scenarioDetail}
          onClick={handleAddScenario}
          icon={<CheckCircleOutlined />}
        >
          시나리오 추가
        </Button>
      ]}
    >
      {error && (
        <Alert
          message="오류"
          description={error}
          type="error"
          closable
          onClose={() => setError(null)}
          style={{ marginBottom: 16 }}
        />
      )}

      <Tabs
        activeKey={selectedCategory}
        onChange={setSelectedCategory}
        style={{ marginBottom: 16 }}
      >
        {categories.map(cat => (
          <TabPane tab={cat.name} key={cat.id} />
        ))}
      </Tabs>

      <div style={{ display: 'flex', gap: '16px', minHeight: '500px' }}>
        {/* 시나리오 목록 */}
        <div style={{ flex: 1, overflowY: 'auto', maxHeight: '500px' }}>
          {loading ? (
            <div style={{ textAlign: 'center', padding: '50px' }}>
              <Spin size="large" tip="시나리오 목록을 불러오는 중..." />
            </div>
          ) : filteredScenarios.length === 0 ? (
            <Empty description="표준 시나리오가 없습니다" />
          ) : (
            <div style={{ display: 'grid', gap: '12px' }}>
              {filteredScenarios.map(scenario => (
                <Card
                  key={scenario.id}
                  hoverable
                  onClick={() => handleScenarioClick(scenario)}
                  style={{
                    border: selectedScenario?.id === scenario.id ? '2px solid #1890ff' : '1px solid #d9d9d9',
                    cursor: 'pointer'
                  }}
                  bodyStyle={{ padding: '12px' }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'start' }}>
                    <div style={{ flex: 1 }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px' }}>
                        {getCategoryIcon(scenario.category)}
                        <strong>{scenario.name}</strong>
                      </div>
                      <div style={{ fontSize: '12px', color: '#666', marginBottom: '8px' }}>
                        {scenario.description}
                      </div>
                      <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
                        <Tag color={getCategoryColor(scenario.category)} style={{ margin: 0 }}>
                          {categories.find(c => c.id === scenario.category)?.name || scenario.category}
                        </Tag>
                        <Tag color="cyan" style={{ margin: 0 }}>
                          📐 {scenario.angleCount}개 각도
                        </Tag>
                        <Tag color="default" style={{ margin: 0 }}>
                          v{scenario.version}
                        </Tag>
                      </div>
                    </div>
                  </div>
                </Card>
              ))}
            </div>
          )}
        </div>

        {/* 시나리오 상세 정보 */}
        <div style={{ flex: 1, borderLeft: '1px solid #d9d9d9', paddingLeft: '16px', overflowY: 'auto', maxHeight: '500px' }}>
          {detailLoading ? (
            <div style={{ textAlign: 'center', padding: '50px' }}>
              <Spin tip="상세 정보를 불러오는 중..." />
            </div>
          ) : scenarioDetail ? (
            <div>
              <h3 style={{ marginBottom: '16px' }}>{scenarioDetail.name}</h3>

              <Descriptions bordered size="small" column={1} style={{ marginBottom: '16px' }}>
                <Descriptions.Item label="설명">
                  {scenarioDetail.description}
                </Descriptions.Item>
                <Descriptions.Item label="카테고리">
                  <Tag color={getCategoryColor(scenarioDetail.category)}>
                    {categories.find(c => c.id === scenarioDetail.category)?.name || scenarioDetail.category}
                  </Tag>
                </Descriptions.Item>
                <Descriptions.Item label="버전">
                  {scenarioDetail.version}
                </Descriptions.Item>
                <Descriptions.Item label="각도 수">
                  {scenarioDetail.angles.length}개
                </Descriptions.Item>
              </Descriptions>

              {scenarioDetail.metadata && (
                <>
                  {scenarioDetail.metadata.standardReference && (
                    <Descriptions bordered size="small" column={1} style={{ marginBottom: '8px' }}>
                      <Descriptions.Item label="표준 참조">
                        {scenarioDetail.metadata.standardReference}
                      </Descriptions.Item>
                    </Descriptions>
                  )}

                  {scenarioDetail.metadata.testMethod && (
                    <Descriptions bordered size="small" column={1} style={{ marginBottom: '8px' }}>
                      <Descriptions.Item label="시험 방법">
                        {scenarioDetail.metadata.testMethod}
                      </Descriptions.Item>
                    </Descriptions>
                  )}

                  {scenarioDetail.metadata.requiredEquipment && scenarioDetail.metadata.requiredEquipment.length > 0 && (
                    <div style={{ marginBottom: '8px' }}>
                      <div style={{ fontWeight: 'bold', marginBottom: '4px', fontSize: '12px' }}>필요 장비:</div>
                      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px' }}>
                        {scenarioDetail.metadata.requiredEquipment.map((eq: string, idx: number) => (
                          <Tag key={idx} color="blue" style={{ margin: 0 }}>
                            {eq}
                          </Tag>
                        ))}
                      </div>
                    </div>
                  )}

                  {scenarioDetail.metadata.safetyRequirements && scenarioDetail.metadata.safetyRequirements.length > 0 && (
                    <div style={{ marginBottom: '8px' }}>
                      <div style={{ fontWeight: 'bold', marginBottom: '4px', fontSize: '12px' }}>안전 요구사항:</div>
                      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px' }}>
                        {scenarioDetail.metadata.safetyRequirements.map((req: string, idx: number) => (
                          <Tag key={idx} color="red" style={{ margin: 0 }}>
                            {req}
                          </Tag>
                        ))}
                      </div>
                    </div>
                  )}
                </>
              )}

              <div style={{ marginTop: '16px' }}>
                <h4 style={{ marginBottom: '8px' }}>각도 목록:</h4>
                <div style={{ maxHeight: '200px', overflowY: 'auto' }}>
                  {scenarioDetail.angles.map((angle: any, idx: number) => (
                    <div
                      key={idx}
                      style={{
                        padding: '6px 8px',
                        marginBottom: '4px',
                        backgroundColor: '#f5f5f5',
                        borderRadius: '4px',
                        fontSize: '12px'
                      }}
                    >
                      <strong>{angle.name}</strong>: φ={angle.phi}°, θ={angle.theta}°, ψ={angle.psi}°
                    </div>
                  ))}
                </div>
              </div>
            </div>
          ) : (
            <Empty description="시나리오를 선택하세요" />
          )}
        </div>
      </div>
    </Modal>
  );
};

export default StandardScenarioModal;
