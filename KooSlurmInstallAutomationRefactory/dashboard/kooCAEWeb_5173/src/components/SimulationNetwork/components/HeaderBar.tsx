// components/simulationnetwork/HeaderBar.tsx - Enhanced Version
import React, { useState, useMemo } from 'react';
import { 
  Space, 
  Select, 
  Button, 
  Input, 
  Badge, 
  Card, 
  Row, 
  Col, 
  Typography, 
  Tooltip,
  Divider,
  Dropdown,
  Switch
} from 'antd';
import { 
  SearchOutlined, 
  FilterOutlined, 
  ClearOutlined, 
  DownloadOutlined,
  SettingOutlined,
  ReloadOutlined,
  PlayCircleOutlined,
  PauseCircleOutlined,
  EyeOutlined,
  EyeInvisibleOutlined,
  BarsOutlined
} from '@ant-design/icons';
import { useSimulationNetworkStore } from '../store/simulationnetworkStore';
import { ALL_STATUSES } from '../utils/statusUtils';
import { CaseStatus } from '../types/simulationnetwork';

const { Text } = Typography;
const { Search } = Input;

// 🎨 Status configuration with colors and counts
const statusConfig: Record<CaseStatus, { color: string; icon: string }> = {
  Running: { color: '#1890ff', icon: '🔄' },
  Completed: { color: '#52c41a', icon: '✅' },
  Failed: { color: '#ff4d4f', icon: '❌' },
  Pending: { color: '#d9d9d9', icon: '⏳' },
  Cancelled: { color: '#faad14', icon: '⚠️' }
};

interface HeaderBarProps {
  onExport?: () => void;
  onRefresh?: () => void;
  showAnalysisPanel?: boolean;
  onToggleAnalysisPanel?: () => void;
}

