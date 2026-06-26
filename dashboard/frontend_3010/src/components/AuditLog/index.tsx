// 감사 로그 뷰어 컴포넌트
import React, { useState, useEffect, useCallback } from 'react';
import { ScrollText, Search, RefreshCw, AlertTriangle, ChevronLeft, ChevronRight } from 'lucide-react';
import { apiGet } from '../../utils/api';

/**
 * AuditLog — 감사 로그 뷰어(관리자 전용).
 * 백엔드 GET /api/audit (admin 전용, apiGet 이 JWT 부착)를 소비해
 * username/action/기간 필터 + 페이지네이션 테이블로 보여준다.
 * action 은 prefix 매칭('node.' 'job.' 'account.'), detail 은 JSON 문자열일 수 있어 truncate 표시.
 */

interface AuditEntry {
  id: number;
  timestamp: string;
  username: string | null;
  action: string;
  target: string | null;
  detail: string | null;
  result: string;
  source_ip: string | null;
}

interface AuditResp {
  success: boolean;
  total: number;
  limit: number;
  offset: number;
  entries: AuditEntry[];
  error?: string;
}

interface Filters {
  username: string;
  action: string;
  since: string;
  until: string;
}

const LIMIT = 50;

function isFail(result: string): boolean {
  const r = result.toLowerCase();
  return r.includes('fail') || r.includes('error') || r.includes('deny') || r.includes('denied');
}

function resultBadge(result: string): string {
  return isFail(result)
    ? 'bg-red-100 text-red-700'
    : 'bg-green-100 text-green-700';
}

