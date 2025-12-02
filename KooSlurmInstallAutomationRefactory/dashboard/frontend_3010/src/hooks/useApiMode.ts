import { useState, useEffect } from 'react';

export type ApiMode = 'mock' | 'production' | 'unknown';

interface HealthCheckResponse {
  status: string;
  mode: string;
  timestamp: string;
}

export const useApiMode = () => {
  const [mode, setMode] = useState<ApiMode>('unknown');
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    const checkMode = async () => {
      try {
        const response = await fetch('/dashboardapi/health');
        const data: HealthCheckResponse = await response.json();
        setMode(data.mode as ApiMode);
      } catch (error) {
        console.error('Failed to check API mode:', error);
        setMode('unknown');
      } finally {
        setIsLoading(false);
      }
    };

    checkMode();
  }, []);

  return { mode, isLoading };
};
