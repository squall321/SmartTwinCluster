/**
 * Job Management 관련 타입 정의
 */

export interface UploadedFile {
  id: string;
  name: string;
  size: number;
  path: string;
  uploadTime: string;
  status: 'uploading' | 'uploaded' | 'error';
  progress?: number;
  variableName?: string;
}
