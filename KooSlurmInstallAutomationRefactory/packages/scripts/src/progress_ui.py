#!/usr/bin/env python3
"""
진행 상황 UI 모듈
Phase 2-3: Progress UI with Rich Library

개선사항:
- Rich 라이브러리로 예쁜 진행 표시
- 실시간 상태 업데이트
- 컬러풀한 로그 출력
- 프로그레스 바
"""

from typing import Optional, List, Dict, Any
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn, TimeRemainingColumn
from rich.table import Table
from rich.panel import Panel
from rich import box
import time


class InstallationProgressUI:
    """설치 진행 상황 UI 클래스"""
    
    def __init__(self):
        self.console = Console()
        self.current_task = None
        self.tasks_completed = 0
        self.total_tasks = 0
        
    def print_banner(self):
        """시작 배너 출력"""
        banner = """
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║   🚀 KooSlurmInstallAutomation v1.2.0                       ║
║      자동화된 Slurm 클러스터 설치 도구                        ║
║                                                              ║
║   Phase 2 개선사항:                                          ║
║   ✅ Pre-flight Check 강화                                   ║
║   ✅ DB 포함 완전 롤백                                        ║
║   ✅ 진행 상황 UI 개선                                        ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
        """
        self.console.print(banner, style="bold cyan")
    
    def print_section(self, title: str, icon: str = "📋"):
        """섹션 제목 출력"""
        self.console.print(f"\n{icon} [bold yellow]{title}[/bold yellow]")
        self.console.print("─" * 60)
    
    def print_success(self, message: str):
        """성공 메시지"""
        self.console.print(f"✅ [green]{message}[/green]")
    
    def print_error(self, message: str):
        """오류 메시지"""
        self.console.print(f"❌ [red]{message}[/red]")
    
    def print_warning(self, message: str):
        """경고 메시지"""
        self.console.print(f"⚠️  [yellow]{message}[/yellow]")
    
    def print_info(self, message: str):
        """정보 메시지"""
        self.console.print(f"ℹ️  [cyan]{message}[/cyan]")
    
    def create_progress_bar(self, description: str = "Processing"):
        """프로그레스 바 생성"""
        return Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TaskProgressColumn(),
            TimeRemainingColumn(),
            console=self.console
        )
    
    def show_installation_summary(self, results: Dict[str, Any]):
        """설치 결과 요약 표시"""
        table = Table(title="설치 결과 요약", box=box.ROUNDED)
        
        table.add_column("노드", style="cyan", no_wrap=True)
        table.add_column("상태", style="magenta")
        table.add_column("설치 시간", justify="right", style="green")
        table.add_column("비고", style="yellow")
        
        for node, result in results.items():
            status = "✅ 성공" if result['success'] else "❌ 실패"
            install_time = f"{result.get('time', 0):.1f}초"
            notes = result.get('notes', '-')
            
            table.add_row(node, status, install_time, notes)
        
        self.console.print(table)
    
    def show_preflight_results(self, results: Dict[str, Any]):
        """Pre-flight 체크 결과 표시"""
        table = Table(title="설치 전 점검 결과", box=box.DOUBLE)
        
        table.add_column("항목", style="cyan", no_wrap=True)
        table.add_column("결과", justify="center", style="magenta")
        table.add_column("상세", style="white")
        
        for check_name, result in results.items():
            if result['passed']:
                status = "[green]✅ 통과[/green]"
            else:
                status = "[red]❌ 실패[/red]"
            
            details = result.get('message', '-')
            
            table.add_row(check_name, status, details)
        
        self.console.print(table)
    
    def show_munge_validation_results(self, results: Dict[str, Any]):
        """Munge 검증 결과 표시"""
        table = Table(title="🔐 Munge 인증 검증 결과", box=box.HEAVY)
        
        table.add_column("노드", style="cyan")
        table.add_column("서비스", justify="center")
        table.add_column("인증 테스트", justify="center")
        table.add_column("키 체크섬", style="yellow")
        
        for node, result in results.items():
            service_status = "🟢" if result.get('service_running') else "🔴"
            auth_status = "✅" if result.get('authentication_ok') else "❌"
            checksum = result.get('key_checksum', 'N/A')[:16] + "..."
            
            table.add_row(node, service_status, auth_status, checksum)
        
        self.console.print(table)
    
    def show_snapshot_list(self, snapshots: List[Dict[str, Any]]):
        """스냅샷 목록 표시"""
        if not snapshots:
            self.print_warning("사용 가능한 스냅샷이 없습니다.")
            return
        
        table = Table(title="💾 사용 가능한 스냅샷", box=box.ROUNDED)
        
        table.add_column("스냅샷 ID", style="cyan")
        table.add_column("생성 시간", style="green")
        table.add_column("Stage", justify="center", style="magenta")
        table.add_column("DB 백업", justify="center")
        
        for snap in snapshots:
            snapshot_id = snap['id']
            timestamp = snap['timestamp']
            stage = str(snap['stage'])
            has_db = "✅" if snap.get('has_db') else "❌"
            
            table.add_row(snapshot_id, timestamp, stage, has_db)
        
        self.console.print(table)
    
    def show_config_summary(self, config: Dict[str, Any]):
        """설정 요약 표시"""
        panel_content = f"""
[cyan]클러스터 이름:[/cyan] {config['cluster_info']['cluster_name']}
[cyan]도메인:[/cyan] {config['cluster_info']['domain']}
[cyan]설치 방식:[/cyan] {config.get('installation', {}).get('install_method', 'package')}
[cyan]Stage:[/cyan] {config.get('stage', 1)}

[yellow]노드 구성:[/yellow]
  • 컨트롤러: {config['nodes']['controller']['hostname']}
  • 계산 노드: {len(config['nodes']['compute_nodes'])}개

[yellow]주요 기능:[/yellow]
  • 데이터베이스: {'✅' if config.get('database', {}).get('enabled') else '❌'}
  • 모니터링: {'✅' if config.get('monitoring', {}).get('prometheus', {}).get('enabled') else '❌'}
  • 오프라인 모드: {'✅' if config.get('installation', {}).get('offline_mode') else '❌'}
        """
        
        panel = Panel(
            panel_content,
            title="⚙️  설정 정보",
            border_style="blue",
            box=box.DOUBLE
        )
        
        self.console.print(panel)
    
    def ask_confirmation(self, question: str) -> bool:
        """사용자 확인 요청"""
        response = self.console.input(f"[yellow]{question}[/yellow] [cyan](Y/n)[/cyan]: ")
        return response.lower() in ['y', 'yes', '']


