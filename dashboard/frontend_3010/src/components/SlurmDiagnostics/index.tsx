import React, { useState, useEffect, useCallback } from 'react';
import { Activity, RefreshCw, Gauge, Cpu, Radio, BarChart3, AlertTriangle, Search } from 'lucide-react';
import { apiGet } from '../../utils/api';

/**
 * SlurmDiagnostics — Slurm 진단·리포트(읽기 전용).
 * 백엔드의 읽기 라우트를 서브탭으로 묶어 보여준다:
 *   우선순위(sprio) / 잡 자원(sstat) / 컨트롤러(controller) / 사용량(sreport).
 * 변경계 작업은 없다(전부 GET). 각 응답의 data.raw 를 <pre> 로 안정적으로 노출하고,
 * 구조화 필드(rows 등)가 있으면 테이블로 추가 표시한다.
 */

type SubTab = 'priority' | 'jobstat' | 'controller' | 'usage';

/** 공통 응답 봉투. 성공 시 data, 실패 시 error. raw 는 양쪽 어디든 올 수 있어 둘 다 optional. */
interface ApiResult<T = unknown> {
  success: boolean;
  data?: T;
  error?: string;
  raw?: string;
}

/** raw 가 항상 있다고 가정하는 일반 진단 데이터(우선순위/컨트롤러/잡자원). */
interface RawData {
  raw?: string;
  [key: string]: unknown;
}

/** 사용량(sreport) 행: by 에 따라 컬럼이 다르다. */
interface UsageRow {
  account?: string;
  login?: string;
  used?: number | string;
}

interface UsageData {
  by: string;
  start: string;
  end: string;
  rows: UsageRow[];
  raw?: string;
  mode?: string;
}

type UsageBy = 'account' | 'user';

/** 응답에서 raw 문자열을 안정적으로 뽑는다(성공/실패 양쪽 대응). */
function pickRaw(res: ApiResult<RawData>): string {
  if (res.data && typeof res.data.raw === 'string') return res.data.raw;
  if (typeof res.raw === 'string') return res.raw;
  return '';
}

