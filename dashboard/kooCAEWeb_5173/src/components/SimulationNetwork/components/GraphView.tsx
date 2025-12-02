// components/simulationnetwork/GraphView.tsx - Enhanced Version
import React, { useMemo, useCallback, useState, useEffect } from 'react';
import ReactFlow, { 
  Background, 
  Node, 
  Edge, 
  Position, 
  Controls,
  MiniMap,
  useNodesState,
  useEdgesState,
  NodeTypes,
  ConnectionMode,
  Panel,
  useReactFlow
} from 'reactflow';
import { Button, Space, Tooltip, Badge, Typography, Select, Card } from 'antd';
import { 
  FullscreenOutlined, 
  ZoomInOutlined, 
  ZoomOutOutlined,
  CompressOutlined,
  ReloadOutlined,
  SettingOutlined,
  EyeOutlined,
  EyeInvisibleOutlined
} from '@ant-design/icons';
import 'reactflow/dist/style.css';
import { useSimulationNetworkStore } from '../store/simulationnetworkStore';
import { SimulationNode, SimulationEdge, CaseStatus } from '../types/simulationnetwork';
import { getLayoutedElements } from '../utils/layout';

const { Text } = Typography;

// 🎨 Enhanced Status Colors & Styles
const statusConfig: Record<CaseStatus, { 
  color: string; 
  bgColor: string; 
  borderColor: string;
  glowColor: string;
}> = {
  Running: { 
    color: '#ffffff', 
    bgColor: 'linear-gradient(135deg, #1890ff 0%, #096dd9 100%)', 
    borderColor: '#1890ff',
    glowColor: '#1890ff'
  },
  Completed: { 
    color: '#ffffff', 
    bgColor: 'linear-gradient(135deg, #52c41a 0%, #389e0d 100%)', 
    borderColor: '#52c41a',
    glowColor: '#52c41a'
  },
  Failed: { 
    color: '#ffffff', 
    bgColor: 'linear-gradient(135deg, #ff4d4f 0%, #cf1322 100%)', 
    borderColor: '#ff4d4f',
    glowColor: '#ff4d4f'
  },
  Pending: { 
    color: '#666666', 
    bgColor: 'linear-gradient(135deg, #f5f5f5 0%, #e6e6e6 100%)', 
    borderColor: '#d9d9d9',
    glowColor: '#d9d9d9'
  },
  Cancelled: { 
    color: '#ffffff', 
    bgColor: 'linear-gradient(135deg, #faad14 0%, #d48806 100%)', 
    borderColor: '#faad14',
    glowColor: '#faad14'
  }
};

// 🎯 Custom Node Component
const CustomSimulationNode = ({ data, selected }: { data: SimulationNode; selected: boolean }) => {
  const config = statusConfig[data.status];
  
  return (
    <div
      style={{
        background: config.bgColor,
        border: `2px solid ${config.borderColor}`,
        borderRadius: '12px',
        padding: '12px 16px',
        minWidth: '200px',
        maxWidth: '300px',
        color: config.color,
        boxShadow: selected 
          ? `0 0 20px ${config.glowColor}40, 0 4px 15px rgba(0,0,0,0.2)` 
          : '0 2px 8px rgba(0,0,0,0.1)',
        transform: selected ? 'scale(1.05)' : 'scale(1)',
        transition: 'all 0.2s ease-in-out',
        cursor: 'pointer',
        position: 'relative',
        overflow: 'hidden'
      }}
    >
      {/* Status Indicator */}
      <div
        style={{
          position: 'absolute',
          top: '8px',
          right: '8px',
          width: '12px',
          height: '12px',
          borderRadius: '50%',
          background: config.borderColor,
          boxShadow: `0 0 6px ${config.borderColor}`,
          animation: data.status === 'Running' ? 'pulse 2s infinite' : 'none'
        }}
      />
      
      {/* Node Content */}
      <div style={{ fontSize: '14px', fontWeight: 'bold', marginBottom: '4px' }}>
        {data.label || data.id}
      </div>
      <div style={{ fontSize: '12px', opacity: 0.9 }}>
        {data.kind} • {data.status}
      </div>
      <div style={{ fontSize: '11px', opacity: 0.7, marginTop: '4px' }}>
        {data.path.split('/').slice(-2).join('/')}
      </div>

      {/* Animated Background for Running Status */}
      {data.status === 'Running' && (
        <div
          style={{
            position: 'absolute',
            top: 0,
            left: '-100%',
            width: '100%',
            height: '100%',
            background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.2), transparent)',
            animation: 'shimmer 3s infinite',
            pointerEvents: 'none'
          }}
        />
      )}
    </div>
  );
};

// 📊 Layout Options
const layoutOptions = [
  { label: 'Top to Bottom', value: 'TB' },
  { label: 'Left to Right', value: 'LR' },
  { label: 'Bottom to Top', value: 'BT' },
  { label: 'Right to Left', value: 'RL' }
];

