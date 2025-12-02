/**
 * FileValidationStatus Component
 * 템플릿 파일 검증 결과 표시
 */

import React from 'react';
import { ValidationResult } from '../../utils/templateFileValidation';
import { CheckCircle, XCircle, AlertCircle, Info } from 'lucide-react';

interface FileValidationStatusProps {
  validation: ValidationResult | null;
  loading?: boolean;
  className?: string;
}

export const FileValidationStatus: React.FC<FileValidationStatusProps> = ({
  validation,
  loading = false,
  className = ''
}) => {
  if (loading) {
    return (
      <div className={`p-4 bg-gray-50 border border-gray-200 rounded-lg ${className}`}>
        <div className="flex items-center gap-2 text-gray-600">
          <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-gray-600"></div>
          <span className="text-sm">파일 검증 중...</span>
        </div>
      </div>
    );
  }

  if (!validation) {
    return null;
  }

  // 검증 통과
  if (validation.valid && validation.warnings.length === 0) {
    return (
      <div className={`p-4 bg-green-50 border border-green-200 rounded-lg ${className}`}>
        <div className="flex items-start gap-3">
          <CheckCircle className="w-5 h-5 text-green-600 flex-shrink-0 mt-0.5" />
          <div className="flex-1">
            <h4 className="text-sm font-medium text-green-800 mb-1">
              ✓ 파일 검증 통과
            </h4>
            <p className="text-sm text-green-700">
              모든 필수 파일이 업로드되었습니다.
            </p>
          </div>
        </div>
      </div>
    );
  }

  // 에러가 있는 경우
  if (!validation.valid) {
    return (
      <div className={`p-4 bg-red-50 border border-red-200 rounded-lg ${className}`}>
        <div className="flex items-start gap-3">
          <XCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
          <div className="flex-1 space-y-3">
            <div>
              <h4 className="text-sm font-medium text-red-800 mb-2">
                필수 파일 누락
              </h4>
              <ul className="space-y-1">
                {validation.errors.map((error, index) => (
                  <li key={index} className="text-sm text-red-700">
                    • {error}
                  </li>
                ))}
              </ul>
            </div>

            {/* 제안 사항 */}
            {validation.suggestions.length > 0 && (
              <div className="pt-2 border-t border-red-200">
                <h5 className="text-xs font-medium text-red-800 mb-1">
                  예제 파일명:
                </h5>
                <ul className="space-y-0.5">
                  {validation.suggestions.map((suggestion, index) => (
                    <li key={index} className="text-xs text-red-600">
                      • {suggestion}
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </div>
        </div>
      </div>
    );
  }

  // 경고만 있는 경우
  if (validation.warnings.length > 0) {
    return (
      <div className={`p-4 bg-yellow-50 border border-yellow-200 rounded-lg ${className}`}>
        <div className="flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-yellow-600 flex-shrink-0 mt-0.5" />
          <div className="flex-1">
            <h4 className="text-sm font-medium text-yellow-800 mb-2">
              주의사항
            </h4>
            <ul className="space-y-1">
              {validation.warnings.map((warning, index) => (
                <li key={index} className="text-sm text-yellow-700">
                  • {warning}
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    );
  }

  return null;
};

/**
 * TemplateRequirements Component
 * 템플릿 파일 요구사항 표시
 */
interface TemplateRequirementsProps {
  schema: any;
  className?: string;
}

export const TemplateRequirements: React.FC<TemplateRequirementsProps> = ({
  schema,
  className = ''
}) => {
  if (!schema || Object.keys(schema).length === 0) {
    return null;
  }

  const required = Object.entries(schema).filter(([_, s]: [string, any]) => s.required);
  const optional = Object.entries(schema).filter(([_, s]: [string, any]) => !s.required);

  return (
    <div className={`p-4 bg-blue-50 border border-blue-200 rounded-lg ${className}`}>
      <div className="flex items-start gap-3">
        <Info className="w-5 h-5 text-blue-600 flex-shrink-0 mt-0.5" />
        <div className="flex-1 space-y-3">
          <h4 className="text-sm font-medium text-blue-800">
            템플릿 파일 요구사항
          </h4>

          {/* 필수 파일 */}
          {required.length > 0 && (
            <div>
              <h5 className="text-xs font-medium text-blue-700 mb-2">
                필수 파일:
              </h5>
              <ul className="space-y-2">
                {required.map(([name, s]: [string, any]) => (
                  <li key={name} className="text-sm text-blue-700">
                    <div className="font-medium">{name}</div>
                    {s.description && (
                      <div className="text-xs text-blue-600 mt-0.5">
                        {s.description}
                      </div>
                    )}
                    {s.examples && s.examples.length > 0 && (
                      <div className="text-xs text-blue-600 mt-0.5">
                        예: {s.examples.join(', ')}
                      </div>
                    )}
                    {s.extensions && s.extensions.length > 0 && (
                      <div className="text-xs text-blue-500 mt-0.5">
                        형식: {s.extensions.join(', ')}
                      </div>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          )}

          {/* 선택 파일 */}
          {optional.length > 0 && (
            <div className="pt-2 border-t border-blue-200">
              <h5 className="text-xs font-medium text-blue-700 mb-2">
                선택 파일 (권장):
              </h5>
              <ul className="space-y-1">
                {optional.map(([name, s]: [string, any]) => (
                  <li key={name} className="text-xs text-blue-600">
                    • {name}
                    {s.description && ` - ${s.description}`}
                  </li>
                ))}
              </ul>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default FileValidationStatus;
