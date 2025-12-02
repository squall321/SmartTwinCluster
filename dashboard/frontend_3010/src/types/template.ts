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

export interface TemplateMetadata {
  name: string;
  display_name?: string;
  description: string;
  version: string;
  author: string;
  tags: string[];
  requirements?: string[];
  is_public?: boolean;
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
  description: string;
  pattern?: string;
  extensions?: string[];
  max_size?: string;
  example?: string;
}

export interface ApptainerConfig {
  image_name: string;
  app?: string;
  bind?: string[];
  env?: Record<string, string>;
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
