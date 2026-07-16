#!/usr/bin/env python3
# DOE 크기 + sinfo 로 KooChainRun 병렬도(nodes/jobs_per_node/ncpu)를 auto-tune 해
# "PARTITION NODES JOBS_PER_NODE NCPU" 한 줄로 출력. 템플릿 드라이버가 CHAIN_* 고정 대신 사용.
# 실패(sinfo 없음/미적용) 시 비제로 종료 → 호출자가 CHAIN_* 기본값으로 폴백.
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import auto_tune
except Exception:  # noqa: BLE001
    sys.exit(1)


def main() -> int:
    ap = argparse.ArgumentParser(description="KooChainRun 병렬도 auto-tune (sinfo 기반).")
    ap.add_argument("--doe", type=int, default=0, help="DOE 케이스 수(각도/위치).")
    ap.add_argument("--partition", default=None, help="파티션 고정(없으면 sinfo 로 자동 선택).")
    ap.add_argument("--ncpu", type=int, default=None, help="잡당 ncpu 힌트.")
    a = ap.parse_args()

    doe = a.doe if a.doe and a.doe > 0 else 1
    r = auto_tune.auto_tune_submit(num_angles=doe, user_partition=a.partition, user_ncpu=a.ncpu)
    if not r.get("applied"):
        sys.stderr.write((r.get("reason") or "auto-tune not applied") + "\n")
        return 2
    part = r.get("partition") or ""
    nodes = int(r.get("nodes") or 1)
    jpn = int(r.get("jobs_per_node") or 1)
    ncpu = int(r.get("ncpu_per_job") or (a.ncpu or 1))
    print(f"{part} {nodes} {jpn} {ncpu}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
