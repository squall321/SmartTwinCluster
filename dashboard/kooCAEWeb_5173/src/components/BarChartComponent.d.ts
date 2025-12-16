import React from 'react';
interface BarChartProps {
    data: {
        name: string;
        number: number;
    }[];
    title?: string;
    color?: string;
    unitLabel?: string;
}
declare const BarChartComponent: React.FC<BarChartProps>;
export default BarChartComponent;
