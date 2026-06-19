import React, { useState, useEffect, useCallback } from 'react';
import { CalendarClock, RefreshCw, Trash2, PlusCircle, AlertTriangle } from 'lucide-react';
import { apiGet, apiPost, apiRequest } from '../../utils/api';

/**
 * Reservations — Slurm 예약(Reservation) 관리 콘솔 (관리자용, scontrol).
 *
 * 조회(GET) + 생성(POST)/삭제(DELETE). 변경계는 SlurmManagement 와 동일 안전모델:
 * dry_run:true 미리보기 → window.confirm(command) → dry_run:false 실행 → 목록 새로고침.
 * 모든 변경은 백엔드 audit_log 에 기록된다.
 */

/** scontrol show reservation 의 Key=Value 를 담는 객체. 주요 키는 있을 수도/없을 수도 있다. */
interface Reservation extends Record<string, string> {
  ReservationName?: string;
  StartTime?: string;
  EndTime?: string;
  Duration?: string;
  Nodes?: string;
  NodeCnt?: string;
  Users?: string;
  Accounts?: string;
  PartitionName?: string;
  State?: string;
  Flags?: string;
}

interface ListResp {
  success: boolean;
  data?: { reservations: Reservation[]; raw: string };
  error?: string;
}

/** 변경계(생성/삭제) 공통 응답. dry_run 이면 command, 실제면 mode/command/message, 실패면 error. */
interface MutateResp {
  success: boolean;
  dry_run?: boolean;
  mode?: string;
  command?: string;
  message?: string;
  error?: string;
}

/** 생성 폼 상태. */
interface CreateForm {
  reservation_name: string;
  starttime: string;
  duration: string;
  endtime: string;
  users: string;
  accounts: string;
  nodes: string;
  partition: string;
  flags: string;
}

const EMPTY_FORM: CreateForm = {
  reservation_name: '',
  starttime: '',
  duration: '',
  endtime: '',
  users: '',
  accounts: '',
  nodes: '',
  partition: '',
  flags: '',
};

