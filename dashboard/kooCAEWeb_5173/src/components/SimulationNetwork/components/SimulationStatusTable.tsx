// components/SimulationStatusTable.tsx (실제 API 버전 - 최적화)
import React, { useState, useEffect, useCallback } from 'react';
import { 
  Table, 
  Card, 
  Select, 
  Space, 
  Tag, 
  Typography, 
  Spin, 
  Button,
  Input,
  Row,
  Col,
  Statistic,
  Alert
} from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { ReloadOutlined, SearchOutlined, ProjectOutlined } from '@ant-design/icons';
import { api } from '../../../api/axiosClient';
import { CaseStatus, CaseKind } from '../types/simulationnetwork';
import { getStatusColor } from '../utils/statusUtils';

const { Title, Text } = Typography;
const { Option } = Select;

// 실제 API 응답에 맞는 타입 정의
interface ApiNode {
  id: string;
  label: string;
  path: string;
  status: CaseStatus;
  kind: CaseKind;
  project?: string;
  revision?: string;
  mode_short?: string;
}

interface ProjectRevisionSummary {
  project: string;
  revision: string;
  mode: string;
  nodes: ApiNode[];
  summary: {
    total: number;
    completed: number;
    running: number;
    failed: number;
    pending: number;
    cancelled: number;
  };
}