const AuditLog: React.FC = () => {
  const [entries, setEntries] = useState<AuditEntry[]>([]);
  const [total, setTotal] = useState(0);
  const [offset, setOffset] = useState(0);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<number | null>(null);

  // 입력 중인 필터(조회 버튼을 눌러야 적용)
  const [draft, setDraft] = useState<Filters>({ username: '', action: '', since: '', until: '' });
  // 실제 조회에 쓰는 필터
  const [applied, setApplied] = useState<Filters>({ username: '', action: '', since: '', until: '' });

  const load = useCallback(async () => {
    setLoading(true);
    setErr(null);
    try {
      const params: Record<string, string | number> = { limit: LIMIT, offset };
      if (applied.username.trim()) params.username = applied.username.trim();
      if (applied.action.trim()) params.action = applied.action.trim();
      if (applied.since) params.since = applied.since;
      if (applied.until) params.until = applied.until;

      const r = await apiGet<AuditResp>('/api/audit', params, { skipCache: true });
      if (r.success) {
        setEntries(r.entries || []);
        setTotal(r.total || 0);
      } else {
        setEntries([]);
        setTotal(0);
        setErr(r.error || '감사 로그를 불러오지 못했습니다.');
      }
    } catch (e) {
      setEntries([]);
      setTotal(0);
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [applied, offset]);

  useEffect(() => { load(); }, [load]);

  const onSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setOffset(0);              // 필터 변경 시 offset 리셋
    setApplied({ ...draft });
  };

  const onPrev = () => setOffset((o) => Math.max(0, o - LIMIT));
  const onNext = () => setOffset((o) => (o + LIMIT < total ? o + LIMIT : o));

  const rangeStart = total === 0 ? 0 : offset + 1;
  const rangeEnd = offset + entries.length;

  return (
    <div className="p-6">
      {/* 헤더 */}
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-2xl font-bold text-gray-800 flex items-center gap-2">
            <ScrollText className="w-6 h-6 text-blue-600" /> 감사 로그
          </h2>
          <p className="text-sm text-gray-500 mt-1">
            변경계 Slurm 작업 등 시스템 활동 기록입니다(관리자 전용).
          </p>
        </div>
        <button
          onClick={() => load()}
          className="px-4 py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-colors"
        >
          <RefreshCw className={`w-4 h-4 inline mr-1 ${loading ? 'animate-spin' : ''}`} /> 새로고침
        </button>
      </div>

      {/* 필터 */}
      <form onSubmit={onSearch} className="flex flex-wrap items-end gap-3 mb-4 bg-white rounded-lg shadow-sm p-4">
        <div className="flex-1 min-w-[140px]">
          <label className="block text-xs text-gray-500 mb-1">사용자</label>
          <input
            value={draft.username}
            onChange={(e) => setDraft((d) => ({ ...d, username: e.target.value }))}
            placeholder="예: koopark"
            className="w-full h-9 rounded-md border border-gray-300 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
          />
        </div>
        <div className="flex-1 min-w-[140px]">
          <label className="block text-xs text-gray-500 mb-1">액션 (접두사)</label>
          <input
            value={draft.action}
            onChange={(e) => setDraft((d) => ({ ...d, action: e.target.value }))}
            placeholder="예: node. / job. / account."
            className="w-full h-9 rounded-md border border-gray-300 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
          />
        </div>
        <div>
          <label className="block text-xs text-gray-500 mb-1">시작일</label>
          <input
            type="date"
            value={draft.since}
            onChange={(e) => setDraft((d) => ({ ...d, since: e.target.value }))}
            className="h-9 rounded-md border border-gray-300 px-3 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-400"
          />
        </div>
        <div>
          <label className="block text-xs text-gray-500 mb-1">종료일</label>
          <input
            type="date"
            value={draft.until}
            onChange={(e) => setDraft((d) => ({ ...d, until: e.target.value }))}
            className="h-9 rounded-md border border-gray-300 px-3 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-blue-400"
          />
        </div>
        <button
          type="submit"
          className="h-9 px-4 rounded-md bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 inline-flex items-center gap-1"
        >
          <Search className="w-4 h-4" /> 조회
        </button>
      </form>

      {err && (
        <div className="mb-4 p-3 bg-red-50 text-red-700 rounded-lg flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {err}
        </div>
      )}

      {/* 테이블 */}
      <div className="overflow-x-auto">
        <table className="min-w-full bg-white rounded-lg shadow-sm">
          <thead>
            <tr className="text-left text-xs text-gray-500 border-b">
              <th className="px-4 py-2">시각</th>
              <th className="px-4 py-2">사용자</th>
              <th className="px-4 py-2">액션</th>
              <th className="px-4 py-2">대상</th>
              <th className="px-4 py-2">결과</th>
              <th className="px-4 py-2">출처 IP</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={6} className="px-4 py-6 text-center text-gray-400">불러오는 중...</td></tr>
            ) : entries.length === 0 ? (
              <tr><td colSpan={6} className="px-4 py-6 text-center text-gray-400">감사 로그가 없습니다.</td></tr>
            ) : (
              entries.map((e) => (
                <tr
                  key={e.id}
                  className="border-b text-sm align-top hover:bg-gray-50 cursor-pointer"
                  onClick={() => setExpanded((x) => (x === e.id ? null : e.id))}
                >
                  <td className="px-4 py-2 whitespace-nowrap font-mono text-xs text-gray-600">{e.timestamp}</td>
                  <td className="px-4 py-2">{e.username ?? '—'}</td>
                  <td className="px-4 py-2 font-mono text-xs">{e.action}</td>
                  <td className="px-4 py-2 text-gray-600">{e.target ?? '—'}</td>
                  <td className="px-4 py-2">
                    <span className={`px-2 py-0.5 rounded text-xs ${resultBadge(e.result)}`}>{e.result}</span>
                  </td>
                  <td className="px-4 py-2 font-mono text-xs text-gray-500">{e.source_ip ?? '—'}</td>
                </tr>
              ))
            )}
            {/* detail: 펼친 행 아래에 전체 표시 */}
            {!loading && entries.map((e) =>
              expanded === e.id && e.detail ? (
                <tr key={`${e.id}-detail`} className="border-b bg-gray-50">
                  <td colSpan={6} className="px-4 py-2">
                    <pre className="text-xs text-gray-700 whitespace-pre-wrap break-all" title={e.detail}>{e.detail}</pre>
                  </td>
                </tr>
              ) : null,
            )}
          </tbody>
        </table>
      </div>

      {/* 페이지네이션 */}
      <div className="flex items-center justify-between mt-4">
        <span className="text-sm text-gray-500">
          {total === 0 ? '0건' : `총 ${total}건 중 ${rangeStart}-${rangeEnd}`}
        </span>
        <div className="flex gap-2">
          <button
            onClick={onPrev}
            disabled={offset === 0 || loading}
            className="px-3 py-1.5 text-sm rounded-md bg-gray-100 text-gray-700 hover:bg-gray-200 disabled:opacity-40 disabled:cursor-not-allowed inline-flex items-center gap-1"
          >
            <ChevronLeft className="w-4 h-4" /> 이전
          </button>
          <button
            onClick={onNext}
            disabled={offset + entries.length >= total || loading}
            className="px-3 py-1.5 text-sm rounded-md bg-gray-100 text-gray-700 hover:bg-gray-200 disabled:opacity-40 disabled:cursor-not-allowed inline-flex items-center gap-1"
          >
            다음 <ChevronRight className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  );
};

export default AuditLog;
