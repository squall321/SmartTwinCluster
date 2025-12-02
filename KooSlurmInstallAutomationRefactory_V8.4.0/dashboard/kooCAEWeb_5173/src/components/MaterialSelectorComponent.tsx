import React, { useEffect, useState } from 'react';
import { Select, Spin, Typography } from 'antd';
import { useMaterialCache } from './MaterialCacheContext';
import type { MaterialData } from './MaterialParserWorker';

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
  const { getMaterials } = useMaterialCache();

  useEffect(() => {
    const loadMaterials = async () => {
      setLoading(true);
      const parsed = await getMaterials(mode);
      setMaterialDict(parsed);
      setMaterialOptions(Object.keys(parsed));
      setLoading(false);
    };
    loadMaterials();
  }, [mode]);

  const handleChange = (value: string) => {
    setSelected(value);
    if (onChange && materialDict[value]) {
      onChange(value, materialDict[value]);
    }
  };

  return (
    <div style={{ padding: '1.5rem' }}>
      <Title level={4}>🧾 재료 선택 ({mode})</Title>
      {loading ? (
        <Spin />
      ) : (
        <Select
          style={{ width: 600 }}
          showSearch
          placeholder="Material 선택 (Type / Name / MID)"
          onChange={handleChange}
          value={selected ?? undefined}
          filterOption={(input, option) => {
            const val = option?.value || '';
            const data = materialDict[val];
            return (
              data?.name?.toLowerCase().includes(input.toLowerCase()) ||
              data?.type?.toLowerCase().includes(input.toLowerCase()) ||
              data?.id?.trim().includes(input)
            );
          }}
        >
          {materialOptions.map((key) => {
            const mat = materialDict[key];
            return (
              <Option key={key} value={key}>
                {mat.type} / {mat.name} (MID={mat.id.trim()})
              </Option>
            );
          })}
        </Select>
      )}
    </div>
  );
};

export default MaterialSelectorComponent;
