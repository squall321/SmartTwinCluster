/**
 * Apptainer Catalog Page
 * Phase 1 Frontend - Apptainer 이미지 카탈로그
 *
 * Features:
 * - 전체 이미지 목록 표시
 * - 파티션별 필터링
 * - 검색 기능
 * - 이미지 상세 모달
 * - 스캔 트리거
 */

import React, { useState } from 'react';
import { ApptainerSelector, ApptainerImage } from '../components/ApptainerSelector';

export const ApptainerCatalog: React.FC = () => {
  const [selectedImage, setSelectedImage] = useState<ApptainerImage | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);

  const handleSelectImage = (image: ApptainerImage | null) => {
    setSelectedImage(image);
    if (image) {
      setShowDetailModal(true);
    }
  };

  const handleCloseModal = () => {
    setShowDetailModal(false);
  };

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      {/* Header */}
      <div className="bg-white dark:bg-gray-800 shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100">
                Apptainer Images
              </h1>
              <p className="mt-2 text-sm text-gray-600 dark:text-gray-400">
                클러스터에서 사용 가능한 Apptainer 컨테이너 이미지 목록
              </p>
            </div>
            <div>
              <span className="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200">
                Phase 1
              </span>
            </div>
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
          <ApptainerSelector
            partition={null}
            selectedImageId={selectedImage?.id}
            onSelect={handleSelectImage}
          />
        </div>

        {/* 사용 가이드 */}
        <div className="mt-6 bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-6">
          <h3 className="text-lg font-semibold text-blue-900 dark:text-blue-200 mb-3">
            사용 방법
          </h3>
          <ul className="space-y-2 text-sm text-blue-700 dark:text-blue-300">
            <li className="flex items-start">
              <span className="mr-2">1️⃣</span>
              <span>목록에서 사용하려는 Apptainer 이미지를 선택하세요</span>
            </li>
            <li className="flex items-start">
              <span className="mr-2">2️⃣</span>
              <span>이미지 클릭 시 상세 정보 (앱, 환경변수, 라벨 등)를 확인할 수 있습니다</span>
            </li>
            <li className="flex items-start">
              <span className="mr-2">3️⃣</span>
              <span>작업 제출 시 선택한 이미지가 자동으로 적용됩니다</span>
            </li>
            <li className="flex items-start">
              <span className="mr-2">4️⃣</span>
              <span>검색 창을 사용하여 이미지 이름, 설명, 앱 이름으로 검색 가능합니다</span>
            </li>
          </ul>
        </div>

        {/* 통계 정보 */}
        <div className="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <div className="w-12 h-12 bg-blue-100 dark:bg-blue-900 rounded-lg flex items-center justify-center">
                  <span className="text-2xl">📦</span>
                </div>
              </div>
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600 dark:text-gray-400">
                  Compute Images
                </p>
                <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                  -
                </p>
              </div>
            </div>
          </div>

          <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <div className="w-12 h-12 bg-purple-100 dark:bg-purple-900 rounded-lg flex items-center justify-center">
                  <span className="text-2xl">🖥️</span>
                </div>
              </div>
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600 dark:text-gray-400">
                  Visualization Images
                </p>
                <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                  -
                </p>
              </div>
            </div>
          </div>

          <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <div className="w-12 h-12 bg-green-100 dark:bg-green-900 rounded-lg flex items-center justify-center">
                  <span className="text-2xl">⚡</span>
                </div>
              </div>
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600 dark:text-gray-400">
                  Total Apps
                </p>
                <p className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                  -
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Detail Modal (간단 버전 - 향후 확장 가능) */}
      {showDetailModal && selectedImage && (
        <div className="fixed inset-0 z-50 overflow-y-auto">
          <div className="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
            {/* Backdrop */}
            <div
              className="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
              onClick={handleCloseModal}
            />

            {/* Modal */}
            <div className="inline-block align-bottom bg-white dark:bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-5xl sm:w-full">
              <div className="bg-white dark:bg-gray-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4 max-h-[85vh] overflow-y-auto">
                <div className="flex items-start justify-between mb-4 sticky top-0 bg-white dark:bg-gray-800 pb-4 border-b border-gray-200 dark:border-gray-700">
                  <h3 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
                    이미지 상세 정보
                  </h3>
                  <button
                    onClick={handleCloseModal}
                    className="text-gray-400 hover:text-gray-500 dark:hover:text-gray-300"
                  >
                    <span className="text-2xl">×</span>
                  </button>
                </div>

                <div className="space-y-6">
                  {/* 기본 정보 */}
                  <div className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-4">
                    <h4 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-2">
                      {selectedImage.name}
                    </h4>
                    <p className="text-sm text-gray-600 dark:text-gray-400">
                      {selectedImage.description}
                    </p>
                  </div>

                  {/* 메타데이터 */}
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-4">
                      <span className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Path</span>
                      <p className="text-sm text-gray-900 dark:text-gray-100 font-mono mt-1 break-all">
                        {selectedImage.path}
                      </p>
                    </div>
                    <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-4">
                      <span className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Node</span>
                      <p className="text-sm text-gray-900 dark:text-gray-100 mt-1">
                        {selectedImage.node}
                      </p>
                    </div>
                    <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-4">
                      <span className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Version</span>
                      <p className="text-sm text-gray-900 dark:text-gray-100 mt-1">
                        {selectedImage.version}
                      </p>
                    </div>
                    <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-4">
                      <span className="text-xs font-medium text-gray-500 dark:text-gray-400 uppercase">Size</span>
                      <p className="text-sm text-gray-900 dark:text-gray-100 mt-1">
                        {(selectedImage.size / (1024 ** 3)).toFixed(2)} GB
                      </p>
                    </div>
                  </div>

                  {/* Apps */}
                  {selectedImage.apps.length > 0 && (
                    <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-4">
                      <h5 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3 flex items-center">
                        <span className="mr-2">⚡</span>
                        Available Apps ({selectedImage.apps.length})
                      </h5>
                      <div className="flex flex-wrap gap-2">
                        {selectedImage.apps.map((app, idx) => (
                          <span
                            key={idx}
                            className="px-3 py-1.5 text-xs font-medium bg-blue-100 dark:bg-blue-900/50 text-blue-800 dark:text-blue-200 rounded-lg border border-blue-200 dark:border-blue-800"
                          >
                            {app}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Labels */}
                  {Object.keys(selectedImage.labels).length > 0 && (
                    <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-4">
                      <h5 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3 flex items-center">
                        <span className="mr-2">🏷️</span>
                        Labels ({Object.keys(selectedImage.labels).length})
                      </h5>
                      <div className="space-y-2">
                        {Object.entries(selectedImage.labels).map(([key, value]) => (
                          <div key={key} className="flex items-start text-sm bg-gray-50 dark:bg-gray-700/50 rounded px-3 py-2">
                            <span className="text-gray-600 dark:text-gray-400 font-medium min-w-[120px] flex-shrink-0">{key}:</span>
                            <span className="text-gray-900 dark:text-gray-100 font-mono text-xs break-all ml-2">{value}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Environment Variables */}
                  {Object.keys(selectedImage.env_vars).length > 0 && (
                    <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-4">
                      <h5 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3 flex items-center">
                        <span className="mr-2">🔧</span>
                        Environment Variables ({Object.keys(selectedImage.env_vars).length})
                      </h5>
                      <div className="space-y-2 max-h-60 overflow-y-auto pr-2">
                        {Object.entries(selectedImage.env_vars).map(([key, value]) => (
                          <div key={key} className="flex items-start text-sm bg-gray-50 dark:bg-gray-700/50 rounded px-3 py-2">
                            <span className="text-gray-600 dark:text-gray-400 font-medium min-w-[140px] flex-shrink-0">{key}:</span>
                            <span className="text-gray-900 dark:text-gray-100 font-mono text-xs break-all ml-2">{value}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              </div>

              <div className="bg-gray-50 dark:bg-gray-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                <button
                  onClick={handleCloseModal}
                  className="w-full inline-flex justify-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-blue-600 text-base font-medium text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:ml-3 sm:w-auto sm:text-sm"
                >
                  닫기
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ApptainerCatalog;
