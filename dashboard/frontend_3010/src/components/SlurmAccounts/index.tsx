import React, { useState, useEffect, useCallback } from 'react';
import { UserCog, Users, RefreshCw, Trash2, Plus, AlertTriangle } from 'lucide-react';
import { apiGet, apiPost, apiRequest } from '../../utils/api';

/**
 * SlurmAccounts — Slurm 계정·Association 관리(sacctmgr, 관리자용).
 *
 * 조회(GET)는 apiGet, 변경계(POST/DELETE)는 dry_run 미리보기 → window.confirm 에
 * 실행될 sacctmgr 명령 표시 → 확인 시 실제 실행(SlurmManagement 와 동일 안전모델).
 * DELETE 는 body(dry_run/user/account)를 실어야 하므로 apiRequest 를 직접 사용한다
 * (apiDelete 는 body 미지원). 모든 호출은 JWT 가 자동 부착되며 admin 인증이 필요하다.
 */

type SubTab = 'accounts' | 'associations';

interface SlurmAccount {
  account: string;
  description: string;
  organization: string;
}
interface SlurmAssociation {
  account: string;
  user: string;
  partition: string;
  qos: string;
  def_qos: string;
  grp_tres: string;
}

interface AccountsResp {
  success: boolean;
  data?: { accounts: SlurmAccount[]; raw: string };
  error?: string;
}
interface AssociationsResp {
  success: boolean;
  data?: { associations: SlurmAssociation[]; raw: string };
  error?: string;
}

/** 변경계 응답: dry_run 이면 command, 실제면 mode/command/message, 실패면 error. */
interface MutateResp {
  success: boolean;
  dry_run?: boolean;
  mode?: string;
  command?: string;
  message?: string;
  error?: string;
}

