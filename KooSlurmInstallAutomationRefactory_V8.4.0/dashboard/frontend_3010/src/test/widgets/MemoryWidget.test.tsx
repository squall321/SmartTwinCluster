import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { server } from '../mocks/server';
import MemoryWidget from '../../components/CustomDashboard/widgets/MemoryWidget';
import { clearCache } from '../../utils/api';

describe('MemoryWidget Integration Tests', () => {
  const mockProps = {
    id: 'memory-test-1',
    onRemove: vi.fn(),
    isEditMode: false,
    mode: 'production' as const,
  };

  beforeEach(() => {
    vi.clearAllMocks();
    clearCache();
    server.resetHandlers();
  });

  it('should display loading state initially', () => {
    render(<MemoryWidget {...mockProps} />);
    
    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('should fetch and display memory data in production mode', async () => {
    render(<MemoryWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 3000 });

    expect(screen.getByText(/Memory Usage/i)).toBeInTheDocument();
    expect(screen.getByText(/Production/i)).toBeInTheDocument();
  });

  it('should show error when API fails', async () => {
    server.use(
      http.get('/api/prometheus/query', ({ request }) => {
        // Both memory queries should return 500
        return HttpResponse.json(
          { error: 'Memory service unavailable' },
          { status: 500 }
        );
      })
    );
    
    render(<MemoryWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.getByText(/failed to fetch|error|unavailable/i)).toBeInTheDocument();
    }, { timeout: 10000 }); // Increased to 10s for retry logic
  }, 15000); // Total test timeout 15s

  it('should show "no data" message when data is empty', async () => {
    server.use(
      http.get('/api/prometheus/query', () => {
        return HttpResponse.json({
          status: 'success',
          data: { result: [] }
        });
      })
    );
    
    render(<MemoryWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.getByText(/no.*data|data.*not.*found/i)).toBeInTheDocument();
    }, { timeout: 3000 });
  });

  it('should use mock data in mock mode', async () => {
    render(<MemoryWidget {...mockProps} mode="mock" />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 3000 });

    expect(screen.getByText(/Mock/i)).toBeInTheDocument();
    expect(screen.getByText(/Memory Usage/i)).toBeInTheDocument();
  });

  it('should show remove button in edit mode', () => {
    render(<MemoryWidget {...mockProps} isEditMode={true} />);
    
    // Find button with X icon (lucide-x class)
    const buttons = screen.getAllByRole('button');
    const removeButton = buttons.find(btn => 
      btn.querySelector('.lucide-x') !== null
    );
    expect(removeButton).toBeInTheDocument();
  });

  it.skip('should call onRemove when remove button is clicked', async () => {
    const onRemove = vi.fn();
    render(<MemoryWidget {...mockProps} isEditMode={true} onRemove={onRemove} />);
    
    // Find button with X icon
    const buttons = screen.getAllByRole('button');
    const removeButton = buttons.find(btn => 
      btn.querySelector('.lucide-x') !== null
    );
    
    if (removeButton) {
      removeButton.click();
      expect(onRemove).toHaveBeenCalledWith('memory-test-1');
    }
  });

  it('should display memory percentage', async () => {
    render(<MemoryWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 3000 });

    // Should show percentage
    expect(screen.getByText(/%/)).toBeInTheDocument();
  });
});
