import { jsx as _jsx } from "react/jsx-runtime";
import { useEffect, useState } from "react";
import { Layer, Line } from "react-konva";
import * as BABYLON from "@babylonjs/core";
import "@babylonjs/loaders/glTF";
const GLBLayerPrev = ({ glbUrl, glbFile, onBounds }) => {
    const [triangles, setTriangles] = useState([]);
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
            let _xmin = +Infinity;
            let _xmax = -Infinity;
            let _ymin = +Infinity;
            let _ymax = -Infinity;
            const tris = [];
            meshes.forEach((mesh) => {
                const geometry = mesh.geometry;
                if (!geometry)
                    return;
                const positions = geometry.getVerticesData(BABYLON.VertexBuffer.PositionKind);
                const indices = geometry.getIndices();
                if (!positions || !indices)
                    return;
                for (let i = 0; i < indices.length; i += 3) {
                    const tri = [];
                    for (let j = 0; j < 3; j++) {
                        const vi = indices[i + j];
                        const x = positions[vi * 3];
                        const y = positions[vi * 3 + 1];
                        const z = positions[vi * 3 + 2];
                        tri.push({ x, y, z });
                        _xmin = Math.min(_xmin, x);
                        _xmax = Math.max(_xmax, x);
                        _ymin = Math.min(_ymin, y);
                        _ymax = Math.max(_ymax, y);
                    }
                    tris.push(tri);
                }
            });
            if (tris.length === 0) {
                console.log("No triangles found in GLB");
                return;
            }
            setTriangles(tris);
            if (onBounds) {
                onBounds({
                    xmin: _xmin,
                    xmax: _xmax,
                    ymin: _ymin,
                    ymax: _ymax,
                });
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
    }, [glbFile, glbUrl, onBounds]);
    if (triangles.length === 0) {
        return null;
    }
    const stageWidth = 800;
    const stageHeight = 600;
    // 모델 전체 범위를 구해 스케일링
    const allX = triangles.flatMap((tri) => tri.map((v) => v.x));
    const allY = triangles.flatMap((tri) => tri.map((v) => v.y));
    const _xmin = Math.min(...allX);
    const _xmax = Math.max(...allX);
    const _ymin = Math.min(...allY);
    const _ymax = Math.max(...allY);
    const modelWidth = _xmax - _xmin;
    const modelHeight = _ymax - _ymin;
    const scaleX = stageWidth / modelWidth;
    const scaleY = stageHeight / modelHeight;
    const scale = Math.min(scaleX, scaleY);
    return (_jsx(Layer, { listening: false, children: triangles.map((tri, i) => {
            const points = tri.flatMap((v) => [
                (v.x - _xmin) * scale,
                (v.y - _ymin) * scale,
            ]);
            return (_jsx(Line, { points: points, closed: true, fill: "green", stroke: "none", strokeWidth: 0, perfectDrawEnabled: false, listening: false }, i));
        }) }));
};
export default GLBLayerPrev;
