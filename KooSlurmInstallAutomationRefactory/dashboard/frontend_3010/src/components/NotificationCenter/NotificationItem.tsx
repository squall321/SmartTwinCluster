import React from 'react';
import { 
  CheckCircle, 
  XCircle, 
  PlayCircle, 
  AlertTriangle, 
  Info, 
  Settings,
  Trash2 
} from 'lucide-react';

/**
 * NotificationItem 컴포넌트
 * 개별 알림 아이템
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

interface NotificationItemProps {
  notification: Notification;
  onMarkAsRead: (id: string) => void;
  onDelete: (id: string) => void;
}

// 알림 타입별 아이콘과 색상
const getNotificationStyle = (type: Notification['type']) => {
  switch (type) {
    case 'job_completed':
      return {
        icon: CheckCircle,
        iconColor: 'text-green-500',
        bgColor: 'bg-green-50 dark:bg-green-900/20',
        borderColor: 'border-green-200 dark:border-green-800',
      };
    case 'job_failed':
      return {
        icon: XCircle,
        iconColor: 'text-red-500',
        bgColor: 'bg-red-50 dark:bg-red-900/20',
        borderColor: 'border-red-200 dark:border-red-800',
      };
    case 'job_started':
      return {
        icon: PlayCircle,
        iconColor: 'text-blue-500',
        bgColor: 'bg-blue-50 dark:bg-blue-900/20',
        borderColor: 'border-blue-200 dark:border-blue-800',
      };
    case 'alert':
      return {
        icon: AlertTriangle,
        iconColor: 'text-yellow-500',
        bgColor: 'bg-yellow-50 dark:bg-yellow-900/20',
        borderColor: 'border-yellow-200 dark:border-yellow-800',
      };
    case 'system':
      return {
        icon: Settings,
        iconColor: 'text-purple-500',
        bgColor: 'bg-purple-50 dark:bg-purple-900/20',
        borderColor: 'border-purple-200 dark:border-purple-800',
      };
    default:
      return {
        icon: Info,
        iconColor: 'text-gray-500',
        bgColor: 'bg-gray-50 dark:bg-gray-900/20',
        borderColor: 'border-gray-200 dark:border-gray-800',
      };
  }
};

// 시간 포맷
const formatTime = (timestamp: string) => {
  const date = new Date(timestamp);
  const now = new Date();
  const diff = Math.floor((now.getTime() - date.getTime()) / 1000); // 초 단위

  if (diff < 60) return '방금 전';
  if (diff < 3600) return `${Math.floor(diff / 60)}분 전`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}시간 전`;
  if (diff < 604800) return `${Math.floor(diff / 86400)}일 전`;
  
  return date.toLocaleDateString('ko-KR', {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const NotificationItem: React.FC<NotificationItemProps> = ({
  notification,
  onMarkAsRead,
  onDelete,
}) => {
  const style = getNotificationStyle(notification.type);
  const Icon = style.icon;

  const handleClick = () => {
    if (!notification.read) {
      onMarkAsRead(notification.id);
    }
  };

  const handleDelete = (e: React.MouseEvent) => {
    e.stopPropagation();
    onDelete(notification.id);
  };

  return (
    <div
      onClick={handleClick}
      className={`
        relative p-4 border-b border-gray-200 dark:border-gray-700
        hover:bg-gray-50 dark:hover:bg-gray-800/50
        cursor-pointer transition-colors
        ${!notification.read ? 'bg-blue-50/50 dark:bg-blue-900/10' : ''}
      `}
    >
      <div className="flex gap-3">
        {/* 아이콘 */}
        <div className={`flex-shrink-0 w-10 h-10 rounded-full ${style.bgColor} flex items-center justify-center`}>
          <Icon className={`w-5 h-5 ${style.iconColor}`} />
        </div>

        {/* 내용 */}
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <h3 className="font-medium text-gray-900 dark:text-white text-sm">
              {notification.title}
            </h3>
            
            {/* 읽지 않음 표시 */}
            {!notification.read && (
              <div className="flex-shrink-0 w-2 h-2 rounded-full bg-blue-500" />
            )}
          </div>

          <p className="text-sm text-gray-600 dark:text-gray-400 mt-1 line-clamp-2">
            {notification.message}
          </p>

          {/* 추가 데이터 */}
          {notification.data && Object.keys(notification.data).length > 0 && (
            <div className="mt-2 text-xs text-gray-500 dark:text-gray-500">
              {Object.entries(notification.data).map(([key, value]) => (
                <span key={key} className="mr-3">
                  {key}: <strong>{String(value)}</strong>
                </span>
              ))}
            </div>
          )}

          {/* 시간 및 액션 */}
          <div className="flex items-center justify-between mt-2">
            <span className="text-xs text-gray-500 dark:text-gray-500">
              {formatTime(notification.timestamp)}
            </span>

            <button
              onClick={handleDelete}
              className="
                p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700
                text-gray-400 hover:text-red-500
                transition-colors opacity-0 group-hover:opacity-100
              "
              title="삭제"
            >
              <Trash2 className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default NotificationItem;
