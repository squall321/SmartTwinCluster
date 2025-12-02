import React from 'react';
import { useDrag } from 'react-dnd';
import { SlurmNode } from '../types';
import { Server, Check } from 'lucide-react';

interface NodeCardProps {
  node: SlurmNode;
  groupColor: string;
  groupId: number;
  isSelected: boolean;
  onToggleSelect: () => void;
  selectedNodeIds: string[];
}

export const NodeCard: React.FC<NodeCardProps> = ({ 
  node, 
  groupColor, 
  groupId,
  isSelected, 
  onToggleSelect,
  selectedNodeIds 
}) => {
  const [{ isDragging }, drag] = useDrag(() => ({
    type: 'node',
    item: () => {
      // 선택된 노드가 있고, 현재 노드가 선택되어 있으면 다중 드래그
      if (isSelected && selectedNodeIds.length > 1) {
        return { nodeIds: selectedNodeIds, groupId };
      }
      // 단일 노드 드래그
      return { nodeId: node.id, groupId };
    },
    collect: (monitor) => ({
      isDragging: monitor.isDragging(),
    }),
  }), [isSelected, selectedNodeIds, node.id, groupId]);

  const stateColors = {
    idle: 'bg-green-100 text-green-800',
    allocated: 'bg-blue-100 text-blue-800',
    mixed: 'bg-yellow-100 text-yellow-800',
    down: 'bg-red-100 text-red-800',
  };

  return (
    <div
      ref={drag}
      className={`
        p-3 rounded-lg border-2 cursor-move transition-all relative
        ${isDragging ? 'opacity-50 scale-95' : 'opacity-100 scale-100'}
        ${isSelected ? 'ring-2 ring-blue-500 bg-blue-50' : 'bg-white'}
        hover:shadow-md
      `}
      style={{ borderColor: isSelected ? '#3b82f6' : groupColor }}
    >
      {/* 선택 체크박스 */}
      <div 
        className="absolute top-2 left-2 cursor-pointer z-10"
        onClick={(e) => {
          e.stopPropagation();
          onToggleSelect();
        }}
      >
        <div className={`
          w-5 h-5 rounded border-2 flex items-center justify-center
          ${isSelected ? 'bg-blue-500 border-blue-500' : 'bg-white border-gray-300'}
          hover:border-blue-500 transition
        `}>
          {isSelected && <Check size={14} className="text-white" />}
        </div>
      </div>

      {/* 다중 선택 배지 */}
      {isSelected && selectedNodeIds.length > 1 && isDragging && (
        <div className="absolute -top-2 -right-2 bg-blue-500 text-white text-xs font-bold rounded-full w-6 h-6 flex items-center justify-center shadow-lg">
          {selectedNodeIds.length}
        </div>
      )}

      <div className="flex items-center gap-2 ml-6">
        <Server size={16} style={{ color: groupColor }} />
        <div className="flex-1">
          <div className="text-sm font-medium">{node.hostname}</div>
          <div className="text-xs text-gray-500">{node.ipAddress}</div>
        </div>
        <span className={`px-2 py-1 rounded text-xs font-medium ${stateColors[node.state]}`}>
          {node.state}
        </span>
      </div>
      <div className="mt-2 ml-6 text-xs text-gray-600">
        {node.cores} cores • {Math.round(node.memory / 1024)}GB
      </div>
    </div>
  );
};
