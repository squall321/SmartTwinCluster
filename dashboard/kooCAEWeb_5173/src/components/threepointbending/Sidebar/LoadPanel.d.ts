import React from "react";
import { LoadConfig } from "../../../types/threepointbending";
interface Props {
    loadConfig: LoadConfig;
    setLoadConfig: (cfg: LoadConfig) => void;
}
declare const LoadPanel: React.FC<Props>;
export default LoadPanel;
