import React, { useEffect, useRef } from "react";
import * as THREE from "three";
import { Face, NetLayout } from "./types";

type Props = {
  xMM: number; yMM: number; zMM: number;
  layout: NetLayout;
  getMaskCanvas: () => HTMLCanvasElement | null;
  getPatternCanvas: () => HTMLCanvasElement | null;
  version: number; // bump to rebuild textures
};

export default function MiniCubePreview({ xMM, yMM, zMM, layout, getMaskCanvas, getPatternCanvas, version }: Props) {
  const mountRef = useRef<HTMLDivElement | null>(null);
  const sceneRef = useRef<THREE.Scene | null>(null);
  const rendererRef = useRef<THREE.WebGLRenderer | null>(null);
  const cameraRef = useRef<THREE.PerspectiveCamera | null>(null);
  const cubeRef = useRef<THREE.Mesh | null>(null);
  const materialsRef = useRef<THREE.MeshBasicMaterial[]>([]);
  const edgesRef = useRef<THREE.LineSegments | null>(null);
  const rafRef = useRef<number | null>(null);
  const draggingRef = useRef(false);
  const lastPosRef = useRef({x:0,y:0});

  const faceOrder: Face[] = ["+X","-X","+Y","-Y","+Z","-Z"];

  function makeFaceTexture(face: Face) {
    const size = 512;
    const cvs = document.createElement("canvas");
    cvs.width = size; cvs.height = size;
    const ctx = cvs.getContext("2d")!;
    ctx.fillStyle = "#AEB6C1"; ctx.fillRect(0,0,size,size);
    ctx.globalAlpha = 0.28; ctx.fillStyle = "#000"; ctx.fillRect(0,0,size,size); ctx.globalAlpha = 1;
    ctx.strokeStyle = "rgba(0,0,0,0.15)"; ctx.lineWidth = 1;
    const step = 64;
    for (let x = step; x < size; x += step) { ctx.beginPath(); ctx.moveTo(x + 0.5, 0); ctx.lineTo(x + 0.5, size); ctx.stroke(); }
    for (let y = step; y < size; y += step) { ctx.beginPath(); ctx.moveTo(0, y + 0.5); ctx.lineTo(size, y + 0.5); ctx.stroke(); }

    const pattern = getPatternCanvas();
    const fr = layout.faceRects[face];
    if (pattern && fr && fr.w > 0 && fr.h > 0) ctx.drawImage(pattern, fr.x, fr.y, fr.w, fr.h, 0, 0, size, size);
    const mask = getMaskCanvas();
    if (mask && fr && fr.w > 0 && fr.h > 0) ctx.drawImage(mask, fr.x, fr.y, fr.w, fr.h, 0, 0, size, size);

    const tex = new THREE.CanvasTexture(cvs);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.minFilter = THREE.LinearFilter; tex.magFilter = THREE.LinearFilter;
    tex.needsUpdate = true;
    return tex;
  }

  function rebuildMaterials() {
    const mats = faceOrder.map((f)=>new THREE.MeshBasicMaterial({ map: makeFaceTexture(f) }));
    materialsRef.current.forEach(m=>{ m.map?.dispose(); m.dispose(); });
    materialsRef.current = mats;
    if (cubeRef.current) (cubeRef.current.material as THREE.Material[]).splice(0,6, ...mats);
  }

  useEffect(() => {
    if (!cubeRef.current || !cameraRef.current) return;
    const cube = cubeRef.current;
    const oldGeo = cube.geometry as THREE.BoxGeometry;
    const newGeo = new THREE.BoxGeometry(xMM, yMM, zMM);
    cube.geometry = newGeo; oldGeo.dispose();

    if (!edgesRef.current) {
      const e = new THREE.EdgesGeometry(newGeo);
      edgesRef.current = new THREE.LineSegments(e, new THREE.LineBasicMaterial({ color: 0x111111 }));
      cube.add(edgesRef.current);
    } else {
      const prev = edgesRef.current;
      prev.geometry.dispose();
      prev.geometry = new THREE.EdgesGeometry(newGeo);
      (prev.material as THREE.LineBasicMaterial).needsUpdate = true;
    }

    const maxDim = Math.max(xMM, yMM, zMM);
    const cam = cameraRef.current!;
    cam.position.set(maxDim * 1.8, maxDim * 1.2, maxDim * 2.2);
    cam.lookAt(0,0,0);
  }, [xMM, yMM, zMM]);

  useEffect(()=>{
    if (!mountRef.current) return;
    const mount = mountRef.current;
    const scene = new THREE.Scene(); scene.background = null; sceneRef.current = scene;
    const renderer = new THREE.WebGLRenderer({ antialias:true, alpha:true }); rendererRef.current = renderer;
    mount.appendChild(renderer.domElement);
    const camera = new THREE.PerspectiveCamera(40, 1, 0.1, 1000); cameraRef.current = camera;
    const amb = new THREE.AmbientLight(0xffffff, 0.9); scene.add(amb);

    const geo = new THREE.BoxGeometry(xMM, yMM, zMM);
    const mats = faceOrder.map((f)=>new THREE.MeshBasicMaterial({ map: makeFaceTexture(f) }));
    materialsRef.current = mats;
    const cube = new THREE.Mesh(geo, mats); cubeRef.current = cube; scene.add(cube);
    const edges = new THREE.EdgesGeometry(geo);
    const line = new THREE.LineSegments(edges, new THREE.LineBasicMaterial({ color: 0x111111 }));
    cube.add(line); edgesRef.current = line;

    const maxDim = Math.max(xMM, yMM, zMM);
    camera.position.set(maxDim*1.8, maxDim*1.2, maxDim*2.2);
    camera.lookAt(0,0,0);

    function resize() {
      const w = mount.clientWidth || 240, h = mount.clientHeight || 240;
      renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
      renderer.setSize(w, h, false);
      camera.aspect = w / h; camera.updateProjectionMatrix();
    }
    const ro = new ResizeObserver(resize); ro.observe(mount); resize();

    function onDown(e: PointerEvent){ draggingRef.current = true; lastPosRef.current = {x:e.clientX,y:e.clientY}; (mount as HTMLElement).setPointerCapture(e.pointerId); }
    function onMove(e: PointerEvent){ if (!draggingRef.current || !cubeRef.current) return;
      const dx = (e.clientX - lastPosRef.current.x) / 150;
      const dy = (e.clientY - lastPosRef.current.y) / 150;
      cubeRef.current.rotation.y += dx; cubeRef.current.rotation.x += dy;
      lastPosRef.current = {x:e.clientX, y:e.clientY}; }
    function onUp(e: PointerEvent){ draggingRef.current = false; (mount as HTMLElement).releasePointerCapture?.(e.pointerId); }
    mount.addEventListener("pointerdown", onDown);
    mount.addEventListener("pointermove", onMove);
    mount.addEventListener("pointerup", onUp);
    mount.addEventListener("pointerleave", onUp);

    const animate = ()=>{ rafRef.current = requestAnimationFrame(animate); if (cubeRef.current && !draggingRef.current) cubeRef.current.rotation.y += 0.006; renderer.render(scene, camera); };
    animate();

    return ()=>{
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
      mount.removeEventListener("pointerdown", onDown);
      mount.removeEventListener("pointermove", onMove);
      mount.removeEventListener("pointerup", onUp);
      mount.removeEventListener("pointerleave", onUp);
      ro.disconnect(); scene.clear();
      materialsRef.current.forEach(m=>{ m.map?.dispose(); m.dispose(); });
      cubeRef.current?.geometry.dispose();
      renderer.dispose();
      mount.removeChild(renderer.domElement);
      if (edgesRef.current) { edgesRef.current.geometry.dispose(); (edgesRef.current.material as THREE.LineBasicMaterial).dispose(); }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(()=>{ rebuildMaterials(); /* eslint-disable-next-line */ }, [layout.atlasW, layout.atlasH, layout.faceRects, version]);

  return <div ref={mountRef} style={{ width:"100%", height: 240 }} />;
}
