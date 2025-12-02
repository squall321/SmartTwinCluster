import React, { useState, useEffect, useCallback } from 'react';
import {
  Play, Pause, Trash2, Search, Plus,
  Clock, User, Cpu, CheckCircle, XCircle, AlertCircle
} from 'lucide-react';
import { SlurmJob, JobSubmitRequest } from '../types';
import { UploadedFile } from './JobManagement/types';
import { apiGet, apiPost, API_ENDPOINTS } from '../utils/api';
import toast from 'react-hot-toast';
import FileUploadSection from './JobManagement/FileUploadSection';
import { createDefaultScript, updateScriptWithFilesSmartly } from './JobManagement/scriptUtils';
import { API_CONFIG } from '../config/api.config';

interface JobManagementProps {
  apiMode: 'mock' | 'production';
  selectedTemplate?: any;  // Template from JobTemplates
  showSubmitModal?: boolean;
  onCloseSubmitModal?: () => void;
}

interface NodeConfig {
  total_cores: number;
  nodes: number;
  cpus_per_node: number;
}

interface Partition {
  name: string;
  label: string;
  allowedCoreSizes: number[];
  allowedConfigs: NodeConfig[];
  description: string;
}

export const JobManagement: React.FC<JobManagementProps> = ({ 
  apiMode,
  selectedTemplate,
  showSubmitModal: externalShowSubmitModal,
  onCloseSubmitModal
}) => {
  const [jobs, setJobs] = useState<SlurmJob[]>([]);
  const [filteredJobs, setFilteredJobs] = useState<SlurmJob[]>([]);
  const [searchTerm, setSearchTerm] = useState('');
  const [stateFilter, setStateFilter] = useState<string>('all');
  const [showSubmitModal, setShowSubmitModal] = useState(false);
  const [selectedJob, setSelectedJob] = useState<SlurmJob | null>(null);

  // External control of submit modal
  useEffect(() => {
    if (externalShowSubmitModal !== undefined) {
      setShowSubmitModal(externalShowSubmitModal);
    }
  }, [externalShowSubmitModal]);

  // Mock 작업 데이터 생성
  const generateMockJobs = (): SlurmJob[] => {
    const states: SlurmJob['state'][] = ['RUNNING', 'PENDING', 'COMPLETED', 'FAILED'];
    const users = ['user01', 'user02', 'user03', 'admin', 'researcher'];
    const partitions = ['group1', 'group2', 'group3', 'gpu', 'debug'];
    
    return Array.from({ length: 20 }, (_, i) => ({
      jobId: `${10000 + i}`,
      userId: users[Math.floor(Math.random() * users.length)],
      jobName: `job_${i}_${['simulation', 'training', 'analysis', 'test'][Math.floor(Math.random() * 4)]}`,
      partition: partitions[Math.floor(Math.random() * partitions.length)],
      qos: `qos_${Math.floor(Math.random() * 3) + 1}`,
      state: states[Math.floor(Math.random() * states.length)],
      nodes: Math.floor(Math.random() * 10) + 1,
      cpus: [128, 256, 512, 1024][Math.floor(Math.random() * 4)],
      memory: `${Math.floor(Math.random() * 64) + 16}GB`,
      startTime: new Date(Date.now() - Math.random() * 86400000).toISOString(),
      runTime: `${Math.floor(Math.random() * 23)}:${String(Math.floor(Math.random() * 60)).padStart(2, '0')}:${String(Math.floor(Math.random() * 60)).padStart(2, '0')}`,
      priority: Math.floor(Math.random() * 1000),
      account: 'research',
    }));
  };

  // 작업 목록 로드
  const fetchJobs = useCallback(async () => {
    try {
      const response = await apiGet<{
        success: boolean;
        mode: string;
        jobs: SlurmJob[];
        count: number;
        error?: string;
      }>(API_ENDPOINTS.jobs, undefined, { skipCache: true });

      if (response.success && response.jobs) {
        // 데이터 유효성 검사: jobs가 배열인지 확인
        const validJobs = Array.isArray(response.jobs) ? response.jobs : [];
        setJobs(validJobs);
        setFilteredJobs(validJobs);
      } else {
        throw new Error(response.error || 'Failed to fetch jobs');
      }
    } catch (error) {
      console.error('Failed to fetch jobs:', error);
      // 에러 발생 시에도 빈 배열로 설정하여 UI가 깨지지 않도록 함
      setJobs([]);
      setFilteredJobs([]);
      toast.error('Failed to load jobs', { duration: 2000 });
    }
  }, []);

  useEffect(() => {
    fetchJobs();
    const interval = setInterval(fetchJobs, 5000); // 5초마다 업데이트

    return () => clearInterval(interval);
  }, [fetchJobs]);

  // 필터링
  useEffect(() => {
    let filtered = jobs;

    if (searchTerm) {
      filtered = filtered.filter(job =>
        job.jobName.toLowerCase().includes(searchTerm.toLowerCase()) ||
        job.userId.toLowerCase().includes(searchTerm.toLowerCase()) ||
        job.jobId.includes(searchTerm)
      );
    }

    if (stateFilter !== 'all') {
      filtered = filtered.filter(job => job.state === stateFilter);
    }

    setFilteredJobs(filtered);
  }, [searchTerm, stateFilter, jobs]);

  // 작업 제어
  const handleJobAction = async (jobId: string, action: 'cancel' | 'hold' | 'release') => {
    try {
      const endpoint = action === 'cancel'
        ? API_ENDPOINTS.jobCancel(jobId)
        : action === 'hold'
        ? API_ENDPOINTS.jobHold(jobId)
        : API_ENDPOINTS.jobRelease(jobId);

      const response = await apiPost<{
        success: boolean;
        mode: string;
        message: string;
        error?: string;
      }>(endpoint);

      // 안전하게 response 체크
      if (response && typeof response === 'object' && 'success' in response) {
        if (response.success) {
          toast.success(response.message || `Job ${action}led successfully`, { duration: 2000 });
        } else {
          toast.error(response.error || `Failed to ${action} job`, { duration: 3000 });
        }
      } else {
        toast.error(`Unexpected response from server`, { duration: 3000 });
      }
    } catch (error) {
      console.error(`Failed to ${action} job ${jobId}:`, error);
      const errorMessage = error instanceof Error ? error.message : String(error);
      toast.error(`Error: ${errorMessage}`, { duration: 3000 });
    } finally {
      // 성공이든 실패든 항상 목록 새로고침하여 현재 상태 반영
      // finally 블록을 사용하여 어떤 경우에도 실행되도록 함
      try {
        await fetchJobs();
      } catch (refreshError) {
        console.error('Failed to refresh jobs list:', refreshError);
        // 새로고침 실패는 무시 (사용자에게 에러를 두 번 보여주지 않기 위해)
      }
    }
  };

  // 통계 계산
  const stats = {
    total: jobs.length,
    running: jobs.filter(j => j.state === 'RUNNING').length,
    pending: jobs.filter(j => j.state === 'PENDING').length,
    completed: jobs.filter(j => j.state === 'COMPLETED').length,
    failed: jobs.filter(j => j.state === 'FAILED').length,
  };

  return (
    <div className="p-6 space-y-6">
      {/* 통계 카드 */}
      <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
        <StatCard label="Total Jobs" value={stats.total} color="gray" icon={<Cpu className="w-5 h-5" />} />
        <StatCard label="Running" value={stats.running} color="blue" icon={<Play className="w-5 h-5" />} />
        <StatCard label="Pending" value={stats.pending} color="amber" icon={<Clock className="w-5 h-5" />} />
        <StatCard label="Completed" value={stats.completed} color="green" icon={<CheckCircle className="w-5 h-5" />} />
        <StatCard label="Failed" value={stats.failed} color="red" icon={<XCircle className="w-5 h-5" />} />
      </div>

      {/* 검색 및 필터 */}
      <div className="bg-white rounded-lg shadow p-4">
        <div className="flex gap-4 items-center">
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
            <input
              type="text"
              placeholder="Search jobs by ID, name, or user..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>
          
          <div className="flex gap-2">
            <select
              value={stateFilter}
              onChange={(e) => setStateFilter(e.target.value)}
              className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
            >
              <option value="all">All States</option>
              <option value="RUNNING">Running</option>
              <option value="PENDING">Pending</option>
              <option value="COMPLETED">Completed</option>
              <option value="FAILED">Failed</option>
              <option value="CANCELLED">Cancelled</option>
            </select>
            
            <button
              onClick={() => setShowSubmitModal(true)}
              className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition"
            >
              <Plus className="w-5 h-5" />
              Submit Job
            </button>
          </div>
        </div>
      </div>

      {/* 작업 목록 */}
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Job ID
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Name
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  User
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  State
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Partition
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Resources
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Runtime
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {filteredJobs.map((job) => (
                <tr key={job.jobId} className="hover:bg-gray-50">
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                    {job.jobId}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <button
                      onClick={() => setSelectedJob(job)}
                      className="hover:text-blue-600 hover:underline"
                    >
                      {job.jobName}
                    </button>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                    <div className="flex items-center gap-1">
                      <User className="w-4 h-4" />
                      {job.userId}
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <JobStateBadge state={job.state} />
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                    {job.partition}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                    <div className="flex items-center gap-1">
                      <Cpu className="w-4 h-4" />
                      {job.nodes}N / {job.cpus}C
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                    {job.runTime || '-'}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                    <div className="flex gap-2">
                      {(job.state === 'RUNNING' || job.state === 'PENDING') && (
                        <button
                          onClick={() => handleJobAction(job.jobId, 'cancel')}
                          className="p-1 text-red-600 hover:bg-red-50 rounded"
                          title="Cancel Job"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      )}
                      {job.state === 'PENDING' && (
                        <button
                          onClick={() => handleJobAction(job.jobId, 'hold')}
                          className="p-1 text-amber-600 hover:bg-amber-50 rounded"
                          title="Hold Job"
                        >
                          <Pause className="w-4 h-4" />
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        
        {filteredJobs.length === 0 && (
          <div className="text-center py-12 text-gray-500">
            No jobs found
          </div>
        )}
      </div>

      {/* 작업 제출 모달 */}
      {showSubmitModal && (
        <JobSubmitModal
          apiMode={apiMode}
          template={selectedTemplate}
          onClose={() => {
            setShowSubmitModal(false);
            if (onCloseSubmitModal) onCloseSubmitModal();
          }}
          onSubmit={() => {
            setShowSubmitModal(false);
            if (onCloseSubmitModal) onCloseSubmitModal();
            toast.success('Job submitted successfully');
          }}
        />
      )}

      {/* 작업 상세 모달 */}
      {selectedJob && (
        <JobDetailsModal
          job={selectedJob}
          onClose={() => setSelectedJob(null)}
        />
      )}
    </div>
  );
};

// 통계 카드 컴포넌트
interface StatCardProps {
  label: string;
  value: number;
  color: 'gray' | 'blue' | 'amber' | 'green' | 'red';
  icon?: React.ReactNode;
}

const StatCard: React.FC<StatCardProps> = ({ label, value, color, icon }) => {
  const colorClasses = {
    gray: 'bg-gray-100 text-gray-900',
    blue: 'bg-blue-100 text-blue-900',
    amber: 'bg-amber-100 text-amber-900',
    green: 'bg-green-100 text-green-900',
    red: 'bg-red-100 text-red-900',
  };

  return (
    <div className={`rounded-lg p-4 ${colorClasses[color]}`}>
      <div className="flex items-center justify-between mb-1">
        <div className="text-sm font-medium">{label}</div>
        {icon && <div className="opacity-70">{icon}</div>}
      </div>
      <div className="text-2xl font-bold">{value}</div>
    </div>
  );
};

// 작업 상태 배지
const JobStateBadge: React.FC<{ state: SlurmJob['state'] }> = ({ state }) => {
  const stateConfig: Record<string, { color: string; icon: any }> = {
    RUNNING: { color: 'bg-blue-100 text-blue-800', icon: Play },
    PENDING: { color: 'bg-amber-100 text-amber-800', icon: Clock },
    COMPLETED: { color: 'bg-green-100 text-green-800', icon: CheckCircle },
    FAILED: { color: 'bg-red-100 text-red-800', icon: XCircle },
    CANCELLED: { color: 'bg-gray-100 text-gray-800', icon: XCircle },
    TIMEOUT: { color: 'bg-orange-100 text-orange-800', icon: AlertCircle },
  };

  // 안전하게 config 가져오기, 없으면 기본값 사용
  const config = stateConfig[state] || {
    color: 'bg-gray-100 text-gray-800',
    icon: AlertCircle
  };
  const Icon = config.icon;

  return (
    <span className={`inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-medium ${config.color}`}>
      <Icon className="w-3 h-3" />
      {state}
    </span>
  );
};

// 작업 제출 모달
interface JobSubmitModalProps {
  apiMode: 'mock' | 'production';
  template?: any;
  onClose: () => void;
  onSubmit: () => void;
}

const JobSubmitModal: React.FC<JobSubmitModalProps> = ({ apiMode, template, onClose, onSubmit }) => {
  // 임시 Job ID 생성 (파일 업로드용)
  const [tempJobId] = useState(() => `tmp-${Date.now()}`);
  
  // 업로드된 파일 상태
  const [uploadedFiles, setUploadedFiles] = useState<UploadedFile[]>([]);
  
  // Template ID 저장
  const [templateId] = useState(() => template?.id);
  
  // 파티션 정보
  const [partitions, setPartitions] = useState<Partition[]>([]);
  const [loadingPartitions, setLoadingPartitions] = useState(true);
  const [allowedConfigs, setAllowedConfigs] = useState<NodeConfig[]>([]);
  const [selectedConfigIndex, setSelectedConfigIndex] = useState(0);
  const [cpusPerNode, setCpusPerNode] = useState(128);
  
  const [formData, setFormData] = useState<JobSubmitRequest>(() => {
    // If template is provided, use template values
    if (template && template.config) {
      return {
        jobName: template.name || '',
        partition: template.config.partition || 'group1',
        nodes: template.config.nodes || 1,
        cpus: template.config.cpus || 128,
        memory: template.config.memory || '16GB',
        time: template.config.time || '01:00:00',
        script: template.config.script || createDefaultScript(),
        gpus: template.config.gpu,
        files: [],
      };
    }
    // Default values
    return {
      jobName: '',
      partition: 'group1',
      nodes: 1,
      cpus: 128,
      memory: '16GB',
      time: '01:00:00',
      script: createDefaultScript(),
      files: [],
    };
  });

  // 기존 템플릿의 구성과 일치하는 인덱스 찾기
  const findMatchingConfigIndex = (configs: NodeConfig[], nodes: number, cpus: number): number => {
    const totalCores = nodes * cpus;
    const index = configs.findIndex(
      config => config.total_cores === totalCores || 
               (config.nodes === nodes && config.cpus_per_node === cpus)
    );
    return index >= 0 ? index : 0;
  };

  // 파티션 목록 로드
  useEffect(() => {
    const loadPartitions = async () => {
      try {
        setLoadingPartitions(true);
        const response = await apiGet<{
          success: boolean;
          partitions: Partition[];
          cpus_per_node: number;
        }>('/api/groups/partitions');

        if (response && response.success && response.partitions) {
          setPartitions(response.partitions);
          setCpusPerNode(response.cpus_per_node || 128);

          if (template) {
            // 템플릿 사용: 현재 파티션의 구성 로드
            const currentPartition = response.partitions.find(
              (p: Partition) => p.name === template.config.partition
            );

            if (currentPartition) {
              setAllowedConfigs(currentPartition.allowedConfigs);

              // 기존 템플릿의 nodes/cpus와 일치하는 구성 찾기
              const matchingIndex = findMatchingConfigIndex(
                currentPartition.allowedConfigs,
                template.config.nodes,
                template.config.cpus
              );
              setSelectedConfigIndex(matchingIndex);
            }
          } else {
            // 템플릿 없음: 첫 번째 파티션을 기본값으로
            if (response.partitions.length > 0) {
              const firstPartition = response.partitions[0];
              const firstConfig = firstPartition.allowedConfigs[0];

              setFormData(prev => ({
                ...prev,
                partition: firstPartition.name,
                nodes: firstConfig.nodes,
                cpus: firstConfig.cpus_per_node
              }));
              setAllowedConfigs(firstPartition.allowedConfigs);
              setSelectedConfigIndex(0);
            }
          }
        }
      } catch (error) {
        console.error('Failed to load partitions:', error);
      } finally {
        setLoadingPartitions(false);
      }
    };

    loadPartitions();
  }, [template]);

  // Partition 변경 시 허용된 구성 목록 업데이트
  useEffect(() => {
    const selectedPartition = partitions.find(p => p.name === formData.partition);
    if (selectedPartition) {
      setAllowedConfigs(selectedPartition.allowedConfigs);
      
      // 파티션이 변경되면 첫 번째 구성을 기본값으로 설정
      if (selectedPartition.allowedConfigs.length > 0) {
        const firstConfig = selectedPartition.allowedConfigs[0];
        setFormData(prev => ({
          ...prev,
          nodes: firstConfig.nodes,
          cpus: firstConfig.cpus_per_node
        }));
        setSelectedConfigIndex(0);
      }
    }
  }, [formData.partition, partitions]);

  // 구성 선택 변경 시 nodes와 cpus 업데이트
  const handleConfigChange = (index: number) => {
    const config = allowedConfigs[index];
    setSelectedConfigIndex(index);
    setFormData(prev => ({
      ...prev,
      nodes: config.nodes,
      cpus: config.cpus_per_node
    }));
  };
  
  // 파일 변경 시 스크립트 자동 업데이트 (스마트 모드)
  useEffect(() => {
    const updatedScript = updateScriptWithFilesSmartly(
      formData.script,
      uploadedFiles,
      tempJobId,
      templateId
    );
    
    setFormData(prev => ({
      ...prev,
      script: updatedScript,
      files: uploadedFiles,
    }));
  }, [uploadedFiles, tempJobId, templateId]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    if (apiMode === 'mock') {
      toast.success('Job submitted successfully (Mock Mode)');
      onSubmit();
    } else {
      try {
        const response = await fetch(`${API_CONFIG.API_BASE_URL.replace(':5010', ':5000')}/api/slurm/jobs/submit`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(formData),
        });
        
        const data = await response.json();
        if (data.success) {
          toast.success(`Job ${data.jobId} submitted successfully`);
          onSubmit();
        } else {
          toast.error('Failed to submit job');
        }
      } catch (error) {
        toast.error(`Error: ${error}`);
      }
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        <div className="p-6">
          <div className="mb-4">
            <h2 className="text-2xl font-bold">Submit New Job</h2>
            {template && (
              <p className="mt-1 text-sm text-blue-600">
                Using template: <span className="font-semibold">{template.name}</span>
              </p>
            )}
          </div>
          
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Job Name *
              </label>
              <input
                type="text"
                required
                value={formData.jobName}
                onChange={(e) => setFormData({ ...formData, jobName: e.target.value })}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                placeholder="my_job"
              />
            </div>

            {/* 파일 업로드 섹션 */}
            <FileUploadSection
              files={uploadedFiles}
              jobId={tempJobId}
              onFilesChange={setUploadedFiles}
              templateId={templateId}
            />

            {/* Partition Selection */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Partition *
                <span className="text-xs text-gray-500 ml-1">(Group)</span>
              </label>
              {loadingPartitions ? (
                <div className="w-full px-3 py-2 border border-gray-300 rounded-lg bg-gray-50 text-gray-500 text-sm">
                  Loading partitions...
                </div>
              ) : partitions.length === 0 ? (
                <div className="w-full px-3 py-2 border border-red-300 rounded-lg bg-red-50 text-red-600 text-xs">
                  No partitions available
                </div>
              ) : (
                <select
                  required
                  value={formData.partition}
                  onChange={(e) => setFormData({ ...formData, partition: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                >
                  {partitions.map((p) => (
                    <option key={p.name} value={p.name}>
                      {p.label} ({p.name})
                    </option>
                  ))}
                </select>
              )}
            </div>

            {/* Resource Configuration Selection */}
            {allowedConfigs.length > 0 && (
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Resource Configuration *
                  <span className="text-xs text-gray-500 ml-1">(Based on Partition Policy)</span>
                </label>
                <div className="grid grid-cols-1 gap-2 max-h-48 overflow-y-auto">
                  {allowedConfigs.map((config, index) => (
                    <div
                      key={index}
                      onClick={() => handleConfigChange(index)}
                      className={`p-3 border-2 rounded-lg cursor-pointer transition-all ${
                        selectedConfigIndex === index
                          ? 'border-blue-500 bg-blue-50'
                          : 'border-gray-200 hover:border-gray-300 bg-white'
                      }`}
                    >
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-3">
                          <input
                            type="radio"
                            checked={selectedConfigIndex === index}
                            onChange={() => handleConfigChange(index)}
                            className="w-4 h-4 text-blue-600"
                          />
                          <div>
                            <div className="font-semibold text-gray-900">
                              {config.total_cores} Total Cores
                            </div>
                            <div className="text-sm text-gray-600">
                              {config.nodes} node{config.nodes > 1 ? 's' : ''} × {config.cpus_per_node} CPUs/node
                            </div>
                          </div>
                        </div>
                        {selectedConfigIndex === index && (
                          <div className="text-blue-600 font-semibold text-sm">
                            ✓ Selected
                          </div>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Display Selected Configuration */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Nodes
                  <span className="text-xs text-gray-500 ml-1">(Auto-calculated)</span>
                </label>
                <input
                  type="number"
                  value={formData.nodes}
                  disabled
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg bg-gray-100 text-gray-600 cursor-not-allowed"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  CPUs per Node
                  <span className="text-xs text-gray-500 ml-1">(Auto-calculated)</span>
                </label>
                <input
                  type="number"
                  value={formData.cpus}
                  disabled
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg bg-gray-100 text-gray-600 cursor-not-allowed"
                />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Memory
                </label>
                <input
                  type="text"
                  value={formData.memory}
                  onChange={(e) => setFormData({ ...formData, memory: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  placeholder="16GB"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Time Limit
                </label>
                <input
                  type="text"
                  value={formData.time}
                  onChange={(e) => setFormData({ ...formData, time: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  placeholder="HH:MM:SS"
                />
              </div>
            </div>

            {/* Info Box */}
            {allowedConfigs.length > 0 && (
              <div className="p-3 bg-blue-50 border border-blue-200 rounded-lg">
                <div className="text-sm font-semibold text-blue-900 mb-1">
                  ℹ️ Resource Policy for "{formData.partition}"
                </div>
                <div className="text-xs text-blue-700 space-y-1">
                  <div>• Each node has {cpusPerNode} CPU cores</div>
                  <div>• Partition allows {allowedConfigs.length} configuration{allowedConfigs.length > 1 ? 's' : ''}</div>
                  <div>• Total cores selected: <span className="font-semibold">{formData.nodes * formData.cpus}</span></div>
                </div>
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Job Script *
              </label>
              <textarea
                required
                value={formData.script}
                onChange={(e) => setFormData({ ...formData, script: e.target.value })}
                rows={10}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 font-mono text-sm"
                placeholder="#!/bin/bash&#10;&#10;# Your script here"
              />
            </div>

            <div className="flex gap-3 pt-4">
              <button
                type="button"
                onClick={onClose}
                className="flex-1 px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={loadingPartitions}
                className="flex-1 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
              >
                Submit Job
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
};

// 작업 상세 모달
interface JobDetailsModalProps {
  job: SlurmJob;
  onClose: () => void;
}

const JobDetailsModal: React.FC<JobDetailsModalProps> = ({ job, onClose }) => {
  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        <div className="p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-2xl font-bold">Job Details</h2>
            <JobStateBadge state={job.state} />
          </div>
          
          <div className="space-y-4">
            <DetailRow label="Job ID" value={job.jobId} />
            <DetailRow label="Job Name" value={job.jobName} />
            <DetailRow label="User" value={job.userId} />
            <DetailRow label="Partition" value={job.partition} />
            <DetailRow label="QoS" value={job.qos} />
            <DetailRow label="Nodes" value={job.nodes.toString()} />
            <DetailRow label="CPUs" value={job.cpus.toString()} />
            {job.memory && <DetailRow label="Memory" value={job.memory} />}
            {job.priority && <DetailRow label="Priority" value={job.priority.toString()} />}
            {job.account && <DetailRow label="Account" value={job.account} />}
            {job.startTime && <DetailRow label="Start Time" value={new Date(job.startTime).toLocaleString()} />}
            {job.runTime && <DetailRow label="Runtime" value={job.runTime} />}
          </div>

          <div className="flex gap-3 pt-6">
            <button
              onClick={onClose}
              className="flex-1 px-4 py-2 bg-gray-600 text-white rounded-lg hover:bg-gray-700"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

const DetailRow: React.FC<{ label: string; value: string }> = ({ label, value }) => (
  <div className="flex justify-between py-2 border-b">
    <span className="font-medium text-gray-700">{label}</span>
    <span className="text-gray-900">{value}</span>
  </div>
);
