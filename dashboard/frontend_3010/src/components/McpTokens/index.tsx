// MCP 토큰 발급/Claude 연결가이드 컴포넌트
import React, { useState, useEffect, useCallback } from 'react';
import { Plug, Trash2, Copy, Check, AlertTriangle, KeyRound } from 'lucide-react';
import { apiGet, apiPost, apiDelete } from '../../utils/api';

/**
 * McpTokens — 개인 액세스 토큰(MCP 연동) 발급/관리 + Claude Code/Desktop 연결 가이드.
 *
 * 발급된 평문 토큰(kst_…)은 이 화면에서 **1회만** 노출된다(서버는 sha256 해시만 저장).
 * 토큰을 박은 Claude Code/Desktop 등록 명령을 그대로 복사해 붙이면 된다.
 * 연결 후 Claude 가 Slurm 을 조회/제어할 때 이 토큰으로 **그 사용자 권한**으로 동작한다.
 */

interface TokenInfo {
  id: number;
  name: string;
  token_prefix: string;
  created_at: string | null;
  last_used_at: string | null;
  expires_at: string | null;
  revoked_at: string | null;
}
interface ListResp { success: boolean; tokens?: TokenInfo[]; error?: string }
interface CreateResp { success: boolean; token?: string; info?: TokenInfo; message?: string; error?: string }
interface DeleteResp { success: boolean; message?: string; error?: string }

/** HTTP(비보안 컨텍스트) 운영서버에서도 동작하도록 navigator.clipboard + textarea 폴백. */
async function copyText(text: string): Promise<boolean> {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      return true;
    }
  } catch { /* 폴백으로 진행 */ }
  try {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    const ok = document.execCommand('copy');
    document.body.removeChild(ta);
    return ok;
  } catch {
    return false;
  }
}

function fmtDate(s: string | null): string {
  if (!s) return '—';
  try {
    return new Date(s.replace(' ', 'T')).toLocaleDateString('ko-KR', { year: '2-digit', month: '2-digit', day: '2-digit' });
  } catch {
    return s;
  }
}

function tokenStatus(t: TokenInfo): { label: string; cls: string } {
  if (t.revoked_at) return { label: '취소됨', cls: 'bg-gray-100 text-gray-500' };
  if (t.expires_at && new Date(t.expires_at.replace(' ', 'T')) < new Date())
    return { label: '만료', cls: 'bg-yellow-100 text-yellow-700' };
  return { label: '활성', cls: 'bg-green-100 text-green-700' };
}

