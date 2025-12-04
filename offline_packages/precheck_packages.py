#!/usr/bin/env python3
"""
오프라인 패키지 설치 전 점검 도구

기능:
  1. 시스템에 이미 설치된 패키지 검사
  2. 오프라인 패키지 디렉토리의 .deb 파일 분석
  3. 의존성 충돌 감지
  4. 설치해야 할 패키지 / 건너뛸 패키지 리스트 생성
  5. 문제가 있는 패키지에 대한 액션 아이템 생성

사용법:
  python3 precheck_packages.py --deb-dir /path/to/deb/files [옵션]

옵션:
  --deb-dir PATH          .deb 파일이 있는 디렉토리
  --requirements PATH     Python requirements.txt 파일들 (여러 개 가능)
  --output-report PATH    리포트 출력 파일 (기본: precheck_report.txt)
  --skip-installed        이미 설치된 패키지는 무조건 건너뛰기
  --critical-only         Critical 문제만 보고
  --json                  JSON 형식으로 출력

작성자: Claude Code
날짜: 2025-12-04
"""

import sys
import os
import subprocess
import re
import json
import argparse
from collections import defaultdict
from typing import Dict, List, Set, Tuple, Optional
from pathlib import Path
from dataclasses import dataclass, asdict


@dataclass
class PackageInfo:
    """패키지 정보"""
    name: str
    version: str
    arch: str = ""
    source: str = ""  # 'deb', 'python', 'system'
    depends: List[str] = None

    def __post_init__(self):
        if self.depends is None:
            self.depends = []


@dataclass
class ConflictIssue:
    """충돌 이슈"""
    package_name: str
    installed_version: str
    new_version: str
    severity: str  # 'critical', 'warning', 'info'
    reason: str
    action: str  # 사용자가 취해야 할 액션


