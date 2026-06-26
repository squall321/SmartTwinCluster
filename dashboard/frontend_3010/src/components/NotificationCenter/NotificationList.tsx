// 알림 목록 컴포넌트
import React from 'react';
import NotificationItem from './NotificationItem';

/**
 * NotificationList 컴포넌트
 * 알림 목록 표시 (무한 스크롤 지원)
 */

interface Notification {
  id: string;
  type: 'job_completed' | 'job_failed' | 'job_started' | 'alert' | 'system' | 'info';
  title: string;
  message: string;
  data?: any;
  read: boolean;
  timestamp: string;
  created_at: string;
}

interface NotificationListProps {
  notifications: Notification[];
  loading: boolean;
  onMarkAsRead: (id: string) => void;
  onDelete: (id: string) => void;
}

const NotificationList: React.FC<NotificationListProps> = ({
  notifications,
  loading,
  onMarkAsRead,
  onDelete,
}) => {
  if (loading) {
    return (
      <div className="flex-1 flex items-center justify-center p-8">
        <div className="text-center">
          <div className="inline-block w-8 h-8 border-4 border-blue-500 border-t-transparent rounded-full animate-spin mb-2" />
          <p className="text-sm text-gray-500 dark:text-gray-400">로딩 중...</p>
        </div>
      </div>
    );
  }

  if (notifications.length === 0) {
    return (
      <div className="flex-1 flex items-center justify-center p-8">
        <div className="text-center">
          <div className="text-6xl mb-4">🔔</div>
          <p className="text-gray-500 dark:text-gray-400">알림이 없습니다</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 overflow-y-auto">
      {notifications.map((notification) => (
        <NotificationItem
          key={notification.id}
          notification={notification}
          onMarkAsRead={onMarkAsRead}
          onDelete={onDelete}
        />
      ))}
    </div>
  );
};

export default NotificationList;
