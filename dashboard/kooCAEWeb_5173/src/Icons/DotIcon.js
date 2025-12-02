import { jsx as _jsx } from "react/jsx-runtime";
const DotIcon = ({ pattern, size = 48, color = "black" }) => {
    // 도트 패턴 정의 (x, y 좌표)
    const patterns = {
        "1x1": [[0, 0]],
        "3x3": [
            [0, 0], [1, 0], [2, 0],
            [0, 1], [1, 1], [2, 1],
            [0, 2], [1, 2], [2, 2],
        ],
        "1x3": [[0, 0], [0, 1], [0, 2]],
        "3x1": [[0, 0], [1, 0], [2, 0]],
        "2x2": [[0, 0], [1, 0], [0, 1], [1, 1]],
        "2x1": [[0, 0], [1, 0]],
        "1x2": [[0, 0], [0, 1]],
    };
    const dots = patterns[pattern];
    const radius = 4;
    const spacing = 12;
    // 패턴의 최대 너비와 높이 계산
    const maxX = Math.max(...dots.map(([x, _]) => x));
    const maxY = Math.max(...dots.map(([_, y]) => y));
    const patternWidth = maxX * spacing;
    const patternHeight = maxY * spacing;
    // 중앙 정렬 오프셋 계산 (기준 viewBox: 48x48)
    const offsetX = (48 - patternWidth) / 2;
    const offsetY = (48 - patternHeight) / 2;
    return (_jsx("svg", { width: size, height: size, viewBox: "0 0 48 48", fill: color, xmlns: "http://www.w3.org/2000/svg", children: dots.map(([x, y], i) => (_jsx("circle", { cx: offsetX + x * spacing, cy: offsetY + y * spacing, r: radius }, i))) }));
};
export default DotIcon;
