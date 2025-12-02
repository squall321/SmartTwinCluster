import React, { useEffect, useRef, useState } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders/glTF';
import { Slider, Button } from 'antd';

interface GltfViewerProps {
  url: string;
}

const GltfViewerWithSliderComponent: React.FC<GltfViewerProps> = ({ url }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const groupRef = useRef<BABYLON.AnimationGroup | null>(null);
  const sceneRef = useRef<BABYLON.Scene | null>(null);
  const engineRef = useRef<BABYLON.Engine | null>(null);

  const [loading, setLoading] = useState(true);
  const [currentFrame, setCurrentFrame] = useState(0);
  const [frameRange, setFrameRange] = useState<[number, number]>([0, 100]);
  const [isPlaying, setIsPlaying] = useState(false);

  useEffect(() => {
    setLoading(true);
    const canvas = canvasRef.current!;
    const engine = new BABYLON.Engine(canvas, true, { preserveDrawingBuffer: true });
    engineRef.current = engine;

    const scene = new BABYLON.Scene(engine);
    sceneRef.current = scene;
    scene.clearColor = new BABYLON.Color4(1, 1, 1, 1);

    const camera = new BABYLON.ArcRotateCamera('camera', -Math.PI / 2, Math.PI / 2.5, 5, BABYLON.Vector3.Zero(), scene);
    camera.attachControl(canvas, true);

    new BABYLON.HemisphericLight('light', new BABYLON.Vector3(0, 1, 0), scene).intensity = 1;

    BABYLON.SceneLoader.ImportMeshAsync(null, '', url, scene).then((result) => {
      const root = result.meshes[0];
      const bbox = root.getBoundingInfo().boundingBox;
      const center = bbox.centerWorld;
      const size = bbox.maximumWorld.subtract(bbox.minimumWorld);
      const maxExtent = Math.max(size.x, size.y, size.z);

      camera.target = center;
      camera.radius = maxExtent * 2;

      if (scene.animationGroups.length > 0) {
        const group = scene.animationGroups[0];
        groupRef.current = group;
        group.pause();
        setFrameRange([group.from, group.to]);
        setCurrentFrame(group.from);
      }

      scene.executeWhenReady(() => setLoading(false));
    });

    const renderLoop = () => {
      if (isPlaying && groupRef.current) {
        const next = currentFrame + 1;
        if (next <= frameRange[1]) {
          groupRef.current!.goToFrame(next);
          setCurrentFrame(next);
        } else {
          setIsPlaying(false); // 끝나면 자동 정지
        }
      }
      scene.render();
    };
    engine.runRenderLoop(renderLoop);

    const handleResize = () => engine.resize();
    window.addEventListener('resize', handleResize);

    return () => {
      engine.dispose();
      window.removeEventListener('resize', handleResize);
    };
  }, [url, currentFrame, isPlaying]);

  const onSliderChange = (value: number) => {
    setCurrentFrame(value);
    groupRef.current?.goToFrame(value);
    setIsPlaying(false);
  };

  const togglePlay = () => {
    setIsPlaying((prev) => !prev);
  };

  return (
    <div style={{ width: '100%', height: '700px', position: 'relative' }}>
      {loading && (
        <div style={{
          position: 'absolute', top: '50%', left: '50%',
          transform: 'translate(-50%, -50%)', fontSize: 20, zIndex: 1,
          background: 'rgba(255,255,255,0.8)', padding: '1rem 2rem', borderRadius: 8
        }}>
          Loading...
        </div>
      )}

      <canvas ref={canvasRef} style={{ width: '100%', height: '600px', display: 'block' }} />

      <div style={{ padding: '12px 24px' }}>
        <Slider
          min={frameRange[0]}
          max={frameRange[1]}
          value={currentFrame}
          onChange={onSliderChange}
          disabled={loading}
        />
        <Button onClick={togglePlay} style={{ marginTop: 12 }}>
          {isPlaying ? '⏸ Pause' : '▶ Play'}
        </Button>
      </div>
    </div>
  );
};

export default GltfViewerWithSliderComponent;
