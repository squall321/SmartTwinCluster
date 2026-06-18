/**
 * Job Management 관련 타입 정의
 */

export interface UploadedFileMetadata {
  file_type?: string;
  upload_id?: string;
  storage_path?: string;
}

export interface UploadedFile {
  id: string;
  name: string;
  size: number;
  path: string;
  uploadTime: string;
  status: 'uploading' | 'uploaded' | 'error' | 'failed';
  progress?: number;
  variableName?: string;
  metadata?: UploadedFileMetadata;
}
