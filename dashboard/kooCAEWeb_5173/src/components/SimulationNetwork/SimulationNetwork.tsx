// components/simulationnetwork/SimulationNetwork.tsx - Enhanced Version
import React, { useEffect, useCallback, useState, useRef } from 'react';
import { useSimulationNetworkStore } from './store/simulationnetworkStore';
import HeaderBar from './components/HeaderBar';
import GraphView from './components/GraphView';
import NodeDrawer from './components/NodeDrawer';
import StatusLegend from './components/StatusLegend';
import SimulationStatusTable from './components/SimulationStatusTable';
import DebugPanel from './components/DebugPanel';
import AnalysisPanel from './components/analysis/AnalysisPanel';
import { api } from '../../api/axiosClient';
import { Space, Tag, Typography, Spin, Divider, Tabs, Alert, Button, Card, Row, Col, notification } from 'antd';
import { 
  PartitionOutlined, 
  TableOutlined, 
  BugOutlined, 
  BarChartOutlined,
  ReloadOutlined,
  ExclamationCircleOutlined,
  CheckCircleOutlined,
  WarningOutlined
} from '@ant-design/icons';

const { Text, Title } = Typography;

// 데이터 해시 생성 함수
const generateDataHash = (data: any): string => {
  return JSON.stringify(data).length.toString() + '_' + JSON.stringify(data).slice(0, 100);
};

