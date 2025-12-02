import { useEffect, useRef, useState, Fragment } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';

const SceneComponent = () => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const pickedPointsRef = useRef<BABYLON.Vector3[]>([]);
  const stlMeshRef = useRef<BABYLON.Mesh | null>(null);
  const cameraRef = useRef<BABYLON.ArcRotateCamera | null>(null);
  const boxCounterRef = useRef(0);

  const [fileName, setFileName] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [pushValue, setPushValue] = useState(0.5);
  const [effectRadius, _setEffectRadius] = useState(0.1);
  const effectRadiusRef = useRef(effectRadius);
  const [selectedBoxId, setSelectedBoxId] = useState<string | null>(null);
  const [boxes, setBoxes] = useState<Record<string, {
    id: string;
    mesh: BABYLON.Mesh;
    outline: BABYLON.Mesh;
    info: BoxInfo;
  }>>({});

  type BoxInfo = {
    width: number;
    height: number;
    depth: number;
    x: number;
    y: number;
    z: number;
  };

  const setEffectRadius = (val: number) => {
    _setEffectRadius(val);
    effectRadiusRef.current = val;
    if (selectedBoxId && boxes[selectedBoxId]) updateOutline(boxes[selectedBoxId]);
  };

  const createOutline = (info: BoxInfo, scene: BABYLON.Scene) => {
    const box = BABYLON.MeshBuilder.CreateBox('outline', {
      width: info.width + effectRadius * 2,
      height: info.height + effectRadius * 2,
      depth: info.depth + effectRadius * 2,
    }, scene);
    const mat = new BABYLON.StandardMaterial('outlineMat', scene);
    mat.diffuseColor = new BABYLON.Color3(1, 0.5, 0.5);
    mat.alpha = 0.3;
    box.material = mat;
    box.enableEdgesRendering();
    box.edgesWidth = effectRadius * 5;
    box.edgesColor = new BABYLON.Color4(1, 0.5, 0.5, 0.6);
    return box;
  };

  const worldToLocal = (worldPos: BABYLON.Vector3, mesh: BABYLON.AbstractMesh) => {
    const inv = mesh.getWorldMatrix().invert();
    return BABYLON.Vector3.TransformCoordinates(worldPos, inv);
  };

  const updateOutline = (entry: { id: string; mesh: BABYLON.Mesh; outline: BABYLON.Mesh; info: BoxInfo }) => {
    const scene = BABYLON.Engine.LastCreatedScene!;
    const newOutline = createOutline(entry.info, scene);
    newOutline.parent = stlMeshRef.current;
    newOutline.position = entry.mesh.position.clone();
    entry.outline.dispose();
    setBoxes(prev => ({ ...prev, [entry.id]: { ...entry, outline: newOutline } }));
  };

  const updateBoxInfo = (key: keyof BoxInfo, value: number) => {
    if (!selectedBoxId) return;

    setBoxes((prev) => {
      const box = prev[selectedBoxId];
      const newInfo = { ...box.info, [key]: value };
      const scene = BABYLON.Engine.LastCreatedScene!;

      box.mesh.setParent(null);
      box.outline.setParent(null);
      box.mesh.dispose();
      box.outline.dispose();

      scene.meshes
        .filter(m => m.name === box.id + '_mesh' || m.name === box.id + '_outline')
        .forEach(m => m.dispose());

      const newMesh = BABYLON.MeshBuilder.CreateBox(box.id + '_mesh', {
        width: newInfo.width,
        height: newInfo.height,
        depth: newInfo.depth,
      }, scene);
      newMesh.name = box.id + '_mesh';
      const mat = new BABYLON.StandardMaterial('mat', scene);
      mat.diffuseColor = new BABYLON.Color3(1, 0, 0);
      mat.alpha = 0.5;
      newMesh.material = mat;
      newMesh.parent = stlMeshRef.current;
      newMesh.position = new BABYLON.Vector3(
        newInfo.x - stlMeshRef.current!.position.x,
        newInfo.y - stlMeshRef.current!.position.y,
        newInfo.z - stlMeshRef.current!.position.z
      );

      const newOutline = createOutline(newInfo, scene);
      newOutline.name = box.id + '_outline';
      newOutline.parent = stlMeshRef.current;
      newOutline.position = newMesh.position.clone();

      return {
        ...prev,
        [box.id]: {
          id: box.id,
          mesh: newMesh,
          outline: newOutline,
          info: newInfo,
        }
      };
    });
  };

  const deleteBox = () => {
    if (!selectedBoxId) return;
    setBoxes((prev) => {
      const { [selectedBoxId]: removed, ...rest } = prev;
      removed.mesh.dispose();
      removed.outline.dispose();
      setSelectedBoxId(Object.keys(rest)[0] || null);
      return rest;
    });
  };

  // ... 나머지 코드는 그대로 유지 ...


  const handleExportScript = () => {
    if (!fileName || Object.keys(boxes).length === 0) return;
  
    const kFile = fileName.replace(/\.stl$/i, '.k');
  
    const header = [
      '*Inputfile',
      kFile,
      '*Mode',
      'PART_MORPHING,1',
      '**PartMorphing,1',
      '#Morph,Part ID,Shape,ShapeKeyword,ShapeKeyword,Direction,Push(+) or Pull(-) Value,EffectRadius'
    ];
  
    const body = Object.values(boxes).map((box, index) => {
      const { width, height, depth, x, y, z } = box.info;
      const lower = [
        (x - width / 2).toFixed(3),
        (z - depth / 2).toFixed(3),
        (y - height / 2).toFixed(3)
      ];
      const upper = [
        (x + width / 2).toFixed(3),
        (z + depth / 2).toFixed(3),
        (y + height / 2).toFixed(3)
      ];
      return `*MorphBox,1,(${lower.join(',')}),(${upper.join(',')}),(0,0,-1),${pushValue},${effectRadius}`;
    });
  
    const footer = [
      '**EndPartMorphing',
      '*End'
    ];
  
    const content = [...header, ...body, ...footer].join('\n');
    const blob = new Blob([content], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'script.txt';
    a.click();
    URL.revokeObjectURL(url);
  };
  

  const handleFileChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file || !canvasRef.current) return;
  
    setFileName(file.name);
    setLoading(true);
  
    try {
      const blobUrl = URL.createObjectURL(file);
      const scene = BABYLON.Engine.LastCreatedScene!;
      scene.meshes.forEach((m) => m.dispose());
  
      const result = await BABYLON.SceneLoader.ImportMeshAsync('', blobUrl, '', scene, undefined, '.stl');
      const meshes = result.meshes.filter(m => m.name !== '__root__' && m instanceof BABYLON.Mesh) as BABYLON.Mesh[];
  
      if (meshes.length === 0) throw new Error('STL 파일에 유효한 메시가 없습니다');
  
      // 전체 바운딩 박스 계산
      const bounds = meshes.map(m => m.getBoundingInfo().boundingBox);
      const min = bounds.map(b => b.minimumWorld).reduce((a, b) => BABYLON.Vector3.Minimize(a, b));
      const max = bounds.map(b => b.maximumWorld).reduce((a, b) => BABYLON.Vector3.Maximize(a, b));
      const center = min.add(max).scale(0.5);
      const size = max.subtract(min);
      const maxExtent = Math.max(size.x, size.y, size.z);
  
      // ✅ 스케일 자동 보정 (작은 모델은 확대)
      const minThreshold = 0.01;  // 너무 작다고 판단할 임계값
      const baseSize = 1.0;
      const scaleFactor = maxExtent < minThreshold ? baseSize / minThreshold : baseSize / maxExtent;
  
      // ✅ 메시 중심 이동 및 스케일링
      meshes.forEach(mesh => {
        mesh.position.subtractInPlace(center);       // 중심을 원점으로 이동
        mesh.scaling.scaleInPlace(scaleFactor);     // 스케일 보정
      });
  
      // ✅ 카메라 시야 재설정 (꽉 차게)
      const camera = cameraRef.current;
      const canvas = canvasRef.current;
      if (camera && canvas) {
        const aspect = canvas.clientWidth / canvas.clientHeight;
        const marginRatio = 1.1;
  
        const xSize = size.x * scaleFactor * 0.5 * marginRatio;
        const ySize = size.y * scaleFactor * 0.5 * marginRatio;
  
        camera.orthoLeft = -xSize * aspect;
        camera.orthoRight = xSize * aspect;
        camera.orthoTop = ySize;
        camera.orthoBottom = -ySize;
  
        camera.setTarget(BABYLON.Vector3.Zero());
      }
  
      // ✅ 기본 재질 지정
      const mat = new BABYLON.PBRMetallicRoughnessMaterial('stlMat', scene);
      mat.baseColor = new BABYLON.Color3(0.8, 0.8, 0.85);
      mat.metallic = 1.0;
      mat.roughness = 0.2;
      mat.environmentTexture = scene.environmentTexture;
  
      meshes.forEach(m => m.material = mat);
  
      stlMeshRef.current = meshes[0];
      setLoading(false);
    } catch (err) {
      console.error('❌ STL 로딩 실패:', err);
      alert('STL 로딩 실패: ' + err);
      setLoading(false);
    }
  };
  
  

  useEffect(() => {
    const canvas = canvasRef.current!;
    const engine = new BABYLON.Engine(canvas, true);
    const scene = new BABYLON.Scene(engine);
    scene.clearColor = new BABYLON.Color4(1, 1, 1, 1);
  
    const camera = new BABYLON.ArcRotateCamera('camera', 0, 0, 100, BABYLON.Vector3.Zero(), scene);
    camera.mode = BABYLON.Camera.ORTHOGRAPHIC_CAMERA;
    camera.lowerAlphaLimit = 0;
    camera.upperAlphaLimit = 0;
    camera.lowerBetaLimit = 0;
    camera.upperBetaLimit = 0;
    camera.panningSensibility = 1000;
    camera.allowUpsideDown = false;
  
    const zoom = camera.orthoTop ?? 50;
    camera.orthoLeft = -zoom;
    camera.orthoRight = zoom;
    camera.orthoTop = zoom;
    camera.orthoBottom = -zoom;
    camera.attachControl(canvas, true);
    cameraRef.current = camera;
  
    new BABYLON.HemisphericLight('light', new BABYLON.Vector3(0, 0, 1), scene).intensity = 0.9;
    const envTex = BABYLON.CubeTexture.CreateFromPrefilteredData('https://playground.babylonjs.com/textures/environment.env', scene);
    scene.environmentTexture = envTex;
    scene.environmentIntensity = 0.9;
    scene.createDefaultSkybox(envTex, true, 1000);
  
    canvas.addEventListener('wheel', (e) => {
      e.preventDefault();
      const zoomStep = 5;
      const delta = e.deltaY > 0 ? zoomStep : -zoomStep;
      if (camera) {
        camera.orthoLeft = (camera.orthoLeft ?? 0) + delta;
        camera.orthoRight = (camera.orthoRight ?? 0) - delta;
        camera.orthoTop = (camera.orthoTop ?? 0) - delta;
        camera.orthoBottom = (camera.orthoBottom ?? 0) + delta;
      }
    }, { passive: false });
  
    scene.onPointerObservable.add((pointerInfo) => {
      if (pointerInfo.type === BABYLON.PointerEventTypes.POINTERDOWN) {
        const pick = scene.pick(scene.pointerX, scene.pointerY);
        if (pick?.hit && pick.pickedPoint && stlMeshRef.current) {
          pickedPointsRef.current.push(pick.pickedPoint.clone());
          if (pickedPointsRef.current.length === 2) {
            const [p1, p2] = pickedPointsRef.current;
            const min = BABYLON.Vector3.Minimize(p1, p2);
            const max = BABYLON.Vector3.Maximize(p1, p2);
            const size = max.subtract(min);
            const center = min.add(size.scale(0.5));
            const box = BABYLON.MeshBuilder.CreateBox('box', { width: size.x, height: size.y, depth: size.z }, scene);
            const mat = new BABYLON.StandardMaterial('mat', scene);
            mat.diffuseColor = new BABYLON.Color3(1, 0, 0);
            mat.alpha = 0.5;
            box.material = mat;
            box.parent = stlMeshRef.current;
            const localCenter = center.subtract(stlMeshRef.current.getAbsolutePosition());
            box.position = localCenter;
            const info: BoxInfo = { width: size.x, height: size.y, depth: size.z, x: center.x, y: center.y, z: center.z };
            const outline = createOutline(info, scene);
            outline.parent = stlMeshRef.current;
            outline.position = box.position.clone();
            const id = `box_${++boxCounterRef.current}`;
            setBoxes(prev => ({ ...prev, [id]: { id, mesh: box, outline, info } }));
            setSelectedBoxId(id);
            pickedPointsRef.current = [];
          }
        }
      }
    });
  
    // ✅ 추가 시작
    const handleResize = () => {
      engine.resize();
  
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      const aspect = width / height;
  
      const zoom = camera.orthoTop ?? 50;  // 기존 zoom 유지
      camera.orthoLeft = -zoom * aspect;
      camera.orthoRight = zoom * aspect;
      camera.orthoTop = zoom;
      camera.orthoBottom = -zoom;
    };
  
    window.addEventListener('resize', handleResize);
    handleResize();  // 초기 1회 호출
    // ✅ 추가 끝
  
    engine.runRenderLoop(() => scene.render());
  
    return () => {
      window.removeEventListener('resize', handleResize); // ✅ 추가
      engine.dispose();
    };
  }, []);
  

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', maxWidth: '100vw' }}>
  <div style={{ height: 'calc(100vh - 220px)', minHeight: 0 }}>
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      {loading && (
        <div style={{
          position: 'absolute', zIndex: 10, width: '100%', height: '100%', background: 'rgba(255,255,255,0.8)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: '24px', fontWeight: 'bold', color: '#333'
        }}>STL 로딩 중...</div>
      )}
      <canvas ref={canvasRef} style={{ width: '100%', height: '100%', display: 'block' }} />
      <input type="file" accept=".stl" ref={fileInputRef} style={{ position: 'absolute', top: 20, left: 20, zIndex: 20 }} onChange={handleFileChange} />
    </div>
  </div>

  {selectedBoxId && boxes[selectedBoxId] && (
    <div style={{ padding: '1rem', background: '#fafafa', borderTop: '1px solid #ccc', height: '220px', overflowY: 'auto' }}>
      <div style={{ maxWidth: 1000, margin: '0 auto 1rem' }}>
        <div style={{ display: 'flex', gap: '1rem', marginBottom: '1rem' }}>
          <label style={{ fontWeight: 'bold' }}>박스 선택</label>
          <select
            onChange={(e) => setSelectedBoxId(e.target.value)}
            value={selectedBoxId || ''}
            style={{ flex: 1, padding: '0.5rem' }}
          >
            <option value="" disabled>박스 선택</option>
            {Object.values(boxes).map(box => (
              <option key={box.id} value={box.id}>{box.id}</option>
            ))}
          </select>
        </div>

        <div style={{ display: 'flex', gap: '1rem', marginBottom: '1rem' }}>
          {(['width', 'height', 'depth'] as (keyof BoxInfo)[]).map((key) => (
            <div key={key} style={{ flex: 1 }}>
              <label style={{ fontWeight: 'bold' }}>{key}</label>
              <input
                type="number"
                value={boxes[selectedBoxId].info[key].toFixed(2)}
                onChange={(e) => updateBoxInfo(key, parseFloat(e.target.value))}
                style={{ padding: '0.25rem', width: '100%', boxSizing: 'border-box' }}
              />
            </div>
          ))}
        </div>

        <div style={{ display: 'flex', gap: '1rem', marginBottom: '1rem' }}>
          {(['x', 'y', 'z'] as (keyof BoxInfo)[]).map((key) => (
            <div key={key} style={{ flex: 1 }}>
              <label style={{ fontWeight: 'bold' }}>{key}</label>
              <input
                type="number"
                value={boxes[selectedBoxId].info[key].toFixed(2)}
                onChange={(e) => updateBoxInfo(key, parseFloat(e.target.value))}
                style={{ padding: '0.25rem', width: '100%', boxSizing: 'border-box' }}
              />
            </div>
          ))}
        </div>

        <div style={{ display: 'flex', gap: '1rem', marginBottom: '1rem' }}>
          <div style={{ flex: 1 }}>
            <label style={{ fontWeight: 'bold' }}>Push/Pull 값</label>
            <input
              type="number"
              value={pushValue}
              step="0.1"
              onChange={(e) => setPushValue(parseFloat(e.target.value))}
              style={{ padding: '0.25rem', width: '100%', boxSizing: 'border-box' }}
            />
          </div>
          <div style={{ flex: 1 }}>
            <label style={{ fontWeight: 'bold' }}>Effect Radius</label>
            <input
              type="number"
              value={effectRadius}
              onChange={(e) => setEffectRadius(parseFloat(e.target.value))}
              style={{ padding: '0.25rem', width: '100%', boxSizing: 'border-box' }}
            />
          </div>
        </div>

        <div style={{ display: 'flex', justifyContent: 'center', gap: '1rem' }}>
          <button onClick={deleteBox} style={{ padding: '0.5rem 1rem', background: '#f44336', color: 'white', border: 'none', minWidth: 120 }}>삭제</button>
          <button onClick={handleExportScript} style={{ padding: '0.5rem 1rem', background: '#4caf50', color: 'white', border: 'none', minWidth: 120 }}>📄 내보내기</button>
        </div>
      </div>
    </div>
  )}
</div>

  );
};

export default SceneComponent;
