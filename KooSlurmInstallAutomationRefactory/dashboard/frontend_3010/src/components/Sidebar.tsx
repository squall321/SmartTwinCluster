import React, { useState } from 'react';
import {
  LayoutGrid, Layout, Activity, BarChart3, FileCode,
  Briefcase, Database, Server, Stethoscope, ChevronDown, ChevronRight, Menu, X, Monitor, Terminal
} from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

export type TabType = 'customdash' | 'cluster' | 'monitoring' | 'prometheus' | 'health' | 'reports' | 'jobs' | 'templates' | 'nodes' | 'data' | 'vnc' | 'ssh';

interface MenuItem {
  id: TabType;
  label: string;
  icon: React.ComponentType<{ size?: number; className?: string }>;
  category?: string;
  requiredPermission?: 'dashboard' | 'cae' | 'vnc' | 'app' | 'admin';
}

interface MenuCategory {
  id: string;
  label: string;
  items: MenuItem[];
}

interface SidebarProps {
  activeTab: TabType;
  onTabChange: (tab: TabType) => void;
  isMobile?: boolean;
}

const menuStructure: MenuCategory[] = [
  {
    id: 'overview',
    label: 'Overview',
    items: [
      { id: 'customdash', label: 'Custom Dashboard', icon: Layout as React.ComponentType<{ size?: number; className?: string }>, requiredPermission: 'dashboard' },
      { id: 'cluster', label: 'Cluster Management', icon: LayoutGrid as React.ComponentType<{ size?: number; className?: string }>, requiredPermission: 'admin' },
    ]
  },
  {
    id: 'operations',
    label: 'Operations',
    items: [
      { id: 'jobs', label: 'Job Management', icon: Briefcase as React.ComponentType<{ size?: number; className?: string }>, requiredPermission: 'dashboard' },
      { id: 'templates', label: 'Job Templates', icon: FileCode as React.ComponentType<{ size?: number; className?: string }>, requiredPermission: 'dashboard' },
      { id: 'nodes', label: 'Node Management', icon: Server as React.ComponentType<{ size?: number; className?: string }>, requiredPermission: 'admin' },
      { id: 'vnc', label: 'VNC Sessions', icon: Monitor as React.ComponentType<{ size?: number; className?: string }>, requiredPermission: 'admin' },
      { id: 'ssh', label: 'SSH Sessions', icon: Terminal as React.ComponentType<{ size?: number; className?: string }>, requiredPermission: 'admin' },
    ]
  },
  {
    id: 'monitoring',
    label: 'Monitoring',
    items: [
      { id: 'monitoring', label: 'Real-time Monitoring', icon: Activity as React.ComponentType<{ size?: number; className?: string }>, requiredPermission: 'dashboard' },
      { id: 'prometheus', label: 'Prometheus Metrics', icon: BarChart3 as React.ComponentType<{ size?: number; className?: string }>, requiredPermission: 'admin' },
      { id: 'health', label: 'Health Check', icon: Stethoscope as React.ComponentType<{ size?: number; className?: string }>, requiredPermission: 'admin' },
      { id: 'reports', label: 'Reports', icon: FileCode as React.ComponentType<{ size?: number; className?: string }>, requiredPermission: 'admin' },
    ]
  },
  {
    id: 'data',
    label: 'Data',
    items: [
      { id: 'data', label: 'Data Management', icon: Database as React.ComponentType<{ size?: number; className?: string }>, requiredPermission: 'admin' },
    ]
  }
];

