# 잡 결과 폴더에 귀환 매니페스트(output/return_manifest.json)를 원자적으로 쓰는 작성기 — 잡 스크립트에 셸 함수로 심긴다
"""귀환 매니페스트 — DynaForge 등이 "끝났나·무엇이 생겼나·없으면 왜" 를 한 파일로 보게 한다.

정본은 이 파일 하나. job_submit_api 가 템플릿 본문에 `write_return_manifest` 가 보이면 이 소스를
셸 함수(heredoc → python3 -)로 잡 스크립트에 심으므로 노드에 따로 배포할 것이 없다.
노드의 python3(22.04=3.10)에서 돌아야 하므로 표준 라이브러리만 쓴다.

파일이 생기는 것 자체가 끝남 신호다 — 임시 파일에 쓰고 os.replace 로 바꾼다(반쯤 쓴 파일을 끝남으로 오인하지 않게).
리포트 있음/없음은 rc 가 아니라 파일 유무로 판정한다(KooChainRun postprocess 는 실패해도 0 으로 끝날 수 있다).

종료 코드: 0 = 기대한 리포트가 모두 있음(또는 후처리 꺼짐), 3 = 기대한 리포트가 없음.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
from datetime import datetime

SCHEMA = 'smarttwin.return_manifest'
VERSION = 1
MANIFEST_REL = os.path.join('output', 'return_manifest.json')
EXIT_REPORT_MISSING = 3
LOG_TAIL_LINES = 20
_HEREDOC_END = '__RETURN_MANIFEST_PY__'
# 이미지 출처(images{}) — 노드 로컬 SIF 와 그 안의 판 글자. SIF 폴더는 시험용으로만 env 로 바꾼다.
SIF_DIR_ENV = 'SMARTTWIN_SIF_DIR'
DEFAULT_SIF_DIR = '/opt/apptainers'
PRE_VERSION_PATH = '/opt/SmartTwinPreprocessor/VERSION'          # pyKooCAE 가 빌드 때 넣는 전처리 판 글자(없으면 null)
POST_VERSION_PATH = '/opt/kood3plot/VERSION'                      # KooD3plotReader 커밋
REMAPPER_INFO_PATH = '/opt/kooremapper/bin/KooRemapper.BUILD_INFO.txt'
REPORT_IMAGES_SUFFIX = '_report.images.json'                     # 리포트 노드가 곁에 남기는 같은 꼴(선택)


def _sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def _tail(path, n=LOG_TAIL_LINES):
    try:
        with open(path, 'r', errors='replace') as f:
            return [line.rstrip('\n') for line in f.readlines()[-n:]]
    except OSError:
        return None


def _sacct_state(job_id):
    """리포트 잡의 (State, ExitCode, NodeList). sacct 가 없거나 실패하면 (None, None, None)."""
    sacct = shutil.which('sacct')
    if not job_id or not sacct:
        return None, None, None
    try:
        r = subprocess.run([sacct, '-j', str(job_id), '-X', '-n', '-P', '--format=State,ExitCode,NodeList'],
                           capture_output=True, text=True, timeout=30)
        line = r.stdout.strip().splitlines()[0] if r.stdout.strip() else ''
        if '|' in line:
            parts = [p.strip() for p in line.split('|')]
            return parts[0], parts[1], (parts[2] if len(parts) > 2 and parts[2] else None)
    except (OSError, subprocess.SubprocessError):
        pass
    return None, None, None


def _sif_cat(sif, inner_path):
    """SIF 안 파일 내용(apptainer exec cat). apptainer 가 없거나 실패하면 None."""
    app = shutil.which('apptainer')
    if not app:
        return None
    try:
        r = subprocess.run([app, 'exec', sif, 'cat', inner_path], capture_output=True, text=True,
                           timeout=120, stdin=subprocess.DEVNULL)
        return r.stdout if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def _first(text, pattern):
    m = re.search(pattern, text or '', re.M)
    return m.group(1) if m else None


def _sif_entry(path, reads):
    if not os.path.isfile(path):
        return {'path': path, 'present': False}
    entry = {'path': path, 'present': True, 'size': os.path.getsize(path), 'sha256': _sha256(path)}
    for key, (inner, pattern) in reads.items():
        entry[key] = _first(_sif_cat(path, inner), pattern)
    return entry


def _node_name():
    return socket.gethostname().split('.')[0]


def collect_images():
    """이 작성기가 도는 노드의 이미지 출처 — 노드 이름, Pre/Post SIF 의 크기·sha256 과 그 안의 판 글자.
    실패해도 매니페스트는 써야 하므로 예외를 error 칸으로 접는다."""
    try:
        d = os.environ.get(SIF_DIR_ENV, DEFAULT_SIF_DIR)
        return {
            'node': _node_name(),
            'pre': _sif_entry(os.path.join(d, 'SmartTwinPreprocessor.sif'), {
                'version': (PRE_VERSION_PATH, r'^Version:\s*(\S+)'),
                'kooremapper_commit': (REMAPPER_INFO_PATH, r'소스 커밋[^0-9a-f]*([0-9a-f]{7,40})'),
            }),
            'post': _sif_entry(os.path.join(d, 'SmartTwinPostprocessor.sif'), {
                'version': (POST_VERSION_PATH, r'^Version:\s*(\S+)'),
            }),
        }
    except Exception as e:  # noqa: BLE001 — 출처 수집이 매니페스트를 막지 않게
        return {'node': _node_name(), 'error': f'{type(e).__name__}: {e}'}


def _report_images(out_dir, kinds):
    """리포트 노드가 곁에 남긴 <kind>_report.images.json(collect_images 와 같은 꼴, 선택). 없으면 None."""
    found = {}
    for kind in kinds:
        path = os.path.join(out_dir, f'{kind}{REPORT_IMAGES_SUFFIX}')
        try:
            if os.path.isfile(path) and os.path.getsize(path) <= 65536:
                with open(path, encoding='utf-8') as f:
                    data = json.load(f)
                if isinstance(data, dict):
                    found[kind] = data
        except (OSError, ValueError):
            continue
    return found or None


def output_dir(result_dir):
    """종합 리포트가 생기는 폴더 — KooChainRun 과 같은 규칙: project.output_dir → 최상위 output_dir(DWI, 예 dwi_output)
    → <base_dir>/output(base_dir 기본은 runner_config 가 있는 결과 폴더). 상대 경로는 결과 폴더 기준(드라이버·후처리 잡의 cwd)."""
    try:
        with open(os.path.join(result_dir, 'runner_config.json'), encoding='utf-8') as f:
            rc = json.load(f)
    except (OSError, ValueError):
        return os.path.join(result_dir, 'output')
    out = ((rc.get('project') or {}).get('output_dir') or rc.get('output_dir')
           or os.path.join(rc.get('base_dir') or result_dir, 'output'))
    return os.path.normpath(os.path.join(result_dir, out))


def _rel(path, result_dir):
    """결과 폴더 기준 경로(파일 REST 의 path 로 바로 쓰게). 결과 폴더 밖이면 절대경로."""
    rel = os.path.relpath(path, result_dir)
    return path if rel == os.pardir or rel.startswith(os.pardir + os.sep) else rel


def _log_names(kind, by):
    """이번에 리포트를 돌린 쪽이 쓴 로그만 — 리포트 잡은 <kind>_report.slurm.{err,out}, 드라이버·후처리 잡의
    KooChainRun postprocess 는 <kind>_report.log. 다른 쪽 파일은 지난 실행의 것일 수 있다(실 Slurm 검증에서 7월 err 가 섞였다)."""
    if by == 'report_job':
        return (f'{kind}_report.slurm.err', f'{kind}_report.slurm.out')
    if by in ('driver', 'postprocess_job'):
        return (f'{kind}_report.log',)
    return ()


def _ontology(result_dir, out_dir, kind):
    """리포트 곁의 해석 온톨로지 꾸러미(짝 HTML 과 같은 폴더·같은 줄기). ok·종료 코드에는 들지 않는다 —
    리포트가 정본이고 꾸러미는 덧붙이는 산출물(DynaForge 요청 10-31). 없으면 present:false, 까닭은 없다."""
    path = os.path.join(out_dir, f'{kind}_report.ontology.json')
    present = os.path.isfile(path)
    return {'path': _rel(path, result_dir), 'present': present,
            'size': os.path.getsize(path) if present else None,
            'sha256': _sha256(path) if present else None}


def _report_entry(result_dir, out_dir, kind, missing_reason, by):
    path = os.path.join(out_dir, f'{kind}_report.html')
    entry = {'kind': kind, 'path': _rel(path, result_dir), 'present': os.path.isfile(path),
             'size': None, 'sha256': None, 'reason': None, 'log_tail': None,
             'ontology': _ontology(result_dir, out_dir, kind)}
    if entry['present']:
        entry['size'] = os.path.getsize(path)
        entry['sha256'] = _sha256(path)
        return entry
    entry['reason'] = missing_reason
    tails = {}
    for name in _log_names(kind, by):
        log = os.path.join(out_dir, name)
        t = _tail(log)
        if t:
            tails[_rel(log, result_dir)] = t
    entry['log_tail'] = tails or None
    return entry


def _missing_reason(a, report_job):
    if a.stage == 'early_exit':
        return f'드라이버가 리포트 단계 전에 끝남(driver rc={a.driver_rc})'
    if a.postprocess == 'disabled':
        return '후처리 꺼짐(CHAIN_POSTPROCESS=false) — 리포트를 만들지 않았다'
    if a.postprocess == 'report_job':
        st = report_job.get('state')
        if st and not st.startswith('COMPLETED'):
            return f"리포트 잡 {report_job.get('id')} 가 {st}({report_job.get('exit_code')}) 로 끝남 — HTML 없음"
        return f"리포트 잡 {report_job.get('id')} 은 끝났으나 HTML 없음"
    return f'{a.postprocess} 의 postprocess(rc={a.pp_rc}) 뒤에도 HTML 없음'


def build(a):
    report_job = None
    report_node = None
    if a.report_job_id:
        state, exit_code, report_node = _sacct_state(a.report_job_id)
        report_job = {'id': str(a.report_job_id), 'state': state, 'exit_code': exit_code}
    elif a.stage == 'complete' and a.postprocess in ('driver', 'postprocess_job'):
        report_node = _node_name()   # 리포트를 이 잡이 이 노드에서 직접 만들었다
    reason = _missing_reason(a, report_job or {})
    out_dir = output_dir(a.result_dir)
    reports = [_report_entry(a.result_dir, out_dir, kind, reason, a.postprocess) for kind in a.expect]
    expected = a.postprocess != 'disabled'   # 이른 종료도 리포트를 기대했던 잡이라 없음 = ok 아님
    return {
        'schema': SCHEMA,
        'version': VERSION,
        'written_at': datetime.now().astimezone().isoformat(timespec='seconds'),
        'stage': a.stage,
        'driver_rc': a.driver_rc,
        'job': {'slurm_job_id': str(a.job_id) if a.job_id else None, 'job_name': a.job_name,
                'web_user': a.web_user, 'sim_type': a.sim_type, 'result_dir': a.result_dir,
                'output_dir': _rel(out_dir, a.result_dir)},
        'postprocess': {'by': a.postprocess, 'rc': a.pp_rc, 'report_job': report_job,
                        'postprocess_job_id': a.postprocess_job_id or None},
        'reports': reports,
        'images': {'manifest_node': collect_images(), 'report_node': report_node,
                   'report_images': _report_images(out_dir, a.expect)},
        'ok': (not expected) or all(r['present'] for r in reports),
    }


def write(result_dir, manifest):
    """같은 디렉터리의 임시 파일에 쓰고 os.replace — 읽는 쪽은 온전한 파일만 본다."""
    path = os.path.join(result_dir, MANIFEST_REL)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f'{path}.tmp.{os.getpid()}'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    return path


def _int_or_none(v):
    return int(v) if str(v).strip().lstrip('-').isdigit() else None


def parse_args(argv):
    env = os.environ
    p = argparse.ArgumentParser(prog='write_return_manifest')
    p.add_argument('--result-dir', default=env.get('RESULT_DIR'))
    p.add_argument('--job-id', default=env.get('SLURM_JOB_ID'))
    p.add_argument('--job-name', default=env.get('SLURM_JOB_NAME'))
    p.add_argument('--web-user', default=env.get('WEB_USER'))
    p.add_argument('--sim-type', required=True)
    p.add_argument('--expect', action='append', choices=['sphere', 'impact'], required=True,
                   help='기대하는 종합 리포트(여러 번 줄 수 있다)')
    p.add_argument('--stage', choices=['complete', 'early_exit'], default='complete')
    p.add_argument('--driver-rc', type=_int_or_none, default=None)
    p.add_argument('--postprocess', choices=['report_job', 'driver', 'postprocess_job', 'disabled'],
                   default='report_job', help='종합 리포트를 누가 만들었나')
    p.add_argument('--pp-rc', type=_int_or_none, default=None)
    p.add_argument('--report-job-id', default='')
    p.add_argument('--postprocess-job-id', default='')
    a = p.parse_args(argv)
    if not a.result_dir:
        p.error('--result-dir(또는 RESULT_DIR) 가 필요하다')
    return a


def main(argv=None):
    a = parse_args(sys.argv[1:] if argv is None else argv)
    manifest = build(a)
    path = write(a.result_dir, manifest)
    missing = [r['kind'] for r in manifest['reports'] if not r['present']]
    print(f"[return_manifest] {path} ok={manifest['ok']}" + (f" missing={','.join(missing)}" if missing else ''))
    return 0 if manifest['ok'] else EXIT_REPORT_MISSING


def shell_function():
    """잡 스크립트에 심을 bash 함수 `write_return_manifest` — 이 파일 소스를 python3 - 로 돌린다."""
    with open(os.path.abspath(__file__), encoding='utf-8') as f:
        src = f.read()
    return ("# --- 귀환 매니페스트 작성기 (backend_5010/return_manifest.py 를 백엔드가 심음) ---\n"
            "write_return_manifest() {\n"
            f"python3 - \"$@\" <<'{_HEREDOC_END}'\n"
            f"{src.rstrip()}\n"
            f"{_HEREDOC_END}\n"
            "}\n\n")


if __name__ == '__main__':
    sys.exit(main())
