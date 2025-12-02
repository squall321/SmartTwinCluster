import { 
  StorageStats, 
  Dataset, 
  NodeScratchData, 
  FileItem,
  TransferTask,
  StorageAnalytics 
} from '../types';

// Helper function to generate random sizes
const generateSize = (minGB: number, maxGB: number): { size: string; bytes: number } => {
  const gb = minGB + Math.random() * (maxGB - minGB);
  const bytes = Math.floor(gb * 1024 * 1024 * 1024);
  
  if (gb < 1) {
    return { size: `${Math.floor(gb * 1024)} MB`, bytes };
  } else if (gb < 1024) {
    return { size: `${gb.toFixed(1)} GB`, bytes };
  } else {
    return { size: `${(gb / 1024).toFixed(1)} TB`, bytes };
  }
};

// Helper function to generate random dates
const generateDate = (daysAgo: number): string => {
  const date = new Date();
  date.setDate(date.getDate() - daysAgo);
  return date.toISOString();
};

const formatTimeAgo = (daysAgo: number): string => {
  if (daysAgo === 0) return 'Today';
  if (daysAgo === 1) return '1 day ago';
  if (daysAgo < 7) return `${daysAgo} days ago`;
  if (daysAgo < 30) return `${Math.floor(daysAgo / 7)} weeks ago`;
  if (daysAgo < 365) return `${Math.floor(daysAgo / 30)} months ago`;
  return `${Math.floor(daysAgo / 365)} years ago`;
};

// Mock Shared Storage Stats
export const mockStorageStats: StorageStats = {
  totalCapacity: '100 TB',
  usedSpace: '45.2 TB',
  availableSpace: '54.8 TB',
  usagePercent: 45.2,
  datasetCount: 127,
  fileCount: 45823,
  lastAnalysis: '2 hours ago'
};

// Mock Datasets
export const mockDatasets: Dataset[] = [
  {
    id: 'ds-001',
    name: 'ML Training Dataset 2024',
    path: '/data/datasets/ml_training_2024',
    ...generateSize(2, 3),
    fileCount: 15420,
    createdAt: generateDate(30),
    lastAccessed: formatTimeAgo(0),
    owner: 'research_team',
    group: 'ml_lab',
    status: 'active',
    tags: ['machine-learning', 'training', 'images']
  },
  {
    id: 'ds-002',
    name: 'Simulation Results Q4',
    path: '/data/results/simulation_q4',
    ...generateSize(5, 6),
    fileCount: 8932,
    createdAt: generateDate(90),
    lastAccessed: formatTimeAgo(1),
    owner: 'sim_group',
    group: 'physics',
    status: 'active',
    tags: ['simulation', 'physics', 'q4-2024']
  },
  {
    id: 'ds-003',
    name: 'Archive 2023',
    path: '/data/archive/2023',
    ...generateSize(10, 15),
    fileCount: 21471,
    createdAt: generateDate(365),
    lastAccessed: formatTimeAgo(30),
    owner: 'admin',
    group: 'archive',
    status: 'archived',
    tags: ['archive', '2023']
  },
  {
    id: 'ds-004',
    name: 'Genomics Project Alpha',
    path: '/data/projects/genomics_alpha',
    ...generateSize(8, 10),
    fileCount: 32104,
    createdAt: generateDate(120),
    lastAccessed: formatTimeAgo(2),
    owner: 'bio_team',
    group: 'genomics',
    status: 'active',
    tags: ['genomics', 'dna', 'sequencing']
  },
  {
    id: 'ds-005',
    name: 'Climate Data 2020-2024',
    path: '/data/datasets/climate_2020_2024',
    ...generateSize(15, 20),
    fileCount: 45823,
    createdAt: generateDate(180),
    lastAccessed: formatTimeAgo(5),
    owner: 'climate_lab',
    group: 'earth_science',
    status: 'active',
    tags: ['climate', 'weather', 'timeseries']
  },
  {
    id: 'ds-006',
    name: 'Video Processing Dataset',
    path: '/data/datasets/video_processing',
    ...generateSize(3, 5),
    fileCount: 2847,
    createdAt: generateDate(45),
    lastAccessed: formatTimeAgo(0),
    owner: 'video_team',
    group: 'media',
    status: 'processing',
    tags: ['video', 'processing', 'ai']
  },
  {
    id: 'ds-007',
    name: 'Financial Models 2024',
    path: '/data/projects/financial_models',
    ...generateSize(1, 2),
    fileCount: 5621,
    createdAt: generateDate(60),
    lastAccessed: formatTimeAgo(3),
    owner: 'finance_team',
    group: 'economics',
    status: 'active',
    tags: ['finance', 'models', 'economics']
  },
  {
    id: 'ds-008',
    name: 'Archive 2022',
    path: '/data/archive/2022',
    ...generateSize(12, 18),
    fileCount: 38291,
    createdAt: generateDate(730),
    lastAccessed: formatTimeAgo(60),
    owner: 'admin',
    group: 'archive',
    status: 'archived',
    tags: ['archive', '2022']
  }
];

