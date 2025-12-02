import React, { useState, useMemo, useEffect } from 'react';
import { useDrop } from 'react-dnd';
import { SlurmGroup } from '../types';
import { useClusterStore } from '../store/clusterStore';
import { NodeCard } from './NodeCard';
import { Plus, X, Edit2, Check, ChevronDown, ChevronUp, Search, Trash2 } from 'lucide-react';

interface GroupPanelProps {
  group: SlurmGroup;
}

export const GroupPanel: React.FC<GroupPanelProps> = ({ group }) => {
  const { moveNode, moveNodes, addCoreSize, removeCoreSize, updateGroupConfig, removeGroup } = useClusterStore();
  const [isEditing, setIsEditing] = useState(false);
  const [newCoreSize, setNewCoreSize] = useState('');
  const [groupName, setGroupName] = useState(group.name);
  const [groupDescription, setGroupDescription] = useState(group.description);
  const [partitionName, setPartitionName] = useState(group.partitionName);
  const [isExpanded, setIsExpanded] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedNodes, setSelectedNodes] = useState<Set<string>>(new Set());

  // Sync local state when group prop changes
  useEffect(() => {
    setGroupName(group.name);
    setGroupDescription(group.description);
    setPartitionName(group.partitionName);
  }, [group.name, group.description, group.partitionName]);

  const [{ isOver }, drop] = useDrop(() => ({
    accept: 'node',
    drop: (item: { nodeId?: string; nodeIds?: string[]; groupId: number }) => {
      if (item.groupId !== group.id) {
        if (item.nodeIds && item.nodeIds.length > 0) {
          // 다중 노드 이동
          moveNodes(item.nodeIds, item.groupId, group.id);
        } else if (item.nodeId) {
          // 단일 노드 이동
          moveNode(item.nodeId, item.groupId, group.id);
        }
      }
    },
    collect: (monitor) => ({
      isOver: monitor.isOver(),
    }),
  }));

  const handleAddCoreSize = () => {
    const size = parseInt(newCoreSize);
    if (!isNaN(size) && size > 0) {
      addCoreSize(group.id, size);
      setNewCoreSize('');
    }
  };

  const handleSaveEdit = () => {
    updateGroupConfig(group.id, {
      name: groupName,
      description: groupDescription,
      partitionName: partitionName,
      qosName: `${partitionName}_qos`,
    });
    setIsEditing(false);
  };

  // 검색 필터링
  const filteredNodes = useMemo(() => {
    if (!searchTerm) return group.nodes;
    
    const term = searchTerm.toLowerCase();
    return group.nodes.filter(node => 
      node.hostname.toLowerCase().includes(term) ||
      node.ipAddress.includes(term) ||
      node.id.toLowerCase().includes(term)
    );
  }, [group.nodes, searchTerm]);

  // 노드 선택 토글
  const toggleNodeSelection = (nodeId: string) => {
    const newSelection = new Set(selectedNodes);
    if (newSelection.has(nodeId)) {
      newSelection.delete(nodeId);
    } else {
      newSelection.add(nodeId);
    }
    setSelectedNodes(newSelection);
  };

  // 전체 선택/해제
  const toggleSelectAll = () => {
    if (selectedNodes.size === filteredNodes.length) {
      setSelectedNodes(new Set());
    } else {
      setSelectedNodes(new Set(filteredNodes.map(n => n.id)));
    }
  };

  // 선택된 노드 개수
  const selectedCount = selectedNodes.size;

  return (
    <div
      ref={drop}
      className={`
        bg-white rounded-lg shadow-lg transition-all
        ${isOver ? 'ring-4 ring-blue-300 scale-105' : ''}
        ${isExpanded ? 'col-span-1 md:col-span-2 lg:col-span-3' : ''}
      `}
      style={{ borderLeft: `4px solid ${group.color}` }}
    >
      <div className="p-6">
        {/* 헤더 */}
        <div className="mb-4">
          <div className="flex items-center justify-between mb-2">
            {isEditing ? (
              <div className="flex-1">
                <input
                  type="text"
                  value={groupName}
                  onChange={(e) => setGroupName(e.target.value)}
                  placeholder="Group display name"
                  className="w-full text-xl font-bold border-b-2 border-gray-300 focus:border-blue-500 outline-none mb-2"
                />
                <div className="flex items-center gap-2">
                  <span className="text-sm text-gray-600">Partition:</span>
                  <input
                    type="text"
                    value={partitionName}
                    onChange={(e) => setPartitionName(e.target.value)}
                    placeholder="partition_name"
                    className="font-mono text-sm border-b border-gray-300 focus:border-blue-500 outline-none"
                  />
                </div>
              </div>
            ) : (
              <div>
                <h3 className="text-xl font-bold" style={{ color: group.color }}>
                  {group.name}
                </h3>
                <p className="text-sm text-gray-600 mt-1">
                  Partition: <span className="font-mono font-semibold text-blue-600">{group.partitionName}</span>
                </p>
              </div>
            )}
            <div className="flex items-center gap-2">
              <button
                onClick={() => setIsExpanded(!isExpanded)}
                className="p-2 hover:bg-gray-100 rounded"
                title={isExpanded ? "축소" : "전체 보기"}
              >
                {isExpanded ? <ChevronUp size={18} /> : <ChevronDown size={18} />}
              </button>
              <button
                onClick={() => isEditing ? handleSaveEdit() : setIsEditing(true)}
                className="p-2 hover:bg-gray-100 rounded"
                title={isEditing ? "Save" : "Edit"}
              >
                {isEditing ? <Check size={18} /> : <Edit2 size={18} />}
              </button>
              <button
                onClick={() => {
                  if (window.confirm(`Delete "${group.name}"? ${group.nodes.length > 0 ? `Its ${group.nodes.length} nodes will be moved to another group.` : ''}`)) {
                    removeGroup(group.id);
                  }
                }}
                className="p-2 hover:bg-red-100 text-red-600 rounded"
                title="Delete Group"
              >
                <Trash2 size={18} />
              </button>
            </div>
          </div>
          
          {isEditing ? (
            <input
              type="text"
              value={groupDescription}
              onChange={(e) => setGroupDescription(e.target.value)}
              className="w-full text-sm text-gray-600 border-b border-gray-200 focus:border-blue-500 outline-none"
            />
          ) : (
            <p className="text-sm text-gray-600">{group.description}</p>
          )}
        </div>

        {/* 통계 */}
        <div className="grid grid-cols-2 gap-4 mb-4 p-4 bg-gray-50 rounded">
          <div>
            <div className="text-xs text-gray-500">Nodes</div>
            <div className="text-2xl font-bold">{group.nodeCount}</div>
          </div>
          <div>
            <div className="text-xs text-gray-500">Total Cores</div>
            <div className="text-2xl font-bold">{group.totalCores.toLocaleString()}</div>
          </div>
        </div>

        {/* 허용된 코어 크기 */}
        <div className="mb-4">
          <div className="text-sm font-semibold mb-2">Allowed Core Sizes</div>
          <div className="flex flex-wrap gap-2 mb-2">
            {group.allowedCoreSizes.map((size) => (
              <span
                key={size}
                className="inline-flex items-center gap-1 px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm font-medium"
              >
                {size} cores
                <button
                  onClick={() => removeCoreSize(group.id, size)}
                  className="hover:bg-blue-200 rounded-full p-0.5"
                >
                  <X size={14} />
                </button>
              </span>
            ))}
          </div>
          
          {/* 새 코어 크기 추가 */}
          <div className="flex gap-2">
            <input
              type="number"
              value={newCoreSize}
              onChange={(e) => setNewCoreSize(e.target.value)}
              placeholder="Add core size"
              className="flex-1 px-3 py-2 border border-gray-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              onKeyPress={(e) => e.key === 'Enter' && handleAddCoreSize()}
            />
            <button
              onClick={handleAddCoreSize}
              className="px-3 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 transition"
            >
              <Plus size={16} />
            </button>
          </div>
        </div>

        {/* Slurm 설정 정보 */}
        <div className="mb-4 p-3 bg-gray-50 rounded text-xs">
          <div className="font-semibold mb-1">Slurm Configuration:</div>
          <div className="text-gray-600">Partition: {group.partitionName}</div>
          <div className="text-gray-600">QoS: {group.qosName}</div>
        </div>

        {/* 노드 검색 및 선택 */}
        {isExpanded && (
          <div className="mb-4 space-y-2">
            {/* 검색 */}
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400" size={18} />
              <input
                type="text"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                placeholder="Search nodes by hostname, IP, or ID..."
                className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded focus:outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>

            {/* 선택 컨트롤 */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-4">
                <button
                  onClick={toggleSelectAll}
                  className="text-sm text-blue-600 hover:text-blue-800"
                >
                  {selectedNodes.size === filteredNodes.length ? 'Deselect All' : 'Select All'}
                </button>
                {selectedCount > 0 && (
                  <span className="text-sm font-medium text-gray-700">
                    {selectedCount} selected
                  </span>
                )}
              </div>
              {selectedCount > 0 && (
                <button
                  onClick={() => setSelectedNodes(new Set())}
                  className="text-sm text-red-600 hover:text-red-800"
                >
                  Clear Selection
                </button>
              )}
            </div>
          </div>
        )}

        {/* 노드 목록 */}
        <div className={`space-y-2 ${isExpanded ? 'max-h-[600px]' : 'max-h-96'} overflow-y-auto`}>
          <div className="flex items-center justify-between mb-2">
            <div className="text-sm font-semibold">
              Nodes ({filteredNodes.length}{searchTerm && ` of ${group.nodes.length}`})
            </div>
            {!isExpanded && group.nodes.length > 10 && (
              <button
                onClick={() => setIsExpanded(true)}
                className="text-xs text-blue-600 hover:text-blue-800"
              >
                View all →
              </button>
            )}
          </div>

          {filteredNodes.length === 0 ? (
            <div className="text-center py-8 text-gray-500">
              No nodes found
            </div>
          ) : (
            <>
              {(isExpanded ? filteredNodes : filteredNodes.slice(0, 10)).map((node) => (
                <NodeCard
                  key={node.id}
                  node={node}
                  groupColor={group.color}
                  groupId={group.id}
                  isSelected={selectedNodes.has(node.id)}
                  onToggleSelect={() => toggleNodeSelection(node.id)}
                  selectedNodeIds={Array.from(selectedNodes)}
                />
              ))}
              {!isExpanded && filteredNodes.length > 10 && (
                <div className="text-xs text-gray-500 text-center py-2">
                  ... and {filteredNodes.length - 10} more nodes (click "View all" to see)
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
};
