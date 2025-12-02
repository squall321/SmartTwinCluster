import { Button } from 'antd';
import { DownloadOutlined } from '@ant-design/icons';
import { useNavigate } from 'react-router-dom';

interface ExportMeshModifierButtonProps {
  kFile: File | null;
  kFileName: string;

  // 🔹 외부에서 주입된 옵션 파일 생성기 (File 객체를 반환)
  optionFileGenerator: () => File;

  solver?: string;
  mode?: string;

  optionFileName?: string;
  buttonLabel?: string;
}

const ExportMeshModifierButton: React.FC<ExportMeshModifierButtonProps> = ({
  kFile,
  kFileName,
  optionFileGenerator,
  solver = 'MeshModifier',
  mode = 'default',
  optionFileName = 'option.txt',
  buttonLabel = '🔁 해석 실행',
}) => {
  const navigate = useNavigate();

  const handleExportToFile = () => {
    const optionFile = optionFileGenerator();

    const link = document.createElement('a');
    link.href = URL.createObjectURL(optionFile);
    link.download = optionFileName;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const handleExportToStreamRunner = () => {
    const optionFile = optionFileGenerator();

    const state = {
      solver,
      mode,
      txtFiles: [optionFile],
      optFiles: kFile ? [kFile] : [],
      autoSubmit: true,
    };

    navigate('/tools/stream-runner', { state });
  };

  return (
    <div>
      <Button type="primary" icon={<DownloadOutlined />} onClick={handleExportToFile}>
        옵션파일 출력
      </Button>
      <Button style={{ marginLeft: 12 }} onClick={handleExportToStreamRunner}>
        {buttonLabel}
      </Button>
    </div>
  );
};

export default ExportMeshModifierButton;