const HeaderBar: React.FC<HeaderBarProps> = ({
  onExport,
  onRefresh,
  showAnalysisPanel,
  onToggleAnalysisPanel
}) => {
  // 🏪 Store state
  const {
    nodes,
    searchQuery,
    statusFilter,
    autoRefresh,
    setSearchQuery,
    setStatusFilter,
    toggleAutoRefresh
  } = useSimulationNetworkStore();

  // 🎛️ Local state
  const [showAdvancedFilters, setShowAdvancedFilters] = useState(false);
  const [selectedKinds, setSelectedKinds] = useState<string[]>([]);

  // 📊 Calculate statistics
  const stats = useMemo(() => {
    const total = nodes.length;
    const statusCounts = nodes.reduce((acc, node) => {
      acc[node.status] = (acc[node.status] || 0) + 1;
      return acc;
    }, {} as Record<CaseStatus, number>);

    const kindCounts = nodes.reduce((acc, node) => {
      acc[node.kind] = (acc[node.kind] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);

    // Calculate filtered count
    let filteredCount = nodes.length;
    if (searchQuery || statusFilter.length > 0 || selectedKinds.length > 0) {
      const query = searchQuery.toLowerCase();
      filteredCount = nodes.filter(node => {
        const matchesSearch = !searchQuery || 
          node.id.toLowerCase().includes(query) || 
          node.label?.toLowerCase().includes(query) ||
          node.path.toLowerCase().includes(query);
        const matchesStatus = statusFilter.length === 0 || statusFilter.includes(node.status);
        const matchesKind = selectedKinds.length === 0 || selectedKinds.includes(node.kind);
        return matchesSearch && matchesStatus && matchesKind;
      }).length;
    }

    return { total, statusCounts, kindCounts, filteredCount };
  }, [nodes, searchQuery, statusFilter, selectedKinds]);

  // 🎯 Event handlers
  const handleSearchChange = (value: string) => {
    setSearchQuery(value);
  };

  const handleStatusFilterChange = (values: CaseStatus[]) => {
    setStatusFilter(values);
  };

  const handleClearFilters = () => {
    setSearchQuery('');
    setStatusFilter([]);
    setSelectedKinds([]);
  };

  const hasActiveFilters = searchQuery || statusFilter.length > 0 || selectedKinds.length > 0;

  // 📋 Settings dropdown menu
  const settingsMenu = {
    items: [
      {
        key: 'advanced-filters',
        label: (
          <Space>
            <FilterOutlined />
            Advanced Filters
          </Space>
        ),
        onClick: () => setShowAdvancedFilters(!showAdvancedFilters)
      },
      {
        key: 'export',
        label: (
          <Space>
            <DownloadOutlined />
            Export Data
          </Space>
        ),
        onClick: onExport,
        disabled: !onExport
      },
      { type: 'divider' },
      {
        key: 'auto-refresh',
        label: (
          <div style={{ display: 'flex', justifyContent: 'space-between', width: '100%' }}>
            <span>Auto Refresh</span>
            <Switch 
              size="small" 
              checked={autoRefresh} 
              onChange={toggleAutoRefresh}
            />
          </div>
        )
      }
    ]
  };

  return (
    <div style={{ marginBottom: '16px' }}>
      {/* Main Header */}
      <Card size="small" style={{ background: '#fafafa' }}>
        <Row gutter={[16, 8]} align="middle">
          {/* Left Section - Search & Filters */}
          <Col flex="auto">
            <Space size="middle" wrap>
              {/* Search Input */}
              <Search
                placeholder="Search by ID, label, or path..."
                value={searchQuery}
                onChange={(e) => handleSearchChange(e.target.value)}
                onSearch={handleSearchChange}
                allowClear
                style={{ minWidth: 250 }}
                prefix={<SearchOutlined />}
              />

              {/* Status Filter */}
              <Select
                mode="multiple"
                allowClear
                placeholder="Filter by status"
                value={statusFilter.length ? statusFilter : undefined}
                onChange={handleStatusFilterChange}
                style={{ minWidth: 180 }}
                optionLabelProp="label"
              >
                {ALL_STATUSES.map(status => (
                  <Select.Option 
                    key={status} 
                    value={status}
                    label={
                      <Space>
                        <Badge color={statusConfig[status].color} />
                        {status}
                      </Space>
                    }
                  >
                    <Space>
                      <Badge color={statusConfig[status].color} />
                      <span>{status}</span>
                      <Text type="secondary">({stats.statusCounts[status] || 0})</Text>
                    </Space>
                  </Select.Option>
                ))}
              </Select>

              {/* Clear Filters */}
              {hasActiveFilters && (
                <Tooltip title="Clear all filters">
                  <Button 
                    icon={<ClearOutlined />} 
                    onClick={handleClearFilters}
                    size="small"
                  >
                    Clear
                  </Button>
                </Tooltip>
              )}

              {/* Filter Indicator */}
              {hasActiveFilters && (
                <Badge count={stats.filteredCount} color="#1890ff">
                  <Text type="secondary">Filtered</Text>
                </Badge>
              )}
            </Space>
          </Col>

          {/* Center Section - Statistics */}
          <Col>
            <Space size="large" split={<Divider type="vertical" />}>
              <Space>
                <Text type="secondary">Total:</Text>
                <Badge count={stats.total} color="#722ed1" />
              </Space>
              
              {Object.entries(stats.statusCounts).map(([status, count]) => (
                count > 0 && (
                  <Space key={status}>
                    <Text type="secondary">{statusConfig[status as CaseStatus].icon}</Text>
                    <Badge count={count} color={statusConfig[status as CaseStatus].color} />
                  </Space>
                )
              ))}
            </Space>
          </Col>

          {/* Right Section - Actions */}
          <Col>
            <Space>
              {/* Auto Refresh Toggle */}
              <Tooltip title={autoRefresh ? "Auto-refresh ON (1min)" : "Auto-refresh OFF"}>
                <Button
                  type={autoRefresh ? "primary" : "default"}
                  icon={autoRefresh ? <PauseCircleOutlined /> : <PlayCircleOutlined />}
                  onClick={toggleAutoRefresh}
                  size="small"
                >
                  {autoRefresh ? "ON" : "OFF"}
                </Button>
              </Tooltip>

              {/* Manual Refresh */}
              <Tooltip title="Refresh data">
                <Button
                  icon={<ReloadOutlined />}
                  onClick={onRefresh}
                  size="small"
                />
              </Tooltip>

              {/* Analysis Panel Toggle */}
              {onToggleAnalysisPanel && (
                <Tooltip title={showAnalysisPanel ? "Hide Analysis Panel" : "Show Analysis Panel"}>
                  <Button
                    type={showAnalysisPanel ? "primary" : "default"}
                    icon={showAnalysisPanel ? <EyeInvisibleOutlined /> : <EyeOutlined />}
                    onClick={onToggleAnalysisPanel}
                    size="small"
                  >
                    Analysis
                  </Button>
                </Tooltip>
              )}

              {/* Settings Dropdown */}
              <Dropdown menu ={settingsMenu as any} trigger={['click']}>
                <Button icon={<SettingOutlined />} size="small" />
              </Dropdown>
            </Space>
          </Col>
        </Row>

        {/* Advanced Filters Section */}
        {showAdvancedFilters && (
          <>
            <Divider style={{ margin: '12px 0' }} />
            <Row gutter={[16, 8]} align="middle">
              <Col span={6}>
                <Text strong>Advanced Filters</Text>
              </Col>
              <Col span={18}>
                <Space wrap>
                  {/* Kind Filter */}
                  <Select
                    mode="multiple"
                    allowClear
                    placeholder="Filter by kind"
                    value={selectedKinds}
                    onChange={setSelectedKinds}
                    style={{ minWidth: 150 }}
                  >
                    {Object.entries(stats.kindCounts).map(([kind, count]) => (
                      <Select.Option key={kind} value={kind}>
                        <Space>
                          <span>{kind}</span>
                          <Text type="secondary">({count})</Text>
                        </Space>
                      </Select.Option>
                    ))}
                  </Select>

                  {/* Additional filters can be added here */}
                  <Button 
                    icon={<BarsOutlined />} 
                    size="small" 
                    disabled
                    style={{ opacity: 0.5 }}
                  >
                    More filters coming soon...
                  </Button>
                </Space>
              </Col>
            </Row>
          </>
        )}
      </Card>

      {/* Quick Stats Bar */}
      {hasActiveFilters && (
        <Card size="small" style={{ marginTop: '8px', background: '#e6f7ff' }}>
          <Row justify="space-between" align="middle">
            <Col>
              <Text type="secondary">
                Showing {stats.filteredCount} of {stats.total} cases
                {searchQuery && ` matching "${searchQuery}"`}
                {statusFilter.length > 0 && ` with status: ${statusFilter.join(', ')}`}
                {selectedKinds.length > 0 && ` of kind: ${selectedKinds.join(', ')}`}
              </Text>
            </Col>
            <Col>
              <Button 
                type="link" 
                size="small" 
                onClick={handleClearFilters}
                icon={<ClearOutlined />}
              >
                Clear all filters
              </Button>
            </Col>
          </Row>
        </Card>
      )}
    </div>
  );
};

export default HeaderBar;
