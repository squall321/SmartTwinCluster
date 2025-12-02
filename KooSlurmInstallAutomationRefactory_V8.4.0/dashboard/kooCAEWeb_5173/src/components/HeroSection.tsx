import React, { useEffect, useRef, useState } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';
import { Button, Typography } from 'antd';

const { Title, Paragraph } = Typography;

const HeroSection: React.FC = () => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const engine = new BABYLON.Engine(canvas, true);
    const scene = new BABYLON.Scene(engine);

    const camera = new BABYLON.ArcRotateCamera(
      'camera',
      -Math.PI / 2,
      Math.PI / 2.5,
      5,
      BABYLON.Vector3.Zero(),
      scene
    );
    camera.attachControl(canvas, true);

    const light = new BABYLON.HemisphericLight(
      'light',
      new BABYLON.Vector3(0, 1, 0),
      scene
    );
    light.intensity = 1;

    BABYLON.SceneLoader.Append('/models/', 'smartphone.glb', scene, () => {
      const meshes = scene.meshes.filter((m) => m.name !== '__root__');
      if (meshes.length > 0) {
        const bounds = meshes.map((m) => m.getBoundingInfo().boundingBox);
        const min = bounds.map((b) => b.minimumWorld).reduce((a, b) => BABYLON.Vector3.Minimize(a, b));
        const max = bounds.map((b) => b.maximumWorld).reduce((a, b) => BABYLON.Vector3.Maximize(a, b));
        const center = min.add(max).scale(0.5);
        const size = max.subtract(min);
        const maxExtent = Math.max(size.x, size.y, size.z);

        // 모델 중심 이동 및 스케일 조정
        const desiredSize = 1.0;
        const scaleFactor = maxExtent < 1e-6 ? 1.0 : desiredSize / maxExtent;
        meshes.forEach((mesh) => {
          mesh.position.subtractInPlace(center);
          mesh.scaling.scaleInPlace(scaleFactor);
        });

        camera.setTarget(BABYLON.Vector3.Zero());
        camera.radius = desiredSize * 2;
      }

      scene.animationGroups.forEach((group) => group.start(true));
      setLoading(false);
    });

    engine.runRenderLoop(() => scene.render());

    const handleResize = () => engine.resize();
    window.addEventListener('resize', handleResize);

    return () => {
      scene.dispose();
      engine.dispose();
      window.removeEventListener('resize', handleResize);
    };
  }, []);

  return (
    <div style={{ position: 'relative', height: '100vh', overflow: 'hidden' }}>
      {loading && (
        <div style={{
          position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)',
          background: 'rgba(255,255,255,0.8)', padding: 20, borderRadius: 8, zIndex: 10
        }}>Loading...</div>
      )}
      <canvas ref={canvasRef} style={{ width: '100%', height: '100%' }} />

      <div style={{
        position: 'absolute',
        top: '30%',
        left: '10%',
        zIndex: 2,
        color: 'white',
        maxWidth: '600px'
      }}>
        <Title level={1} style={{ color: 'white' }}>디지털 트윈으로 미래를 설계하다</Title>
        <Paragraph style={{ color: 'white', fontSize: '18px' }}>
          스마트폰의 낙하, 충격, 열환경을 가상 시뮬레이션으로 예측합니다.
        </Paragraph>
        <div style={{ marginTop: 20 }}>
          <Button type="primary" size="large" style={{ marginRight: 10 }}>시뮬레이션 체험하기</Button>
          <Button ghost size="large">자세히 보기</Button>
        </div>
      </div>
    </div>
  );
};

export default HeroSection;