class RichLogger:
    """Rich 기반 로거"""
    
    def __init__(self, console: Optional[Console] = None):
        self.console = console or Console()
        self.log_level = "INFO"
    
    def debug(self, message: str):
        """디버그 로그"""
        if self.log_level == "DEBUG":
            self.console.print(f"[dim]🐛 DEBUG: {message}[/dim]")
    
    def info(self, message: str):
        """정보 로그"""
        self.console.print(f"ℹ️  [cyan]INFO:[/cyan] {message}")
    
    def warning(self, message: str):
        """경고 로그"""
        self.console.print(f"⚠️  [yellow]WARNING:[/yellow] {message}")
    
    def error(self, message: str):
        """오류 로그"""
        self.console.print(f"❌ [red]ERROR:[/red] {message}")
    
    def success(self, message: str):
        """성공 로그"""
        self.console.print(f"✅ [green]SUCCESS:[/green] {message}")


def demo():
    """UI 데모"""
    ui = InstallationProgressUI()
    
    # 배너
    ui.print_banner()
    
    # 섹션
    ui.print_section("설치 전 점검", "🔍")
    
    # Pre-flight 결과
    test_results = {
        "1. 디스크 공간": {"passed": True, "message": "충분함"},
        "2. 시간 동기화": {"passed": True, "message": "동기화됨"},
        "3. 네트워크": {"passed": False, "message": "일부 노드 느림"},
    }
    ui.show_preflight_results(test_results)
    
    # 설치 결과
    ui.print_section("설치 결과", "📊")
    install_results = {
        "head01": {"success": True, "time": 125.5, "notes": "패키지 설치"},
        "compute01": {"success": True, "time": 118.2, "notes": "패키지 설치"},
    }
    ui.show_installation_summary(install_results)
    
    # Munge 결과
    ui.print_section("Munge 검증", "🔐")
    munge_results = {
        "head01": {
            "service_running": True,
            "authentication_ok": True,
            "key_checksum": "a1b2c3d4e5f6g7h8"
        },
        "compute01": {
            "service_running": True,
            "authentication_ok": True,
            "key_checksum": "a1b2c3d4e5f6g7h8"
        }
    }
    ui.show_munge_validation_results(munge_results)


if __name__ == "__main__":
    demo()
