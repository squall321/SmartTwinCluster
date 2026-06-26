// Slurm 관리 콘솔 컴포넌트
import React, { useState, useEffect, useCallback } from 'react';
import { API_CONFIG } from '../../config/api.config';
import {
  Activity, RefreshCw, Server, Briefcase, Gauge, Power,
  PlayCircle, PauseCircle, RotateCw, ArrowUpCircle, AlertTriangle,
} from 'lucide-react';

/**
 * SlurmManagement — Slurm 관리 콘솔.
 * 백엔드 slurm_admin_api(읽기 6 + 변경계 8 라우트)를 웹에서 직접 다룬다.
 * 변경계는 dry_run 미리보기 → 확인 → 실행(MCP/REST 와 동일 안전모델).
 * 모든 변경은 백엔드 audit_log 에 기록된다.
 */

type SubTab = 'diag' | 'partitions' | 'jobs' | 'fairshare';

interface ApiResult<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
  command?: string;
  dry_run?: boolean;
  raw?: string;
}

const base = () => API_CONFIG.API_BASE_URL;

const SlurmManagement: React.FC = () => {
  const [tab, setTab] = useState<SubTab>('partitions');
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  // 읽기 데이터
  const [diag, setDiag] = useState<string>('');
  const [partitions, setPartitions] = useState<Record<string, string>[]>([]);
  const [jobs, setJobs] = useState<Record<string, string>[]>([]);
  const [fairshare, setFairshare] = useState<string>('');

  const getJson = useCallback(async (path: string): Promise<ApiResult> => {
    const r = await fetch(`${base()}${path}`, { headers: { 'Content-Type': 'application/json' } });
    return r.json();
  }, []);

  const refresh = useCallback(async () => {
    setLoading(true);
    setErr(null);
    try {
      if (tab === 'diag') {
        const d = await getJson('/api/slurm/diag');
        setDiag(d.success ? (typeof d.data === 'string' ? d.data : JSON.stringify(d.data, null, 2)) || d.raw || '' : (d.error || '진단 실패'));
      } else if (tab === 'partitions') {
        const d = await getJson('/api/slurm/partitions');
        setPartitions(d.success && Array.isArray(d.data) ? (d.data as Record<string, string>[]) : []);
      } else if (tab === 'jobs') {
        const d = await getJson('/api/slurm/jobs');
        const arr = (d as { jobs?: unknown[] }).jobs ?? d.data;
        setJobs(Array.isArray(arr) ? (arr as Record<string, string>[]) : []);
      } else if (tab === 'fairshare') {
        const d = await getJson('/api/slurm/fairshare');
        setFairshare(d.success ? (typeof d.data === 'string' ? d.data : JSON.stringify(d.data, null, 2)) || d.raw || '' : (d.error || 'fairshare 실패'));
      }
    } catch (e) {
      setErr(String(e));
    } finally {
      setLoading(false);
    }
  }, [tab, getJson]);

  useEffect(() => { refresh(); }, [refresh]);

  /** 변경계 공통: dry_run 미리보기 → 확인 → 실제 실행. */
  const mutate = async (
    method: 'POST' | 'PATCH',
    path: string,
    body: Record<string, unknown>,
    label: string,
    destructive = false,
  ) => {
    try {
      // 1) dry_run 미리보기
      const pv = await fetch(`${base()}${path}`, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...body, dry_run: true }),
      });
      const pvData: ApiResult = await pv.json();
      const cmd = pvData.command || '(미리보기 불가 — 그래도 진행 가능)';
      const warn = destructive ? '\n\n⚠️ 파괴적 작업입니다 (실행 중 잡이 종료될 수 있음).' : '';
      if (!window.confirm(`${label}${warn}\n\n실행될 명령:\n  ${cmd}\n\n진행할까요?`)) return;

      // 2) 실제 실행
      const r = await fetch(`${base()}${path}`, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...body, dry_run: false }),
      });
      const data: ApiResult = await r.json();
      if (data.success) {
        window.alert(`✅ 완료: ${label}`);
        await refresh();
      } else if (r.status === 403) {
        window.alert(`⛔ 권한 없음: ${data.error || '이 작업이 거부되었습니다.'}`);
      } else {
        window.alert(`❌ 실패: ${data.error || '알 수 없는 오류'}`);
      }
    } catch (e) {
      window.alert(`오류: ${e}`);
    }
  };

  const TABS: { id: SubTab; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
    { id: 'partitions', label: '파티션 관리', icon: Server },
    { id: 'jobs', label: '잡 제어', icon: Briefcase },
    { id: 'diag', label: '스케줄러 진단', icon: Activity },
    { id: 'fairshare', label: '공정공유', icon: Gauge },
  ];

  return (
    <div className="p-6">
      {/* 헤더 */}
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-2xl font-bold text-gray-800 flex items-center gap-2">
            <Power className="w-6 h-6 text-blue-600" /> Slurm 관리
          </h2>
          <p className="text-sm text-gray-500 mt-1">
            변경 작업은 미리보기 후 실행되며 감사 로그에 기록됩니다.
          </p>
        </div>
        <button
          onClick={refresh}
          className="px-4 py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-colors"
        >
          <RefreshCw className={`w-4 h-4 inline mr-1 ${loading ? 'animate-spin' : ''}`} /> 새로고침
        </button>
      </div>

      {/* 서브 탭 */}
      <div className="flex gap-2 mb-4 border-b border-gray-200">
        {TABS.map(t => {
          const Icon = t.icon;
          return (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={`px-4 py-2 text-sm font-medium transition-colors border-b-2 ${
                tab === t.id
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              <Icon className="w-4 h-4 inline mr-1" /> {t.label}
            </button>
          );
        })}
      </div>

      {err && (
        <div className="mb-4 p-3 bg-red-50 text-red-700 rounded-lg flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {err}
        </div>
      )}

      {/* 파티션 관리 */}
      {tab === 'partitions' && (
        <div className="overflow-x-auto">
          <table className="min-w-full bg-white rounded-lg shadow-sm">
            <thead>
              <tr className="text-left text-xs text-gray-500 border-b">
                <th className="px-4 py-2">파티션</th>
                <th className="px-4 py-2">상태</th>
                <th className="px-4 py-2">노드</th>
                <th className="px-4 py-2">상태 전환</th>
              </tr>
            </thead>
            <tbody>
              {partitions.map((p, i) => {
                const name = p.PartitionName || p.name || `part-${i}`;
                return (
                  <tr key={name} className="border-b text-sm">
                    <td className="px-4 py-2 font-medium">{name}</td>
                    <td className="px-4 py-2">{p.State || '-'}</td>
                    <td className="px-4 py-2 text-gray-500">{p.Nodes || p.TotalNodes || '-'}</td>
                    <td className="px-4 py-2">
                      <div className="flex gap-1">
                        {(['UP', 'DOWN', 'DRAIN', 'INACTIVE'] as const).map(st => (
                          <button
                            key={st}
                            onClick={() => mutate(
                              'POST', `/api/slurm/partitions/${name}/state`, { state: st },
                              `파티션 ${name} → ${st}`, st === 'DOWN' || st === 'INACTIVE',
                            )}
                            className={`px-2 py-1 text-xs rounded ${
                              st === 'UP' ? 'bg-green-100 text-green-700 hover:bg-green-200'
                              : st === 'DRAIN' ? 'bg-yellow-100 text-yellow-700 hover:bg-yellow-200'
                              : 'bg-red-100 text-red-700 hover:bg-red-200'
                            }`}
                          >
                            {st}
                          </button>
                        ))}
                      </div>
                    </td>
                  </tr>
                );
              })}
              {partitions.length === 0 && (
                <tr><td colSpan={4} className="px-4 py-6 text-center text-gray-400">파티션 없음</td></tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* 잡 제어 */}
      {tab === 'jobs' && (
        <div className="overflow-x-auto">
          <table className="min-w-full bg-white rounded-lg shadow-sm">
            <thead>
              <tr className="text-left text-xs text-gray-500 border-b">
                <th className="px-4 py-2">잡 ID</th>
                <th className="px-4 py-2">이름</th>
                <th className="px-4 py-2">사용자</th>
                <th className="px-4 py-2">상태</th>
                <th className="px-4 py-2">제어</th>
              </tr>
            </thead>
            <tbody>
              {jobs.map((j, i) => {
                const id = j.job_id || j.JOBID || j.id || `job-${i}`;
                return (
                  <tr key={id} className="border-b text-sm">
                    <td className="px-4 py-2 font-mono">{id}</td>
                    <td className="px-4 py-2">{j.name || j.NAME || '-'}</td>
                    <td className="px-4 py-2 text-gray-500">{j.user || j.USER || '-'}</td>
                    <td className="px-4 py-2">{j.state || j.ST || j.STATE || '-'}</td>
                    <td className="px-4 py-2">
                      <div className="flex gap-1">
                        <button onClick={() => mutate('POST', `/api/slurm/jobs/${id}/requeue`, {}, `잡 ${id} 재큐잉`)}
                          className="px-2 py-1 text-xs rounded bg-blue-100 text-blue-700 hover:bg-blue-200">
                          <RotateCw className="w-3 h-3 inline" /> requeue
                        </button>
                        <button onClick={() => mutate('POST', `/api/slurm/jobs/${id}/hold`, {}, `잡 ${id} 홀드`)}
                          className="px-2 py-1 text-xs rounded bg-yellow-100 text-yellow-700 hover:bg-yellow-200">
                          <PauseCircle className="w-3 h-3 inline" /> hold
                        </button>
                        <button onClick={() => mutate('POST', `/api/slurm/jobs/${id}/release`, {}, `잡 ${id} 릴리즈`)}
                          className="px-2 py-1 text-xs rounded bg-green-100 text-green-700 hover:bg-green-200">
                          <PlayCircle className="w-3 h-3 inline" /> release
                        </button>
                        <button onClick={() => mutate('POST', `/api/slurm/jobs/${id}/top`, {}, `잡 ${id} 최상단 이동`)}
                          className="px-2 py-1 text-xs rounded bg-purple-100 text-purple-700 hover:bg-purple-200">
                          <ArrowUpCircle className="w-3 h-3 inline" /> top
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
              {jobs.length === 0 && (
                <tr><td colSpan={5} className="px-4 py-6 text-center text-gray-400">실행/대기 중 잡 없음</td></tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* 스케줄러 진단 */}
      {tab === 'diag' && (
        <pre className="bg-gray-900 text-gray-100 text-xs p-4 rounded-lg overflow-x-auto whitespace-pre-wrap">
          {diag || '진단 데이터 없음'}
        </pre>
      )}

      {/* 공정공유 */}
      {tab === 'fairshare' && (
        <pre className="bg-gray-900 text-gray-100 text-xs p-4 rounded-lg overflow-x-auto whitespace-pre-wrap">
          {fairshare || 'fairshare 데이터 없음'}
        </pre>
      )}
    </div>
  );
};

export default SlurmManagement;
