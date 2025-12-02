import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// components/SimulationStatusTable.tsx (실제 API 버전 - 최적화)
import { useState, useEffect, useCallback } from 'react';
import { Table, Card, Select, Space, Tag, Typography, Spin, Button, Input, Row, Col, Statistic, Alert } from 'antd';
import { ReloadOutlined, SearchOutlined, ProjectOutlined } from '@ant-design/icons';
import { api } from '../../../api/axiosClient';
import { getStatusColor } from '../utils/statusUtils';
const { Title, Text } = Typography;
const { Option } = Select;
const SimulationStatusTable = () => {
    const [projects, setProjects] = useState([]);
    const [selectedProject, setSelectedProject] = useState('');
    const [selectedRevision, setSelectedRevision] = useState('');
    const [revisions, setRevisions] = useState([]);
    const [tableData, setTableData] = useState([]);
    const [loading, setLoading] = useState(false);
    const [searchText, setSearchText] = useState('');
    const [error, setError] = useState(null);
    const [lastUpdateTime, setLastUpdateTime] = useState(new Date());
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
            let projectList = [];
            if (Array.isArray(data)) {
                projectList = data;
            }
            else if (data && Array.isArray(data.projects)) {
                projectList = data.projects;
            }
            else if (data && Array.isArray(data.data)) {
                projectList = data.data;
            }
            else if (data && typeof data === 'object') {
                // 객체의 값들을 배열로 변환 시도
                const values = Object.values(data);
                if (values.length === 1 && Array.isArray(values[0])) {
                    projectList = values[0];
                }
            }
            console.log('[StatusTable] Parsed projects:', projectList);
            setProjects(projectList);
            if (projectList.length > 0 && !selectedProject) {
                const firstProject = projectList[0];
                console.log('[StatusTable] Auto-selecting first project:', firstProject);
                setSelectedProject(firstProject);
            }
        }
        catch (error) {
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
    const loadRevisions = useCallback(async (project) => {
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
                }
                catch (urlError) {
                    console.log('[StatusTable] Failed URL:', url, 'Error:', urlError.message);
                }
            }
            if (!data) {
                throw new Error('All revision API endpoints failed');
            }
            // 다양한 응답 형식 처리
            let revisionList = [];
            if (Array.isArray(data)) {
                revisionList = data;
            }
            else if (data.revisions && Array.isArray(data.revisions)) {
                revisionList = data.revisions;
            }
            else if (data.data && Array.isArray(data.data)) {
                revisionList = data.data;
            }
            else {
                console.log('[StatusTable] Unexpected response format:', data);
                revisionList = [];
            }
            console.log('[StatusTable] Parsed revisions:', revisionList);
            setRevisions(revisionList);
        }
        catch (error) {
            console.error('[StatusTable] Failed to load revisions:', error);
            setError('Failed to load revisions: ' + (error.message || 'Unknown error'));
            setRevisions([]);
        }
    }, []); // 의존성 제거
    // 시뮬레이션 네트워크 데이터 로드
    const loadSimulationData = useCallback(async () => {
        if (!selectedProject)
            return;
        setLoading(true);
        setError(null);
        try {
            // API 호출 파라미터 구성
            const requestBody = {};
            if (selectedProject)
                requestBody.project = selectedProject;
            if (selectedRevision)
                requestBody.revision = selectedRevision;
            console.log('Loading simulation data with params:', requestBody);
            const { data } = await api.post('/api/proxy/automation/api/simulation-automation/simulationnetwork', requestBody);
            console.log('Simulation network API response:', data);
            const nodes = data?.nodes || [];
            const summary = data?.summary || {};
            console.log('Parsed nodes:', nodes.length);
            console.log('Summary:', summary);
            // 프로젝트/리비전/모드별로 데이터 그룹화
            const groupedData = [];
            const groups = new Map();
            nodes.forEach(node => {
                const project = node.project || selectedProject || 'Unknown';
                const revision = node.revision || selectedRevision || 'Unknown';
                const mode = node.mode_short || 'Unknown';
                const key = `${project}/${revision}/${mode}`;
                if (!groups.has(key)) {
                    groups.set(key, []);
                }
                groups.get(key).push(node);
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
                if (a.project !== b.project)
                    return a.project.localeCompare(b.project);
                if (a.revision !== b.revision)
                    return a.revision.localeCompare(b.revision);
                return a.mode.localeCompare(b.mode);
            });
            setTableData(groupedData);
            setLastUpdateTime(new Date());
        }
        catch (error) {
            console.error('Failed to load simulation data:', error);
            setError('Failed to load simulation data: ' + (error.message || 'Unknown error'));
            setTableData([]);
        }
        finally {
            setLoading(false);
        }
    }, [selectedProject, selectedRevision]); // 의존성을 최소화
    const calculateSummary = (nodes) => {
        const summary = {
            total: nodes.length,
            completed: 0,
            running: 0,
            failed: 0,
            pending: 0,
            cancelled: 0
        };
        nodes.forEach(node => {
            const statusKey = node.status.toLowerCase();
            if (statusKey in summary) {
                summary[statusKey]++;
            }
        });
        return summary;
    };
    // 프로젝트 변경 핸들러
    const handleProjectChange = (project) => {
        console.log('[StatusTable] Project changed to:', project);
        setSelectedProject(project);
        setSelectedRevision(''); // 프로젝트 변경시 리비전 초기화
        setTableData([]); // 기존 데이터 클리어
        // 리비전 목록을 즉시 로드
        loadRevisions(project);
    };
    // 리비전 변경 핸들러
    const handleRevisionChange = (revision) => {
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
        }
        else {
            setRevisions([]);
        }
    }, [selectedProject, loadRevisions]);
    // 수동 refresh만 허용 - 자동 로드 제거
    // 사용자가 Refresh 버튼을 클릭해야만 데이터 로드
    // 테이블 컬럼 정의
    const columns = [
        {
            title: 'Case ID',
            dataIndex: 'id',
            key: 'id',
            width: 180,
            fixed: 'left',
            filteredValue: searchText ? [searchText] : null,
            onFilter: (value, record) => record.id.toLowerCase().includes(value.toString().toLowerCase()) ||
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
            render: (path) => (_jsx(Text, { style: { fontSize: '12px' }, title: path, children: path })),
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
            render: (kind) => (_jsx(Tag, { color: kind === 'DropSet' ? 'blue' : 'green', children: kind })),
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
            render: (status) => (_jsx(Tag, { color: getStatusColor(status), children: status })),
        },
    ];
    // 요약 정보 렌더링
    const renderSummary = (summary) => {
        const completionRate = summary.total > 0 ? Math.round((summary.completed / summary.total) * 100) : 0;
        return (_jsxs(Row, { gutter: 16, children: [_jsx(Col, { children: _jsx(Statistic, { title: "Total", value: summary.total, prefix: _jsx(ProjectOutlined, {}) }) }), _jsx(Col, { children: _jsx(Statistic, { title: "Completed", value: summary.completed, valueStyle: { color: '#52c41a' } }) }), _jsx(Col, { children: _jsx(Statistic, { title: "Running", value: summary.running, valueStyle: { color: '#1890ff' } }) }), _jsx(Col, { children: _jsx(Statistic, { title: "Failed", value: summary.failed, valueStyle: { color: '#ff4d4f' } }) }), _jsx(Col, { children: _jsx(Statistic, { title: "Success Rate", value: completionRate, suffix: "%", valueStyle: { color: completionRate > 80 ? '#52c41a' : completionRate > 50 ? '#faad14' : '#ff4d4f' } }) })] }));
    };
    return (_jsxs("div", { style: { padding: '16px', backgroundColor: '#f5f5f5', minHeight: '100vh' }, children: [_jsxs("div", { style: { marginBottom: '24px' }, children: [_jsxs(Title, { level: 2, style: { margin: 0, color: '#1890ff' }, children: [_jsx(ProjectOutlined, {}), " Simulation Status Overview"] }), _jsx(Text, { type: "secondary", children: "\uD504\uB85C\uC81D\uD2B8\uBCC4 \uC2DC\uBBAC\uB808\uC774\uC158 \uCF00\uC774\uC2A4 \uC9C4\uD589 \uC0C1\uD669\uC744 \uD655\uC778\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4. (\uC218\uB3D9 \uC0C8\uB85C\uACE0\uCE68)" })] }), error && (_jsx(Alert, { message: "API Error", description: error, type: "error", showIcon: true, closable: true, onClose: () => setError(null), style: { marginBottom: '16px' } })), _jsx(Card, { style: { marginBottom: '16px' }, bodyStyle: { padding: '16px' }, children: _jsxs(Row, { gutter: [16, 8], align: "middle", children: [_jsx(Col, { children: _jsx(Text, { strong: true, children: "Project:" }) }), _jsx(Col, { children: _jsx(Select, { value: selectedProject, onChange: handleProjectChange, style: { width: 200 }, placeholder: "Select Project", loading: !projects.length, children: projects.map(project => (_jsx(Option, { value: project, children: project }, project))) }) }), _jsx(Col, { children: _jsx(Text, { strong: true, children: "Revision:" }) }), _jsx(Col, { children: _jsx(Select, { value: selectedRevision, onChange: handleRevisionChange, style: { width: 200 }, placeholder: "All Revisions", allowClear: true, loading: !!selectedProject && !revisions.length, children: revisions.map(revision => (_jsx(Option, { value: revision, children: revision }, revision))) }) }), _jsx(Col, { children: _jsx(Input, { placeholder: "Search cases...", prefix: _jsx(SearchOutlined, {}), value: searchText, onChange: (e) => setSearchText(e.target.value), style: { width: 200 }, allowClear: true }) }), _jsx(Col, { children: _jsx(Button, { type: "primary", icon: _jsx(ReloadOutlined, {}), onClick: loadSimulationData, loading: loading, disabled: !selectedProject, children: "Refresh" }) }), _jsx(Col, { children: _jsx(Button, { onClick: () => {
                                    console.log('[StatusTable] Manual project load test');
                                    loadProjects();
                                }, size: "small", children: "Test Projects" }) }), _jsx(Col, { children: _jsx(Button, { onClick: () => {
                                    if (selectedProject) {
                                        console.log('[StatusTable] Manual revision load test for:', selectedProject);
                                        loadRevisions(selectedProject);
                                    }
                                }, size: "small", disabled: !selectedProject, children: "Test Revisions" }) }), _jsx(Col, { children: _jsxs(Text, { type: "secondary", style: { fontSize: '12px' }, children: ["Last updated: ", lastUpdateTime.toLocaleTimeString()] }) }), _jsx(Col, { children: _jsxs(Text, { type: "secondary", style: { fontSize: '12px' }, children: ["Projects: ", projects.length, " | Revisions: ", revisions.length] }) })] }) }), _jsxs(Spin, { spinning: loading, tip: "Loading simulation data...", children: [tableData.map((groupData, index) => (_jsxs(Card, { style: { marginBottom: '24px' }, title: _jsx(Space, { size: "large", children: _jsxs(Space, { children: [_jsx(ProjectOutlined, { style: { color: '#1890ff' } }), _jsx(Text, { strong: true, style: { fontSize: '16px' }, children: groupData.project }), _jsxs(Text, { type: "secondary", style: { fontSize: '14px' }, children: ["/ ", groupData.revision] }), _jsxs(Text, { type: "secondary", style: { fontSize: '14px' }, children: ["/ ", groupData.mode] })] }) }), bodyStyle: { padding: '0' }, children: [_jsx("div", { style: { padding: '16px', backgroundColor: '#fafafa', borderBottom: '1px solid #f0f0f0' }, children: renderSummary(groupData.summary) }), _jsx(Table, { columns: columns, dataSource: groupData.nodes, rowKey: "id", size: "middle", scroll: { x: 1200 }, pagination: {
                                    showSizeChanger: true,
                                    showQuickJumper: true,
                                    showTotal: (total, range) => `${range[0]}-${range[1]} of ${total} cases`,
                                    pageSizeOptions: ['10', '20', '50', '100'],
                                    defaultPageSize: 20,
                                }, rowClassName: (record) => {
                                    switch (record.status) {
                                        case 'Failed': return 'table-row-failed';
                                        case 'Running': return 'table-row-running';
                                        case 'Completed': return 'table-row-completed';
                                        default: return '';
                                    }
                                } })] }, `${groupData.project}-${groupData.revision}-${groupData.mode}`))), !loading && tableData.length === 0 && !error && (_jsx(Card, { children: _jsxs("div", { style: { textAlign: 'center', padding: '60px 20px' }, children: [_jsx(ProjectOutlined, { style: { fontSize: '48px', color: '#d9d9d9', marginBottom: '16px' } }), _jsx(Title, { level: 4, type: "secondary", children: "No simulation data found" }), _jsxs(Text, { type: "secondary", children: [!selectedProject ?
                                            'Please select a project to view simulation data.' :
                                            'No simulation data found for the selected project/revision.', _jsx("br", {}), selectedProject && 'Try selecting a different project or revision, or refresh the data.'] })] }) }))] }), _jsx("style", { children: `
        .table-row-failed {
          background-color: #fff1f0 !important;
        }
        .table-row-running {
          background-color: #e6f7ff !important;
        }
        .table-row-completed {
          background-color: #f6ffed !important;
        }
      ` })] }));
};
export default SimulationStatusTable;
