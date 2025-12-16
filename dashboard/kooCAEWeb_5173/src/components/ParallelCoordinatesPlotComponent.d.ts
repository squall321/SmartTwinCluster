import React from 'react';
/**
 * MeasurementDB: 20 entities × 30 conditions
 */
interface MeasurementDB {
    entities: string[];
    conditions: {
        [key: string]: number;
    }[];
    values: Float32Array;
    getValue(entityIdx: number, condIdx: number): number;
    setValue(entityIdx: number, condIdx: number, value: number): void;
}
interface ParallelCoordsProps {
    data: MeasurementDB;
    angleKeys?: string[];
    valueKey?: string;
    title?: string;
}
/**
 * 🔷  ParallelCoordinatesPlotComponent
 *   - 축 : roll, pitch, yaw, stress
 *   - 색 : entity index를 기반으로 연속형 색상 매핑
 */
declare const ParallelCoordinatesPlotComponent: React.FC<ParallelCoordsProps>;
export default ParallelCoordinatesPlotComponent;
