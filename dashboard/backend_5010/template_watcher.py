"""
Template File Watcher
파일 시스템의 템플릿 변경을 감지하고 자동으로 DB를 동기화

watchdog 라이브러리를 사용하여 /shared/templates/ 디렉토리의
변경사항을 실시간으로 감지합니다.
"""

import time
import threading
import logging
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler, FileSystemEvent
from template_loader import TemplateLoader

logger = logging.getLogger(__name__)


class TemplateFileHandler(FileSystemEventHandler):
    """
    템플릿 파일 변경 이벤트 핸들러

    YAML 파일의 생성, 수정, 삭제를 감지하고
    TemplateLoader를 통해 DB와 동기화합니다.
    """

    def __init__(self, template_loader: TemplateLoader):
        """
        Args:
            template_loader: TemplateLoader 인스턴스
        """
        super().__init__()
        self.template_loader = template_loader
        self.debounce_time = 2  # 2초 디바운스 (연속된 이벤트 무시)
        self.last_sync_time = 0
        self.pending_sync = False
        self.sync_lock = threading.Lock()

    def on_modified(self, event: FileSystemEvent):
        """
        파일 수정 이벤트 처리

        Args:
            event: 파일 시스템 이벤트
        """
        if event.is_directory:
            return

        if self._is_template_file(event.src_path):
            logger.info(f"Template modified: {event.src_path}")
            self._schedule_sync()

    def on_created(self, event: FileSystemEvent):
        """
        파일 생성 이벤트 처리

        Args:
            event: 파일 시스템 이벤트
        """
        if event.is_directory:
            return

        if self._is_template_file(event.src_path):
            logger.info(f"New template created: {event.src_path}")
            self._schedule_sync()

    def on_deleted(self, event: FileSystemEvent):
        """
        파일 삭제 이벤트 처리

        Args:
            event: 파일 시스템 이벤트
        """
        if event.is_directory:
            return

        if self._is_template_file(event.src_path):
            logger.info(f"Template deleted: {event.src_path}")
            self._schedule_sync()

    def on_moved(self, event: FileSystemEvent):
        """
        파일 이동/이름 변경 이벤트 처리

        Args:
            event: 파일 시스템 이벤트
        """
        if event.is_directory:
            return

        if self._is_template_file(event.src_path) or self._is_template_file(event.dest_path):
            logger.info(f"Template moved: {event.src_path} -> {event.dest_path}")
            self._schedule_sync()

    def _is_template_file(self, path: str) -> bool:
        """
        템플릿 파일인지 확인 (.yaml 확장자)

        Args:
            path: 파일 경로

        Returns:
            템플릿 파일 여부
        """
        return path.endswith('.yaml') or path.endswith('.yml')

    def _schedule_sync(self):
        """
        DB 동기화 스케줄 (디바운스 적용)

        연속된 파일 변경 이벤트가 발생할 때
        디바운스를 적용하여 과도한 동기화를 방지합니다.
        """
        with self.sync_lock:
            current_time = time.time()

            # 마지막 동기화 이후 디바운스 시간이 지났는지 확인
            if current_time - self.last_sync_time < self.debounce_time:
                # 디바운스 중이면 대기 중 플래그만 설정
                self.pending_sync = True
                return

            # 동기화 실행
            self._perform_sync()

            # 대기 중인 동기화가 있으면 디바운스 후 실행
            if self.pending_sync:
                threading.Timer(self.debounce_time, self._delayed_sync).start()
                self.pending_sync = False

    def _perform_sync(self):
        """
        실제 DB 동기화 수행

        TemplateLoader의 sync_to_database() 메서드를 호출합니다.
        """
        try:
            logger.info("Starting template sync to database...")
            stats = self.template_loader.sync_to_database()
            logger.info(f"Template sync completed: {stats}")
            self.last_sync_time = time.time()

        except Exception as e:
            logger.error(f"Failed to sync templates: {e}")

    def _delayed_sync(self):
        """
        디바운스 후 지연된 동기화 실행
        """
        with self.sync_lock:
            self._perform_sync()


class TemplateWatcher:
    """
    템플릿 파일 감시자

    백그라운드 스레드에서 실행되며 템플릿 디렉토리의
    변경사항을 실시간으로 감지합니다.
    """

    def __init__(self, template_loader: TemplateLoader, watch_path: str = "/shared/templates"):
        """
        Args:
            template_loader: TemplateLoader 인스턴스
            watch_path: 감시할 디렉토리 경로
        """
        self.template_loader = template_loader
        self.watch_path = watch_path
        self.observer = None
        self.event_handler = None
        self.is_running = False

    def start(self):
        """
        파일 감시 시작

        백그라운드 스레드에서 실행되며 파일 시스템 이벤트를 감지합니다.
        """
        if self.is_running:
            logger.warning("Template watcher is already running")
            return

        try:
            logger.info(f"Starting template watcher for: {self.watch_path}")

            # 이벤트 핸들러 생성
            self.event_handler = TemplateFileHandler(self.template_loader)

            # Observer 생성 및 시작
            self.observer = Observer()
            self.observer.schedule(
                self.event_handler,
                self.watch_path,
                recursive=True  # 하위 디렉토리도 감시
            )
            self.observer.start()

            self.is_running = True
            logger.info("Template watcher started successfully")

        except Exception as e:
            logger.error(f"Failed to start template watcher: {e}")
            raise

    def stop(self):
        """
        파일 감시 중지
        """
        if not self.is_running:
            logger.warning("Template watcher is not running")
            return

        try:
            logger.info("Stopping template watcher...")

            if self.observer:
                self.observer.stop()
                self.observer.join(timeout=5)

            self.is_running = False
            logger.info("Template watcher stopped successfully")

        except Exception as e:
            logger.error(f"Error stopping template watcher: {e}")

    def is_alive(self) -> bool:
        """
        감시자가 실행 중인지 확인

        Returns:
            실행 중 여부
        """
        return self.is_running and (self.observer is not None and self.observer.is_alive())


# 전역 TemplateWatcher 인스턴스
_watcher_instance = None
_watcher_lock = threading.Lock()


def start_template_watcher(template_loader: TemplateLoader, watch_path: str = "/shared/templates"):
    """
    템플릿 감시자 시작 (싱글톤)

    Args:
        template_loader: TemplateLoader 인스턴스
        watch_path: 감시할 디렉토리 경로

    Returns:
        TemplateWatcher 인스턴스
    """
    global _watcher_instance

    with _watcher_lock:
        if _watcher_instance is not None and _watcher_instance.is_alive():
            logger.info("Template watcher already running")
            return _watcher_instance

        # 새 인스턴스 생성 및 시작
        _watcher_instance = TemplateWatcher(template_loader, watch_path)
        _watcher_instance.start()

        return _watcher_instance


def stop_template_watcher():
    """
    템플릿 감시자 중지

    Returns:
        성공 여부
    """
    global _watcher_instance

    with _watcher_lock:
        if _watcher_instance is None:
            logger.warning("No template watcher instance found")
            return False

        _watcher_instance.stop()
        _watcher_instance = None
        return True


def get_watcher_status():
    """
    템플릿 감시자 상태 조회

    Returns:
        상태 정보 딕셔너리
    """
    global _watcher_instance

    if _watcher_instance is None:
        return {
            'running': False,
            'watch_path': None,
            'message': 'Template watcher not started'
        }

    return {
        'running': _watcher_instance.is_alive(),
        'watch_path': _watcher_instance.watch_path,
        'message': 'Template watcher is running' if _watcher_instance.is_alive() else 'Template watcher stopped'
    }
