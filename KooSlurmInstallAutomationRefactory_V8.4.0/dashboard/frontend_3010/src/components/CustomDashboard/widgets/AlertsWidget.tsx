import React, { useState, useEffect } from 'react';
import { Bell, GripVertical, X, AlertCircle, CheckCircle, XCircle, Info } from 'lucide-react';
import { WidgetProps } from '../widgetRegistry';
import { apiGet } from '../../../utils/api';

interface Alert {
  id: string;
  type: 'info' | 'success' | 'warning' | 'error';
  message: string;
  timestamp: string;
}

const AlertsWidget: React.FC<WidgetProps> = ({ id, onRemove, isEditMode, mode }) => {
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [loading, setLoading] = useState(true);
  const [usingMockData, setUsingMockData] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchAlerts();
    const interval = setInterval(fetchAlerts, 15000);
    return () => clearInterval(interval);
  }, [mode]);

  const fetchAlerts = async () => {
    setError(null);
    
    // Production 모드: 실제 API 시도
    if (mode === 'production') {
      try {
        const response = await apiGet('/api/notifications', { limit: 5 });
        if (response?.notifications && Array.isArray(response.notifications)) {
          // API 응답을 위젯 형식으로 변환
          const mappedAlerts = response.notifications.slice(0, 5).map((n: any) => {
            // 알림 타입 매핑
            let type: 'info' | 'success' | 'warning' | 'error' = 'info';
            const notifType = (n.type || '').toLowerCase();
            
            if (notifType.includes('success') || notifType.includes('completed')) {
              type = 'success';
            } else if (notifType.includes('warning') || notifType.includes('alert')) {
              type = 'warning';
            } else if (notifType.includes('error') || notifType.includes('failed')) {
              type = 'error';
            }
            
            return {
              id: n.id || String(Date.now() + Math.random()),
              type,
              message: n.message || n.title || 'Notification',
              timestamp: n.timestamp || n.created_at || 'Just now'
            };
          });
          
          setAlerts(mappedAlerts);
          setUsingMockData(false);
          setLoading(false);
          console.log('[AlertsWidget] Successfully loaded', mappedAlerts.length, 'alerts');
          return;
        } else {
          // Production 모드에서 알림이 없는 것은 정상 (빈 배열)
          setAlerts([]);
          setUsingMockData(false);
          setLoading(false);
          console.log('[AlertsWidget] No alerts in production mode');
          return;
        }
      } catch (error) {
        console.error('[AlertsWidget] Production API error:', error);
        setError('Failed to fetch alerts data');
        setAlerts([]);
        setUsingMockData(false);
        setLoading(false);
        return;
      }
    }
    
    // Mock 모드: Mock 데이터 사용
    setAlerts([
      { id: '1', type: 'warning', message: 'GPU 2번 온도가 높습니다 (78°C)', timestamp: '2분 전' },
      { id: '2', type: 'success', message: 'Job 12345 완료', timestamp: '5분 전' },
      { id: '3', type: 'error', message: 'Node compute-03 응답 없음', timestamp: '10분 전' },
      { id: '4', type: 'info', message: '시스템 업데이트 예정', timestamp: '15분 전' }
    ]);
    setUsingMockData(true);
    setLoading(false);
    console.log('[AlertsWidget] Using mock alert data');
  };

  const getAlertIcon = (type: string) => {
    switch (type) {
      case 'success':
        return <CheckCircle className="w-5 h-5 text-green-500" />;
      case 'warning':
        return <AlertCircle className="w-5 h-5 text-yellow-500" />;
      case 'error':
        return <XCircle className="w-5 h-5 text-red-500" />;
      default:
        return <Info className="w-5 h-5 text-blue-500" />;
    }
  };

  const getAlertStyle = (type: string) => {
    const styles = {
      success: 'bg-green-50 dark:bg-green-900/20 border-green-200 dark:border-green-800',
      warning: 'bg-yellow-50 dark:bg-yellow-900/20 border-yellow-200 dark:border-yellow-800',
      error: 'bg-red-50 dark:bg-red-900/20 border-red-200 dark:border-red-800',
      info: 'bg-blue-50 dark:bg-blue-900/20 border-blue-200 dark:border-blue-800',
    };
    return styles[type as keyof typeof styles] || styles.info;
  };

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-gray-200 dark:border-gray-700">
        <div className="flex items-center gap-2">
          {isEditMode && (
            <div className="drag-handle cursor-move">
              <GripVertical className="w-4 h-4 text-gray-400" />
            </div>
          )}
          <Bell className="w-5 h-5 text-red-500" />
          <h3 className="font-semibold text-gray-900 dark:text-white">Alerts</h3>
          {alerts.length > 0 && !error && (
            <span className="bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400 text-xs px-2 py-0.5 rounded-full">
              {alerts.length}
            </span>
          )}
          {mode === 'mock' && usingMockData && (
            <span className="text-xs bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 px-2 py-0.5 rounded">
              Mock
            </span>
          )}
          {mode === 'production' && !usingMockData && !loading && !error && (
            <span className="text-xs bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 px-2 py-0.5 rounded">
              Production
            </span>
          )}
        </div>
        {isEditMode && (
          <button
            onClick={onRemove}
            className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors"
          >
            <X className="w-4 h-4 text-gray-400" />
          </button>
        )}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4">
        {loading ? (
          <div className="text-center py-8">
            <div className="w-8 h-8 border-4 border-red-600 border-t-transparent rounded-full animate-spin mx-auto mb-2"></div>
            <p className="text-sm text-gray-500 dark:text-gray-400">Loading...</p>
          </div>
        ) : error ? (
          <div className="text-center text-red-500 dark:text-red-400 py-8">
            <Bell className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">{error}</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              Check Alerts API
            </p>
          </div>
        ) : alerts.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center py-8">
            <Bell className="w-12 h-12 text-gray-300 dark:text-gray-600 mb-3" />
            <p className="text-gray-500 dark:text-gray-400 font-medium">No Alerts</p>
            {mode === 'production' && (
              <p className="text-sm text-gray-400 dark:text-gray-500 mt-1">
                New alerts will appear here
              </p>
            )}
          </div>
        ) : (
          <div className="space-y-3">
            {alerts.map(alert => (
              <div
                key={alert.id}
                className={`border rounded-lg p-3 ${getAlertStyle(alert.type)}`}
              >
                <div className="flex items-start gap-3">
                  <div className="flex-shrink-0 mt-0.5">
                    {getAlertIcon(alert.type)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm text-gray-900 dark:text-white font-medium mb-1">
                      {alert.message}
                    </p>
                    <p className="text-xs text-gray-500 dark:text-gray-400">
                      {alert.timestamp}
                    </p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default AlertsWidget;
