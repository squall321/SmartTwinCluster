import React, { useEffect, useState } from 'react';
import { Select, Spin, Typography } from 'antd';
import { api } from '../api/axiosClient';
import { parseMaterialTxt, MaterialData } from '../components/MaterialParserWorker'; // ✅ 기존 유틸 함수 활용

const { Option } = Select;
const { Title } = Typography;

interface MaterialSelectorProps {
  onChange?: (materialName: string, materialData: MaterialData) => void;
  mode?: 'display' | 'all';
}

const MaterialSelectorComponent: React.FC<MaterialSelectorProps> = ({ onChange, mode = 'display' }) => {
  const [loading, setLoading] = useState(true);
  const [materialOptions, setMaterialOptions] = useState<string[]>([]);
  const [materialDict, setMaterialDict] = useState<Record<string, MaterialData>>({});
  const [selected, setSelected] = useState<string | null>(null);

  useEffect(() => {
    const fetchMaterial = async () => {
      setLoading(true);
      try {
        let url: string;
        if (mode === 'display') {
          url = `/api/materials/display`;
        } else {
          const listRes = await api.post(`/api/materials/all`);
          const fileList = listRes.data.files;
          const displayFile = fileList.find((f: any) => f.name === 'DisplayMaterial.txt');
          url = displayFile ? `${displayFile.url}` : `${fileList[0].url}`;
        }

        const res = await api.get(url, { responseType: 'text' });
        const parsed = parseMaterialTxt(res.data); // ✅ 여기서 가져다 씀
        setMaterialDict(parsed);
        setMaterialOptions(Object.keys(parsed));
      } catch (err) {
        console.error('📛 Material fetch 실패:', err);
      } finally {
        setLoading(false);
      }
    };

    fetchMaterial();
  }, [mode]);

  const handleChange = (value: string) => {
    setSelected(value);
    if (onChange && materialDict[value]) {
      onChange(value, materialDict[value]);
    }
  };

  return (
    <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
      <Title level={4}>🧾 재료 선택 ({mode === 'display' ? 'DisplayMaterial.txt' : 'All'})</Title>
      {loading ? (
        <Spin />
      ) : (
        <Select
          style={{ width: 400 }}
          showSearch
          placeholder="Material 이름 선택"
          onChange={handleChange}
          value={selected ?? undefined}
        >
          {materialOptions.map((name) => (
            <Option key={name} value={name}>
              {name}
            </Option>
          ))}
        </Select>
      )}
    </div>
  );
};

export default MaterialSelectorComponent;
