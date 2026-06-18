/**
 * Template Type Definitions
 * Phase 2 Frontend - Template Management
 */

export interface Template {
  id?: string;
  template_id: string;
  file_path: string;
  file_name?: string;
  file_size: number;
  file_hash: string;
  source: string; // 'official' | 'community' | 'private' | 'private:username'
  category: string;
  template: TemplateMetadata;
  slurm?: SlurmConfig;
  files?: FilesSchema;
  apptainer?: ApptainerConfig;
  apptainer_normalized?: ApptainerNormalizedConfig;
  script?: ScriptConfig;
  created_at?: string;
  updated_at?: string;
  last_scanned?: string;
  last_modified?: string;
  is_active?: number | boolean;
}

export interface TemplateMetadataConfig {
  partition?: string;
  nodes?: number;
  cpus?: number;
  memory?: string;
  time?: string;
}

export interface TemplateMetadata {
  id?: string;
  name: string;
  display_name?: string;
  description: string;
  category?: string;
  version: string;
  author: string;
  tags: string[];
  requirements?: string[];
  is_public?: boolean;
  config?: TemplateMetadataConfig;
}

export interface SlurmConfig {
  partition: string;
  nodes?: number;
  ntasks?: number;
  cpus_per_task?: number;
  mem?: string;
  time?: string;
  gres?: string;
  qos?: string;
}

export interface ApptainerNormalizedConfig {
  mode: 'fixed' | 'partition' | 'specific' | 'any';
  partition?: string;
  default_image?: string;
  allowed_images?: string[];
  user_selectable?: boolean;
  image_name?: string;
}

export interface ScriptConfig {
  pre_exec?: string;
  main_exec?: string;
  post_exec?: string;
}

export interface FilesSchema {
  input_schema?: FileSchema;
  output_schema?: FileSchema;
}

export interface FileSchema {
  required?: FileRequirement[];
  optional?: FileRequirement[];
}

export interface FileRequirement {
  name?: string;
  file_key?: string;
  description: string;
  pattern?: string;
  type?: 'file' | 'directory';
  extensions?: string[];
  max_size?: string;
  example?: string;
}

export interface ApptainerImageSelection {
  mode: 'fixed' | 'partition' | 'specific' | 'any';
  partition?: string;
  default_image?: string;
  allowed_images?: string[];
  required?: boolean;
}

export interface ApptainerConfig {
  image_name: string;
  app?: string;
  bind?: string[];
  env?: Record<string, string>;
  image_selection?: ApptainerImageSelection;
}

export interface TemplatesResponse {
  templates: Template[];
  total: number;
}

export interface TemplateCategory {
  name: string;
  count: number;
  icon?: string;
}

export type TemplateSource = 'all' | 'official' | 'community' | 'private';
