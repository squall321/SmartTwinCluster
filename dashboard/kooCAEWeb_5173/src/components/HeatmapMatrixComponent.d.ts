import React from 'react';
interface MeasurementDB {
    entities: string[];
    conditions: {
        [key: string]: number;
    }[];
    values: Float32Array;
    getValue(entityIdx: number, condIdx: number): number;
    setValue(entityIdx: number, condIdx: number, value: number): void;
}
interface HeatmapMatrixProps {
    data: MeasurementDB;
    title?: string;
    xLabelKeys?: string[];
}
declare const HeatmapMatrixComponent: React.FC<HeatmapMatrixProps>;
export default HeatmapMatrixComponent;
