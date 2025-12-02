// services/slurmApi.ts
import { api } from '../api/axiosClient';
// --- axios 래핑: data만 반환 ---
export const getSinfo = async (signal) => {
    const { data } = await api.get('/slurm/sinfo', { signal });
    return data;
};
export const getSqueue = async (signal) => {
    const { data } = await api.get('/slurm/squeue', { signal });
    return data;
};
export const submitJob = async (script) => {
    const { data } = await api.post('/slurm/submit', { script });
    return data;
};
export const cancelJob = async (jobId) => {
    const { data } = await api.delete(`/slurm/cancel/${encodeURIComponent(jobId)}`);
    return data;
};
export const getJobStats = async (signal) => {
    const { data } = await api.get('/slurm/job-stats', { signal });
    return data;
};
