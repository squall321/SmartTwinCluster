import { http, HttpResponse } from 'msw';

// Mock data
const mockCPUData = {
  status: 'success',
  data: {
    result: [
      {
        metric: { cpu: 'cpu0' },
        value: [1704067200, '85.5']
      },
      {
        metric: { cpu: 'cpu1' },
        value: [1704067200, '72.3']
      }
    ]
  }
};

const mockGPUData = {
  status: 'success',
  data: {
    result: [
      {
        metric: { gpu: '0', exported_instance: 'localhost' },
        value: [1704067200, '0.85']
      },
      {
        metric: { gpu: '1', exported_instance: 'localhost' },
        value: [1704067200, '0.45']
      }
    ]
  }
};

const mockMemoryData = {
  total: 128000,
  used: 96000,
  free: 32000,
  percent: 75
};

const mockJobs = [
  {
    id: '12345',
    name: 'test_job_1',
    state: 'RUNNING',
    user: 'user1',
    partition: 'gpu',
    nodes: 2,
    cpus: 16,
    start_time: '2024-01-01T10:00:00Z',
    time_limit: '24:00:00'
  },
  {
    id: '12346',
    name: 'test_job_2',
    state: 'PENDING',
    user: 'user2',
    partition: 'cpu',
    nodes: 1,
    cpus: 8,
    start_time: null,
    time_limit: '12:00:00'
  }
];

const mockNodes = [
  {
    name: 'node001',
    state: 'IDLE',
    cpus: 64,
    memory: 256000,
    partitions: ['gpu'],
    features: ['gpu', 'nvme']
  },
  {
    name: 'node002',
    state: 'ALLOCATED',
    cpus: 64,
    memory: 256000,
    partitions: ['gpu'],
    features: ['gpu', 'nvme']
  }
];

const mockStorage = {
  storages: [
    {
      name: '/home',
      path: '/home',
      used: 750,
      total: 1000,
      used_gb: 750,
      total_gb: 1000,
      percentage: 75,
      usage_percent: 75
    }
  ]
};

const mockNotifications = [
  {
    id: '1',
    type: 'info',
    title: 'Job Completed',
    message: 'Job test_job_1 has completed successfully',
    timestamp: '2024-01-01T12:00:00Z',
    read: false
  }
];

// API Handlers
export const handlers = [
  // Prometheus CPU endpoint
  http.get('/api/prometheus/query', ({ request }) => {
    const url = new URL(request.url);
    const query = url.searchParams.get('query');
    
    if (query?.includes('node_cpu_seconds_total')) {
      return HttpResponse.json(mockCPUData);
    }
    
    if (query?.includes('node_memory')) {
      return HttpResponse.json({
        status: 'success',
        data: {
          result: [
            { metric: {}, value: [1704067200, '128000000000'] }
          ]
        }
      });
    }
    
    // GPU queries
    if (query?.includes('nvidia_smi')) {
      return HttpResponse.json(mockGPUData);
    }
    
    return HttpResponse.json({ status: 'error', error: 'Unknown query' }, { status: 404 });
  }),

  // GPU endpoint
  http.get('/api/gpu/status', () => {
    return HttpResponse.json(mockGPUData);
  }),

  // Memory endpoint
  http.get('/api/system/memory', () => {
    return HttpResponse.json(mockMemoryData);
  }),

  // Slurm jobs endpoints - Support query parameters
  http.get('/api/slurm/jobs', ({ request }) => {
    const url = new URL(request.url);
    const limit = url.searchParams.get('limit');
    
    if (limit) {
      return HttpResponse.json(mockJobs.slice(0, parseInt(limit)));
    }
    return HttpResponse.json(mockJobs);
  }),

  // Alternative: /api/jobs endpoint (some widgets use this)
  http.get('/api/jobs', ({ request }) => {
    const url = new URL(request.url);
    const limit = url.searchParams.get('limit');
    
    if (limit) {
      return HttpResponse.json(mockJobs.slice(0, parseInt(limit)));
    }
    return HttpResponse.json(mockJobs);
  }),

  http.get('/api/slurm/jobs/:id', ({ params }) => {
    const job = mockJobs.find(j => j.id === params.id);
    if (job) {
      return HttpResponse.json(job);
    }
    return HttpResponse.json({ error: 'Job not found' }, { status: 404 });
  }),

  http.post('/api/slurm/submit', async ({ request }) => {
    const body = await request.json();
    return HttpResponse.json({
      success: true,
      job_id: '12347',
      message: 'Job submitted successfully'
    });
  }),

  http.delete('/api/slurm/jobs/:id', ({ params }) => {
    return HttpResponse.json({
      success: true,
      message: `Job ${params.id} cancelled`
    });
  }),

  // Slurm nodes endpoint - Support /api/nodes
  http.get('/api/slurm/nodes', () => {
    return HttpResponse.json({ nodes: mockNodes });
  }),

  // Alternative: /api/nodes endpoint
  http.get('/api/nodes', () => {
    return HttpResponse.json({ nodes: mockNodes });
  }),

  // Storage endpoints - FIXED: Support both /api/storage/info and /api/storage/usage
  http.get('/api/storage/info', () => {
    return HttpResponse.json(mockStorage);
  }),

  http.get('/api/storage/usage', () => {
    return HttpResponse.json(mockStorage);
  }),

  // Notifications endpoints - Support query parameters
  http.get('/api/notifications', ({ request }) => {
    const url = new URL(request.url);
    const limit = url.searchParams.get('limit');
    
    if (limit) {
      return HttpResponse.json(mockNotifications.slice(0, parseInt(limit)));
    }
    return HttpResponse.json(mockNotifications);
  }),

  http.post('/api/notifications', async ({ request }) => {
    const body = await request.json();
    return HttpResponse.json({
      success: true,
      id: '2'
    });
  }),

  // Error simulation endpoints
  http.get('/api/error/500', () => {
    return HttpResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }),

  http.get('/api/error/404', () => {
    return HttpResponse.json({ error: 'Not Found' }, { status: 404 });
  }),
];
