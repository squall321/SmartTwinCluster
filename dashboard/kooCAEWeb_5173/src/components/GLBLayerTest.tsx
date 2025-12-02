import React, { useEffect, useState } from "react";
import { Layer, Line } from "react-konva";
import * as BABYLON from "@babylonjs/core";
import "@babylonjs/loaders/glTF";
import concaveman from "concaveman";
import simplify from "simplify-js";

type Triangle = { x: number; y: number; z: number }[];

interface Props {
  glbUrl?: string;
  glbFile?: File;
  onBounds?: (bounds: {
    xmin: number;
    xmax: number;
    ymin: number;
    ymax: number;
  }) => void;
}

const GLBLayerTest: React.FC<Props> = ({ glbUrl, glbFile, onBounds }) => {
  const [hullPoints, setHullPoints] = useState<{ x: number; y: number }[]>([]);

  useEffect(() => {
    if (!glbFile && !glbUrl) return;

    let blobUrl: string | null = null;
    let urlToLoad: string;

    if (glbFile) {
      blobUrl = URL.createObjectURL(glbFile);
      urlToLoad = blobUrl;
    } else if (glbUrl) {
      urlToLoad = glbUrl;
    } else {
      return;
    }

    const engine = new BABYLON.NullEngine();
    const scene = new BABYLON.Scene(engine);

    BABYLON.SceneLoader.ImportMesh(
      null,
      "",
      urlToLoad,
      scene,
      (meshes) => {
        let _xmin = +Infinity;
        let _xmax = -Infinity;
        let _ymin = +Infinity;
        let _ymax = -Infinity;

        const points2D: [number, number][] = [];

        meshes.forEach((mesh) => {
          const geometry = mesh.geometry;
          if (!geometry) return;

          const positions = geometry.getVerticesData(BABYLON.VertexBuffer.PositionKind);
          if (!positions) return;

          for (let i = 0; i < positions.length; i += 3) {
            const x = positions[i];
            const y = positions[i + 1];
            const z = positions[i + 2];

            points2D.push([x, y]);

            _xmin = Math.min(_xmin, x);
            _xmax = Math.max(_xmax, x);
            _ymin = Math.min(_ymin, y);
            _ymax = Math.max(_ymax, y);
          }
        });

        if (points2D.length === 0) {
          console.log("No vertices found in GLB");
          return;
        }

        // concaveman returns array of [x,y]
        const concave = concaveman(points2D, 2);

        // Convert to objects for simplify-js
        const hullPointsObj = concave.map((p: any) => ({ x: p[0], y: p[1] }));

        // Simplify with 0.001 tolerance
        const simplified = simplify(hullPointsObj, 0.001);

        setHullPoints(simplified);

        if (onBounds) {
          onBounds({
            xmin: _xmin,
            xmax: _xmax,
            ymin: _ymin,
            ymax: _ymax,
          });
        }
      },
      undefined,
      (error) => {
        console.error("GLB load error", error);
      },
      ".glb"
    );

    return () => {
      if (blobUrl) {
        URL.revokeObjectURL(blobUrl);
      }
      scene.dispose();
      engine.dispose();
    };
  }, [glbFile, glbUrl, onBounds]);

  if (hullPoints.length === 0) {
    return null;
  }

  // Compute scale
  const allX = hullPoints.map((p) => p.x);
  const allY = hullPoints.map((p) => p.y);

  const _xmin = Math.min(...allX);
  const _xmax = Math.max(...allX);
  const _ymin = Math.min(...allY);
  const _ymax = Math.max(...allY);

  const stageWidth = 800;
  const stageHeight = 600;

  const modelWidth = _xmax - _xmin;
  const modelHeight = _ymax - _ymin;

  const scaleX = stageWidth / modelWidth;
  const scaleY = stageHeight / modelHeight;
  const scale = Math.min(scaleX, scaleY);

  const points = hullPoints.flatMap((v) => [
    (v.x - _xmin) * scale,
    (v.y - _ymin) * scale,
  ]);

  return (
    <Layer listening={false}>
      <Line
        points={points}
        closed
        fill="green"
        stroke="none"
        strokeWidth={0}
        perfectDrawEnabled={false}
        listening={false}
      />
    </Layer>
  );
};

export default GLBLayerTest;
