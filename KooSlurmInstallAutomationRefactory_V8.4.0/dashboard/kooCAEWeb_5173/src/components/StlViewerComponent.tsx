import React, { useEffect, useRef, useState } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/core/Meshes/mesh';        // forceSharedVertices 등 포함
import '@babylonjs/loaders';                 // STL 로더 포함

interface StlViewerProps {
  url: string;
}

const StlViewerComponent: React.FC<StlViewerProps> = ({ url }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // ✅ URL 변경 시 즉시 로딩 표시
    setLoading(true);

    const canvas = canvasRef.current!;
    const engine = new BABYLON.Engine(canvas, true, { preserveDrawingBuffer: true });
    const scene = new BABYLON.Scene(engine);
    scene.clearColor = new BABYLON.Color4(1, 1, 1, 1);

    const camera = new BABYLON.ArcRotateCamera(
      'camera',
      -Math.PI / 4,
      Math.PI / 4,
      100,
      BABYLON.Vector3.Zero(),
      scene
    );
    camera.mode = BABYLON.Camera.ORTHOGRAPHIC_CAMERA;
    camera.attachControl(canvas, true);
    camera.panningSensibility = 1000;

    // 조명 설정
    new BABYLON.HemisphericLight('light1', new BABYLON.Vector3(0, 1, 0), scene).intensity = 0.6;
    new BABYLON.HemisphericLight('light2', new BABYLON.Vector3(0, -1, 0), scene).intensity = 0.4;

    
        /*const directions = [
            new BABYLON.Vector3(1, 1, 0),
            new BABYLON.Vector3(-1, 1, 0),
            new BABYLON.Vector3(0, 1, 1),
            new BABYLON.Vector3(0, 1, -1),
            new BABYLON.Vector3(1, 1, 1),
            new BABYLON.Vector3(-1, 1, -1),
          ];
          
          directions.forEach((dir, i) => {
            const light = new BABYLON.HemisphericLight(`light${i}`, dir.normalize(), scene);
            light.intensity = 0.4; // 낮게 나눠서 조합
          });*/    
    BABYLON.SceneLoader.ImportMeshAsync(
      null,
      '',
      url,
      scene,
      undefined,
      '.stl'
    )
      .then((result) => {
        if (result.meshes.length > 0) {
          const mesh = result.meshes[0] as BABYLON.Mesh;

          /*const mat = new BABYLON.StandardMaterial("mat", scene);
            mat.diffuseColor = new BABYLON.Color3(0.2, 0.8, 0.2);
            mat.backFaceCulling = false;
            mesh.material = mat;*/
          const mat = new BABYLON.PBRMetallicRoughnessMaterial("pbr", scene);
          mat.baseColor = new BABYLON.Color3(0.2, 0.8, 0.2);
          mat.metallic = 0.8;
          mat.roughness = 0.3;
          mat._environmentIntensity = 1.0;
          mat._ambientColor = new BABYLON.Color3(0.3, 0.3, 0.3);
          mat.backFaceCulling = false;
          mesh.material = mat;

          // 노멀 보정
          mesh.forceSharedVertices();
          mesh.convertToFlatShadedMesh();
          mesh.refreshBoundingInfo();

          // 카메라 중심 설정
          const boundingBox = mesh.getBoundingInfo().boundingBox;
          const center = boundingBox.centerWorld;
          const extents = boundingBox.maximumWorld.subtract(boundingBox.minimumWorld);
          const maxExtent = Math.max(extents.x, extents.y, extents.z);

          camera.target = center;
          camera.orthoLeft = -maxExtent;
          camera.orthoRight = maxExtent;
          camera.orthoTop = maxExtent;
          camera.orthoBottom = -maxExtent;
          camera.radius = maxExtent * 4;
          camera.setTarget(center); // <-- 핵심
          scene.activeCamera = camera; // <-- 안전을 위해 명시적으로 설정
          // ✅ 렌더링 준비 완료 후 로딩 종료
          scene.executeWhenReady(() => {
            setLoading(false);
          });
        }
      })
      .catch((error) => {
        console.error('❌ STL 불러오기 실패:', error);
        setLoading(false);
      });

    engine.runRenderLoop(() => scene.render());

    const handleResize = () => engine.resize();
    window.addEventListener('resize', handleResize);

    return () => {
      engine.dispose();
      window.removeEventListener('resize', handleResize);
    };
  }, [url]);

  return (
    <div style={{ position: 'relative', width: '100%', height: '600px' }}>
      {loading && (
        <div style={{
          position: 'absolute',
          top: '50%',
          left: '50%',
          transform: 'translate(-50%, -50%)',
          fontSize: 20,
          color: '#555',
          zIndex: 1,
          background: 'rgba(255, 255, 255, 0.8)',
          padding: '1rem 2rem',
          borderRadius: 8,
          boxShadow: '0 0 10px rgba(0,0,0,0.1)'
        }}>
          Loading...
        </div>
      )}
      <canvas
        ref={canvasRef}
        style={{
          width: '100%',
          height: '100%',
          display: 'block',
          zIndex: 0,
          position: 'relative',
        }}
      />
    </div>
  );
};

export default StlViewerComponent;