const SlurmDiagnostics: React.FC = () => {
  const [tab, setTab] = useState<SubTab>('priority');

  // 우선순위(sprio)
  const [priorityRaw, setPriorityRaw] = useState('');
  const [priorityLoading, setPriorityLoading] = useState(false);
  const [priorityErr, setPriorityErr] = useState<string | null>(null);

  // 컨트롤러(controller ping)
  const [controllerRaw, setControllerRaw] = useState('');
  const [controllerLoading, setControllerLoading] = useState(false);
  const [controllerErr, setControllerErr] = useState<string | null>(null);

  // 잡 자원(sstat)
  const [jobId, setJobId] = useState('');
  const [jobStatRaw, setJobStatRaw] = useState('');
  const [jobStatLoading, setJobStatLoading] = useState(false);
  const [jobStatErr, setJobStatErr] = useState<string | null>(null);
  const [jobStatFetched, setJobStatFetched] = useState(false);

  // 사용량(sreport)
  const [usageBy, setUsageBy] = useState<UsageBy>('account');
  const [start, setStart] = useState('');
  const [end, setEnd] = useState('');
  const [usage, setUsage] = useState<UsageData | null>(null);
  const [usageLoading, setUsageLoading] = useState(false);
  const [usageErr, setUsageErr] = useState<string | null>(null);
  const [usageFetched, setUsageFetched] = useState(false);

  const loadPriority = useCallback(async () => {
    setPriorityLoading(true);
    setPriorityErr(null);
    try {
      const r = await apiGet<ApiResult<RawData>>('/api/slurm/jobs/priority', undefined, { skipCache: true });
      setPriorityRaw(pickRaw(r));
      if (!r.success) setPriorityErr(r.error || '우선순위 조회 실패');
    } catch (e) {
      setPriorityErr(e instanceof Error ? e.message : String(e));
    } finally {
      setPriorityLoading(false);
    }
  }, []);

  const loadController = useCallback(async () => {
    setControllerLoading(true);
    setControllerErr(null);
    try {
      const r = await apiGet<ApiResult<RawData>>('/api/slurm/controller/ping', undefined, { skipCache: true });
      setControllerRaw(pickRaw(r));
      if (!r.success) setControllerErr(r.error || '컨트롤러 조회 실패');
    } catch (e) {
      setControllerErr(e instanceof Error ? e.message : String(e));
    } finally {
      setControllerLoading(false);
    }
  }, []);

  const loadJobStat = useCallback(async () => {
    const id = jobId.trim();
    if (!id) {
      setJobStatErr('잡 ID 를 입력하세요.');
      return;
    }
    setJobStatLoading(true);
    setJobStatErr(null);
    setJobStatFetched(true);
    try {
      const r = await apiGet<ApiResult<RawData>>(`/api/slurm/jobs/${encodeURIComponent(id)}/stat`, undefined, { skipCache: true });
      setJobStatRaw(pickRaw(r));
      if (!r.success) setJobStatErr(r.error || '잡 자원 조회 실패');
    } catch (e) {
      setJobStatErr(e instanceof Error ? e.message : String(e));
    } finally {
      setJobStatLoading(false);
    }
  }, [jobId]);

  const loadUsage = useCallback(async () => {
    setUsageLoading(true);
    setUsageErr(null);
    setUsageFetched(true);
    try {
      const params: Record<string, string> = { by: usageBy };
      if (start) params.start = start;
      if (end) params.end = end;
      const r = await apiGet<ApiResult<UsageData>>('/api/slurm/reports/usage', params, { skipCache: true });
      if (r.success && r.data) {
        setUsage(r.data);
      } else {
        setUsage(null);
        setUsageErr(r.error || '사용량 조회 실패');
      }
    } catch (e) {
      setUsage(null);
      setUsageErr(e instanceof Error ? e.message : String(e));
    } finally {
      setUsageLoading(false);
    }
  }, [usageBy, start, end]);

  // 우선순위/컨트롤러는 진입 시 자동 조회.
  useEffect(() => {
    if (tab === 'priority') loadPriority();
    else if (tab === 'controller') loadController();
  }, [tab, loadPriority, loadController]);

  // 헤더 새로고침: 현재 탭만 재조회(잡 자원/사용량은 입력 후 조회한 적 있을 때만).
  const refresh = useCallback(() => {
    if (tab === 'priority') loadPriority();
    else if (tab === 'controller') loadController();
    else if (tab === 'jobstat') { if (jobId.trim()) loadJobStat(); }
    else if (tab === 'usage') { if (usageFetched) loadUsage(); }
  }, [tab, jobId, usageFetched, loadPriority, loadController, loadJobStat, loadUsage]);

  const refreshing =
    (tab === 'priority' && priorityLoading) ||
    (tab === 'controller' && controllerLoading) ||
    (tab === 'jobstat' && jobStatLoading) ||
    (tab === 'usage' && usageLoading);

  const TABS: { id: SubTab; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
    { id: 'priority', label: '우선순위', icon: Gauge },
    { id: 'jobstat', label: '잡 자원', icon: Cpu },
    { id: 'controller', label: '컨트롤러', icon: Radio },
    { id: 'usage', label: '사용량', icon: BarChart3 },
  ];

  const Pre: React.FC<{ text: string; empty: string }> = ({ text, empty }) => (
    <pre className="bg-gray-900 text-gray-100 text-xs p-4 rounded-lg overflow-x-auto whitespace-pre-wrap">
      {text || empty}
    </pre>
  );

  const ErrBox: React.FC<{ msg: string }> = ({ msg }) => (
    <div className="mb-4 p-3 bg-red-50 text-red-700 rounded-lg flex items-center gap-2">
      <AlertTriangle className="w-4 h-4" /> {msg}
    </div>
  );

  return (
    <div className="p-6">
      {/* 헤더 */}
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-2xl font-bold text-gray-800 flex items-center gap-2">
            <Activity className="w-6 h-6 text-blue-600" /> Slurm 진단·리포트
          </h2>
          <p className="text-sm text-gray-500 mt-1">
            우선순위·잡 자원·컨트롤러·사용량을 조회하는 읽기 전용 화면입니다.
          </p>
        </div>
        <button
          onClick={refresh}
          className="px-4 py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-colors"
        >
          <RefreshCw className={`w-4 h-4 inline mr-1 ${refreshing ? 'animate-spin' : ''}`} /> 새로고침
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

      {/* 우선순위(sprio) */}
      {tab === 'priority' && (
        <div>
          {priorityErr && <ErrBox msg={priorityErr} />}
          {priorityLoading ? (
            <p className="text-sm text-gray-500">불러오는 중...</p>
          ) : (
            <Pre text={priorityRaw} empty="우선순위 데이터 없음" />
          )}
        </div>
      )}

      {/* 잡 자원(sstat) */}
      {tab === 'jobstat' && (
        <div>
          <div className="mb-2 text-xs text-gray-500">
            sstat 은 <b>RUNNING(실행 중)</b> 잡에 대해서만 동작합니다. 대기/완료된 잡은 자원 정보가 없습니다.
          </div>
          <div className="flex items-end gap-2 mb-4">
            <div className="min-w-[180px]">
              <label className="block text-xs text-gray-500 mb-1">잡 ID</label>
              <input
                value={jobId}
                onChange={(e) => setJobId(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') loadJobStat(); }}
                placeholder="예: 12345"
                className="w-full h-9 rounded-md border border-gray-300 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
              />
            </div>
            <button
              onClick={loadJobStat}
              disabled={jobStatLoading || !jobId.trim()}
              className="h-9 px-4 rounded-md bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 disabled:opacity-50 inline-flex items-center gap-1"
            >
              <Search className="w-4 h-4" /> {jobStatLoading ? '조회 중...' : '조회'}
            </button>
          </div>
          {jobStatErr && <ErrBox msg={jobStatErr} />}
          {jobStatLoading ? (
            <p className="text-sm text-gray-500">불러오는 중...</p>
          ) : jobStatFetched ? (
            <Pre text={jobStatRaw} empty="잡 자원 데이터 없음 (실행 중 잡인지 확인하세요)" />
          ) : (
            <p className="text-sm text-gray-400">잡 ID 를 입력하고 조회하세요.</p>
          )}
        </div>
      )}

      {/* 컨트롤러(controller ping) */}
      {tab === 'controller' && (
        <div>
          {controllerErr && <ErrBox msg={controllerErr} />}
          {controllerLoading ? (
            <p className="text-sm text-gray-500">불러오는 중...</p>
          ) : (
            <Pre text={controllerRaw} empty="컨트롤러 응답 없음" />
          )}
        </div>
      )}

      {/* 사용량(sreport) */}
      {tab === 'usage' && (
        <div>
          <div className="flex flex-wrap items-end gap-3 mb-4">
            <div>
              <label className="block text-xs text-gray-500 mb-1">집계 기준</label>
              <select
                value={usageBy}
                onChange={(e) => setUsageBy(e.target.value as UsageBy)}
                className="h-9 rounded-md border border-gray-300 px-2 text-sm bg-white"
              >
                <option value="account">account</option>
                <option value="user">user</option>
              </select>
            </div>
            <div>
              <label className="block text-xs text-gray-500 mb-1">시작일</label>
              <input
                type="date"
                value={start}
                onChange={(e) => setStart(e.target.value)}
                className="h-9 rounded-md border border-gray-300 px-2 text-sm"
              />
            </div>
            <div>
              <label className="block text-xs text-gray-500 mb-1">종료일</label>
              <input
                type="date"
                value={end}
                onChange={(e) => setEnd(e.target.value)}
                className="h-9 rounded-md border border-gray-300 px-2 text-sm"
              />
            </div>
            <button
              onClick={loadUsage}
              disabled={usageLoading}
              className="h-9 px-4 rounded-md bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 disabled:opacity-50 inline-flex items-center gap-1"
            >
              <Search className="w-4 h-4" /> {usageLoading ? '조회 중...' : '조회'}
            </button>
            <span className="text-xs text-gray-400">날짜 미입력 시 최근 30일</span>
          </div>

          {usageErr && <ErrBox msg={usageErr} />}

          {usageLoading ? (
            <p className="text-sm text-gray-500">불러오는 중...</p>
          ) : !usageFetched ? (
            <p className="text-sm text-gray-400">조건을 선택하고 조회하세요.</p>
          ) : usage ? (
            <div className="space-y-4">
              <div className="text-xs text-gray-500 flex items-center gap-2">
                기준 <b>{usage.by}</b> · {usage.start} ~ {usage.end}
                {usage.mode === 'mock' && (
                  <span className="px-2 py-0.5 rounded bg-yellow-100 text-yellow-700 text-[10px] font-medium">
                    Mock 데이터
                  </span>
                )}
              </div>

              {/* 구조화 테이블 */}
              <div className="overflow-x-auto">
                <table className="min-w-full bg-white rounded-lg shadow-sm">
                  <thead>
                    <tr className="text-left text-xs text-gray-500 border-b">
                      {usage.by === 'account' && <th className="px-4 py-2">account</th>}
                      <th className="px-4 py-2">login</th>
                      <th className="px-4 py-2">used</th>
                    </tr>
                  </thead>
                  <tbody>
                    {usage.rows.map((row, i) => (
                      <tr key={`${row.account ?? ''}-${row.login ?? ''}-${i}`} className="border-b text-sm">
                        {usage.by === 'account' && (
                          <td className="px-4 py-2 font-medium">{row.account ?? '-'}</td>
                        )}
                        <td className="px-4 py-2">{row.login ?? '-'}</td>
                        <td className="px-4 py-2 text-gray-500">{row.used ?? '-'}</td>
                      </tr>
                    ))}
                    {usage.rows.length === 0 && (
                      <tr>
                        <td colSpan={usage.by === 'account' ? 3 : 2} className="px-4 py-6 text-center text-gray-400">
                          사용량 행 없음
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>

              {/* raw */}
              <Pre text={usage.raw ?? ''} empty="사용량 raw 출력 없음" />
            </div>
          ) : (
            <p className="text-sm text-gray-400">사용량 데이터 없음</p>
          )}
        </div>
      )}
    </div>
  );
};

export default SlurmDiagnostics;
