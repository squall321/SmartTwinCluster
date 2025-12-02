/**
 * FileClassifier Component
 * 업로드된 파일을 타입별로 분류하여 표시
 */

import React, { useMemo } from 'react';
import { ClassifiedFiles } from '../../types/upload';
import {
  Database,
  Settings,
  Code,
  Box,
  Layers,
  FileText,
  File,
  FileCheck
} from 'lucide-react';

interface FileClassifierProps {
  files: File[];
  onClassified?: (classified: ClassifiedFiles) => void;
  className?: string;
}

// 파일 타입 아이콘 매핑
const TYPE_ICONS = {
  data: Database,
  config: Settings,
  script: Code,
  model: Box,
  mesh: Layers,
  result: FileCheck,
  document: FileText,
  other: File
};

// 파일 타입 색상 매핑
const TYPE_COLORS = {
  data: 'text-blue-600 bg-blue-50',
  config: 'text-green-600 bg-green-50',
  script: 'text-purple-600 bg-purple-50',
  model: 'text-orange-600 bg-orange-50',
  mesh: 'text-cyan-600 bg-cyan-50',
  result: 'text-pink-600 bg-pink-50',
  document: 'text-gray-600 bg-gray-50',
  other: 'text-gray-400 bg-gray-50'
};

// 파일 타입 한글 이름
const TYPE_NAMES = {
  data: '데이터',
  config: '설정',
  script: '스크립트',
  model: '모델',
  mesh: '메쉬',
  result: '결과',
  document: '문서',
  other: '기타'
};

/**
 * 파일 확장자로 타입 감지
 */
const detectFileType = (filename: string): keyof ClassifiedFiles => {
  const ext = filename.split('.').pop()?.toLowerCase() || '';

  // Data 파일
  if (['dat', 'csv', 'txt', 'tar', 'gz', 'zip', 'hdf5', 'h5', 'nc', 'bin'].includes(ext)) {
    return 'data';
  }

  // Config 파일
  if (['yaml', 'yml', 'json', 'toml', 'ini', 'conf', 'cfg', 'env'].includes(ext)) {
    return 'config';
  }

  // Script 파일
  if (['py', 'sh', 'bash', 'js', 'ts', 'lua', 'pl', 'rb', 'sbatch', 'slurm'].includes(ext)) {
    return 'script';
  }

  // Model 파일
  if (['pth', 'pt', 'ckpt', 'pb', 'onnx', 'tflite', 'pkl', 'pickle', 'joblib', 'model'].includes(ext)) {
    return 'model';
  }

  // Mesh 파일
  if (['msh', 'mesh', 'ugrid', 'cgns', 'stl', 'obj', 'ply', 'vtk', 'vtu', 'foam'].includes(ext)) {
    return 'mesh';
  }

  // Result 파일
  if (['out', 'log', 'res', 'result', 'plt'].includes(ext)) {
    return 'result';
  }

  // Document 파일
  if (['pdf', 'doc', 'docx', 'md', 'rst', 'xls', 'xlsx', 'ppt', 'pptx'].includes(ext)) {
    return 'document';
  }

  return 'other';
};

/**
 * 파일 크기 포맷
 */
const formatFileSize = (bytes: number): string => {
  if (bytes === 0) return '0 B';

  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));

  return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
};

export const FileClassifier: React.FC<FileClassifierProps> = ({
  files,
  onClassified,
  className = ''
}) => {
  /**
   * 파일 분류
   */
  const classified = useMemo(() => {
    const groups: ClassifiedFiles = {
      data: [],
      config: [],
      script: [],
      model: [],
      mesh: [],
      result: [],
      document: [],
      other: []
    };

    files.forEach(file => {
      const type = detectFileType(file.name);
      groups[type].push(file);
    });

    // 콜백 호출
    if (onClassified) {
      onClassified(groups);
    }

    return groups;
  }, [files, onClassified]);

  /**
   * 총 파일 수 및 크기
   */
  const totalSize = useMemo(() => {
    return files.reduce((sum, file) => sum + file.size, 0);
  }, [files]);

  if (files.length === 0) {
    return null;
  }

  return (
    <div className={`space-y-4 ${className}`}>
      {/* 헤더 */}
      <div className="flex items-center justify-between border-b pb-2">
        <h3 className="text-lg font-semibold text-gray-800">
          파일 분류
        </h3>
        <div className="text-sm text-gray-600">
          총 {files.length}개 파일 ({formatFileSize(totalSize)})
        </div>
      </div>

      {/* 파일 그룹 */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {(Object.entries(classified) as [keyof ClassifiedFiles, File[]][])
          .filter(([_, typeFiles]) => typeFiles.length > 0)
          .map(([type, typeFiles]) => {
            const Icon = TYPE_ICONS[type];
            const colorClass = TYPE_COLORS[type];
            const typeName = TYPE_NAMES[type];

            return (
              <div
                key={type}
                className="border rounded-lg p-4 hover:shadow-md transition-shadow"
              >
                {/* 타입 헤더 */}
                <div className="flex items-center gap-2 mb-3">
                  <div className={`p-2 rounded-lg ${colorClass}`}>
                    <Icon className="w-5 h-5" />
                  </div>
                  <div>
                    <h4 className="font-medium text-gray-800">
                      {typeName} 파일
                    </h4>
                    <p className="text-xs text-gray-500">
                      {typeFiles.length}개
                    </p>
                  </div>
                </div>

                {/* 파일 목록 */}
                <ul className="space-y-2">
                  {typeFiles.slice(0, 5).map((file, index) => (
                    <li
                      key={index}
                      className="flex items-center justify-between text-sm bg-gray-50 rounded px-3 py-2"
                    >
                      <span className="truncate flex-1 text-gray-700">
                        {file.name}
                      </span>
                      <span className="text-gray-500 ml-2 whitespace-nowrap">
                        {formatFileSize(file.size)}
                      </span>
                    </li>
                  ))}

                  {/* 더 많은 파일이 있는 경우 */}
                  {typeFiles.length > 5 && (
                    <li className="text-sm text-gray-500 text-center py-1">
                      외 {typeFiles.length - 5}개 파일
                    </li>
                  )}
                </ul>
              </div>
            );
          })}
      </div>
    </div>
  );
};

export default FileClassifier;
