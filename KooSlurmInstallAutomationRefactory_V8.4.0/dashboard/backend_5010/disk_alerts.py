"""
디스크 사용량 알림 시스템
임계값 초과 시 자동 경고
"""

import os
from typing import List, Dict, Optional
from datetime import datetime
import logging

logger = logging.getLogger(__name__)

# 알림 설정
DEFAULT_WARNING_THRESHOLD = 75  # 75%
DEFAULT_CRITICAL_THRESHOLD = 90  # 90%

class DiskUsageAlert:
    """디스크 사용량 알림 클래스"""
    
    def __init__(self, 
                 warning_threshold: int = DEFAULT_WARNING_THRESHOLD,
                 critical_threshold: int = DEFAULT_CRITICAL_THRESHOLD):
        self.warning_threshold = warning_threshold
        self.critical_threshold = critical_threshold
        self.alerts: List[Dict] = []
    
    def check_usage(self, path: str, usage_percent: float, 
                   node: Optional[str] = None) -> Optional[Dict]:
        """
        디스크 사용량 체크 및 알림 생성
        
        Returns:
            {
                'level': 'warning' | 'critical',
                'path': str,
                'node': str,
                'usage': float,
                'threshold': int,
                'message': str,
                'timestamp': str
            }
        """
        alert = None
        
        if usage_percent >= self.critical_threshold:
            alert = {
                'level': 'critical',
                'path': path,
                'node': node or 'local',
                'usage': usage_percent,
                'threshold': self.critical_threshold,
                'message': f"Critical: {path} is {usage_percent:.1f}% full (threshold: {self.critical_threshold}%)",
                'timestamp': datetime.now().isoformat()
            }
        elif usage_percent >= self.warning_threshold:
            alert = {
                'level': 'warning',
                'path': path,
                'node': node or 'local',
                'usage': usage_percent,
                'threshold': self.warning_threshold,
                'message': f"Warning: {path} is {usage_percent:.1f}% full (threshold: {self.warning_threshold}%)",
                'timestamp': datetime.now().isoformat()
            }
        
        if alert:
            self.alerts.append(alert)
            logger.warning(f"Disk usage alert: {alert['message']}")
        
        return alert
    
    def check_all_storage(self, storage_stats: List[Dict]) -> List[Dict]:
        """
        모든 스토리지 체크
        
        Args:
            storage_stats: [
                {
                    'path': str,
                    'node': str (optional),
                    'usage_percent': float
                }
            ]
        
        Returns:
            List of alerts
        """
        alerts = []
        
        for stat in storage_stats:
            alert = self.check_usage(
                path=stat.get('path', ''),
                usage_percent=stat.get('usage_percent', 0),
                node=stat.get('node')
            )
            if alert:
                alerts.append(alert)
        
        return alerts
    
    def get_recent_alerts(self, limit: int = 50) -> List[Dict]:
        """최근 알림 조회"""
        return self.alerts[-limit:] if self.alerts else []
    
    def clear_alerts(self):
        """알림 초기화"""
        self.alerts.clear()
    
    def get_summary(self) -> Dict:
        """알림 요약"""
        if not self.alerts:
            return {
                'total': 0,
                'warning': 0,
                'critical': 0,
                'latest': None
            }
        
        warning_count = sum(1 for a in self.alerts if a['level'] == 'warning')
        critical_count = sum(1 for a in self.alerts if a['level'] == 'critical')
        
        return {
            'total': len(self.alerts),
            'warning': warning_count,
            'critical': critical_count,
            'latest': self.alerts[-1] if self.alerts else None
        }


# 전역 인스턴스
disk_alert_system = DiskUsageAlert()


def check_data_storage() -> Optional[Dict]:
    """
    /data 스토리지 체크
    """
    try:
        import shutil
        stat = shutil.disk_usage('/data')
        usage_percent = (stat.used / stat.total) * 100
        
        return disk_alert_system.check_usage('/data', usage_percent)
    except Exception as e:
        logger.error(f"Failed to check /data storage: {e}")
        return None


def check_scratch_nodes(nodes_data: List[Dict]) -> List[Dict]:
    """
    Scratch 노드들 체크
    
    Args:
        nodes_data: [
            {
                'node': str,
                'usage_percent': float
            }
        ]
    """
    alerts = []
    
    for node_data in nodes_data:
        alert = disk_alert_system.check_usage(
            path='/scratch',
            usage_percent=node_data.get('usage_percent', 0),
            node=node_data.get('node', 'unknown')
        )
        if alert:
            alerts.append(alert)
    
    return alerts


def get_all_alerts() -> Dict:
    """모든 알림 조회"""
    return {
        'alerts': disk_alert_system.get_recent_alerts(),
        'summary': disk_alert_system.get_summary(),
        'thresholds': {
            'warning': disk_alert_system.warning_threshold,
            'critical': disk_alert_system.critical_threshold
        }
    }
