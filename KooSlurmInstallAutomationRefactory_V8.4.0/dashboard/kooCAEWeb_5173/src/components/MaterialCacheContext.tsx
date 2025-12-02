import React, { createContext, useContext, useState, useEffect } from 'react';
import { api } from '../api/axiosClient';
import { parseMaterialTxt, MaterialData } from './MaterialParserWorker';

type Mode = 'display' | 'all';

interface MaterialCache {
  [mode: string]: Record<string, MaterialData>; // 'display' | 'all'
}

interface MaterialCacheContextType {
  getMaterials: (mode: Mode) => Promise<Record<string, MaterialData>>;
}

const MaterialCacheContext = createContext<MaterialCacheContextType | null>(null);

export const MaterialCacheProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {  
  const [cache, setCache] = useState<MaterialCache>({});

  const getMaterials = async (mode: Mode): Promise<Record<string, MaterialData>> => {
    if (cache[mode]) return cache[mode];

    let url: string;
    if (mode === 'display') {
      url = `/api/materials/display`;
    } else {
      const listRes = await api.post(`/api/materials/all`);
      const fileList = listRes.data.files;
      const displayFile = fileList.find((f: any) => f.name === 'DisplayMaterial.txt');
      url = displayFile ? `${api.defaults.baseURL}${displayFile.url}` : `${api.defaults.baseURL}${fileList[0].url}`;
    }

    const res = await api.get(url, { responseType: 'text' });
    const parsed = parseMaterialTxt(res.data);
    setCache(prev => ({ ...prev, [mode]: parsed }));
    return parsed;
  };

  return (
    <MaterialCacheContext.Provider value={{ getMaterials }}>
      {children}
    </MaterialCacheContext.Provider>
  );
};

// ✅ 이게 누락되면 오류 발생
export const useMaterialCache = () => {
    const ctx = useContext(MaterialCacheContext);
    if (!ctx) throw new Error('MaterialCacheProvider가 필요합니다.');
    return ctx;
  };