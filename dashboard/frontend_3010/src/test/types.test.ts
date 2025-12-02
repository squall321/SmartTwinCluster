import { describe, it, expect } from 'vitest';
import type {
  Job,
  Node,
  Template,
  JobState,
} from '../types';

describe('Type Definitions', () => {
  describe('Job Type', () => {
    it('should create valid Job object', () => {
      const job: Job = {
        id: '1',
        name: 'test-job',
        user: 'testuser',
        state: 'RUNNING',
        partition: 'gpu',
        nodes: 1,
        cpus: 4,
        memory: '16GB',
        timeLimit: '24:00:00',
        qos: 'normal',
        submitTime: '2025-10-08T10:00:00Z',
      };

      expect(job.id).toBe('1');
      expect(job.state).toBe('RUNNING');
      expect(job.nodes).toBe(1);
    });

    it('should have valid JobState values', () => {
      const states: JobState[] = [
        'PENDING',
        'RUNNING',
        'COMPLETED',
        'FAILED',
        'CANCELLED',
        'TIMEOUT',
        'NODE_FAIL'
      ];

      states.forEach(state => {
        expect(typeof state).toBe('string');
        expect(state.length).toBeGreaterThan(0);
      });
    });
  });

  describe('Node Type', () => {
    it('should create valid Node object', () => {
      const node: Node = {
        id: '1',
        name: 'node001',
        state: 'IDLE',
        partition: 'gpu',
        cpus: 32,
        cpusAllocated: 0,
        memory: 128,
        memoryAllocated: 0,
      };

      expect(node.id).toBe('1');
      expect(node.name).toBe('node001');
      expect(node.cpus).toBe(32);
    });
  });

  describe('Template Type', () => {
    it('should create valid Template object', () => {
      const template: Template = {
        id: '1',
        name: 'PyTorch Training',
        description: 'Test',
        category: 'ml',
        shared: true,
        config: {
          partition: 'gpu',
          nodes: 1,
          cpus: 8,
          memory: '32GB',
          time: '24:00:00',
          script: '#!/bin/bash',
        },
        created_by: 'admin',
        created_at: '2025-10-08',
        updated_at: '2025-10-08',
        usage_count: 0,
      };

      expect(template.id).toBe('1');
      expect(template.category).toBe('ml');
      expect(template.config.nodes).toBe(1);
    });
  });
});
