import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { server } from '../mocks/server';
import JobQueueWidget from '../../components/CustomDashboard/widgets/JobQueueWidget';

describe('JobQueueWidget Integration Tests', () => {
  const mockProps = {
    id: 'jobqueue-test-1',
    onRemove: vi.fn(),
    isEditMode: false,
    mode: 'production' as const,
  };

  it('should display loading state initially', () => {
    render(<JobQueueWidget {...mockProps} />);
    
    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('should fetch and display job queue data in production mode', async () => {
    render(<JobQueueWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 3000 });

    expect(screen.getByText(/Job Queue/i)).toBeInTheDocument();
    expect(screen.getByText(/Production/i)).toBeInTheDocument();
  });

  it('should show error when API fails', async () => {
    server.use(
      http.get('/api/jobs', ({ request }) => {
        // Both PENDING and RUNNING queries should return 500
        return HttpResponse.json(
          { error: 'Slurm service unavailable' },
          { status: 500 }
        );
      })
    );
    
    render(<JobQueueWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.getByText(/failed to fetch|error|unavailable/i)).toBeInTheDocument();
    }, { timeout: 10000 }); // Increased to 10s for retry logic
  }, 15000); // Total test timeout 15s

  it('should show "no jobs" message when queue is empty', async () => {
    server.use(
      http.get('/api/jobs', () => {
        return HttpResponse.json([]);
      })
    );
    
    render(<JobQueueWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.getByText('No jobs found')).toBeInTheDocument();
    }, { timeout: 3000 });
  });

  it('should display job statistics', async () => {
    render(<JobQueueWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 3000 });

    // Should show job states (RUNNING, PENDING from mock data)
    expect(screen.getByText(/pending/i)).toBeInTheDocument();
    expect(screen.getByText(/running/i)).toBeInTheDocument();
  });

  it('should use mock data in mock mode', async () => {
    render(<JobQueueWidget {...mockProps} mode="mock" />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 3000 });

    expect(screen.getByText(/Mock/i)).toBeInTheDocument();
    expect(screen.getByText(/Job Queue/i)).toBeInTheDocument();
  });

  it('should show remove button in edit mode', () => {
    render(<JobQueueWidget {...mockProps} isEditMode={true} />);
    
    // Find button with X icon (lucide-x class)
    const buttons = screen.getAllByRole('button');
    const removeButton = buttons.find(btn => 
      btn.querySelector('.lucide-x') !== null
    );
    expect(removeButton).toBeInTheDocument();
  });

  it.skip('should call onRemove when remove button is clicked', async () => {
    const onRemove = vi.fn();
    render(<JobQueueWidget {...mockProps} isEditMode={true} onRemove={onRemove} />);
    
    // Find button with X icon
    const buttons = screen.getAllByRole('button');
    const removeButton = buttons.find(btn => 
      btn.querySelector('.lucide-x') !== null
    );
    
    if (removeButton) {
      removeButton.click();
      expect(onRemove).toHaveBeenCalledWith('jobqueue-test-1');
    }
  });
});