export const Sidebar: React.FC<SidebarProps> = ({ activeTab, onTabChange, isMobile = false }) => {
  const { user } = useAuth();
  const [expandedCategories, setExpandedCategories] = useState<Set<string>>(
    new Set(['overview', 'operations', 'monitoring', 'data'])
  );
  const [isCollapsed, setIsCollapsed] = useState(false);
  const [isMobileOpen, setIsMobileOpen] = useState(false);

  // Check if user has permission to see a menu item
  const hasPermission = (permission?: string): boolean => {
    if (!user) return false;
    if (!permission) return true; // No permission required

    // Get user's permissions from groups
    const userPermissions = new Set<string>();
    user.groups.forEach(group => {
      const groupPerms = {
        'HPC-Admins': ['dashboard', 'cae', 'vnc', 'app', 'admin'],
        'DX-Users': ['dashboard', 'vnc', 'app'],
        'CAEG-Users': ['dashboard', 'cae', 'vnc', 'app'],
      }[group] || [];
      groupPerms.forEach(perm => userPermissions.add(perm));
    });

    return userPermissions.has(permission);
  };

  const toggleCategory = (categoryId: string) => {
    setExpandedCategories(prev => {
      const newSet = new Set(prev);
      if (newSet.has(categoryId)) {
        newSet.delete(categoryId);
      } else {
        newSet.add(categoryId);
      }
      return newSet;
    });
  };

  const handleTabChange = (tab: TabType) => {
    onTabChange(tab);
    if (isMobile) {
      setIsMobileOpen(false);
    }
  };

  const sidebarContent = (
    <div className={`flex flex-col h-full ${isCollapsed ? 'w-16' : 'w-64'} transition-all duration-300`}>
      {/* Sidebar Header */}
      <div className="p-4 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between">
        {!isCollapsed && (
          <h2 className="text-lg font-bold text-gray-800 dark:text-white">Navigation</h2>
        )}
        <button
          onClick={() => isMobile ? setIsMobileOpen(false) : setIsCollapsed(!isCollapsed)}
          className="p-1 rounded hover:bg-gray-200 dark:hover:bg-gray-700 transition"
          title={isCollapsed ? 'Expand' : 'Collapse'}
        >
          {isMobile ? <X size={20} /> : isCollapsed ? <ChevronRight size={20} /> : <Menu size={20} />}
        </button>
      </div>

      {/* Menu Items */}
      <nav className="flex-1 overflow-y-auto py-4">
        {menuStructure.map(category => {
          const isExpanded = expandedCategories.has(category.id);

          // Filter items based on user permissions
          const visibleItems = category.items.filter(item => hasPermission(item.requiredPermission));

          // Don't show category if no items are visible
          if (visibleItems.length === 0) return null;

          return (
            <div key={category.id} className="mb-2">
              {/* Category Header */}
              <button
                onClick={() => toggleCategory(category.id)}
                className={`w-full flex items-center justify-between px-4 py-2 text-sm font-semibold text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 transition ${
                  isCollapsed ? 'justify-center' : ''
                }`}
                title={isCollapsed ? category.label : ''}
              >
                {!isCollapsed && <span>{category.label}</span>}
                {!isCollapsed && (
                  isExpanded ? <ChevronDown size={16} /> : <ChevronRight size={16} />
                )}
                {isCollapsed && (
                  <div className="w-8 h-0.5 bg-gray-400 dark:bg-gray-600" />
                )}
              </button>

              {/* Category Items */}
              {isExpanded && (
                <div className="mt-1">
                  {visibleItems.map(item => {
                    const Icon = item.icon;
                    const isActive = activeTab === item.id;

                    return (
                      <button
                        key={item.id}
                        onClick={() => handleTabChange(item.id)}
                        className={`w-full flex items-center gap-3 px-4 py-2.5 text-sm transition ${
                          isActive
                            ? 'bg-blue-50 dark:bg-blue-900/30 text-blue-600 dark:text-blue-400 border-l-4 border-blue-600'
                            : 'text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800 border-l-4 border-transparent'
                        } ${isCollapsed ? 'justify-center px-2' : ''}`}
                        title={isCollapsed ? item.label : ''}
                      >
                        <Icon size={20} className="flex-shrink-0" />
                        {!isCollapsed && <span>{item.label}</span>}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </nav>

      {/* Sidebar Footer */}
      {!isCollapsed && (
        <div className="p-4 border-t border-gray-200 dark:border-gray-700 bg-gradient-to-br from-blue-50 via-indigo-50 to-purple-50 dark:from-gray-800 dark:via-gray-850 dark:to-gray-900">
          <div>
            {/* Product Name with Version - Enhanced Design */}
            <div className="mb-4">
              {/* Main Title with Gradient */}
              <div className="flex items-baseline gap-2 mb-2">
                <h3 className="font-bold text-lg bg-gradient-to-r from-blue-600 via-indigo-600 to-purple-600 dark:from-blue-400 dark:via-indigo-400 dark:to-purple-400 bg-clip-text text-transparent leading-tight">
                  Smart Twin Flow
                </h3>
                <span className="inline-flex items-center px-2 py-0.5 bg-gradient-to-r from-blue-500 to-indigo-500 text-white rounded-full text-[10px] font-bold shadow-sm">
                  v3.8.0
                </span>
              </div>
              
              {/* Subtitle with Icon */}
              <div className="flex items-center gap-1.5 pl-0.5">
                <div className="w-1 h-1 rounded-full bg-gradient-to-r from-blue-500 to-indigo-500"></div>
                <p className="text-xs font-medium text-gray-600 dark:text-gray-400 tracking-wide">
                  Slurm Management Platform
                </p>
              </div>
            </div>
            
            {/* Divider */}
            <div className="h-px bg-gradient-to-r from-transparent via-gray-300 dark:via-gray-600 to-transparent mb-4"></div>
            
            {/* Creator */}
            <div className="mb-4">
              <p className="text-[11px] text-gray-500 dark:text-gray-500 mb-1.5 uppercase tracking-wider font-medium">
                Created by
              </p>
              <p className="text-sm leading-tight font-bold">
                <span className="text-red-600 dark:text-red-500">Koo</span>
                <span className="text-gray-800 dark:text-gray-200">k Jin Park</span>
              </p>
            </div>
            
            {/* Copyright with Border */}
            <div className="pt-3 border-t border-gray-300 dark:border-gray-600">
              <p className="text-xs font-semibold text-gray-700 dark:text-gray-300 text-center tracking-wide">
                © 2025 All Rights Reserved
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );

  // Mobile: Overlay Sidebar
  if (isMobile) {
    return (
      <>
        {/* Mobile Toggle Button */}
        <button
          onClick={() => setIsMobileOpen(!isMobileOpen)}
          className="fixed top-4 left-4 z-50 p-2 bg-white dark:bg-gray-800 rounded-lg shadow-lg lg:hidden"
        >
          <Menu size={24} />
        </button>

        {/* Mobile Sidebar Overlay */}
        {isMobileOpen && (
          <>
            <div
              className="fixed inset-0 bg-black bg-opacity-50 z-40 lg:hidden"
              onClick={() => setIsMobileOpen(false)}
            />
            <aside className="fixed left-0 top-0 h-full bg-white dark:bg-gray-800 shadow-xl z-50 lg:hidden">
              {sidebarContent}
            </aside>
          </>
        )}
      </>
    );
  }

  // Desktop: Static Sidebar
  return (
    <aside className="h-screen bg-white dark:bg-gray-800 shadow-lg border-r border-gray-200 dark:border-gray-700 sticky top-0">
      {sidebarContent}
    </aside>
  );
};
