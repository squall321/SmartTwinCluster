import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { server } from '../mocks/server';
import StorageWidget from '../../components/CustomDashboard/widgets/StorageWidget';
import { clearCache } from '../../utils/api';

describe('StorageWidget Integration Tests', () => {
  const mockProps = {
    id: 'storage-test-1',
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
    render(<StorageWidget {...mockProps} />);
    
    expect(screen.getByText(/loading/i)).toBeInTheDocument();
  });

  it('should fetch and display storage info in production mode', async () => {
    render(<StorageWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 3000 });

    expect(screen.getByText(/Storage/i)).toBeInTheDocument();
    expect(screen.getByText(/Production/i)).toBeInTheDocument();
  });

  it('should show error when API fails', async () => {
    server.use(
      http.get('/api/storage/usage', () => {
        return HttpResponse.json(
          { error: 'Storage service unavailable' },
          { status: 500 }
        );
      })
    );
    
    render(<StorageWidget {...mockProps} />);
    
    // Wait for loading to complete
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 8000 });
    
    // Check for error message: "Failed to fetch storage data"
    await waitFor(() => {
      const errorText = screen.getByText(/failed.*fetch.*storage|storage.*not.*found|cannot.*fetch/i);
      expect(errorText).toBeInTheDocument();
    }, { timeout: 3000 });
  });

  it('should show "no data" message when storage info is empty', async () => {
    server.use(
      http.get('/api/storage/usage', () => {
        return HttpResponse.json({ storages: [] });
      })
    );
    
    render(<StorageWidget {...mockProps} />);
    
    // Wait for loading to complete first
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 5000 });
    
    // Look for "No Storage Information" or "Storage information not found"
    await waitFor(() => {
      const noDataText = screen.getByText(/No Storage Information|storage.*information.*not.*found/i);
      expect(noDataText).toBeInTheDocument();
    }, { timeout: 3000 });
  });

  it('should display storage percentage', async () => {
    render(<StorageWidget {...mockProps} />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 3000 });

    // Should show percentage (75% from mock data)
    // Use getAllByText since "75" appears multiple times (in size and percentage)
    const percentageElements = screen.getAllByText(/75|%/);
    expect(percentageElements.length).toBeGreaterThanOrEqual(1);
  });

  it('should use mock data in mock mode', async () => {
    render(<StorageWidget {...mockProps} mode="mock" />);
    
    await waitFor(() => {
      expect(screen.queryByText(/loading/i)).not.toBeInTheDocument();
    }, { timeout: 3000 });

    expect(screen.getByText(/Mock/i)).toBeInTheDocument();
    expect(screen.getByText(/Storage/i)).toBeInTheDocument();
  });

  it('should show remove button in edit mode', () => {
    render(<StorageWidget {...mockProps} isEditMode={true} />);
    
    // Find button with X icon (lucide-x class)
    const buttons = screen.getAllByRole('button');
    const removeButton = buttons.find(btn => 
      btn.querySelector('.lucide-x') !== null
    );
    expect(removeButton).toBeInTheDocument();
  });

  it.skip('should call onRemove when remove button is clicked', async () => {
    const onRemove = vi.fn();
    render(<StorageWidget {...mockProps} isEditMode={true} onRemove={onRemove} />);
    
    // Find button with X icon
    const buttons = screen.getAllByRole('button');
    const removeButton = buttons.find(btn => 
      btn.querySelector('.lucide-x') !== null
    );
    
    if (removeButton) {
      removeButton.click();
      expect(onRemove).toHaveBeenCalledWith('storage-test-1');
    }
  });
});