// Mock Scratch Storage Nodes
export const mockScratchNodes: NodeScratchData[] = [
  {
    nodeId: 'node-001',
    nodeName: 'compute-001',
    totalSpace: '2 TB',
    totalSpaceBytes: 2 * 1024 * 1024 * 1024 * 1024,
    usedSpace: '1.2 TB',
    usedSpaceBytes: 1.2 * 1024 * 1024 * 1024 * 1024,
    availableSpace: '800 GB',
    availableSpaceBytes: 800 * 1024 * 1024 * 1024,
    usagePercent: 60,
    fileCount: 3421,
    status: 'online',
    lastUpdated: new Date().toISOString(),
    directories: [
      {
        id: 'dir-001',
        name: 'job_12345_output',
        path: '/scratch/job_12345_output',
        ...generateSize(0.4, 0.5),
        fileCount: 1203,
        createdAt: generateDate(2),
        lastModified: formatTimeAgo(2),
        owner: 'user_a',
        group: 'research',
        jobId: '12345'
      },
      {
        id: 'dir-002',
        name: 'temp_processing',
        path: '/scratch/temp_processing',
        ...generateSize(0.3, 0.4),
        fileCount: 847,
        createdAt: generateDate(5),
        lastModified: formatTimeAgo(5),
        owner: 'user_b',
        group: 'ml_lab',
        jobId: '12340'
      },
      {
        id: 'dir-003',
        name: 'checkpoint_data',
        path: '/scratch/checkpoint_data',
        ...generateSize(0.2, 0.3),
        fileCount: 421,
        createdAt: generateDate(1),
        lastModified: formatTimeAgo(0),
        owner: 'user_a',
        group: 'research'
      }
    ]
  },
  {
    nodeId: 'node-002',
    nodeName: 'compute-002',
    totalSpace: '2 TB',
    totalSpaceBytes: 2 * 1024 * 1024 * 1024 * 1024,
    usedSpace: '450 GB',
    usedSpaceBytes: 450 * 1024 * 1024 * 1024,
    availableSpace: '1.5 TB',
    availableSpaceBytes: 1.5 * 1024 * 1024 * 1024 * 1024,
    usagePercent: 22.5,
    fileCount: 892,
    status: 'online',
    lastUpdated: new Date().toISOString(),
    directories: [
      {
        id: 'dir-004',
        name: 'simulation_data',
        path: '/scratch/simulation_data',
        ...generateSize(0.25, 0.3),
        fileCount: 521,
        createdAt: generateDate(1),
        lastModified: formatTimeAgo(1),
        owner: 'user_c',
        group: 'physics',
        jobId: '12348'
      },
      {
        id: 'dir-005',
        name: 'temp_export',
        path: '/scratch/temp_export',
        ...generateSize(0.15, 0.2),
        fileCount: 371,
        createdAt: generateDate(3),
        lastModified: formatTimeAgo(3),
        owner: 'user_c',
        group: 'physics'
      }
    ]
  },
  {
    nodeId: 'node-003',
    nodeName: 'compute-003',
    totalSpace: '2 TB',
    totalSpaceBytes: 2 * 1024 * 1024 * 1024 * 1024,
    usedSpace: '1.8 TB',
    usedSpaceBytes: 1.8 * 1024 * 1024 * 1024 * 1024,
    availableSpace: '200 GB',
    availableSpaceBytes: 200 * 1024 * 1024 * 1024,
    usagePercent: 90,
    fileCount: 5621,
    status: 'online',
    lastUpdated: new Date().toISOString(),
    directories: [
      {
        id: 'dir-006',
        name: 'large_dataset',
        path: '/scratch/large_dataset',
        ...generateSize(0.9, 1.0),
        fileCount: 3120,
        createdAt: generateDate(7),
        lastModified: formatTimeAgo(7),
        owner: 'user_d',
        group: 'genomics',
        jobId: '12330'
      },
      {
        id: 'dir-007',
        name: 'checkpoint_files',
        path: '/scratch/checkpoint_files',
        ...generateSize(0.6, 0.7),
        fileCount: 2301,
        createdAt: generateDate(3),
        lastModified: formatTimeAgo(3),
        owner: 'user_d',
        group: 'genomics',
        jobId: '12342'
      },
      {
        id: 'dir-008',
        name: 'analysis_temp',
        path: '/scratch/analysis_temp',
        ...generateSize(0.2, 0.25),
        fileCount: 200,
        createdAt: generateDate(1),
        lastModified: formatTimeAgo(0),
        owner: 'user_d',
        group: 'genomics'
      }
    ]
  },
  {
    nodeId: 'node-004',
    nodeName: 'compute-004',
    totalSpace: '2 TB',
    totalSpaceBytes: 2 * 1024 * 1024 * 1024 * 1024,
    usedSpace: '320 GB',
    usedSpaceBytes: 320 * 1024 * 1024 * 1024,
    availableSpace: '1.68 TB',
    availableSpaceBytes: 1.68 * 1024 * 1024 * 1024 * 1024,
    usagePercent: 16,
    fileCount: 654,
    status: 'online',
    lastUpdated: new Date().toISOString(),
    directories: [
      {
        id: 'dir-009',
        name: 'video_render',
        path: '/scratch/video_render',
        ...generateSize(0.25, 0.32),
        fileCount: 654,
        createdAt: generateDate(2),
        lastModified: formatTimeAgo(2),
        owner: 'user_e',
        group: 'media',
        jobId: '12355'
      }
    ]
  },
  {
    nodeId: 'node-005',
    nodeName: 'compute-005',
    totalSpace: '2 TB',
    totalSpaceBytes: 2 * 1024 * 1024 * 1024 * 1024,
    usedSpace: '1.5 TB',
    usedSpaceBytes: 1.5 * 1024 * 1024 * 1024 * 1024,
    availableSpace: '500 GB',
    availableSpaceBytes: 500 * 1024 * 1024 * 1024,
    usagePercent: 75,
    fileCount: 4231,
    status: 'online',
    lastUpdated: new Date().toISOString(),
    directories: [
      {
        id: 'dir-010',
        name: 'training_logs',
        path: '/scratch/training_logs',
        ...generateSize(0.8, 0.9),
        fileCount: 2841,
        createdAt: generateDate(4),
        lastModified: formatTimeAgo(0),
        owner: 'user_f',
        group: 'ml_lab',
        jobId: '12360'
      },
      {
        id: 'dir-011',
        name: 'model_checkpoints',
        path: '/scratch/model_checkpoints',
        ...generateSize(0.6, 0.7),
        fileCount: 1390,
        createdAt: generateDate(4),
        lastModified: formatTimeAgo(1),
        owner: 'user_f',
        group: 'ml_lab',
        jobId: '12360'
      }
    ]
  }
];