const McpTokens: React.FC = () => {
  const [tokens, setTokens] = useState<TokenInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [name, setName] = useState('');
  const [expiresDays, setExpiresDays] = useState(90);
  const [creating, setCreating] = useState(false);
  const [reveal, setReveal] = useState<string | null>(null);  // 방금 발급된 평문(1회 노출)
  const [copied, setCopied] = useState<string | null>(null);  // 복사 피드백 키

  const load = useCallback(async () => {
    setLoading(true);
    setErr(null);
    try {
      const r = await apiGet<ListResp>('/api/me/mcp-tokens');
      setTokens(r.success ? (r.tokens || []) : []);
      if (!r.success) setErr(r.error || '토큰 목록을 불러오지 못했습니다.');
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  const onCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) return;
    setCreating(true);
    setErr(null);
    try {
      const r = await apiPost<CreateResp>('/api/me/mcp-tokens', { name: name.trim(), expires_days: expiresDays });
      if (r.success && r.token) {
        setReveal(r.token);
        setName('');
        await load();
      } else {
        setErr(r.error || '토큰 발급 실패');
      }
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setCreating(false);
    }
  };

  const onDelete = async (t: TokenInfo) => {
    if (!window.confirm(`'${t.name}' 토큰을 삭제할까요?\n이 토큰을 쓰는 연결은 즉시 끊기고 목록에서 사라집니다.`)) return;
    try {
      const r = await apiDelete<DeleteResp>(`/api/me/mcp-tokens/${t.id}`);
      if (r.success) await load();
      else setErr(r.error || '삭제 실패');
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    }
  };

  const doCopy = async (text: string, key: string) => {
    const ok = await copyText(text);
    if (ok) {
      setCopied(key);
      window.setTimeout(() => setCopied((c) => (c === key ? null : c)), 1500);
    } else {
      setErr('복사 실패 — 직접 선택해 복사하세요.');
    }
  };

  // 연결 가이드(토큰 주입). MCP 서버는 대시보드와 같은 호스트의 5012 포트(HTTP, streamable).
  const host = typeof window !== 'undefined' ? window.location.hostname : 'localhost';
  const mcpUrl = `http://${host}:5012/mcp`;

  // Claude Code — 네이티브 HTTP 트랜스포트로 /mcp 엔드포인트에 직접 등록(Node/npx 불필요).
  const claudeCodeCmd = reveal
    ? `claude mcp add --transport http slurm-mcp ${mcpUrl} \\\n  --header "Authorization: Bearer ${reveal}"`
    : '';

  // Claude Desktop — claude_desktop_config.json 의 mcpServers 안에 붙여넣는 항목.
  const desktopCfg = reveal
    ? `"slurm-mcp": ${JSON.stringify(
        {
          command: 'npx',
          args: ['-y', 'mcp-remote', mcpUrl, '--allow-http', '--header', 'Authorization:${AUTH}'],
          env: { AUTH: `Bearer ${reveal}`, NODE_OPTIONS: '--use-system-ca' },
        },
        null,
        2,
      )}`
    : '';

  const CopyBtn: React.FC<{ text: string; ckey: string; label: string }> = ({ text, ckey, label }) => (
    <button
      type="button"
      onClick={() => doCopy(text, ckey)}
      className="px-3 py-1 text-xs rounded bg-gray-100 text-gray-700 hover:bg-gray-200 inline-flex items-center gap-1"
    >
      {copied === ckey ? <Check className="w-3.5 h-3.5 text-green-600" /> : <Copy className="w-3.5 h-3.5" />}
      {copied === ckey ? '복사됨' : label}
    </button>
  );

  return (
    <div className="max-w-3xl">
      {/* 헤더 */}
      <div className="mb-4">
        <h2 className="text-2xl font-bold text-gray-800 flex items-center gap-2">
          <Plug className="w-6 h-6 text-blue-600" /> MCP 토큰 (Claude 연동)
        </h2>
        <p className="text-sm text-gray-500 mt-1">
          Claude(Claude Code/Desktop)가 Slurm 을 조회·제어할 때 쓰는 개인 토큰입니다.
          발급된 값은 <b>한 번만</b> 보이니 바로 복사하세요. 유출되면 여기서 삭제하면 즉시 무효화됩니다.
        </p>
      </div>

      {err && (
        <div className="mb-4 p-3 bg-red-50 text-red-700 rounded-lg flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {err}
        </div>
      )}

      {/* 방금 발급된 토큰 — 1회 노출 + 연결 가이드 */}
      {reveal && (
        <div className="mb-5 rounded-lg border border-blue-300 bg-blue-50 p-4 space-y-3">
          <div className="text-sm font-semibold text-blue-700">
            토큰이 발급되었습니다. 지금 복사하세요 — 다시 볼 수 없습니다.
          </div>
          <div className="flex items-center gap-2">
            <code className="flex-1 truncate rounded bg-white border px-2 py-1 text-xs font-mono">{reveal}</code>
            <CopyBtn text={reveal} ckey="token" label="토큰 복사" />
          </div>

          {/* Claude Code */}
          <div className="pt-2 border-t border-blue-200">
            <div className="text-xs font-semibold text-gray-700 mb-1">Claude Code (터미널)</div>
            <div className="text-xs text-gray-500 mb-1">
              아래 명령을 터미널에 붙여 등록하세요. Claude Code 의 <b>네이티브 HTTP 트랜스포트</b>로
              <code className="font-mono"> /mcp</code> 엔드포인트에 직접 연결합니다(별도 도구 불필요).
              등록 확인은 <code className="font-mono">claude mcp list</code>.
            </div>
            <pre className="overflow-x-auto rounded bg-gray-900 text-gray-100 px-3 py-2 text-[11px] font-mono whitespace-pre">{claudeCodeCmd}</pre>
            <div className="mt-1"><CopyBtn text={claudeCodeCmd} ckey="code" label="명령 복사" /></div>
          </div>

          {/* Claude Desktop */}
          <div className="pt-2 border-t border-blue-200">
            <div className="text-xs font-semibold text-gray-700 mb-1">Claude Desktop (설정 파일)</div>
            <div className="text-xs text-gray-500 mb-1">
              설정 → 개발자 → 「설정 편집」으로 <code className="font-mono">claude_desktop_config.json</code> 을 열고,
              아래 항목을 <b><code className="font-mono">"mcpServers": {'{ }'}</code> 중괄호 안에</b> 붙여넣은 뒤 Claude Desktop 재시작.
              파일에 <code className="font-mono">mcpServers</code> 가 없으면 <code className="font-mono">{'{ "mcpServers": { 여기 } }'}</code> 로 감싸고,
              다른 항목이 있으면 사이에 쉼표를 넣으세요. <b>Node.js 필요.</b>
            </div>
            <pre className="overflow-x-auto rounded bg-gray-900 text-gray-100 px-3 py-2 text-[11px] font-mono whitespace-pre">{desktopCfg}</pre>
            <div className="mt-1 flex gap-2">
              <CopyBtn text={desktopCfg} ckey="desktop" label="항목 복사" />
              <button
                type="button"
                onClick={() => setReveal(null)}
                className="px-3 py-1 text-xs rounded text-gray-500 hover:text-gray-700"
              >
                확인했습니다(닫기)
              </button>
            </div>
          </div>
        </div>
      )}

      {/* 발급 폼 */}
      <form onSubmit={onCreate} className="flex flex-wrap items-end gap-3 mb-4 bg-white rounded-lg shadow-sm p-4">
        <div className="flex-1 min-w-[180px]">
          <label className="block text-xs text-gray-500 mb-1">토큰 이름</label>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="예: 내 노트북"
            maxLength={100}
            className="w-full h-9 rounded-md border border-gray-300 px-3 text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
          />
        </div>
        <div>
          <label className="block text-xs text-gray-500 mb-1">만료</label>
          <select
            value={expiresDays}
            onChange={(e) => setExpiresDays(Number(e.target.value))}
            className="h-9 rounded-md border border-gray-300 px-2 text-sm bg-white"
          >
            <option value={30}>30일</option>
            <option value={90}>90일</option>
            <option value={365}>1년</option>
          </select>
        </div>
        <button
          type="submit"
          disabled={creating || !name.trim()}
          className="h-9 px-4 rounded-md bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 disabled:opacity-50 inline-flex items-center gap-1"
        >
          <KeyRound className="w-4 h-4" /> {creating ? '발급 중...' : '토큰 발급'}
        </button>
      </form>

      {/* 목록 */}
      <div className="bg-white rounded-lg shadow-sm p-2">
        {loading ? (
          <p className="text-sm text-gray-500 p-3">불러오는 중...</p>
        ) : tokens.length === 0 ? (
          <p className="text-sm text-gray-500 p-3">발급된 토큰이 없습니다.</p>
        ) : (
          <ul className="divide-y">
            {tokens.map((t) => {
              const st = tokenStatus(t);
              return (
                <li key={t.id} className="flex items-center justify-between gap-2 px-3 py-2">
                  <div className="min-w-0 flex flex-col gap-0.5">
                    <span className="text-sm font-medium text-gray-800 truncate">{t.name}</span>
                    <span className="text-[10px] text-gray-400 font-mono">
                      {t.token_prefix}… · 생성 {fmtDate(t.created_at)} · 마지막 사용 {fmtDate(t.last_used_at)} · 만료 {fmtDate(t.expires_at)}
                    </span>
                  </div>
                  <div className="flex items-center gap-2 shrink-0">
                    <span className={`px-2 py-0.5 rounded text-xs ${st.cls}`}>{st.label}</span>
                    {!t.revoked_at && (
                      <button
                        type="button"
                        onClick={() => onDelete(t)}
                        title="삭제"
                        className="p-1.5 rounded text-gray-400 hover:text-red-600 hover:bg-red-50"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    )}
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
};

export default McpTokens;
