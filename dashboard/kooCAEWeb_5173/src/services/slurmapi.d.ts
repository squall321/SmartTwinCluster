export interface SinfoNode {
    partition: string;
    nodes: number;
    state: string;
    cpus?: number;
    mem_mb?: number;
}
export interface SqueueItem {
    job_id: string;
    name: string;
    user: string;
    state: string;
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
export declare const getSinfo: (signal?: AbortSignal) => Promise<SinfoNode[]>;
export declare const getSqueue: (signal?: AbortSignal) => Promise<SqueueItem[]>;
export declare const submitJob: (script: string) => Promise<SubmitJobResponse>;
export declare const cancelJob: (jobId: string) => Promise<GenericResponse>;
export declare const getJobStats: (signal?: AbortSignal) => Promise<JobStats>;
