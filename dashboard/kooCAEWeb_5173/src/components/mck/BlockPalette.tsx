import React from 'react';
import { useDrag } from 'react-dnd';
import { Card, Space, Button } from 'antd';

export const ItemTypes = {
  MASS: 'mass',
  SPRING: 'spring',
  DAMPER: 'damper',
  FORCE: 'force',
  FIXED: 'fixed',      // ✅ Fixed 추가
};

const Block: React.FC<{ type: string; label: string; color: string }> = ({
  type,
  label,
  color,
}) => {
  const [{ isDragging }, drag] = useDrag(() => ({
    type,
    item: { type },
    collect: (monitor) => ({
      isDragging: !!monitor.isDragging(),
    }),
  }));

  return (
    <Card
      ref={drag as any}
      style={{
        width: 60,
        height: 60,
        backgroundColor: color,
        color: 'white',
        textAlign: 'center',
        lineHeight: '60px',
        cursor: 'grab',
        opacity: isDragging ? 0.5 : 1,
      }}
      size="small"
    >
      {label}
    </Card>
  );
};

interface BlockPaletteProps {
  onSelectTool: (tool: string | null) => void;
}

const BlockPalette: React.FC<BlockPaletteProps> = ({ onSelectTool }) => {
  return (
    <Space direction="vertical">
      <Block type={ItemTypes.MASS} label="MASS" color="#2980b9" />

      <Button
        style={{ width: 60 }}
        onClick={() => onSelectTool(ItemTypes.SPRING)}
        type="primary"
      >
        SPRING
      </Button>

      <Button
        style={{ width: 60, backgroundColor: '#e67e22', borderColor: '#e67e22' }}
        onClick={() => onSelectTool(ItemTypes.DAMPER)}
        type="primary"
      >
        DAMPER
      </Button>

      <Block type={ItemTypes.FIXED} label="FIXED" color="#2c3e50" /> {/* ✅ 추가 */}
    </Space>
  );
};

export default BlockPalette;