const SlurmAccounts: React.FC = () => {
  const [tab, setTab] = useState<SubTab>('accounts');
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const [accounts, setAccounts] = useState<SlurmAccount[]>([]);
  const [associations, setAssociations] = useState<SlurmAssociation[]>([]);

  // 계정 생성 폼
  const [newAccount, setNewAccount] = useState('');
  const [newDescription, setNewDescription] = useState('');
  const [newOrganization, setNewOrganization] = useState('');

  // Association 추가 폼
  const [assocUser, setAssocUser] = useState('');
  const [assocAccount, setAssocAccount] = useState('');
  const [assocPartition, setAssocPartition] = useState('');
  const [assocQos, setAssocQos] = useState('');

  const refresh = useCallback(async () => {
    setLoading(true);
    setErr(null);
    try {
      if (tab === 'accounts') {
        const r = await apiGet<AccountsResp>('/api/slurm/accounts');
        if (r.success) setAccounts(r.data?.accounts || []);
        else setErr(r.error || '계정 목록을 불러오지 못했습니다.');
      } else {
        const r = await apiGet<AssociationsResp>('/api/slurm/associations');
        if (r.success) setAssociations(r.data?.associations || []);
        else setErr(r.error || 'Association 목록을 불러오지 못했습니다.');
      }
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [tab]);

  useEffect(() => { refresh(); }, [refresh]);

  /**
   * 변경계 공통: dry_run:true 로 미리보기 → command 를 window.confirm 에 표시 →
   * 확인 시 dry_run:false 로 재호출 → 성공하면 목록 새로고침.
   */
  const mutate = useCallback(async (
    call: (dryRun: boolean) => Promise<MutateResp>,
    label: string,
    destructive = false,
  ): Promise<boolean> => {
    setErr(null);
    try {
      // 1) dry_run 미리보기
      const preview = await call(true);
      if (!preview.success) {
        setErr(preview.error || `${label} 미리보기 실패`);
        return false;
      }
      const cmd = preview.command || '(미리보기 불가)';
      const warn = destructive ? '\n\n⚠️ 파괴적 작업입니다 (되돌릴 수 없습니다).' : '';
      if (!window.confirm(`${label}${warn}\n\n실행될 명령:\n  ${cmd}\n\n진행할까요?`)) return false;

      // 2) 실제 실행
      const result = await call(false);
      if (result.success) {
        await refresh();
        return true;
      }
      setErr(result.error || `${label} 실패`);
      return false;
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
      return false;
    }
  }, [refresh]);

  const onCreateAccount = async (e: React.FormEvent) => {
    e.preventDefault();
    const account = newAccount.trim();
    if (!account) return;
    const ok = await mutate(
      (dry_run) => apiPost<MutateResp>('/api/slurm/accounts', {
        account,
        description: newDescription.trim() || undefined,
        organization: newOrganization.trim() || undefined,
        dry_run,
      }),
      `계정 '${account}' 생성`,
    );
    if (ok) {
      setNewAccount('');
      setNewDescription('');
      setNewOrganization('');
    }
  };

  const onDeleteAccount = (account: string) => {
    void mutate(
      (dry_run) => apiRequest<MutateResp>(`/api/slurm/accounts/${account}`, {
        method: 'DELETE',
        body: JSON.stringify({ dry_run }),
      }),
      `계정 '${account}' 삭제`,
      true,
    );
  };

  const onAddAssociation = async (e: React.FormEvent) => {
    e.preventDefault();
    const user = assocUser.trim();
    const account = assocAccount.trim();
    if (!user || !account) return;
    const ok = await mutate(
      (dry_run) => apiPost<MutateResp>('/api/slurm/associations', {
        user,
        account,
        partition: assocPartition.trim() || undefined,
        qos: assocQos.trim() || undefined,
        dry_run,
      }),
      `Association 추가 (${user} → ${account})`,
    );
    if (ok) {
      setAssocUser('');
      setAssocAccount('');
      setAssocPartition('');
      setAssocQos('');
    }
  };

  const onDeleteAssociation = (user: string, account: string) => {
    void mutate(
      (dry_run) => apiRequest<MutateResp>('/api/slurm/associations', {
        method: 'DELETE',
        body: JSON.stringify({ user, account, dry_run }),
      }),
      `Association 삭제 (${user} → ${account})`,
      true,
    );
  };

  const TABS: { id: SubTab; label: string; icon: React.ComponentType<{ className?: string }> }[] = [
    { id: 'accounts', label: '계정', icon: Users },
    { id: 'associations', label: 'Association', icon: UserCog },
  ];

  const inputCls = 'w-full h-9 rounded-md border border-gray-300 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-400';

  return (
    <div className="p-6">
      {/* 헤더 */}
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-2xl font-bold text-gray-800 flex items-center gap-2">
            <UserCog className="w-6 h-6 text-blue-600" /> Slurm 계정·Association
          </h2>
          <p className="text-sm text-gray-500 mt-1">
            sacctmgr 기반 계정/Association 관리(관리자용). 변경 작업은 미리보기 후 실행됩니다.
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
        {TABS.map((t) => {
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

      {/* 계정 탭 */}
      {tab === 'accounts' && (
        <div className="space-y-4">
          {/* 생성 폼 */}
          <form onSubmit={onCreateAccount} className="flex flex-wrap items-end gap-3 bg-white rounded-lg shadow-sm p-4">
            <div className="flex-1 min-w-[160px]">
              <label className="block text-xs text-gray-500 mb-1">계정 (필수)</label>
              <input value={newAccount} onChange={(e) => setNewAccount(e.target.value)} placeholder="예: research" className={inputCls} />
            </div>
            <div className="flex-1 min-w-[160px]">
              <label className="block text-xs text-gray-500 mb-1">설명 (선택)</label>
              <input value={newDescription} onChange={(e) => setNewDescription(e.target.value)} placeholder="예: 연구팀" className={inputCls} />
            </div>
            <div className="flex-1 min-w-[160px]">
              <label className="block text-xs text-gray-500 mb-1">조직 (선택)</label>
              <input value={newOrganization} onChange={(e) => setNewOrganization(e.target.value)} placeholder="예: R&D" className={inputCls} />
            </div>
            <button
              type="submit"
              disabled={!newAccount.trim()}
              className="h-9 px-4 rounded-md bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 disabled:opacity-50 inline-flex items-center gap-1"
            >
              <Plus className="w-4 h-4" /> 계정 생성
            </button>
          </form>

          {/* 목록 */}
          <div className="overflow-x-auto">
            <table className="min-w-full bg-white rounded-lg shadow-sm">
              <thead>
                <tr className="text-left text-xs text-gray-500 border-b">
                  <th className="px-4 py-2">계정</th>
                  <th className="px-4 py-2">설명</th>
                  <th className="px-4 py-2">조직</th>
                  <th className="px-4 py-2">삭제</th>
                </tr>
              </thead>
              <tbody>
                {loading ? (
                  <tr><td colSpan={4} className="px-4 py-6 text-center text-gray-400">불러오는 중...</td></tr>
                ) : accounts.length === 0 ? (
                  <tr><td colSpan={4} className="px-4 py-6 text-center text-gray-400">계정 없음</td></tr>
                ) : (
                  accounts.map((a) => (
                    <tr key={a.account} className="border-b text-sm">
                      <td className="px-4 py-2 font-medium">{a.account}</td>
                      <td className="px-4 py-2 text-gray-500">{a.description || '—'}</td>
                      <td className="px-4 py-2 text-gray-500">{a.organization || '—'}</td>
                      <td className="px-4 py-2">
                        <button
                          type="button"
                          onClick={() => onDeleteAccount(a.account)}
                          title="계정 삭제"
                          className="p-1.5 rounded text-gray-400 hover:text-red-600 hover:bg-red-50"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Association 탭 */}
      {tab === 'associations' && (
        <div className="space-y-4">
          {/* 추가 폼 */}
          <form onSubmit={onAddAssociation} className="flex flex-wrap items-end gap-3 bg-white rounded-lg shadow-sm p-4">
            <div className="flex-1 min-w-[140px]">
              <label className="block text-xs text-gray-500 mb-1">사용자 (필수)</label>
              <input value={assocUser} onChange={(e) => setAssocUser(e.target.value)} placeholder="예: alice" className={inputCls} />
            </div>
            <div className="flex-1 min-w-[140px]">
              <label className="block text-xs text-gray-500 mb-1">계정 (필수)</label>
              <input value={assocAccount} onChange={(e) => setAssocAccount(e.target.value)} placeholder="예: research" className={inputCls} />
            </div>
            <div className="flex-1 min-w-[140px]">
              <label className="block text-xs text-gray-500 mb-1">파티션 (선택)</label>
              <input value={assocPartition} onChange={(e) => setAssocPartition(e.target.value)} placeholder="예: gpu" className={inputCls} />
            </div>
            <div className="flex-1 min-w-[140px]">
              <label className="block text-xs text-gray-500 mb-1">QoS (선택)</label>
              <input value={assocQos} onChange={(e) => setAssocQos(e.target.value)} placeholder="예: normal" className={inputCls} />
            </div>
            <button
              type="submit"
              disabled={!assocUser.trim() || !assocAccount.trim()}
              className="h-9 px-4 rounded-md bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 disabled:opacity-50 inline-flex items-center gap-1"
            >
              <Plus className="w-4 h-4" /> Association 추가
            </button>
          </form>

          {/* 목록 */}
          <div className="overflow-x-auto">
            <table className="min-w-full bg-white rounded-lg shadow-sm">
              <thead>
                <tr className="text-left text-xs text-gray-500 border-b">
                  <th className="px-4 py-2">계정</th>
                  <th className="px-4 py-2">사용자</th>
                  <th className="px-4 py-2">파티션</th>
                  <th className="px-4 py-2">QoS</th>
                  <th className="px-4 py-2">삭제</th>
                </tr>
              </thead>
              <tbody>
                {loading ? (
                  <tr><td colSpan={5} className="px-4 py-6 text-center text-gray-400">불러오는 중...</td></tr>
                ) : associations.length === 0 ? (
                  <tr><td colSpan={5} className="px-4 py-6 text-center text-gray-400">Association 없음</td></tr>
                ) : (
                  associations.map((a, i) => (
                    <tr key={`${a.account}|${a.user}|${a.partition}|${i}`} className="border-b text-sm">
                      <td className="px-4 py-2 font-medium">{a.account}</td>
                      <td className="px-4 py-2">{a.user || '—'}</td>
                      <td className="px-4 py-2 text-gray-500">{a.partition || '—'}</td>
                      <td className="px-4 py-2 text-gray-500">{a.qos || '—'}</td>
                      <td className="px-4 py-2">
                        <button
                          type="button"
                          onClick={() => onDeleteAssociation(a.user, a.account)}
                          disabled={!a.user || !a.account}
                          title="Association 삭제"
                          className="p-1.5 rounded text-gray-400 hover:text-red-600 hover:bg-red-50 disabled:opacity-40 disabled:hover:text-gray-400 disabled:hover:bg-transparent"
                        >
                          <Trash2 className="w-4 h-4" />
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
};

export default SlurmAccounts;