// Mock File Browser Data
export const generateMockFiles = (path: string): FileItem[] => {
  const baseName = path.split('/').pop() || 'root';
  
  const fileTypes = [
    { ext: '.txt', mime: 'text/plain' },
    { ext: '.csv', mime: 'text/csv' },
    { ext: '.json', mime: 'application/json' },
    { ext: '.py', mime: 'text/x-python' },
    { ext: '.log', mime: 'text/plain' },
    { ext: '.dat', mime: 'application/octet-stream' },
    { ext: '.h5', mime: 'application/x-hdf' },
    { ext: '.png', mime: 'image/png' },
    { ext: '.jpg', mime: 'image/jpeg' },
  ];

  const files: FileItem[] = [];
  
  // Add some directories
  const dirCount = Math.floor(Math.random() * 5) + 2;
  for (let i = 0; i < dirCount; i++) {
    const name = ['analysis', 'data', 'results', 'scripts', 'models', 'logs', 'temp'][i % 7];
    files.push({
      id: `dir-${path}-${i}`,
      name,
      path: `${path}/${name}`,
      type: 'directory',
      ...generateSize(0.5, 5),
      permissions: 'drwxr-xr-x',
      owner: ['user_a', 'user_b', 'user_c'][Math.floor(Math.random() * 3)],
      group: ['research', 'ml_lab', 'physics'][Math.floor(Math.random() * 3)],
      modifiedAt: generateDate(Math.floor(Math.random() * 30))
    });
  }

  // Add some files
  const fileCount = Math.floor(Math.random() * 10) + 5;
  for (let i = 0; i < fileCount; i++) {
    const fileType = fileTypes[Math.floor(Math.random() * fileTypes.length)];
    const name = `file_${i + 1}${fileType.ext}`;
    files.push({
      id: `file-${path}-${i}`,
      name,
      path: `${path}/${name}`,
      type: 'file',
      ...generateSize(0.001, 1),
      permissions: '-rw-r--r--',
      owner: ['user_a', 'user_b', 'user_c'][Math.floor(Math.random() * 3)],
      group: ['research', 'ml_lab', 'physics'][Math.floor(Math.random() * 3)],
      modifiedAt: generateDate(Math.floor(Math.random() * 30)),
      mimeType: fileType.mime,
      extension: fileType.ext
    });
  }

  return files;
};