const SimulationNetwork: React.FC = () => {
  const autoRefresh = useSimulationNetworkStore(state => state.autoRefresh);
  const setNodes = useSimulationNetworkStore(state => state.setNodes);
  const nodes = useSimulationNetworkStore(state => state.nodes);
  const intervalRef = useRef<NodeJS.Timeout | null>(null);

  // 🔹 Enhanced state management
  const [projects, setProjects] = useState<string[]>([]);
  const [loadingProjects, setLoadingProjects] = useState(false);
  const [loadingGraph, setLoadingGraph] = useState(false);
  const [activeTab, setActiveTab] = useState('network');
  const [showAnalysisPanel, setShowAnalysisPanel] = useState(false);
  const [lastUpdateTime, setLastUpdateTime] = useState<Date | null>(null);
  const [dataHash, setDataHash] = useState<string>('');
  const [connectionStatus, setConnectionStatus] = useState<'connected' | 'disconnected' | 'error'>('connected');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // 📊 Statistics
  const stats = React.useMemo(() => {
    const total = nodes.length;
    const statusCounts = nodes.reduce((acc, node) => {
      acc[node.status] = (acc[node.status] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);

    return { total, statusCounts };
  }, [nodes]);

  // 🔄 Load projects with error handling
  const loadProjects = useCallback(async () => {
    try {
      setLoadingProjects(true);
      setConnectionStatus('connected');
      const { data } = await api.get('/api/proxy/automation/api/simulation-automation/projects');
      setProjects(Array.isArray(data?.projects) ? data.projects : []);
      console.log('[SimulationNetwork] Projects loaded:', data?.projects?.length || 0);
    } catch (e) {
      console.error('[SimulationNetwork] Failed to load projects:', e);
      setProjects([]);
      setConnectionStatus('error');
      setErrorMessage('Failed to connect to simulation automation service');
    } finally {
      setLoadingProjects(false);
    }
  }, []);

  // 🔄 Enhanced graph data loading
  const loadGraphData = useCallback(async (forceUpdate = false) => {
    try {
      setLoadingGraph(true);
      setConnectionStatus('connected');
      setErrorMessage(null);
      
      console.log('[SimulationNetwork] Loading graph data... (forceUpdate:', forceUpdate, ')');
      const url = `/api/proxy/automation/api/simulation-automation/simulationnetwork`;
      const { data } = await api.get(url);
      
      // Check if data actually changed
      const newHash = generateDataHash(data);
      if (!forceUpdate && newHash === dataHash) {
        console.log('[SimulationNetwork] Data unchanged, skipping update');
        return;
      }
      
      console.log('[SimulationNetwork] Data loaded, updating...');
      
      // API 응답 구조 확인 및 처리
      const nodes = data?.nodes || [];
      const edges = data?.edges || [];
      
      console.log('[SimulationNetwork] Found nodes:', nodes.length, 'edges:', edges.length);
      
      if (nodes.length > 0 || edges.length > 0) {
        setNodes(nodes, edges);
        setDataHash(newHash);
        setLastUpdateTime(new Date());
        console.log('[SimulationNetwork] Nodes updated in store');
        
        // Show success notification for manual refresh
        if (forceUpdate) {
          notification.success({
            message: 'Data Updated',
            description: `Loaded ${nodes.length} nodes and ${edges.length} edges`,
            duration: 3
          });
        }
      } else {
        console.warn('[SimulationNetwork] No nodes or edges found in response');
        console.log('[SimulationNetwork] Response structure:', Object.keys(data || {}));
        
        if (forceUpdate) {
          notification.warning({
            message: 'No Data Found',
            description: 'No simulation network data available',
            duration: 3
          });
        }
      }
    } catch (error) {
      console.error('[SimulationNetwork] Error loading simulation network data:', error);
      setConnectionStatus('error');
      setErrorMessage('Failed to load simulation data');
      
      if (forceUpdate) {
        notification.error({
          message: 'Load Failed',
          description: 'Unable to fetch simulation network data',
          duration: 5
        });
      }
    } finally {
      setLoadingGraph(false);
    }
  }, [setNodes, dataHash]);

  // 🎯 Manual refresh handler
  const handleManualRefresh = useCallback(() => {
    console.log('[SimulationNetwork] Manual refresh triggered');
    loadProjects();
    loadGraphData(true);
  }, [loadProjects, loadGraphData]);

  // 🎯 Export data handler
  const handleExportData = useCallback(() => {
    try {
      const exportData = {
        timestamp: new Date().toISOString(),
        projects,
        nodes,
        statistics: stats
      };
      
      const dataStr = JSON.stringify(exportData, null, 2);
      const dataBlob = new Blob([dataStr], { type: 'application/json' });
      const url = URL.createObjectURL(dataBlob);
      
      const link = document.createElement('a');
      link.href = url;
      link.download = `simulation-network-${new Date().getTime()}.json`;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(url);
      
      notification.success({
        message: 'Export Successful',
        description: 'Simulation network data exported successfully',
        duration: 3
      });
    } catch (error) {
      notification.error({
        message: 'Export Failed',
        description: 'Failed to export simulation network data',
        duration: 5
      });
    }
  }, [projects, nodes, stats]);

  // 🔄 Initial loading
  useEffect(() => {
    console.log('[SimulationNetwork] Component mounted, starting initial load');
    loadProjects();
    loadGraphData(true);
  }, [loadProjects, loadGraphData]);

  // 🔄 Auto-refresh logic with enhanced error handling
  useEffect(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current);
      intervalRef.current = null;
    }

    if (!autoRefresh) {
      console.log('[SimulationNetwork] Auto-refresh disabled');
      return;
    }

    console.log('[SimulationNetwork] Setting up auto-refresh (60 seconds)');
    intervalRef.current = setInterval(() => {
      console.log('[SimulationNetwork] Auto-refresh triggered');
      loadGraphData();
    }, 60000); // 60초 = 1분

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [autoRefresh, loadGraphData]);

  // 🧹 Cleanup on unmount
  useEffect(() => {
    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, []);

  // 🎨 Enhanced tab items
  const tabItems = [
    {
      key: 'network',
      label: (
        <span>
          <PartitionOutlined />
          Network Graph
          {loadingGraph && <Spin size="small" style={{ marginLeft: 8 }} />}
        </span>
      ),
      children: (
        <div>
          <HeaderBar 
            onRefresh={handleManualRefresh}
            onExport={handleExportData}
            showAnalysisPanel={showAnalysisPanel}
            onToggleAnalysisPanel={() => setShowAnalysisPanel(!showAnalysisPanel)}
          />
          
          <Row gutter={16}>
            {/* Main Graph View */}
            <Col span={showAnalysisPanel ? 16 : 24}>
              <div style={{ position: 'relative', height: '75vh', border: '1px solid #f0f0f0', borderRadius: '8px' }}>
                <GraphView />
                <div
                  style={{
                    position: 'absolute',
                    bottom: 8,
                    right: 8,
                    background: 'white',
                    padding: '4px 8px',
                    borderRadius: 4,
                    boxShadow: '0 0 4px rgba(0,0,0,0.15)',
                  }}
                >
                  <StatusLegend />
                </div>
              </div>
            </Col>
            
            {/* Analysis Panel */}
            {showAnalysisPanel && (
              <Col span={8}>
                <Card 
                  title="Quick Analysis" 
                  size="small"
                  style={{ height: '75vh', overflow: 'auto' }}
                  extra={
                    <Button 
                      type="text" 
                      size="small"
                      onClick={() => setShowAnalysisPanel(false)}
                    >
                      ×
                    </Button>
                  }
                >
                  <AnalysisPanel />
                </Card>
              </Col>
            )}
          </Row>
          
          <NodeDrawer />
        </div>
      ),
    },
    {
      key: 'table',
      label: (
        <span>
          <TableOutlined />
          Status Table
        </span>
      ),
      children: <SimulationStatusTable />,
    },
    {
      key: 'analysis',
      label: (
        <span>
          <BarChartOutlined />
          Analysis Dashboard
        </span>
      ),
      children: <AnalysisPanel />,
    },
    {
      key: 'debug',
      label: (
        <span>
          <BugOutlined />
          Debug Info
        </span>
      ),
      children: <DebugPanel />,
    },
  ];

  return (
    <div style={{ minHeight: '100vh', background: '#f5f5f5' }}>
      {/* 🔹 Enhanced header with system status */}
      <Card style={{ margin: '0 0 16px 0', borderRadius: '0' }}>
        <Row justify="space-between" align="middle">
          <Col flex="auto">
            <Space align="center" wrap>
              <Title level={4} style={{ margin: 0 }}>
                <PartitionOutlined style={{ color: '#1890ff' }} />
                Simulation Automation Network
              </Title>
              
              {/* Connection Status */}
              <Tag 
                color={connectionStatus === 'connected' ? 'green' : connectionStatus === 'error' ? 'red' : 'orange'}
                icon={connectionStatus === 'connected' ? <CheckCircleOutlined /> : <ExclamationCircleOutlined />}
              >
                {connectionStatus.toUpperCase()}
              </Tag>
              
              {/* Projects Info */}
              <Text type="secondary">Projects:</Text>
              {loadingProjects ? (
                <Spin size="small" />
              ) : projects.length ? (
                projects.map(p => (
                  <Tag key={p} color="blue">{p}</Tag>
                ))
              ) : (
                <Tag color="default">No projects</Tag>
              )}
              
              <Divider type="vertical" />
              
              {/* Statistics */}
              <Space>
                <Text type="secondary">Total Cases:</Text>
                <Tag color="purple">{stats.total}</Tag>
                {Object.entries(stats.statusCounts).map(([status, count]) => (
                  <Tag key={status} color={getStatusColor(status)}>
                    {status}: {count}
                  </Tag>
                ))}
              </Space>
            </Space>
          </Col>
          
          <Col>
            <Space>
              {/* Last Update Time */}
              {lastUpdateTime && (
                <Text type="secondary" style={{ fontSize: 12 }}>
                  Updated: {lastUpdateTime.toLocaleTimeString()}
                </Text>
              )}
              
              {/* Auto-refresh Status */}
              <Text type="secondary" style={{ fontSize: 12 }}>
                Auto-refresh: {autoRefresh ? (
                  <Text type="success">ON (1min)</Text>
                ) : (
                  <Text type="warning">OFF</Text>
                )}
              </Text>
              
              {/* Manual Refresh */}
              <Button 
                icon={<ReloadOutlined />} 
                onClick={handleManualRefresh}
                loading={loadingGraph || loadingProjects}
                size="small"
              >
                Refresh
              </Button>
            </Space>
          </Col>
        </Row>
      </Card>

      {/* 🔹 Error Alert */}
      {errorMessage && (
        <Alert
          message="Connection Error"
          description={errorMessage}
          type="error"
          showIcon
          closable
          onClose={() => setErrorMessage(null)}
          style={{ margin: '0 16px 16px 16px' }}
          action={
            <Button size="small" onClick={handleManualRefresh}>
              Retry
            </Button>
          }
        />
      )}

      {/* 🔹 Main content with enhanced tabs */}
      <div style={{ padding: '0 16px' }}>
        <Tabs
          activeKey={activeTab}
          onChange={setActiveTab}
          items={tabItems}
          size="large"
          type="card"
          style={{ background: 'white', borderRadius: '8px' }}
        />
      </div>
    </div>
  );
};

// 🎨 Helper function for status colors
function getStatusColor(status: string): string {
  switch (status.toLowerCase()) {
    case 'running': return 'blue';
    case 'completed': return 'green';
    case 'failed': return 'red';
    case 'pending': return 'default';
    case 'cancelled': return 'orange';
    default: return 'default';
  }
}

export default SimulationNetwork;