const Reservations: React.FC = () => {
  const [reservations, setReservations] = useState<Reservation[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [form, setForm] = useState<CreateForm>(EMPTY_FORM);
  const [busy, setBusy] = useState(false); // 생성/삭제 진행 중 (중복 클릭 방지)

  const load = useCallback(async () => {
    setLoading(true);
    setErr(null);
    try {
      const r = await apiGet<ListResp>('/api/slurm/reservations', undefined, { skipCache: true });
      setReservations(r.success ? (r.data?.reservations ?? []) : []);
      if (!r.success) setErr(r.error || '예약 목록을 불러오지 못했습니다.');
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const onField = (key: keyof CreateForm) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));

  /** 프론트 검증: starttime 필수, (duration 또는 endtime) 중 1, (users 또는 accounts) 중 1. */
  const validate = (f: CreateForm): string | null => {
    if (!f.starttime.trim()) return 'starttime(시작 시각)은 필수입니다.';
    if (!f.duration.trim() && !f.endtime.trim()) return 'duration 또는 endtime 중 하나는 입력해야 합니다.';
    if (!f.users.trim() && !f.accounts.trim()) return 'users 또는 accounts 중 하나는 입력해야 합니다.';
    return null;
  };

  /** dry_run 미리보기 → command 확인 → 실제 실행. 성공 시 목록 새로고침. */
  const runMutation = async (
    label: string,
    call: (dryRun: boolean) => Promise<MutateResp>,
    destructive = false,
  ) => {
    setBusy(true);
    setErr(null);
    try {
      // 1) dry_run 미리보기
      const pv = await call(true);
      if (!pv.success) {
        setErr(pv.error || `${label} 미리보기에 실패했습니다.`);
        return;
      }
      const cmd = pv.command || '(미리보기 불가 — 그래도 진행 가능)';
      const warn = destructive ? '\n\n⚠️ 파괴적 작업입니다 — 예약이 삭제됩니다.' : '';
      if (!window.confirm(`${label}${warn}\n\n실행될 명령:\n  ${cmd}\n\n진행할까요?`)) return;

      // 2) 실제 실행
      const res = await call(false);
      if (res.success) {
        window.alert(`✅ 완료: ${label}\n${res.message || res.command || ''}`.trim());
        await load();
      } else {
        setErr(res.error || `${label} 실행에 실패했습니다.`);
      }
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

  const onCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    const v = validate(form);
    if (v) { setErr(v); return; }

    const payload: Record<string, unknown> = {
      starttime: form.starttime.trim(),
    };
    if (form.reservation_name.trim()) payload.reservation_name = form.reservation_name.trim();
    if (form.duration.trim()) payload.duration = form.duration.trim();
    if (form.endtime.trim()) payload.endtime = form.endtime.trim();
    if (form.users.trim()) payload.users = form.users.trim();
    if (form.accounts.trim()) payload.accounts = form.accounts.trim();
    if (form.nodes.trim()) payload.nodes = form.nodes.trim();
    if (form.partition.trim()) payload.partition = form.partition.trim();
    if (form.flags.trim()) payload.flags = form.flags.trim();

    const label = `예약 생성${form.reservation_name.trim() ? ` (${form.reservation_name.trim()})` : ''}`;
    await runMutation(label, (dryRun) =>
      apiPost<MutateResp>('/api/slurm/reservations', { ...payload, dry_run: dryRun }),
    );
    // runMutation 내부에서 성공 시 목록을 새로고침하므로, 폼은 비워둔다(취소 시에도 무해).
    if (!validate(form)) setForm(EMPTY_FORM);
  };

  const onDelete = async (name: string) => {
    await runMutation(
      `예약 삭제 (${name})`,
      (dryRun) =>
        apiRequest<MutateResp>(`/api/slurm/reservations/${encodeURIComponent(name)}`, {
          method: 'DELETE',
          body: JSON.stringify({ dry_run: dryRun }),
        }),
      true,
    );
  };

  const FIELDS: { key: keyof CreateForm; label: string; placeholder: string; required?: boolean }[] = [
    { key: 'reservation_name', label: '예약 이름 (선택)', placeholder: '예: maint_2026' },
    { key: 'starttime', label: '시작 시각', placeholder: 'now 또는 2026-06-20T09:00:00', required: true },
    { key: 'duration', label: 'duration (endtime 과 택1)', placeholder: "예: 120 또는 2:00:00" },
    { key: 'endtime', label: 'endtime (duration 과 택1)', placeholder: '예: 2026-06-20T11:00:00' },
    { key: 'users', label: 'users (콤마, accounts 와 택1)', placeholder: '예: alice,bob' },
    { key: 'accounts', label: 'accounts (콤마, users 와 택1)', placeholder: '예: hpc,research' },
    { key: 'nodes', label: 'nodes (선택)', placeholder: '예: cn[01-04]' },
    { key: 'partition', label: 'partition (선택)', placeholder: '예: gpu' },
    { key: 'flags', label: 'flags (선택)', placeholder: '예: MAINT,IGNORE_JOBS' },
  ];

  return (
    <div className="p-6">
      {/* 헤더 */}
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-2xl font-bold text-gray-800 flex items-center gap-2">
            <CalendarClock className="w-6 h-6 text-blue-600" /> Slurm 예약(Reservation)
          </h2>
          <p className="text-sm text-gray-500 mt-1">
            scontrol 예약 관리(관리자). 생성·삭제는 미리보기 후 실행되며 감사 로그에 기록됩니다.
          </p>
        </div>
        <button
          onClick={load}
          className="px-4 py-2 bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300 transition-colors"
        >
          <RefreshCw className={`w-4 h-4 inline mr-1 ${loading ? 'animate-spin' : ''}`} /> 새로고침
        </button>
      </div>

      {err && (
        <div className="mb-4 p-3 bg-red-50 text-red-700 rounded-lg flex items-center gap-2">
          <AlertTriangle className="w-4 h-4 shrink-0" /> {err}
        </div>
      )}

      {/* 예약 목록 */}
      <div className="overflow-x-auto mb-6">
        <table className="min-w-full bg-white rounded-lg shadow-sm">
          <thead>
            <tr className="text-left text-xs text-gray-500 border-b">
              <th className="px-4 py-2">예약 이름</th>
              <th className="px-4 py-2">시작</th>
              <th className="px-4 py-2">종료</th>
              <th className="px-4 py-2">노드</th>
              <th className="px-4 py-2">사용자</th>
              <th className="px-4 py-2">계정</th>
              <th className="px-4 py-2">상태</th>
              <th className="px-4 py-2">삭제</th>
            </tr>
          </thead>
          <tbody>
            {loading ? (
              <tr><td colSpan={8} className="px-4 py-6 text-center text-gray-400">불러오는 중...</td></tr>
            ) : reservations.length === 0 ? (
              <tr><td colSpan={8} className="px-4 py-6 text-center text-gray-400">No reservations — 등록된 예약이 없습니다.</td></tr>
            ) : (
              reservations.map((r, i) => {
                const name = r.ReservationName || `reservation-${i}`;
                return (
                  <tr key={name} className="border-b text-sm">
                    <td className="px-4 py-2 font-medium">{name}</td>
                    <td className="px-4 py-2 text-gray-500">{r.StartTime || '-'}</td>
                    <td className="px-4 py-2 text-gray-500">{r.EndTime || r.Duration || '-'}</td>
                    <td className="px-4 py-2 text-gray-500">{r.Nodes || r.NodeCnt || '-'}</td>
                    <td className="px-4 py-2 text-gray-500">{r.Users || '-'}</td>
                    <td className="px-4 py-2 text-gray-500">{r.Accounts || '-'}</td>
                    <td className="px-4 py-2">{r.State || '-'}</td>
                    <td className="px-4 py-2">
                      <button
                        type="button"
                        disabled={busy || !r.ReservationName}
                        onClick={() => onDelete(name)}
                        title="예약 삭제"
                        className="p-1.5 rounded text-gray-400 hover:text-red-600 hover:bg-red-50 disabled:opacity-40 disabled:cursor-not-allowed"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {/* 생성 폼 */}
      <form onSubmit={onCreate} className="bg-white rounded-lg shadow-sm p-4">
        <h3 className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-1">
          <PlusCircle className="w-4 h-4 text-blue-600" /> 예약 생성
        </h3>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {FIELDS.map((fld) => (
            <div key={fld.key}>
              <label className="block text-xs text-gray-500 mb-1">
                {fld.label}{fld.required && <span className="text-red-500"> *</span>}
              </label>
              <input
                value={form[fld.key]}
                onChange={onField(fld.key)}
                placeholder={fld.placeholder}
                className="w-full h-9 rounded-md border border-gray-300 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
              />
            </div>
          ))}
        </div>
        <p className="text-xs text-gray-400 mt-3">
          검증: 시작 시각 필수 · (duration 또는 endtime) 중 1 · (users 또는 accounts) 중 1.
        </p>
        <div className="mt-3">
          <button
            type="submit"
            disabled={busy}
            className="h-9 px-4 rounded-md bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 disabled:opacity-50 inline-flex items-center gap-1"
          >
            <PlusCircle className="w-4 h-4" /> {busy ? '처리 중...' : '예약 생성 (미리보기)'}
          </button>
        </div>
      </form>
    </div>
  );
};

export default Reservations;
