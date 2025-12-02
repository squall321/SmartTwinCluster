import React, { useRef, useEffect, useState } from 'react';
import { Canvas, useFrame, ThreeElements } from '@react-three/fiber';
import { OrbitControls, Text } from '@react-three/drei';
import * as THREE from 'three';
import { SlurmGroup, SlurmNode } from '../types';
import { Maximize2, Minimize2, RotateCcw } from 'lucide-react';

interface ClusterVisualization3DProps {
  groups: SlurmGroup[];
}

export const ClusterVisualization3D: React.FC<ClusterVisualization3DProps> = ({ groups }) => {
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [selectedNode, setSelectedNode] = useState<SlurmNode | null>(null);
  const [cameraReset, setCameraReset] = useState(0);

  return (
    <div className={`bg-white rounded-lg shadow ${isFullscreen ? 'fixed inset-0 z-50' : 'h-[600px]'}`}>
      {/* 컨트롤 바 */}
      <div className="absolute top-4 right-4 z-10 flex gap-2">
        <button
          onClick={() => setCameraReset(prev => prev + 1)}
          className="p-2 bg-white rounded-lg shadow hover:bg-gray-50"
          title="Reset View"
        >
          <RotateCcw className="w-5 h-5" />
        </button>
        <button
          onClick={() => setIsFullscreen(!isFullscreen)}
          className="p-2 bg-white rounded-lg shadow hover:bg-gray-50"
          title={isFullscreen ? "Exit Fullscreen" : "Fullscreen"}
        >
          {isFullscreen ? <Minimize2 className="w-5 h-5" /> : <Maximize2 className="w-5 h-5" />}
        </button>
      </div>

      {/* 정보 패널 */}
      {selectedNode && (
        <div className="absolute top-4 left-4 z-10 bg-white rounded-lg shadow-lg p-4 max-w-xs">
          <h3 className="font-bold text-lg mb-2">{selectedNode.hostname}</h3>
          <div className="space-y-1 text-sm">
            <div><span className="font-medium">IP:</span> {selectedNode.ipAddress}</div>
            <div><span className="font-medium">Cores:</span> {selectedNode.cores}</div>
            <div><span className="font-medium">Memory:</span> {selectedNode.memory} MB</div>
            <div><span className="font-medium">State:</span> <StateTag state={selectedNode.state} /></div>
          </div>
          <button
            onClick={() => setSelectedNode(null)}
            className="mt-3 w-full px-3 py-1 bg-gray-600 text-white rounded hover:bg-gray-700 text-sm"
          >
            Close
          </button>
        </div>
      )}

      {/* 범례 */}
      <div className="absolute bottom-4 left-4 z-10 bg-white rounded-lg shadow p-4">
        <h4 className="font-bold text-sm mb-2">Node States</h4>
        <div className="space-y-1">
          <LegendItem color="#10b981" label="Idle" />
          <LegendItem color="#3b82f6" label="Allocated" />
          <LegendItem color="#f59e0b" label="Mixed" />
          <LegendItem color="#ef4444" label="Down" />
        </div>
      </div>

      {/* 3D Canvas */}
      <Canvas camera={{ position: [50, 50, 50], fov: 60 }}>
        <ambientLight intensity={0.5} />
        <pointLight position={[100, 100, 100]} intensity={1} />
        <pointLight position={[-100, -100, -100]} intensity={0.5} />
        
        <ClusterScene 
          groups={groups} 
          onNodeClick={setSelectedNode}
          cameraReset={cameraReset}
        />
        
        <OrbitControls 
          enableDamping
          dampingFactor={0.05}
          minDistance={20}
          maxDistance={200}
        />
        <gridHelper args={[200, 20]} />
      </Canvas>

      {/* 통계 오버레이 */}
      <div className="absolute top-4 left-1/2 transform -translate-x-1/2 z-10">
        <div className="bg-white bg-opacity-90 rounded-lg shadow px-6 py-3">
          <div className="flex gap-6 text-sm">
            <div>
              <span className="font-medium">Total Nodes:</span> {groups.reduce((sum, g) => sum + g.nodeCount, 0)}
            </div>
            <div>
              <span className="font-medium">Total Cores:</span> {groups.reduce((sum, g) => sum + g.totalCores, 0).toLocaleString()}
            </div>
            <div>
              <span className="font-medium">Groups:</span> {groups.length}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

// 3D 씬 컴포넌트
interface ClusterSceneProps {
  groups: SlurmGroup[];
  onNodeClick: (node: SlurmNode) => void;
  cameraReset: number;
}

const ClusterScene: React.FC<ClusterSceneProps> = ({ groups, onNodeClick, cameraReset }) => {
  // 그룹별로 노드를 배치
  const groupSpacing = 25;
  const nodeSpacing = 3;
  
  return (
    <group>
      {groups.map((group, groupIndex) => {
        const groupX = (groupIndex % 3) * groupSpacing - groupSpacing;
        const groupZ = Math.floor(groupIndex / 3) * groupSpacing - groupSpacing;
        
        return (
          <group key={group.id} position={[groupX, 0, groupZ]}>
            {/* 그룹 레이블 */}
            <Text
              position={[0, 10, 0]}
              fontSize={2}
              color={group.color}
              anchorX="center"
              anchorY="middle"
            >
              {group.name}
            </Text>
            
            {/* 그룹의 노드들 */}
            {group.nodes.slice(0, 16).map((node, nodeIndex) => {
              const row = Math.floor(nodeIndex / 4);
              const col = nodeIndex % 4;
              const x = col * nodeSpacing - 4.5;
              const z = row * nodeSpacing - 4.5;
              
              return (
                <NodeCube
                  key={node.id}
                  node={node}
                  position={[x, 1, z]}
                  onClick={() => onNodeClick(node)}
                />
              );
            })}
            
            {/* 그룹 바닥 플레이트 */}
            <mesh position={[0, -0.5, 0]} receiveShadow>
              <boxGeometry args={[15, 0.2, 15]} />
              <meshStandardMaterial color={group.color} opacity={0.3} transparent />
            </mesh>
          </group>
        );
      })}
    </group>
  );
};

// 개별 노드 큐브
interface NodeCubeProps {
  node: SlurmNode;
  position: [number, number, number];
  onClick: () => void;
}

const NodeCube: React.FC<NodeCubeProps> = ({ node, position, onClick }) => {
  const meshRef = useRef<THREE.Mesh>(null);
  const [hovered, setHovered] = useState(false);

  // 상태에 따른 색상
  const getColor = () => {
    switch (node.state) {
      case 'idle': return '#10b981';
      case 'allocated': return '#3b82f6';
      case 'mixed': return '#f59e0b';
      case 'down': return '#ef4444';
      default: return '#6b7280';
    }
  };

  // 애니메이션
  useFrame((state) => {
    if (meshRef.current) {
      // 호버 시 약간 위로
      meshRef.current.position.y = position[1] + (hovered ? 0.5 : 0);
      
      // allocated 상태일 때 펄스 효과
      if (node.state === 'allocated') {
        const scale = 1 + Math.sin(state.clock.elapsedTime * 2) * 0.05;
        meshRef.current.scale.set(scale, scale, scale);
      }
    }
  });

  return (
    <mesh
      ref={meshRef}
      position={position}
      onClick={onClick}
      onPointerOver={() => setHovered(true)}
      onPointerOut={() => setHovered(false)}
      castShadow
    >
      <boxGeometry args={[1.5, 1.5, 1.5]} />
      <meshStandardMaterial 
        color={getColor()} 
        emissive={getColor()}
        emissiveIntensity={hovered ? 0.3 : 0.1}
        metalness={0.3}
        roughness={0.4}
      />
    </mesh>
  );
};

// 상태 태그
const StateTag: React.FC<{ state: SlurmNode['state'] }> = ({ state }) => {
  const stateConfig = {
    idle: 'bg-green-100 text-green-800',
    allocated: 'bg-blue-100 text-blue-800',
    mixed: 'bg-amber-100 text-amber-800',
    down: 'bg-red-100 text-red-800',
  };

  return (
    <span className={`px-2 py-0.5 rounded text-xs font-medium ${stateConfig[state]}`}>
      {state.toUpperCase()}
    </span>
  );
};

// 범례 아이템
const LegendItem: React.FC<{ color: string; label: string }> = ({ color, label }) => (
  <div className="flex items-center gap-2 text-xs">
    <div className="w-3 h-3 rounded" style={{ backgroundColor: color }} />
    <span>{label}</span>
  </div>
);