// Mock Transfer Tasks
export const mockTransferTasks: TransferTask[] = [
  {
    id: 'task-001',
    type: 'move',
    source: '/scratch/job_12345_output',
    destination: '/data/from_scratch/job_12345_output',
    status: 'running',
    progress: 67,
    speed: '125 MB/s',
    eta: '2m 15s',
    startTime: new Date(Date.now() - 180000).toISOString(),
    fileCount: 1203,
    totalSize: '450 GB'
  },
  {
    id: 'task-002',
    type: 'copy',
    source: '/data/datasets/ml_training_2024',
    destination: '/scratch/temp_ml_data',
    status: 'completed',
    progress: 100,
    startTime: new Date(Date.now() - 600000).toISOString(),
    endTime: new Date(Date.now() - 300000).toISOString(),
    fileCount: 15420,
    totalSize: '2.4 TB'
  },
  {
    id: 'task-003',
    type: 'delete',
    source: '/scratch/old_checkpoint',
    status: 'pending',
    progress: 0,
    fileCount: 842,
    totalSize: '320 GB'
  }
];

// Mock Storage Analytics
export const mockStorageAnalytics: StorageAnalytics = {
  fileTypeDistribution: [
    { type: '.h5 (HDF5)', count: 15420, ...generateSize(8, 10), percent: 35 },
    { type: '.dat (Data)', count: 12840, ...generateSize(6, 8), percent: 28 },
    { type: '.csv (CSV)', count: 8932, ...generateSize(2, 3), percent: 12 },
    { type: '.txt (Text)', count: 5621, ...generateSize(0.5, 1), percent: 8 },
    { type: '.json (JSON)', count: 3847, ...generateSize(1, 2), percent: 7 },
    { type: 'Images', count: 2104, ...generateSize(1.5, 2), percent: 6 },
    { type: 'Other', count: 1847, ...generateSize(1, 1.5), percent: 4 }
  ],
  topUsers: [
    { user: 'user_d', ...generateSize(8, 10), fileCount: 15420, percent: 22 },
    { user: 'user_a', ...generateSize(6, 8), fileCount: 12305, percent: 18 },
    { user: 'climate_lab', ...generateSize(15, 20), fileCount: 45823, percent: 42 },
    { user: 'bio_team', ...generateSize(8, 10), fileCount: 32104, percent: 22 },
    { user: 'user_c', ...generateSize(3, 4), fileCount: 5621, percent: 8 }
  ],
  usageTrend: [
    { date: '2024-10-01', used: 38.2, percent: 38.2 },
    { date: '2024-10-08', used: 39.5, percent: 39.5 },
    { date: '2024-10-15', used: 41.0, percent: 41.0 },
    { date: '2024-10-22', used: 42.8, percent: 42.8 },
    { date: '2024-10-29', used: 43.5, percent: 43.5 },
    { date: '2024-11-05', used: 44.2, percent: 44.2 },
    { date: '2024-11-12', used: 45.2, percent: 45.2 }
  ],
  largestDirectories: [
    { path: '/data/datasets/climate_2020_2024', ...generateSize(15, 20), fileCount: 45823 },
    { path: '/data/archive/2023', ...generateSize(10, 15), fileCount: 21471 },
    { path: '/data/projects/genomics_alpha', ...generateSize(8, 10), fileCount: 32104 },
    { path: '/data/results/simulation_q4', ...generateSize(5, 6), fileCount: 8932 },
    { path: '/data/datasets/video_processing', ...generateSize(3, 5), fileCount: 2847 }
  ]
};
