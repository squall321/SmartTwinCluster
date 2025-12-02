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
interface LineChartPerEntityProps {
    data: MeasurementDB;
    title?: string;
    xLabelKeys?: string[];
    selectedEntities?: string[];
}
declare const LineChartPerEntityComponent: React.FC<LineChartPerEntityProps>;
export default LineChartPerEntityComponent;
