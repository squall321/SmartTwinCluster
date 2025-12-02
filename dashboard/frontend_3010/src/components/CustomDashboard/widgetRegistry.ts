import React from 'react';
import CPUWidget from './widgets/CPUWidget';
import MemoryWidget from './widgets/MemoryWidget';
import GPUWidget from './widgets/GPUWidget';
import JobQueueWidget from './widgets/JobQueueWidget';
import RecentJobsWidget from './widgets/RecentJobsWidget';
import QuickActionsWidget from './widgets/QuickActionsWidget';
import NodeStatusWidget from './widgets/NodeStatusWidget';
import StorageWidget from './widgets/StorageWidget';
import AlertsWidget from './widgets/AlertsWidget';
import FavoritesWidget from './widgets/FavoritesWidget';

export type WidgetType = 
  | 'cpu'
  | 'memory'
  | 'gpu'
  | 'jobQueue'
  | 'recentJobs'
  | 'quickActions'
  | 'nodeStatus'
  | 'storage'
  | 'alerts'
  | 'favorites';

export interface WidgetProps {
  id: string;
  onRemove: () => void;
  isEditMode: boolean;
  mode: 'mock' | 'production';
}

export const widgetRegistry: Record<WidgetType, React.FC<WidgetProps>> = {
  cpu: CPUWidget,
  memory: MemoryWidget,
  gpu: GPUWidget,
  jobQueue: JobQueueWidget,
  recentJobs: RecentJobsWidget,
  quickActions: QuickActionsWidget,
  nodeStatus: NodeStatusWidget,
  storage: StorageWidget,
  alerts: AlertsWidget,
  favorites: FavoritesWidget,
};
