/**
 * useTemplateSchema Hook
 * Template API에서 파일 스키마를 가져옵니다
 */

import { useState, useEffect } from 'react';
import { TemplateFileSchema } from '../utils/templateFileValidation';

interface Template {
  template: {
    id: string;
    name: string;
    category: string;
    description?: string;
  };
  file_schema?: TemplateFileSchema;
  slurm_config?: any;
  apptainer_config?: any;
}

export const useTemplateSchema = (templateId?: string) => {
  const [schema, setSchema] = useState<TemplateFileSchema | null>(null);
  const [template, setTemplate] = useState<Template | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    if (!templateId) {
      setSchema(null);
      setTemplate(null);
      return;
    }

    const fetchTemplate = async () => {
      setLoading(true);
      setError(null);

      try {
        // Template API v2에서 템플릿 정보 가져오기
        const response = await fetch(`/api/v2/templates/${templateId}`);

        if (!response.ok) {
          throw new Error('Failed to fetch template');
        }

        const data: Template = await response.json();
        setTemplate(data);

        // file_schema가 있으면 설정
        if (data.file_schema) {
          setSchema(data.file_schema);
        } else {
          setSchema(null);
        }

      } catch (err) {
        console.error('Failed to fetch template schema:', err);
        setError(err as Error);
        setSchema(null);
      } finally {
        setLoading(false);
      }
    };

    fetchTemplate();
  }, [templateId]);

  return {
    schema,
    template,
    loading,
    error
  };
};

export default useTemplateSchema;
