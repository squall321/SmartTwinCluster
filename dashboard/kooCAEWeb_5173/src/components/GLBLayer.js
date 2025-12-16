import { jsx as _jsx } from "react/jsx-runtime";
import { useEffect, useState } from "react";
import { Layer, Rect } from "react-konva";
import * as BABYLON from "@babylonjs/core";
import "@babylonjs/loaders/glTF";
const GLBLayer = ({ glbUrl, glbFile, voxelCount = 100, onBounds, }) => {
    const [grid, setGrid] = useState([]);
    const [gridSize, setGridSize] = useState({
        cols: 0,
        rows: 0,
    });
    const [bounds, setBounds] = useState(null);
    useEffect(() => {
        if (!glbFile && !glbUrl)
            return;
        let blobUrl = null;
        let urlToLoad;
        if (glbFile) {
            blobUrl = URL.createObjectURL(glbFile);
            urlToLoad = blobUrl;
        }
        else if (glbUrl) {
            urlToLoad = glbUrl;
        }
        else {
            return;
        }
        const engine = new BABYLON.NullEngine();
        const scene = new BABYLON.Scene(engine);
        BABYLON.SceneLoader.ImportMesh(null, "", urlToLoad, scene, (meshes) => {
            let xmin = +Infinity;
            let xmax = -Infinity;
            let ymin = +Infinity;
            let ymax = -Infinity;
            const triangles = [];
            meshes.forEach((mesh) => {
                const geometry = mesh.geometry;
                if (!geometry)
                    return;
                const positions = geometry.getVerticesData(BABYLON.VertexBuffer.PositionKind);
                const indices = geometry.getIndices();
                if (!positions || !indices)
                    return;
                for (let i = 0; i < indices.length; i += 3) {
                    const p0 = new BABYLON.Vector2(positions[indices[i] * 3], positions[indices[i] * 3 + 1]);
                    const p1 = new BABYLON.Vector2(positions[indices[i + 1] * 3], positions[indices[i + 1] * 3 + 1]);
                    const p2 = new BABYLON.Vector2(positions[indices[i + 2] * 3], positions[indices[i + 2] * 3 + 1]);
                    xmin = Math.min(xmin, p0.x, p1.x, p2.x);
                    xmax = Math.max(xmax, p0.x, p1.x, p2.x);
                    ymin = Math.min(ymin, p0.y, p1.y, p2.y);
                    ymax = Math.max(ymax, p0.y, p1.y, p2.y);
                    triangles.push([p0, p1, p2]);
                }
            });
            if (triangles.length === 0) {
                console.log("No triangles found in GLB");
                return;
            }
            const modelWidth = xmax - xmin;
            const modelHeight = ymax - ymin;
            const longest = Math.max(modelWidth, modelHeight);
            const cellSize = longest / voxelCount;
            const cols = Math.ceil(modelWidth / cellSize);
            const rows = Math.ceil(modelHeight / cellSize);
            const gridArray = Array.from({ length: rows }, () => Array(cols).fill(false));
            // Triangles → grid
            for (const tri of triangles) {
                const [a, b, c] = tri;
                const triXmin = Math.min(a.x, b.x, c.x);
                const triXmax = Math.max(a.x, b.x, c.x);
                const triYmin = Math.min(a.y, b.y, c.y);
                const triYmax = Math.max(a.y, b.y, c.y);
                const minCol = Math.floor((triXmin - xmin) / cellSize);
                const maxCol = Math.floor((triXmax - xmin) / cellSize);
                const minRow = Math.floor((triYmin - ymin) / cellSize);
                const maxRow = Math.floor((triYmax - ymin) / cellSize);
                for (let row = minRow; row <= maxRow; row++) {
                    if (row < 0 || row >= rows)
                        continue;
                    for (let col = minCol; col <= maxCol; col++) {
                        if (col < 0 || col >= cols)
                            continue;
                        const cellCenterX = xmin + (col + 0.5) * cellSize;
                        const cellCenterY = ymin + (row + 0.5) * cellSize;
                        if (pointInTriangle(new BABYLON.Vector2(cellCenterX, cellCenterY), a, b, c)) {
                            gridArray[row][col] = true;
                        }
                    }
                }
            }
            setGrid(gridArray);
            setGridSize({ cols, rows });
            setBounds({ xmin, xmax, ymin, ymax });
            if (onBounds) {
                onBounds({ xmin, xmax, ymin, ymax });
            }
        }, undefined, (error) => {
            console.error("GLB load error", error);
        }, ".glb");
        return () => {
            if (blobUrl) {
                URL.revokeObjectURL(blobUrl);
            }
            scene.dispose();
            engine.dispose();
        };
    }, [glbFile, glbUrl, voxelCount, onBounds]);
    if (!bounds || grid.length === 0) {
        return null;
    }
    const stageWidth = 800;
    const stageHeight = 600;
    const modelWidth = bounds.xmax - bounds.xmin;
    const modelHeight = bounds.ymax - bounds.ymin;
    const scaleX = stageWidth / modelWidth;
    const scaleY = stageHeight / modelHeight;
    const scale = Math.min(scaleX, scaleY);
    const cellWidth = (modelWidth / gridSize.cols) * scale;
    const cellHeight = (modelHeight / gridSize.rows) * scale;
    return (_jsx(Layer, { listening: false, children: grid.flatMap((row, rowIdx) => row.map((filled, colIdx) => {
            if (!filled)
                return null;
            const x = (colIdx * (modelWidth / gridSize.cols)) * scale;
            const y = stageHeight -
                ((rowIdx + 1) * (modelHeight / gridSize.rows)) * scale;
            return (_jsx(Rect, { x: x, y: y, width: cellWidth, height: cellHeight, fill: "green", stroke: "none", listening: false }, `${rowIdx}-${colIdx}`));
        })) }));
};
function pointInTriangle(p, a, b, c) {
    const v0 = c.subtract(a);
    const v1 = b.subtract(a);
    const v2 = p.subtract(a);
    const dot00 = BABYLON.Vector2.Dot(v0, v0);
    const dot01 = BABYLON.Vector2.Dot(v0, v1);
    const dot02 = BABYLON.Vector2.Dot(v0, v2);
    const dot11 = BABYLON.Vector2.Dot(v1, v1);
    const dot12 = BABYLON.Vector2.Dot(v1, v2);
    const denom = dot00 * dot11 - dot01 * dot01;
    if (denom === 0)
        return false;
    const u = (dot11 * dot02 - dot01 * dot12) / denom;
    const v = (dot00 * dot12 - dot01 * dot02) / denom;
    return u >= 0 && v >= 0 && u + v <= 1;
}
export default GLBLayer;
