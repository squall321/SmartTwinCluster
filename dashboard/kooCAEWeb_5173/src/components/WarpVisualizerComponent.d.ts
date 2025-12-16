import '@babylonjs/loaders';
interface WarpageInfo {
    rawData: number[][];
    xLength: number;
    yLength: number;
    scaleFactor: number;
}
interface WarpVisualizerComponentProps {
    warpageInfo: WarpageInfo | null;
}
declare const WarpVisualizerComponent: React.FC<WarpVisualizerComponentProps>;
export default WarpVisualizerComponent;
