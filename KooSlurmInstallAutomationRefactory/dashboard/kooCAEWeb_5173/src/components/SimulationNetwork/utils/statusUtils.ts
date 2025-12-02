// utils/simulationnetwork/statusUtils.ts
import { CaseStatus } from '../types/simulationnetwork';

export const STATUS_COLORS: Record<CaseStatus, string> = {
  Running: 'processing',
  Completed: 'success',
  Failed: 'error',
  Pending: 'default',
  Cancelled: 'warning'
};

export const ALL_STATUSES: CaseStatus[] = Object.keys(STATUS_COLORS) as CaseStatus[];

export function getStatusColor(status: CaseStatus): string {
  return STATUS_COLORS[status] || 'default';
}
