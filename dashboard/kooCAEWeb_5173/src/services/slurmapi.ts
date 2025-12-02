// services/slurmApi.ts
import { api } from '../api/axiosClient';

// --- 응답 타입(필요 수준만 선언, 실제 스키마에 맞춰 확장하세요) ---
export interface SinfoNode {
  partition: string;
  nodes: number;
  state: string;   // idle, mix, alloc ...
  cpus?: number;
  mem_mb?: number;
}

export interface SqueueItem {
  job_id: string;
  name: string;
  user: string;
  state: string;   // PD,R,CG,...
  time: string;
  partition?: string;
  nodes?: number;
}

export interface SubmitJobResponse {
  job_id: string;
  message?: string;
}

export interface GenericResponse {
  ok: boolean;
  message?: string;
}

export interface JobStats {
  running: number;
  pending: number;
  failed: number;
  completed: number;
  others?: number;
}

// --- axios 래핑: data만 반환 ---
export const getSinfo = async (signal?: AbortSignal) => {
  const { data } = await api.get<SinfoNode[]>('/slurm/sinfo', { signal });
  return data;
};

export const getSqueue = async (signal?: AbortSignal) => {
  const { data } = await api.get<SqueueItem[]>('/slurm/squeue', { signal });
  return data;
};

export const submitJob = async (script: string) => {
  const { data } = await api.post<SubmitJobResponse>('/slurm/submit', { script });
  return data;
};

export const cancelJob = async (jobId: string) => {
  const { data } = await api.delete<GenericResponse>(`/slurm/cancel/${encodeURIComponent(jobId)}`);
  return data;
};

export const getJobStats = async (signal?: AbortSignal) => {
  const { data } = await api.get<JobStats>('/slurm/job-stats', { signal });
  return data;
};