const nodeTypes: NodeTypes = {
  simulationNode: CustomSimulationNode
};

const GraphView: React.FC = () => {
  const nodes = useSimulationNetworkStore(state => state.nodes);
  const edges = useSimulationNetworkStore(state => state.edges);
  const searchQuery = useSimulationNetworkStore(state => state.searchQuery);
  const statusFilter = useSimulationNetworkStore(state => state.statusFilter);
  const setSelectedNode = useSimulationNetworkStore(state => state.setSelectedNode);

  // 🎛️ Local State
  const [layoutDirection, setLayoutDirection] = useState<'TB' | 'LR' | 'BT' | 'RL'>('LR');
  const [showMiniMap, setShowMiniMap] = useState(true);
  const [showControls, setShowControls] = useState(true);
  const [isFullscreen, setIsFullscreen] = useState(false);
  
  // ReactFlow hooks
  const [reactFlowNodes, setReactFlowNodes, onNodesChange] = useNodesState([]);
  const [reactFlowEdges, setReactFlowEdges, onEdgesChange] = useEdgesState([]);

  // 🔄 Debug Logging
  useEffect(() => {
    console.log('[GraphView] Data updated:', {
      nodesCount: nodes.length,
      edgesCount: edges.length,
      searchQuery,
      statusFilter: statusFilter.length
    });
  }, [nodes, edges, searchQuery, statusFilter]);

  // 🔍 Filtered Data
  const filteredData = useMemo(() => {
    console.log('[GraphView] Computing filtered data...');
    
    let filteredNodes = nodes;
    
    // Search filter
    if (searchQuery) {
      const query = searchQuery.toLowerCase();
      filteredNodes = filteredNodes.filter(n => 
        n.id.toLowerCase().includes(query) || 
        n.label?.toLowerCase().includes(query) ||
        n.path.toLowerCase().includes(query)
      );
    }
    
    // Status filter
    if (statusFilter.length > 0) {
      filteredNodes = filteredNodes.filter(n => statusFilter.includes(n.status));
    }
    
    // Filter edges to only include visible nodes
    const visibleNodeIds = new Set(filteredNodes.map(n => n.id));
    const filteredEdges = edges.filter(e => 
      visibleNodeIds.has(e.source) && visibleNodeIds.has(e.target)
    );
    
    console.log('[GraphView] Filtered result:', {
      nodes: filteredNodes.length,
      edges: filteredEdges.length
    });
    
    return { nodes: filteredNodes, edges: filteredEdges };
  }, [nodes, edges, searchQuery, statusFilter]);

  // 🎨 Layout Calculation
  const layoutedData = useMemo(() => {
    console.log('[GraphView] Computing layout...');
    
    if (filteredData.nodes.length === 0) {
      return { nodes: [], edges: [] };
    }
    
    const { nodes: layoutedNodes, edges: layoutedEdges } = getLayoutedElements(
      filteredData.nodes, 
      filteredData.edges, 
      layoutDirection
    );
    
    console.log('[GraphView] Layout computed:', {
      layoutDirection,
      layoutedNodes: layoutedNodes.length,
      layoutedEdges: layoutedEdges.length
    });
    
    return { nodes: layoutedNodes, edges: layoutedEdges };
  }, [filteredData, layoutDirection]);

  // 🔄 Convert to ReactFlow Format
  useEffect(() => {
    console.log('[GraphView] Converting to ReactFlow format...');
    
    const flowNodes: Node[] = layoutedData.nodes.map(n => ({
      id: n.id,
      type: 'simulationNode',
      position: n.position || { x: 0, y: 0 },
      data: n,
      sourcePosition: n.sourcePosition as Position,
      targetPosition: n.targetPosition as Position,
    }));

    const flowEdges: Edge[] = layoutedData.edges.map(e => ({
      id: e.id,
      source: e.source,
      target: e.target,
      label: e.label,
      type: 'smoothstep',
      animated: false,
      style: { stroke: '#e6e6e6', strokeWidth: 2 }
    }));

    setReactFlowNodes(flowNodes);
    setReactFlowEdges(flowEdges);
    
  }, [layoutedData, setReactFlowNodes, setReactFlowEdges]);

  // 🎯 Event Handlers
  const onNodeClick = useCallback((_: React.MouseEvent, node: Node) => {
    console.log('[GraphView] Node clicked:', node.id);
    const data = node.data as SimulationNode;
    setSelectedNode(data);
  }, [setSelectedNode]);

  const handleLayoutChange = useCallback((direction: string) => {
    setLayoutDirection(direction as 'TB' | 'LR' | 'BT' | 'RL');
  }, []);

  const toggleFullscreen = useCallback(() => {
    setIsFullscreen(!isFullscreen);
  }, [isFullscreen]);

  // 📊 Statistics
  const stats = useMemo(() => {
    const statusCounts = filteredData.nodes.reduce((acc, node) => {
      acc[node.status] = (acc[node.status] || 0) + 1;
      return acc;
    }, {} as Record<CaseStatus, number>);
    
    return {
      total: filteredData.nodes.length,
      edges: filteredData.edges.length,
      statusCounts
    };
  }, [filteredData]);

  return (
    <div 
      style={{ 
        height: isFullscreen ? '100vh' : '100%', 
        width: '100%', 
        position: isFullscreen ? 'fixed' : 'relative',
        top: isFullscreen ? 0 : 'auto',
        left: isFullscreen ? 0 : 'auto',
        zIndex: isFullscreen ? 9999 : 'auto',
        background: '#fafafa'
      }}
    >
      <ReactFlow
        nodes={reactFlowNodes}
        edges={reactFlowEdges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onNodeClick={onNodeClick}
        nodeTypes={nodeTypes}
        connectionMode={ConnectionMode.Loose}
        fitView
        attributionPosition="bottom-left"
        style={{ background: '#fafafa' }}
      >
        <Background color="#e1e1e1" gap={20} size={1} />
        
        {/* Controls */}
        {showControls && (
          <Controls 
            position="top-left"
            style={{ 
              background: 'white', 
              border: '1px solid #d9d9d9',
              borderRadius: '6px'
            }}
          />
        )}
        
        {/* MiniMap */}
        {showMiniMap && (
          <MiniMap 
            position="bottom-right"
            style={{
              background: 'white',
              border: '1px solid #d9d9d9',
              borderRadius: '6px'
            }}
            nodeStrokeWidth={3}
            nodeColor={(node) => statusConfig[node.data.status as CaseStatus]?.borderColor || '#ccc'}
          />
        )}

        {/* Top Panel - Controls & Stats */}
        <Panel position="top-center">
          <Card 
            size="small" 
            style={{ 
              background: 'rgba(255,255,255,0.95)', 
              backdropFilter: 'blur(8px)',
              borderRadius: '8px',
              border: '1px solid rgba(0,0,0,0.1)'
            }}
          >
            <Space size="large">
              {/* Layout Controls */}
              <Space align="center">
                <Text type="secondary">Layout:</Text>
                <Select
                  value={layoutDirection}
                  onChange={handleLayoutChange}
                  options={layoutOptions}
                  size="small"
                  style={{ minWidth: 140 }}
                />
              </Space>

              {/* Statistics */}
              <Space align="center">
                <Text type="secondary">Nodes:</Text>
                <Badge count={stats.total} color="#1890ff" />
                <Text type="secondary">Edges:</Text>
                <Badge count={stats.edges} color="#52c41a" />
              </Space>

              {/* Status Distribution */}
              <Space align="center">
                {Object.entries(stats.statusCounts).map(([status, count]) => (
                  <Badge 
                    key={status}
                    count={count} 
                    color={statusConfig[status as CaseStatus]?.borderColor}
                    title={status}
                  />
                ))}
              </Space>
            </Space>
          </Card>
        </Panel>

        {/* Right Panel - View Controls */}
        <Panel position="top-right">
          <Space direction="vertical" size="small">
            <Button
              icon={<ReloadOutlined />}
              onClick={() => window.location.reload()}
              title="Refresh Layout"
              size="small"
            />
            <Button
              icon={showMiniMap ? <EyeInvisibleOutlined /> : <EyeOutlined />}
              onClick={() => setShowMiniMap(!showMiniMap)}
              title="Toggle MiniMap"
              size="small"
            />
            <Button
              icon={showControls ? <EyeInvisibleOutlined /> : <EyeOutlined />}
              onClick={() => setShowControls(!showControls)}
              title="Toggle Controls"
              size="small"
            />
            <Button
              icon={isFullscreen ? <CompressOutlined /> : <FullscreenOutlined />}
              onClick={toggleFullscreen}
              title="Toggle Fullscreen"
              size="small"
            />
          </Space>
        </Panel>

        {/* Empty State */}
        {filteredData.nodes.length === 0 && (
          <div style={{ 
            position: 'absolute', 
            top: '50%', 
            left: '50%', 
            transform: 'translate(-50%, -50%)',
            zIndex: 10
          }}>
            <Card style={{ textAlign: 'center', maxWidth: 300 }}>
              <div style={{ fontSize: '48px', color: '#d9d9d9', marginBottom: '16px' }}>
                📊
              </div>
              <Text type="secondary">
                {nodes.length === 0 
                  ? 'No simulation data available'
                  : 'No nodes match current filters'
                }
              </Text>
            </Card>
          </div>
        )}
      </ReactFlow>

      {/* CSS Animations */}
      <style>{`
        @keyframes pulse {
          0%, 100% { opacity: 1; transform: scale(1); }
          50% { opacity: 0.7; transform: scale(1.1); }
        }
        
        @keyframes shimmer {
          0% { left: -100%; }
          100% { left: 100%; }
        }
      `}</style>
    </div>
  );
};

export default GraphView;
