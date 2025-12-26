/**
 * Authentication Context
 * JWT 토큰 기반 사용자 인증 및 권한 관리
 * SSO false 모드에서는 자동으로 admin 권한 부여
 */

import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { getUserInfo, isTokenExpired, clearJwtToken, UserInfo, checkSsoConfig } from '../utils/api';

interface AuthContextType {
  user: UserInfo | null;
  isAuthenticated: boolean;
  isAdmin: boolean;
  hasGroup: (groupName: string) => boolean;
  logout: () => void;
  refreshUser: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<UserInfo | null>(null);
  const [ssoConfigLoaded, setSsoConfigLoaded] = useState(false);

  const loadUser = () => {
    try {
      // Check if token is expired
      if (isTokenExpired()) {
        console.warn('[Auth] JWT token expired');
        clearJwtToken();
        setUser(null);
        return;
      }

      const userInfo = getUserInfo();
      setUser(userInfo);

      if (userInfo) {
        console.log('[Auth] User loaded:', {
          username: userInfo.username,
          groups: userInfo.groups,
          isAdmin: userInfo.groups.includes('HPC-Admins'),
        });
      }
    } catch (error) {
      console.error('[Auth] Error loading user:', error);
      setUser(null);
    }
  };

  useEffect(() => {
    // Load SSO config first, then load user
    const initAuth = async () => {
      try {
        const config = await checkSsoConfig();
        setSsoConfigLoaded(true);

        if (!config.sso_enabled) {
          console.log('[Auth] SSO disabled - granting full admin permissions');
        }

        // Load user after SSO config is loaded
        loadUser();
      } catch (error) {
        console.error('[Auth] Error loading SSO config:', error);
        setSsoConfigLoaded(true);
        loadUser();
      }
    };

    initAuth();

    // Check token expiration every minute
    const interval = setInterval(() => {
      if (isTokenExpired()) {
        console.warn('[Auth] JWT token expired, clearing session');
        clearJwtToken();
        setUser(null);
      }
    }, 60 * 1000);

    return () => clearInterval(interval);
  }, []);

  const logout = () => {
    clearJwtToken();
    setUser(null);
    window.location.href = '/'; // Redirect to auth portal
  };

  const hasGroup = (groupName: string): boolean => {
    return user?.groups.includes(groupName) || false;
  };

  const isAdmin = user?.groups.includes('HPC-Admins') || false;
  const isAuthenticated = user !== null;

  const value = {
    user,
    isAuthenticated,
    isAdmin,
    hasGroup,
    logout,
    refreshUser: loadUser,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
