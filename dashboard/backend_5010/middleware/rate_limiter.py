"""
Rate Limiting Middleware
API 남용 방지를 위한 Rate Limiter

Features:
- 메모리 기반 Rate Limiting
- 사용자별 요청 수 제한
- Sliding Window 알고리즘
- 자동 만료 처리
"""

from functools import wraps
from flask import request, jsonify, g
from datetime import datetime, timedelta
from collections import defaultdict
from typing import Dict, List
import threading
import logging

logger = logging.getLogger(__name__)


class RateLimiter:
    """
    메모리 기반 Rate Limiter

    Sliding Window 알고리즘 사용:
    - 각 사용자별로 요청 타임스탬프 저장
    - window 시간 밖의 요청은 자동 제거
    - 현재 window 내 요청 수가 max_requests 초과 시 차단
    """

    def __init__(self):
        # {user_id: [timestamp1, timestamp2, ...]}
        self.requests: Dict[str, List[datetime]] = defaultdict(list)
        self.lock = threading.Lock()

        # 통계 (선택적)
        self.stats = {
            'total_requests': 0,
            'blocked_requests': 0,
            'unique_users': set()
        }

    def is_allowed(self, user_id: str, max_requests: int, window_seconds: int) -> bool:
        """
        Rate limit 체크

        Args:
            user_id: 사용자 ID
            max_requests: 허용된 최대 요청 수
            window_seconds: 시간 window (초)

        Returns:
            bool: 허용 여부
        """
        with self.lock:
            now = datetime.now()
            cutoff = now - timedelta(seconds=window_seconds)

            # 오래된 요청 제거 (sliding window)
            self.requests[user_id] = [
                ts for ts in self.requests[user_id]
                if ts > cutoff
            ]

            # 현재 window 내 요청 수 확인
            current_requests = len(self.requests[user_id])

            # 통계 업데이트
            self.stats['total_requests'] += 1
            self.stats['unique_users'].add(user_id)

            if current_requests >= max_requests:
                self.stats['blocked_requests'] += 1
                logger.warning(
                    f"Rate limit exceeded for user {user_id}: "
                    f"{current_requests}/{max_requests} requests in {window_seconds}s"
                )
                return False

            # 새 요청 추가
            self.requests[user_id].append(now)
            return True

    def get_remaining(self, user_id: str, max_requests: int, window_seconds: int) -> int:
        """
        남은 요청 수 계산

        Args:
            user_id: 사용자 ID
            max_requests: 최대 요청 수
            window_seconds: 시간 window (초)

        Returns:
            int: 남은 요청 수
        """
        with self.lock:
            now = datetime.now()
            cutoff = now - timedelta(seconds=window_seconds)

            # 현재 window 내 요청 수
            current_requests = sum(
                1 for ts in self.requests[user_id]
                if ts > cutoff
            )

            return max(0, max_requests - current_requests)

    def get_retry_after(self, user_id: str, window_seconds: int) -> int:
        """
        재시도 가능 시간 계산

        Args:
            user_id: 사용자 ID
            window_seconds: 시간 window (초)

        Returns:
            int: 재시도까지 남은 시간 (초)
        """
        with self.lock:
            if user_id not in self.requests or not self.requests[user_id]:
                return 0

            now = datetime.now()
            oldest_request = min(self.requests[user_id])
            retry_after = (oldest_request + timedelta(seconds=window_seconds) - now).total_seconds()

            return max(0, int(retry_after))

    def reset(self, user_id: str = None):
        """
        Rate limit 리셋

        Args:
            user_id: 특정 사용자만 리셋 (None이면 전체 리셋)
        """
        with self.lock:
            if user_id:
                self.requests.pop(user_id, None)
                logger.info(f"Rate limit reset for user {user_id}")
            else:
                self.requests.clear()
                logger.info("Rate limit reset for all users")

    def get_stats(self) -> Dict:
        """
        Rate limiter 통계 반환

        Returns:
            dict: 통계 정보
        """
        with self.lock:
            return {
                'total_requests': self.stats['total_requests'],
                'blocked_requests': self.stats['blocked_requests'],
                'unique_users': len(self.stats['unique_users']),
                'active_users': len(self.requests),
                'block_rate': (
                    self.stats['blocked_requests'] / self.stats['total_requests'] * 100
                    if self.stats['total_requests'] > 0 else 0
                )
            }

    def cleanup_old_entries(self, max_age_seconds: int = 3600):
        """
        오래된 엔트리 정리 (메모리 절약)

        Args:
            max_age_seconds: 최대 보관 시간 (초, 기본 1시간)
        """
        with self.lock:
            now = datetime.now()
            cutoff = now - timedelta(seconds=max_age_seconds)

            # 오래된 요청 제거
            users_to_remove = []
            for user_id, timestamps in self.requests.items():
                self.requests[user_id] = [ts for ts in timestamps if ts > cutoff]
                if not self.requests[user_id]:
                    users_to_remove.append(user_id)

            # 빈 엔트리 제거
            for user_id in users_to_remove:
                del self.requests[user_id]

            logger.debug(f"Cleaned up {len(users_to_remove)} old entries")


