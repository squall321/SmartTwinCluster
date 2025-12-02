import { jsx as _jsx } from "react/jsx-runtime";
import { createContext, useContext, useState } from 'react';
import { api } from '../api/axiosClient';
import { parseMaterialTxt } from './MaterialParserWorker';
const MaterialCacheContext = createContext(null);
export const MaterialCacheProvider = ({ children }) => {
    const [cache, setCache] = useState({});
    const getMaterials = async (mode) => {
        if (cache[mode])
            return cache[mode];
        let url;
        if (mode === 'display') {
            url = `/api/materials/display`;
        }
        else {
            const listRes = await api.post(`/api/materials/all`);
            const fileList = listRes.data.files;
            const displayFile = fileList.find((f) => f.name === 'DisplayMaterial.txt');
            url = displayFile ? `${api.defaults.baseURL}${displayFile.url}` : `${api.defaults.baseURL}${fileList[0].url}`;
        }
        const res = await api.get(url, { responseType: 'text' });
        const parsed = parseMaterialTxt(res.data);
        setCache(prev => ({ ...prev, [mode]: parsed }));
        return parsed;
    };
    return (_jsx(MaterialCacheContext.Provider, { value: { getMaterials }, children: children }));
};
// ✅ 이게 누락되면 오류 발생
export const useMaterialCache = () => {
    const ctx = useContext(MaterialCacheContext);
    if (!ctx)
        throw new Error('MaterialCacheProvider가 필요합니다.');
    return ctx;
};
