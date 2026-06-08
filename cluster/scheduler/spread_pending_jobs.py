#!/usr/bin/env python3
"""현재 PENDING 잡들을 지정한 파티션들로 분산.

파티션 이름을 콤마(,)로 여러 개 지정하면, 현재 PENDING 인 모든 잡의 Partition 을
그 목록으로 바꾼다(scontrol update). Slurm(backfill) 이 그 중 가장 먼저 시작
가능한 파티션에서 잡을 띄우므로 비어있는 파티션이 자동 활용된다 → 편중 해소.

사용:
  spread_pending_jobs.py alpha,beta,gamma,share
  spread_pending_jobs.py alpha,beta,gamma,share --dry-run

권한: 헤드/컨트롤러에서 Slurm operator/root 로 실행(모든 사용자 잡 적용).
"""
import argparse
import subprocess
import sys


def main():
    ap = argparse.ArgumentParser(description="펜딩 잡을 지정 파티션들로 분산")
    ap.add_argument("partitions", help="분산할 파티션 (콤마구분, 예: alpha,beta,gamma,share)")
    ap.add_argument("--dry-run", action="store_true", help="변경 미적용, 출력만")
    args = ap.parse_args()

    plist = ",".join(p.strip() for p in args.partitions.split(",") if p.strip())
    if not plist:
        sys.exit("파티션을 지정하세요 (예: alpha,beta,gamma,share)")

    # 현재 PENDING 잡 (jobid | 현재 partition)
    r = subprocess.run(["squeue", "-h", "-t", "PD", "-o", "%i|%P"],
                       capture_output=True, text=True)
    jobs = [ln.split("|", 1) for ln in r.stdout.splitlines() if "|" in ln]
    if not jobs:
        print("펜딩 잡 없음")
        return

    done = 0
    for jid, cur in jobs:
        jid = jid.strip()
        if not jid:
            continue
        if args.dry_run:
            print(f"[DRY] job {jid}: {cur.strip()} -> {plist}")
            done += 1
            continue
        rr = subprocess.run(["scontrol", "update", f"jobid={jid}", f"Partition={plist}"],
                            capture_output=True, text=True)
        if rr.returncode == 0:
            print(f"job {jid} -> Partition={plist}")
            done += 1
        else:
            print(f"job {jid} 실패: {rr.stderr.strip()[:160]}")

    print(f"{'적용예정' if args.dry_run else '적용'} {done} / 펜딩 {len(jobs)}")


if __name__ == "__main__":
    main()