class PackageAnalyzer:
    """패키지 분석기"""

    def __init__(self, skip_installed: bool = True):
        self.skip_installed = skip_installed
        self.installed_apt_packages: Dict[str, str] = {}
        self.installed_python_packages: Dict[str, str] = {}
        self.deb_packages: Dict[str, PackageInfo] = {}
        self.python_requirements: Dict[str, str] = {}
        self.conflicts: List[ConflictIssue] = []

        # Critical 시스템 패키지 (절대 건드리면 안됨)
        self.critical_system_packages = {
            'systemd', 'init', 'libc6', 'libc-bin',
            'base-files', 'base-passwd', 'dpkg', 'apt',
            'coreutils', 'bash', 'dash', 'util-linux',
            'libsystemd0', 'udev', 'mount', 'login'
        }

        # 위험한 패키지 (주의 필요)
        self.risky_packages = {
            'python3', 'python3-minimal', 'python3-pkg-resources',
            'openssh-server', 'openssh-client',
            'kernel', 'linux-', 'grub'
        }

    def load_installed_apt_packages(self):
        """시스템에 설치된 APT 패키지 로드"""
        print("🔍 Loading installed APT packages...")

        try:
            result = subprocess.run(
                ['dpkg-query', '-W', '-f=${Package}\t${Version}\t${Status}\n'],
                capture_output=True, text=True, check=True
            )

            for line in result.stdout.strip().split('\n'):
                if not line:
                    continue

                parts = line.split('\t')
                if len(parts) >= 3:
                    package_name = parts[0]
                    version = parts[1]
                    status = parts[2]

                    # 'install ok installed' 상태만 추출
                    if 'install ok installed' in status:
                        self.installed_apt_packages[package_name] = version

            print(f"   ✅ Found {len(self.installed_apt_packages)} installed APT packages")

        except subprocess.CalledProcessError as e:
            print(f"   ⚠️  Warning: Failed to load APT packages: {e}")

    def load_installed_python_packages(self):
        """시스템에 설치된 Python 패키지 로드"""
        print("🔍 Loading installed Python packages...")

        try:
            result = subprocess.run(
                ['pip3', 'list', '--format=freeze'],
                capture_output=True, text=True, check=True
            )

            for line in result.stdout.strip().split('\n'):
                if '==' in line:
                    name, version = line.split('==', 1)
                    self.installed_python_packages[name.lower()] = version

            print(f"   ✅ Found {len(self.installed_python_packages)} installed Python packages")

        except subprocess.CalledProcessError as e:
            print(f"   ⚠️  Warning: Failed to load Python packages: {e}")

    def analyze_deb_file(self, deb_path: str) -> Optional[PackageInfo]:
        """deb 파일 분석"""
        try:
            # 패키지 정보 추출
            result = subprocess.run(
                ['dpkg-deb', '-f', deb_path],
                capture_output=True, text=True, check=True
            )

            info = {}
            for line in result.stdout.split('\n'):
                if ':' in line:
                    key, value = line.split(':', 1)
                    info[key.strip()] = value.strip()

            package_name = info.get('Package', '')
            version = info.get('Version', '')
            arch = info.get('Architecture', 'amd64')
            depends_str = info.get('Depends', '')

            # 의존성 파싱
            depends = []
            if depends_str:
                for dep in depends_str.split(','):
                    dep = dep.strip().split()[0]  # 버전 정보 제거
                    depends.append(dep)

            return PackageInfo(
                name=package_name,
                version=version,
                arch=arch,
                source='deb',
                depends=depends
            )

        except Exception as e:
            print(f"   ⚠️  Failed to analyze {os.path.basename(deb_path)}: {e}")
            return None

    def load_deb_directory(self, deb_dir: str):
        """deb 디렉토리의 모든 패키지 로드"""
        print(f"🔍 Analyzing .deb files in {deb_dir}...")

        deb_files = list(Path(deb_dir).glob('*.deb'))
        print(f"   Found {len(deb_files)} .deb files")

        for deb_file in deb_files:
            pkg_info = self.analyze_deb_file(str(deb_file))
            if pkg_info:
                self.deb_packages[pkg_info.name] = pkg_info

        print(f"   ✅ Successfully analyzed {len(self.deb_packages)} packages")

    def load_requirements_file(self, req_file: str):
        """Python requirements.txt 파일 로드"""
        print(f"🔍 Loading Python requirements from {req_file}...")

        try:
            with open(req_file, 'r') as f:
                for line in f:
                    line = line.strip()

                    # 주석과 빈 줄 건너뛰기
                    if not line or line.startswith('#'):
                        continue

                    # 패키지 이름과 버전 파싱
                    if '==' in line:
                        name, version = line.split('==', 1)
                        self.python_requirements[name.lower().strip()] = version.strip()
                    elif '>=' in line:
                        name = line.split('>=')[0].strip()
                        version = line.split('>=')[1].strip()
                        self.python_requirements[name.lower()] = f">={version}"

            print(f"   ✅ Loaded {len(self.python_requirements)} Python requirements")

        except Exception as e:
            print(f"   ⚠️  Warning: Failed to load {req_file}: {e}")

    def check_apt_conflicts(self):
        """APT 패키지 충돌 검사"""
        print("\n🔎 Checking APT package conflicts...")

        for pkg_name, pkg_info in self.deb_packages.items():
            installed_version = self.installed_apt_packages.get(pkg_name)

            if not installed_version:
                # 설치되지 않음 - OK
                continue

            # Critical 시스템 패키지 체크
            if pkg_name in self.critical_system_packages:
                self.conflicts.append(ConflictIssue(
                    package_name=pkg_name,
                    installed_version=installed_version,
                    new_version=pkg_info.version,
                    severity='critical',
                    reason='Critical system package - NEVER update',
                    action=f'SKIP: Remove {pkg_name}_{pkg_info.version}_*.deb from offline package directory'
                ))
                continue

            # Risky 패키지 체크
            is_risky = any(risky in pkg_name for risky in self.risky_packages)
            if is_risky:
                self.conflicts.append(ConflictIssue(
                    package_name=pkg_name,
                    installed_version=installed_version,
                    new_version=pkg_info.version,
                    severity='warning',
                    reason='Risky package - review carefully',
                    action=f'REVIEW: Consider skipping {pkg_name} or test in staging environment first'
                ))
                continue

            # 일반 패키지 - 이미 설치되어 있음
            if self.skip_installed:
                self.conflicts.append(ConflictIssue(
                    package_name=pkg_name,
                    installed_version=installed_version,
                    new_version=pkg_info.version,
                    severity='info',
                    reason='Already installed (skip mode enabled)',
                    action=f'SKIP: Package will be skipped during installation'
                ))

        critical_count = sum(1 for c in self.conflicts if c.severity == 'critical')
        warning_count = sum(1 for c in self.conflicts if c.severity == 'warning')
        info_count = sum(1 for c in self.conflicts if c.severity == 'info')

        print(f"   Found: {critical_count} critical, {warning_count} warnings, {info_count} info")

    def check_python_conflicts(self):
        """Python 패키지 충돌 검사"""
        print("\n🔎 Checking Python package conflicts...")

        for pkg_name, req_version in self.python_requirements.items():
            installed_version = self.installed_python_packages.get(pkg_name)

            if not installed_version:
                # 설치되지 않음 - OK
                continue

            # 시스템 Python 패키지는 주의
            if pkg_name in ['pip', 'setuptools', 'wheel', 'distutils']:
                self.conflicts.append(ConflictIssue(
                    package_name=pkg_name,
                    installed_version=installed_version,
                    new_version=req_version,
                    severity='warning',
                    reason='Core Python package',
                    action=f'REVIEW: Consider using virtual environment for {pkg_name}'
                ))
                continue

            # 일반 패키지 - 이미 설치되어 있음
            if self.skip_installed:
                self.conflicts.append(ConflictIssue(
                    package_name=f"python:{pkg_name}",
                    installed_version=installed_version,
                    new_version=req_version,
                    severity='info',
                    reason='Already installed (skip mode enabled)',
                    action=f'SKIP: Package will be skipped during pip install'
                ))

    def generate_skip_lists(self) -> Tuple[List[str], List[str]]:
        """건너뛸 패키지 리스트 생성"""
        apt_skip_list = []
        python_skip_list = []

        for conflict in self.conflicts:
            if conflict.action.startswith('SKIP'):
                if conflict.package_name.startswith('python:'):
                    python_skip_list.append(conflict.package_name.replace('python:', ''))
                else:
                    apt_skip_list.append(conflict.package_name)

        return apt_skip_list, python_skip_list

    def generate_report(self, output_file: str, critical_only: bool = False):
        """리포트 생성"""
        print(f"\n📝 Generating report to {output_file}...")

        with open(output_file, 'w', encoding='utf-8') as f:
            f.write("=" * 80 + "\n")
            f.write("   오프라인 패키지 설치 전 점검 리포트\n")
            f.write("=" * 80 + "\n\n")

            f.write(f"검사 일시: {subprocess.check_output(['date']).decode().strip()}\n")
            f.write(f"호스트명: {subprocess.check_output(['hostname']).decode().strip()}\n")
            f.write(f"Skip 모드: {'활성화' if self.skip_installed else '비활성화'}\n\n")

            # 통계
            f.write("=" * 80 + "\n")
            f.write("📊 통계\n")
            f.write("=" * 80 + "\n")
            f.write(f"시스템에 설치된 APT 패키지: {len(self.installed_apt_packages)}\n")
            f.write(f"시스템에 설치된 Python 패키지: {len(self.installed_python_packages)}\n")
            f.write(f"오프라인 .deb 패키지: {len(self.deb_packages)}\n")
            f.write(f"Python requirements: {len(self.python_requirements)}\n\n")

            # 충돌 이슈
            critical_issues = [c for c in self.conflicts if c.severity == 'critical']
            warning_issues = [c for c in self.conflicts if c.severity == 'warning']
            info_issues = [c for c in self.conflicts if c.severity == 'info']

            f.write("=" * 80 + "\n")
            f.write("⚠️  발견된 이슈\n")
            f.write("=" * 80 + "\n")
            f.write(f"🔴 Critical: {len(critical_issues)}\n")
            f.write(f"🟡 Warning: {len(warning_issues)}\n")
            f.write(f"🔵 Info: {len(info_issues)}\n\n")

            # Critical 이슈 상세
            if critical_issues:
                f.write("=" * 80 + "\n")
                f.write("🔴 CRITICAL 이슈 (즉시 조치 필요)\n")
                f.write("=" * 80 + "\n\n")

                for i, issue in enumerate(critical_issues, 1):
                    f.write(f"[{i}] {issue.package_name}\n")
                    f.write(f"    설치된 버전: {issue.installed_version}\n")
                    f.write(f"    새 버전: {issue.new_version}\n")
                    f.write(f"    이유: {issue.reason}\n")
                    f.write(f"    조치: {issue.action}\n\n")

            # Warning 이슈 상세
            if not critical_only and warning_issues:
                f.write("=" * 80 + "\n")
                f.write("🟡 WARNING 이슈 (검토 권장)\n")
                f.write("=" * 80 + "\n\n")

                for i, issue in enumerate(warning_issues, 1):
                    f.write(f"[{i}] {issue.package_name}\n")
                    f.write(f"    설치된 버전: {issue.installed_version}\n")
                    f.write(f"    새 버전: {issue.new_version}\n")
                    f.write(f"    이유: {issue.reason}\n")
                    f.write(f"    조치: {issue.action}\n\n")

            # Info 이슈 (skip 리스트)
            if not critical_only and info_issues:
                f.write("=" * 80 + "\n")
                f.write("🔵 INFO (건너뛸 패키지 목록)\n")
                f.write("=" * 80 + "\n\n")

                apt_skip = [i for i in info_issues if not i.package_name.startswith('python:')]
                python_skip = [i for i in info_issues if i.package_name.startswith('python:')]

                if apt_skip:
                    f.write(f"APT 패키지 ({len(apt_skip)}개):\n")
                    for issue in apt_skip[:20]:  # 처음 20개만
                        f.write(f"  - {issue.package_name} ({issue.installed_version})\n")
                    if len(apt_skip) > 20:
                        f.write(f"  ... 외 {len(apt_skip) - 20}개\n")
                    f.write("\n")

                if python_skip:
                    f.write(f"Python 패키지 ({len(python_skip)}개):\n")
                    for issue in python_skip[:20]:  # 처음 20개만
                        f.write(f"  - {issue.package_name} ({issue.installed_version})\n")
                    if len(python_skip) > 20:
                        f.write(f"  ... 외 {len(python_skip) - 20}개\n")
                    f.write("\n")

            # 액션 아이템
            f.write("=" * 80 + "\n")
            f.write("✅ 다음 단계\n")
            f.write("=" * 80 + "\n\n")

            if critical_issues:
                f.write("🔴 CRITICAL 이슈 해결이 필요합니다:\n\n")
                f.write("1. 다음 패키지들을 오프라인 패키지 디렉토리에서 제거하세요:\n\n")
                for issue in critical_issues:
                    f.write(f"   rm -f apt_packages/{issue.package_name}_*.deb\n")
                f.write("\n")
                f.write("2. 제거 후 이 스크립트를 다시 실행하세요.\n")
                f.write("3. CRITICAL 이슈가 없으면 설치를 진행할 수 있습니다.\n\n")
            else:
                f.write("✅ CRITICAL 이슈가 없습니다. 설치를 진행할 수 있습니다.\n\n")

                if warning_issues:
                    f.write("⚠️  WARNING 이슈가 있습니다. 검토 후 진행하세요.\n\n")

                f.write("설치 명령어:\n\n")
                f.write("   # 전체 설치 (skip 모드)\n")
                f.write("   sudo ./setup_cluster_full_multihead_offline.sh --skip-installed\n\n")

            # Skip 리스트 파일 생성 안내
            if info_issues:
                f.write("=" * 80 + "\n")
                f.write("📋 생성된 파일\n")
                f.write("=" * 80 + "\n\n")
                f.write("  - apt_skip_list.txt     : 건너뛸 APT 패키지 목록\n")
                f.write("  - python_skip_list.txt  : 건너뛸 Python 패키지 목록\n\n")

            f.write("=" * 80 + "\n")
            f.write("리포트 끝\n")
            f.write("=" * 80 + "\n")

        print(f"   ✅ Report generated: {output_file}")

    def save_skip_lists(self, output_dir: str):
        """건너뛸 패키지 리스트를 파일로 저장"""
        apt_skip, python_skip = self.generate_skip_lists()

        # APT skip list
        apt_file = os.path.join(output_dir, 'apt_skip_list.txt')
        with open(apt_file, 'w') as f:
            f.write("# APT packages to skip during installation\n")
            f.write("# One package name per line\n")
            f.write("# Generated by precheck_packages.py\n\n")
            for pkg in sorted(apt_skip):
                f.write(f"{pkg}\n")

        print(f"   ✅ APT skip list saved: {apt_file} ({len(apt_skip)} packages)")

        # Python skip list
        python_file = os.path.join(output_dir, 'python_skip_list.txt')
        with open(python_file, 'w') as f:
            f.write("# Python packages to skip during installation\n")
            f.write("# One package name per line\n")
            f.write("# Generated by precheck_packages.py\n\n")
            for pkg in sorted(python_skip):
                f.write(f"{pkg}\n")

        print(f"   ✅ Python skip list saved: {python_file} ({len(python_skip)} packages)")

    def has_critical_issues(self) -> bool:
        """Critical 이슈가 있는지 확인"""
        return any(c.severity == 'critical' for c in self.conflicts)