const SimulationStatusTable: React.FC = () => {
  const [projects, setProjects] = useState<string[]>([]);
  const [selectedProject, setSelectedProject] = useState<string>('');
  const [selectedRevision, setSelectedRevision] = useState<string>('');
  const [revisions, setRevisions] = useState<string[]>([]);
  const [tableData, setTableData] = useState<ProjectRevisionSummary[]>([]);
  const [loading, setLoading] = useState(false);
  const [searchText, setSearchText] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [lastUpdateTime, setLastUpdateTime] = useState<Date>(new Date());

  // 프로젝트 목록 로드
  const loadProjects = useCallback(async () => {
    console.log('[StatusTable] Loading projects...');
    try {
      setError(null);
      const { data } = await api.get('/api/proxy/automation/api/simulation-automation/projects');
      console.log('[StatusTable] Projects API response:', data);
      console.log('[StatusTable] Response type:', typeof data);
      console.log('[StatusTable] Response keys:', Object.keys(data || {}));
      
      // 다양한 응답 형식 처리
      let projectList: string[] = [];
      
      if (Array.isArray(data)) {
        projectList = data;
      } else if (data && Array.isArray(data.projects)) {
        projectList = data.projects;
      } else if (data && Array.isArray(data.data)) {
        projectList = data.data;
      } else if (data && typeof data === 'object') {
        // 객체의 값들을 배열로 변환 시도
        const values = Object.values(data);
        if (values.length === 1 && Array.isArray(values[0])) {
          projectList = values[0] as string[];
        }
      }
      
      console.log('[StatusTable] Parsed projects:', projectList);
      setProjects(projectList);
      
      if (projectList.length > 0 && !selectedProject) {
        const firstProject = projectList[0];
        console.log('[StatusTable] Auto-selecting first project:', firstProject);
        setSelectedProject(firstProject);
      }
    } catch (error: any) {
      console.error('[StatusTable] Failed to load projects:', error);
      console.error('[StatusTable] Error details:', {
        message: error.message,
        status: error.response?.status,
        statusText: error.response?.statusText,
        data: error.response?.data
      });
      setError('Failed to load projects: ' + (error.message || 'Unknown error'));
      setProjects([]);
    }
  }, []); // 의존성 제거

  // 리비전 목록 로드  
  const loadRevisions = useCallback(async (project: string) => {
    if (!project) {
      console.log('[StatusTable] No project specified for revisions');
      return;
    }
    
    console.log('[StatusTable] Loading revisions for project:', project);
    try {
      setError(null);
      
      // 다양한 API 경로 시도
      const possibleUrls = [
        `/api/proxy/automation/api/simulation-automation/projects/${project}/revisions`,
        `/api/proxy/automation/api/simulation-automation/revisions?project=${project}`,
        `/api/proxy/automation/api/simulation-automation/revisions/${project}`
      ];
      
      let data = null;
      let successUrl = null;
      
      for (const url of possibleUrls) {
        try {
          console.log('[StatusTable] Trying URL:', url);
          const response = await api.get(url);
          data = response.data;
          successUrl = url;
          console.log('[StatusTable] Success with URL:', url, 'Response:', data);
          break;
        } catch (urlError: any) {
          console.log('[StatusTable] Failed URL:', url, 'Error:', urlError.message);
        }
      }
      
      if (!data) {
        throw new Error('All revision API endpoints failed');
      }
      
      // 다양한 응답 형식 처리
      let revisionList: string[] = [];
      
      if (Array.isArray(data)) {
        revisionList = data;
      } else if (data.revisions && Array.isArray(data.revisions)) {
        revisionList = data.revisions;
      } else if (data.data && Array.isArray(data.data)) {
        revisionList = data.data;
      } else {
        console.log('[StatusTable] Unexpected response format:', data);
        revisionList = [];
      }
      
      console.log('[StatusTable] Parsed revisions:', revisionList);
      setRevisions(revisionList);
      
    } catch (error: any) {
      console.error('[StatusTable] Failed to load revisions:', error);
      setError('Failed to load revisions: ' + (error.message || 'Unknown error'));
      setRevisions([]);
    }
  }, []); // 의존성 제거

  // 시뮬레이션 네트워크 데이터 로드
  const loadSimulationData = useCallback(async () => {
    if (!selectedProject) return;
    
    setLoading(true);
    setError(null);
    try {
      // API 호출 파라미터 구성
      const requestBody: any = {};
      if (selectedProject) requestBody.project = selectedProject;
      if (selectedRevision) requestBody.revision = selectedRevision;
      
      console.log('Loading simulation data with params:', requestBody);
      
      const { data } = await api.post('/api/proxy/automation/api/simulation-automation/simulationnetwork', requestBody);
      console.log('Simulation network API response:', data);
      
      const nodes: ApiNode[] = data?.nodes || [];
      const summary = data?.summary || {};
      
      console.log('Parsed nodes:', nodes.length);
      console.log('Summary:', summary);
      
      // 프로젝트/리비전/모드별로 데이터 그룹화
      const groupedData: ProjectRevisionSummary[] = [];
      const groups = new Map<string, ApiNode[]>();
      
      nodes.forEach(node => {
        const project = node.project || selectedProject || 'Unknown';
        const revision = node.revision || selectedRevision || 'Unknown';
        const mode = node.mode_short || 'Unknown';
        const key = `${project}/${revision}/${mode}`;
        
        if (!groups.has(key)) {
          groups.set(key, []);
        }
        groups.get(key)!.push(node);
      });
      
      // 그룹별로 요약 데이터 생성
      groups.forEach((nodes, key) => {
        const [project, revision, mode] = key.split('/');
        groupedData.push({
          project,
          revision,
          mode,
          nodes,
          summary: calculateSummary(nodes)
        });
      });
      
      // 프로젝트/리비전별로 정렬
      groupedData.sort((a, b) => {
        if (a.project !== b.project) return a.project.localeCompare(b.project);
        if (a.revision !== b.revision) return a.revision.localeCompare(b.revision);
        return a.mode.localeCompare(b.mode);
      });
      
      setTableData(groupedData);
      setLastUpdateTime(new Date());
      
    } catch (error: any) {
      console.error('Failed to load simulation data:', error);
      setError('Failed to load simulation data: ' + (error.message || 'Unknown error'));
      setTableData([]);
    } finally {
      setLoading(false);
    }
  }, [selectedProject, selectedRevision]); // 의존성을 최소화

  const calculateSummary = (nodes: ApiNode[]) => {
    const summary = {
      total: nodes.length,
      completed: 0,
      running: 0,
      failed: 0,
      pending: 0,
      cancelled: 0
    };
    
    nodes.forEach(node => {
      const statusKey = node.status.toLowerCase() as keyof typeof summary;
      if (statusKey in summary) {
        (summary as any)[statusKey]++;
      }
    });
    
    return summary;
  };

  // 프로젝트 변경 핸들러
  const handleProjectChange = (project: string) => {
    console.log('[StatusTable] Project changed to:', project);
    setSelectedProject(project);
    setSelectedRevision(''); // 프로젝트 변경시 리비전 초기화
    setTableData([]); // 기존 데이터 클리어
    // 리비전 목록을 즉시 로드
    loadRevisions(project);
  };

  // 리비전 변경 핸들러
  const handleRevisionChange = (revision: string) => {
    console.log('[StatusTable] Revision changed to:', revision);
    setSelectedRevision(revision);
    setTableData([]); // 기존 데이터 클리어
  };

  // 초기 프로젝트 목록 로드 (한 번만)
  useEffect(() => {
    console.log('[StatusTable] Component mounted, loading projects');
    loadProjects();
  }, [loadProjects]);

  // 프로젝트 변경 시 리비전 목록 로드
  useEffect(() => {
    console.log('[StatusTable] useEffect for project change:', selectedProject);
    if (selectedProject) {
      setRevisions([]);
      loadRevisions(selectedProject);
    } else {
      setRevisions([]);
    }
  }, [selectedProject, loadRevisions]);

  // 수동 refresh만 허용 - 자동 로드 제거
  // 사용자가 Refresh 버튼을 클릭해야만 데이터 로드

  // 테이블 컬럼 정의
  const columns: ColumnsType<ApiNode> = [
    {
      title: 'Case ID',
      dataIndex: 'id',
      key: 'id',
      width: 180,
      fixed: 'left',
      filteredValue: searchText ? [searchText] : null,
      onFilter: (value, record) => 
        record.id.toLowerCase().includes(value.toString().toLowerCase()) ||
        record.label.toLowerCase().includes(value.toString().toLowerCase()),
      sorter: (a, b) => a.id.localeCompare(b.id),
    },
    {
      title: 'Label',
      dataIndex: 'label',
      key: 'label',
      ellipsis: true,
      width: 200,
    },
    {
      title: 'Path',
      dataIndex: 'path',
      key: 'path',
      ellipsis: true,
      width: 300,
      render: (path: string) => (
        <Text style={{ fontSize: '12px' }} title={path}>
          {path}
        </Text>
      ),
    },
    {
      title: 'Kind',
      dataIndex: 'kind',
      key: 'kind',
      width: 120,
      filters: [
        { text: 'DropSet', value: 'DropSet' },
        { text: 'DropImpactor', value: 'DropImpactor' },
      ],
      onFilter: (value, record) => record.kind === value,
      render: (kind: CaseKind) => (
        <Tag color={kind === 'DropSet' ? 'blue' : 'green'}>
          {kind}
        </Tag>
      ),
    },
    {
      title: 'Status',
      dataIndex: 'status',
      key: 'status',
      width: 120,
      filters: [
        { text: 'Running', value: 'Running' },
        { text: 'Completed', value: 'Completed' },
        { text: 'Failed', value: 'Failed' },
        { text: 'Pending', value: 'Pending' },
        { text: 'Cancelled', value: 'Cancelled' },
      ],
      onFilter: (value, record) => record.status === value,
      render: (status: CaseStatus) => (
        <Tag color={getStatusColor(status)}>{status}</Tag>
      ),
    },
  ];

  // 요약 정보 렌더링
  const renderSummary = (summary: ProjectRevisionSummary['summary']) => {
    const completionRate = summary.total > 0 ? Math.round((summary.completed / summary.total) * 100) : 0;
    
    return (
      <Row gutter={16}>
        <Col>
          <Statistic 
            title="Total" 
            value={summary.total} 
            prefix={<ProjectOutlined />}
          />
        </Col>
        <Col>
          <Statistic 
            title="Completed" 
            value={summary.completed} 
            valueStyle={{ color: '#52c41a' }}
          />
        </Col>
        <Col>
          <Statistic 
            title="Running" 
            value={summary.running} 
            valueStyle={{ color: '#1890ff' }}
          />
        </Col>
        <Col>
          <Statistic 
            title="Failed" 
            value={summary.failed} 
            valueStyle={{ color: '#ff4d4f' }}
          />
        </Col>
        <Col>
          <Statistic 
            title="Success Rate" 
            value={completionRate} 
            suffix="%" 
            valueStyle={{ color: completionRate > 80 ? '#52c41a' : completionRate > 50 ? '#faad14' : '#ff4d4f' }}
          />
        </Col>
      </Row>
    );
  };

  return (
    <div style={{ padding: '16px', backgroundColor: '#f5f5f5', minHeight: '100vh' }}>
      <div style={{ marginBottom: '24px' }}>
        <Title level={2} style={{ margin: 0, color: '#1890ff' }}>
          <ProjectOutlined /> Simulation Status Overview
        </Title>
        <Text type="secondary">프로젝트별 시뮬레이션 케이스 진행 상황을 확인할 수 있습니다. (수동 새로고침)</Text>
      </div>
      
      {/* 에러 표시 */}
      {error && (
        <Alert
          message="API Error"
          description={error}
          type="error"
          showIcon
          closable
          onClose={() => setError(null)}
          style={{ marginBottom: '16px' }}
        />
      )}
      
      {/* 필터 컨트롤 */}
      <Card style={{ marginBottom: '16px' }} bodyStyle={{ padding: '16px' }}>
        <Row gutter={[16, 8]} align="middle">
          <Col>
            <Text strong>Project:</Text>
          </Col>
          <Col>
            <Select
              value={selectedProject}
              onChange={handleProjectChange}
              style={{ width: 200 }}
              placeholder="Select Project"
              loading={!projects.length}
            >
              {projects.map(project => (
                <Option key={project} value={project}>{project}</Option>
              ))}
            </Select>
          </Col>
          <Col>
            <Text strong>Revision:</Text>
          </Col>
          <Col>
            <Select
              value={selectedRevision}
              onChange={handleRevisionChange}
              style={{ width: 200 }}
              placeholder="All Revisions"
              allowClear
              loading={!!selectedProject && !revisions.length}
            >
              {revisions.map(revision => (
                <Option key={revision} value={revision}>{revision}</Option>
              ))}
            </Select>
          </Col>
          <Col>
            <Input
              placeholder="Search cases..."
              prefix={<SearchOutlined />}
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              style={{ width: 200 }}
              allowClear
            />
          </Col>
          <Col>
            <Button 
              type="primary"
              icon={<ReloadOutlined />} 
              onClick={loadSimulationData}
              loading={loading}
              disabled={!selectedProject}
            >
              Refresh
            </Button>
          </Col>
          <Col>
            <Button 
              onClick={() => {
                console.log('[StatusTable] Manual project load test');
                loadProjects();
              }}
              size="small"
            >
              Test Projects
            </Button>
          </Col>
          <Col>
            <Button 
              onClick={() => {
                if (selectedProject) {
                  console.log('[StatusTable] Manual revision load test for:', selectedProject);
                  loadRevisions(selectedProject);
                }
              }}
              size="small"
              disabled={!selectedProject}
            >
              Test Revisions
            </Button>
          </Col>
          <Col>
            <Text type="secondary" style={{ fontSize: '12px' }}>
              Last updated: {lastUpdateTime.toLocaleTimeString()}
            </Text>
          </Col>
          <Col>
            <Text type="secondary" style={{ fontSize: '12px' }}>
              Projects: {projects.length} | Revisions: {revisions.length}
            </Text>
          </Col>
        </Row>
      </Card>

      {/* 데이터 테이블 */}
      <Spin spinning={loading} tip="Loading simulation data...">
        {tableData.map((groupData, index) => (
          <Card 
            key={`${groupData.project}-${groupData.revision}-${groupData.mode}`}
            style={{ marginBottom: '24px' }}
            title={
              <Space size="large">
                <Space>
                  <ProjectOutlined style={{ color: '#1890ff' }} />
                  <Text strong style={{ fontSize: '16px' }}>{groupData.project}</Text>
                  <Text type="secondary" style={{ fontSize: '14px' }}>/ {groupData.revision}</Text>
                  <Text type="secondary" style={{ fontSize: '14px' }}>/ {groupData.mode}</Text>
                </Space>
              </Space>
            }
            bodyStyle={{ padding: '0' }}
          >
            {/* 요약 통계 */}
            <div style={{ padding: '16px', backgroundColor: '#fafafa', borderBottom: '1px solid #f0f0f0' }}>
              {renderSummary(groupData.summary)}
            </div>
            
            {/* 케이스 테이블 */}
            <Table
              columns={columns}
              dataSource={groupData.nodes}
              rowKey="id"
              size="middle"
              scroll={{ x: 1200 }}
              pagination={{
                showSizeChanger: true,
                showQuickJumper: true,
                showTotal: (total, range) => 
                  `${range[0]}-${range[1]} of ${total} cases`,
                pageSizeOptions: ['10', '20', '50', '100'],
                defaultPageSize: 20,
              }}
              rowClassName={(record) => {
                switch (record.status) {
                  case 'Failed': return 'table-row-failed';
                  case 'Running': return 'table-row-running';
                  case 'Completed': return 'table-row-completed';
                  default: return '';
                }
              }}
            />
          </Card>
        ))}
        
        {!loading && tableData.length === 0 && !error && (
          <Card>
            <div style={{ textAlign: 'center', padding: '60px 20px' }}>
              <ProjectOutlined style={{ fontSize: '48px', color: '#d9d9d9', marginBottom: '16px' }} />
              <Title level={4} type="secondary">No simulation data found</Title>
              <Text type="secondary">
                {!selectedProject ? 
                  'Please select a project to view simulation data.' :
                  'No simulation data found for the selected project/revision.'
                }
                <br />
                {selectedProject && 'Try selecting a different project or revision, or refresh the data.'}
              </Text>
            </div>
          </Card>
        )}
      </Spin>
      
      <style>{`
        .table-row-failed {
          background-color: #fff1f0 !important;
        }
        .table-row-running {
          background-color: #e6f7ff !important;
        }
        .table-row-completed {
          background-color: #f6ffed !important;
        }
      `}</style>
    </div>
  );
};

export default SimulationStatusTable;
