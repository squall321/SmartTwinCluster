"""
Redis Session Manager

Unified session management for all dashboard services using Redis as backend.
"""

import json
import time
from datetime import datetime
from typing import Dict, List, Optional, Any
import redis

from .config import get_redis_client, DEFAULT_SESSION_TTL, MAX_SESSION_TTL


class RedisSessionManager:
    """
    Redis-based session manager

    Features:
    - Automatic TTL management
    - JSON serialization/deserialization
    - Session indexing for fast lookup
    - Batch operations
    - Health monitoring
    """

    def __init__(self, service_name: str, ttl: int = DEFAULT_SESSION_TTL, redis_client: Optional[redis.Redis] = None, legacy_key_pattern: bool = True):
        """
        Initialize session manager

        Args:
            service_name: Service identifier (e.g., 'app', 'vnc', 'auth')
            ttl: Default session TTL in seconds (default: 7200 = 2 hours)
            redis_client: Optional Redis client (will create if not provided)
            legacy_key_pattern: Use legacy key pattern {service}:session:{id} for backward compatibility
        """
        self.service_name = service_name
        self.ttl = min(ttl, MAX_SESSION_TTL)  # Cap at max TTL
        self.redis = redis_client or get_redis_client()
        self.legacy_key_pattern = legacy_key_pattern

        # Key patterns - support both legacy and new patterns
        if legacy_key_pattern:
            # Legacy: {service}:session:{id}
            self.session_key_prefix = f"{service_name}:session"
            self.index_key = f"{service_name}:session:index"
        else:
            # New: session:{service}:{id}
            self.session_key_prefix = f"session:{service_name}"
            self.index_key = f"{self.session_key_prefix}:index"

    def _get_session_key(self, session_id: str) -> str:
        """Get Redis key for session"""
        return f"{self.session_key_prefix}:{session_id}"

    def _serialize(self, data: dict) -> str:
        """Serialize session data to JSON"""
        # Add metadata
        data_with_meta = {
            **data,
            '_service': self.service_name,
            '_updated_at': datetime.now().isoformat(),
        }
        return json.dumps(data_with_meta, default=str)

    def _deserialize(self, data: str) -> Optional[dict]:
        """Deserialize JSON to session data"""
        if not data:
            return None
        try:
            return json.loads(data)
        except json.JSONDecodeError:
            return None

    def create_session(self, session_id: str, data: dict, ttl: Optional[int] = None) -> bool:
        """
        Create a new session

        Args:
            session_id: Unique session identifier
            data: Session data (must be JSON serializable)
            ttl: Optional TTL override (seconds)

        Returns:
            bool: True if successful, False otherwise
        """
        try:
            key = self._get_session_key(session_id)
            ttl = ttl or self.ttl

            # Add session ID to data
            data['id'] = session_id

            # Serialize and store
            serialized = self._serialize(data)
            self.redis.setex(key, ttl, serialized)

            # Add to index
            self.redis.sadd(self.index_key, session_id)

            return True
        except Exception as e:
            print(f"[RedisSessionManager] Error creating session {session_id}: {e}")
            return False

    def get_session(self, session_id: str) -> Optional[dict]:
        """
        Get session data

        Args:
            session_id: Session identifier

        Returns:
            dict: Session data or None if not found
        """
        try:
            key = self._get_session_key(session_id)
            data = self.redis.get(key)
            return self._deserialize(data) if data else None
        except Exception as e:
            print(f"[RedisSessionManager] Error getting session {session_id}: {e}")
            return None

    def update_session(self, session_id: str, data: dict, ttl: Optional[int] = None, merge: bool = True) -> bool:
        """
        Update session data

        Args:
            session_id: Session identifier
            data: New session data
            ttl: Optional TTL override (seconds)
            merge: If True, merge with existing data; if False, replace

        Returns:
            bool: True if successful, False otherwise
        """
        try:
            if merge:
                # Merge with existing data
                existing = self.get_session(session_id)
                if existing:
                    # Remove metadata before merging
                    existing.pop('_service', None)
                    existing.pop('_updated_at', None)
                    data = {**existing, **data}

            # Update
            return self.create_session(session_id, data, ttl)
        except Exception as e:
            print(f"[RedisSessionManager] Error updating session {session_id}: {e}")
            return False

    def delete_session(self, session_id: str) -> bool:
        """
        Delete a session

        Args:
            session_id: Session identifier

        Returns:
            bool: True if deleted, False otherwise
        """
        try:
            key = self._get_session_key(session_id)
            self.redis.delete(key)
            self.redis.srem(self.index_key, session_id)
            return True
        except Exception as e:
            print(f"[RedisSessionManager] Error deleting session {session_id}: {e}")
            return False

    def list_sessions(self, include_data: bool = True) -> List[dict]:
        """
        List all sessions

        Args:
            include_data: If True, include session data; if False, only IDs

        Returns:
            List[dict]: List of sessions
        """
        try:
            session_ids = self.redis.smembers(self.index_key)

            if not include_data:
                return [{'id': sid} for sid in session_ids]

            sessions = []
            for sid in session_ids:
                session = self.get_session(sid)
                if session:
                    sessions.append(session)
                else:
                    # Clean up stale index entry
                    self.redis.srem(self.index_key, sid)

            return sessions
        except Exception as e:
            print(f"[RedisSessionManager] Error listing sessions: {e}")
            return []

    def session_exists(self, session_id: str) -> bool:
        """
        Check if session exists

        Args:
            session_id: Session identifier

        Returns:
            bool: True if exists, False otherwise
        """
        try:
            key = self._get_session_key(session_id)
            return self.redis.exists(key) > 0
        except Exception as e:
            print(f"[RedisSessionManager] Error checking session {session_id}: {e}")
            return False

    def extend_ttl(self, session_id: str, ttl: Optional[int] = None) -> bool:
        """
        Extend session TTL

        Args:
            session_id: Session identifier
            ttl: New TTL in seconds (default: use service default)

        Returns:
            bool: True if successful, False otherwise
        """
        try:
            key = self._get_session_key(session_id)
            ttl = ttl or self.ttl
            return self.redis.expire(key, ttl)
        except Exception as e:
            print(f"[RedisSessionManager] Error extending TTL for {session_id}: {e}")
            return False

    def get_ttl(self, session_id: str) -> int:
        """
        Get remaining TTL for session

        Args:
            session_id: Session identifier

        Returns:
            int: Remaining TTL in seconds (-1 if no expiry, -2 if not found)
        """
        try:
            key = self._get_session_key(session_id)
            return self.redis.ttl(key)
        except Exception as e:
            print(f"[RedisSessionManager] Error getting TTL for {session_id}: {e}")
            return -2

    def count_sessions(self) -> int:
        """
        Count active sessions

        Returns:
            int: Number of active sessions
        """
        try:
            return self.redis.scard(self.index_key)
        except Exception as e:
            print(f"[RedisSessionManager] Error counting sessions: {e}")
            return 0

    def delete_all_sessions(self) -> int:
        """
        Delete all sessions for this service (USE WITH CAUTION!)

        Returns:
            int: Number of sessions deleted
        """
        try:
            session_ids = self.redis.smembers(self.index_key)
            count = 0

            for sid in session_ids:
                if self.delete_session(sid):
                    count += 1

            return count
        except Exception as e:
            print(f"[RedisSessionManager] Error deleting all sessions: {e}")
            return 0

    def cleanup_stale_index(self) -> int:
        """
        Remove stale entries from index (sessions that no longer exist)

        Returns:
            int: Number of stale entries removed
        """
        try:
            session_ids = self.redis.smembers(self.index_key)
            removed = 0

            for sid in session_ids:
                if not self.session_exists(sid):
                    self.redis.srem(self.index_key, sid)
                    removed += 1

            return removed
        except Exception as e:
            print(f"[RedisSessionManager] Error cleaning up index: {e}")
            return 0

    def get_stats(self) -> dict:
        """
        Get session statistics

        Returns:
            dict: Statistics about sessions
        """
        try:
            total = self.count_sessions()
            sessions = self.list_sessions(include_data=True)

            # Calculate average TTL
            ttls = [self.get_ttl(s['id']) for s in sessions if s.get('id')]
            avg_ttl = sum(t for t in ttls if t > 0) / len(ttls) if ttls else 0

            return {
                'service': self.service_name,
                'total_sessions': total,
                'average_ttl': round(avg_ttl, 2),
                'redis_connected': True,
            }
        except Exception as e:
            print(f"[RedisSessionManager] Error getting stats: {e}")
            return {
                'service': self.service_name,
                'total_sessions': 0,
                'average_ttl': 0,
                'redis_connected': False,
                'error': str(e),
            }
