import React, { useEffect, useRef, useState } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/core/Meshes/mesh';
import '@babylonjs/loaders'; // OBJ 로더 포함

interface ObjViewerProps {
  url: string;
  mtlUrl?: string;
  backgroundColor?: BABYLON.Color4;
  orthographic?: boolean;
}

const ObjViewerComponent: React.FC<ObjViewerProps> = ({
  url,
  mtlUrl,
  backgroundColor = new BABYLON.Color4(1, 1, 1, 1),
  orthographic = true,
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let disposed = false;
    const canvas = canvasRef.current!;
    const engine = new BABYLON.Engine(canvas, true, { preserveDrawingBuffer: true });
    const scene = new BABYLON.Scene(engine);
    scene.clearColor = backgroundColor;

    const camera = new BABYLON.ArcRotateCamera(
      'camera',
      -Math.PI / 4,
      Math.PI / 4,
      100,
      BABYLON.Vector3.Zero(),
      scene
    );
    camera.attachControl(canvas, true);
    camera.panningSensibility = 1000;
    if (orthographic) {
      camera.mode = BABYLON.Camera.ORTHOGRAPHIC_CAMERA;
    }

    new BABYLON.HemisphericLight('light1', new BABYLON.Vector3(0, 1, 0), scene).intensity = 0.6;
    new BABYLON.HemisphericLight('light2', new BABYLON.Vector3(0, -1, 0), scene).intensity = 0.4;

    const load = async () => {
      try {
        setLoading(true);
        const result = await BABYLON.SceneLoader.ImportMeshAsync(
          null,
          '',
          url,
          scene,
          undefined,
          '.obj'
        );

        if (disposed) return;

        const meshes = result.meshes.filter(m => m instanceof BABYLON.Mesh) as BABYLON.Mesh[];
        if (meshes.length === 0) throw new Error('OBJ에서 Mesh를 찾을 수 없습니다.');

        const hasMaterial = meshes.some(m => !!m.material);
        if (!hasMaterial) {
          const pbr = new BABYLON.PBRMetallicRoughnessMaterial('pbr', scene);
          pbr.baseColor = new BABYLON.Color3(0.2, 0.8, 0.2);
          pbr.metallic = 0.8;
          pbr.roughness = 0.3;
          pbr.backFaceCulling = false;
          meshes.forEach(m => (m.material = pbr));
        }

        meshes.forEach(mesh => {
          mesh.forceSharedVertices();
          mesh.convertToFlatShadedMesh();
          mesh.refreshBoundingInfo();
        });

        const min = new BABYLON.Vector3(Number.POSITIVE_INFINITY, Number.POSITIVE_INFINITY, Number.POSITIVE_INFINITY);
        const max = new BABYLON.Vector3(Number.NEGATIVE_INFINITY, Number.NEGATIVE_INFINITY, Number.NEGATIVE_INFINITY);
        meshes.forEach(m => {
          const info = m.getBoundingInfo().boundingBox;
          min.x = Math.min(min.x, info.minimumWorld.x);
          min.y = Math.min(min.y, info.minimumWorld.y);
          min.z = Math.min(min.z, info.minimumWorld.z);
          max.x = Math.max(max.x, info.maximumWorld.x);
          max.y = Math.max(max.y, info.maximumWorld.y);
          max.z = Math.max(max.z, info.maximumWorld.z);
        });

        const center = min.add(max).scale(0.5);
        const extents = max.subtract(min);
        const maxExtent = Math.max(extents.x, extents.y, extents.z);

        camera.target = center;
        if (orthographic) {
          const padding = 0.2;
          camera.orthoLeft = -extents.x * (0.5 + padding);
          camera.orthoRight = extents.x * (0.5 + padding);
          camera.orthoTop = extents.y * (0.5 + padding);
          camera.orthoBottom = -extents.y * (0.5 + padding);
        } else {
          camera.radius = maxExtent * 3.0;
        }
        camera.setTarget(center);
        scene.activeCamera = camera;

        scene.executeWhenReady(() => {
          if (!disposed) setLoading(false);
        });
      } catch (e) {
        console.error('❌ OBJ 불러오기 실패:', e);
        if (!disposed) setLoading(false);
      }
    };

    load();

    engine.runRenderLoop(() => scene.render());
    const handleResize = () => engine.resize();
    window.addEventListener('resize', handleResize);

    return () => {
      disposed = true;
      engine.dispose();
      window.removeEventListener('resize', handleResize);
    };
  }, [url]);

  return (
    <div style={{ position: 'relative', width: '100%', height: '600px' }}>
      {loading && (
        <div style={{
          position: 'absolute', top: '50%', left: '50%',
          transform: 'translate(-50%, -50%)',
          fontSize: 20, color: '#555', zIndex: 1,
          background: 'rgba(255, 255, 255, 0.8)',
          padding: '1rem 2rem', borderRadius: 8,
          boxShadow: '0 0 10px rgba(0,0,0,0.1)'
        }}>
          Loading...
        </div>
      )}
      <canvas
        ref={canvasRef}
        style={{ width: '100%', height: '100%', display: 'block', zIndex: 0, position: 'relative' }}
      />
    </div>
  );
};

export default ObjViewerComponent;