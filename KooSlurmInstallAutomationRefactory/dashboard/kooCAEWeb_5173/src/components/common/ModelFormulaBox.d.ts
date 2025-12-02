import React from "react";
interface Props {
    title: string;
    description: string | React.ReactNode;
    formulas: string[];
}
declare const ModelFormulaBox: React.FC<Props>;
export default ModelFormulaBox;
