/**
 * Apptainer 타입 정의
 * API 응답 구조와 일치하도록 작성
 */

/**
 * 동적 변수 정의
 * Slurm 설정값을 command로 자동 매핑
 */
export interface DynamicVariable {
  source: string;         // 예: "slurm.ntasks"
  transform?: string;     // 예: "memory_to_kb"
  description: string;
  required: boolean;
}

/**
 * 입력 파일 변수 정의
 * file_key 기반으로 FILE_* 환경 변수 생성
 */
export interface InputFileVariable {
  description: string;
  pattern: string;        // 예: "*.py"
  type?: 'file' | 'directory';
  required: boolean;
  file_key: string;       // 예: "python_script" → FILE_PYTHON_SCRIPT
}

/**
 * 출력 파일 변수 정의
 */
export interface OutputFileVariable {
  pattern: string;        // 예: "results_*"
  description: string;
  collect: boolean;
}

/**
 * Command Template 정의
 * Apptainer 이미지에 포함된 실행 명령어 템플릿
 */
export interface CommandTemplate {
  template_id: string;
  display_name: string;
  description: string;
  category: 'solver' | 'pre-processing' | 'post-processing' | 'utility';
  command: {
    executable: string;
    format: string;       // 예: "apptainer exec ${APPTAINER_IMAGE} python3 ${SCRIPT_FILE}"
    requires_mpi: boolean;
  };
  variables: {
    dynamic: Record<string, DynamicVariable>;
    input_files: Record<string, InputFileVariable>;
    output_files: Record<string, OutputFileVariable>;
  };
  pre_commands: string[];
  post_commands: string[];
}

export interface ApptainerImage {
  id: string;
  name: string;
  path: string;
  node: string;
  partition: string;
  type: 'viz' | 'compute' | 'custom';
  size: number;
  version: string;
  description: string;
  labels: Record<string, string>;
  apps: string[];
  runscript: string;
  env_vars: Record<string, string>;
  command_templates?: CommandTemplate[];  // 추가: Command Templates
  created_at: string;
  updated_at: string;
  last_scanned: string;
  is_active: number | boolean; // SQLite: 0/1, TypeScript: boolean
}

export interface ApptainerImagesResponse {
  images: ApptainerImage[];
}

export interface ApptainerImageMetadata {
  id: string;
  name: string;
  size: number;
  version: string;
  description: string;
  created_at: string;
  labels: Record<string, string>;
  env_vars: Record<string, string>;
  runscript: string;
  apps: string[];
}

export interface ApptainerScanResponse {
  status: string;
  message: string;
  scanned_nodes: string[];
  images_found: number;
  timestamp: string;
}

export type ApptainerFilterType = 'all' | 'viz' | 'compute' | 'custom';
export type ApptainerPartition = 'compute' | 'viz' | null;
