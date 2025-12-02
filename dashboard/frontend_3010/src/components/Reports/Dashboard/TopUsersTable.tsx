/**
 * TopUsersTable.tsx
 * Top users ranking table
 * v3.4.0
 */

import React from 'react';
import { UserGroupIcon } from '@heroicons/react/24/outline';
import type { DashboardTopUser } from '../../../utils/api';

interface TopUsersTableProps {
  users: DashboardTopUser[];
  loading?: boolean;
  error?: string | null;
}

const TopUsersTable: React.FC<TopUsersTableProps> = ({
  users,
  loading = false,
  error = null,
}) => {
  if (loading) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        <div className="flex items-center gap-2 mb-4">
          <UserGroupIcon className="w-6 h-6 text-purple-600" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Top Users
          </h3>
        </div>
        <div className="h-96 flex items-center justify-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-purple-600"></div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        <div className="flex items-center gap-2 mb-4">
          <UserGroupIcon className="w-6 h-6 text-purple-600" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Top 사용자
          </h3>
        </div>
        <div className="h-96 flex items-center justify-center">
          <div className="text-center">
            <p className="text-red-500 mb-2">❌ {error}</p>
            <p className="text-gray-500 dark:text-gray-400 text-sm">
              Unable to load data
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
      {/* 헤더 */}
      <div className="flex items-center gap-2 mb-4">
        <UserGroupIcon className="w-6 h-6 text-purple-600" />
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
          Top Users (Top {users.length})
        </h3>
      </div>

      {/* 테이블 */}
      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead className="bg-gray-50 dark:bg-gray-900">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Rank
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                User
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                CPU (Hours)
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                GPU (Hours)
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Jobs
              </th>
              <th className="px-4 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Cost
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Usage
              </th>
            </tr>
          </thead>
          <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
            {users.map((user) => (
              <tr
                key={user.rank}
                className="hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors"
              >
                {/* 순위 */}
                <td className="px-4 py-4 whitespace-nowrap">
                  <div className="flex items-center">
                    {user.rank <= 3 ? (
                      <span className="text-2xl">
                        {user.rank === 1 ? '🥇' : user.rank === 2 ? '🥈' : '🥉'}
                      </span>
                    ) : (
                      <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
                        {user.rank}
                      </span>
                    )}
                  </div>
                </td>

                {/* 사용자 */}
                <td className="px-4 py-4 whitespace-nowrap">
                  <div className="text-sm font-medium text-gray-900 dark:text-white">
                    {user.username}
                  </div>
                  <div className="text-xs text-gray-500 dark:text-gray-400">
                    {user.jobs_success} / {user.jobs_count} Success
                  </div>
                </td>

                {/* CPU 시간 */}
                <td className="px-4 py-4 whitespace-nowrap text-right">
                  <div className="text-sm text-gray-900 dark:text-white">
                    {user.cpu_hours.toFixed(1)}h
                  </div>
                </td>

                {/* GPU 시간 */}
                <td className="px-4 py-4 whitespace-nowrap text-right">
                  <div className="text-sm text-gray-900 dark:text-white">
                    {user.gpu_hours.toFixed(1)}h
                  </div>
                </td>

                {/* 작업 수 */}
                <td className="px-4 py-4 whitespace-nowrap text-right">
                  <div className="text-sm text-gray-900 dark:text-white">
                    {user.jobs_count}
                  </div>
                </td>

                {/* 비용 */}
                <td className="px-4 py-4 whitespace-nowrap text-right">
                  <div className="text-sm font-semibold text-gray-900 dark:text-white">
                    ${user.cost.toFixed(2)}
                  </div>
                </td>

                {/* 사용률 프로그레스 바 */}
                <td className="px-4 py-4 whitespace-nowrap">
                  <div className="space-y-1">
                    {/* CPU */}
                    <div className="flex items-center gap-2">
                      <span className="text-xs text-gray-500 dark:text-gray-400 w-8">
                        CPU
                      </span>
                      <div className="flex-1 bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                        <div
                          className="bg-blue-600 h-2 rounded-full transition-all"
                          style={{ width: `${user.cpu_utilization}%` }}
                        />
                      </div>
                      <span className="text-xs text-gray-600 dark:text-gray-400 w-10 text-right">
                        {user.cpu_utilization.toFixed(0)}%
                      </span>
                    </div>
                    {/* GPU */}
                    <div className="flex items-center gap-2">
                      <span className="text-xs text-gray-500 dark:text-gray-400 w-8">
                        GPU
                      </span>
                      <div className="flex-1 bg-gray-200 dark:bg-gray-700 rounded-full h-2">
                        <div
                          className="bg-green-600 h-2 rounded-full transition-all"
                          style={{ width: `${user.gpu_utilization}%` }}
                        />
                      </div>
                      <span className="text-xs text-gray-600 dark:text-gray-400 w-10 text-right">
                        {user.gpu_utilization.toFixed(0)}%
                      </span>
                    </div>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {users.length === 0 && (
        <div className="text-center py-8">
          <p className="text-gray-500 dark:text-gray-400">
            No user data
          </p>
        </div>
      )}
    </div>
  );
};

export default TopUsersTable;
