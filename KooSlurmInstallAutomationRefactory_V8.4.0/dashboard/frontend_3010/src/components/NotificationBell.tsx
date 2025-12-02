import React, { useState, useEffect } from 'react';
import { Bell } from 'lucide-react';
import NotificationCenter from './NotificationCenter';

/**
 * NotificationBell 컴포넌트
 * 헤더에 표시되는 알림 벨 아이콘
 */

interface NotificationBellProps {
  className?: string;
}

const NotificationBell: React.FC<NotificationBellProps> = ({ className = '' }) => {
  const [isOpen, setIsOpen] = useState(false);
  const [unreadCount, setUnreadCount] = useState(0);
  const [isAnimating, setIsAnimating] = useState(false);

  // 미읽음 알림 개수 가져오기
  const fetchUnreadCount = async () => {
    try {
      const response = await fetch('/dashboardapi/notifications/unread-count');
      if (response.ok) {
        const data = await response.json();
        const newCount = data.count || 0;
        
        // 새 알림이 있으면 애니메이션
        if (newCount > unreadCount) {
          setIsAnimating(true);
          setTimeout(() => setIsAnimating(false), 1000);
        }
        
        setUnreadCount(newCount);
      }
    } catch (error) {
      console.error('Failed to fetch unread count:', error);
    }
  };

  // 초기 로드
  useEffect(() => {
    fetchUnreadCount();
  }, []);

  // 토글 핸들러
  const handleToggle = () => {
    setIsOpen(!isOpen);
  };

  // NotificationCenter가 닫힐 때
  const handleClose = () => {
    setIsOpen(false);
    fetchUnreadCount(); // 개수 업데이트
  };

  return (
    <>
      {/* 벨 아이콘 */}
      <div className={`relative ${className}`}>
        <button
          onClick={handleToggle}
          className={`
            relative p-2 rounded-lg transition-all duration-200
            hover:bg-gray-100 dark:hover:bg-gray-800
            ${isOpen ? 'bg-gray-100 dark:bg-gray-800' : ''}
            ${isAnimating ? 'animate-bounce' : ''}
          `}
          aria-label="알림"
        >
          <Bell 
            className={`
              w-6 h-6 text-gray-600 dark:text-gray-300
              ${isAnimating ? 'animate-pulse' : ''}
            `}
          />
          
          {/* 미읽음 배지 */}
          {unreadCount > 0 && (
            <span className="
              absolute -top-1 -right-1
              min-w-[20px] h-5 px-1
              flex items-center justify-center
              text-xs font-bold text-white
              bg-red-500 rounded-full
              animate-pulse
            ">
              {unreadCount > 99 ? '99+' : unreadCount}
            </span>
          )}
        </button>

        {/* 툴팁 */}
        {!isOpen && unreadCount > 0 && (
          <div className="
            absolute top-full right-0 mt-1
            px-2 py-1 text-xs text-white bg-gray-900 rounded
            whitespace-nowrap opacity-0 hover:opacity-100
            transition-opacity duration-200 pointer-events-none
          ">
            {unreadCount}개의 새 알림
          </div>
        )}
      </div>

      {/* NotificationCenter 패널 */}
      {isOpen && (
        <NotificationCenter
          isOpen={isOpen}
          onClose={handleClose}
          onUnreadCountChange={setUnreadCount}
        />
      )}
    </>
  );
};

export default NotificationBell;
