export const STATUS_COLORS = {
    Running: 'processing',
    Completed: 'success',
    Failed: 'error',
    Pending: 'default',
    Cancelled: 'warning'
};
export const ALL_STATUSES = Object.keys(STATUS_COLORS);
export function getStatusColor(status) {
    return STATUS_COLORS[status] || 'default';
}
