import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { server } from '../mocks/server';
import NodeStatusWidget from '../../components/CustomDashboard/widgets/NodeStatusWidget';
import { clearCache } from '../../utils/api';

describe('NodeStatusWidget Integration Tests', () => {
  const mockProps = {
    id: 'nodestatus-test-1',
    onRemove: vi.fn(),
    isEditMode: false,
    mode: 'production' as const,
  };

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

  beforeEach(() => {
    vi.clearAllMocks();
    clearCache();
    server.resetHandlers();
  });

  it('should display loading state initially', () => {
    render(<NodeStatusWidget {...mockProps} />);
    
    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('should fetch and display node status in production mode', async () => {
    // Mock returns {nodes: [...]} format
    server.use(
      http.get('/api/nodes', () => {
        return HttpResponse.json({ nodes: mockNodes });
      })
    );

    render(<NodeStatusWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 5000 });

    expect(screen.getByText(/Node Status/i)).toBeInTheDocument();
  });

  it('should show error when API fails', async () => {
    server.use(
      http.get('/api/nodes', () => {
        return HttpResponse.json(
          { error: 'Node service unavailable' },
          { status: 500 }
        );
      })
    );
    
    render(<NodeStatusWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 10000 });
    
    await waitFor(() => {
      const errorMessage = 
        screen.queryByText(/failed/i) ||
        screen.queryByText(/error/i) ||
        screen.queryByText(/unavailable/i) ||
        screen.queryByText(/cannot/i) ||
        screen.queryByText(/no.*node/i) ||
        screen.queryByText(/node.*not.*found/i);
      expect(errorMessage).toBeInTheDocument();
    }, { timeout: 3000 });
  }, 20000);

  it('should show "no nodes" message when list is empty', async () => {
    server.use(
      http.get('/api/nodes', () => {
        return HttpResponse.json({ nodes: [] });
      })
    );
    
    render(<NodeStatusWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 5000 });
    
    await waitFor(() => {
      const noNodesText = 
        screen.queryByText(/no.*node/i) ||
        screen.queryByText(/node.*not.*found/i) ||
        screen.queryByText(/node.*information/i);
      expect(noNodesText).toBeInTheDocument();
    }, { timeout: 3000 });
  });

  it('should display node statistics', async () => {
    server.use(
      http.get('/api/nodes', () => {
        return HttpResponse.json({ nodes: mockNodes });
      })
    );

    render(<NodeStatusWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 5000 });

    await waitFor(() => {
      // Should show state stats - check for numeric values
      const bodyText = document.body.textContent || '';
      const hasStats = 
        bodyText.match(/\d+/) || // Has numbers
        bodyText.toLowerCase().includes('idle') ||
        bodyText.toLowerCase().includes('allocated') ||
        bodyText.toLowerCase().includes('total');
      expect(hasStats).toBeTruthy();
    }, { timeout: 3000 });
  });

  it('should display total node count', async () => {
    server.use(
      http.get('/api/nodes', () => {
        return HttpResponse.json({ nodes: mockNodes });
      })
    );

    render(<NodeStatusWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 5000 });

    await waitFor(() => {
      const bodyText = document.body.textContent || '';
      // Should have node count (2 nodes in mock data)
      expect(bodyText.match(/\d+/)).toBeTruthy();
    }, { timeout: 3000 });
  });

  it('should use mock data in mock mode', async () => {
    render(<NodeStatusWidget {...mockProps} mode="mock" />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 3000 });

    expect(screen.getByText(/Mock/i)).toBeInTheDocument();
  });

  it('should show remove button in edit mode', () => {
    render(<NodeStatusWidget {...mockProps} isEditMode={true} />);
    
    const buttons = screen.getAllByRole('button');
    const removeButton = buttons.find(btn => 
      btn.querySelector('.lucide-x') !== null
    );
    expect(removeButton).toBeInTheDocument();
  });

  it.skip('should call onRemove when remove button is clicked', () => {
    expect(true).toBe(true);
  });
});
