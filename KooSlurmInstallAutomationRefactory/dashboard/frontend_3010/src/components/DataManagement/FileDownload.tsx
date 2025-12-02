import React from 'react';
import { Download, FileArchive, Loader } from 'lucide-react';
import { API_CONFIG } from "../../config/api.config";

interface FileDownloadProps {
  filePath: string;
  filename?: string;
  storageType?: 'data' | 'scratch';
  node?: string;
  isDirectory?: boolean;
  onDownloadStart?: () => void;
  onDownloadComplete?: () => void;
  onDownloadError?: (error: string) => void;
}

const API_BASE_URL = API_CONFIG.API_BASE_URL;

const FileDownload: React.FC<FileDownloadProps> = ({
  filePath,
  filename,
  storageType = 'data',
  node,
  isDirectory = false,
  onDownloadStart,
  onDownloadComplete,
  onDownloadError
}) => {
  const [isDownloading, setIsDownloading] = React.useState(false);
  const [progress, setProgress] = React.useState(0);

  const downloadFile = async () => {
    try {
      setIsDownloading(true);
      setProgress(0);
      
      if (onDownloadStart) {
        onDownloadStart();
      }

      if (isDirectory) {
        // 디렉토리 다운로드 (tar.gz)
        const response = await fetch(`${API_BASE_URL}/api/download/directory`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            path: filePath,
            storage_type: storageType
          })
        });

        if (!response.ok) {
          const error = await response.json();
          throw new Error(error.error || 'Download failed');
        }

        // 파일 다운로드
        const blob = await response.blob();
        const url = window.URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `${filename || 'archive'}.tar.gz`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        window.URL.revokeObjectURL(url);

      } else {
        // 파일 다운로드
        const params = new URLSearchParams({
          path: filePath,
          storage_type: storageType
        });

        if (node) {
          params.append('node', node);
        }

        const response = await fetch(
          `${API_BASE_URL}/api/download/file?${params.toString()}`
        );

        if (!response.ok) {
          const error = await response.json();
          throw new Error(error.error || 'Download failed');
        }

        // 진행률 추적 (지원되는 경우)
        const contentLength = response.headers.get('content-length');
        const total = contentLength ? parseInt(contentLength, 10) : 0;

        if (total > 0 && response.body) {
          const reader = response.body.getReader();
          const chunks: Uint8Array[] = [];
          let received = 0;

          while (true) {
            const { done, value } = await reader.read();

            if (done) break;

            chunks.push(value);
            received += value.length;

            if (total > 0) {
              setProgress((received / total) * 100);
            }
          }

          // Blob 생성
          const blob = new Blob(chunks);
          const url = window.URL.createObjectURL(blob);
          const link = document.createElement('a');
          link.href = url;
          link.download = filename || filePath.split('/').pop() || 'download';
          document.body.appendChild(link);
          link.click();
          document.body.removeChild(link);
          window.URL.revokeObjectURL(url);

        } else {
          // 진행률 추적 불가능한 경우
          const blob = await response.blob();
          const url = window.URL.createObjectURL(blob);
          const link = document.createElement('a');
          link.href = url;
          link.download = filename || filePath.split('/').pop() || 'download';
          document.body.appendChild(link);
          link.click();
          document.body.removeChild(link);
          window.URL.revokeObjectURL(url);
        }
      }

      if (onDownloadComplete) {
        onDownloadComplete();
      }

    } catch (error) {
      console.error('Download failed:', error);
      
      if (onDownloadError) {
        onDownloadError(error instanceof Error ? error.message : 'Download failed');
      }

    } finally {
      setIsDownloading(false);
      setProgress(0);
    }
  };

  return (
    <button
      onClick={downloadFile}
      disabled={isDownloading}
      className={`
        inline-flex items-center gap-2 px-3 py-1.5 text-sm rounded-md
        transition-colors
        ${isDownloading
          ? 'bg-gray-100 text-gray-400 cursor-not-allowed'
          : 'bg-blue-500 text-white hover:bg-blue-600'
        }
      `}
      title={isDirectory ? 'Download as .tar.gz archive' : 'Download file'}
    >
      {isDownloading ? (
        <>
          <Loader className="w-4 h-4 animate-spin" />
          <span>
            {progress > 0 ? `${progress.toFixed(0)}%` : 'Downloading...'}
          </span>
        </>
      ) : (
        <>
          {isDirectory ? (
            <FileArchive className="w-4 h-4" />
          ) : (
            <Download className="w-4 h-4" />
          )}
          <span>Download</span>
        </>
      )}
    </button>
  );
};

export default FileDownload;
