#!/usr/bin/env python3
"""VNC/GPU .sif 가 Google Drive 에 업로드된 뒤 메일 알림 (SmartTwin 메일러와 동일 설정 재사용).

SMTP/수신자 설정은 ~/.config/smartTwinMailer.env 를 그대로 씀
  (SMTP_HOST/PORT/USER/PASS, MAIL_TO).  → Preprocessor 와 동일한 수신자로 발송.
파일은 push-vnc-images.sh(rclone) 가 이미 Drive 에 올렸다고 가정 — 여기선 공유링크+메일만.

Usage:
    notify_vnc_build.py <remote_base> <file1.sif> [file2.sif ...]
      remote_base 예: ApptainerImages:SmartTwinCluster/apptainer-images/viz-node-images
"""
import hashlib
import os
import smtplib
import ssl
import subprocess
import sys
from datetime import datetime
from email.message import EmailMessage
from pathlib import Path


def load_env(path: Path) -> None:
    if not path.is_file():
        return
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())


def need(var: str) -> str:
    v = os.environ.get(var)
    if not v:
        sys.exit(f"ERROR: env {var} not set (~/.config/smartTwinMailer.env 확인)")
    return v


def human(n: int) -> str:
    f = float(n)
    for u in ("B", "KB", "MB", "GB", "TB"):
        if f < 1024:
            return f"{f:.1f} {u}"
        f /= 1024
    return f"{f:.1f} PB"


def md5sum(path: Path, chunk: int = 1 << 20) -> str:
    h = hashlib.md5()
    with path.open("rb") as fh:
        while True:
            b = fh.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def rclone_link(remote_file: str) -> str:
    try:
        r = subprocess.run(["rclone", "link", remote_file],
                           check=True, capture_output=True, text=True)
        return r.stdout.strip()
    except Exception as e:
        return f"(공유링크 생성 실패: {e})"


def main(argv):
    if len(argv) < 3:
        sys.exit(f"usage: {argv[0]} <remote_base> <file1.sif> [file2.sif ...]")

    load_env(Path.home() / ".config" / "smartTwinMailer.env")
    remote_base = argv[1].rstrip("/")
    files = [Path(p).resolve() for p in argv[2:]]
    for f in files:
        if not f.is_file():
            sys.exit(f"ERROR: missing file: {f}")

    lines = [
        "VNC/GPU Apptainer 이미지가 Google Drive 에 업로드되었습니다.",
        f"업로드 시각: {datetime.now():%Y-%m-%d %H:%M:%S}",
        f"호스트: {os.uname().nodename}",
        f"원격: {remote_base}/",
        "",
        "사내 수신: offline_packages_2404/pull-apptainers.sh 로 viz-node-images 수신 →",
        "          deploy_vnc_image_to_viz.sh 로 viz 노드 배포.",
        "",
    ]
    for f in files:
        link = rclone_link(f"{remote_base}/{f.name}")
        lines += [
            f"■ {f.name}",
            f"  size : {human(f.stat().st_size)}",
            f"  md5  : {md5sum(f)}",
            f"  link : {link}",
            "",
        ]
    body = "\n".join(lines)

    recipients = [a.strip() for a in need("MAIL_TO").replace(";", ",").split(",") if a.strip()]
    if not recipients:
        sys.exit("ERROR: MAIL_TO 수신자 없음")

    msg = EmailMessage()
    msg["Subject"] = f"[SmartTwinVNC] GPU VNC 이미지 업로드 완료 ({datetime.now():%Y-%m-%d %H:%M})"
    msg["From"] = need("SMTP_USER")
    msg["To"] = ", ".join(recipients)
    msg.set_content(body)

    ctx = ssl.create_default_context()
    with smtplib.SMTP(need("SMTP_HOST"), int(need("SMTP_PORT"))) as s:
        s.starttls(context=ctx)
        s.login(need("SMTP_USER"), need("SMTP_PASS"))
        s.send_message(msg, from_addr=os.environ["SMTP_USER"], to_addrs=recipients)
    print(f"[mail] sent to {recipients}")


if __name__ == "__main__":
    main(sys.argv)