def main():
    parser = argparse.ArgumentParser(
        description='오프라인 패키지 설치 전 점검 도구',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
예제:
  # APT 패키지만 점검
  python3 precheck_packages.py --deb-dir offline_packages/apt_packages

  # Python 패키지 포함 점검
  python3 precheck_packages.py --deb-dir offline_packages/apt_packages \\
      --requirements dashboard/backend_5010/requirements.txt \\
      --requirements dashboard/kooCAEWebServer_5000/requirements.txt

  # Critical 이슈만 보기
  python3 precheck_packages.py --deb-dir offline_packages/apt_packages --critical-only
        """
    )

    parser.add_argument('--deb-dir', required=True,
                        help='.deb 파일이 있는 디렉토리')
    parser.add_argument('--requirements', action='append',
                        help='Python requirements.txt 파일 (여러 개 가능)')
    parser.add_argument('--output-report', default='precheck_report.txt',
                        help='리포트 출력 파일 (기본: precheck_report.txt)')
    parser.add_argument('--skip-installed', action='store_true', default=True,
                        help='이미 설치된 패키지 건너뛰기 (기본: 활성화)')
    parser.add_argument('--critical-only', action='store_true',
                        help='Critical 이슈만 보고')
    parser.add_argument('--json', action='store_true',
                        help='JSON 형식으로 출력')

    args = parser.parse_args()

    # 배너
    print("\n" + "=" * 80)
    print("   오프라인 패키지 설치 전 점검 도구")
    print("=" * 80 + "\n")

    # Analyzer 생성
    analyzer = PackageAnalyzer(skip_installed=args.skip_installed)

    # 시스템 패키지 로드
    analyzer.load_installed_apt_packages()
    analyzer.load_installed_python_packages()

    # 오프라인 패키지 분석
    if not os.path.isdir(args.deb_dir):
        print(f"❌ Error: Directory not found: {args.deb_dir}")
        sys.exit(1)

    analyzer.load_deb_directory(args.deb_dir)

    # Python requirements 로드
    if args.requirements:
        for req_file in args.requirements:
            if os.path.isfile(req_file):
                analyzer.load_requirements_file(req_file)
            else:
                print(f"⚠️  Warning: Requirements file not found: {req_file}")

    # 충돌 검사
    analyzer.check_apt_conflicts()
    if args.requirements:
        analyzer.check_python_conflicts()

    # Skip 리스트 저장
    output_dir = os.path.dirname(args.output_report) or '.'
    analyzer.save_skip_lists(output_dir)

    # 리포트 생성
    analyzer.generate_report(args.output_report, critical_only=args.critical_only)

    # 결과 요약
    print("\n" + "=" * 80)
    print("📊 점검 완료")
    print("=" * 80)

    has_critical = analyzer.has_critical_issues()

    if has_critical:
        print("\n❌ CRITICAL 이슈가 발견되었습니다!")
        print(f"   리포트를 확인하세요: {args.output_report}")
        print("\n   조치 후 다시 점검하세요:")
        print(f"   python3 {sys.argv[0]} --deb-dir {args.deb_dir}")
        sys.exit(1)
    else:
        print("\n✅ CRITICAL 이슈 없음 - 설치 진행 가능")
        print(f"   리포트: {args.output_report}")
        print("\n   다음 명령으로 설치하세요:")
        print("   sudo ./setup_cluster_full_multihead_offline.sh --skip-installed")
        sys.exit(0)


if __name__ == '__main__':
    main()
