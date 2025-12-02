/**
 * File Upload Types
 * Phase 3: Unified File Upload API
 */

export interface FileInfo {
  type: 'data' | 'config' | 'script' | 'model' | 'mesh' | 'result' | 'document' | 'other';
  extension: string;
  mime_type: string;
  size: number;
  is_binary: boolean;
  is_compressed: boolean;
}

export interface UploadSession {
  upload_id: string;
  chunk_size: number;
  total_chunks: number;
  storage_path: string;
  file_info: FileInfo;
}

export interface UploadedFile {
  id: number;
  upload_id: string;
  filename: string;
  file_size: number;
  file_type: string;
  user_id: string;
  job_id?: string;
  storage_path: string;
  file_path?: string;
  chunk_size: number;
  total_chunks: number;
  uploaded_chunks: number;
  status: 'initialized' | 'uploading' | 'completed' | 'cancelled' | 'failed';
  created_at: string;
  updated_at?: string;
  completed_at?: string;
  error_message?: string;
}

export interface UploadProgress {
  upload_id: string;
  filename: string;
  progress: number; // 0-100
  uploaded_chunks: number;
  total_chunks: number;
  status: string;
  speed?: string;
  eta?: string;
}

export interface ClassifiedFiles {
  data: File[];
  config: File[];
  script: File[];
  model: File[];
  mesh: File[];
  result: File[];
  document: File[];
  other: File[];
}

export interface ChunkUploadOptions {
  file: File;
  uploadId: string;
  chunkSize: number;
  onProgress: (progress: number) => void;
  onError: (error: Error) => void;
  signal?: AbortSignal;
}

export interface UnifiedUploaderProps {
  templateId?: string;
  jobId?: string;
  userId: string;
  onComplete: (files: UploadedFile[]) => void;
  onError?: (error: Error) => void;
  onClassified?: (files: ClassifiedFiles) => void;
  maxFileSize?: number;
  maxFiles?: number;
  acceptedTypes?: string[];
  enableChunking?: boolean;
  chunkSize?: number;
}
