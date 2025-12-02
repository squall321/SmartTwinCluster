// components/DebugPanel.tsx
import React, { useState } from 'react';
import { Card, Button, Space, Typography, Collapse, Tag } from 'antd';
import { BugOutlined, ReloadOutlined } from '@ant-design/icons';
import { api } from '../../../api/axiosClient';
import { useSimulationNetworkStore } from '../store/simulationnetworkStore';

const { Title, Text, Paragraph } = Typography;
const { Panel } = Collapse;

const DebugPanel: React.FC = () => {
  const [apiResponse, setApiResponse] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  
  const nodes = useSimulationNetworkStore(state => state.nodes);
  const edges = useSimulationNetworkStore(state => state.edges);

  const testApiCall = async () => {
    setLoading(true);
    setError(null);
    try {
      console.log('🔍 Testing API call...');
      const url = `/api/proxy/automation/api/simulation-automation/simulationnetwork`;
      const response = await api.post(url);
      
      console.log('✅ API Response:', response);
      setApiResponse(response.data);
      
      // 응답 구조 분석
      const data = response.data;
      console.log('📊 Response Analysis:');
      console.log('- Response type:', typeof data);
      console.log('- Has nodes?', 'nodes' in data, Array.isArray(data?.nodes));
      console.log('- Has edges?', 'edges' in data, Array.isArray(data?.edges));
      console.log('- Nodes count:', data?.nodes?.length || 0);
      console.log('- Edges count:', data?.edges?.length || 0);
      
      if (data?.nodes?.length > 0) {
        console.log('- First node sample:', data.nodes[0]);
      }
      if (data?.edges?.length > 0) {
        console.log('- First edge sample:', data.edges[0]);
      }
      
    } catch (err: any) {
      console.error('❌ API Error:', err);
      setError(err.message || 'Unknown error');
    } finally {
      setLoading(false);
    }
  };

  const renderApiResponse = () => {
    if (!apiResponse) return <Text type="secondary">No API response yet</Text>;
    
    return (
      <div>
        <Paragraph>
          <Text strong>Response Type:</Text> {typeof apiResponse}
        </Paragraph>
        
        <Space direction="vertical" style={{ width: '100%' }}>
          <div>
            <Text strong>Has nodes: </Text>
            <Tag color={Array.isArray(apiResponse?.nodes) ? 'green' : 'red'}>
              {Array.isArray(apiResponse?.nodes) ? 'Yes' : 'No'}
            </Tag>
            {Array.isArray(apiResponse?.nodes) && (
              <Tag color="blue">Count: {apiResponse.nodes.length}</Tag>
            )}
          </div>
          
          <div>
            <Text strong>Has edges: </Text>
            <Tag color={Array.isArray(apiResponse?.edges) ? 'green' : 'red'}>
              {Array.isArray(apiResponse?.edges) ? 'Yes' : 'No'}
            </Tag>
            {Array.isArray(apiResponse?.edges) && (
              <Tag color="blue">Count: {apiResponse.edges.length}</Tag>
            )}
          </div>
        </Space>
        
        <Collapse style={{ marginTop: 16 }}>
          <Panel header="Raw Response" key="raw">
            <pre style={{ 
              background: '#f5f5f5', 
              padding: '12px', 
              borderRadius: '4px',
              maxHeight: '300px',
              overflow: 'auto',
              fontSize: '12px'
            }}>
              {JSON.stringify(apiResponse, null, 2)}
            </pre>
          </Panel>
          
          {apiResponse?.nodes?.length > 0 && (
            <Panel header="Sample Node" key="node">
              <pre style={{ 
                background: '#f5f5f5', 
                padding: '12px', 
                borderRadius: '4px',
                fontSize: '12px'
              }}>
                {JSON.stringify(apiResponse.nodes[0], null, 2)}
              </pre>
            </Panel>
          )}
          
          {apiResponse?.edges?.length > 0 && (
            <Panel header="Sample Edge" key="edge">
              <pre style={{ 
                background: '#f5f5f5', 
                padding: '12px', 
                borderRadius: '4px',
                fontSize: '12px'
              }}>
                {JSON.stringify(apiResponse.edges[0], null, 2)}
              </pre>
            </Panel>
          )}
        </Collapse>
      </div>
    );
  };

  const renderStoreState = () => (
    <Space direction="vertical" style={{ width: '100%' }}>
      <div>
        <Text strong>Store Nodes: </Text>
        <Tag color={nodes.length > 0 ? 'green' : 'orange'}>
          {nodes.length} nodes
        </Tag>
      </div>
      
      <div>
        <Text strong>Store Edges: </Text>
        <Tag color={edges.length > 0 ? 'green' : 'orange'}>
          {edges.length} edges
        </Tag>
      </div>
      
      {nodes.length > 0 && (
        <Collapse>
          <Panel header="Sample Store Node" key="store-node">
            <pre style={{ 
              background: '#f5f5f5', 
              padding: '12px', 
              borderRadius: '4px',
              fontSize: '12px'
            }}>
              {JSON.stringify(nodes[0], null, 2)}
            </pre>
          </Panel>
        </Collapse>
      )}
    </Space>
  );

  return (
    <div style={{ padding: '16px' }}>
      <Title level={3}>
        <BugOutlined /> API Debug Panel
      </Title>
      
      <Space direction="vertical" style={{ width: '100%' }} size="large">
        <Card 
          title="API Test" 
          extra={
            <Button 
              type="primary" 
              icon={<ReloadOutlined />} 
              onClick={testApiCall}
              loading={loading}
            >
              Test API
            </Button>
          }
        >
          {error && (
            <div style={{ marginBottom: 16 }}>
              <Text type="danger">Error: {error}</Text>
            </div>
          )}
          
          {renderApiResponse()}
        </Card>
        
        <Card title="Store State">
          {renderStoreState()}
        </Card>
        
        <Card title="Debugging Steps">
          <ol>
            <li>
              <Text strong>Step 1:</Text> Click "Test API" to see raw API response
            </li>
            <li>
              <Text strong>Step 2:</Text> Check if response has proper "nodes" and "edges" arrays
            </li>
            <li>
              <Text strong>Step 3:</Text> Verify store state is updated after API call
            </li>
            <li>
              <Text strong>Step 4:</Text> Check browser console for detailed logs
            </li>
          </ol>
          
          <div style={{ marginTop: 16, padding: '12px', background: '#f6f8fa', borderRadius: '4px' }}>
            <Text type="secondary">
              <strong>Expected API Response Format:</strong>
              <br />
              {`{ "nodes": [...], "edges": [...] }`}
            </Text>
          </div>
        </Card>
      </Space>
    </div>
  );
};

export default DebugPanel;