# 전역 Rate Limiter 인스턴스
_rate_limiter_instance = RateLimiter()


def get_rate_limiter() -> RateLimiter:
    """Rate Limiter 싱글톤 인스턴스 반환"""
    return _rate_limiter_instance


def rate_limit(max_requests: int = 100, window_seconds: int = 60):
    """
    Rate limiting 데코레이터

    사용자별로 지정된 시간 window 내에서 최대 요청 수를 제한합니다.

    Usage:
        @jwt_required
        @rate_limit(max_requests=10, window_seconds=60)
        def upload_file():
            ...

    Args:
        max_requests: 허용된 최대 요청 수 (기본 100)
        window_seconds: 시간 window 초 단위 (기본 60초)

    Returns:
        decorator function
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            # JWT에서 사용자 정보 가져오기
            user = g.get('user')
            if not user:
                # JWT 인증이 없으면 IP 주소 기반으로 제한
                user_id = request.remote_addr or 'anonymous'
                logger.warning(f"Rate limiting without JWT for IP: {user_id}")
            else:
                user_id = user['username']

            # Rate limit 체크
            rate_limiter = get_rate_limiter()

            if not rate_limiter.is_allowed(user_id, max_requests, window_seconds):
                # 제한 초과
                remaining = rate_limiter.get_remaining(user_id, max_requests, window_seconds)
                retry_after = rate_limiter.get_retry_after(user_id, window_seconds)

                response = jsonify({
                    'error': 'Rate limit exceeded',
                    'message': f'Maximum {max_requests} requests per {window_seconds} seconds',
                    'retry_after': retry_after,
                    'limit': max_requests,
                    'window': window_seconds,
                    'remaining': remaining
                })
                response.status_code = 429
                response.headers['Retry-After'] = str(retry_after)
                response.headers['X-RateLimit-Limit'] = str(max_requests)
                response.headers['X-RateLimit-Remaining'] = str(remaining)
                response.headers['X-RateLimit-Reset'] = str(retry_after)

                return response

            # 허용 - 헤더에 정보 추가
            remaining = rate_limiter.get_remaining(user_id, max_requests, window_seconds)

            # 원래 함수 실행
            response = f(*args, **kwargs)

            # Response에 Rate Limit 정보 추가
            if hasattr(response, 'headers'):
                response.headers['X-RateLimit-Limit'] = str(max_requests)
                response.headers['X-RateLimit-Remaining'] = str(remaining)
                response.headers['X-RateLimit-Window'] = str(window_seconds)

            return response

        return decorated_function
    return decorator


def rate_limit_by_ip(max_requests: int = 100, window_seconds: int = 60):
    """
    IP 주소 기반 Rate limiting 데코레이터

    JWT 인증 없이 IP 주소만으로 제한합니다.

    Usage:
        @rate_limit_by_ip(max_requests=10, window_seconds=60)
        def public_api():
            ...

    Args:
        max_requests: 허용된 최대 요청 수
        window_seconds: 시간 window 초 단위

    Returns:
        decorator function
    """
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            # IP 주소로 식별
            ip_address = request.remote_addr or 'unknown'

            rate_limiter = get_rate_limiter()

            if not rate_limiter.is_allowed(ip_address, max_requests, window_seconds):
                retry_after = rate_limiter.get_retry_after(ip_address, window_seconds)

                return jsonify({
                    'error': 'Rate limit exceeded',
                    'message': f'Maximum {max_requests} requests per {window_seconds} seconds',
                    'retry_after': retry_after
                }), 429

            return f(*args, **kwargs)

        return decorated_function
    return decorator
