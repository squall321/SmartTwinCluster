import React from 'react';
import { MaterialData } from './MaterialParserWorker';
type Mode = 'display' | 'all';
interface MaterialCacheContextType {
    getMaterials: (mode: Mode) => Promise<Record<string, MaterialData>>;
}
export declare const MaterialCacheProvider: React.FC<{
    children: React.ReactNode;
}>;
export declare const useMaterialCache: () => MaterialCacheContextType;
export {};
